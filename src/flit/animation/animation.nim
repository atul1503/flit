## Animation primitives: `Ticker`, `AnimationController`, `Tween`, and
## a small set of built-in `Curve` functions. Models Flutter's
## `package:flutter/animation`.
##
## Typical usage from inside a `State`:
##
## ```nim
## # initState:
## controller = newAnimationController(durationSec = 0.5)
## controller.addListener(proc(v: float32) =
##   setState(self, proc() = self.fade = v))
## controller.forward(globalBinding, curve = curveEaseInOut)
##
## # dispose:
## controller.dispose()
## ```

import std/math
import ../foundation/binding

type
  Curve* = proc(t: float32): float32
    ## An easing function. Receives `t` in `[0, 1]` and returns the
    ## eased progress (usually also in `[0, 1]`, but curves like
    ## `curveElasticIn` may overshoot).

  TickerCallback* = proc(elapsed: float32)
    ## A frame-by-frame callback. `elapsed` is seconds since the
    ## ticker started.

  Ticker* = ref object
    ## A self-rescheduling frame callback. Used by
    ## `AnimationController` to advance value each frame. Stopped via
    ## `Ticker.stop`.
    callback*: TickerCallback
    active*:   bool
    start*:    float

  AnimationStatus* = enum
    ## Lifecycle states of an `AnimationController`. Matches Flutter:
    ## - `asDismissed`: at the lower bound, not running.
    ## - `asForward`: currently animating from lower toward upper.
    ## - `asReverse`: currently animating from upper toward lower.
    ## - `asCompleted`: at the upper bound, not running.
    asDismissed, asForward, asReverse, asCompleted

  AnimationController* = ref object
    ## Drives a `value` field between `lower` and `upper` over
    ## `duration` seconds. Listeners are called on every value change;
    ## status listeners on every state transition.
    valueField:        float32
    lower*:    float32
    upper*:    float32
    duration*: float32
    status*:   AnimationStatus
    ticker*:   Ticker
    listeners*:        seq[proc(v: float32)]
    statusListeners*:  seq[proc(s: AnimationStatus)]

proc value*(c: AnimationController): float32 = c.valueField
  ## Current value of the controller, always in `[lower, upper]`.

# Built-in curves

proc curveLinear*(t: float32): float32 = t
  ## Constant-speed easing. Returns `t` unchanged.

proc curveEaseIn*(t: float32): float32 = t * t
  ## Slow start, fast end. `f(t) = t^2`.

