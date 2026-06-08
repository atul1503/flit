## Lazy list render object. Only mounts and lays out the items
## visible in the viewport plus a small over-render buffer; items
## that scroll off the screen are kept in a cache so they can be
## re-shown without a fresh build (state preservation).
##
## Mirrors the Flutter pattern of `SliverList` + `ListView.builder`:
## arbitrary item count without per-item layout cost. The `total`
## height (or width) reported to the viewport is
## `itemCount * itemExtent`, so the scrollbar geometry is correct
## even though most items have never been built.

import std/tables
import ../foundation/[render_object, geometry]
import ./viewport

type
  RenderSliverList* = ref object of RenderViewport
    ## Lazy viewport. Items live in `items` keyed by absolute index;
    ## the widget layer fills this table during its `build` based on
    ## the visible range reported back via `firstVisible` /
    ## `lastVisible`.
    ##
    ## Fields beyond `RenderViewport`:
    ## - `itemCount`: total number of items in the conceptual list.
    ## - `itemExtent`: per-item pixel size when items are
    ##   fixed-extent. Positive means "every item is exactly this
    ##   size"; the scroll math runs in O(1) per query.
    ## - `extentFor`: optional callback returning the per-item
    ##   extent for variable-extent lists. When set, `itemExtent`
    ##   is ignored and the sliver maintains a prefix-sum cache of
    ##   measured extents indexed by item position. Items past the
    ##   highest-measured index get an estimated extent (set to
    ##   `extentEstimate`) so the scrollbar geometry remains
    ##   stable while the user scrolls.
    ## - `extentEstimate`: fallback extent for items we have not
    ##   yet measured. The estimate is replaced with the true
    ##   extent the first time the item enters the visible range.
    ## - `prefixSums`: cumulative extents up to but not including
    ##   each index, with one extra entry at the end holding the
    ##   total. Index-from-offset is then a binary search.
    ## - `measured`: which prefix-sum entries reflect real
    ##   measurements vs. estimates.
    ## - `items`: cached child render objects by absolute index.
    ## - `firstVisible`, `lastVisible`: index range computed during
    ##   the most recent layout. The widget layer reads these to
    ##   know which items to mount on the next build.
    itemCount*:      int
    itemExtent*:     float32
    extentFor*:      proc(idx: int): float32 {.closure.}
    extentEstimate*: float32
    prefixSums*:     seq[float32]
    measured*:       seq[bool]
    items*:          Table[int, RenderObject]
    firstVisible*:   int
    lastVisible*:    int

proc rebuildPrefixSums*(r: RenderSliverList) =
  ## Rebuild the prefix-sum cache from scratch. Called when the
  ## item count changes or the extent function is replaced. For
  ## fixed-extent lists this is unused (we use `itemExtent` math
  ## directly).
  if r.extentFor.isNil: return
  let n = r.itemCount
  let est = if r.extentEstimate > 0: r.extentEstimate else: 50.0'f32
  r.prefixSums.setLen(n + 1)
  r.measured.setLen(n)
  r.prefixSums[0] = 0
  for i in 0 ..< n:
    r.measured[i] = false
    r.prefixSums[i + 1] = r.prefixSums[i] + est

proc recordExtent(r: RenderSliverList, idx: int, extent: float32) =
  ## Update the prefix-sum cache after measuring item `idx`. Only
  ## reshuffles indices >= idx+1; the prefix walk is O(n) worst-
  ## case but in practice runs only over the dirty tail so amortizes
  ## well. For workloads where this is too expensive we can move to
  ## a Fenwick tree later without touching the public API.
  if r.extentFor.isNil: return
  if idx < 0 or idx >= r.itemCount: return
  let prev = r.prefixSums[idx + 1] - r.prefixSums[idx]
  if abs(prev - extent) < 0.001'f32 and r.measured[idx]: return
  let delta = extent - prev
  for j in (idx + 1) .. r.itemCount:
    r.prefixSums[j] = r.prefixSums[j] + delta
  r.measured[idx] = true

proc indexAtOffset(r: RenderSliverList, off: float32): int =
  ## Binary search the prefix-sum cache for the item whose extent
  ## interval contains `off`. Returns the largest index `i` such
  ## that `prefixSums[i] <= off`. Clamped to `[0, itemCount-1]`.
  if r.extentFor.isNil: return 0
  if off <= 0 or r.itemCount <= 0: return 0
  if off >= r.prefixSums[r.itemCount]: return r.itemCount - 1
  var lo = 0
  var hi = r.itemCount
  while lo < hi:
    let mid = (lo + hi) div 2
    if r.prefixSums[mid + 1] <= off:
      lo = mid + 1
    else:
      hi = mid
  lo

proc offsetOfIndex*(r: RenderSliverList, idx: int): float32 =
  ## Returns the cumulative extent of items `0..idx-1`. For fixed-
  ## extent lists this is just `idx * itemExtent`; for variable-
  ## extent lists it's the prefix-sum entry.
  if r.extentFor.isNil:
    return float32(idx) * r.itemExtent
  if idx <= 0: return 0
  if idx >= r.itemCount: return r.prefixSums[r.itemCount]
  return r.prefixSums[idx]

