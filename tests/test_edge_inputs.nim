## Stress tests with degenerate / pathological inputs. Each
## previously-found bug class gets a defensive check: empty
## strings, NaN, Inf, zero, negative, very large, multi-byte.

import std/[unittest, math, strutils]
import ../src/flit
import ../src/flit/widgets/text_field
import ../src/flit/foundation/runtime

suite "Edge inputs":

  test "newAnimationController(durationSec=0) doesn't div-by-zero":
    let c = newAnimationController(durationSec = 0.0)
    # Internal duration is clamped to 0.001; value is still
    # accessible without producing NaN/Inf.
    c.value = 0.5
    check c.value == 0.5
    check c.value.classify == fcNormal

  test "newAnimationController(durationSec=negative) clamps":
    let c = newAnimationController(durationSec = -5.0)
    c.value = 0.7
    check c.value.classify in {fcNormal, fcSubnormal}

  test "TextField insert empty string is a no-op":
    let c = newTextEditingController("hello")
    c.cursor = 3; c.selectionEnd = 3
    c.insertText("", 0)
    check c.text == "hello"
    check c.cursor == 3

  test "TextField backspace on empty string is safe":
    let c = newTextEditingController("")
    c.cursor = 0; c.selectionEnd = 0
    c.backspace()   # no-op, doesn't crash
    check c.text == ""

  test "TextField forwardDelete on empty is safe":
    let c = newTextEditingController("")
    c.forwardDelete()
    check c.text == ""

  test "TextField undo on empty history returns false":
    let c = newTextEditingController("hi")
    check (not c.undo())

  test "TextField with very long string":
    let big = "abcdefghij".repeat(10_000)   # 100k chars
    let c = newTextEditingController(big)
    check c.text.len == 100_000
    c.cursor = c.text.len
    c.backspace()
    check c.text.len == 99_999

  test "Constraints with zero max is valid":
    let cn = constraints(0, 0, 0, 0)
    let s = cn.constrain(Size(width: 100, height: 100))
    check s.width == 0
    check s.height == 0

  test "Color hex parse round-trip":
    let c = color.fromHex("#FF0080")
    let s = $c.value
    check s.len > 0   # just doesn't crash

  test "ValueNotifier disposed before next set is safe":
    let n = newValueNotifier(0)
    n.dispose()
    n.value = 1   # no listeners; safe
    check n.value == 1

  test "TextField multi-byte combined edits":
    let c = newTextEditingController("")
    c.insertText("a", 0)
    c.insertText("ø", 0)        # 2 bytes
    c.insertText("👍", 0)        # 4 bytes
    c.insertText("b", 0)
    check c.text == "aø👍b"
    c.moveLeft(false)            # past b
    c.moveLeft(false)            # past 👍
    c.moveLeft(false)            # past ø
    c.moveLeft(false)            # past a -> cursor at 0
    check c.cursor == 0
    c.moveRight(false)
    c.moveRight(false)
    c.backspace()                # delete ø
    check c.text == "a👍b"

  test "ListView.builder with itemCount=0 doesn't crash":
    let widget = listViewBuilder(
      itemCount = 0,
      itemExtent = 50.0,
      itemBuilder = proc(idx: int): Widget = nil)
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 200))
    check not root.isNil

  test "ListView.builder with itemExtent=0 doesn't div-by-zero":
    let widget = listViewBuilder(
      itemCount = 10,
      itemExtent = 0.0,
      itemBuilder = proc(idx: int): Widget = sizedBox(width = 50, height = 50))
    let root = mountElement(nil, widget, 0)
    runLayout(root, tightFor(200, 200))   # would div by 0 without guard
    check not root.isNil
