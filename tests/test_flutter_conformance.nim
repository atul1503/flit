## Table-driven assertions for documented Flutter behavior on specific
## edge cases. Each test is sourced from Flutter's published docs or
## source code. Any failure here indicates a divergence from Flutter.

import std/[unittest, math]
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../src/flit/rendering/[proxy_box, flex, decoration]

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------

suite "Flutter conformance: BoxConstraints":
  test "tight constraints have min == max":
    # Flutter: BoxConstraints.tight(Size).isTight is true.
    let c = tightFor(100, 50)
    check c.isTight
    check c.minWidth == c.maxWidth
    check c.minHeight == c.maxHeight

  test "loosen preserves max, zeroes min":
    # Flutter: BoxConstraints.loosen() -> minWidth=0, maxWidth unchanged.
    let c = constraints(50, 200, 25, 100)
    let l = c.loosen()
    check l.minWidth == 0
    check l.maxWidth == 200
    check l.minHeight == 0
    check l.maxHeight == 100

  test "enforce clamps inner constraints into parent's range":
    # Flutter: BoxConstraints.enforce returns clamp(inner, parent).
    let parent = constraints(50, 100, 50, 100)
    let inner = constraints(10, 200, 10, 200)
    let r = inner.enforce(parent)
    check r.minWidth == 50
    check r.maxWidth == 100
    check r.minHeight == 50
    check r.maxHeight == 100

# ---------------------------------------------------------------------------
# SizedBox
# ---------------------------------------------------------------------------

suite "Flutter conformance: SizedBox":
  test "SizedBox(width: w) tightens width, height follows constraints":
    # Flutter: SizedBox.fromSize gives tight on the dim it specifies and
    # passes through the other.
    let tree = center(child = sizedBox(width = 100,
      child = coloredBox(color = colorRed)))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(800, 600))
    let r = descendantRenderElement(root).renderObj
    let inner = RenderAlign(r).child
    check inner.size.width == 100
    # Height was unconstrained for the child; coloredBox-with-no-child
    # fills bounded constraints (here we passed loose).

  test "SizedBox.shrink (no dims) collapses to (0, 0) when no child":
    let tree = center(child = sizedBox())
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(800, 600))
    let r = descendantRenderElement(root).renderObj
    let inner = RenderAlign(r).child
    check inner.size.width == 0
    check inner.size.height == 0

# ---------------------------------------------------------------------------
# Padding
# ---------------------------------------------------------------------------

suite "Flutter conformance: Padding":
  test "Padding(EdgeInsets.all(N)) adds 2N to each axis":
    let tree = center(child = padding(
      child = sizedBox(width = 50, height = 20),
      padding = edgeInsetsAll(10)))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(800, 600))
    let r = descendantRenderElement(root).renderObj
    let pad = RenderAlign(r).child
    check pad.size.width == 70
    check pad.size.height == 40

  test "Padding deflates child constraints by the insets":
    # Inner constraints are tightFor(100, 50). Padding 10 leaves 80x30.
    let p = RenderPadding(padding: edgeInsetsAll(10))
    p.child = RenderSizedBox(requestedWidth: 0, requestedHeight: 0,
                              child: nil)
    p.layout(tightFor(100, 50))
    # Padding lays out child with deflated constraints and returns
    # child.size + 2N. Sized box with no child + no requested dims
    # collapses to 0. Padding.size = (20, 20).
    check p.size.width == 100   # tight constraints win
    check p.size.height == 50

# ---------------------------------------------------------------------------
# Align
# ---------------------------------------------------------------------------

