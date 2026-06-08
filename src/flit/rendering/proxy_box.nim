## Proxy-style render objects: single-child render objects that mostly
## delegate to their child. These are the internal render-tree nodes
## behind widgets like `Padding`, `Center`, `Align`, `ConstrainedBox`,
## `Opacity`, `Transform`, `SizedBox`, `AspectRatio`, `ClipRect`,
## `ClipRRect`, `ColoredBox`.
##
## End users typically don't construct these directly; they use the
## widget constructors in `flit/widgets/basic.nim` which create the
## right render object via their `createRenderObject` method.

import std/options
import ../foundation/[render_object, geometry, color]

type
  RenderProxyBox* = ref object of RenderObject
    ## Base class for single-child render objects. Default layout
    ## passes constraints through to the child and adopts the child's
    ## size. Default paint just paints the child unmodified.
    child*: RenderObject

  RenderConstrainedBox* = ref object of RenderProxyBox
    ## Adds extra constraints (via `additionalConstraints.enforce`) on
    ## top of those passed by the parent. Backs the `ConstrainedBox`
    ## widget.
    additionalConstraints*: Constraints

  RenderPadding* = ref object of RenderProxyBox
    ## Insets the child by `padding`. Backs the `Padding` widget.
    padding*: EdgeInsets

  RenderAlign* = ref object of RenderProxyBox
    ## Positions the child according to `alignment`. When
    ## `widthFactor`/`heightFactor` are nonzero, sizes itself to
    ## `child.size * factor`; otherwise fills its constraints. Backs
    ## the `Align` and `center` widgets.
    alignment*: Alignment
    widthFactor*: float32
    heightFactor*: float32

  RenderColoredBox* = ref object of RenderProxyBox
    ## Paints a solid `fill` color underneath the child. Backs the
    ## `ColoredBox` widget.
    fill*: Color

  RenderOpacity* = ref object of RenderProxyBox
    ## Wraps the child paint with `pushOpacity` / `popOpacity` so
    ## every primitive painted inside dims by `opacity`. Backs the
    ## `OpacityWidget`.
    opacity*: float32

  RenderTransform* = ref object of RenderProxyBox
    ## Applies a 2D translate + rotate + scale to the child's paint.
    ## Backs the `Transform` widget. `scale = 0` or `1` is treated as
    ## identity for that axis; `rotation` is in radians.
    translation*: Offset
    scale*: float32
    rotation*: float32

  RenderSizedBox* = ref object of RenderProxyBox
    ## Forces tight constraints on whichever axis has
    ## `requestedWidth > 0` or `requestedHeight > 0`. Backs the
    ## `SizedBox` widget.
    requestedWidth*: float32
    requestedHeight*: float32

  RenderAspectRatio* = ref object of RenderProxyBox
    ## Sizes the child to a given width/height ratio while obeying
    ## parent constraints. Backs the `AspectRatio` widget.
    aspectRatio*: float32

  RenderClipRect* = ref object of RenderProxyBox
    ## Clips the child's painting to this render object's rectangular
    ## bounds. Backs the `ClipRect` widget.

  RenderClipRRect* = ref object of RenderProxyBox
    ## Clips the child's painting to a rounded rectangle of the given
    ## `radius`. Backs the `ClipRRect` widget. Backend support for
    ## rounded clipping is partial; falls back to rectangular clip
    ## on backends without it.
    radius*: float32

  RenderRepaintBoundary* = ref object of RenderProxyBox
    ## Caches the rasterized output of its subtree in a backend sub-
    ## canvas. On each paint pass: if `cacheDirty` is true, the sub-
    ## canvas is re-rasterized from the child; either way the sub-
    ## canvas is then composited onto the parent canvas in a single
    ## blit (GPU when the backend supports it).
    ##
    ## Sets `cacheDirty = true` whenever `markNeedsPaint` is called on
    ## anything in the subtree (the bubble-up walk in `markNeedsPaint`
    ## passes through this render object, so we override that to flip
    ## the flag and stop the propagation).
    ##
    ## Backs the `RepaintBoundary` widget. Backends that return `nil`
    ## from `createSubCanvas` skip caching entirely and just paint the
    ## subtree directly; correctness is preserved, the perf win is
    ## lost.
    subCanvas*: Canvas
    cachedSize*: Size
    cacheDirty*: bool

method performLayout*(r: RenderProxyBox) =
  ## Default proxy layout. With a child: passes the parent's
  ## constraints through unchanged, adopts the child's size. With no
  ## child: expands to fill bounded constraints (so decorative-only
  ## ColoredBox/DecoratedBox used as backgrounds, dividers and
  ## spacers don't shrink to zero).
  if r.child.isNil:
    let w = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: 0.0'f32
    let h = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: 0.0'f32
    r.setSize(r.constraints.constrain(Size(width: w, height: h)))
  else:
    r.child.layout(r.constraints)
    r.setSize(r.constraints.constrain(r.child.size))

