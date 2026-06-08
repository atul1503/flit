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

method performLayout*(r: RenderProxyBox) =
  if r.child.isNil:
    # No child: expand to whatever the parent's constraints allow. If we
    # shrunk to zero here, every decorative-only ColoredBox/DecoratedBox
    # (used as backgrounds, dividers, spacers) would disappear.
    let w = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: 0.0'f32
    let h = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: 0.0'f32
    r.setSize(r.constraints.constrain(Size(width: w, height: h)))
  else:
    r.child.layout(r.constraints)
    r.setSize(r.constraints.constrain(r.child.size))

method paint*(r: RenderProxyBox, ctx: PaintingContext, offset: Offset) =
  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

method hitTest*(r: RenderProxyBox, htResult: HitTestResult, position: Offset): bool =
  ## Default proxy: forward to the child if the point is inside us, then add
  ## ourself so a GestureDetector wrapping us is reachable.
  if not r.child.isNil:
    let local = position - r.child.offset
    let cs = r.child.size
    if local.dx >= 0 and local.dy >= 0 and local.dx < cs.width and local.dy < cs.height:
      discard r.child.hitTest(htResult, local)
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

# ConstrainedBox

method performLayout*(r: RenderConstrainedBox) =
  let merged = r.additionalConstraints.enforce(r.constraints)
  if r.child.isNil:
    r.setSize(merged.constrain(SizeZero))
  else:
    r.child.layout(merged)
    r.setSize(merged.constrain(r.child.size))

# SizedBox: like ConstrainedBox but supplies tight constraints from width/height.

method performLayout*(r: RenderSizedBox) =
  # SizedBox uses requested dims as TIGHT constraints. For unspecified dims:
  # when no child, default to 0 (so SizedBox(width=12) is a 12x0 spacer, not
  # a column-filling bar). When there IS a child, leave loose so the child
  # picks its own size in the unspecified axis.
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

# AspectRatio: pick the largest box that fits constraints and has the
# requested width/height ratio, mirroring Flutter's RenderAspectRatio
# algorithm. Falls back to width-driven sizing when both axes are
# unbounded so the result is still finite.

method performLayout*(r: RenderAspectRatio) =
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
  if not r.child.isNil:
    ctx.paintChild(r.child, r.child.offset)

# Align (also used by Center, which is just Align(Alignment.center))

method performLayout*(r: RenderAlign) =
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
  if not r.child.isNil:
    ctx.paintChild(r.child, r.child.offset)

# ColoredBox

method paint*(r: RenderColoredBox, ctx: PaintingContext, offset: Offset) =
  let rect = rectFromOffsetSize(offset, r.size)
  ctx.canvas.drawRect(rect, r.fill.value)
  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

# Opacity (simple: just dim child by alpha-blending its result). For
# performance we'd push a layer; here we forward to the canvas hint.

method paint*(r: RenderOpacity, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  ctx.canvas.pushOpacity(r.opacity)
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.popOpacity()

# ClipRect: clips its child's painting to its own bounds. Layout is just
# pass-through (parent constraints define our box).

method paint*(r: RenderClipRect, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()

# ClipRRect: same but with rounded corners. The clipRect call on most
# backends is rectangular, so we approximate by painting a rounded fill
# in a transparent layer; here we just clip to the bounding box and rely
# on the child's own rounded decoration. A real layer-aware backend can
# override this method.

method paint*(r: RenderClipRRect, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()

# Transform: applies a full TRS (translate, rotate, scale) around the
# child's top-left. Each component is skipped if it's the identity.

method paint*(r: RenderTransform, ctx: PaintingContext, offset: Offset) =
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
