## Embedded runner. For headless targets that draw to a raw framebuffer
## (Raspberry Pi DRM/KMS, e-ink panels, kiosks, etc.). Uses Pixie to
## render off-screen, then hands the pixel buffer to a caller-supplied
## flush callback. Typically dispatched to via
## `runApp(widget, flush = myFlush)` on builds with `-d:flitEmbedded`.

when defined(js):
  {.error: "embedded runner is not for JS backend".}

import std/[times, os, tables, hashes]
import pixie except Rect, rect
import ../../foundation/[widget, render_object, binding, geometry, runtime,
                          diagnostics]

type
  EmbeddedCanvas* = ref object of Canvas
    ## A `Canvas` implementation that paints into a Pixie `Image`
    ## in memory. The host pulls the rendered pixels out via
    ## `EmbeddedFlush` once per frame.
    image*: Image
    ctx*:   Context

  EmbeddedFlush* = proc(pixels: ptr UncheckedArray[uint32], w, h: int)
    ## Host-supplied callback that writes the rendered frame
    ## somewhere (e.g. `/dev/fb0`, an SPI bus, a network stream).
    ## `pixels` is an ARGB buffer of length `w * h`. The pointer is
    ## owned by flit and only valid for the duration of the call.

proc argbToColor(v: uint32): pixie.Color =
  let a = float32((v shr 24) and 0xFF) / 255.0
  let r = float32((v shr 16) and 0xFF) / 255.0
  let g = float32((v shr  8) and 0xFF) / 255.0
  let b = float32( v         and 0xFF) / 255.0
  pixie.color(r, g, b, a)

proc newEmbeddedCanvas*(w, h: int): EmbeddedCanvas =
  ## Allocates a Pixie-backed canvas of `w x h` pixels. Used for both
  ## the `runEmbedded` runner and for offline tests that render the
  ## widget tree to a PNG.
  let img = newImage(w, h)
  EmbeddedCanvas(image: img, ctx: newContext(img),
                 size: Size(width: float32(w), height: float32(h)))

proc argbToPaint(v: uint32): Paint =
  result = newPaint(SolidPaint)
  result.color = argbToColor(v)

method clear*(c: EmbeddedCanvas, color: uint32) =
  c.ctx.fillStyle = argbToPaint(color)
  c.ctx.fillRect(pixie.rect(0.0'f32, 0.0'f32, c.size.width, c.size.height))

method drawRect*(c: EmbeddedCanvas, r: Rect, fill: uint32) =
  c.ctx.fillStyle = argbToPaint(fill)
  c.ctx.fillRect(pixie.rect(r.left, r.top, r.width, r.height))

method drawRRect*(c: EmbeddedCanvas, r: RRect, fill: uint32) =
  c.ctx.fillStyle = argbToPaint(fill)
  var path = newPath()
  path.roundedRect(pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height),
                   r.tl.x, r.tr.x, r.br.x, r.bl.x)
  c.ctx.fill(path)

method drawCircle*(c: EmbeddedCanvas, center: Offset, radius: float32, fill: uint32) =
  c.ctx.fillStyle = argbToPaint(fill)
  var path = newPath()
  path.circle(center.dx, center.dy, radius)
  c.ctx.fill(path)

method drawLine*(c: EmbeddedCanvas, p0, p1: Offset, color: uint32, width: float32) =
  c.ctx.strokeStyle = argbToPaint(color)
  c.ctx.lineWidth = width
  var path = newPath()
  path.moveTo(p0.dx, p0.dy)
  path.lineTo(p1.dx, p1.dy)
  c.ctx.stroke(path)

var embeddedFont*: pixie.Font = nil
  ## Pixie font used by the embedded canvas's `drawText`. Hosts that
  ## need text rendering should assign this from a loaded TTF before
  ## the first frame; defaults to nil (no text drawn).

# Text rasterization cache. Pixie's fillText is the single biggest
# CPU cost in the warm paint pass; for stable strings (every list
# item label, every button caption) we rasterize once into a small
# image and `draw` that image on every subsequent call. Cache key
# is (text, fontSize, color); the active font is implicit because
# only one font is installed at a time.

