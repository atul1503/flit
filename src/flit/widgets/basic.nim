## Layout widgets: the building blocks every Flutter user knows.
## Container, Padding, Center, Align, Row, Column, Stack, SizedBox,
## Expanded, Flexible, ConstrainedBox, AspectRatio, ColoredBox.

import ../foundation/[widget, key, geometry, color, render_object]
import ../rendering/[proxy_box, flex, stack, decoration, text, viewport]

# ----- Container -----

# Container is defined at the END of this file: its build() needs to
# call padding(), align(), decoratedBox(), constrainedBox() and
# sizedBox() which are all defined below.

# ----- SizedBox -----

type
  SizedBox* = ref object of RenderObjectWidget
    width*, height*: float32
    child*: Widget

method widgetTypeName*(w: SizedBox): string = "SizedBox"
method createElement*(w: SizedBox): Element = newElement(ekRender, w)
method createRenderObject*(w: SizedBox, ctx: BuildContext): RenderObject =
  RenderSizedBox(requestedWidth: w.width, requestedHeight: w.height)
method updateRenderObject*(w: SizedBox, ctx: BuildContext, r: RenderObject) =
  let s = RenderSizedBox(r)
  s.requestedWidth = w.width
  s.requestedHeight = w.height
  r.markNeedsLayout()

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
method updateRenderObject*(w: Padding, ctx: BuildContext, r: RenderObject) =
  RenderPadding(r).padding = w.padding
  r.markNeedsLayout()

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
method updateRenderObject*(w: Align, ctx: BuildContext, r: RenderObject) =
  let a = RenderAlign(r)
  a.alignment = w.alignment
  a.widthFactor = w.widthFactor
  a.heightFactor = w.heightFactor
  r.markNeedsLayout()

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
method updateRenderObject*(w: ColoredBox, ctx: BuildContext, r: RenderObject) =
  RenderColoredBox(r).fill = w.color
  r.markNeedsPaint()

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
method updateRenderObject*(w: DecoratedBox, ctx: BuildContext, r: RenderObject) =
  RenderDecoratedBox(r).decoration = w.decoration
  r.markNeedsPaint()

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
method updateRenderObject*(w: Row, ctx: BuildContext, r: RenderObject) =
  let f = RenderFlex(r)
  f.mainAxisAlignment = w.mainAxisAlignment
  f.crossAxisAlignment = w.crossAxisAlignment
  f.mainAxisSize = w.mainAxisSize
  r.markNeedsLayout()
method updateRenderObject*(w: Column, ctx: BuildContext, r: RenderObject) =
  let f = RenderFlex(r)
  f.mainAxisAlignment = w.mainAxisAlignment
  f.crossAxisAlignment = w.crossAxisAlignment
  f.mainAxisSize = w.mainAxisSize
  r.markNeedsLayout()

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
method updateRenderObject*(w: Stack, ctx: BuildContext, r: RenderObject) =
  let st = RenderStack(r)
  st.alignment = w.alignment
  st.fit = w.fit
  r.markNeedsLayout()

proc stack*(children: seq[Widget] = @[], alignment = alignTopLeft,
            fit = sfLoose, key: Key = nil): Stack =
  Stack(key: key, children: children, alignment: alignment, fit: fit)

# ----- ScrollView -----

type
  ScrollView* = ref object of RenderObjectWidget
    child*: Widget
    direction*: Axis

method widgetTypeName*(w: ScrollView): string = "ScrollView"
method createElement*(w: ScrollView): Element = newElement(ekRender, w)
method createRenderObject*(w: ScrollView, ctx: BuildContext): RenderObject =
  RenderViewport(direction: w.direction, scrollOffset: 0, maxScroll: 0)
method updateRenderObject*(w: ScrollView, ctx: BuildContext, r: RenderObject) =
  RenderViewport(r).direction = w.direction
  r.markNeedsLayout()

proc scrollView*(child: Widget, direction = axVertical,
                 key: Key = nil): ScrollView =
  ScrollView(key: key, child: child, direction: direction)

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

# ----- AspectRatio -----

type
  AspectRatio* = ref object of RenderObjectWidget
    aspectRatio*: float32
    child*: Widget

method widgetTypeName*(w: AspectRatio): string = "AspectRatio"
method createElement*(w: AspectRatio): Element = newElement(ekRender, w)
method createRenderObject*(w: AspectRatio, ctx: BuildContext): RenderObject =
  RenderAspectRatio(aspectRatio: w.aspectRatio)
method updateRenderObject*(w: AspectRatio, ctx: BuildContext, r: RenderObject) =
  RenderAspectRatio(r).aspectRatio = w.aspectRatio
  r.markNeedsLayout()

proc aspectRatio*(child: Widget, aspectRatio: float32,
                  key: Key = nil): AspectRatio =
  AspectRatio(key: key, child: child, aspectRatio: aspectRatio)

