## `Binding`: the runtime that owns the element tree, drives frames,
## and dispatches input. Mirrors Flutter's `WidgetsBinding` /
## `SchedulerBinding` singletons combined into one struct.
##
## A `Binding` is created once per app (usually by `runApp`) and stored
## in the module-level `globalBinding`. Platform runners
## (`platform/desktop/runner`, etc.) drive frames by:
##   1. Polling platform events and dispatching them via
##      `dispatchPointer` / `dispatchKey`.
##   2. Calling `processPointerEvents` (from `runtime.nim`) to deliver
##      events to gesture detectors.
##   3. Walking `dirtyRoots` and rebuilding any subtrees that need it.
##   4. Running `frameCallbacks` for active tickers.
##   5. Repainting and presenting the frame.

import std/[times, deques, options]
import ./widget
import ./render_object
import ./geometry
import ./diagnostics

type
  FrameCallback*    = proc(timestamp: float)
    ## Called once per frame with the current binding-relative
    ## timestamp in seconds. Used by `Ticker` to drive animations.

  PostFrameCallback* = proc()
    ## Called once after the next frame completes painting. Used for
    ## work that needs to run when layout/paint are stable.

  PointerEventKind* = enum
    ## Kinds of pointer events dispatched by the platform runner:
    ## down/move/up are taps and drags; cancel aborts an in-progress
    ## gesture; hover-enter/exit are mouse hover transitions; scroll
    ## carries a wheel delta.
    peDown, peMove, peUp, peCancel, peHoverEnter, peHoverExit, peScroll

  PointerEvent* = object
    ## A single pointer event. `position` is in window coordinates.
    ## `delta` is the per-event movement (for moves). `scrollDelta`
    ## carries wheel deltas (peScroll only). `buttons` is a platform-
    ## specific bitmask. `pointer` is an opaque ID identifying which
    ## finger / cursor.
    kind*: PointerEventKind
    pointer*: int
    position*: Offset
    delta*: Offset
    scrollDelta*: Offset
    buttons*: uint32
    timestamp*: float

  KeyEventKind* = enum
    ## Key-event lifecycle: press, release, auto-repeat.
    keDown, keUp, keRepeat

  KeyEvent* = object
    ## A single key event. `keyCode` is a logical key code,
    ## `scancode` is the physical key, `modifiers` is a bitmask of
    ## Shift/Ctrl/Alt/etc., `text` is the typed character (may be
    ## empty for non-printing keys).
    kind*: KeyEventKind
    keyCode*: int
    scancode*: int
    modifiers*: uint32
    text*: string

  Binding* = ref object
    ## App-wide runtime state. One per app, available as
    ## `globalBinding`. Fields:
    ## - `rootElement`: top of the element tree.
    ## - `rootRender`: top of the render tree (set by the runner
    ##   after layout).
    ## - `canvas`: drawing surface.
    ## - `dirtyRoots`: elements that need rebuilding next frame.
    ## - `needsRepaint`: set by scroll and other layout-stable
    ##   changes to request a paint-only frame.
    ## - `frameCallbacks`: callbacks to run on the next frame.
    ## - `postFrame`: callbacks to run after the next frame.
    ## - `pendingPointers` / `pendingKeys`: event queues.
    ## - `surfaceSize`: the window size in logical pixels.
    ## - `devicePixelRatio`: scale factor for HiDPI.
    ## - `startTime`: epoch time when the binding was created.
    ## - `frameCount`: total frames rendered.
    ## - `locale`: BCP-47 locale string (`"en-US"` by default).
    ## - `debugInspector`: when true, the runner shows debug
    ##   overlays.
    rootElement*: Element
    rootRender*:  RenderObject
    canvas*:      Canvas
    dirtyRoots*:  seq[Element]
    needsRepaint*: bool
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
  ## Active binding for the app. Set by `newBinding`. Read by setState
  ## machinery, ticker scheduling, and the platform runner.

proc newBinding*(canvas: Canvas, surfaceSize: Size,
                 devicePixelRatio: float32 = 1.0): Binding =
  ## Constructs a binding and installs it as `globalBinding`.
  ##
  ## Inputs:
  ## - `canvas`: the drawing surface for this app.
  ## - `surfaceSize`: initial window size in logical pixels.
  ## - `devicePixelRatio`: backing-store scale factor (2.0 on
  ##   retina, 1.0 elsewhere).
  ##
  ## Effect: also installs an `onSetStateRoot` hook that pushes
  ## dirty elements onto `globalBinding.dirtyRoots`.
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
  ## Schedules `cb` to run on the next frame. Used by `Ticker` to
  ## drive animations.
  b.frameCallbacks.add(cb)

proc addPostFrameCallback*(b: Binding, cb: PostFrameCallback) =
  ## Schedules `cb` to run after the next frame finishes painting.
  b.postFrame.add(cb)

proc dispatchPointer*(b: Binding, ev: PointerEvent) =
  ## Enqueues a pointer event. The runner drains the queue every
  ## frame via `processPointerEvents`.
  b.pendingPointers.addLast(ev)

proc dispatchKey*(b: Binding, ev: KeyEvent) =
  ## Enqueues a key event. (No key-event dispatcher is wired up yet;
  ## reads from `pendingKeys` are the caller's responsibility.)
  b.pendingKeys.addLast(ev)

proc currentTime*(b: Binding): float =
  ## Seconds since this binding was created. Use as a monotonic clock
  ## for animation timestamps.
  epochTime() - b.startTime

proc markRootDirty*(b: Binding, root: Element) =
  ## Adds `root` to the dirty queue, deduped. Safe to call with nil.
  if root.isNil: return
  if root notin b.dirtyRoots:
    b.dirtyRoots.add(root)

proc clearDirty*(b: Binding) =
  ## Empties the dirty queue. Called by the runner after a rebuild
  ## pass completes.
  b.dirtyRoots.setLen(0)
