## Gallery: walks through the basic flit widget primitives. Pure stateless
## composition with no callbacks, useful as a screenshot reference.

import ../../src/flit

type
  Gallery* = ref object of StatelessWidget

method widgetTypeName*(w: Gallery): string = "Gallery"
method createElement*(w: Gallery): Element = newElement(ekStateless, w)
method build*(w: Gallery, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(title = text("Flit Gallery")),
    body = padding(padding = edgeInsetsAll(16),
      child = column(crossAxisAlignment = caStretch, children = @[
        Widget(text("Decorations", style = textStyle(fontSize = 20, fontWeight = 600))),
        sizedBox(height = 8),
        row(mainAxisAlignment = maSpaceAround, children = @[
          Widget(decoratedBox(
            decoration = boxDecoration(color = colorRed, borderRadius = 8),
            child = sizedBox(width = 60, height = 60))),
          decoratedBox(
            decoration = boxDecoration(color = colorBlue, borderRadius = 30,
                                       shape = bsCircle),
            child = sizedBox(width = 60, height = 60)),
          decoratedBox(
            decoration = boxDecoration(color = colorGreen,
              border = Border(color: colorBlack, width: 3)),
            child = sizedBox(width = 60, height = 60))]),
        sizedBox(height = 24),
        text("Buttons", style = textStyle(fontSize = 20, fontWeight = 600)),
        sizedBox(height = 8),
        row(mainAxisAlignment = maSpaceAround, children = @[
          Widget(elevatedButton(child = text("Elevated"))),
          textButton(child = text("Text"))]),
        sizedBox(height = 24),
        text("Layout", style = textStyle(fontSize = 20, fontWeight = 600)),
        sizedBox(height = 8),
        row(crossAxisAlignment = caStretch, children = @[
          Widget(expanded(decoratedBox(
            decoration = boxDecoration(color = colorAmber),
            child = sizedBox(height = 80, child = center(child = text("1")))))),
          expanded(decoratedBox(
            decoration = boxDecoration(color = colorTeal),
            child = sizedBox(height = 80, child = center(child = text("2")))),
            flex = 2),
          expanded(decoratedBox(
            decoration = boxDecoration(color = colorPurple),
            child = sizedBox(height = 80, child = center(child = text("1"))))),
        ]),
      ]))))

when isMainModule: runApp(Gallery())
