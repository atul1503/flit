## GPU-first canvas backend. Uses SDL2's hardware-accelerated renderer
## (Metal on macOS, Direct3D on Windows, OpenGL elsewhere) for every
## primitive that maps directly to it:
##
## - `clear`        -> `SDL_RenderClear`
## - `drawRect`     -> `SDL_RenderFillRect`
## - `drawLine`     -> `SDL_RenderDrawLine`
## - `compositeSubCanvas` -> `SDL_RenderCopy` (shared with `SdlCanvas`)
##
## Primitives that aren't direct renderer ops (rounded rectangles,
## circles, anti-aliased shapes, text) are rasterized once with Pixie
## into a cached `SDL_Texture` keyed by `(kind, dims, color)` and then
## drawn on every subsequent frame via `SDL_RenderCopy`. After the
## first frame, even those primitives are effectively zero-CPU.
##
## When `SdlCanvas` is the "Pixie-on-CPU then upload" path,
## `GpuCanvas` is the "SDL renderer is the truth" path. Both expose
## the same `Canvas` surface; the platform runner picks one. Pick
## `GpuCanvas` for UIs whose pixels mostly come from solid rects,
## images, and cached layers. Pick `SdlCanvas` when you need Pixie's
## high-quality anti-aliased path rendering for every primitive.

import std/[tables, hashes]
import ../foundation/render_object
import ../foundation/geometry as geom
import ./glyph_atlas

