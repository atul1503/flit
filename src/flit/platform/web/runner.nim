## Web runner: HTMLCanvasElement-based backend for the JS target.
## Driven by the browser's requestAnimationFrame.

when not defined(js):
  {.error: "web runner is only for the js backend".}

import std/[dom, jsffi]
import ../../foundation/[widget, render_object, binding, geometry,
                          runtime, diagnostics]

type
  WebCanvas* = ref object of Canvas
    ctx*: JsObject  # CanvasRenderingContext2D
    elem*: Element  # HTMLCanvasElement

proc colorToCss(v: uint32): cstring =
  let a = (v shr 24) and 0xFF
  let r = (v shr 16) and 0xFF
  let g = (v shr  8) and 0xFF
  let b =  v         and 0xFF
  cstring("rgba(" & $r & "," & $g & "," & $b & "," & $(float(a)/255.0) & ")")

method clear*(c: WebCanvas, color: uint32) =
  c.ctx.fillStyle = colorToCss(color).toJs
  c.ctx.fillRect(0, 0, c.size.width, c.size.height)

method drawRect*(c: WebCanvas, r: Rect, fill: uint32) =
  c.ctx.fillStyle = colorToCss(fill).toJs
  c.ctx.fillRect(r.left, r.top, r.width, r.height)

method drawRRect*(c: WebCanvas, r: RRect, fill: uint32) =
  c.ctx.fillStyle = colorToCss(fill).toJs
  c.ctx.beginPath()
  let radius = r.tl.x
  c.ctx.roundRect(r.rect.left, r.rect.top, r.rect.width, r.rect.height, radius)
  c.ctx.fill()

method drawCircle*(c: WebCanvas, center: Offset, radius: float32, fill: uint32) =
  c.ctx.fillStyle = colorToCss(fill).toJs
  c.ctx.beginPath()
  c.ctx.arc(center.dx, center.dy, radius, 0, 6.283185307)
  c.ctx.fill()

method drawLine*(c: WebCanvas, p0, p1: Offset, color: uint32, width: float32) =
  c.ctx.strokeStyle = colorToCss(color).toJs
  c.ctx.lineWidth = width.toJs
  c.ctx.beginPath()
  c.ctx.moveTo(p0.dx, p0.dy)
  c.ctx.lineTo(p1.dx, p1.dy)
  c.ctx.stroke()

method drawText*(c: WebCanvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) =
  c.ctx.fillStyle = colorToCss(color).toJs
  c.ctx.font = (cstring($fontSize & "px " & fontFamily)).toJs
  c.ctx.fillText(cstring(text), pos.dx, pos.dy + fontSize)

method save*(c: WebCanvas)    = c.ctx.save()
method restore*(c: WebCanvas) = c.ctx.restore()
method translate*(c: WebCanvas, dx, dy: float32) = c.ctx.translate(dx, dy)
method clipRect*(c: WebCanvas, r: Rect) =
  c.ctx.beginPath()
  c.ctx.rect(r.left, r.top, r.width, r.height)
  c.ctx.clip()

proc runWeb*(rootWidget: Widget, canvasElementId: string = "flit-canvas") =
  let canvasEl = document.getElementById(canvasElementId.cstring)
  if canvasEl.isNil:
    raise newException(ValueError, "canvas element not found: " & canvasElementId)
  let cw = canvasEl.clientWidth.float32
  let ch = canvasEl.clientHeight.float32
  let ctx = canvasEl.toJs.getContext("2d".cstring)
  let canvas = WebCanvas(ctx: ctx, elem: canvasEl,
                         size: Size(width: cw, height: ch))
  let binding = newBinding(canvas, canvas.size, 1.0)
  let rootElement = mountElement(nil, rootWidget, 0)
  binding.rootElement = rootElement
  runLayout(rootElement, tightFor(canvas.size))
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(rootElement, canvas)

  proc frame(ts: float) =
    if binding.dirtyRoots.len > 0:
      for r in binding.dirtyRoots: rebuildElement(r)
      binding.clearDirty()
      runLayout(rootElement, tightFor(binding.surfaceSize))
    canvas.clear(0xFFFFFFFF'u32)
    runPaint(rootElement, canvas)
    discard window.toJs.requestAnimationFrame(frame)

  discard window.toJs.requestAnimationFrame(frame)