# ----- ClipRect / ClipRRect / Opacity widgets -----

type
  ClipRect* = ref object of RenderObjectWidget
    child*: Widget

  ClipRRect* = ref object of RenderObjectWidget
    radius*: float32
    child*: Widget

  OpacityWidget* = ref object of RenderObjectWidget
    opacity*: float32
    child*: Widget

method widgetTypeName*(w: ClipRect): string = "ClipRect"
method createElement*(w: ClipRect): Element = newElement(ekRender, w)
method createRenderObject*(w: ClipRect, ctx: BuildContext): RenderObject =
  RenderClipRect()

method widgetTypeName*(w: ClipRRect): string = "ClipRRect"
method createElement*(w: ClipRRect): Element = newElement(ekRender, w)
method createRenderObject*(w: ClipRRect, ctx: BuildContext): RenderObject =
  RenderClipRRect(radius: w.radius)
method updateRenderObject*(w: ClipRRect, ctx: BuildContext, r: RenderObject) =
  RenderClipRRect(r).radius = w.radius
  r.markNeedsPaint()

method widgetTypeName*(w: OpacityWidget): string = "Opacity"
method createElement*(w: OpacityWidget): Element = newElement(ekRender, w)
method createRenderObject*(w: OpacityWidget, ctx: BuildContext): RenderObject =
  RenderOpacity(opacity: w.opacity)
method updateRenderObject*(w: OpacityWidget, ctx: BuildContext, r: RenderObject) =
  RenderOpacity(r).opacity = w.opacity
  r.markNeedsPaint()

proc clipRect*(child: Widget, key: Key = nil): ClipRect =
  ClipRect(key: key, child: child)

proc clipRRect*(child: Widget, radius: float32, key: Key = nil): ClipRRect =
  ClipRRect(key: key, child: child, radius: radius)

proc opacity*(child: Widget, opacity: float32, key: Key = nil): OpacityWidget =
  OpacityWidget(key: key, child: child, opacity: opacity)

# ----- Container -----
# Convenience wrapper that builds the standard Flutter composition:
#   margin > decoration > constrained > padding > align > child.
# Each layer is skipped if not requested. Defined at end of file because
# its build() needs the constructors above (padding, align, decoratedBox,
# constrainedBox, sizedBox) to be in scope.

type
  Container* = ref object of StatelessWidget
    width*, height*: float32
    padding*, margin*: EdgeInsets
    color*: Color
    decoration*: BoxDecoration
    alignment*: Alignment
    child*: Widget
    hasAlignment*: bool
    hasDecoration*: bool
    hasColor*: bool

method widgetTypeName*(w: Container): string = "Container"
method createElement*(w: Container): Element = newElement(ekStateless, w)
method build*(w: Container, ctx: BuildContext): Widget =
  var current = w.child

  if w.hasAlignment and not current.isNil:
    current = align(child = current, alignment = w.alignment)

  if w.padding.left != 0 or w.padding.top != 0 or
     w.padding.right != 0 or w.padding.bottom != 0:
    current = padding(child = current, padding = w.padding)

  if w.width > 0 or w.height > 0:
    let minW = if w.width  > 0: w.width  else: 0.0'f32
    let maxW = if w.width  > 0: w.width  else: Inf
    let minH = if w.height > 0: w.height else: 0.0'f32
    let maxH = if w.height > 0: w.height else: Inf
    if current.isNil:
      current = sizedBox(width = w.width, height = w.height)
    else:
      current = constrainedBox(child = current,
                               boxConstraints = constraints(minW, maxW, minH, maxH))

  if w.hasDecoration:
    if not current.isNil:
      current = decoratedBox(child = current, decoration = w.decoration)
    else:
      current = decoratedBox(decoration = w.decoration)
  elif w.hasColor:
    let dec = boxDecoration(color = w.color)
    if not current.isNil:
      current = decoratedBox(child = current, decoration = dec)
    else:
      current = decoratedBox(decoration = dec)

  if w.margin.left != 0 or w.margin.top != 0 or
     w.margin.right != 0 or w.margin.bottom != 0:
    current = padding(child = current, padding = w.margin)

  if current.isNil: current = sizedBox()
  current

proc container*(child: Widget = nil,
                width = 0.0'f32, height = 0.0'f32,
                color = colorTransparent,
                padding = edgeInsetsAll(0),
                margin = edgeInsetsAll(0),
                alignment = alignCenter,
                decoration = BoxDecoration(),
                hasColor = false,
                hasDecoration = false,
                hasAlignment = false,
                key: Key = nil): Container =
  Container(key: key, width: width, height: height, color: color,
            padding: padding, margin: margin, alignment: alignment,
            decoration: decoration, child: child,
            hasColor: hasColor, hasDecoration: hasDecoration,
            hasAlignment: hasAlignment)
