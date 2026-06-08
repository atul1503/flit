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

  proc present*(c: SdlCanvas) =
    ## Push the pixie image into the SDL streaming texture and render it.
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
