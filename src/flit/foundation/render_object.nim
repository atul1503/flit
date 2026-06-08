## RenderObject: the layout and paint tree. Each RenderObject knows how to
## measure itself given parent Constraints and paint itself onto a Canvas.
## Mirrors Flutter's RenderObject / RenderBox.

import std/[options]
import ./geometry
import ./diagnostics

type
  Canvas* = ref object of RootObj
    ## Abstract drawing surface. Implementations live in
    ## `flit/rendering/canvas_sdl.nim`, `flit/rendering/canvas_js.nim`, etc.
    size*: Size

  PaintingContext* = ref object
    canvas*: Canvas
    offset*: Offset

  HitTestEntry* = object
    target*: RenderObject
    local*: Offset

  HitTestResult* = ref object
    path*: seq[HitTestEntry]

  RenderObject* = ref object of RootObj
    parent*: RenderObject
    constraints*: Constraints
    sizeOpt*: Option[Size]
    offset*: Offset
    needsLayout*: bool
    needsPaint*: bool
    attached*: bool
    debugLabel*: string

# Forward declarations for methods used by procs below.
method paint*(r: RenderObject, ctx: PaintingContext, offset: Offset) {.base.}

# Canvas interface. Backends override these via method.
method drawRect*(c: Canvas, r: Rect, fill: uint32) {.base.} = discard
method drawRRect*(c: Canvas, r: RRect, fill: uint32) {.base.} = discard
method drawCircle*(c: Canvas, center: Offset, radius: float32, fill: uint32) {.base.} = discard
method drawLine*(c: Canvas, p0, p1: Offset, color: uint32, width: float32) {.base.} = discard
method drawText*(c: Canvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) {.base.} = discard
method drawImage*(c: Canvas, image: pointer, src, dst: Rect) {.base.} = discard
method clipRect*(c: Canvas, r: Rect) {.base.} = discard
method save*(c: Canvas) {.base.} = discard
method restore*(c: Canvas) {.base.} = discard
method translate*(c: Canvas, dx, dy: float32) {.base.} = discard
method clear*(c: Canvas, color: uint32) {.base.} = discard

# PaintingContext

proc newPaintingContext*(canvas: Canvas, offset = OffsetZero): PaintingContext =
  PaintingContext(canvas: canvas, offset: offset)

proc paintChild*(ctx: PaintingContext, child: RenderObject, offset: Offset) =
  ## Recursively paint a child render object. Caller provides child's offset
  ## from this context's origin.
  if child.isNil: return
  let childCtx = newPaintingContext(ctx.canvas, ctx.offset + offset)
  paint(child, childCtx, ctx.offset + offset)

method paint*(r: RenderObject, ctx: PaintingContext, offset: Offset) = discard
method performLayout*(r: RenderObject) {.base.} = discard
method hitTest*(r: RenderObject, htResult: HitTestResult, position: Offset): bool {.base.} =
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

# Public surface

proc size*(r: RenderObject): Size =
  if r.sizeOpt.isSome: r.sizeOpt.get else: SizeZero

proc setSize*(r: RenderObject, s: Size) =
  r.sizeOpt = some(s)

proc layout*(r: RenderObject, c: Constraints) =
  ## Called by the parent. Stores constraints, runs performLayout, clears
  ## the dirty flag.
  if r.isNil: return
  r.constraints = c
  r.performLayout()
  r.needsLayout = false

proc markNeedsLayout*(r: RenderObject) =
  if r.isNil or r.needsLayout: return
  r.needsLayout = true
  if not r.parent.isNil:
    r.parent.markNeedsLayout()

proc markNeedsPaint*(r: RenderObject) =
  if r.isNil or r.needsPaint: return
  r.needsPaint = true
  if not r.parent.isNil:
    r.parent.markNeedsPaint()

proc attach*(r: RenderObject) =
  r.attached = true

proc detach*(r: RenderObject) =
  r.attached = false

proc debugDescribe*(r: RenderObject): DiagnosticsNode =
  ## Default debug node; subclasses override to add their fields.
  let n = node($typeof(r), "size=" & $r.size & ", offset=" & $r.offset)
  if r.debugLabel.len > 0:
    n.add("label", r.debugLabel)
  n
