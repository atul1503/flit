# 06. Animations

flit's animations are time-driven, controller-based, identical in
shape to Flutter's `AnimationController` + `Tween`.

Three pieces:

1. `AnimationController`: produces values from a lower bound to an upper
   bound over a duration. Mutable; you call `forward`, `reverse`, etc.
2. `Tween[T]`: interpolates between two `T` values according to a `t`
   in `[0, 1]`.
3. Curves: shape the `t` value (ease-in, ease-out, bounce).

## Hello animation

A button that fades in over one second:

```nim
import flit

type
  Fader = ref object of StatefulWidget
  FaderState = ref object of State
    controller: AnimationController

method widgetTypeName(w: Fader): string = "Fader"
method createElement(w: Fader): Element = newElement(ekStateful, w)
method createState(w: Fader): State = FaderState()

method initState(s: FaderState) =
  s.controller = newAnimationController(durationMs = 1000)
  s.controller.addListener(proc(v: float32) =
    setState(s, proc() = discard))
  s.controller.forward()

method dispose(s: FaderState) =
  s.controller.dispose()

method build(s: FaderState, ctx: BuildContext): Widget =
  opacity(s.controller.value,
    child = text("Hello", style = textStyle(fontSize = 40)))
```

Three things to notice:

1. `initState` creates the controller; `dispose` cleans it up. Always
   pair these. Forgetting `dispose` leaks the ticker on every
   widget unmount.
2. `addListener(proc(v))` runs every frame the controller is animating.
   Inside, we `setState` (with an empty closure) to dirty this widget
   so its `build` reruns and reads the new value.
3. `controller.value` is a `float32` in `[lowerBound, upperBound]`
   (default 0 to 1).

## Controller operations

| Method | Effect |
|--------|--------|
| `forward()` | Animate from current value to `upperBound` |
| `reverse()` | Animate from current value to `lowerBound` |
| `animateTo(target, durationMs)` | Animate to an arbitrary value over a custom duration |
| `repeat()` | Forward, then back, forever |
| `stop()` | Halt at the current value |
| `dispose()` | Stop and unregister the ticker. Required at end of life. |

Read access:

- `controller.value`: current animated value
- `controller.status`: one of `asDismissed`, `asForward`, `asReverse`,
  `asCompleted`

## Listeners

```nim
let unsubscribe = controller.addListener(proc(v: float32) =
  echo "animation value: ", v)

# Later:
controller.removeListener(unsubscribe)
```

In a stateful widget that owns the controller, the standard pattern is
to add a listener in `initState` and not bother removing it; calling
`controller.dispose()` drops every listener.

## Tween

A controller produces values from 0 to 1 (by default). To interpolate
between richer types, use `Tween[T]`:

```nim
let colorTween = newTween[Color](colorBlue, colorRed)
let widthTween = newTween[float32](100, 400)
let offsetTween = newTween[Offset](
  Offset(dx: 0, dy: 0),
  Offset(dx: 200, dy: 0))

# In build:
let t = controller.value  # 0..1
let currentColor = colorTween.lerp(t)
let currentWidth = widthTween.lerp(t)
let currentOffset = offsetTween.lerp(t)
```

flit ships `lerp` for `float32`, `int`, `Color`, `Offset`, `Size`,
`EdgeInsets`. Other types: implement `proc lerp(a, b: T, t: float32): T`
and `Tween[T]` will use it.

## Curves

Linear motion looks robotic. Curves shape the controller's output:

| Curve | Shape |
|-------|-------|
| `linear` | Straight line (no easing) |
| `easeIn` | Slow start, fast end |
| `easeOut` | Fast start, slow end |
| `easeInOut` | Slow start and end, fast middle |
| `bounceOut` | Lands with a bounce |
| `elasticIn` | Spring-back wobble at start |

Apply a curve to the controller's value before tweening:

```nim
let t = easeInOut(controller.value)
let pos = offsetTween.lerp(t)
```

Or compose at the tween:

```nim
# Animate over a curved t, not a linear one.
let curvedT = bounceOut(controller.value)
let scale = newTween[float32](1.0, 1.5).lerp(curvedT)
```

## Composing animations

Multiple animated properties usually share one controller, with each
property using its own tween:

```nim
method initState(s: BannerState) =
  s.controller = newAnimationController(durationMs = 600)
  s.controller.addListener(proc(_) =
    setState(s, proc() = discard))
  s.opacityTween = newTween[float32](0, 1)
  s.scaleTween = newTween[float32](0.8, 1.0)
  s.controller.forward()

method build(s: BannerState, ctx: BuildContext): Widget =
  let t = easeOut(s.controller.value)
  opacity(s.opacityTween.lerp(t),
    child = transform(scale = s.scaleTween.lerp(t),
      child = bannerContent))
```

One controller, two visual properties, perfectly synchronized.

## Looping

For idle animations (spinners, loading indicators):

```nim
method initState(s: SpinnerState) =
  s.controller = newAnimationController(durationMs = 1500)
  s.controller.addListener(proc(_) =
    setState(s, proc() = discard))
  s.controller.repeat()

method build(s: SpinnerState, ctx: BuildContext): Widget =
  let radians = s.controller.value * 6.283   # 0..2pi
  transform(rotation = radians, child = spinnerDot)
```

`repeat()` goes 0 to 1 then 1 to 0 then 0 to 1 forever. Halve the
duration if you want a one-way cycle.

## When animations stop

flit's animation pump runs only when at least one controller is
animating. When all controllers are dismissed or completed, the frame
loop idles (no CPU usage). `dispose` removes the controller from the
pump.

## Next step

Read `07-performance.md` for the performance subsystems.
