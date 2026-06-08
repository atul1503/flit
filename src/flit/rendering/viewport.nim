## Scrollable viewport. Lays out the child with unbounded main-axis
## constraints, clips to its own bounds, and paints the child translated
## by -scrollOffset. The runtime's pointer dispatch updates scrollOffset
## when a mouse-wheel event lands inside.

import ../foundation/[render_object, geometry, color]

type
  RenderViewport* = ref object of RenderObject
    child*: RenderObject
    scrollOffset*: float32    # how far down (or right) we've scrolled
    maxScroll*:    float32    # set during layout: child main-extent minus our main-extent
    direction*:    Axis

proc clampScroll*(r: RenderViewport) =
  if r.scrollOffset < 0:               r.scrollOffset = 0
  if r.scrollOffset > r.maxScroll:     r.scrollOffset = r.maxScroll

method performLayout*(r: RenderViewport) =
  if r.child.isNil:
    r.setSize(r.constraints.constrain(SizeZero))
    r.maxScroll = 0
    return
  let inner =
    if r.direction == axVertical:
      constraints(r.constraints.minWidth, r.constraints.maxWidth, 0, Inf)
    else:
      constraints(0, Inf, r.constraints.minHeight, r.constraints.maxHeight)
  r.child.layout(inner)
  # We fill the parent's bounded constraints.
  let myW = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: r.child.size.width
  let myH = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: r.child.size.height
  r.setSize(r.constraints.constrain(Size(width: myW, height: myH)))
  r.maxScroll =
    if r.direction == axVertical:   max(0.0'f32, r.child.size.height - r.size.height)
    else:                            max(0.0'f32, r.child.size.width  - r.size.width)
  r.clampScroll()

method paint*(r: RenderViewport, ctx: PaintingContext, offset: Offset) =
  if r.child.isNil: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  let shift =
    if r.direction == axVertical: Offset(dx: 0, dy: -r.scrollOffset)
    else:                          Offset(dx: -r.scrollOffset, dy: 0)
  ctx.paintChild(r.child, shift)
  ctx.canvas.restore()

  # Scrollbar indicator. Drawn only if there's something to scroll, and
  # sized proportionally: thumb length = visible/total, position = offset/total.
  if r.maxScroll <= 0: return
  const thumbWidth = 6.0'f32
  const thumbMargin = 2.0'f32
  let total = r.maxScroll +
    (if r.direction == axVertical: r.size.height else: r.size.width)
  if r.direction == axVertical:
    let trackH = r.size.height - thumbMargin * 2
    let thumbH = max(24.0'f32, trackH * (r.size.height / total))
    let thumbY = (trackH - thumbH) * (r.scrollOffset / r.maxScroll)
    let trackX = offset.dx + r.size.width - thumbWidth - thumbMargin
    let rect = rectFromLTWH(trackX, offset.dy + thumbMargin + thumbY,
                            thumbWidth, thumbH)
    ctx.canvas.drawRRect(rrect(rect, thumbWidth * 0.5), 0x99000000'u32)
  else:
    let trackW = r.size.width - thumbMargin * 2
    let thumbW = max(24.0'f32, trackW * (r.size.width / total))
    let thumbX = (trackW - thumbW) * (r.scrollOffset / r.maxScroll)
    let trackY = offset.dy + r.size.height - thumbWidth - thumbMargin
    let rect = rectFromLTWH(offset.dx + thumbMargin + thumbX, trackY,
                            thumbW, thumbWidth)
    ctx.canvas.drawRRect(rrect(rect, thumbWidth * 0.5), 0x99000000'u32)

method hitTest*(r: RenderViewport, htResult: HitTestResult, position: Offset): bool =
  # Translate the hit point by the scroll offset, but only if it's inside
  # the visible viewport (the clip area).
  if position.dx < 0 or position.dy < 0 or
     position.dx >= r.size.width or position.dy >= r.size.height:
    return false
  if not r.child.isNil:
    let local =
      if r.direction == axVertical: position + Offset(dx: 0, dy: r.scrollOffset)
      else:                          position + Offset(dx: r.scrollOffset, dy: 0)
    discard r.child.hitTest(htResult, local)
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true
