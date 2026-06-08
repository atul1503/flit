## The canonical Flutter "counter" sample, in Nim.

import ../../src/flit

type
  Counter* = ref object of StatefulWidget
  CounterState = ref object of State
    count: int

method widgetTypeName*(w: Counter): string = "Counter"
method createElement*(w: Counter): Element = newElement(ekStateful, w)
method createState*(w: Counter): State = CounterState(count: 0)

method build*(s: CounterState, ctx: BuildContext): Widget =
  materialApp(
    title = "Counter",
    home = scaffold(
      appBar = appBar(title = text("Flit counter")),
      body = center(
        child = column(
          mainAxisAlignment = maCenter,
          children = @[
            Widget(text("You have pushed the button this many times:")),
            text($s.count, style = textStyle(fontSize = 36, fontWeight = 700)),
          ])),
      floatingActionButton = floatingActionButton(
        child = text("+", style = textStyle(fontSize = 28, color = colorWhite)),
        onPressed = proc() = setState(s, proc() = inc s.count))))

when isMainModule:
  runApp(Counter())
