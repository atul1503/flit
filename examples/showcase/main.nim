## flit showcase: a tour of nearly every flit feature in one app.
##
## Six tabs across the top, switchable by tap, each demonstrates a different
## slice of the framework:
##
##   Home       a counter, hero text, two button styles, theme toggle
##   Layout     Row + Column + Stack + Expanded/Flexible with every
##              MainAxisAlignment and CrossAxisAlignment value
##   Style      DecoratedBox variations: solid, rounded, circular,
##              bordered, shadowed, plus EdgeInsets variations
##   Inputs     all button types, GestureDetector with tap and pan,
##              a draggable puck and a "hold to charge" indicator
##   Animation  AnimationController + Tween + every built-in curve
##   Cupertino  iOS-styled tab, navigation bar and buttons in one frame
##
## Build:
##
##   nim c -d:release -o:bin/showcase examples/showcase/main.nim
##
## then `./bin/showcase` (on macOS you may need
## `DYLD_LIBRARY_PATH=/opt/homebrew/lib`).

import ../../src/flit
import std/[strutils, math]

# ---------------------------------------------------------------------------
# App state
# ---------------------------------------------------------------------------

type
  Tab* = enum
    tabHome, tabLayout, tabStyle, tabInputs, tabAnimation, tabState, tabCupertino

  Showcase* = ref object of StatefulWidget

  ShowcaseState* = ref object of State
    tab*: Tab
    darkMode*: bool
    counter*: int
    panOffset*: Offset
    panTapCount*: int
    holdProgress*: float32
    animController*: AnimationController
    animPos*: float32
    selectedCurve*: int
    tapLog*: int   # surfaces onDoubleTap demo result

# Module-level shared state for the "State" tab. Declared here (NOT
# on ShowcaseState) so we can demonstrate that ValueNotifiers can
# live anywhere - module scope, on a State, or anywhere else - and
# that watchers find them via direct reference. These notifiers
# persist across tab switches: incrementing the counter, switching
# to another tab, and switching back will show the updated value.
let sharedCount* = newValueNotifier(0)
let sharedLabel* = newValueNotifier("Atul")

method widgetTypeName*(w: Showcase): string = "Showcase"
method createElement*(w: Showcase): Element = newElement(ekStateful, w)
method createState*(w: Showcase): State =
  ShowcaseState(tab: tabHome, darkMode: false, counter: 0,
                panOffset: Offset(dx: 120, dy: 60), holdProgress: 0,
                animPos: 0, selectedCurve: 0, tapLog: 0)

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

proc tabLabel(tab: Tab): string =
  case tab
  of tabHome:      "Home"
  of tabLayout:    "Layout"
  of tabStyle:     "Style"
  of tabInputs:    "Inputs"
  of tabAnimation: "Anim"
  of tabState:     "State"
  of tabCupertino: "Cupertino"

