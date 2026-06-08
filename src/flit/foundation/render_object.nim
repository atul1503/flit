## RenderObject: the layout and paint tree. Each `RenderObject` knows
## how to measure itself given parent `Constraints` and paint itself
## onto a `Canvas`. Mirrors Flutter's `RenderObject` / `RenderBox`.
##
## Concrete render objects live in `flit/rendering/*`. Each is
## instantiated by a `RenderObjectWidget`'s `createRenderObject` and
## kept up-to-date by `updateRenderObject`.

import std/[options]
import ./geometry
import ./diagnostics

type
  Canvas* = ref object of RootObj
    ## Abstract drawing surface. Concrete backends override the draw
    ## methods below: `SdlCanvas` for desktop, `WebCanvas` for the JS
    ## target, `EmbeddedCanvas` for framebuffer rendering.
    ##
    ## Tracks an opacity stack so the `Opacity` widget can attenuate
    ## the alpha of every primitive painted inside its subtree.
    size*: Size            ## current surface size in logical pixels.
    opacityStack*: seq[float32]
      ## stack of opacity multipliers. Top is the active value;
      ## `pushOpacity` pushes `top * alpha` and `popOpacity` pops.
      ## Empty stack means 1.0 (opaque).

  PaintingContext* = ref object
    ## Carries the current canvas and the absolute origin of whoever
    ## is painting into it. Pass to `paintChild` to descend into a
    ## subtree.
    canvas*: Canvas
    offset*: Offset

  HitTestEntry* = object
    ## A single entry in a hit-test path: the render object the
    ## pointer was inside, plus the position translated into that
    ## render object's local coordinate space.
    target*: RenderObject
    local*: Offset

  HitTestResult* = ref object
    ## Result of a hit-test walk. The `path` is leaf-first: index 0
    ## is the deepest render object the pointer touched.
    path*: seq[HitTestEntry]

  RenderObject* = ref object of RootObj
    ## Base of the render tree. Subclasses override `performLayout`,
    ## `paint`, and (optionally) `hitTest`. Fields:
    ## - `parent`: parent render object, set by attachment.
    ## - `constraints`: last constraints received from `layout()`.
    ## - `sizeOpt`: size assigned by `setSize` during layout. None
    ##   means "not yet laid out".
    ## - `offset`: position within the parent (in parent's coord
    ##   space). Some render objects use this; others store offsets
    ##   in their own parent-data structs.
    ## - `needsLayout`: true when a future layout pass should re-run
    ##   `performLayout`. Set by `markNeedsLayout`.
    ## - `needsPaint`: similar for repainting.
    ## - `attached`: true after `attach()`, false after `detach()`.
    ## - `debugLabel`: optional name shown by `debugDescribe`.
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
  ## Returns the current opacity multiplier (top of the stack, or 1.0
  ## if the stack is empty).
  if c.opacityStack.len == 0: 1.0'f32 else: c.opacityStack[^1]

proc pushOpacity*(c: Canvas, alpha: float32) =
  ## Pushes a new opacity onto the stack. The new value is
  ## `currentOpacity * clamp(alpha, 0, 1)`, so nested `opacity`
  ## widgets multiply.
  let parent = currentOpacity(c)
  c.opacityStack.add(parent * clamp(alpha, 0.0'f32, 1.0'f32))

proc popOpacity*(c: Canvas) =
  ## Pops the topmost opacity. Safe to call on an empty stack
  ## (no-op).
  if c.opacityStack.len > 0: discard c.opacityStack.pop()

