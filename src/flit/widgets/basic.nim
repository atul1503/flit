## Layout widgets: the building blocks every Flutter user knows.
## Container, Padding, Center, Align, Row, Column, Stack, SizedBox,
## Expanded, Flexible, ConstrainedBox, AspectRatio, ColoredBox.

import ../foundation/[widget, key, geometry, color, render_object]
import ../rendering/[proxy_box, flex, stack, decoration, text]

# ----- Container -----

type
  Container* = ref object of RenderObjectWidget
    width*, height*: float32
    padding*, margin*: EdgeInsets
    color*: Color
    decoration*: BoxDecoration
    alignment*: Alignment
    child*: Widget
    hasAlignment*: bool
    hasDecoration*: bool

method widgetTypeName*(w: Container): string = "Container"
method createElement*(w: Container): Element = newElement(ekRender, w)
method createRenderObject*(w: Container, ctx: BuildContext): RenderObject =
  ## Real Container is a composite: margin -> decoration -> padding -> align -> child.
  ## Here we return the outermost render object and chain inwards.
  result = RenderConstrainedBox(
    additionalConstraints:
      if w.width > 0 or w.height > 0:
        let mw = if w.width  > 0: w.width  else: Inf
        let mh = if w.height > 0: w.height else: Inf
        constraints(0, mw, 0, mh)
      else: unbounded())

proc container*(child: Widget = nil,
                width = 0.0'f32, height = 0.0'f32,
                color = colorTransparent,
                padding = edgeInsetsAll(0),
                margin = edgeInsetsAll(0),
                alignment = alignTopLeft,
                decoration = BoxDecoration(),
                key: Key = nil): Container =
  Container(key: key, width: width, height: height, color: color,
            padding: padding, margin: margin, alignment: alignment,
            decoration: decoration, child: child)

# ----- SizedBox -----

type
  SizedBox* = ref object of RenderObjectWidget
    width*, height*: float32
    child*: Widget

method widgetTypeName*(w: SizedBox): string = "SizedBox"
method createElement*(w: SizedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: SizedBox, ctx: BuildContext): RenderObject =
  RenderSizedBox(requestedWidth: w.width, requestedHeight: w.height)

proc sizedBox*(child: Widget = nil, width = 0.0'f32, height = 0.0'f32,
               key: Key = nil): SizedBox =
  SizedBox(key: key, width: width, height: height, child: child)

# ----- Padding -----

type
  Padding* = ref object of RenderObjectWidget
    padding*: EdgeInsets
    child*: Widget

method widgetTypeName*(w: Padding): string = "Padding"
method createElement*(w: Padding): Element = newElement(ekRender, w)
method createRenderObject*(w: Padding, ctx: BuildContext): RenderObject =
  RenderPadding(padding: w.padding)

proc padding*(child: Widget = nil, padding = edgeInsetsAll(8),
              key: Key = nil): Padding =
  Padding(key: key, padding: padding, child: child)

# ----- Align / Center -----

type
  Align* = ref object of RenderObjectWidget
    alignment*: Alignment
    widthFactor*, heightFactor*: float32
    child*: Widget

method widgetTypeName*(w: Align): string = "Align"
method createElement*(w: Align): Element = newElement(ekRender, w)
method createRenderObject*(w: Align, ctx: BuildContext): RenderObject =
  RenderAlign(alignment: w.alignment,
              widthFactor: w.widthFactor, heightFactor: w.heightFactor)

proc align*(child: Widget = nil, alignment = alignCenter,
            widthFactor = 0.0'f32, heightFactor = 0.0'f32,
            key: Key = nil): Align =
  Align(key: key, alignment: alignment, widthFactor: widthFactor,
        heightFactor: heightFactor, child: child)

proc center*(child: Widget = nil, key: Key = nil): Align =
  align(child = child, alignment = alignCenter, key = key)

# ----- ColoredBox -----

type
  ColoredBox* = ref object of RenderObjectWidget
    color*: Color
    child*: Widget

method widgetTypeName*(w: ColoredBox): string = "ColoredBox"
method createElement*(w: ColoredBox): Element = newElement(ekRender, w)
method createRenderObject*(w: ColoredBox, ctx: BuildContext): RenderObject =
  RenderColoredBox(fill: w.color)

proc coloredBox*(child: Widget = nil, color = colorTransparent,
                 key: Key = nil): ColoredBox =
  ColoredBox(key: key, color: color, child: child)

# ----- DecoratedBox -----

type
  DecoratedBox* = ref object of RenderObjectWidget
    decoration*: BoxDecoration
    child*: Widget

method widgetTypeName*(w: DecoratedBox): string = "DecoratedBox"
method createElement*(w: DecoratedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: DecoratedBox, ctx: BuildContext): RenderObject =
  RenderDecoratedBox(decoration: w.decoration)

proc decoratedBox*(child: Widget = nil, decoration = BoxDecoration(),
                   key: Key = nil): DecoratedBox =
  DecoratedBox(key: key, decoration: decoration, child: child)

# ----- Row / Column -----

