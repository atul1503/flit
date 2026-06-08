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
    tabHome, tabLayout, tabStyle, tabInputs, tabAnimation, tabCupertino

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

method widgetTypeName*(w: Showcase): string = "Showcase"
method createElement*(w: Showcase): Element = newElement(ekStateful, w)
method createState*(w: Showcase): State =
  ShowcaseState(tab: tabHome, darkMode: false, counter: 0,
                panOffset: Offset(dx: 120, dy: 60), holdProgress: 0,
                animPos: 0, selectedCurve: 0)

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
  var pillRow: seq[Widget] = @[]
  for i, n in curveNames:
    let idx = i
    let nm = n
    let active = s.selectedCurve == idx
    pillRow.add(padding(
      padding = edgeInsetsAll(2),
      child = gestureDetector(
        behavior = htOpaque,
        onTap = proc() = setState(s, proc() = s.selectedCurve = idx),
        child = decoratedBox(
          decoration = boxDecoration(
            color = if active: scheme.primary else: scheme.surface,
            borderRadius = 12,
            border = Border(color: scheme.outline, width: 1)),
          child = padding(
            padding = edgeInsetsSymmetric(horizontal = 12, vertical = 6),
            child = text(nm, style = textStyle(fontSize = 12,
              color = if active: scheme.onPrimary else: scheme.onSurface)))))))

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
      row(mainAxisAlignment = maStart, children = @[
        Widget(elevatedButton(
          child = text("Run", style = textStyle(fontSize = 14, color = colorWhite)),
          onPressed = proc() =
            let curve = curveByName(curveNames[s.selectedCurve])
            if s.animController.isNil:
              s.animController = newAnimationController(durationSec = 1.2'f32)
              s.animController.addListener(proc(v: float32) =
                setState(s, proc() = s.animPos = v))
            else:
              s.animController.value = 0
              s.animPos = 0
            s.animController.forward(globalBinding, curve))),
        sizedBox(width = 8),
        textButton(child = text("Reset",
          style = textStyle(fontSize = 14, color = scheme.primary)),
          onPressed = proc() = setState(s, proc() = s.animPos = 0)),
      ]),
      divider(),
      heading("Tween (manual)"),
      body("A Tween[float32] from 0 -> 360 evaluated at the animation value."),
      sizedBox(height = 4),
      body("current: " & formatFloat(
        lerp(0.0'f32, 360.0'f32, s.animPos), ffDecimal, 1) & " deg"),
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
  case s.tab
  of tabHome:      homeTab(s)
  of tabLayout:    layoutTab(s)
  of tabStyle:     styleTab(s)
  of tabInputs:    inputsTab(s)
  of tabAnimation: animationTab(s)
  of tabCupertino: cupertinoTab(s)

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
