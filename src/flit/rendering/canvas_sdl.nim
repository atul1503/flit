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
  import std/[tables, hashes, os]

  # Text rasterization cache for the SDL backend. Same shape as the
  # embedded canvas's cache: Pixie's `fillText` is by far the
  # heaviest paint op (typeset + glyph raster); for stable strings
  # (item labels, button captions) we rasterize once into a small
  # image and `draw` that image on every subsequent call. Cache key
  # is (text, family, fontSize-as-px, color). Per-process, shared
  # across all SdlCanvas instances.

  type
    SdlTextCacheKey = object
      text:   string
      family: string
      size:   uint16
      color:  uint32

    SdlTextCacheEntry = object
      image: pixie.Image
      width, height: int

  proc hash(k: SdlTextCacheKey): Hash =
    var h: Hash = 0
    h = h !& hash(k.text)
    h = h !& hash(k.family)
    h = h !& int(k.size)
    h = h !& int(k.color)
    !$h

  proc `==`(a, b: SdlTextCacheKey): bool =
    a.text == b.text and a.family == b.family and
      a.size == b.size and a.color == b.color

  var sdlTextCache* {.threadvar.}: Table[SdlTextCacheKey, SdlTextCacheEntry]
  var sdlTextCacheLimit* = 2048
    ## Maximum number of rasterized text bitmaps to keep. Eviction
    ## is "drop everything when full" today; LRU is a follow-up.

  var sdlTextCacheHits*  {.threadvar.}: int
  var sdlTextCacheMisses* {.threadvar.}: int
    ## Per-thread counters; useful for confirming the cache actually
    ## hits in interactive workloads.

  # Rounded-rect bitmap cache. Pixie's path fill is the second most
  # expensive paint op after fillText; for repeated shapes (button
  # backgrounds, card containers, the search box) we rasterize each
  # (size + radii + fill) tuple once and blit thereafter. Key
  # quantizes the width/height/radii to 1px so near-identical
  # shapes share a single bitmap.

  type
    SdlRRectKey = object
      w:     uint16
      h:     uint16
      tl, tr, br, bl: uint16
      color: uint32

    SdlRRectEntry = object
      image: pixie.Image

  proc hash(k: SdlRRectKey): Hash =
    var h: Hash = 0
    h = h !& int(k.w)
    h = h !& int(k.h)
    h = h !& int(k.tl)
    h = h !& int(k.tr)
    h = h !& int(k.br)
    h = h !& int(k.bl)
    h = h !& int(k.color)
    !$h

  proc `==`(a, b: SdlRRectKey): bool =
    a.w == b.w and a.h == b.h and
      a.tl == b.tl and a.tr == b.tr and
      a.br == b.br and a.bl == b.bl and
      a.color == b.color

  var sdlRRectCache* {.threadvar.}: Table[SdlRRectKey, SdlRRectEntry]
  var sdlRRectCacheLimit* = 512
    ## Cap on number of cached rrect bitmaps. Clears wholesale on
    ## overflow.
  var sdlRRectCacheHits*   {.threadvar.}: int
  var sdlRRectCacheMisses* {.threadvar.}: int

  proc clearSdlRRectCache*() =
    sdlRRectCache.clear()

  proc clearSdlTextCache*() =
    ## Drops every rasterized text image from the SDL canvas cache.
    sdlTextCache.clear()

  type
    SdlCanvas* = ref object of Canvas
      ## SDL2 + Pixie canvas. Drawing operations go through Pixie
      ## into `image`; once per frame `present()` swizzles the buffer
      ## into the streaming `texture` and copies it to the window.
      ##
      ## HiDPI: on retina displays SDL allocates a 2x drawable
      ## buffer when `SDL_WINDOW_ALLOW_HIGHDPI` is set. We size the
      ## Pixie image at the PHYSICAL drawable size and pre-apply
      ## `scale(dpr)` to the Context, so render-object paint methods
      ## can keep using LOGICAL coordinates while text and shapes
      ## rasterize at full native pixel density (sharp on retina).
      image*:    Image
      ctx*:      Context
      window*:   WindowPtr
      renderer*: RendererPtr
      texture*:  TexturePtr
      fonts*:    Table[string, Font]
      defaultFont*: Font
      dpr*:      float32       ## device pixel ratio (1.0 on non-retina; 2.0 on retina)

  proc applyDprBaseTransform(c: SdlCanvas) =
    ## Re-applies the dpr scale to the context. Pixie's Context
    ## resets its transform on every `save()` / `restore()` pair, so
    ## we call this after each top-level clear so the per-frame
    ## paint pass starts in the correct coordinate space.
    c.ctx.resetTransform()
    if c.dpr != 1.0'f32:
      c.ctx.scale(c.dpr, c.dpr)

  proc newSdlCanvas*(window: WindowPtr, renderer: RendererPtr,
                     w, h: int, defaultFontPath: string = "",
                     dpr: float32 = 1.0'f32): SdlCanvas =
    ## Constructs an `SdlCanvas`.
    ##
    ## Inputs:
    ## - `window`, `renderer`: live SDL2 handles obtained via
    ##   `createWindow` / `createRenderer`.
    ## - `w`, `h`: LOGICAL surface size in pixels (what layout sees).
    ## - `defaultFontPath`: absolute path to a TTF to load and
    ##   register under the "system" family. Empty leaves the font
    ##   table empty; `drawText` becomes a no-op.
    ## - `dpr`: device pixel ratio. Pass the renderer's drawable
    ##   width divided by `w` (use `getRendererOutputSize`). Default
    ##   1.0 keeps the legacy non-HiDPI behavior.
    ##
    ## Output: a ready-to-use canvas. Pair with `present(canvas)`
    ## once per frame to ship pixels to the SDL window.
    let pw = max(1, int(float32(w) * dpr + 0.5'f32))
    let ph = max(1, int(float32(h) * dpr + 0.5'f32))
    var img = newImage(pw, ph)
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
                             SDL_TEXTUREACCESS_STREAMING, cint(pw), cint(ph))
    result = SdlCanvas(image: img, ctx: c, window: window, renderer: renderer,
              texture: tex, fonts: fonts, defaultFont: defaultFont,
              dpr: dpr,
              size: Size(width: float32(w), height: float32(h)))
    applyDprBaseTransform(result)

  proc resize*(c: SdlCanvas, w, h: int) =
    ## Resizes the canvas to `w x h` LOGICAL pixels. Reallocates the
    ## Pixie image at the physical size implied by `dpr`. Call when
    ## the window resize event arrives.
    let pw = max(1, int(float32(w) * c.dpr + 0.5'f32))
    let ph = max(1, int(float32(h) * c.dpr + 0.5'f32))
    c.image = newImage(pw, ph)
    c.ctx  = newContext(c.image)
    c.size = Size(width: float32(w), height: float32(h))
    destroyTexture(c.texture)
    c.texture = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                              SDL_TEXTUREACCESS_STREAMING, cint(pw), cint(ph))
    applyDprBaseTransform(c)

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
    let opaqued = c.applyOpacity(fill)
    let w = int(r.rect.width + 0.5'f32)
    let h = int(r.rect.height + 0.5'f32)
    # Tiny shapes or fully-rectangular (no rounded corners) fall
    # through to direct fillRect - cheaper than building a path.
    if w <= 0 or h <= 0: return
    if r.tl.x < 0.5 and r.tr.x < 0.5 and r.br.x < 0.5 and r.bl.x < 0.5:
      c.ctx.fillStyle = argbToPaint(c, fill)
      c.ctx.fillRect(pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height))
      return
    # Cache at PHYSICAL resolution so retina displays get sharp
    # rounded corners. Key includes dpr because the same logical
    # shape needs distinct bitmaps at different densities.
    let dpr = c.dpr
    let pw = max(1, int(float32(w) * dpr + 0.5'f32))
    let ph = max(1, int(float32(h) * dpr + 0.5'f32))
    let key = SdlRRectKey(
      w: uint16(pw), h: uint16(ph),
      tl: uint16(r.tl.x * dpr + 0.5'f32), tr: uint16(r.tr.x * dpr + 0.5'f32),
      br: uint16(r.br.x * dpr + 0.5'f32), bl: uint16(r.bl.x * dpr + 0.5'f32),
      color: opaqued)
    var entry: SdlRRectEntry
    if sdlRRectCache.hasKey(key):
      entry = sdlRRectCache[key]
      inc sdlRRectCacheHits
    else:
      inc sdlRRectCacheMisses
      let img = pixie.newImage(pw, ph)
      var ctx = newContext(img)
      let a = uint8((opaqued shr 24) and 0xFF)
      let red = uint8((opaqued shr 16) and 0xFF)
      let g = uint8((opaqued shr  8) and 0xFF)
      let b = uint8( opaqued         and 0xFF)
      var pt = newPaint(SolidPaint)
      pt.color = rgba(red, g, b, a).color
      ctx.fillStyle = pt
      var path = newPath()
      path.roundedRect(pixie.rect(0.0'f32, 0.0'f32, float32(pw), float32(ph)),
                       r.tl.x * dpr, r.tr.x * dpr,
                       r.br.x * dpr, r.bl.x * dpr)
      ctx.fill(path)
      entry = SdlRRectEntry(image: img)
      if sdlRRectCache.len >= sdlRRectCacheLimit:
        sdlRRectCache.clear()
      sdlRRectCache[key] = entry
    # The cached image is at physical scale. ctx.getTransform()
    # contains scale(dpr); composing with scale(1/dpr) undoes that
    # for the pre-scaled bitmap so it lands at logical size.
    let m =
      if dpr == 1.0'f32:
        c.ctx.getTransform() * translate(vec2(r.rect.left, r.rect.top))
      else:
        c.ctx.getTransform() * translate(vec2(r.rect.left, r.rect.top)) *
          pixie.scale(vec2(1.0'f32 / dpr, 1.0'f32 / dpr))
    c.image.draw(entry.image, m)

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

  method fillPolygon*(c: SdlCanvas, points: seq[geom.Offset], fill: uint32) =
    if points.len < 3: return
    c.ctx.fillStyle = argbToPaint(c, fill)
    var path = newPath()
    path.moveTo(points[0].dx, points[0].dy)
    for i in 1 ..< points.len:
      path.lineTo(points[i].dx, points[i].dy)
    path.closePath()
    c.ctx.fill(path)

  method drawText*(c: SdlCanvas, text: string, pos: geom.Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    if text.len == 0: return
    var f = c.fonts.getOrDefault(fontFamily, c.defaultFont)
    if f.isNil: return
    # Bake opacity into the cache key so semi-transparent and opaque
    # variants of the same string keep separate bitmaps.
    let opaqued = c.applyOpacity(color)
    let dpr = c.dpr
    # Rasterize the glyph image at the PHYSICAL font size so retina
    # text is sharp. Cache key includes dpr so the same logical size
    # cached at 1x doesn't get reused at 2x.
    let physSize = fontSize * dpr
    let key = SdlTextCacheKey(
      text: text, family: fontFamily,
      size: uint16(physSize + 0.5'f32), color: opaqued)
    var entry: SdlTextCacheEntry
    if sdlTextCache.hasKey(key):
      entry = sdlTextCache[key]
      inc sdlTextCacheHits
    else:
      inc sdlTextCacheMisses
      # cache miss; build the cached image at physical scale.
      f.size = physSize
      let bounds = pixie.typeset(f, text).computeBounds()
      let tw = max(int(bounds.w) + 2, 1)
      let th = max(int(max(bounds.h, physSize)) + 2, 1)
      let img = pixie.newImage(tw, th)
      let a = uint8((opaqued shr 24) and 0xFF)
      let r = uint8((opaqued shr 16) and 0xFF)
      let g = uint8((opaqued shr  8) and 0xFF)
      let b = uint8( opaqued         and 0xFF)
      var pt = newPaint(SolidPaint)
      pt.color = rgba(r, g, b, a).color
      f.paints = @[pt]
      img.fillText(f, text, translate(vec2(0, 0)))
      entry = SdlTextCacheEntry(image: img, width: tw, height: th)
      if sdlTextCache.len >= sdlTextCacheLimit:
        sdlTextCache.clear()
      sdlTextCache[key] = entry
    # Blit the cached bitmap at `pos`. Pixie places typeset text at
    # the top-left of the translate point, NOT the baseline; the
    # cache image preserves that, so just translate directly.
    #
    # IMPORTANT: image.draw bypasses the Context's transformation
    # matrix, so we must compose with getTransform() ourselves or
    # text inside a `transform` widget (rotation / scale / slide
    # animations) paints at untransformed coordinates.
    #
    # The cached image is rasterized at physical scale (fontSize *
    # dpr); ctx.getTransform() also has scale(dpr) baked in. Without
    # a counter-scale of 1/dpr the high-res bitmap would draw dpr^2
    # too large. With it, the bitmap lands at the correct logical
    # size with full native pixel density. dpr == 1 short-circuits.
    let m =
      if dpr == 1.0'f32:
        c.ctx.getTransform() * translate(vec2(pos.dx, pos.dy))
      else:
        c.ctx.getTransform() * translate(vec2(pos.dx, pos.dy)) *
          pixie.scale(vec2(1.0'f32 / dpr, 1.0'f32 / dpr))
    c.image.draw(entry.image, m)

  method save*(c: SdlCanvas) = c.ctx.save()
  method restore*(c: SdlCanvas) = c.ctx.restore()
  method translate*(c: SdlCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)
  method scale*(c: SdlCanvas, sx, sy: float32) = c.ctx.scale(sx, sy)
  method rotate*(c: SdlCanvas, radians: float32) = c.ctx.rotate(radians)
  method clipRect*(c: SdlCanvas, r: geom.Rect) =
    # Clamp the clip rect to the canvas bounds. Pixie's NEON fill
    # path raises IndexDefect when the clip's bounding box
    # extends past the underlying buffer. Clamping is safe
    # because nothing outside the canvas is visible anyway.
    let canvasW = c.size.width
    let canvasH = c.size.height
    let left   = max(0.0'f32, r.left)
    let top    = max(0.0'f32, r.top)
    let right  = min(canvasW, r.right)
    let bottom = min(canvasH, r.bottom)
    if right <= left or bottom <= top:
      # Fully off-screen; clip to a zero-area rect so subsequent
      # draws are no-ops.
      var path = newPath()
      pixie.rect(path, pixie.rect(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32))
      c.ctx.clip(path)
      return
    var path = newPath()
    pixie.rect(path, pixie.rect(left, top, right - left, bottom - top))
    c.ctx.clip(path)

  method drawImage*(c: SdlCanvas, image: pointer, src, dst: geom.Rect) =
    ## Draws a Pixie image from the `image` pointer (cast from a
    ## Pixie `Image` ref) into the `dst` rect, taking the `src`
    ## sub-rect. Uses Pixie's draw with a translate+scale matrix
    ## to handle non-1:1 scaling.
    if image.isNil: return
    let img = cast[pixie.Image](image)
    let srcW = src.right - src.left
    let srcH = src.bottom - src.top
    let dstW = dst.right - dst.left
    let dstH = dst.bottom - dst.top
    if srcW <= 0 or srcH <= 0 or dstW <= 0 or dstH <= 0: return
    let sx = dstW / srcW
    let sy = dstH / srcH
    var mat = translate(vec2(dst.left, dst.top)) *
              pixie.scale(vec2(sx, sy)) *
              translate(vec2(-src.left, -src.top))
    c.image.draw(img, mat)

  # --- Sub-canvas (RepaintBoundary backing) ---

  type
    SdlSubCanvas* = ref object of Canvas
      ## Off-screen sub-canvas: a Pixie image with no SDL window.
      ## RepaintBoundary draws into one of these and then composites
      ## the result onto its parent canvas. The parent's
      ## `compositeSubCanvas` does the upload-and-blit so the per-
      ## frame cost of a clean boundary is a single GPU operation.
      ##
      ## HiDPI: inherits its parent's `dpr` so the cached bitmap is
      ## rasterized at full native pixel density just like the main
      ## canvas. `compositeSubCanvas` composes the inverse scale so
      ## the physical-sized bitmap blits at the right logical size.
      image*:        Image
      ctx*:          Context
      fonts*:        Table[string, Font]
      defaultFont*:  Font
      dpr*:          float32
      # A persistent GPU texture cache. When the sub-canvas is clean
      # (i.e. its pixels match what's in `texture`) we can skip the
      # CPU-to-GPU upload entirely.
      texture*:      TexturePtr
      textureDirty*: bool

  proc disposeSubCanvas*(s: SdlSubCanvas) =
    ## Releases the SDL texture this sub-canvas holds. Safe to
    ## call multiple times. Call when a `RepaintBoundary` is
    ## unmounted to avoid leaking GPU memory; otherwise the
    ## texture stays alive until the SDL renderer itself is
    ## destroyed.
    if s.isNil: return
    if not s.texture.isNil:
      destroyTexture(s.texture)
      s.texture = nil

  proc newSdlSubCanvas*(parent: SdlCanvas, w, h: int): SdlSubCanvas =
    ## Builds a child sub-canvas backed by its own Pixie image. The
    ## texture is created lazily on first composite. Fonts are
    ## shared from `parent` so text inside the boundary renders
    ## without each layer carrying its own font table.
    ##
    ## Pixie image is sized at PHYSICAL resolution (w * parent.dpr)
    ## so the cached bitmap is sharp on retina; the context applies
    ## scale(dpr) so drawing into the sub-canvas uses logical
    ## coordinates the same as the main canvas.
    let dpr = parent.dpr
    let pw = max(1, int(float32(w) * dpr + 0.5'f32))
    let ph = max(1, int(float32(h) * dpr + 0.5'f32))
    var img = newImage(pw, ph)
    var c = newContext(img)
    if dpr != 1.0'f32: c.scale(dpr, dpr)
    SdlSubCanvas(image: img, ctx: c,
                 fonts: parent.fonts, defaultFont: parent.defaultFont,
                 dpr: dpr,
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

  method fillPolygon*(s: SdlSubCanvas, points: seq[geom.Offset], fill: uint32) =
    if points.len < 3: return
    s.ctx.fillStyle = subArgbToPaint(s, fill)
    var path = newPath()
    path.moveTo(points[0].dx, points[0].dy)
    for i in 1 ..< points.len:
      path.lineTo(points[i].dx, points[i].dy)
    path.closePath()
    s.ctx.fill(path)
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
    # Clamp to sub-canvas bounds. See SdlCanvas.clipRect for rationale.
    let canvasW = s.size.width
    let canvasH = s.size.height
    let left   = max(0.0'f32, r.left)
    let top    = max(0.0'f32, r.top)
    let right  = min(canvasW, r.right)
    let bottom = min(canvasH, r.bottom)
    if right <= left or bottom <= top:
      var path = newPath()
      pixie.rect(path, pixie.rect(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32))
      s.ctx.clip(path)
      return
    var path = newPath()
    pixie.rect(path, pixie.rect(left, top, right - left, bottom - top))
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
    # Composite the sub-canvas's CPU Pixie image into the parent's
    # CPU Pixie image. `Image.draw` uses Pixie's vectorized
    # RGBA-over-RGBA blend (much faster than a per-pixel Nim loop).
    # The parent's `present` then handles the single CPU->GPU
    # upload for the whole frame. This is the source of truth for
    # what the user sees; we no longer keep a separate GPU texture
    # per sub-canvas.
    # Compose with the Context's transform so a RepaintBoundary
    # inside a `transform` widget (scaled / rotated / translated
    # animation) composites at the transformed position. The
    # sub-canvas image is at physical scale; getTransform() has
    # scale(dpr); a counter-scale of 1/dpr lands the bitmap at its
    # natural logical size with full pixel density preserved.
    let dpr = c.dpr
    let m =
      if dpr == 1.0'f32:
        c.ctx.getTransform() * translate(vec2(offset.dx, offset.dy))
      else:
        c.ctx.getTransform() * translate(vec2(offset.dx, offset.dy)) *
          pixie.scale(vec2(1.0'f32 / dpr, 1.0'f32 / dpr))
    c.image.draw(s.image, m)

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
