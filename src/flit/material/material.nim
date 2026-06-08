## Material widget library: MaterialApp, Scaffold, AppBar, buttons, Card.

import ../foundation/[widget, key, geometry, color]
import ../rendering/[decoration, text]
import ../widgets/basic
import ../gestures/detector
import ./theme

# ----- MaterialApp -----

type
  MaterialApp* = ref object of StatelessWidget
    title*: string
    theme*: ThemeData
    home*: Widget

method widgetTypeName*(w: MaterialApp): string = "MaterialApp"
method createElement*(w: MaterialApp): Element = newElement(ekStateless, w)
method build*(w: MaterialApp, ctx: BuildContext): Widget =
  pushTheme(w.theme)
  coloredBox(child = w.home, color = w.theme.colorScheme.background)

proc materialApp*(home: Widget, title = "Flit App", theme = themeData(),
                  key: Key = nil): MaterialApp =
  MaterialApp(key: key, home: home, title: title, theme: theme)

# ----- Scaffold -----

type
  Scaffold* = ref object of StatelessWidget
    appBar*: Widget
    body*: Widget
    floatingActionButton*: Widget
    backgroundColor*: Color
    hasBackgroundColor*: bool

method widgetTypeName*(w: Scaffold): string = "Scaffold"
method createElement*(w: Scaffold): Element = newElement(ekStateless, w)
method build*(w: Scaffold, ctx: BuildContext): Widget =
  let bg = if w.hasBackgroundColor: w.backgroundColor
           else: currentTheme().colorScheme.background
  var kids: seq[Widget] = @[]
  if not w.appBar.isNil:
    kids.add(w.appBar)
  if not w.body.isNil:
    kids.add(expanded(w.body))
  let col = column(children = kids, mainAxisSize = msMax,
                   crossAxisAlignment = caStretch)
  if w.floatingActionButton.isNil:
    coloredBox(child = col, color = bg)
  else:
    stack(children = @[
      Widget(coloredBox(child = col, color = bg)),
      positioned(child = w.floatingActionButton, right = 16, bottom = 16)
    ])

proc scaffold*(body: Widget, appBar: Widget = nil,
               floatingActionButton: Widget = nil,
               backgroundColor = colorTransparent,
               hasBackgroundColor = false,
               key: Key = nil): Scaffold =
  Scaffold(key: key, body: body, appBar: appBar,
           floatingActionButton: floatingActionButton,
           backgroundColor: backgroundColor,
           hasBackgroundColor: hasBackgroundColor)

# ----- AppBar -----

type
  AppBar* = ref object of StatelessWidget
    title*: Widget
    actions*: seq[Widget]
    backgroundColor*: Color
    hasBackgroundColor*: bool
    elevation*: float32

method widgetTypeName*(w: AppBar): string = "AppBar"
method createElement*(w: AppBar): Element = newElement(ekStateless, w)
method build*(w: AppBar, ctx: BuildContext): Widget =
  let t = currentTheme()
  let bg = if w.hasBackgroundColor: w.backgroundColor else: t.colorScheme.primary
  var rowChildren: seq[Widget] = @[]
  if not w.title.isNil:
    rowChildren.add(expanded(w.title))
  for a in w.actions:
    rowChildren.add(a)
  decoratedBox(
    decoration = boxDecoration(color = bg,
      border = Border(color: colorTransparent, width: 0)),
    child = sizedBox(height = 56,
      child = padding(padding = edgeInsetsSymmetric(16, 8),
        child = row(children = rowChildren,
                    crossAxisAlignment = caCenter,
                    mainAxisSize = msMax))))