when not defined(js):
  import pixie except Rect, rect
  import sdl2

  type
    ShapeKey = tuple
      kind: int       # 0 = rrect, 1 = circle
      w, h: int       # bounding box in pixels
      radius: int     # rounded corner radius (or circle radius)
      color: uint32

    GpuCanvas* = ref object of Canvas
      ## SDL_Renderer-based canvas. Direct hardware draws for rects /
      ## lines / clears; cached textures (also drawn on the renderer)
      ## for paths and shapes that the SDL renderer can't express
      ## natively.
      window*:    WindowPtr
      renderer*:  RendererPtr
      fonts*:     Table[string, Font]
      defaultFont*: Font
      # Per-shape texture cache. Hot on the first frame after layout,
      # then read-only for stable UIs.
      shapeCache*: Table[ShapeKey, TexturePtr]
      # Glyph atlas for text. One cache entry per
      # `(text, fontHash, size, color)`; subsequent draws of the
      # same label become single texture copies.
      atlas*: GlyphAtlas
      # The current translation accumulated from save/translate. The
      # SDL renderer's own clip rect is tracked separately. Rotation
      # and scale are NOT supported in this fast path; widgets that
      # need them (Transform) should wrap themselves in a
      # RepaintBoundary so the rotated render lands in a sub-canvas
      # which then composites cleanly.
      tx*, ty*:   float32
      stateStack*: seq[(float32, float32)]

  proc newGpuCanvas*(window: WindowPtr, renderer: RendererPtr,
                     w, h: int, defaultFontPath: string = ""): GpuCanvas =
    ## Builds a `GpuCanvas`. The caller owns the `window` and
    ## `renderer`; the canvas only uses them. Fonts may be loaded
    ## lazily by the glyph atlas.
    ##
    ## Inputs:
    ## - `window`, `renderer`: live SDL2 handles.
    ## - `w`, `h`: surface size.
    ## - `defaultFontPath`: optional TTF path. Empty leaves text
    ##   rendering off until a glyph atlas is installed.
    ##
    ## Output: a `GpuCanvas` ready to be painted onto.
    var defaultFont: Font
    var fonts = initTable[string, Font]()
    if defaultFontPath.len > 0:
      try:
        let f = readFont(defaultFontPath)
        f.size = 14
        defaultFont = f
        fonts["system"] = f
      except CatchableError:
        defaultFont = nil
    let atlas = newGlyphAtlas(renderer)
    if defaultFontPath.len > 0:
      atlas.registerHbFont(hash("system"), defaultFontPath)
    GpuCanvas(window: window, renderer: renderer,
              fonts: fonts, defaultFont: defaultFont,
              shapeCache: initTable[ShapeKey, TexturePtr](),
              atlas: atlas,
              size: Size(width: float32(w), height: float32(h)))

  proc unpackArgb(c: GpuCanvas, color: uint32): tuple[r, g, b, a: uint8] =
    let opaqued = c.applyOpacity(color)
    ( uint8((opaqued shr 16) and 0xFF),
      uint8((opaqued shr  8) and 0xFF),
      uint8( opaqued         and 0xFF),
      uint8((opaqued shr 24) and 0xFF))

  method clear*(c: GpuCanvas, color: uint32) =
    let p = c.unpackArgb(color)
    discard setDrawColor(c.renderer, p.r, p.g, p.b, p.a)
    discard clear(c.renderer)

  method drawRect*(c: GpuCanvas, r: geom.Rect, fill: uint32) =
    let p = c.unpackArgb(fill)
    discard setDrawColor(c.renderer, p.r, p.g, p.b, p.a)
    var rect = sdl2.rect(cint(r.left + c.tx), cint(r.top + c.ty),
                         cint(r.width), cint(r.height))
    discard fillRect(c.renderer, addr rect)

  method drawLine*(c: GpuCanvas, p0, p1: geom.Offset, color: uint32, width: float32) =
    let p = c.unpackArgb(color)
    discard setDrawColor(c.renderer, p.r, p.g, p.b, p.a)
    discard drawLine(c.renderer,
                     cint(p0.dx + c.tx), cint(p0.dy + c.ty),
                     cint(p1.dx + c.tx), cint(p1.dy + c.ty))

  proc rasterizeRRect(c: GpuCanvas, w, h, radius: int, color: uint32): TexturePtr =
    ## Build a small Pixie image of the rounded rect, upload as
    ## an SDL_Texture, cache by `(w, h, radius, color)`. After the
    ## first frame, draws hit the cache and never re-rasterize.
    var img = newImage(w, h)
    var ctx = newContext(img)
    var paint = newPaint(SolidPaint)
    let p = c.unpackArgb(color)
    paint.color = rgba(p.r, p.g, p.b, p.a).color
    ctx.fillStyle = paint
    var path = newPath()
    let rf = float32(radius)
    path.roundedRect(pixie.rect(0.0'f32, 0.0'f32, float32(w), float32(h)),
                     rf, rf, rf, rf)
    ctx.fill(path)
    let tex = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                            SDL_TEXTUREACCESS_STATIC, cint(w), cint(h))
    discard setTextureBlendMode(tex, BlendMode_Blend)
    # Pixie's pixels are RGBA8 (R low byte); ARGB8888 needs swizzle.
    var buf = newSeq[uint32](w * h)
    let src = cast[ptr UncheckedArray[uint32]](addr img.data[0])
    for i in 0 ..< w * h:
      let px = src[i]
      let r2 = (px shr 0)  and 0xFF
      let g2 = (px shr 8)  and 0xFF
      let b2 = (px shr 16) and 0xFF
      let a2 = (px shr 24) and 0xFF
      buf[i] = (a2 shl 24) or (r2 shl 16) or (g2 shl 8) or b2
    discard updateTexture(tex, nil, addr buf[0], cint(w * 4))
    tex

  method drawRRect*(c: GpuCanvas, r: geom.RRect, fill: uint32) =
    let w = int(r.rect.width)
    let h = int(r.rect.height)
    if w <= 0 or h <= 0: return
    let radius = int(max(r.tl.x, max(r.tr.x, max(r.bl.x, r.br.x))))
    let key = (0, w, h, radius, c.applyOpacity(fill))
    var tex: TexturePtr
    if c.shapeCache.hasKey(key):
      tex = c.shapeCache[key]
    else:
      tex = rasterizeRRect(c, w, h, radius, fill)
      c.shapeCache[key] = tex
    var dst = sdl2.rect(cint(r.rect.left + c.tx), cint(r.rect.top + c.ty),
                        cint(w), cint(h))
    discard copy(c.renderer, tex, nil, addr dst)

  proc rasterizeCircle(c: GpuCanvas, radius: int, color: uint32): TexturePtr =
    let d = radius * 2
    var img = newImage(d, d)
    var ctx = newContext(img)
    var paint = newPaint(SolidPaint)
    let p = c.unpackArgb(color)
    paint.color = rgba(p.r, p.g, p.b, p.a).color
    ctx.fillStyle = paint
    var path = newPath()
    path.circle(float32(radius), float32(radius), float32(radius))
    ctx.fill(path)
    let tex = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                            SDL_TEXTUREACCESS_STATIC, cint(d), cint(d))
    discard setTextureBlendMode(tex, BlendMode_Blend)
    var buf = newSeq[uint32](d * d)
    let src = cast[ptr UncheckedArray[uint32]](addr img.data[0])
    for i in 0 ..< d * d:
      let px = src[i]
      let r2 = (px shr 0)  and 0xFF
      let g2 = (px shr 8)  and 0xFF
      let b2 = (px shr 16) and 0xFF
      let a2 = (px shr 24) and 0xFF
      buf[i] = (a2 shl 24) or (r2 shl 16) or (g2 shl 8) or b2
    discard updateTexture(tex, nil, addr buf[0], cint(d * 4))
    tex

  method drawCircle*(c: GpuCanvas, center: geom.Offset, radius: float32, fill: uint32) =
    let ri = int(radius)
    if ri <= 0: return
    let key = (1, ri * 2, ri * 2, ri, c.applyOpacity(fill))
    var tex: TexturePtr
    if c.shapeCache.hasKey(key):
      tex = c.shapeCache[key]
    else:
      tex = rasterizeCircle(c, ri, fill)
      c.shapeCache[key] = tex
    var dst = sdl2.rect(cint(center.dx - radius + c.tx),
                        cint(center.dy - radius + c.ty),
                        cint(ri * 2), cint(ri * 2))
    discard copy(c.renderer, tex, nil, addr dst)

  method drawText*(c: GpuCanvas, text: string, pos: geom.Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    ## Goes through the glyph atlas: first draw of a given
    ## `(text, fontHash, size, color)` rasterizes once, subsequent
    ## draws are a single GPU `RenderCopy` of the cached texture.
    var f = c.fonts.getOrDefault(fontFamily, c.defaultFont)
    if f.isNil: return
    let fontHash = hash(fontFamily)
    let entry = c.atlas.getOrRasterize(f, text, fontSize,
                                       c.applyOpacity(color), fontHash)
    var dst = sdl2.rect(cint(pos.dx + c.tx), cint(pos.dy + c.ty),
                        cint(entry.width), cint(entry.height))
    discard copy(c.renderer, entry.texture, nil, addr dst)

  method save*(c: GpuCanvas) =
    c.stateStack.add((c.tx, c.ty))

  method restore*(c: GpuCanvas) =
    if c.stateStack.len > 0:
      let s = c.stateStack.pop()
      c.tx = s[0]
      c.ty = s[1]

  method translate*(c: GpuCanvas, dx, dy: float32) =
    c.tx += dx
    c.ty += dy

  method scale*(c: GpuCanvas, sx, sy: float32) = discard
    ## Not supported on the GPU fast path. Widgets that need scaling
    ## should wrap themselves in a `repaintBoundary` so the scaled
    ## render is captured into a sub-canvas, which then composites
    ## back with a cleanly scaled destination rect.

  method rotate*(c: GpuCanvas, radians: float32) = discard
    ## Not supported on the GPU fast path. Wrap rotating subtrees in
    ## `repaintBoundary` for the same reason as `scale`.

  method clipRect*(c: GpuCanvas, r: geom.Rect) =
    var clip = sdl2.rect(cint(r.left + c.tx), cint(r.top + c.ty),
                         cint(r.width), cint(r.height))
    discard setClipRect(c.renderer, addr clip)

  # --- Sub-canvas support: identical wiring to SdlCanvas so the
  # cached RepaintBoundary layer path works the same way. The
  # texture upload + RenderCopy path is the actual GPU compositor.

  type
    GpuSubCanvas* = ref object of Canvas
      ## Off-screen surface for a `RepaintBoundary` under a
      ## `GpuCanvas`. Backed by a render-target texture; drawing
      ## inside it issues GPU primitives directly into the target.
      parent*:   GpuCanvas
      texture*:  TexturePtr

  proc newGpuSubCanvas(parent: GpuCanvas, w, h: int): GpuSubCanvas =
    let tex = createTexture(parent.renderer, SDL_PIXELFORMAT_ARGB8888,
                            SDL_TEXTUREACCESS_TARGET, cint(w), cint(h))
    discard setTextureBlendMode(tex, BlendMode_Blend)
    GpuSubCanvas(parent: parent, texture: tex,
                 size: Size(width: float32(w), height: float32(h)))

  template withTarget(c: GpuCanvas, tex: TexturePtr, body: untyped) =
    let prev = getRenderTarget(c.renderer)
    discard setRenderTarget(c.renderer, tex)
    body
    discard setRenderTarget(c.renderer, prev)

  method clear*(s: GpuSubCanvas, color: uint32) =
    let p = s.parent.unpackArgb(color)
    withTarget(s.parent, s.texture):
      discard setDrawColor(s.parent.renderer, p.r, p.g, p.b, p.a)
      discard clear(s.parent.renderer)

  method drawRect*(s: GpuSubCanvas, r: geom.Rect, fill: uint32) =
    let p = s.parent.unpackArgb(fill)
    var rect = sdl2.rect(cint(r.left), cint(r.top), cint(r.width), cint(r.height))
    withTarget(s.parent, s.texture):
      discard setDrawColor(s.parent.renderer, p.r, p.g, p.b, p.a)
      discard fillRect(s.parent.renderer, addr rect)

  method drawLine*(s: GpuSubCanvas, p0, p1: geom.Offset, color: uint32, width: float32) =
    let p = s.parent.unpackArgb(color)
    withTarget(s.parent, s.texture):
      discard setDrawColor(s.parent.renderer, p.r, p.g, p.b, p.a)
      discard drawLine(s.parent.renderer,
                       cint(p0.dx), cint(p0.dy),
                       cint(p1.dx), cint(p1.dy))

  method drawRRect*(s: GpuSubCanvas, r: geom.RRect, fill: uint32) =
    # Delegate to parent's shape cache.
    let w = int(r.rect.width)
    let h = int(r.rect.height)
    if w <= 0 or h <= 0: return
    let radius = int(max(r.tl.x, max(r.tr.x, max(r.bl.x, r.br.x))))
    let key = (0, w, h, radius, s.parent.applyOpacity(fill))
    var tex: TexturePtr
    if s.parent.shapeCache.hasKey(key):
      tex = s.parent.shapeCache[key]
    else:
      tex = rasterizeRRect(s.parent, w, h, radius, fill)
      s.parent.shapeCache[key] = tex
    var dst = sdl2.rect(cint(r.rect.left), cint(r.rect.top), cint(w), cint(h))
    withTarget(s.parent, s.texture):
      discard copy(s.parent.renderer, tex, nil, addr dst)

  method drawCircle*(s: GpuSubCanvas, center: geom.Offset, radius: float32, fill: uint32) =
    let ri = int(radius)
    if ri <= 0: return
    let key = (1, ri * 2, ri * 2, ri, s.parent.applyOpacity(fill))
    var tex: TexturePtr
    if s.parent.shapeCache.hasKey(key):
      tex = s.parent.shapeCache[key]
    else:
      tex = rasterizeCircle(s.parent, ri, fill)
      s.parent.shapeCache[key] = tex
    var dst = sdl2.rect(cint(center.dx - radius), cint(center.dy - radius),
                        cint(ri * 2), cint(ri * 2))
    withTarget(s.parent, s.texture):
      discard copy(s.parent.renderer, tex, nil, addr dst)

  method drawText*(s: GpuSubCanvas, text: string, pos: geom.Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    ## Routes through the parent canvas's glyph atlas.
    var f = s.parent.fonts.getOrDefault(fontFamily, s.parent.defaultFont)
    if f.isNil: return
    let fontHash = hash(fontFamily)
    let entry = s.parent.atlas.getOrRasterize(f, text, fontSize,
                                              s.parent.applyOpacity(color),
                                              fontHash)
    var dst = sdl2.rect(cint(pos.dx), cint(pos.dy),
                        cint(entry.width), cint(entry.height))
    withTarget(s.parent, s.texture):
      discard copy(s.parent.renderer, entry.texture, nil, addr dst)

  method save*(s: GpuSubCanvas) = discard
  method restore*(s: GpuSubCanvas) = discard
  method translate*(s: GpuSubCanvas, dx, dy: float32) = discard
  method scale*(s: GpuSubCanvas, sx, sy: float32) = discard
  method rotate*(s: GpuSubCanvas, radians: float32) = discard
  method clipRect*(s: GpuSubCanvas, r: geom.Rect) = discard

  method createSubCanvas*(c: GpuCanvas, w, h: int): Canvas =
    newGpuSubCanvas(c, w, h)

  method compositeSubCanvas*(c: GpuCanvas, sub: Canvas, offset: geom.Offset, size: geom.Size) =
    if not (sub of GpuSubCanvas): return
    let s = GpuSubCanvas(sub)
    let alpha = uint8(currentOpacity(c) * 255.0'f32)
    discard setTextureAlphaMod(s.texture, alpha)
    var dst = sdl2.rect(cint(offset.dx + c.tx), cint(offset.dy + c.ty),
                        cint(size.width), cint(size.height))
    discard copy(c.renderer, s.texture, nil, addr dst)

  proc present*(c: GpuCanvas) =
    ## Flushes the renderer to the window. Call once per frame after
    ## all draw calls have run. No CPU upload step; everything is
    ## already on the GPU.
    present(c.renderer)