type
  TextCacheKey = object
    text: string
    size: uint16   # px
    color: uint32

  TextCacheEntry = object
    image: pixie.Image
    width, height: int

proc hash(k: TextCacheKey): Hash =
  var h: Hash = 0
  h = h !& hash(k.text)
  h = h !& int(k.size)
  h = h !& int(k.color)
  !$h

proc `==`(a, b: TextCacheKey): bool =
  a.text == b.text and a.size == b.size and a.color == b.color

var embeddedTextCache* {.threadvar.}: Table[TextCacheKey, TextCacheEntry]
var embeddedTextCacheLimit* = 1024
  ## Max entries before old ones get evicted. Tune for your UI.

proc clearEmbeddedTextCache*() =
  ## Drops every rasterized text image from the cache.
  embeddedTextCache.clear()

proc rasterizeText(text: string, fontSize: float32, color: uint32): TextCacheEntry =
  ## Renders `text` into a fresh Pixie image sized to the typeset
  ## bounds + 2px padding. Returns the image + dimensions.
  embeddedFont.size = fontSize
  let bounds = pixie.typeset(embeddedFont, text).computeBounds()
  let tw = max(int(bounds.w) + 2, 1)
  let th = max(int(max(bounds.h, fontSize)) + 2, 1)
  let img = pixie.newImage(tw, th)
  embeddedFont.paints = @[argbToPaint(color)]
  img.fillText(embeddedFont, text, translate(pixie.vec2(0, 0)))
  TextCacheEntry(image: img, width: tw, height: th)

method drawText*(c: EmbeddedCanvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) =
  if embeddedFont.isNil: return
  if text.len == 0: return
  let opaqued = c.applyOpacity(color)
  let key = TextCacheKey(text: text, size: uint16(fontSize), color: opaqued)
  var entry: TextCacheEntry
  if embeddedTextCache.hasKey(key):
    entry = embeddedTextCache[key]
  else:
    entry = rasterizeText(text, fontSize, opaqued)
    if embeddedTextCache.len < embeddedTextCacheLimit:
      embeddedTextCache[key] = entry
  c.image.draw(entry.image,
               translate(pixie.vec2(pos.dx, pos.dy)))

method save*(c: EmbeddedCanvas)    = c.ctx.save()
method restore*(c: EmbeddedCanvas) = c.ctx.restore()
method translate*(c: EmbeddedCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)
method scale*(c: EmbeddedCanvas, sx, sy: float32) = c.ctx.scale(sx, sy)
method rotate*(c: EmbeddedCanvas, radians: float32) = c.ctx.rotate(radians)

proc runEmbedded*(rootWidget: Widget, w, h: int, flush: EmbeddedFlush,
                  frameRateHz: int = 30) =
  ## Mounts `rootWidget`, renders frames at `frameRateHz`, and calls
  ## `flush(pixels, w, h)` after each frame so the host can present
  ## them. Blocks forever; intended for kiosk / embedded use.
  ##
  ## Inputs:
  ## - `rootWidget`: top of the widget tree.
  ## - `w`, `h`: framebuffer dimensions in pixels.
  ## - `flush`: host callback. See `EmbeddedFlush`.
  ## - `frameRateHz`: target frame rate. Sleeps between frames.
  let canvas = newEmbeddedCanvas(w, h)
  let binding = newBinding(canvas, Size(width: float32(w), height: float32(h)))
  let rootElement = mountElement(nil, rootWidget, 0)
  binding.rootElement = rootElement
  runLayout(rootElement, tightFor(binding.surfaceSize))

  let frameMs = 1000 div frameRateHz
  while true:
    if binding.dirtyRoots.len > 0:
      let pending = binding.dirtyRoots
      binding.dirtyRoots.setLen(0)
      for r in pending: rebuildElement(r)
      runLayout(rootElement, tightFor(binding.surfaceSize))
    canvas.clear(0xFFFFFFFF'u32)
    runPaint(rootElement, canvas)
    flush(cast[ptr UncheckedArray[uint32]](addr canvas.image.data[0]), w, h)
    sleep(frameMs)
