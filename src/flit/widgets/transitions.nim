## Route transition widgets. Wrap a pushed Navigator route in one
## of these and it animates in from the chosen direction. Each
## transition owns its own `AnimationController`, runs forward on
## mount, and reverses on dispose if requested.
##
## Use directly:
##
## .. code-block:: nim
##   slideInLeft(child = detailScreen())
##
## Or via the Navigator integration:
##
## .. code-block:: nim
##   currentNavigator().push(proc(): Widget = detailScreen(),
##                           transition = trSlideLeft)

import ../foundation/[widget, render_object, geometry, color, key,
                       runtime, binding]
import ../animation/animation
import ./basic

type
  RouteTransitionKind* = enum
    ## Built-in transition kinds. `trNone` skips the animation.
    trNone, trFade, trSlideLeft, trSlideRight, trSlideUp, trSlideDown, trScale

  SlideIn* = ref object of StatefulWidget
    direction*:   RouteTransitionKind  # trSlideLeft / Right / Up / Down
    child*:       Widget
    durationMs*:  int

  FadeIn* = ref object of StatefulWidget
    child*:       Widget
    durationMs*:  int

  ScaleIn* = ref object of StatefulWidget
    child*:       Widget
    durationMs*:  int

  SlideInState = ref object of State
    controller: AnimationController
  FadeInState = ref object of State
    controller: AnimationController
  ScaleInState = ref object of State
    controller: AnimationController

method widgetTypeName*(w: SlideIn): string = "SlideIn"
method createElement*(w: SlideIn): Element = newElement(ekStateful, w)
method createState*(w: SlideIn): State = SlideInState()

method initState(s: SlideInState) =
  let host = SlideIn(s.element.widget)
  s.controller = newAnimationController(
    durationSec = (if host.durationMs > 0: host.durationMs.float32 / 1000.0 else: 0.25))
  s.controller.addListener(proc(v: float32) =
    setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.controller.forward(globalBinding)

method dispose(s: SlideInState) =
  if not s.controller.isNil: s.controller.dispose()

method build*(s: SlideInState, ctx: BuildContext): Widget =
  let host = SlideIn(s.element.widget)
  # Ease-out for a natural settling feel.
  let t = curveEaseOut(s.controller.value)
  # 1 -> 0 (we start off-screen and settle to in-place).
  let progress = 1.0'f32 - t
  # 400px slide distance. Could be plumbed from constraints later
  # for full-viewport slides; for now this matches typical phone
  # screen widths.
  const dist = 400.0'f32
  var dx, dy: float32 = 0.0
  case host.direction
  of trSlideLeft:  dx = progress * dist
  of trSlideRight: dx = -progress * dist
  of trSlideUp:    dy = progress * dist
  of trSlideDown:  dy = -progress * dist
  else: discard
  transform(translation = Offset(dx: dx, dy: dy), child = host.child)

method widgetTypeName*(w: FadeIn): string = "FadeIn"
method createElement*(w: FadeIn): Element = newElement(ekStateful, w)
method createState*(w: FadeIn): State = FadeInState()

method initState(s: FadeInState) =
  let host = FadeIn(s.element.widget)
  s.controller = newAnimationController(
    durationSec = (if host.durationMs > 0: host.durationMs.float32 / 1000.0 else: 0.20))
  s.controller.addListener(proc(v: float32) =
    setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.controller.forward(globalBinding)

method dispose(s: FadeInState) =
  if not s.controller.isNil: s.controller.dispose()

method build*(s: FadeInState, ctx: BuildContext): Widget =
  opacity(child = FadeIn(s.element.widget).child, opacity = s.controller.value)

method widgetTypeName*(w: ScaleIn): string = "ScaleIn"
method createElement*(w: ScaleIn): Element = newElement(ekStateful, w)
method createState*(w: ScaleIn): State = ScaleInState()

method initState(s: ScaleInState) =
  let host = ScaleIn(s.element.widget)
  s.controller = newAnimationController(
    durationSec = (if host.durationMs > 0: host.durationMs.float32 / 1000.0 else: 0.20))
  s.controller.addListener(proc(v: float32) =
    setState(s, proc() = discard))
  if not globalBinding.isNil:
    s.controller.forward(globalBinding)

method dispose(s: ScaleInState) =
  if not s.controller.isNil: s.controller.dispose()

method build*(s: ScaleInState, ctx: BuildContext): Widget =
  let t = curveEaseOut(s.controller.value)
  # Start at 0.85, settle at 1.0.
  let scaleVal = 0.85'f32 + 0.15'f32 * t
  transform(scale = scaleVal, child = ScaleIn(s.element.widget).child)

proc slideInLeft*(child: Widget, durationMs: int = 250, key: Key = nil): SlideIn =
  ## Slides `child` in from the right edge, settling left to its
  ## natural position. Common "push from right" iOS-style.
  SlideIn(key: key, child: child, direction: trSlideLeft, durationMs: durationMs)

proc slideInRight*(child: Widget, durationMs: int = 250, key: Key = nil): SlideIn =
  SlideIn(key: key, child: child, direction: trSlideRight, durationMs: durationMs)

proc slideInUp*(child: Widget, durationMs: int = 250, key: Key = nil): SlideIn =
  ## Slides `child` in from below. Common "modal sheet" pattern.
  SlideIn(key: key, child: child, direction: trSlideUp, durationMs: durationMs)

proc slideInDown*(child: Widget, durationMs: int = 250, key: Key = nil): SlideIn =
  SlideIn(key: key, child: child, direction: trSlideDown, durationMs: durationMs)

proc fadeIn*(child: Widget, durationMs: int = 200, key: Key = nil): FadeIn =
  ## Fades `child` from invisible to opaque. Material-style screen
  ## transition.
  FadeIn(key: key, child: child, durationMs: durationMs)

proc scaleIn*(child: Widget, durationMs: int = 200, key: Key = nil): ScaleIn =
  ## Scales `child` from 85% to 100%. Useful for dialogs and popups.
  ScaleIn(key: key, child: child, durationMs: durationMs)

proc withTransition*(kind: RouteTransitionKind, child: Widget): Widget =
  ## Wraps `child` in the requested transition. `trNone` returns
  ## the child unchanged. Used by Navigator.push to apply
  ## transitions without the caller knowing about the specific
  ## transition widget type.
  case kind
  of trNone:       child
  of trFade:       fadeIn(child)
  of trSlideLeft:  slideInLeft(child)
  of trSlideRight: slideInRight(child)
  of trSlideUp:    slideInUp(child)
  of trSlideDown:  slideInDown(child)
  of trScale:      scaleIn(child)
