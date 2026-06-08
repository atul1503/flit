## Cupertino: iOS-styled widgets. Companion to Material.

import ../foundation/[widget, key, geometry, color]
import ../rendering/[decoration, text]
import ../widgets/basic
import ../gestures/detector

type
  CupertinoColors* = object
    activeBlue*:    Color
    systemBackground*: Color
    label*:         Color
    secondaryLabel*: Color
    separator*:     Color

const cupertinoLight* = CupertinoColors(
  activeBlue: rgb(0, 122, 255),
  systemBackground: colorWhite,
  label: colorBlack,
  secondaryLabel: rgb(60, 60, 67),
  separator: rgb(198, 198, 200))

const cupertinoDark* = CupertinoColors(
  activeBlue: rgb(10, 132, 255),
  systemBackground: colorBlack,
  label: colorWhite,
  secondaryLabel: rgb(235, 235, 245),
  separator: rgb(56, 56, 58))

type
  CupertinoTheme* = object
    brightness*: int  # 0 = light, 1 = dark
    colors*: CupertinoColors
    primaryColor*: Color
    fontFamily*: string

proc cupertinoTheme*(dark = false, fontFamily = "SF Pro"): CupertinoTheme =
  let c = if dark: cupertinoDark else: cupertinoLight
  CupertinoTheme(brightness: if dark: 1 else: 0,
                 colors: c, primaryColor: c.activeBlue, fontFamily: fontFamily)

var cupertinoCurrent*: CupertinoTheme = cupertinoTheme()

# ----- CupertinoApp -----

type
  CupertinoApp* = ref object of StatelessWidget
    home*: Widget
    theme*: CupertinoTheme

method widgetTypeName*(w: CupertinoApp): string = "CupertinoApp"
method createElement*(w: CupertinoApp): Element = newElement(ekStateless, w)
method build*(w: CupertinoApp, ctx: BuildContext): Widget =
  cupertinoCurrent = w.theme
  coloredBox(child = w.home, color = w.theme.colors.systemBackground)

proc cupertinoApp*(home: Widget, theme = cupertinoTheme(),
                   key: Key = nil): CupertinoApp =
  CupertinoApp(key: key, home: home, theme: theme)

# ----- CupertinoNavigationBar -----

type
  CupertinoNavigationBar* = ref object of StatelessWidget
    middle*: Widget
    leading*: Widget
    trailing*: Widget

method widgetTypeName*(w: CupertinoNavigationBar): string = "CupertinoNavigationBar"
method createElement*(w: CupertinoNavigationBar): Element = newElement(ekStateless, w)
method build*(w: CupertinoNavigationBar, ctx: BuildContext): Widget =
  let t = cupertinoCurrent
  var rowChildren: seq[Widget] = @[]
  if not w.leading.isNil: rowChildren.add(w.leading)
  rowChildren.add(expanded(center(child = w.middle)))
  if not w.trailing.isNil: rowChildren.add(w.trailing)
  decoratedBox(
    decoration = boxDecoration(color = t.colors.systemBackground.withOpacity(0.92)),
    child = sizedBox(height = 44,
      child = padding(padding = edgeInsetsSymmetric(16, 4),
        child = row(children = rowChildren, mainAxisSize = msMax,
                    crossAxisAlignment = caCenter))))

proc cupertinoNavigationBar*(middle: Widget, leading: Widget = nil,
                             trailing: Widget = nil,
                             key: Key = nil): CupertinoNavigationBar =
  CupertinoNavigationBar(key: key, middle: middle, leading: leading, trailing: trailing)

# ----- CupertinoButton -----

type
  CupertinoButton* = ref object of StatelessWidget
    onPressed*: TapCallback
    child*: Widget
    filled*: bool

method widgetTypeName*(w: CupertinoButton): string = "CupertinoButton"
method createElement*(w: CupertinoButton): Element = newElement(ekStateless, w)
method build*(w: CupertinoButton, ctx: BuildContext): Widget =
  let t = cupertinoCurrent
  var body: Widget
  if w.filled:
    body = decoratedBox(
      decoration = boxDecoration(color = t.primaryColor, borderRadius = 8),
      child = padding(padding = edgeInsetsSymmetric(20, 10), child = w.child))
  else:
    body = padding(padding = edgeInsetsSymmetric(16, 8), child = w.child)
  if w.onPressed.isNil: body
  else: gestureDetector(child = body, onTap = w.onPressed, behavior = htOpaque)

proc cupertinoButton*(child: Widget, onPressed: TapCallback = nil,
                      filled = false, key: Key = nil): CupertinoButton =
  CupertinoButton(key: key, child: child, onPressed: onPressed, filled: filled)
