## `GestureDetector` widget plus the underlying `RenderGestureDetector`
## render object. Subscribes to pointer events that hit its subtree and
## fires user callbacks (`onTap`, `onPanStart`/`Update`/`End`,
## `onDoubleTap`, etc.).
##
## The `runtime.processPointerEvents` proc is what drives the detector;
## it hit-tests through the render tree, finds the topmost detector in
## the hit path, and invokes `handleDown` / `handleMove` / `handleUp`.

import std/times
import ../foundation/[widget, render_object, geometry, color]
import ../rendering/proxy_box

type
  TapCallback*       = proc()
    ## A zero-argument click handler. Used for `onTap`,
    ## `onDoubleTap`, `onPanEnd`, `onLongPress`.

  DragUpdate*        = proc(delta, position: Offset)
    ## Drag callback. `delta` is the movement since the previous
    ## update; `position` is the absolute pointer position in window
    ## coords.

  PointerCallback*   = proc(event: Offset)
    ## Pointer-event handler that just needs the position. Used for
    ## `onPanStart`, `onPointerDown`, `onPointerUp`.

  RenderGestureDetector* = ref object of RenderProxyBox
    ## The render object that backs `GestureDetector`. Stores all the
    ## callback closures plus the cross-event state needed for tap /
    ## double-tap / pan recognition.
    onTap*: TapCallback
    onDoubleTap*: TapCallback
    onLongPress*: TapCallback
      ## NOTE: not implemented yet. Stored on the widget for
      ## forward-compatibility; firing requires binding-level timers
      ## not yet wired up.
    onPanStart*: PointerCallback
    onPanUpdate*: DragUpdate
    onPanEnd*: TapCallback
    onPointerDown*: PointerCallback
    onPointerUp*: PointerCallback
    behavior*: HitTestBehavior
    lastDown*: Offset
    lastTapTime*: float
    isDragging*: bool

  HitTestBehavior* = enum
    ## How the gesture detector participates in hit testing.
    ## - `htDeferToChild`: the detector is only hit when its child
    ##   is. Pointer events that fall in padding-only areas of the
    ##   detector are NOT delivered.
    ## - `htOpaque`: the detector itself is hit whenever the pointer
    ##   is inside its bounds, regardless of the child. Use this for
    ##   buttons so the entire box is clickable.
    ## - `htTranslucent`: the detector is hit AND any siblings behind
    ##   it (in a Stack) are also tested. Currently treated as
    ##   `htOpaque` for compatibility.
    htDeferToChild, htOpaque, htTranslucent

method hitTest*(r: RenderGestureDetector, htResult: HitTestResult, position: Offset): bool =
  ## Recurses into the child first. If the child reports a hit, adds
  ## this detector to the path and returns true. If the child misses
  ## and `behavior == htDeferToChild`, returns false (this detector
  ## is not hit). Otherwise (`htOpaque` / `htTranslucent`) the
  ## detector itself absorbs the hit even in padding-only zones.
  if not r.child.isNil:
    if r.child.hitTest(htResult, position):
      htResult.path.add(HitTestEntry(target: r, local: position))
      return true
  if r.behavior == htDeferToChild:
    return false
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

proc handleDown*(r: RenderGestureDetector, p: Offset) =
  ## Records `p` as the down position and fires `onPointerDown`.
  ## Called by the dispatcher when a `peDown` lands on this detector.
  r.lastDown = p
  if r.onPointerDown != nil: r.onPointerDown(p)

proc handleUp*(r: RenderGestureDetector, p: Offset) =
  ## Fires `onPointerUp`, then dispatches one of:
  ## - `onDoubleTap` if a second tap-up landed within 300ms of the
  ##   previous one and total travel was < 8px.
  ## - `onTap` if travel was < 8px and it's the first tap.
  ## - `onPanEnd` if we were dragging (delta moved past 4px during
  ##   the gesture).
  if r.onPointerUp != nil: r.onPointerUp(p)
  let travel = (p - r.lastDown).distance
  if travel < 8.0:
    let now = epochTime()
    if r.lastTapTime > 0 and now - r.lastTapTime < 0.3 and r.onDoubleTap != nil:
      r.onDoubleTap()
      r.lastTapTime = 0
    else:
      if r.onTap != nil: r.onTap()
      r.lastTapTime = now
  if r.isDragging and r.onPanEnd != nil:
    r.onPanEnd()
  r.isDragging = false