proc appBar*(title: Widget, actions: seq[Widget] = @[],
             backgroundColor = colorTransparent,
             hasBackgroundColor = false,
             elevation = 4.0'f32, key: Key = nil): AppBar =
  AppBar(key: key, title: title, actions: actions,
         backgroundColor: backgroundColor,
         hasBackgroundColor: hasBackgroundColor, elevation: elevation)

# ----- Buttons -----

type
  ElevatedButton* = ref object of StatelessWidget
    onPressed*: TapCallback
    child*: Widget
    backgroundColor*: Color
    foregroundColor*: Color
    hasColors*: bool

method widgetTypeName*(w: ElevatedButton): string = "ElevatedButton"
method createElement*(w: ElevatedButton): Element = newElement(ekStateless, w)
method build*(w: ElevatedButton, ctx: BuildContext): Widget =
  let t = currentTheme()
  let bg = if w.hasColors: w.backgroundColor else: t.colorScheme.primary
  let fg = if w.hasColors: w.foregroundColor else: t.colorScheme.onPrimary
  let body =
    decoratedBox(
      decoration = boxDecoration(color = bg, borderRadius = 20.0'f32),
      child = padding(
        padding = edgeInsetsSymmetric(24, 12),
        child = w.child))
  if w.onPressed.isNil: body
  else: gestureDetector(child = body, onTap = w.onPressed,
                        behavior = htOpaque)

proc elevatedButton*(child: Widget, onPressed: TapCallback = nil,
                     backgroundColor = colorTransparent,
                     foregroundColor = colorTransparent,
                     hasColors = false,
                     key: Key = nil): ElevatedButton =
  ElevatedButton(key: key, child: child, onPressed: onPressed,
                 backgroundColor: backgroundColor,
                 foregroundColor: foregroundColor, hasColors: hasColors)

type
  TextButton* = ref object of StatelessWidget
    onPressed*: TapCallback
    child*: Widget

method widgetTypeName*(w: TextButton): string = "TextButton"
method createElement*(w: TextButton): Element = newElement(ekStateless, w)
method build*(w: TextButton, ctx: BuildContext): Widget =
  let body = padding(padding = edgeInsetsSymmetric(16, 8), child = w.child)
  if w.onPressed.isNil: body
  else: gestureDetector(child = body, onTap = w.onPressed, behavior = htOpaque)

proc textButton*(child: Widget, onPressed: TapCallback = nil,
                 key: Key = nil): TextButton =
  TextButton(key: key, child: child, onPressed: onPressed)

# ----- Card -----

type
  Card* = ref object of StatelessWidget
    child*: Widget
    elevation*: float32
    margin*: EdgeInsets

method widgetTypeName*(w: Card): string = "Card"
method createElement*(w: Card): Element = newElement(ekStateless, w)
method build*(w: Card, ctx: BuildContext): Widget =
  let t = currentTheme()
  padding(padding = w.margin,
    child = decoratedBox(
      decoration = boxDecoration(color = t.colorScheme.surface,
                                 borderRadius = t.defaultRadius),
      child = w.child))

proc card*(child: Widget, elevation = 2.0'f32,
           margin = edgeInsetsAll(8), key: Key = nil): Card =
  Card(key: key, child: child, elevation: elevation, margin: margin)

# ----- FloatingActionButton -----

type
  FloatingActionButton* = ref object of StatelessWidget
    onPressed*: TapCallback
    child*: Widget

method widgetTypeName*(w: FloatingActionButton): string = "FloatingActionButton"
method createElement*(w: FloatingActionButton): Element = newElement(ekStateless, w)
method build*(w: FloatingActionButton, ctx: BuildContext): Widget =
  let t = currentTheme()
  let body = decoratedBox(
    decoration = boxDecoration(color = t.colorScheme.primary,
                               borderRadius = 28, shape = bsCircle),
    child = sizedBox(width = 56, height = 56,
      child = center(child = w.child)))
  if w.onPressed.isNil: body
  else: gestureDetector(child = body, onTap = w.onPressed, behavior = htOpaque)

proc floatingActionButton*(child: Widget, onPressed: TapCallback = nil,
                           key: Key = nil): FloatingActionButton =
  FloatingActionButton(key: key, child: child, onPressed: onPressed)
