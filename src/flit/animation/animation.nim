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
    value*:    float32
    lower*:    float32
    upper*:    float32
    duration*: float32  # seconds
    status*:   AnimationStatus
    ticker*:   Ticker
    listeners*:        seq[proc(v: float32)]
    statusListeners*:  seq[proc(s: AnimationStatus)]

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
                      value: lower, status: asDismissed,
                      listeners: @[], statusListeners: @[])

proc addListener*(c: AnimationController, fn: proc(v: float32)) =
  c.listeners.add(fn)

proc addStatusListener*(c: AnimationController, fn: proc(s: AnimationStatus)) =
  c.statusListeners.add(fn)

proc setValue(c: AnimationController, v: float32) =
  c.value = clamp(v, c.lower, c.upper)
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

# Tween: linear interpolation between two values of any type T.

type
  Tween*[T] = object
    begin*, `end`*: T

proc tween*[T](begin, ending: T): Tween[T] = Tween[T](begin: begin, `end`: ending)

proc lerp*[T: SomeFloat](a, b: T, t: float32): T = a + (b - a) * T(t)
proc lerp*(a, b: int, t: float32): int = int(float32(a) + float32(b - a) * t)

proc evaluate*[T](tw: Tween[T], c: AnimationController): T =
  lerp(tw.begin, tw.`end`, c.value)
