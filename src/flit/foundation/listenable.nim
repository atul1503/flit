## Listenable / ValueNotifier / ListenableBuilder: small reactive
## primitives for shared state.
##
## A `ValueNotifier[T]` is a mutable box around a `T` that calls
## registered listeners whenever the value changes. A
## `ListenableBuilder` widget subscribes to one for the lifetime of
## its element and calls `setState` (only on itself) whenever the
## notifier fires.
##
## Example:
##
## .. code-block:: nim
##   # Shared state - declare anywhere, even at module scope.
##   let counter = newValueNotifier(0)
##
##   # Widget that watches it. Only this subtree rebuilds when
##   # counter.value changes; the rest of the app is untouched.
##   listenableBuilder(counter, proc(ctx: BuildContext, v: int): Widget =
##     text("count: " & $v))
##
##   # Update from anywhere - a button, an HTTP callback, a timer...
##   counter.value = counter.value + 1
##
## This is roughly the same pattern as Flutter's `ValueNotifier` +
## `ValueListenableBuilder`.

import std/options
import ./widget
import ./render_object
import ./key
import ./geometry

type
  ValueNotifier*[T] = ref object
    ## A mutable cell that notifies listeners on every change. Build
    ## with `newValueNotifier(initial)`; read via `.value`, write via
    ## `.value = x`. Listeners registered via `addListener(fn)` fire
    ## synchronously on every successful write.
    valueField: T
    listeners: seq[proc(v: T)]
    equalsFn: proc(a, b: T): bool

proc defaultEquals[T](a, b: T): bool = a == b

proc newValueNotifier*[T](initial: T,
                          equals: proc(a, b: T): bool = nil): ValueNotifier[T] =
  ## Builds a `ValueNotifier` holding `initial`.
  ##
  ## Inputs:
  ## - `initial`: starting value of the notifier.
  ## - `equals`: optional custom equality. When provided, a `.value`
  ##   assignment only fires listeners if `equals(old, new) == false`.
  ##   Defaults to `==` (requires `T` to define one).
  ##
  ## Output: a fresh notifier with no listeners.
  ValueNotifier[T](valueField: initial, listeners: @[],
                   equalsFn: if equals.isNil: defaultEquals[T] else: equals)

proc value*[T](n: ValueNotifier[T]): T = n.valueField
  ## Returns the current value. Read-only access.

proc `value=`*[T](n: ValueNotifier[T], v: T) =
  ## Assigns a new value. If the new value differs from the current
  ## one (per `equalsFn`), every registered listener is called with
  ## `v` synchronously. Listener errors are NOT caught; they
  ## propagate to the caller of `value =`.
  ##
  ## Listeners are iterated over a snapshot of the list, so a
  ## listener that registers or unregisters listeners during the
  ## notification is safe (the new registration takes effect on
  ## the next notify, not the current one).
  if n.equalsFn(n.valueField, v): return
  n.valueField = v
  let snapshot = n.listeners
  for fn in snapshot: fn(v)

proc notify*[T](n: ValueNotifier[T]) =
  ## Manually fires all listeners with the current value, regardless
  ## of whether it changed. Useful for `seq[T]` or `ref` values that
  ## mutate in place without going through `.value =`.
  let snapshot = n.listeners
  for fn in snapshot: fn(n.valueField)

proc addListener*[T](n: ValueNotifier[T], fn: proc(v: T)) =
  ## Registers `fn` to be called on every change. The same listener
  ## can be added multiple times; each registration fires
  ## independently.
  n.listeners.add(fn)

proc removeListener*[T](n: ValueNotifier[T], fn: proc(v: T)) =
  ## Removes the first matching listener (by closure identity). No-op
  ## if not found. Use the SAME `proc(...)` value you passed to
  ## `addListener`.
  for i, l in n.listeners:
    if l == fn:
      n.listeners.delete(i)
      return

proc dispose*[T](n: ValueNotifier[T]) =
  ## Drops every listener. Call when the notifier outlives the
  ## widgets that subscribed to it (rare); usually
  ## `ListenableBuilder` handles its own teardown.
  n.listeners.setLen(0)

proc hasListeners*[T](n: ValueNotifier[T]): bool = n.listeners.len > 0
  ## Returns true if at least one listener is registered. Useful for
  ## tests.

