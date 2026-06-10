## ScrollController tests: programmatic scrolling added for the
## chat-app archetype (scroll-to-bottom on new messages).

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/rendering/viewport

proc tallContent(n: int): Widget =
  ## n rows of 50px = n*50 total height.
  var rows: seq[Widget]
  for i in 0 ..< n:
    rows.add(container(height = 50, hasColor = true,
      color = (if i mod 2 == 0: colorBlue else: colorRed)))
  column(crossAxisAlignment = caStretch, mainAxisSize = msMin,
         children = rows)

suite "ScrollController":
  test "unattached controller reads safely":
    let sc = newScrollController()
    check sc.offset == 0.0'f32
    check sc.atEnd          # nothing to scroll = at end

  test "controller attaches to the viewport on mount":
    let sc = newScrollController()
    let root = mountElement(nil,
      scrollView(controller = sc, child = tallContent(20)), 0)
    runLayout(root, tightFor(400, 300))
    check not sc.viewport.isNil
    # 20 * 50 = 1000 content, 300 viewport -> 700 max scroll.
    check sc.viewport.maxScroll == 700.0'f32

  test "jumpTo scrolls and clamps":
    let sc = newScrollController()
    let root = mountElement(nil,
      scrollView(controller = sc, child = tallContent(20)), 0)
    runLayout(root, tightFor(400, 300))
    sc.jumpTo(150)
    check sc.offset == 150.0'f32
    sc.jumpTo(99999)
    check sc.offset == 700.0'f32   # clamped to maxScroll
    sc.jumpTo(-50)
    check sc.offset == 0.0'f32     # clamped to zero

  test "scrollToEnd lands on the bottom":
    let sc = newScrollController()
    let root = mountElement(nil,
      scrollView(controller = sc, child = tallContent(20)), 0)
    runLayout(root, tightFor(400, 300))
    sc.scrollToEnd()
    check sc.offset == 700.0'f32
    check sc.atEnd

  test "scrollToEnd before layout applies after layout (append + stick pattern)":
    # The chat pattern: request scrollToEnd in the same frame that
    # appends content. The pending request must resolve against the
    # NEW maxScroll, not the stale one.
    let sc = newScrollController()
    let root = mountElement(nil,
      scrollView(controller = sc, child = tallContent(20)), 0)
    runLayout(root, tightFor(400, 300))
    check sc.viewport.maxScroll == 700.0'f32
    # Simulate content growth: mount a bigger tree into the same
    # controller, request end BEFORE the layout pass.
    let root2 = mountElement(nil,
      scrollView(controller = sc, child = tallContent(40)), 0)
    sc.scrollToEnd()
    runLayout(root2, tightFor(400, 300))
    # 40 * 50 = 2000 content -> 1700 max scroll.
    check sc.viewport.maxScroll == 1700.0'f32
    check sc.offset == 1700.0'f32
    check sc.atEnd

  test "atEnd is false mid-scroll":
    let sc = newScrollController()
    let root = mountElement(nil,
      scrollView(controller = sc, child = tallContent(20)), 0)
    runLayout(root, tightFor(400, 300))
    sc.jumpTo(100)
    check not sc.atEnd
