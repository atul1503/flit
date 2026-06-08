## Material Design widget library: `MaterialApp`, `Scaffold`, `AppBar`,
## `ElevatedButton`, `TextButton`, `Card`, `FloatingActionButton`.
##
## Every widget reads its colors and typography from the ambient
## `ThemeData` set via `setTheme(...)` (see `flit/material/theme`). To
## use these widgets, call `setTheme(themeData(...))` near the top of
## your root widget's `build` (or rely on `MaterialApp` to do it for
## you), then compose freely.

import ../foundation/[widget, key, geometry, color]
import ../rendering/[decoration, text]
import ../widgets/basic
import ../gestures/detector
import ./theme

# ----- MaterialApp -----

type
  MaterialApp* = ref object of StatelessWidget
    ## Top-level Material widget. Holds the app's title, theme and the
    ## root child (`home`). Paints the theme's background color behind
    ## the home tree.
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
  ## Builds a `MaterialApp`, the standard root of a Material UI.
  ##
  ## Inputs:
  ## - `home`: the widget displayed below the system chrome. Usually a
  ##   `Scaffold`. Required.
  ## - `title`: window/app title (used by the platform shell when
  ##   available). Defaults to "Flit App".
  ## - `theme`: the `ThemeData` to install as the ambient theme.
  ##   Defaults to a fresh light `themeData()`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: pushes `theme` onto the ambient theme stack, then paints a
  ## background of `theme.colorScheme.background` behind `home`.
  MaterialApp(key: key, home: home, title: title, theme: theme)

# ----- Scaffold -----

type
  Scaffold* = ref object of StatelessWidget
    ## Standard Material page layout. Stacks an optional `appBar` on top
    ## of `body`, optionally with a `floatingActionButton` anchored to
    ## the bottom-right corner. Mirrors Flutter's `Scaffold`.
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
  ## Builds a `Scaffold`.
  ##
  ## Inputs:
  ## - `body`: the main content of the page. Required.
  ## - `appBar`: optional top bar widget (usually an `AppBar`).
  ## - `floatingActionButton`: optional FAB pinned 16px from the
  ##   bottom-right corner.
  ## - `backgroundColor`: explicit page background.
  ## - `hasBackgroundColor`: must be `true` for `backgroundColor` to
  ##   override the theme's default background.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: lays out as a column [appBar?, expanded(body)], paints the
  ## background, and if `floatingActionButton` is set, stacks it over
  ## the top-right portion of the page.
  Scaffold(key: key, body: body, appBar: appBar,
           floatingActionButton: floatingActionButton,
           backgroundColor: backgroundColor,
           hasBackgroundColor: hasBackgroundColor)

# ----- AppBar -----

type
  AppBar* = ref object of StatelessWidget
    ## Material app bar: a 56px-tall header with a title on the left and
    ## optional `actions` widgets on the right. Painted in the theme's
    ## primary color by default.
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
  ## Builds an `AppBar`.
  ##
  ## Inputs:
  ## - `title`: widget displayed at the leading edge (usually a `text`).
  ##   Required.
  ## - `actions`: trailing widgets, typically icon-like text buttons.
  ## - `backgroundColor`: explicit fill. Used only when
  ##   `hasBackgroundColor` is `true`; otherwise the theme's primary
  ##   color is used.
  ## - `hasBackgroundColor`: must be `true` for `backgroundColor` to
  ##   take effect.
  ## - `elevation`: shadow elevation. Stored on the widget but only
  ##   rendered when the backend supports box shadows; currently a
  ##   no-op visually.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: builds a 56px-tall row with the title (expanded) followed
  ## by the action widgets.
  AppBar(key: key, title: title, actions: actions,
         backgroundColor: backgroundColor,
         hasBackgroundColor: hasBackgroundColor, elevation: elevation)

# ----- Buttons -----

type
  ElevatedButton* = ref object of StatelessWidget
    ## Material "elevated" (high-emphasis) button. Filled background in
    ## the primary color with contrasting label text.
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
  ## Builds an `ElevatedButton`.
  ##
  ## Inputs:
  ## - `child`: button label, usually a `text` widget. Required.
  ## - `onPressed`: callback fired on tap. If `nil`, the button does
  ##   nothing when tapped (visually present but inert).
  ## - `backgroundColor`, `foregroundColor`: explicit colors. Used only
  ##   when `hasColors` is `true`; otherwise theme primary / onPrimary
  ##   are used.
  ## - `hasColors`: opt-in for the explicit colors above.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: renders a filled rounded rectangle (radius 20) with the
  ## child inside `edgeInsetsSymmetric(24, 12)` padding. The whole
  ## rectangle is tappable.
  ElevatedButton(key: key, child: child, onPressed: onPressed,
                 backgroundColor: backgroundColor,
                 foregroundColor: foregroundColor, hasColors: hasColors)

type
  TextButton* = ref object of StatelessWidget
    ## Material "text" (low-emphasis) button. Just a tappable label with
    ## padding; no background fill.
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
  ## Builds a `TextButton`.
  ##
  ## Inputs:
  ## - `child`: button label. Required.
  ## - `onPressed`: callback fired on tap.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: wraps `child` in `edgeInsetsSymmetric(16, 8)` padding and
  ## makes the padded box tappable.
  TextButton(key: key, child: child, onPressed: onPressed)

# ----- Card -----

type
  Card* = ref object of StatelessWidget
    ## A surface-colored container with rounded corners and an outer
    ## margin. Used to group related content. Matches Flutter's `Card`
    ## but without the shadow elevation rendering.
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
  ## Builds a `Card`.
  ##
  ## Inputs:
  ## - `child`: content inside the card. Required.
  ## - `elevation`: shadow depth. Stored but not rendered (the canvas
  ##   backend currently lacks proper drop-shadow blur).
  ## - `margin`: outside spacing. Defaults to `edgeInsetsAll(8)`.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: paints a rounded surface (`theme.colorScheme.surface` filled
  ## with `theme.defaultRadius` corner radius) and embeds `child` inside,
  ## with `margin` of empty space around the card.
  Card(key: key, child: child, elevation: elevation, margin: margin)

# ----- FloatingActionButton -----

type
  FloatingActionButton* = ref object of StatelessWidget
    ## A 56x56 circular button in the theme's primary color, intended
    ## for the most prominent action on a screen.
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
  ## Builds a `FloatingActionButton`.
  ##
  ## Inputs:
  ## - `child`: contents of the FAB, usually a single character (`"+"`,
  ##   `"?"`) or a small icon. Required.
  ## - `onPressed`: callback fired on tap.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: paints a 56x56 circle in the theme's primary color with
  ## the child centered.
  FloatingActionButton(key: key, child: child, onPressed: onPressed)