proc applyOpacity*(c: Canvas, color: uint32): uint32 =
  ## Returns `color` with its alpha multiplied by the current opacity.
  ## Backends call this on every draw so `RenderOpacity` just pushes
  ## and pops without each shape knowing about opacity.
  ##
  ## Input: a packed `0xAARRGGBB` value.
  ## Output: same color with the alpha channel scaled by
  ## `currentOpacity(c)`. Returns the input unchanged if opacity is
  ## effectively 1.0.
  let mul = currentOpacity(c)
  if mul >= 0.999'f32: return color
  let a = ((color shr 24) and 0xFF).float32 * mul
  let aByte = uint32(clamp(a, 0.0, 255.0).int)
  (color and 0x00FFFFFF'u32) or (aByte shl 24)

# Forward declarations for methods used by procs below.
method paint*(r: RenderObject, ctx: PaintingContext, offset: Offset) {.base.}

# Canvas interface. Backends override these via method.

method drawRect*(c: Canvas, r: Rect, fill: uint32) {.base.} = discard
  ## Fills `r` with the ARGB color `fill`. Backends override; base is
  ## a no-op (useful for recording / counting in tests).

method drawRRect*(c: Canvas, r: RRect, fill: uint32) {.base.} = discard
  ## Fills a rounded rectangle.

method drawCircle*(c: Canvas, center: Offset, radius: float32, fill: uint32) {.base.} = discard
  ## Fills a circle centered at `center` with the given `radius`.

method drawLine*(c: Canvas, p0, p1: Offset, color: uint32, width: float32) {.base.} = discard
  ## Strokes a line from `p0` to `p1` with the given `color` and
  ## `width` in logical pixels.

method drawText*(c: Canvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) {.base.} = discard
  ## Draws `text` at `pos` (top-left of the first glyph) in `color`
  ## with the given `fontSize` and `fontFamily`. Backends look up the
  ## font by family name.

method drawImage*(c: Canvas, image: pointer, src, dst: Rect) {.base.} = discard
  ## Blits a region `src` of `image` (a backend-specific pointer) to
  ## the region `dst` on the canvas.

method clipRect*(c: Canvas, r: Rect) {.base.} = discard
  ## Restricts subsequent drawing to the rectangle `r`. Use `save` and
  ## `restore` around the clip to scope it.

method save*(c: Canvas) {.base.} = discard
  ## Pushes the current transform/clip state.

method restore*(c: Canvas) {.base.} = discard
  ## Pops the most recently saved transform/clip state.

method translate*(c: Canvas, dx, dy: float32) {.base.} = discard
  ## Translates the canvas origin by `(dx, dy)`.

method scale*(c: Canvas, sx, sy: float32) {.base.} = discard
  ## Scales the canvas by `(sx, sy)` around the current origin.

method rotate*(c: Canvas, radians: float32) {.base.} = discard
  ## Rotates the canvas by `radians` around the current origin.

method clear*(c: Canvas, color: uint32) {.base.} = discard
  ## Fills the entire canvas with `color`. Typically called by the
  ## runner at the start of each frame.

# PaintingContext

proc newPaintingContext*(canvas: Canvas, offset = OffsetZero): PaintingContext =
  ## Builds a `PaintingContext`. The `offset` is the absolute origin
  ## of the render object that "owns" this context (i.e., where its
  ## (0,0) maps to on the canvas).
  PaintingContext(canvas: canvas, offset: offset)

proc paintChild*(ctx: PaintingContext, child: RenderObject, offset: Offset) =
  ## Recursively paints a child render object. `offset` is the child's
  ## position relative to `ctx`'s origin. The child paints at the
  ## absolute position `ctx.offset + offset`. Safe to call with
  ## `child == nil` (no-op).
  if child.isNil: return
  let childCtx = newPaintingContext(ctx.canvas, ctx.offset + offset)
  paint(child, childCtx, ctx.offset + offset)

method paint*(r: RenderObject, ctx: PaintingContext, offset: Offset) = discard
  ## Paints `r` at the given absolute `offset`. Default no-op;
  ## subclasses override to issue draw calls and `paintChild` calls.

method performLayout*(r: RenderObject) {.base.} = discard
  ## Computes this render object's size given `r.constraints` (set by
  ## the parent's `layout` call) and lays out children. Subclasses
  ## MUST override and end by calling `setSize` with the final size.

method hitTest*(r: RenderObject, htResult: HitTestResult, position: Offset): bool {.base.} =
  ## Tests whether `position` (in this render object's local
  ## coordinate space) is inside `r`. Default adds an entry for `r`
  ## and returns true. Container subclasses override to iterate
  ## children first.
  ##
  ## Inputs:
  ## - `htResult`: the `HitTestResult` to append to. Entries are
  ##   added leaf-first (deepest hit first).
  ## - `position`: pointer location in this render object's local
  ##   coordinate space.
  ##
  ## Returns: true if the pointer hit this render object.
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

# Public surface

proc size*(r: RenderObject): Size =
  ## Returns the size assigned by `setSize` during the last layout,
  ## or `SizeZero` if not yet laid out.
  if r.sizeOpt.isSome: r.sizeOpt.get else: SizeZero

proc setSize*(r: RenderObject, s: Size) =
  ## Records `s` as this render object's size. Called from
  ## `performLayout`.
  r.sizeOpt = some(s)

proc constraintsEq(a, b: Constraints): bool =
  a.minWidth == b.minWidth and a.maxWidth == b.maxWidth and
  a.minHeight == b.minHeight and a.maxHeight == b.maxHeight

proc layout*(r: RenderObject, c: Constraints) =
  ## Called by the parent to lay out `r` under constraints `c`.
  ## Stores the constraints, runs `performLayout`, clears the
  ## dirty flag. Skips the inner layout pass entirely when `c`
  ## matches the previous call AND `needsLayout` is false (relayout
  ## fast path; mirrors Flutter's `RenderObject.layout`).
  ##
  ## Side effects: may call into the subtree's `performLayout` and
  ## set `sizeOpt` / child offsets.
  if r.isNil: return
  if not r.needsLayout and r.sizeOpt.isSome and constraintsEq(r.constraints, c):
    return
  r.constraints = c
  r.performLayout()
  r.needsLayout = false

proc markNeedsLayout*(r: RenderObject) =
  ## Marks `r` and all ancestors as needing layout. Idempotent; if
  ## `r` was already dirty the walk stops immediately. Call this when
  ## a property changes that affects sizing.
  if r.isNil or r.needsLayout: return
  r.needsLayout = true
  if not r.parent.isNil:
    r.parent.markNeedsLayout()

proc markNeedsPaint*(r: RenderObject) =
  ## Marks `r` and all ancestors as needing repaint. Call this when
  ## a property changes that affects only appearance (color, etc.),
  ## not layout.
  if r.isNil or r.needsPaint: return
  r.needsPaint = true
  if not r.parent.isNil:
    r.parent.markNeedsPaint()

proc attach*(r: RenderObject) =
  ## Marks `r` as attached to the render tree. Lifecycle hook
  ## reserved for future use.
  r.attached = true

proc detach*(r: RenderObject) =
  ## Marks `r` as detached.
  r.attached = false

proc debugDescribe*(r: RenderObject): DiagnosticsNode =
  ## Returns a debug `DiagnosticsNode` showing the render object's
  ## type, size, offset and optional `debugLabel`. Subclasses can
  ## override (via a normal proc with same signature is hard in Nim;
  ## typically you provide your own wrapper).
  let n = node($typeof(r), "size=" & $r.size & ", offset=" & $r.offset)
  if r.debugLabel.len > 0:
    n.add("label", r.debugLabel)
  n
