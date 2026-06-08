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
    # Opacity stack: top of stack is the current multiplier. Pushed by
    # RenderOpacity via pushOpacity, popped by popOpacity. Default 1.0.
    opacityStack*: seq[float32]

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

# Opacity stack helpers - declared after the type block so all of Canvas/
# RenderObject/PaintingContext are in scope.

proc currentOpacity*(c: Canvas): float32 =
  if c.opacityStack.len == 0: 1.0'f32 else: c.opacityStack[^1]

proc pushOpacity*(c: Canvas, alpha: float32) =
  let parent = currentOpacity(c)
  c.opacityStack.add(parent * clamp(alpha, 0.0'f32, 1.0'f32))

proc popOpacity*(c: Canvas) =
  if c.opacityStack.len > 0: discard c.opacityStack.pop()

proc applyOpacity*(c: Canvas, color: uint32): uint32 =
  ## Returns the input color with its alpha channel multiplied by the
  ## current opacity. Backends call this on every draw so RenderOpacity
  ## just needs to push/pop without each shape knowing about it.
  let mul = currentOpacity(c)
  if mul >= 0.999'f32: return color
  let a = ((color shr 24) and 0xFF).float32 * mul
  let aByte = uint32(clamp(a, 0.0, 255.0).int)
  (color and 0x00FFFFFF'u32) or (aByte shl 24)

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
method scale*(c: Canvas, sx, sy: float32) {.base.} = discard
method rotate*(c: Canvas, radians: float32) {.base.} = discard
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

proc constraintsEq(a, b: Constraints): bool =
  a.minWidth == b.minWidth and a.maxWidth == b.maxWidth and
  a.minHeight == b.minHeight and a.maxHeight == b.maxHeight

proc layout*(r: RenderObject, c: Constraints) =
  ## Called by the parent. Skips performLayout when the constraints match
  ## last call AND we haven't been marked dirty - mirrors Flutter's
  ## RenderObject.layout fast path. Saves a measurement pass on every
  ## widget whose constraints didn't change between rebuilds.
  if r.isNil: return
  if not r.needsLayout and r.sizeOpt.isSome and constraintsEq(r.constraints, c):
    return
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