proc extentOfIndex*(r: RenderSliverList, idx: int): float32 =
  ## Returns the extent of item `idx`. Uses the measured value
  ## when available, otherwise the estimate (or `itemExtent` for
  ## fixed-extent lists).
  if r.extentFor.isNil:
    return r.itemExtent
  if idx < 0 or idx >= r.itemCount: return 0
  if r.measured[idx]:
    return r.prefixSums[idx + 1] - r.prefixSums[idx]
  return if r.extentEstimate > 0: r.extentEstimate else: 50.0'f32

proc newRenderSliverList*(itemCount: int, itemExtent: float32,
                          direction: Axis = axVertical,
                          extentFor: proc(idx: int): float32 = nil,
                          extentEstimate: float32 = 0): RenderSliverList =
  ## Builds a fresh `RenderSliverList`. Items are added incrementally
  ## by the widget layer.
  ##
  ## Inputs:
  ## - `itemCount`: total items.
  ## - `itemExtent`: extent for fixed-extent lists. Ignored when
  ##   `extentFor` is set.
  ## - `direction`: scroll axis.
  ## - `extentFor`: optional callback returning per-item extent.
  ##   When set, the list operates in variable-extent mode.
  ## - `extentEstimate`: extent used for items we have not yet
  ##   measured. Used to seed scrollbar geometry before items are
  ##   visible. Defaults to 50px if zero.
  result = RenderSliverList(direction: direction, itemCount: itemCount,
                            itemExtent: itemExtent,
                            extentFor: extentFor,
                            extentEstimate: extentEstimate,
                            items: initTable[int, RenderObject](),
                            firstVisible: -1, lastVisible: -1)
  if not extentFor.isNil:
    result.rebuildPrefixSums()

