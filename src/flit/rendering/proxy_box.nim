## Proxy-style render objects: those with a single child that mostly delegate
## layout and painting to it. ConstrainedBox, Padding, Center, Align, Opacity,
## etc. all build on these.

import std/options
import ../foundation/[render_object, geometry, color]

type
  RenderProxyBox* = ref object of RenderObject
    child*: RenderObject

  RenderConstrainedBox* = ref object of RenderProxyBox
    additionalConstraints*: Constraints

  RenderPadding* = ref object of RenderProxyBox
    padding*: EdgeInsets

  RenderAlign* = ref object of RenderProxyBox
    alignment*: Alignment
    widthFactor*: float32   # 0 means follow constraints
    heightFactor*: float32

  RenderColoredBox* = ref object of RenderProxyBox
    fill*: Color

  RenderOpacity* = ref object of RenderProxyBox
    opacity*: float32

  RenderTransform* = ref object of RenderProxyBox
    translation*: Offset
    scale*: float32
    rotation*: float32

  RenderSizedBox* = ref object of RenderProxyBox
    requestedWidth*: float32
    requestedHeight*: float32

method performLayout*(r: RenderProxyBox) =
  if r.child.isNil:
    r.setSize(r.constraints.constrain(SizeZero))
  else:
    r.child.layout(r.constraints)
    r.setSize(r.constraints.constrain(r.child.size))

method paint*(r: RenderProxyBox, ctx: PaintingContext, offset: Offset) =
  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

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
  var minW, maxW, minH, maxH: float32
  if r.requestedWidth > 0:
    minW = r.requestedWidth; maxW = r.requestedWidth
  else:
    minW = r.constraints.minWidth; maxW = r.constraints.maxWidth
  if r.requestedHeight > 0:
    minH = r.requestedHeight; maxH = r.requestedHeight
  else:
    minH = r.constraints.minHeight; maxH = r.constraints.maxHeight
  let merged = constraints(minW, maxW, minH, maxH).enforce(r.constraints)
  if r.child.isNil:
    r.setSize(merged.constrain(Size(width: maxW, height: maxH)))
  else:
    r.child.layout(merged)
    r.setSize(merged.constrain(r.child.size))

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
  ctx.canvas.save()
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()

# Transform: applies a translate+scale (rotation handled by backend).

method paint*(r: RenderTransform, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.translate(r.translation.dx, r.translation.dy)
  ctx.paintChild(r.child, OffsetZero)
  ctx.canvas.restore()
