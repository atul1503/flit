## SchedulerBinding & WidgetBinding: the runtime that owns the element tree,
## drives frames, and dispatches input. Mirrors Flutter's WidgetsBinding /
## SchedulerBinding singletons.

import std/[times, deques, options]
import ./widget
import ./render_object
import ./geometry
import ./diagnostics

type
  FrameCallback*    = proc(timestamp: float)
  PostFrameCallback* = proc()
  PointerEventKind* = enum
    peDown, peMove, peUp, peCancel, peHoverEnter, peHoverExit, peScroll

  PointerEvent* = object
    kind*: PointerEventKind
    pointer*: int
    position*: Offset
    delta*: Offset
    scrollDelta*: Offset
    buttons*: uint32
    timestamp*: float

  KeyEventKind* = enum
    keDown, keUp, keRepeat

  KeyEvent* = object
    kind*: KeyEventKind
    keyCode*: int
    scancode*: int
    modifiers*: uint32
    text*: string

  Binding* = ref object
    rootElement*: Element
    rootRender*:  RenderObject
    canvas*:      Canvas
    dirtyRoots*:  seq[Element]
    needsRepaint*: bool  # paint-only pass (e.g. scroll, no tree change)
    frameCallbacks*: seq[FrameCallback]
    postFrame*:   seq[PostFrameCallback]
    pendingPointers*: Deque[PointerEvent]
    pendingKeys*: Deque[KeyEvent]
    surfaceSize*: Size
    devicePixelRatio*: float32
    startTime*:   float
    frameCount*:  int
    locale*:      string
    debugInspector*: bool

var globalBinding*: Binding

proc newBinding*(canvas: Canvas, surfaceSize: Size,
                 devicePixelRatio: float32 = 1.0): Binding =
  result = Binding(
    canvas: canvas,
    surfaceSize: surfaceSize,
    devicePixelRatio: devicePixelRatio,
    dirtyRoots: @[],
    frameCallbacks: @[],
    postFrame: @[],
    pendingPointers: initDeque[PointerEvent](),
    pendingKeys: initDeque[KeyEvent](),
    startTime: epochTime(),
    locale: "en-US")
  globalBinding = result
  onSetStateRoot = proc(root: Element) =
    if globalBinding.isNil: return
    if root notin globalBinding.dirtyRoots:
      globalBinding.dirtyRoots.add(root)

proc scheduleFrame*(b: Binding, cb: FrameCallback) =
  b.frameCallbacks.add(cb)

proc addPostFrameCallback*(b: Binding, cb: PostFrameCallback) =
  b.postFrame.add(cb)

proc dispatchPointer*(b: Binding, ev: PointerEvent) =
  b.pendingPointers.addLast(ev)

proc dispatchKey*(b: Binding, ev: KeyEvent) =
  b.pendingKeys.addLast(ev)

proc currentTime*(b: Binding): float = epochTime() - b.startTime

proc markRootDirty*(b: Binding, root: Element) =
  if root.isNil: return
  if root notin b.dirtyRoots:
    b.dirtyRoots.add(root)

proc clearDirty*(b: Binding) =
  b.dirtyRoots.setLen(0)
