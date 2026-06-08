## Pocket calculator. Demonstrates Row/Column nesting, gesture handling, and
## state-driven text updates.

import ../../src/flit
import std/strutils

type
  CalcApp* = ref object of StatefulWidget
  CalcState = ref object of State
    display: string
    accumulator: float
    pendingOp: char

method widgetTypeName*(w: CalcApp): string = "CalcApp"
method createElement*(w: CalcApp): Element = newElement(ekStateful, w)
method createState*(w: CalcApp): State = CalcState(display: "0", pendingOp: '\0')

proc apply(s: CalcState) =
  let v = parseFloat(s.display)
  case s.pendingOp
  of '+': s.accumulator += v
  of '-': s.accumulator -= v
  of '*': s.accumulator *= v
  of '/':
    if v != 0: s.accumulator /= v
  of '\0': s.accumulator = v
  else: discard
  s.display = $s.accumulator

proc onDigit(s: CalcState, d: string) =
  setState(s, proc() =
    if s.display == "0": s.display = d
    else: s.display.add(d))

proc onOp(s: CalcState, op: char) =
  setState(s, proc() =
    apply(s)
    s.pendingOp = op
    s.display = "0")

proc onEq(s: CalcState) =
  setState(s, proc() =
    apply(s)
    s.pendingOp = '\0')

proc onClear(s: CalcState) =
  setState(s, proc() =
    s.display = "0"
    s.accumulator = 0
    s.pendingOp = '\0')

proc btn(label: string, cb: TapCallback, bg = rgb(70, 70, 70),
         fg = colorWhite): Widget =
  expanded(
    padding(
      child = gestureDetector(
        onTap = cb, behavior = htOpaque,
        child = decoratedBox(
          decoration = boxDecoration(color = bg, borderRadius = 12),
          child = sizedBox(height = 64,
            child = center(child = text(label,
              style = textStyle(fontSize = 22, color = fg)))))),
      padding = edgeInsetsAll(4)))

method build*(s: CalcState, ctx: BuildContext): Widget =
  let orange = rgb(255, 149, 0)
  let display = sizedBox(height = 120,
    child = padding(padding = edgeInsetsAll(16),
      child = align(alignment = alignBottomRight,
        child = text(s.display, style = textStyle(
          fontSize = 48, color = colorWhite, fontFamily = "monospace")))))
  let rows = @[
    Widget(row(crossAxisAlignment = caStretch, children = @[
      btn("C",  proc() = onClear(s), rgb(165, 165, 165), colorBlack),
      btn("+/-", proc() = setState(s, proc() =
        if s.display.startsWith("-"): s.display = s.display[1..^1]
        else: s.display = "-" & s.display), rgb(165, 165, 165), colorBlack),
      btn("%",  proc() = discard, rgb(165, 165, 165), colorBlack),
      btn("/",  proc() = onOp(s, '/'), orange) ])),
    row(crossAxisAlignment = caStretch, children = @[
      btn("7", proc() = onDigit(s, "7")),
      btn("8", proc() = onDigit(s, "8")),
      btn("9", proc() = onDigit(s, "9")),
      btn("*", proc() = onOp(s, '*'), orange)]),
    row(crossAxisAlignment = caStretch, children = @[
      btn("4", proc() = onDigit(s, "4")),
      btn("5", proc() = onDigit(s, "5")),
      btn("6", proc() = onDigit(s, "6")),
      btn("-", proc() = onOp(s, '-'), orange)]),
    row(crossAxisAlignment = caStretch, children = @[
      btn("1", proc() = onDigit(s, "1")),
      btn("2", proc() = onDigit(s, "2")),
      btn("3", proc() = onDigit(s, "3")),
      btn("+", proc() = onOp(s, '+'), orange)]),
    row(crossAxisAlignment = caStretch, children = @[
      expanded(padding(
          child = gestureDetector(behavior = htOpaque,
            onTap = proc() = onDigit(s, "0"),
            child = decoratedBox(
              decoration = boxDecoration(color = rgb(70, 70, 70), borderRadius = 12),
              child = sizedBox(height = 64,
                child = center(child = text("0",
                  style = textStyle(fontSize = 22, color = colorWhite)))))),
          padding = edgeInsetsAll(4)),
        flex = 2),
      btn(".", proc() = setState(s, proc() =
        if "." notin s.display: s.display.add('.'))),
      btn("=", proc() = onEq(s), orange)])]
  materialApp(theme = themeData(bDark),
    home = scaffold(
      hasBackgroundColor = true, backgroundColor = colorBlack,
      body = column(crossAxisAlignment = caStretch, children = @[
        Widget(display),
        expanded(column(crossAxisAlignment = caStretch, children = rows))])))

when isMainModule: runApp(CalcApp())
