## Image widget. Loads PNG / JPEG / BMP / GIF from disk via Pixie,
## caches decoded images by absolute path, and paints them through
## the canvas.
##
## Public surface:
## - `image(path)` widget constructor.
## - `imageMemory(bytes)` for in-memory image data.
## - `clearImageCache()` to drop the cache (useful in tests).
##
## The decoded `Image` is held by the cache; the widget just
## carries the path or bytes. Painting goes through a custom
## `drawImageAt` proc on the canvas; backends that don't implement
## image drawing show a placeholder rectangle.

import std/[tables, hashes]
import ../foundation/[widget, render_object, geometry, color, key]

when not defined(js):
  import pixie except Rect, rect

type
  ImageFit* = enum
    ## How to scale the image into its slot:
    ## - `ifFill`: stretch to fill, ignore aspect ratio
    ## - `ifContain`: largest size that fits, preserve aspect ratio
    ## - `ifCover`: smallest size that covers, preserve aspect ratio
    ## - `ifNone`: draw at native size, top-left aligned
    ifFill, ifContain, ifCover, ifNone

  ImageWidget* = ref object of RenderObjectWidget
    ## Carries the image source plus rendering hints.
    path*:   string             ## absolute disk path; empty for in-memory
    bytes*:  string             ## raw image bytes; empty when using path
    fit*:    ImageFit
    width*:  float32
    height*: float32

  RenderImage* = ref object of RenderObject
    path*:        string
    bytes*:       string
    fit*:         ImageFit
    requestedW*:  float32
    requestedH*:  float32
    when not defined(js):
      decoded*:   pixie.Image

# Cache of decoded images keyed by source identity. Path-keyed for
# disk images, byte-hash-keyed for in-memory. Cache is unbounded
# today; eviction would be a future addition for image-heavy apps.

when not defined(js):
  var imageCache: Table[string, pixie.Image]

proc cacheKey(path, bytes: string): string =
  if path.len > 0: "p:" & path
  else: "b:" & $hash(bytes)

proc loadImage*(path, bytes: string): auto =
  ## Returns the decoded Pixie image for the given source, decoding
  ## and caching on first call. Returns nil on failure (file
  ## missing, decode error, etc.).
  when defined(js):
    return nil
  else:
    let key = cacheKey(path, bytes)
    if imageCache.hasKey(key):
      return imageCache[key]
    var img: pixie.Image
    try:
      if path.len > 0:
        img = readImage(path)
      else:
        img = decodeImage(bytes)
    except CatchableError:
      return nil
    if img.isNil: return nil
    imageCache[key] = img
    return img

proc clearImageCache*() =
  ## Drops every decoded image from the cache. Use in tests or to
  ## free memory when transitioning between scenes.
  when not defined(js):
    imageCache.clear()

method widgetTypeName*(w: ImageWidget): string = "Image"
method createElement*(w: ImageWidget): Element = newElement(ekRender, w)
method createRenderObject*(w: ImageWidget, ctx: BuildContext): RenderObject =
  let r = RenderImage(path: w.path, bytes: w.bytes, fit: w.fit,
                      requestedW: w.width, requestedH: w.height)
  when not defined(js):
    r.decoded = loadImage(w.path, w.bytes)
  r

method updateRenderObject*(w: ImageWidget, ctx: BuildContext, r: RenderObject) =
  let ri = RenderImage(r)
  if ri.path != w.path or ri.bytes != w.bytes:
    ri.path = w.path
    ri.bytes = w.bytes
    when not defined(js):
      ri.decoded = loadImage(w.path, w.bytes)
  ri.fit = w.fit
  ri.requestedW = w.width
  ri.requestedH = w.height
  r.markNeedsLayout()

