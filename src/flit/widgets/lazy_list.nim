## ListView.builder: lazy list. Items are mounted on demand based on
## the visible viewport range, so a list of a million items costs the
## same per frame as a list of fifty.
##
## Usage:
##
## .. code-block:: nim
##   listViewBuilder(
##     itemCount = 1000,
##     itemExtent = 60.0,
##     itemBuilder = proc(idx: int): Widget =
##       container(padding = edgeInsetsAll(8), child = text("Item " & $idx)))
##
## Architecture: the render object owns an internal pool of mounted
## elements keyed by absolute item index. Each layout pass:
##
## 1. Computes `firstVisible` / `lastVisible` from `scrollOffset`,
##    the viewport extent, and `itemExtent`.
## 2. For each visible index not already in the pool, calls
##    `itemBuilder`, mounts the result, stores the element.
## 3. For each pooled index that is now out of range, unmounts it
##    (calling `dispose` on any held state).
## 4. Lays out the visible items at their natural offsets.
##
## Scroll wheel events route through the standard viewport mechanism
## (`RenderSliverList` inherits from `RenderViewport`). The scrollbar
## thumb is sized as if every item were laid out, even though most
## haven't been built.
##
## State lifetime for items: each item's `State` lives from the moment
## the item scrolls in until it scrolls out, then `dispose` is called.
## Items that should keep state across scrolls should store it
## externally (e.g. in a `ValueNotifier` referenced via an
## `InheritedWidget`).

import std/tables
import ../foundation/[widget, render_object, geometry, key, runtime]
import ../rendering/[sliver_list, viewport]

type
  ListViewBuilder* = ref object of RenderObjectWidget
    ## Configuration for a lazy list. `itemExtent` and `extentFor`
    ## are mutually exclusive: pass one of them.
    ## - Fixed-extent: `itemExtent > 0` and `extentFor == nil`.
    ## - Variable-extent: `itemExtent == 0` and `extentFor != nil`.
    itemBuilder*:    proc(idx: int): Widget
    itemCount*:      int
    itemExtent*:     float32
    extentFor*:      proc(idx: int): float32
    extentEstimate*: float32
    direction*:      Axis

  RenderLazyList* = ref object of RenderSliverList
    ## Render object for `ListViewBuilder`. Adds a pool of mounted
    ## `Element` references alongside the `items` render-object
    ## table inherited from `RenderSliverList`, plus the
    ## `itemBuilder` closure used to mount items lazily.
    itemBuilder*:  proc(idx: int): Widget
    elements*:     Table[int, Element]

proc newRenderLazyList*(itemBuilder: proc(idx: int): Widget,
                       itemCount: int, itemExtent: float32,
                       direction: Axis,
                       extentFor: proc(idx: int): float32 = nil,
                       extentEstimate: float32 = 0): RenderLazyList =
  ## Builds a `RenderLazyList`. Items are mounted on demand during
  ## the layout pass. Pass `extentFor` to enable variable-extent
  ## mode; in that case `itemExtent` is ignored.
  result = RenderLazyList(direction: direction, itemCount: itemCount,
                          itemExtent: itemExtent, itemBuilder: itemBuilder,
                          extentFor: extentFor,
                          extentEstimate: extentEstimate,
                          items: initTable[int, RenderObject](),
                          elements: initTable[int, Element](),
                          firstVisible: -1, lastVisible: -1)
  if not extentFor.isNil:
    result.rebuildPrefixSums()