proc handleMove*(r: RenderGestureDetector, p, delta: Offset) =
  ## Called for each pointer-move while a `peDown` is in progress.
  ## Transitions into "dragging" state once accumulated `delta` exceeds
  ## 4px; fires `onPanStart` on the transition and `onPanUpdate` on
  ## every move thereafter.
  if not r.isDragging and delta.distance > 4.0:
    r.isDragging = true
    if r.onPanStart != nil: r.onPanStart(p)
  if r.isDragging and r.onPanUpdate != nil:
    r.onPanUpdate(delta, p)

# Widget

type
  GestureDetector* = ref object of RenderObjectWidget
    ## A widget that detects taps, double-taps, drags and other
    ## pointer gestures on its subtree.
    child*: Widget
    onTap*: TapCallback
    onDoubleTap*: TapCallback
    onLongPress*: TapCallback
    onPanStart*: PointerCallback
    onPanUpdate*: DragUpdate
    onPanEnd*: TapCallback
    behavior*: HitTestBehavior

method widgetTypeName*(w: GestureDetector): string = "GestureDetector"
method createElement*(w: GestureDetector): Element = newElement(ekRender, w)
method createRenderObject*(w: GestureDetector, ctx: BuildContext): RenderObject =
  RenderGestureDetector(
    onTap: w.onTap, onDoubleTap: w.onDoubleTap, onLongPress: w.onLongPress,
    onPanStart: w.onPanStart, onPanUpdate: w.onPanUpdate, onPanEnd: w.onPanEnd,
    behavior: w.behavior)
method updateRenderObject*(w: GestureDetector, ctx: BuildContext, r: RenderObject) =
  let g = RenderGestureDetector(r)
  g.onTap = w.onTap
  g.onDoubleTap = w.onDoubleTap
  g.onLongPress = w.onLongPress
  g.onPanStart = w.onPanStart
  g.onPanUpdate = w.onPanUpdate
  g.onPanEnd = w.onPanEnd
  g.behavior = w.behavior

proc gestureDetector*(child: Widget, onTap: TapCallback = nil,
                      onDoubleTap: TapCallback = nil,
                      onLongPress: TapCallback = nil,
                      onPanStart: PointerCallback = nil,
                      onPanUpdate: DragUpdate = nil,
                      onPanEnd: TapCallback = nil,
                      behavior = htDeferToChild,
                      key: Key = nil): GestureDetector =
  ## Builds a `GestureDetector` around `child`.
  ##
  ## Inputs:
  ## - `child`: subtree whose painted area is sensitive to gestures.
  ##   Required.
  ## - `onTap`: tap-up handler. Fires if pointer-up lands within 8px
  ##   of pointer-down.
  ## - `onDoubleTap`: fires when a second clean tap arrives within
  ##   300ms of the first. Consumes the second tap so `onTap` doesn't
  ##   fire twice.
  ## - `onLongPress`: NOT YET IMPLEMENTED (see field doc).
  ## - `onPanStart`: fires once when accumulated drag exceeds 4px.
  ## - `onPanUpdate`: fires on every move during a drag; receives
  ##   `(delta, position)`.
  ## - `onPanEnd`: fires on pointer-up if we were dragging.
  ## - `behavior`: hit-test behavior. Use `htOpaque` for buttons so
  ##   the whole padded area is tappable, not just the inner content.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: registers a `RenderGestureDetector` in the render tree
  ## that the runtime's pointer dispatcher routes events to.
  GestureDetector(key: key, child: child, onTap: onTap, onDoubleTap: onDoubleTap,
                  onLongPress: onLongPress, onPanStart: onPanStart,
                  onPanUpdate: onPanUpdate, onPanEnd: onPanEnd, behavior: behavior)