proc heading(s: string, size = 24.0'f32): Widget =
  padding(
    child = text(s, style = textStyle(fontSize = size, fontWeight = 600,
                                      color = currentTheme().colorScheme.onSurface)),
    padding = edgeInsetsOnly(top = 12, bottom = 6))

proc body(s: string): Widget =
  text(s, style = textStyle(fontSize = 14,
                            color = currentTheme().colorScheme.onSurface))

proc divider(): Widget =
  padding(
    child = sizedBox(height = 1,
      child = coloredBox(color = currentTheme().colorScheme.outline)),
    padding = edgeInsetsSymmetric(0, 8))

# Horizontal progress bar via Row + Expanded with integer flex weights, so
# the filled portion grows proportionally to `progress` (0..1) regardless
# of the parent's width. Avoids needing widthFactor to know the parent
# size at construction time.
proc progressBar(progress: float32, height: float32 = 24.0'f32): Widget =
  let scheme = currentTheme().colorScheme
  let p = clamp(progress, 0.0'f32, 1.0'f32)
  let filled = int(p * 1000.0'f32)
  let empty  = max(1, 1000 - filled)
  var children: seq[Widget] = @[]
  if filled > 0:
    children.add(expanded(
      decoratedBox(
        decoration = boxDecoration(color = scheme.primary, borderRadius = height / 2)),
      flex = filled))
  children.add(expanded(
    coloredBox(color = colorTransparent),
    flex = empty))
  sizedBox(height = height,
    child = decoratedBox(
      decoration = boxDecoration(color = scheme.primaryContainer.withOpacity(0.3),
        borderRadius = height / 2,
        border = Border(color: scheme.outline, width: 1)),
      child = row(mainAxisSize = msMax, crossAxisAlignment = caStretch,
                  children = children)))

# Tap-able tab pill rendered manually so we can demo Decoration + Gesture.
proc tabPill(s: ShowcaseState, t: Tab): Widget =
  let active = s.tab == t
  let theme  = currentTheme()
  let bg     = if active: theme.colorScheme.primary
               else: theme.colorScheme.surface
  let fg     = if active: theme.colorScheme.onPrimary
               else: theme.colorScheme.onSurface
  gestureDetector(
    behavior = htOpaque,
    onTap = proc() = setState(s, proc() = s.tab = t),
    child = padding(
      child = decoratedBox(
        decoration = boxDecoration(color = bg, borderRadius = 16,
          border = Border(color: theme.colorScheme.outline, width: 1)),
        child = padding(
          child = text(tabLabel(t),
                       style = textStyle(fontSize = 13, color = fg,
                                         fontWeight = if active: 600 else: 400)),
          padding = edgeInsetsSymmetric(horizontal = 14, vertical = 8))),
      padding = edgeInsetsAll(4)))

proc tabBar(s: ShowcaseState): Widget =
  let pills: seq[Widget] = @[
    tabPill(s, tabHome),
    tabPill(s, tabLayout),
    tabPill(s, tabStyle),
    tabPill(s, tabInputs),
    tabPill(s, tabAnimation),
    tabPill(s, tabState),
    tabPill(s, tabCupertino),
  ]
  padding(
    child = row(crossAxisAlignment = caCenter,
                mainAxisAlignment = maStart,
                mainAxisSize = msMax,
                children = pills),
    padding = edgeInsetsSymmetric(horizontal = 8, vertical = 4))

# ---------------------------------------------------------------------------
# Home tab
# ---------------------------------------------------------------------------

proc homeTab(s: ShowcaseState): Widget =
  let scheme = currentTheme().colorScheme
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                   children = @[
      heading("flit Showcase", 32.0'f32),
      body("Every tab demonstrates a different corner of the framework."),
      sizedBox(height = 16),
      decoratedBox(
        decoration = boxDecoration(color = scheme.primaryContainer,
          borderRadius = 12,
          border = Border(color: scheme.outline, width: 1)),
        child = padding(
          padding = edgeInsetsAll(16),
          child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                         children = @[
            Widget(text("You have pressed the button:",
              style = textStyle(fontSize = 14, color = scheme.onSurface))),
            sizedBox(height = 8),
            text($s.counter,
              style = textStyle(fontSize = 56, fontWeight = 700,
                                color = scheme.primary)),
            sizedBox(height = 8),
            row(mainAxisSize = msMin, mainAxisAlignment = maStart, children = @[
              Widget(elevatedButton(
                child = text("Increment",
                  style = textStyle(fontSize = 14, color = colorWhite)),
                onPressed = proc() = setState(s, proc() = inc s.counter))),
              sizedBox(width = 12),
              textButton(
                child = text("Reset",
                  style = textStyle(fontSize = 14, color = scheme.primary)),
                onPressed = proc() = setState(s, proc() = s.counter = 0))]),
          ]))),
      sizedBox(height = 24),
      heading("Theme"),
      body("Toggle between Material 3 light and dark color schemes."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, children = @[
        Widget(elevatedButton(
          child = text(if s.darkMode: "Switch to Light" else: "Switch to Dark",
            style = textStyle(fontSize = 13, color = colorWhite)),
          onPressed = proc() = setState(s, proc() = s.darkMode = not s.darkMode))),
      ]),
    ]))

# ---------------------------------------------------------------------------
# Layout tab: Row, Column, Stack, Expanded, alignments
# ---------------------------------------------------------------------------

proc box(label: string, color: Color, w = 60.0'f32, h = 40.0'f32): Widget =
  decoratedBox(
    decoration = boxDecoration(color = color, borderRadius = 6),
    child = sizedBox(width = w, height = h,
      child = center(child = text(label,
        style = textStyle(fontSize = 12, color = colorWhite,
                          fontWeight = 600)))))

proc rowDemo(label: string, ma: MainAxisAlignment): Widget =
  padding(
    padding = edgeInsetsSymmetric(horizontal = 0, vertical = 4),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                   children = @[
      Widget(body(label)),
      sizedBox(height = 4),
      decoratedBox(
        decoration = boxDecoration(
          color = currentTheme().colorScheme.surface,
          borderRadius = 4,
          border = Border(color: currentTheme().colorScheme.outline, width: 1)),
        child = sizedBox(height = 56,
          child = padding(
            padding = edgeInsetsAll(8),
            child = row(mainAxisAlignment = ma, mainAxisSize = msMax,
                        children = @[
                          box("a", colorBlue),
                          box("b", colorTeal),
                          box("c", colorPurple)]))))]))