type
  Row* = ref object of RenderObjectWidget
    mainAxisAlignment*: MainAxisAlignment
    crossAxisAlignment*: CrossAxisAlignment
    mainAxisSize*: MainAxisSize
    children*: seq[Widget]

  Column* = ref object of RenderObjectWidget
    mainAxisAlignment*: MainAxisAlignment
    crossAxisAlignment*: CrossAxisAlignment
    mainAxisSize*: MainAxisSize
    children*: seq[Widget]

method widgetTypeName*(w: Row): string = "Row"
method widgetTypeName*(w: Column): string = "Column"
method createElement*(w: Row): Element = newElement(ekRender, w)
method createElement*(w: Column): Element = newElement(ekRender, w)
method createRenderObject*(w: Row, ctx: BuildContext): RenderObject =
  RenderFlex(direction: axHorizontal,
             mainAxisAlignment: w.mainAxisAlignment,
             crossAxisAlignment: w.crossAxisAlignment,
             mainAxisSize: w.mainAxisSize)
method createRenderObject*(w: Column, ctx: BuildContext): RenderObject =
  RenderFlex(direction: axVertical,
             mainAxisAlignment: w.mainAxisAlignment,
             crossAxisAlignment: w.crossAxisAlignment,
             mainAxisSize: w.mainAxisSize)

proc row*(children: seq[Widget] = @[],
          mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
          mainAxisSize = msMax, key: Key = nil): Row =
  Row(key: key, children: children,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize)

proc column*(children: seq[Widget] = @[],
             mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
             mainAxisSize = msMax, key: Key = nil): Column =
  Column(key: key, children: children,
         mainAxisAlignment: mainAxisAlignment,
         crossAxisAlignment: crossAxisAlignment,
         mainAxisSize: mainAxisSize)

# ----- Expanded / Flexible -----

type
  Flexible* = ref object of ProxyWidget
    flex*: int
    fit*: FlexFit

method widgetTypeName*(w: Flexible): string = "Flexible"
method createElement*(w: Flexible): Element = newElement(ekProxy, w)

proc flexible*(child: Widget, flex = 1, fit = ffLoose, key: Key = nil): Flexible =
  Flexible(key: key, child: child, flex: flex, fit: fit)

proc expanded*(child: Widget, flex = 1, key: Key = nil): Flexible =
  flexible(child = child, flex = flex, fit = ffTight, key = key)

# ----- Positioned (Stack child) -----

type
  Positioned* = ref object of ProxyWidget
    left*, top*, right*, bottom*, width*, height*: float32

method widgetTypeName*(w: Positioned): string = "Positioned"
method createElement*(w: Positioned): Element = newElement(ekProxy, w)

proc positioned*(child: Widget,
                 left = unsetF, top = unsetF, right = unsetF,
                 bottom = unsetF, width = unsetF, height = unsetF,
                 key: Key = nil): Positioned =
  Positioned(key: key, child: child, left: left, top: top, right: right,
             bottom: bottom, width: width, height: height)

# ----- Stack -----

type
  Stack* = ref object of RenderObjectWidget
    alignment*: Alignment
    fit*: StackFit
    children*: seq[Widget]

method widgetTypeName*(w: Stack): string = "Stack"
method createElement*(w: Stack): Element = newElement(ekRender, w)
method createRenderObject*(w: Stack, ctx: BuildContext): RenderObject =
  RenderStack(alignment: w.alignment, fit: w.fit)

proc stack*(children: seq[Widget] = @[], alignment = alignTopLeft,
            fit = sfLoose, key: Key = nil): Stack =
  Stack(key: key, children: children, alignment: alignment, fit: fit)

# ----- Text -----

type
  Text* = ref object of RenderObjectWidget
    data*: string
    style*: TextStyle
    textAlign*: TextAlign
    softWrap*: bool
    maxLines*: int

method widgetTypeName*(w: Text): string = "Text"
method createElement*(w: Text): Element = newElement(ekRender, w)
method createRenderObject*(w: Text, ctx: BuildContext): RenderObject =
  RenderParagraph(text: w.data, style: w.style, align: w.textAlign,
                  maxLines: w.maxLines, softWrap: w.softWrap)
method updateRenderObject*(w: Text, ctx: BuildContext, r: RenderObject) =
  let p = RenderParagraph(r)
  p.text = w.data
  p.style = w.style
  p.align = w.textAlign
  p.softWrap = w.softWrap
  p.maxLines = w.maxLines
  p.markNeedsLayout()

proc text*(data: string, style = defaultTextStyle,
           textAlign = taStart, softWrap = true, maxLines = 0,
           key: Key = nil): Text =
  Text(key: key, data: data, style: style, textAlign: textAlign,
       softWrap: softWrap, maxLines: maxLines)

# ----- ConstrainedBox -----

type
  ConstrainedBox* = ref object of RenderObjectWidget
    boxConstraints*: Constraints
    child*: Widget

method widgetTypeName*(w: ConstrainedBox): string = "ConstrainedBox"
method createElement*(w: ConstrainedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: ConstrainedBox, ctx: BuildContext): RenderObject =
  RenderConstrainedBox(additionalConstraints: w.boxConstraints)

proc constrainedBox*(child: Widget, boxConstraints: Constraints,
                     key: Key = nil): ConstrainedBox =
  ConstrainedBox(key: key, child: child, boxConstraints: boxConstraints)