method paint*(r: RenderProxyBox, ctx: PaintingContext, offset: Offset) =
  ## Default proxy paint: paints the child at this widget's origin,
  ## adding no decoration of its own. Subclasses override to draw
  ## extra layers (decoration, opacity, clipping, ...).
  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

method hitTest*(r: RenderProxyBox, htResult: HitTestResult, position: Offset): bool =
  ## Default proxy hit test: forwards to the child first (if any),
  ## then unconditionally adds itself to the path so a wrapping
  ## `GestureDetector` is reachable. Always returns true.
  if not r.child.isNil:
    let local = position - r.child.offset
    let cs = r.child.size
    if local.dx >= 0 and local.dy >= 0 and local.dx < cs.width and local.dy < cs.height:
      discard r.child.hitTest(htResult, local)
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

# ConstrainedBox

method performLayout*(r: RenderConstrainedBox) =
  ## Combines `additionalConstraints` with the parent's via `enforce`
  ## (parent's tight constraints always win), then lays out the child
  ## under the merged result. With no child, sizes to the merged
  ## constraints' minima.
  let merged = r.additionalConstraints.enforce(r.constraints)
  if r.child.isNil:
    r.setSize(merged.constrain(SizeZero))
  else:
    r.child.layout(merged)
    r.setSize(merged.constrain(r.child.size))

# SizedBox: like ConstrainedBox but supplies tight constraints from width/height.

method performLayout*(r: RenderSizedBox) =
  ## Tightens an axis when its requested dim is positive. For an axis
  ## with no requested dim and no child, the size collapses to 0 (so
  ## `SizedBox(width = 12)` is a 12x0 spacer, not a column-filling
  ## bar). With a child, an unspecified axis passes through the
  ## parent's range so the child can pick its own size.
  var minW, maxW, minH, maxH: float32
  if r.requestedWidth > 0:
    minW = r.requestedWidth; maxW = r.requestedWidth
  elif r.child.isNil:
    minW = 0; maxW = 0
  else:
    minW = r.constraints.minWidth; maxW = r.constraints.maxWidth
  if r.requestedHeight > 0:
    minH = r.requestedHeight; maxH = r.requestedHeight
  elif r.child.isNil:
    minH = 0; maxH = 0
  else:
    minH = r.constraints.minHeight; maxH = r.constraints.maxHeight
  let merged = constraints(minW, maxW, minH, maxH).enforce(r.constraints)
  if r.child.isNil:
    r.setSize(merged.constrain(Size(width: maxW, height: maxH)))
  else:
    r.child.layout(merged)
    r.setSize(merged.constrain(r.child.size))

method performLayout*(r: RenderAspectRatio) =
  ## Picks the largest box that fits the parent constraints and has
  ## the requested width/height ratio (mirrors Flutter's
  ## RenderAspectRatio algorithm). Falls back to width-driven sizing
  ## via `maxHeight * ratio` when both axes are unbounded so the
  ## result is still finite. Child receives tight constraints equal
  ## to the chosen size.
  let c = r.constraints
  let ar = if r.aspectRatio > 0: r.aspectRatio else: 1.0'f32

  var w = if c.hasBoundedWidth: c.maxWidth else: c.maxHeight * ar
  var h = w / ar
  if h > c.maxHeight:
    h = c.maxHeight
    w = h * ar
  if w < c.minWidth:
    w = c.minWidth
    h = w / ar
  if h < c.minHeight:
    h = c.minHeight
    w = h * ar
  let size = c.constrain(Size(width: w, height: h))
  if not r.child.isNil:
    r.child.layout(tightFor(size))
  r.setSize(size)

# Padding

method performLayout*(r: RenderPadding) =
  ## Deflates the parent constraints by the inset totals, lays out
  ## the child under those reduced constraints, then sets this
  ## render object's size to `child.size + insets`. With no child,
  ## sizes to just the inset totals (acts as a spacer).
  let innerConstraints = r.constraints.deflate(r.padding)
  if r.child.isNil:
    r.setSize(r.constraints.constrain(
      Size(width: r.padding.horizontal, height: r.padding.vertical)))
    return
  r.child.layout(innerConstraints)
  r.child.offset = r.padding.topLeftOffset
  r.setSize(r.constraints.constrain(
    Size(width:  r.child.size.width  + r.padding.horizontal,
         height: r.child.size.height + r.padding.vertical)))

method paint*(r: RenderPadding, ctx: PaintingContext, offset: Offset) =
  ## Paints the child at the inset offset stored in `child.offset`
  ## (set during `performLayout`).
  if not r.child.isNil:
    ctx.paintChild(r.child, r.child.offset)

# Align (also used by Center, which is just Align(Alignment.center))

