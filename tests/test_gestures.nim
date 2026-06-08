## Gesture dispatch test. Mounts a widget tree with a tap callback, simulates
## a Down/Up pointer pair, and verifies the callback fired.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/foundation/binding

suite "Gesture dispatch":
  test "tap on GestureDetector invokes onTap":
    var tapped = 0
    let tree = center(
      child = gestureDetector(
        onTap = (proc() = inc tapped),
        behavior = htOpaque,
        child = decoratedBox(
          decoration = boxDecoration(color = colorRed),
          child = sizedBox(width = 100, height = 50))))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(400, 300))
    # Center of 400x300 surface puts the 100x50 box at roughly
    # (150, 125) - (250, 175). Tap dead center.
    let canvas = Canvas(size: Size(width: 400, height: 300))
    let b = newBinding(canvas, Size(width: 400, height: 300))
    b.rootElement = root
    b.dispatchPointer(PointerEvent(kind: peDown,
                                   position: Offset(dx: 200, dy: 150)))
    b.dispatchPointer(PointerEvent(kind: peUp,
                                   position: Offset(dx: 201, dy: 150)))
    processPointerEvents(b)
    check tapped == 1

  test "tap outside the GestureDetector does not invoke onTap":
    var tapped = 0
    let tree = center(
      child = gestureDetector(
        onTap = (proc() = inc tapped),
        behavior = htOpaque,
        child = sizedBox(width = 40, height = 40,
          child = coloredBox(color = colorBlue))))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(400, 300))
    let canvas = Canvas(size: Size(width: 400, height: 300))
    let b = newBinding(canvas, Size(width: 400, height: 300))
    b.rootElement = root
    # Tap a corner well outside the 40x40 centered box.
    b.dispatchPointer(PointerEvent(kind: peDown,
                                   position: Offset(dx: 10, dy: 10)))
    b.dispatchPointer(PointerEvent(kind: peUp,
                                   position: Offset(dx: 11, dy: 11)))
    processPointerEvents(b)
    check tapped == 0

  test "pan delivers Update + End even when finger leaves the widget":
    var moves = 0
    var ended = 0
    let tree = center(
      child = gestureDetector(
        onPanUpdate = (proc(delta, position: Offset) = inc moves),
        onPanEnd = (proc() = inc ended),
        behavior = htOpaque,
        child = sizedBox(width = 100, height = 50,
          child = coloredBox(color = colorGreen))))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(400, 300))
    let canvas = Canvas(size: Size(width: 400, height: 300))
    let b = newBinding(canvas, Size(width: 400, height: 300))
    b.rootElement = root
    b.dispatchPointer(PointerEvent(kind: peDown,
                                   position: Offset(dx: 200, dy: 150)))
    # Several moves crossing outside the box; capture should keep firing.
    for i in 0 ..< 5:
      b.dispatchPointer(PointerEvent(kind: peMove,
                                     position: Offset(dx: float32(200 + i*30),
                                                      dy: float32(150 + i*5))))
    b.dispatchPointer(PointerEvent(kind: peUp,
                                   position: Offset(dx: 400, dy: 200)))
    processPointerEvents(b)
    check moves >= 1
    check ended == 1

suite "Double tap":
  test "two taps within 300ms fire onDoubleTap, not onTap twice":
    var taps = 0
    var doubles = 0
    let tree = center(
      child = gestureDetector(
        onTap = (proc() = inc taps),
        onDoubleTap = (proc() = inc doubles),
        behavior = htOpaque,
        child = sizedBox(width = 100, height = 50,
          child = coloredBox(color = colorRed))))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(400, 300))
    let canvas = Canvas(size: Size(width: 400, height: 300))
    let b = newBinding(canvas, Size(width: 400, height: 300))
    b.rootElement = root
    # First tap
    b.dispatchPointer(PointerEvent(kind: peDown, position: Offset(dx: 200, dy: 150)))
    b.dispatchPointer(PointerEvent(kind: peUp,   position: Offset(dx: 200, dy: 150)))
    processPointerEvents(b)
    check taps == 1
    check doubles == 0
    # Second tap immediately after - within 300ms window.
    b.dispatchPointer(PointerEvent(kind: peDown, position: Offset(dx: 200, dy: 150)))
    b.dispatchPointer(PointerEvent(kind: peUp,   position: Offset(dx: 200, dy: 150)))
    processPointerEvents(b)
    check doubles == 1
    check taps == 1  # the second tap is consumed by onDoubleTap

when isMainModule: discard
