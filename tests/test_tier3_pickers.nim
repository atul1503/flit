## Color and font pickers: widget construction and onChange wiring.

import std/unittest
import ../src/flit/widgets/pickers
import ../src/flit/foundation/color
import ../src/flit/rendering/text

suite "ColorPicker":
  test "constructs with default initial":
    let p = colorPicker()
    check not p.isNil
    check p.widgetTypeName == "ColorPicker"

  test "stores initial color":
    let p = colorPicker(initial = colorRed)
    check p.initial.value == colorRed.value

  test "onChange callback is stored":
    var seen: Color
    let p = colorPicker(initial = colorBlue,
                        onChange = proc(c: Color) = seen = c)
    check not p.onChange.isNil
    p.onChange(colorGreen)
    check seen.value == colorGreen.value

suite "FontPicker":
  test "constructs with default style + families":
    let p = fontPicker()
    check not p.isNil
    check p.widgetTypeName == "FontPicker"
    check p.families == @["system"]

  test "stores custom families":
    let p = fontPicker(families = @["system", "monospace", "serif"])
    check p.families.len == 3
    check p.families[2] == "serif"

  test "onChange callback is stored":
    var seenFamily: string
    let p = fontPicker(families = @["A", "B"],
                       onChange = proc(s: TextStyle) =
                         seenFamily = s.fontFamily)
    check not p.onChange.isNil
    var ts = defaultTextStyle
    ts.fontFamily = "B"
    p.onChange(ts)
    check seenFamily == "B"
