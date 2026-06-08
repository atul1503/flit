## GestureDetector: subscribes to pointer events that fall within its bounds.
## The render object wraps a child and records callbacks that the binding's
## hit-test pass invokes.

import std/times
import ../foundation/[widget, render_object, geometry, color]
import ../rendering/proxy_box

type
  TapCallback*       = proc()
  DragUpdate*        = proc(delta, position: Offset)
  PointerCallback*   = proc(event: Offset)

  RenderGestureDetector* = ref object of RenderProxyBox
    onTap*: TapCallback
    onDoubleTap*: TapCallback
    # onLongPress is exposed for forward-compatibility but doesn't fire
    # yet - we have no binding-level timer to detect 500ms-without-move
    # before peUp arrives. Use a frame callback in your app if you need
    # it today, or wait for a future flit release.
    onLongPress*: TapCallback
    onPanStart*: PointerCallback
    onPanUpdate*: DragUpdate
    onPanEnd*: TapCallback
    onPointerDown*: PointerCallback
    onPointerUp*: PointerCallback
    behavior*: HitTestBehavior
    lastDown*: Offset
    lastTapTime*: float    # epoch-seconds of the last clean tap-up
    isDragging*: bool

  HitTestBehavior* = enum
    htDeferToChild, htOpaque, htTranslucent

method hitTest*(r: RenderGestureDetector, htResult: HitTestResult, position: Offset): bool =
  if not r.child.isNil:
    if r.child.hitTest(htResult, position):
      htResult.path.add(HitTestEntry(target: r, local: position))
      return true
  if r.behavior == htDeferToChild:
    return false
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true

proc handleDown*(r: RenderGestureDetector, p: Offset) =
  r.lastDown = p
  if r.onPointerDown != nil: r.onPointerDown(p)

proc handleUp*(r: RenderGestureDetector, p: Offset) =
  if r.onPointerUp != nil: r.onPointerUp(p)
  let travel = (p - r.lastDown).distance
  if travel < 8.0:
    let now = epochTime()
    if r.lastTapTime > 0 and now - r.lastTapTime < 0.3 and r.onDoubleTap != nil:
      r.onDoubleTap()
      r.lastTapTime = 0   # consume so a triple-tap isn't a double-tap too
    else:
      if r.onTap != nil: r.onTap()
      r.lastTapTime = now
  if r.isDragging and r.onPanEnd != nil:
    r.onPanEnd()
  r.isDragging = false

proc handleMove*(r: RenderGestureDetector, p, delta: Offset) =
  if not r.isDragging and delta.distance > 4.0:
    r.isDragging = true
    if r.onPanStart != nil: r.onPanStart(p)
  if r.isDragging and r.onPanUpdate != nil:
    r.onPanUpdate(delta, p)

# Widget

type
  GestureDetector* = ref object of RenderObjectWidget
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
  GestureDetector(key: key, child: child, onTap: onTap, onDoubleTap: onDoubleTap,
                  onLongPress: onLongPress, onPanStart: onPanStart,
                  onPanUpdate: onPanUpdate, onPanEnd: onPanEnd, behavior: behavior)