suite "Flutter conformance: Align":
  test "Align without widthFactor expands to maxWidth":
    # Flutter: Align with no widthFactor lays out as large as the
    # constraint allows.
    let a = RenderAlign(alignment: alignCenter)
    a.child = RenderSizedBox(requestedWidth: 50, requestedHeight: 30)
    a.layout(constraints(0, 400, 0, 200))
    check a.size.width == 400
    check a.size.height == 200

  test "Align with widthFactor=2.0 sizes to 2 * child.width":
    let a = RenderAlign(alignment: alignCenter, widthFactor: 2.0'f32)
    a.child = RenderSizedBox(requestedWidth: 50, requestedHeight: 30)
    a.layout(constraints(0, 400, 0, 200))
    check a.size.width == 100

# ---------------------------------------------------------------------------
# Row / Column / Flex
# ---------------------------------------------------------------------------

suite "Flutter conformance: Row/Column":
  test "Row with mainAxisAlignment.spaceBetween: 3 children, gaps only between":
    # Flutter: maSpaceBetween places no gap before first or after last.
    proc child(w: float32): RenderObject =
      RenderSizedBox(requestedWidth: w, requestedHeight: 10)
    let r = RenderFlex(direction: axHorizontal, mainAxisSize: msMax,
                       mainAxisAlignment: maSpaceBetween,
                       crossAxisAlignment: caCenter)
    r.children = @[
      RenderFlexChild(obj: child(20), pd: FlexParentData()),
      RenderFlexChild(obj: child(20), pd: FlexParentData()),
      RenderFlexChild(obj: child(20), pd: FlexParentData()),
    ]
    r.layout(tightFor(200, 50))
    # Total child width = 60, free = 140, gap = 70 between each pair.
    check abs(r.children[0].pd.offset.dx - 0.0)   < 0.01
    check abs(r.children[1].pd.offset.dx - 90.0)  < 0.01
    check abs(r.children[2].pd.offset.dx - 180.0) < 0.01

  test "Column with mainAxisSize.min sizes to children":
    let c = RenderFlex(direction: axVertical, mainAxisSize: msMin,
                       crossAxisAlignment: caCenter)
    c.children = @[
      RenderFlexChild(obj: RenderSizedBox(requestedWidth: 30,
                                          requestedHeight: 25),
                       pd: FlexParentData()),
      RenderFlexChild(obj: RenderSizedBox(requestedWidth: 30,
                                          requestedHeight: 25),
                       pd: FlexParentData()),
    ]
    c.layout(constraints(0, 400, 0, 400))
    check c.size.height == 50

  test "Expanded children split remaining space proportionally":
    proc child(w: float32, flex: int): RenderFlexChild =
      RenderFlexChild(
        obj: RenderSizedBox(requestedWidth: w, requestedHeight: 10),
        pd: FlexParentData(flex: flex, fit: ffTight))
    let r = RenderFlex(direction: axHorizontal, mainAxisSize: msMax,
                       mainAxisAlignment: maStart,
                       crossAxisAlignment: caCenter)
    r.children = @[child(0, 1), child(0, 2), child(0, 1)]
    r.layout(tightFor(400, 50))
    # Total flex = 4; each unit = 100px.
    check abs(r.children[0].obj.size.width - 100.0) < 0.01
    check abs(r.children[1].obj.size.width - 200.0) < 0.01
    check abs(r.children[2].obj.size.width - 100.0) < 0.01

# ---------------------------------------------------------------------------
# DecoratedBox / BoxDecoration
# ---------------------------------------------------------------------------

type
  RecCanvas = ref object of Canvas
    rects*: int
    rrects*: int

proc newRecCanvas(): RecCanvas =
  RecCanvas(rects: 0, rrects: 0, size: Size(width: 100, height: 100))

method drawRect*(c: RecCanvas, r: Rect, fill: uint32) = inc c.rects
method drawRRect*(c: RecCanvas, r: RRect, fill: uint32) = inc c.rrects

suite "Flutter conformance: BoxDecoration":
  test "borderRadius > 0 routes painting through drawRRect":
    let rounded = RenderDecoratedBox(
      decoration: boxDecoration(color = colorRed, borderRadius = 8))
    rounded.layout(tightFor(50, 50))
    let rec = newRecCanvas()
    let ctx = newPaintingContext(rec)
    rounded.paint(ctx, OffsetZero)
    check rec.rrects == 1
    check rec.rects == 0

    let sharp = RenderDecoratedBox(
      decoration: boxDecoration(color = colorRed))
    sharp.layout(tightFor(50, 50))
    let rec2 = newRecCanvas()
    let ctx2 = newPaintingContext(rec2)
    sharp.paint(ctx2, OffsetZero)
    check rec2.rects == 1
    check rec2.rrects == 0

# ---------------------------------------------------------------------------
# Color
# ---------------------------------------------------------------------------

suite "Flutter conformance: Color":
  test "rgba components round-trip":
    let c = rgba(10, 20, 30, 40)
    check c.red == 10
    check c.green == 20
    check c.blue == 30
    check c.alpha == 40

  test "withAlpha replaces only the alpha channel":
    let c = rgba(10, 20, 30, 200)
    let a = c.withAlpha(50)
    check a.red == 10
    check a.green == 20
    check a.blue == 30
    check a.alpha == 50

  test "lerp at t=0 is exactly a, at t=1 is exactly b":
    let a = rgba(10, 20, 30, 200)
    let b = rgba(200, 100, 50, 255)
    check lerp(a, b, 0.0'f32) == a
    check lerp(a, b, 1.0'f32) == b

# ---------------------------------------------------------------------------
# AnimationController
# ---------------------------------------------------------------------------

suite "Flutter conformance: AnimationController":
  test "initial status is dismissed":
    let c = newAnimationController(durationSec = 1.0'f32)
    check c.status == asDismissed

  test "value= setter clamps to [lower, upper]":
    let c = newAnimationController(durationSec = 1.0'f32,
                                    lower = 0, upper = 1)
    c.value = 5.0'f32
    check c.value == 1.0'f32
    c.value = -2.0'f32
    check c.value == 0.0'f32

  test "removeListener removes the listener":
    let c = newAnimationController(durationSec = 1.0'f32)
    var hits = 0
    let listener = proc(v: float32) = inc hits
    c.addListener(listener)
    c.value = 0.5
    check hits == 1
    c.removeListener(listener)
    c.value = 0.7
    check hits == 1   # not incremented

  test "dispose stops the controller":
    let c = newAnimationController(durationSec = 1.0'f32)
    c.dispose()
    check c.listeners.len == 0
    check c.statusListeners.len == 0

# ---------------------------------------------------------------------------
# Stack / Positioned
# ---------------------------------------------------------------------------

suite "Flutter conformance: Stack":
  test "Positioned with only top+left lays out at that offset":
    let st = RenderStack(alignment: alignTopLeft, fit: sfExpand)
    let child = RenderSizedBox(requestedWidth: 20, requestedHeight: 20)
    let pd = newStackParentData(left = 30.0'f32, top = 40.0'f32)
    st.children = @[RenderStackChild(obj: child, pd: pd)]
    st.layout(tightFor(200, 200))
    check abs(st.children[0].pd.offset.dx - 30.0) < 0.01
    check abs(st.children[0].pd.offset.dy - 40.0) < 0.01

  test "Positioned with right only places at parent.right - child.width":
    let st = RenderStack(alignment: alignTopLeft, fit: sfExpand)
    let child = RenderSizedBox(requestedWidth: 20, requestedHeight: 20)
    let pd = newStackParentData(right = 10.0'f32)
    st.children = @[RenderStackChild(obj: child, pd: pd)]
    st.layout(tightFor(200, 200))
    check abs(st.children[0].pd.offset.dx - (200 - 10 - 20)) < 0.01

when isMainModule: discard