method performLayout*(r: RenderAlign) =
  ## Lays the child out with loose constraints so it picks its own
  ## size, then sizes this box to either `child.size * widthFactor`
  ## (when widthFactor > 0) or the parent's max width. Same for
  ## height. Finally positions the child via
  ## `alignment.resolveOffset`.
  let loose = r.constraints.loosen()
  if r.child.isNil:
    let w = if r.widthFactor  > 0: r.widthFactor  else: r.constraints.maxWidth
    let h = if r.heightFactor > 0: r.heightFactor else: r.constraints.maxHeight
    r.setSize(r.constraints.constrain(Size(width: w, height: h)))
    return
  r.child.layout(loose)
  let usedW = if r.widthFactor  > 0: r.child.size.width  * r.widthFactor
              else: r.constraints.maxWidth
  let usedH = if r.heightFactor > 0: r.child.size.height * r.heightFactor
              else: r.constraints.maxHeight
  let mySize = r.constraints.constrain(Size(width: usedW, height: usedH))
  r.setSize(mySize)
  r.child.offset = r.alignment.resolveOffset(mySize, r.child.size)

method paint*(r: RenderAlign, ctx: PaintingContext, offset: Offset) =
  ## Paints the child at the offset set during layout.
  if not r.child.isNil:
    ctx.paintChild(r.child, r.child.offset)

# ColoredBox

method paint*(r: RenderColoredBox, ctx: PaintingContext, offset: Offset) =
  ## Draws a solid `fill` rectangle covering this box's bounds, then
  ## paints the child on top unchanged.
  let rect = rectFromOffsetSize(offset, r.size)
  ctx.canvas.drawRect(rect, r.fill.value)
  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

# Opacity

method paint*(r: RenderOpacity, ctx: PaintingContext, offset: Offset) =
  ## Pushes `r.opacity` onto the canvas opacity stack, paints the
  ## child, then pops. Every primitive painted inside is alpha-scaled
  ## by `currentOpacity * r.opacity`. Nested `RenderOpacity` widgets
  ## therefore multiply.
  if r.child.isNil: return
  ctx.canvas.pushOpacity(r.opacity)
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.popOpacity()

# ClipRect: clips its child's painting to its own bounds. Layout is
# pass-through (parent constraints define our box).

method paint*(r: RenderClipRect, ctx: PaintingContext, offset: Offset) =
  ## Wraps the child's painting in `save()` + rectangular
  ## `clipRect()` + `restore()`. Any drawing that would extend
  ## outside this box's bounds is cut off.
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()

method paint*(r: RenderClipRRect, ctx: PaintingContext, offset: Offset) =
  ## Like `RenderClipRect.paint` but conceptually a rounded clip.
  ## Backends that don't support rounded clipping fall back to the
  ## bounding rectangle, so children with their own rounded
  ## decoration look correct but those without may show square
  ## corners at the edges.
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()

# RepaintBoundary: cache the child paint in a sub-canvas, composite on
# every frame. The first paint always rasterizes; subsequent paints
# skip rasterization until something in the subtree calls
# `markNeedsPaint`, which bubbles through here and sets `cacheDirty`.

method absorbPaintMark*(r: RenderRepaintBoundary) =
  r.cacheDirty = true

method paint*(r: RenderRepaintBoundary, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  let sz = r.size
  if sz.width <= 0 or sz.height <= 0:
    # Degenerate; nothing to cache.
    ctx.paintChild(r.child, OffsetZero)
    return

  # Recreate the sub-canvas whenever the boundary's size changed; the
  # old surface no longer fits.
  let sizeChanged = sz != r.cachedSize
  if r.subCanvas.isNil or sizeChanged:
    r.subCanvas = ctx.canvas.createSubCanvas(int(sz.width), int(sz.height))
    r.cachedSize = sz
    r.cacheDirty = true

  if r.subCanvas.isNil:
    # Backend doesn't support sub-canvases. Fall back to the slow
    # path: paint the subtree directly. Correctness only, no caching.
    ctx.paintChild(r.child, OffsetZero)
    return

  if r.cacheDirty:
    r.subCanvas.clear(0x00000000'u32)
    let subCtx = newPaintingContext(r.subCanvas, OffsetZero)
    paint(r.child, subCtx, OffsetZero)
    r.cacheDirty = false

  ctx.canvas.compositeSubCanvas(r.subCanvas, offset, sz)

method paint*(r: RenderTransform, ctx: PaintingContext, offset: Offset) =
  ## Applies a full Translate-Rotate-Scale on the canvas around this
  ## box's top-left, then paints the child in the transformed
  ## coordinate space. Each TRS component is skipped if it's the
  ## identity (rotation == 0, scale == 0 or 1).
  if r.child.isNil: return
  ctx.canvas.save()
  # Translate first so subsequent rotation/scale happens around the box's
  # origin (matching Flutter's default origin = top-left).
  ctx.canvas.translate(offset.dx + r.translation.dx, offset.dy + r.translation.dy)
  if r.rotation != 0:
    ctx.canvas.rotate(r.rotation)
  if r.scale != 0 and r.scale != 1:
    ctx.canvas.scale(r.scale, r.scale)
  # The canvas is now translated; reset offset to 0 in this new coord
  # space so drawing at (0,0) lands at the translated origin.
  let innerCtx = newPaintingContext(ctx.canvas, OffsetZero)
  paint(r.child, innerCtx, OffsetZero)
  ctx.canvas.restore()