# ---------------------------------------------------------------------------
# ListenableBuilder widget.

type
  ListenableBuilder*[T] = ref object of StatefulWidget
    ## A widget that subscribes to a `ValueNotifier[T]` and rebuilds
    ## ONLY this subtree whenever the notifier fires. Parents,
    ## siblings and the rest of the app are untouched.
    ##
    ## Use this to bind shared mutable state to a localized UI patch
    ## without dirtying the whole root every time.
    listenable*: ValueNotifier[T]
    builder*: proc(ctx: BuildContext, value: T): Widget

  ListenableBuilderState* = ref object of State
    ## Internal State for `ListenableBuilder`. Non-generic so it can
    ## participate in Nim's method dispatch (`dispose`, `build` etc.
    ## must be reachable from the runtime via the base `State` type).
    ## Holds an `unsubscribe` closure that captures the listenable
    ## and listener and undoes the subscription.
    unsubscribe*: proc()
    buildFn*: proc(ctx: BuildContext): Widget
    rebindFn*: proc()

method widgetTypeName*[T](w: ListenableBuilder[T]): string = "ListenableBuilder"
method createElement*[T](w: ListenableBuilder[T]): Element =
  newElement(ekStateful, w)
method createState*[T](w: ListenableBuilder[T]): State =
  let s = ListenableBuilderState()
  # Capture T via closures so the (non-generic) State can run
  # everything the runtime dispatches to it.
  var currentNotifier: ValueNotifier[T]
  var listener: proc(v: T)
  s.buildFn = proc(ctx: BuildContext): Widget =
    let host = ListenableBuilder[T](s.element.widget)
    host.builder(ctx, host.listenable.value)
  s.rebindFn = proc() =
    let host = ListenableBuilder[T](s.element.widget)
    if not currentNotifier.isNil and
       cast[pointer](currentNotifier) == cast[pointer](host.listenable):
      return  # already subscribed to this notifier
    if not currentNotifier.isNil and not listener.isNil:
      currentNotifier.removeListener(listener)
    currentNotifier = host.listenable
    listener = proc(v: T) =
      if s.mounted:
        setState(s, proc() = discard)
    currentNotifier.addListener(listener)
  s.unsubscribe = proc() =
    if not currentNotifier.isNil and not listener.isNil:
      currentNotifier.removeListener(listener)
      currentNotifier = nil
      listener = nil
  s

method initState*(s: ListenableBuilderState) =
  ## Registers a listener on the host's notifier that schedules a
  ## rebuild of this State (and only this State). Stores the
  ## unsubscribe and rebind closures so `dispose` and
  ## `didUpdateWidget` can move them between notifiers.
  s.mounted = true
  s.rebindFn()

method didUpdateWidget*(s: ListenableBuilderState, old: StatefulWidget) =
  ## If the widget swaps a new notifier in, move the subscription so
  ## we listen to the new one and stop listening to the old.
  s.rebindFn()

method dispose*(s: ListenableBuilderState) =
  ## Removes the listener so the notifier doesn't keep referencing
  ## this State after unmount.
  s.mounted = false
  if not s.unsubscribe.isNil:
    s.unsubscribe()
    s.unsubscribe = nil

method build*(s: ListenableBuilderState, ctx: BuildContext): Widget =
  # Should never see a nil buildFn in practice (createState always
  # populates it), but be defensive.
  if s.buildFn.isNil: Widget(nil)
  else: s.buildFn(ctx)

proc listenableBuilder*[T](listenable: ValueNotifier[T],
                           builder: proc(ctx: BuildContext, value: T): Widget,
                           key: Key = nil): ListenableBuilder[T] =
  ## Builds a `ListenableBuilder[T]`.
  ##
  ## Inputs:
  ## - `listenable`: the `ValueNotifier` to subscribe to. Required.
  ## - `builder`: called with the current value on every rebuild.
  ##   Must be deterministic w.r.t. its inputs - it'll be called many
  ##   times.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: registers a listener on `listenable` for the lifetime of
  ## the resulting element. When `listenable.value` changes, only
  ## this widget's subtree rebuilds.
  ListenableBuilder[T](key: key, listenable: listenable, builder: builder)