method performLayout*(r: RenderImage) =
  ## Sizing strategy:
  ## - Both width and height requested: use them tight (subject to
  ##   parent's constraints).
  ## - One dimension requested + image known: derive the other from
  ##   the aspect ratio.
  ## - Neither requested + image known: use image's natural size,
  ##   clamped to parent's constraints.
  ## - No image: fill bounded constraints, or 0x0.
  var w, h: float32
  when not defined(js):
    let imgW = if r.decoded.isNil: 0.0'f32 else: float32(r.decoded.width)
    let imgH = if r.decoded.isNil: 0.0'f32 else: float32(r.decoded.height)
  else:
    let imgW = 0.0'f32
    let imgH = 0.0'f32

  if r.requestedW > 0 and r.requestedH > 0:
    w = r.requestedW; h = r.requestedH
  elif r.requestedW > 0 and imgW > 0:
    w = r.requestedW; h = w * imgH / imgW
  elif r.requestedH > 0 and imgH > 0:
    # The previous version checked `imgW > 0` here, then divided
    # by imgH which could be zero. Bug fix: check the divisor.
    h = r.requestedH; w = h * imgW / imgH
  elif imgW > 0 and imgH > 0:
    w = imgW; h = imgH
  else:
    w = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: 0.0'f32
    h = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: 0.0'f32
  r.setSize(r.constraints.constrain(Size(width: w, height: h)))

method paint*(r: RenderImage, ctx: PaintingContext, offset: Offset) =
  when defined(js):
    ctx.canvas.drawRect(rectFromOffsetSize(offset, r.size), 0xFFE0E0E0'u32)
    return
  else:
    if r.decoded.isNil:
      # Placeholder: light grey box with diagonal line.
      ctx.canvas.drawRect(rectFromOffsetSize(offset, r.size), 0xFFE0E0E0'u32)
      ctx.canvas.drawLine(offset, offset + Offset(dx: r.size.width, dy: r.size.height),
                          0xFFAAAAAA'u32, 1.0)
      return
    let img = r.decoded
    let sw = float32(img.width)
    let sh = float32(img.height)
    let dw = r.size.width
    let dh = r.size.height
    # Degenerate input: skip drawing if any dimension is zero
    # (no pixels to fit; avoids div-by-zero in aspect math).
    if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0: return
    var dstW, dstH, dstX, dstY: float32
    case r.fit
    of ifFill:
      dstW = dw; dstH = dh; dstX = offset.dx; dstY = offset.dy
    of ifNone:
      dstW = sw; dstH = sh; dstX = offset.dx; dstY = offset.dy
    of ifContain:
      let arSrc = sw / sh
      let arDst = dw / dh
      if arSrc > arDst:
        dstW = dw; dstH = dw / arSrc
      else:
        dstH = dh; dstW = dh * arSrc
      dstX = offset.dx + (dw - dstW) * 0.5'f32
      dstY = offset.dy + (dh - dstH) * 0.5'f32
    of ifCover:
      let arSrc = sw / sh
      let arDst = dw / dh
      if arSrc < arDst:
        dstW = dw; dstH = dw / arSrc
      else:
        dstH = dh; dstW = dh * arSrc
      dstX = offset.dx + (dw - dstW) * 0.5'f32
      dstY = offset.dy + (dh - dstH) * 0.5'f32
    ctx.canvas.drawImage(cast[pointer](img),
                         Rect(left: 0, top: 0, right: sw, bottom: sh),
                         Rect(left: dstX, top: dstY,
                              right: dstX + dstW, bottom: dstY + dstH))

method hitTest*(r: RenderImage, htResult: HitTestResult, position: Offset): bool =
  htResult.path.add(HitTestEntry(target: r, local: position))
  true

proc image*(path: string, fit: ImageFit = ifContain,
            width: float32 = 0, height: float32 = 0,
            key: Key = nil): ImageWidget =
  ## Builds an `Image` widget that loads `path` from disk.
  ##
  ## Inputs:
  ## - `path`: absolute path to PNG / JPEG / BMP / GIF.
  ## - `fit`: how to scale the image into the widget's box.
  ## - `width`, `height`: optional explicit dims. Zero leaves the
  ##   axis derived from constraints + native aspect ratio.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: decodes the image once (cached for subsequent uses
  ## of the same path), then paints via the canvas's drawImage on
  ## every frame. Shows a light grey placeholder if the load
  ## fails.
  ImageWidget(key: key, path: path, bytes: "", fit: fit,
              width: width, height: height)

proc imageMemory*(bytes: string, fit: ImageFit = ifContain,
                  width: float32 = 0, height: float32 = 0,
                  key: Key = nil): ImageWidget =
  ## Builds an `Image` widget from in-memory bytes. Same semantics
  ## as `image` otherwise. Useful for embedded images via
  ## `staticRead` or images received over the network.
  ImageWidget(key: key, path: "", bytes: bytes, fit: fit,
              width: width, height: height)