proc layoutTab(s: ShowcaseState): Widget =
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
      Widget(heading("Row mainAxisAlignment")),
      rowDemo("maStart",        maStart),
      rowDemo("maEnd",          maEnd),
      rowDemo("maCenter",       maCenter),
      rowDemo("maSpaceBetween", maSpaceBetween),
      rowDemo("maSpaceAround",  maSpaceAround),
      rowDemo("maSpaceEvenly",  maSpaceEvenly),
      divider(),
      heading("Expanded + Flexible"),
      body("Three children with flex 1, 2, 1. Middle child takes twice the space."),
      sizedBox(height = 8),
      decoratedBox(
        decoration = boxDecoration(
          color = currentTheme().colorScheme.surface, borderRadius = 6,
          border = Border(color: currentTheme().colorScheme.outline, width: 1)),
        child = sizedBox(height = 60,
          child = row(crossAxisAlignment = caStretch, children = @[
            Widget(expanded(box("1", colorRed))),
            expanded(box("2", colorGreen), flex = 2),
            expanded(box("3", colorOrange))]))),
      divider(),
      heading("Stack + Positioned"),
      body("Three children layered. The yellow circle is absolutely positioned."),
      sizedBox(height = 8),
      decoratedBox(
        decoration = boxDecoration(
          color = currentTheme().colorScheme.surface, borderRadius = 6,
          border = Border(color: currentTheme().colorScheme.outline, width: 1)),
        child = sizedBox(height = 140,
          child = stack(alignment = alignCenter, fit = sfExpand, children = @[
            Widget(decoratedBox(
              decoration = boxDecoration(color = colorBlue.withOpacity(0.25)))),
            text("centered text", style = textStyle(fontSize = 16)),
            positioned(
              child = decoratedBox(
                decoration = boxDecoration(color = colorYellow, shape = bsCircle),
                child = sizedBox(width = 40, height = 40)),
              top = 10, right = 10)]))),
    ]))

# ---------------------------------------------------------------------------
# Style tab: every decoration option
# ---------------------------------------------------------------------------

proc styleSwatch(label: string, decoration: BoxDecoration): Widget =
  padding(
    padding = edgeInsetsAll(6),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caCenter, children = @[
      Widget(decoratedBox(decoration = decoration,
        child = sizedBox(width = 80, height = 60))),
      sizedBox(height = 4),
      text(label, style = textStyle(fontSize = 11))]))

