## TextField + TextEditingController tests. Focused on the
## controller logic since it's where bugs hide; the render side
## is covered by visual inspection during showcase use.

import std/unittest
import ../src/flit/widgets/text_field

suite "TextEditingController":
  test "insertText appends at cursor":
    let c = newTextEditingController("ab")
    c.cursor = 2
    c.selectionEnd = 2
    c.insertText("cd", 0)
    check c.text == "abcd"
    check c.cursor == 4

  test "insertText respects maxLength":
    let c = newTextEditingController("ab")
    c.cursor = 2
    c.selectionEnd = 2
    c.insertText("xxxxxx", 5)
    check c.text == "abxxx"

  test "insertText replaces selection":
    let c = newTextEditingController("hello world")
    c.cursor = 6
    c.selectionEnd = 11   # selecting "world"
    c.insertText("there", 0)
    check c.text == "hello there"
    check c.cursor == 11

  test "backspace removes one char left of cursor":
    let c = newTextEditingController("abc")
    c.cursor = 3
    c.selectionEnd = 3
    c.backspace()
    check c.text == "ab"
    check c.cursor == 2

  test "backspace with selection deletes the selection":
    let c = newTextEditingController("hello")
    c.cursor = 5
    c.selectionEnd = 2  # selecting "llo"
    c.backspace()
    check c.text == "he"
    check c.cursor == 2

  test "backspace at start of text is no-op":
    let c = newTextEditingController("hi")
    c.cursor = 0
    c.selectionEnd = 0
    c.backspace()
    check c.text == "hi"
    check c.cursor == 0

  test "forwardDelete removes char right of cursor":
    let c = newTextEditingController("abc")
    c.cursor = 0
    c.selectionEnd = 0
    c.forwardDelete()
    check c.text == "bc"

  test "moveLeft / moveRight clamp at bounds":
    let c = newTextEditingController("ab")
    c.cursor = 0; c.selectionEnd = 0
    c.moveLeft(false)
    check c.cursor == 0
    c.cursor = 2; c.selectionEnd = 2
    c.moveRight(false)
    check c.cursor == 2

  test "moveLeft with extend grows selection":
    let c = newTextEditingController("hello")
    c.cursor = 3; c.selectionEnd = 3
    c.moveLeft(true)
    check c.cursor == 2
    check c.selectionEnd == 3   # selectionEnd anchor unchanged

  test "moveHome/moveEnd":
    let c = newTextEditingController("hello")
    c.cursor = 3; c.selectionEnd = 3
    c.moveHome(false)
    check c.cursor == 0
    c.moveEnd(false)
    check c.cursor == 5

  test "value= clamps cursor":
    let c = newTextEditingController("hello")
    c.cursor = 5
    c.value = "hi"
    check c.text == "hi"
    check c.cursor == 2

  test "listeners fire on value=":
    let c = newTextEditingController("a")
    var got: string
    c.addListener(proc(v: string) = got = v)
    c.value = "b"
    check got == "b"

suite "TextField undo / redo / clipboard":
  test "undo walks back to previous state":
    let c = newTextEditingController("hello")
    c.cursor = 5; c.selectionEnd = 5
    c.insertText(" world", 0)
    check c.text == "hello world"
    discard c.undo()
    check c.text == "hello"

  test "redo walks forward after undo":
    let c = newTextEditingController("a")
    c.cursor = 1; c.selectionEnd = 1
    c.insertText("b", 0)
    check c.text == "ab"
    discard c.undo()
    check c.text == "a"
    discard c.redo()
    check c.text == "ab"

  test "undo returns false when history empty":
    let c = newTextEditingController("x")
    check (not c.undo())

  test "new edit clears redo branch":
    let c = newTextEditingController("a")
    c.cursor = 1; c.selectionEnd = 1
    c.insertText("b", 0)
    discard c.undo()
    # New edit at this point: redo branch should be invalidated.
    c.insertText("c", 0)
    check (not c.redo())

  test "selectAll selects the whole text":
    let c = newTextEditingController("hello")
    c.selectAll()
    check c.hasSelection
    check c.selectionRange == (0, 5)

  test "copyToString returns selected range":
    let c = newTextEditingController("hello world")
    c.cursor = 0
    c.selectionEnd = 5
    check c.copyToString() == "hello"

  test "deleteSelectionWithUndo records undo":
    let c = newTextEditingController("hello world")
    c.cursor = 0
    c.selectionEnd = 5
    check c.deleteSelectionWithUndo()
    check c.text == " world"
    discard c.undo()
    check c.text == "hello world"

  test "snapshot / restore round-trips":
    let c = newTextEditingController("abc")
    c.cursor = 1
    c.selectionEnd = 3
    let snap = c.snapshot
    c.text = "xyz"; c.cursor = 0; c.selectionEnd = 0
    c.restore(snap)
    check c.text == "abc"
    check c.cursor == 1
    check c.selectionEnd == 3

suite "TextField UTF-8 handling":
  test "backspace removes a full multi-byte codepoint (accented char)":
    # 'é' is 2 bytes in UTF-8 (0xC3 0xA9).
    let c = newTextEditingController("café")
    check c.text.len == 5   # 4 ASCII chars + 1 byte for é = 5? no
    # Actually café = c, a, f, é = c(1) + a(1) + f(1) + é(2) = 5 bytes
    c.cursor = 5; c.selectionEnd = 5
    c.backspace()
    check c.text == "caf"   # full é gone, not just one byte
    check c.cursor == 3

  test "backspace on emoji removes all 4 bytes":
    # '👋' is 4 bytes in UTF-8 (0xF0 0x9F 0x91 0x8B).
    let c = newTextEditingController("hi👋")
    let initialLen = c.text.len  # 2 + 4 = 6
    check initialLen == 6
    c.cursor = initialLen; c.selectionEnd = initialLen
    c.backspace()
    check c.text == "hi"
    check c.cursor == 2

  test "forwardDelete removes a full multi-byte codepoint":
    let c = newTextEditingController("éclair")
    c.cursor = 0; c.selectionEnd = 0
    c.forwardDelete()
    check c.text == "clair"   # full é gone
    check c.cursor == 0

  test "moveRight advances by full codepoint":
    let c = newTextEditingController("a😀b")
    c.cursor = 0; c.selectionEnd = 0
    c.moveRight(false)
    check c.cursor == 1   # past 'a'
    c.moveRight(false)
    check c.cursor == 5   # past '😀' (4 bytes)
    c.moveRight(false)
    check c.cursor == 6   # past 'b'

  test "moveLeft retreats by full codepoint":
    let c = newTextEditingController("a😀b")
    c.cursor = c.text.len; c.selectionEnd = c.text.len
    c.moveLeft(false)
    check c.cursor == 5   # back to start of 'b'
    c.moveLeft(false)
    check c.cursor == 1   # back to start of '😀'
    c.moveLeft(false)
    check c.cursor == 0   # back to start of 'a'

  test "insertText with multi-byte content is preserved":
    let c = newTextEditingController("hello ")
    c.cursor = 6; c.selectionEnd = 6
    c.insertText("世界", 0)
    check c.text == "hello 世界"
    # cursor advanced by byte length of the inserted UTF-8 (6 bytes)
    check c.cursor == 12

  test "mixed editing: type, navigate, delete with emoji":
    let c = newTextEditingController("")
    c.insertText("a🎉b", 0)
    check c.text == "a🎉b"
    c.moveLeft(false)              # before 'b'
    c.moveLeft(false)              # before 🎉
    c.forwardDelete()              # remove 🎉
    check c.text == "ab"
    check c.cursor == 1
