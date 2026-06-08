## Embedded runner. For headless targets that draw to a raw framebuffer
## (Raspberry Pi DRM/KMS, e-ink panels, kiosks). Uses Pixie to render off-screen,
## then writes pixel buffers via a user-supplied flush callback.

when defined(js):
  {.error: "embedded runner is not for JS backend".}

import std/[times, os]
import pixie
import ../../foundation/[widget, render_object, binding, geometry, runtime,
                          diagnostics]

type
  EmbeddedCanvas* = ref object of Canvas
    image*: Image
    ctx*:   Context

  EmbeddedFlush* = proc(pixels: ptr UncheckedArray[uint32], w, h: int)

proc argbToColor(v: uint32): pixie.Color =
  let a = float32((v shr 24) and 0xFF) / 255.0
  let r = float32((v shr 16) and 0xFF) / 255.0
  let g = float32((v shr  8) and 0xFF) / 255.0
  let b = float32( v         and 0xFF) / 255.0
  pixie.color(r, g, b, a)

proc newEmbeddedCanvas*(w, h: int): EmbeddedCanvas =
  let img = newImage(w, h)
  EmbeddedCanvas(image: img, ctx: newContext(img),
                 size: Size(width: float32(w), height: float32(h)))

method clear*(c: EmbeddedCanvas, color: uint32) =
  c.ctx.fillStyle = argbToColor(color)
  c.ctx.fillRect(rect(0.0, 0.0, c.size.width, c.size.height))

method drawRect*(c: EmbeddedCanvas, r: Rect, fill: uint32) =
  c.ctx.fillStyle = argbToColor(fill)
  c.ctx.fillRect(pixie.rect(r.left, r.top, r.width, r.height))

method drawRRect*(c: EmbeddedCanvas, r: RRect, fill: uint32) =
  c.ctx.fillStyle = argbToColor(fill)
  c.ctx.fillRoundedRect(
    pixie.rect(r.rect.left, r.rect.top, r.rect.width, r.rect.height),
    r.tl.x, r.tr.x, r.br.x, r.bl.x)

method drawCircle*(c: EmbeddedCanvas, center: Offset, radius: float32, fill: uint32) =
  c.ctx.fillStyle = argbToColor(fill)
  c.ctx.fillCircle(circle(pixie.vec2(center.dx, center.dy), radius))

method drawLine*(c: EmbeddedCanvas, p0, p1: Offset, color: uint32, width: float32) =
  c.ctx.strokeStyle = argbToColor(color)
  c.ctx.lineWidth = width
  c.ctx.strokeSegment(segment(pixie.vec2(p0.dx, p0.dy), pixie.vec2(p1.dx, p1.dy)))

method drawText*(c: EmbeddedCanvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) =
  discard  # embedded loads a font separately if needed

method save*(c: EmbeddedCanvas)    = c.ctx.save()
method restore*(c: EmbeddedCanvas) = c.ctx.restore()
method translate*(c: EmbeddedCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)

proc runEmbedded*(rootWidget: Widget, w, h: int, flush: EmbeddedFlush,
                  frameRateHz: int = 30) =
  let canvas = newEmbeddedCanvas(w, h)
  let binding = newBinding(canvas, Size(width: float32(w), height: float32(h)))
  let rootElement = mountElement(nil, rootWidget, 0)
  binding.rootElement = rootElement
  runLayout(rootElement, tightFor(binding.surfaceSize))

  let frameMs = 1000 div frameRateHz
  while true:
    if binding.dirtyRoots.len > 0:
      for r in binding.dirtyRoots: rebuildElement(r)
      binding.clearDirty()
      runLayout(rootElement, tightFor(binding.surfaceSize))
    canvas.clear(0xFFFFFFFF'u32)
    runPaint(rootElement, canvas)
    flush(cast[ptr UncheckedArray[uint32]](addr canvas.image.data[0]), w, h)
    sleep(frameMs)
