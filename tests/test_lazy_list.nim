## ListView.builder tests. Verifies the core perf property: only
## items in the visible range are built, and items that scroll out
## of range get unmounted.

import std/[unittest, tables]
import ../src/flit
import ../src/flit/foundation/[runtime, render_object]
import ../src/flit/widgets/lazy_list
import ../src/flit/rendering/sliver_list

suite "ListView.builder laziness":
  test "only items in the visible range get built":
    var builds: seq[int]
    let widget = listViewBuilder(
      itemCount = 1000,
      itemExtent = 50.0,
      itemBuilder = proc(idx: int): Widget =
        builds.add(idx)
        sizedBox(width = 200, height = 50))
    let root = mountElement(nil, widget, 0)
    # 400px viewport / 50px extent = 8 items, plus pre/post buffer (~3) = ~11.
    runLayout(root, tightFor(200, 400))
    # We should have built around the first 11 items, NOT all 1000.
    check builds.len < 30
    check builds.len > 0

  test "itemBuilder is not called for items beyond the viewport":
    var maxIdx = -1
    let widget = listViewBuilder(
      itemCount = 10_000,
      itemExtent = 60.0,
      itemBuilder = proc(idx: int): Widget =
        if idx > maxIdx: maxIdx = idx
        sizedBox(width = 100, height = 60))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(300, 300))
    # Should top out around (300 / 60) + 3 buffer = 8 items
    check maxIdx < 20
    check maxIdx >= 0

  test "scrolling reveals new items lazily":
    var builds: seq[int]
    let widget = listViewBuilder(
      itemCount = 500,
      itemExtent = 40.0,
      itemBuilder = proc(idx: int): Widget =
        builds.add(idx)
        sizedBox(width = 100, height = 40))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 200))
    let initial = builds.len
    check initial > 0

    # Find the render object and simulate a scroll.
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    sliver.scrollOffset = 200.0  # Skip about 5 items
    sliver.markNeedsLayout()
    runLayout(root, tightFor(200, 200))

    # Builder should have been called for items further down the
    # list that weren't in the original visible window.
    var sawHigher = false
    for idx in builds:
      if idx > 8:
        sawHigher = true
        break
    check sawHigher

  test "scrolling far drops out-of-range items from the pool":
    let widget = listViewBuilder(
      itemCount = 1000,
      itemExtent = 50.0,
      itemBuilder = proc(idx: int): Widget =
        sizedBox(width = 100, height = 50))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 200))
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    let initialPool = sliver.elements.len
    check initialPool > 0
    # Jump scroll to mid-list.
    sliver.scrollOffset = 25000.0
    sliver.markNeedsLayout()
    runLayout(root, tightFor(200, 200))
    # The pool should NOT have grown to thousands; old items
    # should have been dropped.
    check sliver.elements.len < 30
    # And the index range should reflect the new position.
    check sliver.firstVisible >= 400

  test "scrollbar geometry uses full content extent":
    let widget = listViewBuilder(
      itemCount = 10_000,
      itemExtent = 40.0,
      itemBuilder = proc(idx: int): Widget =
        sizedBox(width = 100, height = 40))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 400))
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    check sliver.maxScroll == 399600.0'f32

suite "ListView.builder variable extent":
  test "items report different extents via extentFor":
    var builds: seq[int]
    let widget = listViewBuilder(
      itemCount = 100,
      extentFor = proc(idx: int): float32 =
        if idx mod 2 == 0: 40.0'f32 else: 60.0'f32,
      extentEstimate = 50.0,
      itemBuilder = proc(idx: int): Widget =
        builds.add(idx)
        sizedBox(width = 100, height = if idx mod 2 == 0: 40.0 else: 60.0))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 400))
    # Should still be lazy: only enough items to fill the viewport,
    # not all 100.
    check builds.len < 30
    check builds.len > 0

  test "offsetOfIndex returns cumulative extent for variable lists":
    let widget = listViewBuilder(
      itemCount = 10,
      extentFor = proc(idx: int): float32 =
        if idx < 5: 30.0'f32 else: 70.0'f32,
      extentEstimate = 50.0,
      itemBuilder = proc(idx: int): Widget =
        sizedBox(width = 100, height = if idx < 5: 30.0 else: 70.0))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 1000))  # tall enough to see all
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    # After layout, items 0..n should be measured. Item 5 starts
    # at offset 5*30 = 150 (after layout has measured them).
    check sliver.offsetOfIndex(0) == 0.0'f32
    check sliver.offsetOfIndex(5) == 150.0'f32  # 5 * 30
    check sliver.offsetOfIndex(10) == 500.0'f32  # 5*30 + 5*70

  test "maxScroll uses measured prefix-sum total":
    let widget = listViewBuilder(
      itemCount = 10,
      extentFor = proc(idx: int): float32 =
        if idx < 5: 30.0'f32 else: 70.0'f32,
      extentEstimate = 50.0,
      itemBuilder = proc(idx: int): Widget =
        sizedBox(width = 100, height = if idx < 5: 30.0 else: 70.0))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 1000))
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    # Total content = 5*30 + 5*70 = 500. Viewport = 1000. So
    # maxScroll clamps to 0 (everything fits).
    check sliver.maxScroll == 0.0'f32

  test "fixed-extent path unchanged when extentFor is nil":
    let widget = listViewBuilder(
      itemCount = 100,
      itemExtent = 40.0,
      itemBuilder = proc(idx: int): Widget =
        sizedBox(width = 100, height = 40))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 400))
    let rE = descendantRenderElement(root)
    let sliver = RenderLazyList(rE.renderObj)
    # 100 * 40 = 4000 total, viewport 400, maxScroll = 3600.
    check sliver.maxScroll == 3600.0'f32
    check sliver.extentFor.isNil
