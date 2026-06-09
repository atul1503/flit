## TextField extensions in 0.10.0: multiline editing, obscureText
## password rendering, maxLines clamp.

import std/[unittest, strutils]
import ../src/flit/widgets/text_field
import ../src/flit/rendering/text
import ../src/flit/foundation/color

suite "TextField - multiline":
  test "multiline flag is plumbed":
    let f = textField(multiline = true)
    check f.multiline
    check not f.obscureText

  test "controller inserts newlines like any other text":
    let c = newTextEditingController("line 1")
    c.cursor = 6
    c.selectionEnd = 6
    c.insertText("\nline 2", 0)
    check c.text == "line 1\nline 2"
    check c.text.contains("\n")

  test "maxLines is plumbed":
    let f = textField(multiline = true, maxLines = 5)
    check f.maxLines == 5

  test "single-line field default is multiline=false":
    let f = textField()
    check not f.multiline
    check f.maxLines == 0

suite "TextField - obscureText":
  test "obscureText flag is plumbed":
    let f = textField(obscureText = true, obscureChar = "#")
    check f.obscureText
    check f.obscureChar == "#"

  test "obscureChar default is *":
    let f = textField(obscureText = true)
    check f.obscureChar == "*"

  test "controller text is the raw value (obscuring is render-time only)":
    let c = newTextEditingController("secret")
    let f = textField(controller = c, obscureText = true)
    # The widget's underlying value is unchanged; the display layer
    # substitutes characters in build().
    check c.text == "secret"
    check f.obscureText

suite "TextField - controller still solid":
  test "multiline insert preserves cursor position":
    let c = newTextEditingController("ab\ncd")
    c.cursor = 2
    c.selectionEnd = 2
    c.insertText("X", 0)
    check c.text == "abX\ncd"
    check c.cursor == 3

  test "backspace across newlines walks the byte properly":
    let c = newTextEditingController("a\nb")
    c.cursor = 2
    c.selectionEnd = 2
    c.backspace()
    check c.text == "ab"
    check c.cursor == 1