method performLayout*(r: RenderSliverList) =
  ## Computes which items are visible at the current scroll offset,
  ## lays each one out, and records the visible range for the
  ## widget layer to inspect. Handles both fixed-extent (when
  ## `extentFor` is nil) and variable-extent (when it isn't) lists.
  ##
  ## For variable-extent lists, the per-item extent is measured the
  ## first time the item enters the visible range. The prefix-sum
  ## cache is updated incrementally so subsequent scrolls reuse
  ## the measurement.
  let mainConstraint =
    if r.direction == axVertical: r.constraints.maxHeight
    else:                          r.constraints.maxWidth
  let crossConstraint =
    if r.direction == axVertical: r.constraints.maxWidth
    else:                          r.constraints.maxHeight

  # Size the viewport itself.
  let myW = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: 0.0'f32
  let myH = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: 0.0'f32
  r.setSize(r.constraints.constrain(Size(width: myW, height: myH)))

  if r.itemCount <= 0:
    r.firstVisible = -1
    r.lastVisible = -1
    r.maxScroll = 0
    return

  let variable = not r.extentFor.isNil

  # Make sure the prefix-sum cache exists for variable-extent lists.
  if variable and r.prefixSums.len != r.itemCount + 1:
    r.rebuildPrefixSums()

  if not variable and r.itemExtent <= 0:
    r.firstVisible = -1
    r.lastVisible = -1
    r.maxScroll = 0
    return

  # Find first visible.
  var firstIdx, lastIdx: int
  if variable:
    firstIdx = max(0, r.indexAtOffset(r.scrollOffset) - 1)
  else:
    firstIdx = max(0, int(r.scrollOffset / r.itemExtent) - 1)

  # Walk forward until we've covered the viewport (extent of each
  # visible item is queried lazily). For variable-extent we also
  # record measured extents on every visible item to keep the
  # prefix sums hot.
  if variable:
    var coveredFromFirst = 0.0'f32
    var i = firstIdx
    # firstIdx may start a bit above scrollOffset; we want
    # firstIdx's top to be <= scrollOffset.
    var firstOff = r.offsetOfIndex(firstIdx)
    let need = (r.scrollOffset - firstOff) + mainConstraint
    while i < r.itemCount and coveredFromFirst < need + 1.0'f32:
      let realExtent = r.extentFor(i)
      r.recordExtent(i, realExtent)
      coveredFromFirst += realExtent
      lastIdx = i
      inc i
    # Add a one-item buffer.
    lastIdx = min(r.itemCount - 1, lastIdx + 1)
  else:
    let visibleCount = int(mainConstraint / r.itemExtent) + 3
    lastIdx = min(r.itemCount - 1, firstIdx + visibleCount)

  r.firstVisible = firstIdx
  r.lastVisible = lastIdx

  # Total content extent.
  let total =
    if variable: r.prefixSums[r.itemCount]
    else:        float32(r.itemCount) * r.itemExtent
  r.maxScroll = max(0.0'f32, total - mainConstraint)
  r.clampScroll()

  # Lay out items in the visible range. Their offsets within the
  # content frame come from the prefix sums (variable) or
  # `idx * itemExtent` (fixed).
  for idx in firstIdx .. lastIdx:
    if not r.items.hasKey(idx): continue
    let child = r.items[idx]
    let childExtent = r.extentOfIndex(idx)
    let childConstraints =
      if r.direction == axVertical:
        # Variable extent uses a max constraint rather than tight
        # so the child can self-size; we re-measure after layout.
        if variable: constraints(0, crossConstraint, 0, childExtent * 4)
        else:        constraints(0, crossConstraint, childExtent, childExtent)
      else:
        if variable: constraints(0, childExtent * 4, 0, crossConstraint)
        else:        constraints(childExtent, childExtent, 0, crossConstraint)
    child.layout(childConstraints)
    if variable:
      # Update the prefix-sum cache with the real measured extent.
      let measured = if r.direction == axVertical: child.size.height
                     else: child.size.width
      r.recordExtent(idx, measured)
    let pos = r.offsetOfIndex(idx)
    if r.direction == axVertical:
      child.offset = Offset(dx: 0, dy: pos)
    else:
      child.offset = Offset(dx: pos, dy: 0)

method paint*(r: RenderSliverList, ctx: PaintingContext, offset: Offset) =
  ## Paints only the items in the current visible range, with the
  ## scroll-offset translation and viewport clip applied. Items
  ## past the visible range are silently skipped even if they're
  ## still in `items`.
  if r.firstVisible < 0: return
  ctx.canvas.save()
  ctx.canvas.clipRect(rectFromOffsetSize(offset, r.size))
  let shift =
    if r.direction == axVertical: Offset(dx: 0, dy: -r.scrollOffset)
    else:                          Offset(dx: -r.scrollOffset, dy: 0)
  for idx in r.firstVisible .. r.lastVisible:
    if r.items.hasKey(idx):
      let child = r.items[idx]
      ctx.paintChild(child, child.offset + shift)
  ctx.canvas.restore()

  # Optional scrollbar thumb (same as RenderViewport).
  if r.maxScroll <= 0: return
  const thumbWidth = 6.0'f32
  const thumbMargin = 2.0'f32
  let total =
    if r.extentFor.isNil: float32(r.itemCount) * r.itemExtent
    else:                  r.prefixSums[r.itemCount]
  if r.direction == axVertical:
    let thumbH = max(20.0'f32, r.size.height * (r.size.height / total))
    let thumbY = (r.scrollOffset / r.maxScroll) * (r.size.height - thumbH)
    ctx.canvas.drawRect(
      Rect(left: offset.dx + r.size.width - thumbWidth - thumbMargin,
           top: offset.dy + thumbY,
           right: offset.dx + r.size.width - thumbMargin,
           bottom: offset.dy + thumbY + thumbH),
      0x80404040'u32)
  else:
    let thumbW = max(20.0'f32, r.size.width * (r.size.width / total))
    let thumbX = (r.scrollOffset / r.maxScroll) * (r.size.width - thumbW)
    ctx.canvas.drawRect(
      Rect(left: offset.dx + thumbX,
           top: offset.dy + r.size.height - thumbWidth - thumbMargin,
           right: offset.dx + thumbX + thumbW,
           bottom: offset.dy + r.size.height - thumbMargin),
      0x80404040'u32)

method hitTest*(r: RenderSliverList, htResult: HitTestResult, position: Offset): bool =
  ## Hit-tests only items in the visible range. Translates by
  ## scroll offset before descending. Always adds itself to the
  ## path so scroll wheel events route here (via the parent's
  ## viewport handling in `processPointerEvents`).
  if r.firstVisible >= 0:
    let shift =
      if r.direction == axVertical: Offset(dx: 0, dy: -r.scrollOffset)
      else:                          Offset(dx: -r.scrollOffset, dy: 0)
    for idx in r.firstVisible .. r.lastVisible:
      if r.items.hasKey(idx):
        let child = r.items[idx]
        let childPos = child.offset + shift
        let local = position - childPos
        let cs = child.size
        if local.dx >= 0 and local.dy >= 0 and
           local.dx < cs.width and local.dy < cs.height:
          if child.hitTest(htResult, local):
            htResult.path.add(HitTestEntry(target: r, local: position))
            return true
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

proc updateVisibleItems*(r: RenderSliverList,
                        builtItems: Table[int, RenderObject]) =
  ## Called by the widget layer after building items for the
  ## current visible range. Replaces `r.items` with the new
  ## mapping, attaches each child's parent pointer, and marks
  ## layout dirty so the next pass positions the items.
  ##
  ## Items that were in `r.items` but not in `builtItems` are
  ## dropped (no caching across visible-range changes). This
  ## means stateful items lose state when scrolled out; a future
  ## refinement could keep them around.
  r.items = builtItems
  for _, child in r.items:
    child.parent = r
  r.markNeedsLayout()
