## Widget framework smoke tests. Build a tree, mount it, and walk it.

import std/unittest
import ../src/flit/foundation/[widget, key, geometry, color, render_object, runtime]
import ../src/flit/widgets/basic
import ../src/flit/rendering/[proxy_box, flex]

suite "Widget mount":
  test "stateless widget produces an element with one child":
    let t = text("hello")
    let e = mountElement(nil, t, 0)
    check e.kind == ekRender
    check not e.renderObj.isNil

  test "column with two children":
    let c = column(children = @[
      Widget(text("a")), Widget(text("b"))])
    let e = mountElement(nil, c, 0)
    check e.kind == ekRender
    check e.children.len == 2

suite "Key equality":
  test "value keys with same content are equal":
    check newValueKey("x") == newValueKey("x")
    check newValueKey("x") != newValueKey("y")
  test "unique keys never collide":
    check newUniqueKey() != newUniqueKey()

suite "Color helpers":
  test "withOpacity scales alpha":
    let c = colorRed.withOpacity(0.5)
    check c.alpha >= 126 and c.alpha <= 128
  test "fromHex round-trip":
    check fromHex("#FF112233").value == 0xFF112233'u32

when isMainModule: discard
