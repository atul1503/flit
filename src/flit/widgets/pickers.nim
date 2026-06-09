## Color and font pickers. flit-rendered widgets (modal-style) that
## the app pushes via `Navigator` or shows inline.
##
## Native pickers (`NSColorPanel`, `ChooseColor`, `GtkColorChooser`,
## `NSFontPanel`) require per-platform binding work; the
## flit-rendered version works everywhere including web.
##
## The native variants ship as stubs that fall back to the
## flit-rendered widget.

import std/[options, math, strutils]
import ../foundation/[widget, render_object, geometry, color, key, runtime]
import ../widgets/basic
import ../widgets/text_field
import ../gestures/detector
import ../rendering/[text, decoration]

type
  ColorPicker* = ref object of StatefulWidget
    initial*:  Color
    onChange*: proc(c: Color) {.closure.}

  ColorPickerState* = ref object of State
    current: Color

  FontPicker* = ref object of StatefulWidget
    initial*:  TextStyle
    onChange*: proc(s: TextStyle) {.closure.}
    families*: seq[string]   # available families to pick from

  FontPickerState* = ref object of State
    current: TextStyle

method widgetTypeName*(w: ColorPicker): string = "ColorPicker"
method createElement*(w: ColorPicker): Element = newElement(ekStateful, w)
method createState*(w: ColorPicker): State = ColorPickerState(current: w.initial)

proc rgbSwatch(c: Color, label: string,
               onPress: proc()): Widget =
  let onTap: TapCallback = onPress
  gestureDetector(
    behavior = htOpaque,
    onTap = onTap,
    child = container(
      width = 60, height = 60,
      margin = edgeInsetsAll(4),
      hasDecoration = true,
      decoration = boxDecoration(color = c, borderRadius = 6)))

method build*(s: ColorPickerState, ctx: BuildContext): Widget =
  let host = ColorPicker(s.element.widget)
  let swatchPalette = @[
    colorBlack, colorWhite, colorRed, colorOrange, colorAmber,
    colorYellow, colorGreen, colorTeal, colorCyan,
    colorBlue, colorIndigo, colorPurple, colorPink, colorGrey,
  ]
  var rows: seq[Widget]
  rows.add(Widget(text("Pick a color",
    style = textStyle(fontSize = 16, color = colorBlack))))
  rows.add(sizedBox(height = 8))
  # Current color preview.
  rows.add(container(
    width = 100, height = 40,
    hasDecoration = true,
    decoration = boxDecoration(color = s.current, borderRadius = 6,
                               border = Border(color: colorBlack, width: 1))))
  rows.add(sizedBox(height = 12))
  # Palette grid.
  var swatches: seq[Widget]
  for c in swatchPalette:
    let captured = c
    let host2 = host
    let s2 = s
    swatches.add(rgbSwatch(c, "", proc() =
      setState(s2, proc() = s2.current = captured)
      if not host2.onChange.isNil:
        try: host2.onChange(captured) except CatchableError: discard))
  rows.add(row(children = swatches))
  container(padding = edgeInsetsAll(16), child = column(
    crossAxisAlignment = caStart, mainAxisSize = msMin, children = rows))

method widgetTypeName*(w: FontPicker): string = "FontPicker"
method createElement*(w: FontPicker): Element = newElement(ekStateful, w)
method createState*(w: FontPicker): State = FontPickerState(current: w.initial)

method build*(s: FontPickerState, ctx: BuildContext): Widget =
  let host = FontPicker(s.element.widget)
  var rows: seq[Widget]
  rows.add(Widget(text("Pick a font",
    style = textStyle(fontSize = 16, color = colorBlack))))
  rows.add(sizedBox(height = 8))
  for fam in host.families:
    let captured = fam
    let host2 = host
    let s2 = s
    let onTap: TapCallback = proc() =
      var newStyle = s2.current
      newStyle.fontFamily = captured
      setState(s2, proc() = s2.current = newStyle)
      if not host2.onChange.isNil:
        try: host2.onChange(newStyle) except CatchableError: discard
    rows.add(gestureDetector(
      behavior = htOpaque,
      onTap = onTap,
      child = container(
        padding = edgeInsetsSymmetric(horizontal = 12, vertical = 6),
        child = text(fam, style = textStyle(fontFamily = fam, fontSize = 14,
                                            color = colorBlack)))))
  container(padding = edgeInsetsAll(16), child = column(
    crossAxisAlignment = caStart, mainAxisSize = msMin, children = rows))

proc colorPicker*(initial: Color = colorBlack,
                  onChange: proc(c: Color) = nil,
                  key: Key = nil): ColorPicker =
  ## Builds a color picker widget. Push it via `Navigator` for a
  ## modal-style picker, or embed inline. `onChange` fires every
  ## time the user selects a color.
  ColorPicker(key: key, initial: initial, onChange: onChange)

proc fontPicker*(initial: TextStyle = defaultTextStyle,
                 families: seq[string] = @["system"],
                 onChange: proc(s: TextStyle) = nil,
                 key: Key = nil): FontPicker =
  ## Builds a font picker. `families` is the list to choose from
  ## (typically populated from system fonts at startup).
  FontPicker(key: key, initial: initial, families: families,
             onChange: onChange)
