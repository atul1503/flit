## Todo: mutate a list of items, hit-test buttons, rebuild on setState.

import ../../src/flit

type
  TodoItem = object
    text: string
    done: bool

  TodoApp* = ref object of StatefulWidget
  TodoState = ref object of State
    items: seq[TodoItem]
    nextId: int

method widgetTypeName*(w: TodoApp): string = "TodoApp"
method createElement*(w: TodoApp): Element = newElement(ekStateful, w)
method createState*(w: TodoApp): State =
  TodoState(items: @[
    TodoItem(text: "Try flit", done: true),
    TodoItem(text: "Build something cool", done: false),
    TodoItem(text: "Ship it", done: false)])

proc itemRow(s: TodoState, i: int): Widget =
  let it = s.items[i]
  let stl = if it.done:
    textStyle(fontSize = 16, color = colorGrey, italic = true)
  else:
    textStyle(fontSize = 16, color = colorBlack)
  gestureDetector(
    child = padding(padding = edgeInsetsAll(12),
      child = row(crossAxisAlignment = caCenter, children = @[
        Widget(decoratedBox(
          decoration = boxDecoration(
            color = if it.done: colorGreen else: colorTransparent,
            borderRadius = 4,
            border = Border(color: colorGrey, width: 2)),
          child = sizedBox(width = 20, height = 20))),
        sizedBox(width = 12),
        expanded(text(it.text, style = stl)),
      ])),
    onTap = proc() =
      setState(s, proc() = s.items[i].done = not s.items[i].done),
    behavior = htOpaque)

method build*(s: TodoState, ctx: BuildContext): Widget =
  var listKids: seq[Widget] = @[]
  for i in 0 ..< s.items.len:
    listKids.add(itemRow(s, i))
  materialApp(
    title = "Todo",
    home = scaffold(
      appBar = appBar(title = text("Todos")),
      body = column(crossAxisAlignment = caStretch, children = listKids),
      floatingActionButton = floatingActionButton(
        child = text("+", style = textStyle(fontSize = 28, color = colorWhite)),
        onPressed = proc() = setState(s, proc() =
          inc s.nextId
          s.items.add(TodoItem(text: "New item " & $s.nextId, done: false))))))

when isMainModule: runApp(TodoApp())
