## SDL2 + Pixie-backed canvas implementation.
##
## Pixie draws into an ARGB pixel buffer; SDL2 blits that buffer to the
## window each frame. Anti-aliased shapes and real font rendering on macOS,
## Linux, and Windows.
##
## Note: both pixie (via bumpy) and sdl2 ship a `Rect` type, and my geometry
## module exports one too. So this file uses explicit qualification to keep
## them straight: `geometry.Rect`, `geometry.rect()` for ours; `pixie.rect()`
## for Pixie's; SDL types only via `sdl2.X` aliases.

import ../foundation/render_object
import ../foundation/geometry as geom

when not defined(js):
  import pixie except Rect, rect
  import sdl2
  import std/[tables]

  type
    SdlCanvas* = ref object of Canvas
      ## SDL2 + Pixie canvas. Drawing operations go through Pixie
      ## into `image`; once per frame `present()` swizzles the buffer
      ## into the streaming `texture` and copies it to the window.
      image*:    Image
      ctx*:      Context
      window*:   WindowPtr
      renderer*: RendererPtr
      texture*:  TexturePtr
      fonts*:    Table[string, Font]
      defaultFont*: Font

  proc newSdlCanvas*(window: WindowPtr, renderer: RendererPtr,
                     w, h: int, defaultFontPath: string = ""): SdlCanvas =
    ## Constructs an `SdlCanvas`.
    ##
    ## Inputs:
    ## - `window`, `renderer`: live SDL2 handles obtained via
    ##   `createWindow` / `createRenderer`.
    ## - `w`, `h`: surface size in pixels.
    ## - `defaultFontPath`: absolute path to a TTF to load and
    ##   register under the "system" family. Empty leaves the font
    ##   table empty; `drawText` becomes a no-op.
    ##
    ## Output: a ready-to-use canvas. Pair with `present(canvas)`
    ## once per frame to ship pixels to the SDL window.
    var img = newImage(w, h)
    var c = newContext(img)
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
    let tex = createTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                             SDL_TEXTUREACCESS_STREAMING, cint(w), cint(h))
    SdlCanvas(image: img, ctx: c, window: window, renderer: renderer,
              texture: tex, fonts: fonts, defaultFont: defaultFont,
              size: Size(width: float32(w), height: float32(h)))

  proc resize*(c: SdlCanvas, w, h: int) =
    ## Resizes the canvas to `w x h` pixels. Allocates a new Pixie
    ## image and a new SDL streaming texture. Call when the window
    ## resize event arrives.
    c.image = newImage(w, h)
    c.ctx  = newContext(c.image)
    c.size = Size(width: float32(w), height: float32(h))
    destroyTexture(c.texture)
    c.texture = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                              SDL_TEXTUREACCESS_STREAMING, cint(w), cint(h))

  proc argbToPaint(c: SdlCanvas, v: uint32): Paint =
    let opaqued = c.applyOpacity(v)
    let a = uint8((opaqued shr 24) and 0xFF)
    let r = uint8((opaqued shr 16) and 0xFF)
    let g = uint8((opaqued shr  8) and 0xFF)
    let b = uint8( opaqued         and 0xFF)
    result = newPaint(SolidPaint)
    result.color = rgba(r, g, b, a).color

  method clear*(c: SdlCanvas, color: uint32) =
    c.ctx.fillStyle = argbToPaint(c, color)
    c.ctx.fillRect(pixie.rect(0.0'f32, 0.0'f32, c.size.width, c.size.height))

  method drawRect*(c: SdlCanvas, r: geom.Rect, fill: uint32) =
    c.ctx.fillStyle = argbToPaint(c, fill)
    c.ctx.fillRect(pixie.rect(r.left, r.top, r.width, r.height))

  method drawRRect*(c: SdlCanvas, r: geom.RRect, fill: uint32) =
    c.ctx.fillStyle = argbToPaint(c, fill)
    let pxR = pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height)
    var path = newPath()
    path.roundedRect(pxR, r.tl.x, r.tr.x, r.br.x, r.bl.x)
    c.ctx.fill(path)

  method drawCircle*(c: SdlCanvas, center: geom.Offset, radius: float32, fill: uint32) =
    c.ctx.fillStyle = argbToPaint(c, fill)
    var path = newPath()
    path.circle(center.dx, center.dy, radius)
    c.ctx.fill(path)

  method drawLine*(c: SdlCanvas, p0, p1: geom.Offset, color: uint32, width: float32) =
    c.ctx.strokeStyle = argbToPaint(c, color)
    c.ctx.lineWidth = width
    var path = newPath()
    path.moveTo(p0.dx, p0.dy)
    path.lineTo(p1.dx, p1.dy)
    c.ctx.stroke(path)

  method drawText*(c: SdlCanvas, text: string, pos: geom.Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    var f = c.fonts.getOrDefault(fontFamily, c.defaultFont)
    if f.isNil: return
    f.size = fontSize
    let pt = argbToPaint(c, color)
    f.paints = @[pt]
    # Pixie places typeset text at the top-left of the translate point, NOT
    # the baseline. So we just translate to pos directly.
    c.image.fillText(f, text, translate(vec2(pos.dx, pos.dy)))

  method save*(c: SdlCanvas) = c.ctx.save()
  method restore*(c: SdlCanvas) = c.ctx.restore()
  method translate*(c: SdlCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)
  method scale*(c: SdlCanvas, sx, sy: float32) = c.ctx.scale(sx, sy)
  method rotate*(c: SdlCanvas, radians: float32) = c.ctx.rotate(radians)
  method clipRect*(c: SdlCanvas, r: geom.Rect) =
    var path = newPath()
    pixie.rect(path, pixie.rect(r.left, r.top, r.width, r.height))
    c.ctx.clip(path)

  # --- Sub-canvas (RepaintBoundary backing) ---

  type
    SdlSubCanvas* = ref object of Canvas
      ## Off-screen sub-canvas: a Pixie image with no SDL window.
      ## RepaintBoundary draws into one of these and then composites
      ## the result onto its parent canvas. The parent's
      ## `compositeSubCanvas` does the upload-and-blit so the per-
      ## frame cost of a clean boundary is a single GPU operation.
      image*:        Image
      ctx*:          Context
      fonts*:        Table[string, Font]
      defaultFont*:  Font
      # A persistent GPU texture cache. When the sub-canvas is clean
      # (i.e. its pixels match what's in `texture`) we can skip the
      # CPU-to-GPU upload entirely.
      texture*:      TexturePtr
      textureDirty*: bool

  proc newSdlSubCanvas*(parent: SdlCanvas, w, h: int): SdlSubCanvas =
    ## Builds a child sub-canvas backed by its own Pixie image. The
    ## texture is created lazily on first composite. Fonts are
    ## shared from `parent` so text inside the boundary renders
    ## without each layer carrying its own font table.
    var img = newImage(w, h)
    var c = newContext(img)
    SdlSubCanvas(image: img, ctx: c,
                 fonts: parent.fonts, defaultFont: parent.defaultFont,
                 textureDirty: true,
                 size: Size(width: float32(w), height: float32(h)))

  proc subArgbToPaint(s: SdlSubCanvas, v: uint32): Paint =
    let opaqued = s.applyOpacity(v)
    let a = uint8((opaqued shr 24) and 0xFF)
    let r = uint8((opaqued shr 16) and 0xFF)
    let g = uint8((opaqued shr  8) and 0xFF)
    let b = uint8( opaqued         and 0xFF)
    result = newPaint(SolidPaint)
    result.color = rgba(r, g, b, a).color

  method clear*(s: SdlSubCanvas, color: uint32) =
    s.ctx.fillStyle = subArgbToPaint(s, color)
    s.ctx.fillRect(pixie.rect(0.0'f32, 0.0'f32, s.size.width, s.size.height))
    s.textureDirty = true

  method drawRect*(s: SdlSubCanvas, r: geom.Rect, fill: uint32) =
    s.ctx.fillStyle = subArgbToPaint(s, fill)
    s.ctx.fillRect(pixie.rect(r.left, r.top, r.width, r.height))
    s.textureDirty = true

  method drawRRect*(s: SdlSubCanvas, r: geom.RRect, fill: uint32) =
    s.ctx.fillStyle = subArgbToPaint(s, fill)
    let pxR = pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height)
    var path = newPath()
    path.roundedRect(pxR, r.tl.x, r.tr.x, r.br.x, r.bl.x)
    s.ctx.fill(path)
    s.textureDirty = true

  method drawCircle*(s: SdlSubCanvas, center: geom.Offset, radius: float32, fill: uint32) =
    s.ctx.fillStyle = subArgbToPaint(s, fill)
    var path = newPath()
    path.circle(center.dx, center.dy, radius)
    s.ctx.fill(path)
    s.textureDirty = true

  method drawLine*(s: SdlSubCanvas, p0, p1: geom.Offset, color: uint32, width: float32) =
    s.ctx.strokeStyle = subArgbToPaint(s, color)
    s.ctx.lineWidth = width
    var path = newPath()
    path.moveTo(p0.dx, p0.dy)
    path.lineTo(p1.dx, p1.dy)
    s.ctx.stroke(path)
    s.textureDirty = true

  method drawText*(s: SdlSubCanvas, text: string, pos: geom.Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    var f = s.fonts.getOrDefault(fontFamily, s.defaultFont)
    if f.isNil: return
    f.size = fontSize
    let pt = subArgbToPaint(s, color)
    f.paints = @[pt]
    s.image.fillText(f, text, translate(vec2(pos.dx, pos.dy)))
    s.textureDirty = true

  method save*(s: SdlSubCanvas) = s.ctx.save()
  method restore*(s: SdlSubCanvas) = s.ctx.restore()
  method translate*(s: SdlSubCanvas, dx, dy: float32) = s.ctx.translate(dx, dy)
  method scale*(s: SdlSubCanvas, sx, sy: float32) = s.ctx.scale(sx, sy)
  method rotate*(s: SdlSubCanvas, radians: float32) = s.ctx.rotate(radians)
  method clipRect*(s: SdlSubCanvas, r: geom.Rect) =
    var path = newPath()
    pixie.rect(path, pixie.rect(r.left, r.top, r.width, r.height))
    s.ctx.clip(path)

  # SdlCanvas implementations of the boundary hooks. The big perf win
  # lives here: when the sub-canvas's pixels haven't changed since the
  # last composite (`textureDirty == false`) we skip the CPU-to-GPU
  # upload entirely and only issue the `RenderCopy`. That's what makes
  # the boundary worth having.

  method createSubCanvas*(c: SdlCanvas, w, h: int): Canvas =
    newSdlSubCanvas(c, w, h)

  method compositeSubCanvas*(c: SdlCanvas, sub: Canvas, offset: geom.Offset, size: geom.Size) =
    if not (sub of SdlSubCanvas): return
    let s = SdlSubCanvas(sub)
    let w = s.image.width
    let h = s.image.height
    # Lazily create / refresh the texture.
    if s.texture.isNil:
      s.texture = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                                SDL_TEXTUREACCESS_STREAMING, cint(w), cint(h))
      discard setTextureBlendMode(s.texture, BlendMode_Blend)
      s.textureDirty = true
    if s.textureDirty:
      var pixels: pointer
      var pitch: cint
      discard lockTexture(s.texture, nil, addr pixels, addr pitch)
      # Same RGBA -> ARGB swizzle as `present`. Done once per dirty
      # frame, then cached.
      let src = cast[ptr UncheckedArray[uint32]](addr s.image.data[0])
      let dst = cast[ptr UncheckedArray[uint32]](pixels)
      for i in 0 ..< w * h:
        let px = src[i]
        let r2 = (px shr 0)  and 0xFF
        let g2 = (px shr 8)  and 0xFF
        let b2 = (px shr 16) and 0xFF
        let a2 = (px shr 24) and 0xFF
        dst[i] = (a2 shl 24) or (r2 shl 16) or (g2 shl 8) or b2
      unlockTexture(s.texture)
      s.textureDirty = false
    # Composite to the streaming texture that the renderer will copy
    # to the window. Setting render target to `c.texture` makes this
    # a texture-to-texture GPU blit; SDL2 picks the accelerated path
    # on macOS (Metal), Windows (D3D), and Linux (OpenGL).
    let alpha = uint8(currentOpacity(c) * 255.0'f32)
    discard setTextureAlphaMod(s.texture, alpha)
    var dstRect = sdl2.rect(cint(offset.dx), cint(offset.dy),
                            cint(size.width), cint(size.height))
    discard setRenderTarget(c.renderer, c.texture)
    discard copy(c.renderer, s.texture, nil, addr dstRect)
    discard setRenderTarget(c.renderer, nil)
    # We also have to keep the Pixie image (CPU side) in sync so that
    # screenshot tests, hit testing visuals, etc. see consistent
    # output. Composite the source image into the parent image at the
    # given offset. Cheap for typical layer sizes; can be skipped in
    # release if needed.
    let ix = int(offset.dx)
    let iy = int(offset.dy)
    let parentW = c.image.width
    let parentH = c.image.height
    let psrc = cast[ptr UncheckedArray[uint32]](addr s.image.data[0])
    let pdst = cast[ptr UncheckedArray[uint32]](addr c.image.data[0])
    for y in 0 ..< h:
      let dy = iy + y
      if dy < 0 or dy >= parentH: continue
      for x in 0 ..< w:
        let dx = ix + x
        if dx < 0 or dx >= parentW: continue
        let sPx = psrc[y * w + x]
        let sA = (sPx shr 24) and 0xFF
        if sA == 0: continue
        if sA == 0xFF:
          pdst[dy * parentW + dx] = sPx
        else:
          # Standard "source-over" compositing on RGBA8 channels.
          let dPx = pdst[dy * parentW + dx]
          let sR = (sPx shr 0)  and 0xFF
          let sG = (sPx shr 8)  and 0xFF
          let sB = (sPx shr 16) and 0xFF
          let dR = (dPx shr 0)  and 0xFF
          let dG = (dPx shr 8)  and 0xFF
          let dB = (dPx shr 16) and 0xFF
          let dA = (dPx shr 24) and 0xFF
          let invA = (255 - sA)
          let outR = ((sR * sA) + (dR * invA)) div 255
          let outG = ((sG * sA) + (dG * invA)) div 255
          let outB = ((sB * sA) + (dB * invA)) div 255
          let outA = sA + ((dA * invA) div 255)
          pdst[dy * parentW + dx] = (outA shl 24) or (outB shl 16) or (outG shl 8) or outR

  proc present*(c: SdlCanvas) =
    ## Push the Pixie image into the SDL streaming texture, copy the
    ## texture to the renderer's window, and call `SDL_RenderPresent`.
    ## Call once per rendered frame after all draw calls have run.
    ## Performs a per-pixel RGBA->ARGB swizzle in the process.
    var pixels: pointer
    var pitch: cint
    discard lockTexture(c.texture, nil, addr pixels, addr pitch)
    let w = c.image.width
    let h = c.image.height
    # Pixie's buffer is RGBA8888 (R in low byte); SDL_PIXELFORMAT_ARGB8888 is
    # ARGB in memory. We swizzle in place.
    let src = cast[ptr UncheckedArray[uint32]](addr c.image.data[0])
    let dst = cast[ptr UncheckedArray[uint32]](pixels)
    for i in 0 ..< w * h:
      let px = src[i]
      let r = (px shr 0)  and 0xFF
      let g = (px shr 8)  and 0xFF
      let b = (px shr 16) and 0xFF
      let a = (px shr 24) and 0xFF
      dst[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
    unlockTexture(c.texture)
    discard copy(c.renderer, c.texture, nil, nil)
    present(c.renderer)