proc curveEaseOut*(t: float32): float32 = t * (2.0'f32 - t)
  ## Fast start, slow end. `f(t) = t * (2 - t)`.

proc curveEaseInOut*(t: float32): float32 =
  ## Slow start and end, fast middle. Smooth S-curve.
  if t < 0.5: 2.0'f32 * t * t
  else: -1.0'f32 + (4.0'f32 - 2.0'f32 * t) * t

proc curveBounceOut*(t: float32): float32 =
  ## Overshoots and bounces a couple of times before settling at 1.
  ## Mimics a rubber ball dropping.
  let n1 = 7.5625'f32
  let d1 = 2.75'f32
  if t < 1.0/d1: n1*t*t
  elif t < 2.0/d1:
    let t2 = t - 1.5/d1
    n1*t2*t2 + 0.75
  elif t < 2.5/d1:
    let t2 = t - 2.25/d1
    n1*t2*t2 + 0.9375
  else:
    let t2 = t - 2.625/d1
    n1*t2*t2 + 0.984375

proc curveElasticIn*(t: float32): float32 =
  ## Rubbery start that pulls back before snapping forward. May return
  ## values outside `[0, 1]`.
  if t == 0 or t == 1: t
  else: -pow(2.0'f32, 10*(t-1)) * sin((t-1-0.3/4.0) * (2*PI)/0.3).float32

proc newTicker*(cb: TickerCallback): Ticker =
  ## Constructs a `Ticker` that will invoke `cb` each frame once
  ## started. The ticker is initially inactive; call `start` to begin.
  Ticker(callback: cb, active: false, start: 0)

proc start*(t: Ticker, b: Binding) =
  ## Begins ticking. Each frame, the ticker calls its callback with
  ## `(now - t.start)` and reschedules itself via `b.scheduleFrame`.
  ## Stops when `t.active` becomes false.
  t.active = true
  t.start = b.currentTime
  var tick: FrameCallback
  tick = proc(ts: float) =
    if not t.active: return
    let elapsed = float32(ts - t.start)
    t.callback(elapsed)
    b.scheduleFrame(tick)
  b.scheduleFrame(tick)

proc stop*(t: Ticker) = t.active = false
  ## Stops the ticker on the next frame boundary. Subsequent
  ## scheduled callbacks become no-ops.

proc newAnimationController*(durationSec: float32, lower = 0.0'f32,
                             upper = 1.0'f32): AnimationController =
  ## Constructs an `AnimationController`.
  ##
  ## Inputs:
  ## - `durationSec`: full sweep time in seconds. `forward()` and
  ##   `reverse()` use this unless overridden by `animateTo`.
  ## - `lower`: initial / minimum value. Default 0.
  ## - `upper`: maximum value. Default 1.
  ##
  ## Output: a fresh controller in `asDismissed` state with
  ## `value = lower`.
  ##
  ## `durationSec` of zero (or negative) is clamped to 1ms to
  ## avoid division by zero in the frame ticker. Animations that
  ## want to be effectively instant should set the value directly
  ## via `value =` instead of using `forward()`.
  let safeDuration = max(durationSec, 0.001'f32)
  AnimationController(duration: safeDuration, lower: lower, upper: upper,
                      valueField: lower, status: asDismissed,
                      listeners: @[], statusListeners: @[])

proc addListener*(c: AnimationController, fn: proc(v: float32)) =
  ## Registers `fn` to be called on every value change. Use this to
  ## trigger `setState` from a `State` that owns the controller.
  c.listeners.add(fn)

proc addStatusListener*(c: AnimationController, fn: proc(s: AnimationStatus)) =
  ## Registers `fn` to be called on every `AnimationStatus` transition
  ## (asForward / asCompleted / asReverse / asDismissed).
  c.statusListeners.add(fn)

proc removeListener*(c: AnimationController, fn: proc(v: float32)) =
  ## Removes the first matching value listener. Matches by closure
  ## identity (the same `proc(...)` value must be passed back, same
  ## constraint as Flutter's `removeListener`).
  for i, l in c.listeners:
    if l == fn:
      c.listeners.delete(i)
      return

proc removeStatusListener*(c: AnimationController,
                           fn: proc(s: AnimationStatus)) =
  ## Removes the first matching status listener.
  for i, l in c.statusListeners:
    if l == fn:
      c.statusListeners.delete(i)
      return

proc stop*(c: AnimationController) =
  ## Halts an in-progress animation. The current `value` is preserved
  ## (the animation is not "completed", just paused).
  if not c.ticker.isNil:
    c.ticker.stop()

proc dispose*(c: AnimationController) =
  ## Releases the ticker and clears all listeners. Call from
  ## `State.dispose` so the controller doesn't keep firing after its
  ## host widget unmounts.
  if not c.ticker.isNil:
    c.ticker.stop()
    c.ticker = nil
  c.listeners.setLen(0)
  c.statusListeners.setLen(0)

proc `value=`*(c: AnimationController, v: float32) =
  ## Sets the controller's value, clamped to `[lower, upper]`. Notifies
  ## all listeners if the value changed. Does NOT change `status`.
  ## Listeners are iterated over a snapshot so a listener that
  ## registers or removes listeners during the notification doesn't
  ## crash on Nim's seq-length-changed assertion.
  let clamped = clamp(v, c.lower, c.upper)
  if c.value == clamped: return
  c.valueField = clamped
  let snapshot = c.listeners
  for l in snapshot: l(c.value)

proc setValue(c: AnimationController, v: float32) =
  c.valueField = clamp(v, c.lower, c.upper)
  let snapshot = c.listeners
  for l in snapshot: l(c.value)

proc setStatus(c: AnimationController, s: AnimationStatus) =
  c.status = s
  let snapshot = c.statusListeners
  for l in snapshot: l(s)

proc forward*(c: AnimationController, b: Binding,
              curve: Curve = curveLinear) =
  ## Drives the controller from `lower` to `upper` over `duration`
  ## seconds, applying `curve` to the progress fraction. Sets status
  ## to `asForward` immediately and `asCompleted` when it finishes.
  c.setStatus(asForward)
  c.ticker = newTicker(proc(elapsed: float32) =
    let t = clamp(elapsed / c.duration, 0.0'f32, 1.0'f32)
    c.setValue(c.lower + (c.upper - c.lower) * curve(t))
    if t >= 1.0:
      c.ticker.stop()
      c.setStatus(asCompleted))
  c.ticker.start(b)

proc reverse*(c: AnimationController, b: Binding,
              curve: Curve = curveLinear) =
  ## Drives the controller from its current value down to `lower` over
  ## `duration` seconds. Sets status to `asReverse` immediately and
  ## `asDismissed` when it reaches `lower`.
  c.setStatus(asReverse)
  let startVal = c.value
  c.ticker = newTicker(proc(elapsed: float32) =
    let t = clamp(elapsed / c.duration, 0.0'f32, 1.0'f32)
    c.setValue(startVal + (c.lower - startVal) * curve(t))
    if t >= 1.0:
      c.ticker.stop()
      c.setStatus(asDismissed))
  c.ticker.start(b)

proc repeat*(c: AnimationController, b: Binding,
             curve: Curve = curveLinear, reverse: bool = false) =
  ## Drives the controller from `lower` to `upper` repeatedly.
  ##
  ## Inputs:
  ## - `b`: binding the ticker schedules against.
  ## - `curve`: easing applied within each lap.
  ## - `reverse`: if true, alternates direction each lap (ping-pong:
  ##   lower->upper, then upper->lower, then lower->upper, ...).
  ##   Default false (always restart at `lower`).
  ##
  ## Effect: never sets status to `asCompleted`. Stop via
  ## `controller.stop()` or `controller.dispose()`.
  c.setStatus(asForward)
  c.ticker = newTicker(proc(elapsed: float32) =
    let lap = elapsed / c.duration
    let t = clamp(lap mod 1.0'f32, 0.0'f32, 1.0'f32)
    if reverse:
      let cycle = int(lap) mod 2
      if cycle == 0: c.setValue(c.lower + (c.upper - c.lower) * curve(t))
      else:          c.setValue(c.upper - (c.upper - c.lower) * curve(t))
    else:
      c.setValue(c.lower + (c.upper - c.lower) * curve(t)))
  c.ticker.start(b)

proc animateTo*(c: AnimationController, b: Binding, target: float32,
                durationSec: float32 = -1, curve: Curve = curveLinear) =
  ## Animates from the current value to `target` over `durationSec`
  ## (or `c.duration` if negative). Status is set to `asForward` if
  ## `target >= currentValue`, otherwise `asReverse`. On arrival,
  ## status becomes `asCompleted` if `target` is at the upper bound,
  ## else `asDismissed`.
  let dur = if durationSec > 0: durationSec else: c.duration
  let startVal = c.value
  let endVal = clamp(target, c.lower, c.upper)
  c.setStatus(if endVal >= startVal: asForward else: asReverse)
  c.ticker = newTicker(proc(elapsed: float32) =
    let t = clamp(elapsed / dur, 0.0'f32, 1.0'f32)
    c.setValue(startVal + (endVal - startVal) * curve(t))
    if t >= 1.0:
      c.ticker.stop()
      c.setStatus(if endVal >= c.upper - 0.0001'f32: asCompleted else: asDismissed))
  c.ticker.start(b)

# Tween: linear interpolation between two values of any type T.

type
  Tween*[T] = object
    ## A pair of values `begin` and `end` that can be interpolated by
    ## evaluating against an `AnimationController`. Works for any `T`
    ## that has a `lerp(T, T, float32) -> T` overload in scope; flit
    ## ships overloads for `int`, `float`/`float32`, `Color`, `Offset`,
    ## `Size`, `EdgeInsets`.
    begin*, `end`*: T

proc tween*[T](begin, ending: T): Tween[T] = Tween[T](begin: begin, `end`: ending)
  ## Builds a `Tween[T]` from two endpoints. Use `evaluate` to read
  ## the interpolated value at the controller's current `value`.

proc lerp*[T: SomeFloat](a, b: T, t: float32): T = a + (b - a) * T(t)
  ## Linear interpolation between two `SomeFloat` values.

proc lerp*(a, b: int, t: float32): int = int(float32(a) + float32(b - a) * t)
  ## Linear interpolation between two ints. Truncates toward zero.

proc evaluate*[T](tw: Tween[T], c: AnimationController): T =
  ## Returns the interpolated value `lerp(tw.begin, tw.end, c.value)`.
  lerp(tw.begin, tw.`end`, c.value)
