## Cupertino: iOS-styled widgets. Companion to the Material library, for
## apps that want to look at home on iOS / macOS. The set is intentionally
## small: `CupertinoApp`, `CupertinoNavigationBar`, `CupertinoButton`.
## Colors come from a separate `CupertinoTheme` rather than the Material
## `ThemeData`, and the active theme lives in the `cupertinoCurrent` var.

import ../foundation/[widget, key, geometry, color]
import ../rendering/[decoration, text]
import ../widgets/basic
import ../gestures/detector

type
  CupertinoColors* = object
    ## A small set of system colors that mirror iOS's UIKit semantic
    ## colors. Used to build the active `CupertinoTheme`.
    activeBlue*:    Color  ## iOS system blue (tint for buttons, links).
    systemBackground*: Color  ## page background.
    label*:         Color  ## primary text color.
    secondaryLabel*: Color  ## secondary text color (captions, hints).
    separator*:     Color  ## hairline separator color.

const cupertinoLight* = CupertinoColors(
    ## Light-mode system colors mirroring UIKit.
  activeBlue: rgb(0, 122, 255),
  systemBackground: colorWhite,
  label: colorBlack,
  secondaryLabel: rgb(60, 60, 67),
  separator: rgb(198, 198, 200))

const cupertinoDark* = CupertinoColors(
    ## Dark-mode system colors mirroring UIKit.
  activeBlue: rgb(10, 132, 255),
  systemBackground: colorBlack,
  label: colorWhite,
  secondaryLabel: rgb(235, 235, 245),
  separator: rgb(56, 56, 58))

type
  CupertinoTheme* = object
    ## Ambient theme for Cupertino widgets. Set the active theme via
    ## `cupertinoCurrent = ...` or let a `CupertinoApp` do it for you.
    brightness*: int   ## 0 = light, 1 = dark.
    colors*: CupertinoColors  ## the active palette.
    primaryColor*: Color  ## tint color (usually `colors.activeBlue`).
    fontFamily*: string  ## default font family.

proc cupertinoTheme*(dark = false, fontFamily = "SF Pro"): CupertinoTheme =
  ## Builds a `CupertinoTheme`.
  ##
  ## Inputs:
  ## - `dark`: when `true`, returns a dark-mode theme using
  ##   `cupertinoDark` colors. Default `false` (light).
  ## - `fontFamily`: default font name for Cupertino widgets. Default
  ##   `"SF Pro"`.
  ##
  ## Output: a populated `CupertinoTheme` ready to assign to
  ## `cupertinoCurrent` or pass to `cupertinoApp(theme = ...)`.
  let c = if dark: cupertinoDark else: cupertinoLight
  CupertinoTheme(brightness: if dark: 1 else: 0,
                 colors: c, primaryColor: c.activeBlue, fontFamily: fontFamily)

var cupertinoCurrent*: CupertinoTheme = cupertinoTheme()
    ## The ambient Cupertino theme. Read by every Cupertino widget
    ## during its build. `CupertinoApp` assigns to this var as part of
    ## its own build.

# ----- CupertinoApp -----

type
  CupertinoApp* = ref object of StatelessWidget
    ## Top-level Cupertino app widget. Equivalent of `MaterialApp` for
    ## iOS-styled UIs.
    home*: Widget
    theme*: CupertinoTheme

method widgetTypeName*(w: CupertinoApp): string = "CupertinoApp"
method createElement*(w: CupertinoApp): Element = newElement(ekStateless, w)
method build*(w: CupertinoApp, ctx: BuildContext): Widget =
  ## Assigns `w.theme` to `cupertinoCurrent` (so descendant widgets
  ## pick it up via that var) and wraps `home` in a system-background
  ## `ColoredBox`.
  cupertinoCurrent = w.theme
  coloredBox(child = w.home, color = w.theme.colors.systemBackground)

proc cupertinoApp*(home: Widget, theme = cupertinoTheme(),
                   key: Key = nil): CupertinoApp =
  ## Builds a `CupertinoApp`.
  ##
  ## Inputs:
  ## - `home`: root widget. Required.
  ## - `theme`: `CupertinoTheme` to install. Defaults to light.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: assigns `theme` to `cupertinoCurrent` so descendants pick
  ## it up, then paints the system background behind `home`.
  CupertinoApp(key: key, home: home, theme: theme)

# ----- CupertinoNavigationBar -----

type
  CupertinoNavigationBar* = ref object of StatelessWidget
    ## A 44pt-tall iOS-style navigation bar with three slots: a leading
    ## widget on the left (commonly a back button), a centered title
    ## (`middle`), and a trailing widget on the right (commonly a done
    ## button). The background is the system background with 0.92 alpha
    ## to suggest the translucent effect iOS uses.
    middle*: Widget
    leading*: Widget
    trailing*: Widget

method widgetTypeName*(w: CupertinoNavigationBar): string = "CupertinoNavigationBar"
method createElement*(w: CupertinoNavigationBar): Element = newElement(ekStateless, w)
method build*(w: CupertinoNavigationBar, ctx: BuildContext): Widget =
  ## Builds `[leading?, expanded(center(middle)), trailing?]` inside
  ## a 44pt-tall translucent (0.92 alpha) background bar.
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
  ## Builds a `CupertinoNavigationBar`.
  ##
  ## Inputs:
  ## - `middle`: centered widget (title). Required.
  ## - `leading`: optional leading widget (back button).
  ## - `trailing`: optional trailing widget (action button).
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: lays out as `[leading?, expanded(center(middle)), trailing?]`
  ## inside a 44pt-tall bar with translucent system background.
  CupertinoNavigationBar(key: key, middle: middle, leading: leading, trailing: trailing)

# ----- CupertinoButton -----

type
  CupertinoButton* = ref object of StatelessWidget
    ## iOS-style button. Two flavors: plain (just a tappable label in
    ## the tint color) and filled (a rounded rectangle in the tint
    ## color with contrast text).
    onPressed*: TapCallback
    child*: Widget
    filled*: bool

method widgetTypeName*(w: CupertinoButton): string = "CupertinoButton"
method createElement*(w: CupertinoButton): Element = newElement(ekStateless, w)
method build*(w: CupertinoButton, ctx: BuildContext): Widget =
  ## When `filled`, builds a tint-colored rounded (8px) rectangle
  ## with the child wrapped in `edgeInsetsSymmetric(20, 10)`. When
  ## not filled, just wraps the child in `edgeInsetsSymmetric(16, 8)`
  ## padding. Wrapped in a `GestureDetector` if `onPressed` is set.
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
  ## Builds a `CupertinoButton`.
  ##
  ## Inputs:
  ## - `child`: button label. Required.
  ## - `onPressed`: tap callback.
  ## - `filled`: if `true`, render as a filled rounded rectangle (8px
  ##   radius). If `false` (default), render as a plain text-style
  ##   tappable label.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: paints either a tint-filled pill or just padded text, both
  ## tappable when `onPressed` is provided.
  CupertinoButton(key: key, child: child, onPressed: onPressed, filled: filled)