method performLayout*(r: RenderLazyList) =
  ## Two-phase: (1) call the base `RenderSliverList.performLayout`
  ## to compute the visible range and run its variable-extent /
  ## fixed-extent math; (2) mount any newly-visible items, unmount
  ## items that fell out, then ask the base to re-run layout if the
  ## pool changed (so newly-mounted children get measured).
  ##
  ## We use the base layout as a measurement of "what range do we
  ## need." When variable-extent items get mounted, their measured
  ## extents flow back into the prefix-sum cache and the next
  ## frame's layout (if any) reflects them.
  procCall performLayout(RenderSliverList(r))
  if r.firstVisible < 0: return

  # Drop items that fell out of range.
  var toDrop: seq[int]
  for idx in r.elements.keys:
    if idx < r.firstVisible or idx > r.lastVisible: toDrop.add(idx)
  for idx in toDrop:
    let elem = r.elements[idx]
    unmountElement(elem)
    r.elements.del(idx)
    r.items.del(idx)

  # Mount any items in range that aren't yet in the pool.
  var mountedAny = false
  for idx in r.firstVisible .. r.lastVisible:
    if not r.elements.hasKey(idx):
      let itemWidget = r.itemBuilder(idx)
      if itemWidget.isNil: continue
      let elem = mountElement(nil, itemWidget, idx)
      let ro = descendantRenderObj(elem)
      if ro.isNil:
        unmountElement(elem)
        continue
      r.elements[idx] = elem
      r.items[idx] = ro
      ro.parent = r
      mountedAny = true

  # If we mounted new items, the base layout already ran but
  # didn't have those children yet. Re-run so they're laid out
  # and their extents flow into the prefix sums (variable mode).
  if mountedAny:
    procCall performLayout(RenderSliverList(r))

method widgetTypeName*(w: ListViewBuilder): string = "ListViewBuilder"
method createElement*(w: ListViewBuilder): Element = newElement(ekRender, w)
method createRenderObject*(w: ListViewBuilder, ctx: BuildContext): RenderObject =
  newRenderLazyList(w.itemBuilder, w.itemCount, w.itemExtent, w.direction,
                    w.extentFor, w.extentEstimate)
method updateRenderObject*(w: ListViewBuilder, ctx: BuildContext, r: RenderObject) =
  let r2 = RenderLazyList(r)
  r2.itemBuilder = w.itemBuilder
  let configChanged =
    r2.itemCount != w.itemCount or r2.itemExtent != w.itemExtent or
    r2.direction != w.direction or
    (r2.extentFor.isNil != w.extentFor.isNil)
  if configChanged:
    r2.itemCount = w.itemCount
    r2.itemExtent = w.itemExtent
    r2.direction = w.direction
    r2.extentFor = w.extentFor
    r2.extentEstimate = w.extentEstimate
    for idx, elem in r2.elements:
      unmountElement(elem)
    r2.elements.clear()
    r2.items.clear()
    if not r2.extentFor.isNil:
      r2.rebuildPrefixSums()
    r2.markNeedsLayout()

proc listViewBuilder*(itemBuilder: proc(idx: int): Widget,
                     itemCount: int,
                     itemExtent: float32 = 0,
                     extentFor: proc(idx: int): float32 = nil,
                     extentEstimate: float32 = 0,
                     direction: Axis = axVertical,
                     key: Key = nil): ListViewBuilder =
  ## Builds a `ListViewBuilder`.
  ##
  ## Inputs:
  ## - `itemBuilder`: closure mapping an absolute item index to its
  ##   widget. Called lazily as items scroll into view; not called
  ##   for items outside the current visible range. Required.
  ## - `itemCount`: total number of items in the list. Cost scales
  ##   only with the visible range, not `itemCount`.
  ## - `itemExtent`: fixed pixel size of each item along
  ##   `direction`. Use this for uniform-height lists. Set to
  ##   zero (and pass `extentFor`) for variable-extent lists.
  ## - `extentFor`: callback returning the per-item extent.
  ##   Required for variable-extent lists. The sliver maintains a
  ##   prefix-sum cache keyed by index so scroll math stays
  ##   O(log itemCount) for offset-to-index queries.
  ## - `extentEstimate`: extent used for items we have not yet
  ##   measured (variable-extent mode). Determines scrollbar
  ##   geometry before items become visible.
  ## - `direction`: `axVertical` (default) or `axHorizontal`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: items in the visible range are mounted on demand;
  ## items outside the visible range get `unmount`ed. Scroll wheel
  ## events route to the underlying sliver via the standard viewport
  ## mechanism.
  ListViewBuilder(key: key, itemBuilder: itemBuilder,
                  itemCount: itemCount, itemExtent: itemExtent,
                  extentFor: extentFor, extentEstimate: extentEstimate,
                  direction: direction)
