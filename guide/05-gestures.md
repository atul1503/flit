# 05. Gestures

User input arrives as pointer events (mouse, touch) and key events. flit
routes pointer events through hit testing to the topmost
`GestureDetector` that wants them.

## GestureDetector

Wrap any widget to make it interactive:

```nim
gestureDetector(
  child = container(
    padding = edgeInsetsAll(12),
    hasColor = true, color = colorBlue,
    child = text("Press me", style = textStyle(color = colorWhite))),
  onTap = proc() = echo "tapped")
```

The detector forwards every supported gesture to the matching callback.
Unset callbacks (default `nil`) make that gesture pass through to the
next detector in the hit chain.

## Available gestures

| Callback | When it fires |
|----------|---------------|
| `onTap` | Pointer down + pointer up within tap distance and tap window |
| `onDoubleTap` | Two taps within 300ms; cancels both taps' `onTap` |
| `onLongPress` | Reserved; not yet implemented |
| `onPanStart` | Pointer down inside the widget; followed by zero or more pan updates |
| `onPanUpdate` | Pointer moved while down (delta provided) |
| `onPanEnd` | Pointer up after one or more pan updates |

```nim
gestureDetector(
  child = mainContent,
  onTap = proc() = handleTap(),
  onDoubleTap = proc() = handleDoubleTap(),
  onPanStart = proc(offset: Offset) = beginDrag(offset),
  onPanUpdate = proc(offset, delta: Offset) = updateDrag(delta),
  onPanEnd = proc(offset: Offset) = endDrag())
```

The `Offset` passed to pan callbacks is in global screen coordinates,
not widget-local. Subtract the widget's origin if you need local
coordinates.

## Hit-test behavior

When two GestureDetectors overlap (one inside the other), only one
should receive the event. Control which with `behavior`:

| Value | Meaning |
|-------|---------|
| `htOpaque` | This detector absorbs the hit; child detectors never see it |
| `htDeferToChild` (default) | If a child detector would handle it, defer; otherwise take it |
| `htTranslucent` | Both this detector and the child detectors get the event |

```nim
gestureDetector(
  behavior = htOpaque,
  child = innerWidgetThatHasItsOwnGestureDetectors,
  onTap = proc() = handleOuterTap())
```

`htOpaque` is the usual choice for buttons: you don't want clicks
inside the button label to dribble down to anything else.

## Tap distance and double-tap timing

flit uses Flutter's defaults:

- Tap distance: 8 pixels. If the pointer moves more than 8 pixels between
  down and up, the tap is cancelled and becomes a pan.
- Double-tap window: 300 milliseconds. Two taps within this window become
  a double-tap.

When `onDoubleTap` is set, the first tap is held back for 300ms to see
if a second one arrives. This adds 300ms of latency to single taps in
that detector. Don't set `onDoubleTap` on widgets where tap latency
matters.

## Scroll wheel

Mouse wheel events route to the topmost `ScrollView` (or
`ListView.builder`) in the hit chain. You don't write code for this; it
is wired up by `processPointerEvents` in the runtime.

```nim
scrollView(child = column(children = manyRows))
# Scroll wheel works automatically over the viewport.
```

## Key events

`Binding.dispatchKey(KeyEvent(...))` exists but no widget-level
shortcut for key handlers is exposed in flit 0.7.0. Use SDL2's key event
plumbing directly if you need keyboard handling.

A future release will add `KeyboardListener` and `Shortcuts` widgets.

## Building a custom gesture

If you need a gesture that GestureDetector doesn't have (long press,
pinch, swipe), drop down to the render layer and override `hitTest`
plus implement event handling in a new `RenderObject`. Look at
`src/flit/gestures/detector.nim` for the template.

## Common patterns

### Disabled button

`onPressed = nil` makes a button non-interactive. Combine with
visual styling:

```nim
elevatedButton(
  child = text("Submit"),
  onPressed = if formValid: proc() = submit() else: nil)
```

### Draggable card

```nim
type
  Card = ref object of StatefulWidget
  CardState = ref object of State
    position: Offset

method build(s: CardState, ctx: BuildContext): Widget =
  positioned(
    left = s.position.dx, top = s.position.dy,
    child = gestureDetector(
      child = container(
        width = 100, height = 100,
        hasColor = true, color = colorBlue),
      onPanUpdate = proc(pos, delta: Offset) =
        setState(s, proc() =
          s.position = Offset(dx: s.position.dx + delta.dx,
                              dy: s.position.dy + delta.dy))))
```

Wrap the result in a `stack(...)` so the absolute positioning works.

## Next step

Read `06-animations.md` for time-driven updates.
