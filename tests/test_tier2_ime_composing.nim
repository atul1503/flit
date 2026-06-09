## IME composing: handleComposingEvent routes composition updates
## to the focused node's onComposing handler.

import std/unittest
import ../src/flit/foundation/focus

suite "IME composing":
  test "handleComposingEvent calls focused node's onComposing":
    let m = FocusManager()
    var composing: string
    var cursor: int
    let n = newFocusNode()
    n.onComposing = proc(node: FocusNode, c: string, p: int) =
      composing = c
      cursor = p
    m.add(n)
    m.focus(n)
    m.handleComposingEvent("こん", 2)
    check composing == "こん"
    check cursor == 2

  test "handleComposingEvent without onComposing is a no-op":
    let m = FocusManager()
    let n = newFocusNode()
    m.add(n)
    m.focus(n)
    # No callback registered; should not crash.
    m.handleComposingEvent("test", 0)
    check true

  test "handleComposingEvent without focused node is a no-op":
    let m = FocusManager()
    m.handleComposingEvent("nope", 0)
    check m.current.isNil

  test "empty composing string indicates end of composition":
    let m = FocusManager()
    var seen: seq[string]
    let n = newFocusNode()
    n.onComposing = proc(node: FocusNode, c: string, p: int) =
      seen.add(c)
    m.add(n)
    m.focus(n)
    m.handleComposingEvent("ab", 2)
    m.handleComposingEvent("", 0)
    check seen == @["ab", ""]

  test "onComposing handler that throws does not crash dispatcher":
    let m = FocusManager()
    let n = newFocusNode()
    n.onComposing = proc(node: FocusNode, c: string, p: int) =
      raise newException(ValueError, "boom")
    m.add(n)
    m.focus(n)
    m.handleComposingEvent("x", 0)
    check true
