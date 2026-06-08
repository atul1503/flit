## SDL2 + Pixie-backed canvas implementation.
##
## Pixie does the high-quality 2D vector rendering into an ARGB pixel buffer;
## SDL2 blits that buffer to a window each frame. This gives us anti-aliased
## shapes, gradients, and real font rendering on macOS, Linux, and Windows.

import ../foundation/[render_object, geometry]

when not defined(js):
  import pixie
  import sdl2
  import std/[tables]

  type
    SdlCanvas* = ref object of Canvas
      image*:    Image
      ctx*:      Context
      window*:   WindowPtr
      renderer*: RendererPtr
      texture*:  TexturePtr
      fonts*:    Table[string, Font]
      defaultFont*: Font

  proc newSdlCanvas*(window: WindowPtr, renderer: RendererPtr,
                     w, h: int, defaultFontPath: string = ""): SdlCanvas =
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
    c.image = newImage(w, h)
    c.ctx  = newContext(c.image)
    c.size = Size(width: float32(w), height: float32(h))
    destroyTexture(c.texture)
    c.texture = createTexture(c.renderer, SDL_PIXELFORMAT_ARGB8888,
                              SDL_TEXTUREACCESS_STREAMING, cint(w), cint(h))

  proc argbToColor(v: uint32): pixie.Color =
    let a = float32((v shr 24) and 0xFF) / 255.0
    let r = float32((v shr 16) and 0xFF) / 255.0
    let g = float32((v shr  8) and 0xFF) / 255.0
    let b = float32( v         and 0xFF) / 255.0
    pixie.color(r, g, b, a)

  method clear*(c: SdlCanvas, color: uint32) =
    c.ctx.fillStyle = argbToColor(color)
    c.ctx.fillRect(rect(0.0, 0.0, c.size.width, c.size.height))

  method drawRect*(c: SdlCanvas, r: Rect, fill: uint32) =
    c.ctx.fillStyle = argbToColor(fill)
    c.ctx.fillRect(pixie.rect(r.left, r.top, r.width, r.height))

  method drawRRect*(c: SdlCanvas, r: RRect, fill: uint32) =
    c.ctx.fillStyle = argbToColor(fill)
    c.ctx.fillRoundedRect(
      pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height),
      r.tl.x, r.tr.x, r.br.x, r.bl.x)

  method drawCircle*(c: SdlCanvas, center: Offset, radius: float32, fill: uint32) =
    c.ctx.fillStyle = argbToColor(fill)
    c.ctx.fillCircle(circle(pixie.vec2(center.dx, center.dy), radius))

  method drawLine*(c: SdlCanvas, p0, p1: Offset, color: uint32, width: float32) =
    c.ctx.strokeStyle = argbToColor(color)
    c.ctx.lineWidth = width
    c.ctx.strokeSegment(segment(
      pixie.vec2(p0.dx, p0.dy), pixie.vec2(p1.dx, p1.dy)))

  method drawText*(c: SdlCanvas, text: string, pos: Offset, color: uint32,
                   fontSize: float32, fontFamily: string) =
    var f = c.fonts.getOrDefault(fontFamily, c.defaultFont)
    if f.isNil: return
    f.size = fontSize
    f.paint.color = argbToColor(color)
    c.ctx.image.fillText(f, text, translate(pixie.vec2(pos.dx, pos.dy + fontSize)))

  method save*(c: SdlCanvas) = c.ctx.save()
  method restore*(c: SdlCanvas) = c.ctx.restore()
  method translate*(c: SdlCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)
  method clipRect*(c: SdlCanvas, r: Rect) =
    c.ctx.beginPath()
    c.ctx.rect(pixie.rect(r.left, r.top, r.width, r.height))
    c.ctx.clip()

  proc present*(c: SdlCanvas) =
    ## Push the pixie image into the SDL streaming texture and render it.
    var pixels: pointer
    var pitch: cint
    discard lockTexture(c.texture, nil, addr pixels, addr pitch)
    let w = c.image.width
    let h = c.image.height
    # Pixie uses RGBA8888; SDL wants ARGB8888. Swap bytes per pixel.
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