proc styleTab(s: ShowcaseState): Widget =
  let scheme = currentTheme().colorScheme
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
      Widget(heading("Decorations")),
      body("Boxes with color, radius, border, circle shape and drop shadow."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, crossAxisAlignment = caStart,
          children = @[
        styleSwatch("solid",
          boxDecoration(color = colorRed)),
        styleSwatch("rounded",
          boxDecoration(color = colorBlue, borderRadius = 12)),
        styleSwatch("circle",
          boxDecoration(color = colorGreen, shape = bsCircle)),
        styleSwatch("border",
          boxDecoration(color = colorAmber, borderRadius = 8,
            border = Border(color: colorBlack, width: 3))),
        styleSwatch("shadow", BoxDecoration(
          color: scheme.surface, borderRadius: 8, hasBorder: false,
          shadows: @[BoxShadow(color: colorBlack.withOpacity(0.35),
            offset: Offset(dx: 0, dy: 4), blur: 8, spread: 0)])),
      ]),
      divider(),
      heading("Border radii"),
      sizedBox(height = 4),
      row(mainAxisAlignment = maStart, crossAxisAlignment = caEnd,
          children = @[
        styleSwatch("0",  boxDecoration(color = colorPurple, borderRadius = 0)),
        styleSwatch("4",  boxDecoration(color = colorPurple, borderRadius = 4)),
        styleSwatch("12", boxDecoration(color = colorPurple, borderRadius = 12)),
        styleSwatch("30", boxDecoration(color = colorPurple, borderRadius = 30)),
      ]),
      divider(),
      heading("EdgeInsets"),
      body("Each card has the same 60x40 inner square; the surrounding padding shows the inset shape."),
      sizedBox(height = 8),
      block:
        proc swatch(label: string, p: EdgeInsets): Widget =
          padding(padding = edgeInsetsAll(6),
            child = column(mainAxisSize = msMin, crossAxisAlignment = caCenter,
                           children = @[
              Widget(decoratedBox(
                decoration = boxDecoration(color = scheme.primaryContainer,
                                           borderRadius = 6,
                                           border = Border(color: scheme.outline, width: 1)),
                child = padding(padding = p,
                  child = decoratedBox(
                    decoration = boxDecoration(color = scheme.primary, borderRadius = 4),
                    child = sizedBox(width = 60, height = 40))))),
              sizedBox(height = 4),
              text(label, style = textStyle(fontSize = 11,
                                            color = scheme.onSurface))]))
        row(mainAxisAlignment = maStart, crossAxisAlignment = caStart,
            children = @[
          swatch("all(8)",          edgeInsetsAll(8)),
          swatch("sym(h=20,v=4)",   edgeInsetsSymmetric(horizontal = 20, vertical = 4)),
          swatch("only(top=24)",    edgeInsetsOnly(top = 24)),
          swatch("LTRB(2,4,24,16)", edgeInsetsLTRB(2, 4, 24, 16)),
        ]),
      divider(),
      heading("AspectRatio"),
      body("Each box has the SAME maxWidth=200 but a different ratio."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, crossAxisAlignment = caStart,
          children = @[
        Widget(sizedBox(width = 80, height = 80,
          child = aspectRatio(
            child = decoratedBox(decoration = boxDecoration(color = colorTeal,
                                                            borderRadius = 4)),
            aspectRatio = 1.0'f32))),
        sizedBox(width = 8),
        sizedBox(width = 120, height = 80,
          child = aspectRatio(
            child = decoratedBox(decoration = boxDecoration(color = colorIndigo,
                                                            borderRadius = 4)),
            aspectRatio = 2.0'f32)),
        sizedBox(width = 8),
        sizedBox(width = 60, height = 80,
          child = aspectRatio(
            child = decoratedBox(decoration = boxDecoration(color = colorOrange,
                                                            borderRadius = 4)),
            aspectRatio = 0.5'f32)),
      ]),
      sizedBox(height = 12),
      body("ratios above: 1.0 (square), 2.0 (landscape), 0.5 (portrait)"),
      divider(),
      heading("Opacity"),
      body("opacity 1.0 -> 0.6 -> 0.3 -> 0.1 applied to the same purple box."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
          children = @[
        Widget(opacity(child = sizedBox(width = 80, height = 50,
          child = coloredBox(color = scheme.primary)), opacity = 1.0'f32)),
        sizedBox(width = 12),
        opacity(child = sizedBox(width = 80, height = 50,
          child = coloredBox(color = scheme.primary)), opacity = 0.6'f32),
        sizedBox(width = 12),
        opacity(child = sizedBox(width = 80, height = 50,
          child = coloredBox(color = scheme.primary)), opacity = 0.3'f32),
        sizedBox(width = 12),
        opacity(child = sizedBox(width = 80, height = 50,
          child = coloredBox(color = scheme.primary)), opacity = 0.1'f32),
      ]),
      divider(),
      heading("ClipRRect"),
      body("Same orange child painted twice; right is clipped to a " &
           "rounded rect with radius 24."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, crossAxisAlignment = caCenter,
          children = @[
        Widget(sizedBox(width = 100, height = 60,
          child = coloredBox(color = colorOrange))),
        sizedBox(width = 24),
        clipRRect(
          child = sizedBox(width = 100, height = 60,
            child = coloredBox(color = colorOrange)),
          radius = 24.0'f32),
      ]),
      divider(),
      heading("TextStyle"),
      sizedBox(height = 4),
      text("regular 14",         style = textStyle(fontSize = 14)),
      text("bold 14",             style = textStyle(fontSize = 14, fontWeight = 700)),
      text("italic 14",           style = textStyle(fontSize = 14, italic = true)),
      text("large 24",            style = textStyle(fontSize = 24)),
      text("colored",             style = textStyle(fontSize = 14, color = colorRed)),
      text("light + spaced",      style = textStyle(fontSize = 14, fontWeight = 300,
                                                    letterSpacing = 2.0'f32,
                                                    color = scheme.outline)),
    ]))

# ---------------------------------------------------------------------------
# Inputs tab: every gesture and button
# ---------------------------------------------------------------------------

proc inputsTab(s: ShowcaseState): Widget =
  let scheme = currentTheme().colorScheme
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
      Widget(heading("Buttons")),
      sizedBox(height = 4),
      row(mainAxisAlignment = maStart, children = @[
        Widget(elevatedButton(child = text("Elevated",
          style = textStyle(fontSize = 14, color = colorWhite)),
          onPressed = proc() = setState(s, proc() = inc s.panTapCount))),
        sizedBox(width = 8),
        textButton(child = text("Text button",
          style = textStyle(fontSize = 14, color = scheme.primary)),
          onPressed = proc() = setState(s, proc() = inc s.panTapCount)),
        sizedBox(width = 8),
        floatingActionButton(child = text("+",
          style = textStyle(fontSize = 22, color = colorWhite)),
          onPressed = proc() = setState(s, proc() = inc s.panTapCount)),
      ]),
      sizedBox(height = 8),
      body("Total taps across the three above: " & $s.panTapCount),
      divider(),
      heading("Double tap"),
      body("Tap the box once (single tap log goes up). Tap it twice " &
           "within 300ms - onDoubleTap fires and the second tap is " &
           "CONSUMED (single-tap log does NOT increase a second time)."),
      sizedBox(height = 8),
      row(mainAxisSize = msMin, crossAxisAlignment = caCenter, children = @[
        Widget(gestureDetector(
          behavior = htOpaque,
          onTap = (proc() = setState(s, proc() = inc s.panTapCount)),
          onDoubleTap = (proc() = setState(s, proc() = s.tapLog += 100)),
          child = sizedBox(width = 100, height = 60,
            child = decoratedBox(
              decoration = boxDecoration(color = scheme.primary,
                                         borderRadius = 8),
              child = center(child = text("tap me",
                style = textStyle(fontSize = 14, color = colorWhite))))))),
        sizedBox(width = 16),
        column(mainAxisSize = msMin, crossAxisAlignment = caStart, children = @[
          Widget(body("single taps: " & $s.panTapCount)),
          body("double-taps (each adds 100): " & $s.tapLog),
        ]),
      ]),
      divider(),
      heading("Pan: drag the puck"),
      body("onPanStart / onPanUpdate / onPanEnd move the circle below."),
      sizedBox(height = 4),
      decoratedBox(
        decoration = boxDecoration(color = scheme.surface, borderRadius = 8,
          border = Border(color: scheme.outline, width: 1)),
        child = sizedBox(height = 180,
          child = stack(alignment = alignTopLeft, fit = sfExpand, children = @[
            Widget(gestureDetector(
              behavior = htOpaque,
              onPanUpdate = proc(delta, position: Offset) =
                setState(s, proc() = s.panOffset = s.panOffset + delta),
              child = decoratedBox(
                decoration = boxDecoration(color = colorTransparent)))),
            positioned(
              left = s.panOffset.dx, top = s.panOffset.dy,
              child = decoratedBox(
                decoration = boxDecoration(color = scheme.primary,
                  shape = bsCircle),
                child = sizedBox(width = 40, height = 40,
                  child = center(child = text("drag",
                    style = textStyle(fontSize = 10, color = colorWhite))))))]))),
      divider(),
      heading("Hold to charge"),
      body("Press and hold the bar; release to reset."),
      sizedBox(height = 4),
      gestureDetector(
        behavior = htOpaque,
        onPanStart = (proc(p: Offset) =
          setState(s, proc() = s.holdProgress = 0.05'f32)),
        onPanUpdate = (proc(delta, position: Offset) =
          setState(s, proc() =
            s.holdProgress = clamp(s.holdProgress + 0.02'f32,
                                   0.0'f32, 1.0'f32))),
        onPanEnd = (proc() = setState(s, proc() = s.holdProgress = 0)),
        onTap = (proc() = setState(s, proc() = s.holdProgress = 0)),
        child = progressBar(s.holdProgress, height = 24.0'f32)),
      sizedBox(height = 4),
      body("charge: " & formatFloat(s.holdProgress, ffDecimal, 2)),
    ]))

# ---------------------------------------------------------------------------
# Animation tab: AnimationController + every built-in curve
# ---------------------------------------------------------------------------

proc curveByName(name: string): Curve =
  case name
  of "linear":     curveLinear
  of "easeIn":     curveEaseIn
  of "easeOut":    curveEaseOut
  of "easeInOut":  curveEaseInOut
  of "bounceOut":  curveBounceOut
  of "elasticIn":  curveElasticIn
  else:            curveLinear

const curveNames = ["linear", "easeIn", "easeOut", "easeInOut",
                    "bounceOut", "elasticIn"]

proc animationTab(s: ShowcaseState): Widget =
  let scheme = currentTheme().colorScheme

  # Closure-in-loop: Nim's loop variable is reused across iterations and
  # closures capturing it by reference all see the LAST value. Wrap the
  # tap callback creation in a proc so the captured `idx` is a fresh
  # parameter binding per call.
  proc makePill(idx: int, label: string, active: bool): Widget =
    padding(
      padding = edgeInsetsAll(2),
      child = gestureDetector(
        behavior = htOpaque,
        onTap = (proc() = setState(s, proc() = s.selectedCurve = idx)),
        child = decoratedBox(
          decoration = boxDecoration(
            color = if active: scheme.primary else: scheme.surface,
            borderRadius = 12,
            border = Border(color: scheme.outline, width: 1)),
          child = padding(
            padding = edgeInsetsSymmetric(horizontal = 12, vertical = 6),
            child = text(label, style = textStyle(fontSize = 12,
              color = if active: scheme.onPrimary else: scheme.onSurface))))))

  var pillRow: seq[Widget] = @[]
  for i, n in curveNames:
    pillRow.add(makePill(i, n, s.selectedCurve == i))

  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
      Widget(heading("Animation curves")),
      body("Pick a curve, then press Run. The bar fills using that curve."),
      sizedBox(height = 8),
      row(mainAxisAlignment = maStart, mainAxisSize = msMax,
          crossAxisAlignment = caStart, children = pillRow),
      sizedBox(height = 12),
      progressBar(s.animPos, height = 30.0'f32),
      sizedBox(height = 12),
      block:
        proc ensureCtrl(): AnimationController =
          if s.animController.isNil:
            s.animController = newAnimationController(durationSec = 1.2'f32)
            s.animController.addListener(proc(v: float32) =
              setState(s, proc() = s.animPos = v))
          s.animController
        row(mainAxisAlignment = maStart, children = @[
          Widget(elevatedButton(
            child = text("Run", style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = (proc() =
              let c = ensureCtrl()
              c.value = 0
              c.forward(globalBinding, curveByName(curveNames[s.selectedCurve]))))),
          sizedBox(width = 6),
          elevatedButton(
            child = text("Reverse", style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = (proc() =
              let c = ensureCtrl()
              if c.value < 0.01'f32: c.value = 1.0'f32
              c.reverse(globalBinding, curveByName(curveNames[s.selectedCurve])))),
          sizedBox(width = 6),
          elevatedButton(
            child = text("To 0.5", style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = (proc() =
              let c = ensureCtrl()
              c.animateTo(globalBinding, 0.5'f32,
                          curve = curveByName(curveNames[s.selectedCurve])))),
          sizedBox(width = 6),
          elevatedButton(
            child = text("Repeat", style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = (proc() =
              let c = ensureCtrl()
              c.repeat(globalBinding, curveByName(curveNames[s.selectedCurve]),
                       reverse = true))),
          sizedBox(width = 6),
          elevatedButton(
            child = text("Stop", style = textStyle(fontSize = 14, color = colorWhite)),
            onPressed = (proc() =
              if not s.animController.isNil: s.animController.stop())),
          sizedBox(width = 6),
          textButton(child = text("Reset",
            style = textStyle(fontSize = 14, color = scheme.primary)),
            onPressed = (proc() = setState(s, proc() = s.animPos = 0))),
        ]),
      divider(),
      heading("Tween (manual)"),
      body("A Tween[float32] from 0 -> 360 evaluated at the animation value."),
      sizedBox(height = 4),
      body("current: " & formatFloat(
        lerp(0.0'f32, 360.0'f32, s.animPos), ffDecimal, 1) & " deg"),
    ]))

# ---------------------------------------------------------------------------
# State tab: ValueNotifier + ListenableBuilder + InheritedWidget.
# ---------------------------------------------------------------------------

# A tiny InheritedWidget carrying a string label. Descendants that
# call `dependOnInheritedOfType[LabelTheme](ctx)` will auto-rebuild
# when this widget instance is replaced with a different label.
type
  LabelTheme = ref object of InheritedWidget
    label: string

method widgetTypeName(w: LabelTheme): string = "LabelTheme"
method createElement(w: LabelTheme): Element = newElement(ekInherited, w)
method updateShouldNotify(w: LabelTheme, old: InheritedWidget): bool =
  LabelTheme(w).label != LabelTheme(old).label

# A stateless widget that reads LabelTheme via dependOnInheritedOfType.
# Two of these are placed in the tree to show that ALL dependents see
# the new value when the ancestor's label is replaced.
type
  LabelReader = ref object of StatelessWidget
    prefix: string

method widgetTypeName(w: LabelReader): string = "LabelReader"
method createElement(w: LabelReader): Element = newElement(ekStateless, w)
method build(w: LabelReader, ctx: BuildContext): Widget =
  let theme = dependOnInheritedOfType[LabelTheme](ctx)
  let lbl = if theme.isNil: "(no theme)" else: theme.label
  text(w.prefix & ": " & lbl,
       style = textStyle(fontSize = 14,
                         color = currentTheme().colorScheme.onSurface))

proc stateTab(s: ShowcaseState): Widget =
  let scheme = currentTheme().colorScheme
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch,
                   children = @[
      Widget(heading("ValueNotifier + ListenableBuilder")),
      body("Two notifiers live at module scope. Both watchers below " &
           "rebuild only when their notifier fires; the rest of this " &
           "tab does not. Try switching tabs and coming back - the " &
           "values persist because the notifiers outlive this tree."),
      sizedBox(height = 12),

      # Watcher 1: the int notifier
      decoratedBox(
        decoration = boxDecoration(color = scheme.primaryContainer,
                                   borderRadius = 8,
                                   border = Border(color: scheme.outline, width: 1)),
        child = padding(padding = edgeInsetsAll(12),
          child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                         children = @[
            Widget(text("sharedCount (watcher A)",
              style = textStyle(fontSize = 12, color = scheme.outline))),
            sizedBox(height = 4),
            listenableBuilder(sharedCount,
              proc(ctx: BuildContext, v: int): Widget =
                text("value = " & $v,
                  style = textStyle(fontSize = 24, fontWeight = 700,
                                    color = scheme.primary)))]))),
      sizedBox(height = 8),

      # Watcher 2: same notifier, different formatting. Both rebuild
      # together on update.
      decoratedBox(
        decoration = boxDecoration(color = scheme.primaryContainer,
                                   borderRadius = 8,
                                   border = Border(color: scheme.outline, width: 1)),
        child = padding(padding = edgeInsetsAll(12),
          child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                         children = @[
            Widget(text("sharedCount (watcher B, same notifier)",
              style = textStyle(fontSize = 12, color = scheme.outline))),
            sizedBox(height = 4),
            listenableBuilder(sharedCount,
              proc(ctx: BuildContext, v: int): Widget =
                text("v * 2 = " & $(v * 2),
                  style = textStyle(fontSize = 24, fontWeight = 700,
                                    color = scheme.primary)))]))),
      sizedBox(height = 12),

      # Buttons that mutate the notifier from OUTSIDE any watcher.
      # The buttons themselves are not watchers and don't rebuild
      # when the value changes.
      row(mainAxisSize = msMin, mainAxisAlignment = maStart, children = @[
        Widget(elevatedButton(
          child = text("Increment", style = textStyle(fontSize = 14, color = colorWhite)),
          onPressed = (proc() = sharedCount.value = sharedCount.value + 1))),
        sizedBox(width = 8),
        elevatedButton(
          child = text("Reset", style = textStyle(fontSize = 14, color = colorWhite)),
          onPressed = (proc() = sharedCount.value = 0)),
      ]),
      sizedBox(height = 24),

      # String notifier watcher
      heading("Watcher of a string notifier"),
      decoratedBox(
        decoration = boxDecoration(color = scheme.primaryContainer,
                                   borderRadius = 8,
                                   border = Border(color: scheme.outline, width: 1)),
        child = padding(padding = edgeInsetsAll(12),
          child = listenableBuilder(sharedLabel,
            proc(ctx: BuildContext, name: string): Widget =
              text("name = '" & name & "'",
                style = textStyle(fontSize = 18, fontWeight = 600,
                                  color = scheme.primary))))),
      sizedBox(height = 8),
      row(mainAxisSize = msMin, children = @[
        Widget(elevatedButton(child = text("Set to Atul",
          style = textStyle(fontSize = 13, color = colorWhite)),
          onPressed = (proc() = sharedLabel.value = "Atul"))),
        sizedBox(width = 8),
        elevatedButton(child = text("Set to Bob",
          style = textStyle(fontSize = 13, color = colorWhite)),
          onPressed = (proc() = sharedLabel.value = "Bob")),
        sizedBox(width = 8),
        elevatedButton(child = text("Set to Carol",
          style = textStyle(fontSize = 13, color = colorWhite)),
          onPressed = (proc() = sharedLabel.value = "Carol")),
      ]),
      sizedBox(height = 24),

      # InheritedWidget demo.
      heading("InheritedWidget + dependOnInheritedOfType"),
      body("Both readers below subscribe to LabelTheme via " &
           "dependOnInheritedOfType. When the parent rebuilds with " &
           "a NEW label, updateShouldNotify returns true and only " &
           "the registered dependents rebuild. The notifier above " &
           "drives the label."),
      sizedBox(height = 8),
      listenableBuilder(sharedLabel,
        proc(ctx: BuildContext, name: string): Widget =
          # Pass the notifier's value through as the inherited
          # widget's label. The inherited widget is re-emitted on
          # every listenable rebuild, but updateShouldNotify only
          # returns true when the label actually changed.
          LabelTheme(label: name, child: decoratedBox(
            decoration = boxDecoration(color = scheme.surface,
                                       borderRadius = 8,
                                       border = Border(color: scheme.outline, width: 1)),
            child = padding(padding = edgeInsetsAll(12),
              child = column(mainAxisSize = msMin, crossAxisAlignment = caStart,
                             children = @[
                Widget(LabelReader(prefix: "Reader 1 (Top of subtree)")),
                sizedBox(height = 6),
                LabelReader(prefix: "Reader 2 (nested deeper)"),
                sizedBox(height = 6),
                text("Static text - not a reader, NEVER rebuilds",
                  style = textStyle(fontSize = 12, color = scheme.outline,
                                    italic = true)),
              ]))))),
    ]))

# ---------------------------------------------------------------------------
# Cupertino tab: iOS-styled controls living inside the Material shell
# ---------------------------------------------------------------------------

proc cupertinoTab(s: ShowcaseState): Widget =
  let t = cupertinoTheme(dark = s.darkMode)
  cupertinoCurrent = t  # update ambient
  padding(
    padding = edgeInsetsAll(16),
    child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
      Widget(heading("Cupertino widgets")),
      body("The same setState-driven model with iOS-styled controls."),
      sizedBox(height = 8),
      cupertinoNavigationBar(
        leading = cupertinoButton(
          child = text("Back",
            style = textStyle(fontSize = 14, color = t.primaryColor)),
          onPressed = proc() = setState(s, proc() = s.tab = tabHome)),
        middle = text("Settings",
          style = textStyle(fontSize = 16, fontWeight = 600,
                            color = t.colors.label)),
        trailing = cupertinoButton(
          child = text("Done",
            style = textStyle(fontSize = 14, color = t.primaryColor)),
          onPressed = proc() = setState(s, proc() = s.counter = 0))),
      sizedBox(height = 16),
      decoratedBox(
        decoration = boxDecoration(color = t.colors.systemBackground,
          borderRadius = 10,
          border = Border(color: t.colors.separator, width: 1)),
        child = padding(
          padding = edgeInsetsAll(12),
          child = column(mainAxisSize = msMin, crossAxisAlignment = caStretch, children = @[
            Widget(row(mainAxisAlignment = maSpaceBetween,
                       crossAxisAlignment = caCenter, children = @[
              Widget(text("Tap count",
                style = textStyle(fontSize = 14, color = t.colors.label))),
              text($s.counter,
                style = textStyle(fontSize = 14, color = t.colors.secondaryLabel))])),
            sizedBox(height = 8),
            divider(),
            sizedBox(height = 8),
            row(mainAxisAlignment = maSpaceAround, children = @[
              Widget(cupertinoButton(filled = true,
                child = text("Increment",
                  style = textStyle(fontSize = 14, color = colorWhite)),
                onPressed = proc() = setState(s, proc() = inc s.counter))),
              cupertinoButton(
                child = text("Decrement",
                  style = textStyle(fontSize = 14, color = t.primaryColor)),
                onPressed = proc() = setState(s, proc() = dec s.counter)),
            ]),
          ]))),
    ]))

# ---------------------------------------------------------------------------
# Root build
# ---------------------------------------------------------------------------

proc currentTabContent(s: ShowcaseState): Widget =
  let inner = case s.tab
    of tabHome:      homeTab(s)
    of tabLayout:    layoutTab(s)
    of tabStyle:     styleTab(s)
    of tabInputs:    inputsTab(s)
    of tabAnimation: animationTab(s)
    of tabState:     stateTab(s)
    of tabCupertino: cupertinoTab(s)
  # Wrap every tab body in a vertical scroll view so content taller than
  # the window is reachable via mouse wheel / two-finger scroll.
  scrollView(inner, direction = axVertical)

method build*(s: ShowcaseState, ctx: BuildContext): Widget =
  # Set the ambient theme FIRST so every child widget that reads
  # `currentTheme()` during construction sees the right colors.
  let theme = themeData(if s.darkMode: bDark else: bLight)
  setTheme(theme)
  materialApp(
    title = "flit showcase",
    theme = theme,
    home = scaffold(
      appBar = appBar(
        title = text("flit showcase",
          style = textStyle(fontSize = 18, fontWeight = 600,
                            color = theme.colorScheme.onPrimary)),
        actions = @[
          Widget(textButton(
            child = text(if s.darkMode: "Light" else: "Dark",
              style = textStyle(fontSize = 14, color = theme.colorScheme.onPrimary)),
            onPressed = proc() = setState(s, proc() = s.darkMode = not s.darkMode)))]),
      body = column(crossAxisAlignment = caStretch, children = @[
        Widget(tabBar(s)),
        divider(),
        expanded(currentTabContent(s)),
      ]),
      floatingActionButton = floatingActionButton(
        child = text("?", style = textStyle(fontSize = 22, color = colorWhite)),
        onPressed = proc() = setState(s, proc() = s.tab = tabHome))))

when isMainModule:
  # Using a UniqueKey at the root, just to exercise the Key API.
  let app = Showcase(key: newUniqueKey())
  runApp(app)
