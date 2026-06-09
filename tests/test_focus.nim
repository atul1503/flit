## FocusManager tests. Verifies registration, focus transitions,
## traversal, and key dispatch routing.

import std/unittest
import ../src/flit/foundation/[focus, binding]

suite "FocusManager":
  test "add registers a node":
    let m = FocusManager()
    let n = newFocusNode()
    m.add(n)
    check m.nodes.len == 1

  test "focus transitions hasFocus + fires onFocusChange":
    let m = FocusManager()
    var got: seq[bool]
    let n = newFocusNode(onFocusChange = proc(f: bool) = got.add(f))
    m.add(n)
    m.focus(n)
    check n.hasFocus
    check got == @[true]
    m.unfocus()
    check (not n.hasFocus)
    check got == @[true, false]

  test "next cycles through registered nodes":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    let c = newFocusNode()
    m.add(a); m.add(b); m.add(c)
    m.focus(a)
    m.next(); check m.current == b
    m.next(); check m.current == c
    m.next(); check m.current == a  # wraps

  test "prev cycles backwards":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    let c = newFocusNode()
    m.add(a); m.add(b); m.add(c)
    m.focus(a)
    m.prev(); check m.current == c  # wraps backwards

  test "next skips disabled nodes":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    let c = newFocusNode()
    b.enabled = false
    m.add(a); m.add(b); m.add(c)
    m.focus(a)
    m.next(); check m.current == c   # b skipped

  test "handleKeyEvent: Tab cycles":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    m.add(a); m.add(b)
    m.focus(a)
    let handled = m.handleKeyEvent(KeyEvent(kind: keDown, keyCode: 9))
    check handled
    check m.current == b

  test "handleKeyEvent: Shift+Tab cycles backwards":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    m.add(a); m.add(b)
    m.focus(a)
    let handled = m.handleKeyEvent(
      KeyEvent(kind: keDown, keyCode: 9, modifiers: 0x0001))
    check handled
    check m.current == b  # wraps backwards from index 0

  test "handleKeyEvent: text events reach onText":
    let m = FocusManager()
    var captured: string
    let n = newFocusNode(onText = proc(node: FocusNode, t: string) = captured = t)
    m.add(n)
    m.focus(n)
    discard m.handleKeyEvent(KeyEvent(kind: keDown, text: "x"))
    check captured == "x"

  test "remove drops the node and clears focus if it was focused":
    let m = FocusManager()
    let n = newFocusNode()
    m.add(n)
    m.focus(n)
    m.remove(n)
    check m.current.isNil
    check (not n.hasFocus)
