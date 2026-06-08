## Animation primitives: Ticker, AnimationController, Tween, curves.
## Models Flutter's animation package.

import std/math
import ../foundation/binding

type
  Curve* = proc(t: float32): float32
  TickerCallback* = proc(elapsed: float32)

  Ticker* = ref object
    callback*: TickerCallback
    active*:   bool
    start*:    float

  AnimationStatus* = enum
    asDismissed, asForward, asReverse, asCompleted

  AnimationController* = ref object
    valueField:        float32   # use .value getter / .value= setter
    lower*:    float32
    upper*:    float32
    duration*: float32  # seconds
    status*:   AnimationStatus
    ticker*:   Ticker
    listeners*:        seq[proc(v: float32)]
    statusListeners*:  seq[proc(s: AnimationStatus)]

proc value*(c: AnimationController): float32 = c.valueField

# Built-in curves

proc curveLinear*(t: float32): float32 = t
proc curveEaseIn*(t: float32): float32 = t * t
proc curveEaseOut*(t: float32): float32 = t * (2.0'f32 - t)
proc curveEaseInOut*(t: float32): float32 =
  if t < 0.5: 2.0'f32 * t * t
  else: -1.0'f32 + (4.0'f32 - 2.0'f32 * t) * t
proc curveBounceOut*(t: float32): float32 =
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
  if t == 0 or t == 1: t
  else: -pow(2.0'f32, 10*(t-1)) * sin((t-1-0.3/4.0) * (2*PI)/0.3).float32

proc newTicker*(cb: TickerCallback): Ticker =
  Ticker(callback: cb, active: false, start: 0)

proc start*(t: Ticker, b: Binding) =
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

proc newAnimationController*(durationSec: float32, lower = 0.0'f32,
                             upper = 1.0'f32): AnimationController =
  AnimationController(duration: durationSec, lower: lower, upper: upper,
                      valueField: lower, status: asDismissed,
                      listeners: @[], statusListeners: @[])

proc addListener*(c: AnimationController, fn: proc(v: float32)) =
  c.listeners.add(fn)

proc addStatusListener*(c: AnimationController, fn: proc(s: AnimationStatus)) =
  c.statusListeners.add(fn)

proc removeListener*(c: AnimationController, fn: proc(v: float32)) =
  ## Removes the first matching listener. Matches by closure environment
  ## pointer; same constraint as Flutter's removeListener.
  for i, l in c.listeners:
    if l == fn:
      c.listeners.delete(i)
      return

proc removeStatusListener*(c: AnimationController,
                           fn: proc(s: AnimationStatus)) =
  for i, l in c.statusListeners:
    if l == fn:
      c.statusListeners.delete(i)
      return

proc stop*(c: AnimationController) =
  ## Halts the controller mid-animation, leaving value at its current spot.
  if not c.ticker.isNil:
    c.ticker.stop()

proc dispose*(c: AnimationController) =
  ## Releases the ticker and clears all listeners. Call this from State.dispose
  ## when the controller's host widget is being unmounted.
  if not c.ticker.isNil:
    c.ticker.stop()
    c.ticker = nil
  c.listeners.setLen(0)
  c.statusListeners.setLen(0)

proc `value=`*(c: AnimationController, v: float32) =
  ## Direct setter that notifies listeners, matching Flutter.
  let clamped = clamp(v, c.lower, c.upper)
  if c.value == clamped: return
  c.valueField = clamped
  for l in c.listeners: l(c.value)

proc setValue(c: AnimationController, v: float32) =
  c.valueField = clamp(v, c.lower, c.upper)
  for l in c.listeners: l(c.value)

proc setStatus(c: AnimationController, s: AnimationStatus) =
  c.status = s
  for l in c.statusListeners: l(s)

proc forward*(c: AnimationController, b: Binding,
              curve: Curve = curveLinear) =
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
  ## Drives the controller from lower->upper repeatedly. If `reverse` is
  ## true, alternates direction each lap (ping-pong). Mirrors Flutter's
  ## AnimationController.repeat(reverse: true).
  c.setStatus(asForward)
  var goingForward = true
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
  ## Animate from current value to `target`. If durationSec < 0 the
  ## controller's own duration is used. Stops when the target is reached.
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
    begin*, `end`*: T

proc tween*[T](begin, ending: T): Tween[T] = Tween[T](begin: begin, `end`: ending)

proc lerp*[T: SomeFloat](a, b: T, t: float32): T = a + (b - a) * T(t)
proc lerp*(a, b: int, t: float32): int = int(float32(a) + float32(b - a) * t)

proc evaluate*[T](tw: Tween[T], c: AnimationController): T =
  lerp(tw.begin, tw.`end`, c.value)
