## Multi-touch gesture recognizers: pinch (scale) and rotate.
##
## SDL2 fires a `MultiGesture` event when the OS detects a
## two-finger pinch or rotation on a touchpad / touchscreen.
## We expose the deltas via `PinchDetector` and `RotateDetector`
## widgets that wrap a child.
##
## On desktop without touch hardware, these widgets are inert
## (no pinch / rotate happens). For testing, the runner could
## synthesize multi-touch events from Cmd+drag, but that's not
## wired today.

import std/[options, math]
import ../foundation/[widget, render_object, geometry, key, runtime, binding]

type
  PinchDetector* = ref object of StatefulWidget
    ## Calls `onPinch` with the cumulative scale factor (1.0 =
    ## no change, 2.0 = pinched-out-to-double, 0.5 = pinched in).
    onPinch*:  proc(scale: float32) {.closure.}
    onPinchEnd*: proc() {.closure.}
    child*:    Widget

  RotateDetector* = ref object of StatefulWidget
    ## Calls `onRotate` with the cumulative rotation in radians.
    onRotate*:  proc(radians: float32) {.closure.}
    onRotateEnd*: proc() {.closure.}
    child*:     Widget

  PinchState = ref object of State
    accumulated: float32

  RotateState = ref object of State
    accumulated: float32

# Multi-touch event dispatch. The runner will push events here.

type
  PinchEvent* = object
    deltaScale*:  float32  # multiplicative delta this frame
    deltaTheta*:  float32  # rotation delta this frame (radians)
    x*, y*:       float32  # center of the gesture

var pinchListeners* {.threadvar.}: seq[proc(ev: PinchEvent) {.closure.}]

proc dispatchMultiGesture*(ev: PinchEvent) =
  ## Called by the runner when SDL fires a MultiGesture event.
  let snap = pinchListeners
  for fn in snap:
    try: fn(ev) except CatchableError: discard

method widgetTypeName*(w: PinchDetector): string = "PinchDetector"
method createElement*(w: PinchDetector): Element = newElement(ekStateful, w)
method createState*(w: PinchDetector): State = PinchState(accumulated: 1.0)

method initState(s: PinchState) =
  let host = PinchDetector(s.element.widget)
  let onEv = proc(ev: PinchEvent) =
    s.accumulated *= (1.0'f32 + ev.deltaScale)
    if not host.onPinch.isNil:
      try: host.onPinch(s.accumulated) except CatchableError: discard
  pinchListeners.add(onEv)

method build*(s: PinchState, ctx: BuildContext): Widget =
  let host = PinchDetector(s.element.widget)
  host.child

method widgetTypeName*(w: RotateDetector): string = "RotateDetector"
method createElement*(w: RotateDetector): Element = newElement(ekStateful, w)
method createState*(w: RotateDetector): State = RotateState(accumulated: 0)

method initState(s: RotateState) =
  let host = RotateDetector(s.element.widget)
  let onEv = proc(ev: PinchEvent) =
    s.accumulated += ev.deltaTheta
    if not host.onRotate.isNil:
      try: host.onRotate(s.accumulated) except CatchableError: discard
  pinchListeners.add(onEv)

method build*(s: RotateState, ctx: BuildContext): Widget =
  let host = RotateDetector(s.element.widget)
  host.child

proc pinchDetector*(child: Widget,
                    onPinch: proc(scale: float32),
                    onPinchEnd: proc() = nil,
                    key: Key = nil): PinchDetector =
  ## Wraps `child` so two-finger pinch on touch hardware drives
  ## the `onPinch` callback with the cumulative scale factor.
  PinchDetector(key: key, child: child, onPinch: onPinch,
                onPinchEnd: onPinchEnd)

proc rotateDetector*(child: Widget,
                     onRotate: proc(radians: float32),
                     onRotateEnd: proc() = nil,
                     key: Key = nil): RotateDetector =
  ## Wraps `child` so two-finger rotation drives the `onRotate`
  ## callback with cumulative radians.
  RotateDetector(key: key, child: child, onRotate: onRotate,
                 onRotateEnd: onRotateEnd)
