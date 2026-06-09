## Navigator route-stack tests.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/widgets/navigator as nav_widget

suite "Navigator":
  test "depth starts at 1 (just the initial route)":
    let app = navigator(proc(): Widget = text("home"))
    let root = mountElement(nil, app, 0)
    check currentNavigator().depth == 1
    discard root

  test "push grows the stack":
    let app = navigator(proc(): Widget = text("home"))
    discard mountElement(nil, app, 0)
    let h = currentNavigator()
    check h.depth == 1
    h.push(proc(): Widget = text("detail"))
    check h.depth == 2

  test "pop removes the top route":
    let app = navigator(proc(): Widget = text("home"))
    discard mountElement(nil, app, 0)
    let h = currentNavigator()
    h.push(proc(): Widget = text("detail"))
    h.pop()
    check h.depth == 1

  test "pop on the initial route is a no-op":
    let app = navigator(proc(): Widget = text("home"))
    discard mountElement(nil, app, 0)
    let h = currentNavigator()
    h.pop()
    check h.depth == 1

  test "popUntil trims to the requested depth":
    let app = navigator(proc(): Widget = text("home"))
    discard mountElement(nil, app, 0)
    let h = currentNavigator()
    h.push(proc(): Widget = text("a"))
    h.push(proc(): Widget = text("b"))
    h.push(proc(): Widget = text("c"))
    check h.depth == 4
    h.popUntil(2)
    check h.depth == 2

  test "pushReplacement does not grow the stack":
    let app = navigator(proc(): Widget = text("home"))
    discard mountElement(nil, app, 0)
    let h = currentNavigator()
    h.push(proc(): Widget = text("a"))
    check h.depth == 2
    h.pushReplacement(proc(): Widget = text("b"))
    check h.depth == 2
