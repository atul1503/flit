## Scrollable viewport. Backs the `ScrollView` widget.
##
## Lays out the child with unbounded main-axis constraints, clips
## painting to its own bounds, paints the child translated by
## `-scrollOffset`, and draws a thin scrollbar thumb on the trailing
## edge. The runtime's pointer dispatcher updates `scrollOffset` when
## a wheel event lands inside.

import ../foundation/[render_object, geometry, color]

type
  RenderViewport* = ref object of RenderObject
    ## A clipping, translating render object that backs `ScrollView`.
    ## Fields:
    ## - `child`: content; can be larger than the viewport along
    ##   `direction`.
    ## - `scrollOffset`: how many pixels of content are hidden above
    ##   (or to the left of) the viewport. Always in `[0, maxScroll]`.
    ## - `maxScroll`: maximum scroll offset, set during layout to
    ##   `child.mainExtent - viewport.mainExtent` (zero when the
    ##   child fits).
    ## - `direction`: scroll axis. `axVertical` or `axHorizontal`.
    child*: RenderObject
    scrollOffset*: float32
    maxScroll*:    float32
    direction*:    Axis

proc clampScroll*(r: RenderViewport) =
  ## Clamps `r.scrollOffset` to `[0, r.maxScroll]`. Called after the
  ## offset changes (e.g. by wheel events).
  if r.scrollOffset < 0:               r.scrollOffset = 0
  if r.scrollOffset > r.maxScroll:     r.scrollOffset = r.maxScroll

method performLayout*(r: RenderViewport) =
  ## Lays the child out with UNBOUNDED main-axis extent (cross
  ## constraints pass through unchanged), then sizes the viewport
  ## to fill the parent's bounded constraints. Sets `maxScroll`
  ## to `child.mainExtent - viewport.mainExtent` (clamped to zero
  ## when the child fits). Clamps the current scroll offset so it
  ## stays in range after content size changes.
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
  ## Wraps the child paint with `save()` + `clipRect()` so content
  ## outside the viewport is hidden, then offsets the child by
  ## `-scrollOffset` on the scroll axis. Restores the canvas, then
  ## draws a thin dark scrollbar thumb on the trailing edge when
  ## `maxScroll > 0`. Thumb length is `viewportExtent /
  ## totalContentExtent` and position is `scrollOffset / maxScroll`.
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
  ## Rejects points outside the visible viewport bounds, then
  ## translates the hit point by `+scrollOffset` (matching the
  ## paint-time `-scrollOffset` translation) before recursing into
  ## the child. Always adds itself to the path so wheel events can
  ## find this viewport.
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
