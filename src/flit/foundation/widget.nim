## Widget framework. The flit equivalent of Flutter's `flutter/widgets`
## core. There are three parallel trees:
##
##   Widget  - immutable description of part of the UI (config object).
##   Element - a long-lived instance of a Widget at a position in the
##             tree. Mounts, updates and unmounts; owns State.
##   Render  - the actual layout/paint tree.
##
## Widget subtypes:
##
##   `StatelessWidget`     - emits a child tree from build(ctx).
##   `StatefulWidget`      - pairs with a `State`; setState triggers
##                           rebuild.
##   `ProxyWidget`         - one-child wrapper with no rendering of its
##                           own (used for parent-data carriers like
##                           `Flexible` and `Positioned`).
##   `InheritedWidget`     - a `ProxyWidget` whose value descendants can
##                           read; the lookup mechanism is bare-bones in
##                           flit today.
##   `RenderObjectWidget`  - the leaf that owns a `RenderObject`.

import std/[tables, options]
import ./key
import ./render_object
import ./geometry
import ./diagnostics
export key

type
  Widget* = ref object of RootObj
    ## Base class for every widget. Subclass via one of `StatelessWidget`,
    ## `StatefulWidget`, `RenderObjectWidget`, `ProxyWidget`,
    ## `InheritedWidget`. The single mandatory field is `key`, which
    ## controls reconciliation identity.
    key*: Key

  StatelessWidget*    = ref object of Widget
    ## A widget that emits a child tree from `build(ctx)`. Override
    ## `build` and `widgetTypeName`. Optionally override `createElement`
    ## (the default of `newElement(ekStateless, w)` is usually fine).
  StatefulWidget*     = ref object of Widget
    ## A widget that pairs with a `State` returned by `createState`. The
    ## State persists across rebuilds and is where mutable data lives.
  RenderObjectWidget* = ref object of Widget
    ## A widget that owns a `RenderObject`. Override `createRenderObject`
    ## to build one, and `updateRenderObject` to mirror config changes
    ## onto an existing render object during reconciliation.
  ProxyWidget*        = ref object of Widget
    ## A widget that wraps exactly one `child` without producing its own
    ## render object. Used for parent-data carriers (`Flexible`,
    ## `Positioned`).
    child*: Widget
  InheritedWidget*    = ref object of ProxyWidget
    ## A widget whose data descendants can look up via
    ## `findInheritedOfType[T]`. Override `updateShouldNotify` to control
    ## whether dependents rebuild when the inherited widget changes.

  ElementKind* = enum
    ## Discriminator for `Element` shape. Set by `createElement`.
    ekStateless, ekStateful, ekRender, ekProxy, ekInherited, ekRoot

  Element* = ref object of RootObj
    ## A long-lived instance of a widget at a position in the tree.
    ## Fields:
    ## - `kind`: which family of `Widget` this Element wraps.
    ## - `widget`: the current widget configuration (may be replaced
    ##   on reconciliation).
    ## - `parent`/`children`: tree links.
    ## - `dirty`: pending rebuild flag.
    ## - `depth`: distance from root (used for traversal heuristics).
    ## - `renderObj`: the owned `RenderObject` (for `ekRender` only).
    ## - `inheritedAncestors`: cached lookup of ancestor inherited
    ##   widgets by type-name; currently used as documentation only.
    ## - `state`: the `State` instance (for `ekStateful` only).
    ## - `slot`: integer position in the parent's child list (helps
    ##   reorder tracking).
    kind*:   ElementKind
    widget*: Widget
    parent*: Element
    children*: seq[Element]
    dirty*:  bool
    depth*:  int
    renderObj*: RenderObject
    inheritedAncestors*: Table[string, Element]
    state*: State
    slot*: int

  State* = ref object of RootObj
    ## Mutable state attached to a `StatefulWidget`'s element.
    ## Subclasses store their data fields and override `build`, plus
    ## any of `initState`, `didUpdateWidget`, `didChangeDependencies`,
    ## `dispose`, `reassemble` as needed.
    element*: Element
    mounted*: bool

  BuildContext* = Element
    ## Alias for `Element`. Passed to `build` so widgets can walk the
    ## tree (look up ancestors etc.). In Flutter this is an interface
    ## that `Element` implements; here we use the element directly.

# ---- Widget API ----

method createElement*(w: Widget): Element {.base.} =
  ## Constructs the `Element` that owns this widget. Subclasses MUST
  ## override and return `newElement(ekX, w)` where `ekX` matches the
  ## widget kind. The base raises `Defect`.
  raise newException(Defect, "Widget.createElement must be overridden")

method widgetTypeName*(w: Widget): string {.base.} = "Widget"
  ## Returns a stable identifier for the widget's runtime type. The
  ## framework uses this to decide whether `oldWidget` and `newWidget`
  ## refer to the same kind during reconciliation. Subclasses override
  ## to return a unique string (typically just `"MyWidget"`).

method canUpdate*(oldW, newW: Widget): bool {.base.} =
  ## True when an existing `Element` whose widget is `oldW` can be
  ## reused with `newW` as its new configuration. The default checks
  ## that the runtime type names match AND the keys are equal.
  if oldW.isNil or newW.isNil: return false
  if oldW.widgetTypeName != newW.widgetTypeName: return false
  oldW.key == newW.key

# StatelessWidget
method build*(w: StatelessWidget, ctx: BuildContext): Widget {.base.} =
  ## Emits the child widget tree. Subclasses MUST override. The
  ## returned widget becomes the sole child element. The base raises
  ## `Defect`.
  raise newException(Defect, "StatelessWidget.build must be overridden")

# StatefulWidget
method createState*(w: StatefulWidget): State {.base.} =
  ## Returns a freshly-constructed `State` subclass instance. Called
  ## once per element mount. Subclasses MUST override.
  raise newException(Defect, "StatefulWidget.createState must be overridden")

# State
method build*(s: State, ctx: BuildContext): Widget {.base.} =
  ## Emits the child widget tree from the state's current data.
  ## Subclasses MUST override. Reads `s.element.widget` to access the
  ## latest widget config.
  raise newException(Defect, "State.build must be overridden")

method initState*(s: State) {.base.} = s.mounted = true
  ## Called once when the state's element is first mounted. Override to
  ## perform one-time setup (allocate controllers, subscribe to streams,
  ## etc.). Default sets `mounted = true`.

method didChangeDependencies*(s: State) {.base.} = discard
  ## Called after `initState` and again any time an ancestor
  ## inherited-widget the state depends on changes. Override to react.
  ## Default no-op.

method dispose*(s: State) {.base.} = s.mounted = false
  ## Called when the state's element is being unmounted. Override to
  ## release resources (cancel animation controllers, close streams).
  ## Default sets `mounted = false`.

method didUpdateWidget*(s: State, old: StatefulWidget) {.base.} = discard
  ## Called when the widget config above this state is replaced with a
  ## new (compatible) instance. `old` is the previous widget. Override
  ## to compare and react (e.g., reset internal state when a key prop
  ## changes). Default no-op.

method reassemble*(s: State) {.base.} = discard
  ## Hook for hot-reload integrations. Default no-op.

# RenderObjectWidget
method createRenderObject*(w: RenderObjectWidget, ctx: BuildContext): RenderObject {.base.} =
  ## Constructs the `RenderObject` that backs this widget. Subclasses
  ## MUST override. The base raises `Defect`.
  raise newException(Defect, "RenderObjectWidget.createRenderObject must be overridden")

method updateRenderObject*(w: RenderObjectWidget, ctx: BuildContext, r: RenderObject) {.base.} =
  ## Mirrors widget-config changes onto the existing render object on
  ## reconciliation. Subclasses override to copy fields (color,
  ## decoration, padding, etc.) and call `markNeedsLayout` /
  ## `markNeedsPaint` as appropriate. Default no-op.
  discard

# ProxyWidget / InheritedWidget
method child*(p: ProxyWidget): Widget {.base.} = p.child
  ## Returns the wrapped child widget. Default returns `p.child`.

method updateShouldNotify*(w: InheritedWidget, old: InheritedWidget): bool {.base.} = true
  ## Called when a new instance of this inherited widget replaces an
  ## old one. Return `true` if dependents should rebuild. The default
  ## returns `true` (always notify); override for cheaper updates.

# ---- Element machinery ----

var nextElementId {.compileTime.} = 0

proc newElement*(kind: ElementKind, widget: Widget): Element =
  ## Builds an `Element` of the given kind wrapping `widget`. Called by
  ## widget `createElement` overrides. The element is initially `dirty`
  ## so the next rebuild pass populates its children.
  Element(kind: kind, widget: widget, dirty: true, children: @[],
          inheritedAncestors: initTable[string, Element]())

var onSetStateRoot*: proc(root: Element) = proc(_: Element) = discard
  ## Hook assigned by the runtime in `binding.nim`. Called with the
  ## dirty element whenever `setState` or `markNeedsBuild` fires.

var inBuildPhase* {.threadvar.}: bool
  ## True while the runtime is in the middle of running
  ## `StatelessWidget.build` or `State.build`. The runtime sets and
  ## clears this around its rebuild pass. `setState` checks it to
  ## raise on misuse.

proc setState*(s: State, fn: proc()) =
  ## Updates `State` and schedules a rebuild. The callback `fn` is run
  ## synchronously to mutate state; afterward the element is marked
  ## dirty and the runtime is told to rebuild this subtree on the
  ## next frame.
  ##
  ## Inputs:
  ## - `s`: the State whose data is changing.
  ## - `fn`: a closure that mutates fields on `s`.
  ##
  ## Effect: marks `s.element` dirty and adds it to the binding's
  ## dirty-roots queue. Raises `Defect` if called during `build` (a
  ## common Flutter misuse).
  if inBuildPhase:
    raise newException(Defect,
      "setState called during build. Move the call out of build() " &
      "into a frame callback, event handler, or initState().")
  fn()
  if not s.element.isNil:
    s.element.dirty = true
    onSetStateRoot(s.element)

proc markNeedsBuild*(e: Element) =
  ## Marks `e` dirty and asks the runtime to rebuild it. Lower-level
  ## than `setState`; use it from outside a `State` (e.g., from a
  ## global event handler).
  if e.isNil or e.dirty: return
  e.dirty = true
  onSetStateRoot(e)

# Reconciliation

proc updateChild*(parent: Element, oldChild: Element, newWidget: Widget, slot: int): Element =
  ## Decides what to do with a slot during reconciliation:
  ## - `newWidget == nil`: unmount oldChild (if any), return nil.
  ## - `oldChild == nil`: mount a new element for `newWidget`.
  ## - `canUpdate(oldChild.widget, newWidget)`: keep oldChild, swap
  ##   widget, mark dirty.
  ## - otherwise: mount a new element to replace oldChild.
  ##
  ## Inputs:
  ## - `parent`: the parent element of the slot.
  ## - `oldChild`: the existing element in that slot, or nil.
  ## - `newWidget`: the new widget for that slot, or nil.
  ## - `slot`: index of the slot within the parent's children.
  ##
  ## Returns the element to install at that slot (possibly `nil` if
  ## the slot is empty).
  if newWidget.isNil:
    if not oldChild.isNil:
      discard  # actual unmount happens in `unmount` (runtime.nim)
    return nil
  if oldChild.isNil:
    let child = newWidget.createElement()
    child.parent = parent
    child.depth = parent.depth + 1
    child.slot = slot
    return child
  if canUpdate(oldChild.widget, newWidget):
    oldChild.widget = newWidget
    oldChild.dirty = true
    oldChild.slot = slot
    return oldChild
  # Replace
  let child = newWidget.createElement()
  child.parent = parent
  child.depth = parent.depth + 1
  child.slot = slot
  return child

# Build paths per element kind

method performRebuild*(e: Element) {.base.} =
  ## Recompute this element's child widget tree and reconcile. The
  ## runtime calls this on dirty elements during the rebuild pass.
  ## Default clears the dirty flag; concrete element kinds do the
  ## real work in `runtime.rebuildElement`.
  e.dirty = false

# Walk

proc visit*(e: Element, fn: proc(child: Element)) =
  ## Calls `fn` on each direct child of `e`. Order is the same as
  ## `e.children`.
  for c in e.children: fn(c)

proc visitDeep*(e: Element, fn: proc(child: Element)) =
  ## Calls `fn` on `e` then recursively on every descendant
  ## (pre-order).
  fn(e)
  for c in e.children: visitDeep(c, fn)

# Inherited lookup

proc findInheritedOfType*[T: InheritedWidget](e: Element): T =
  ## Walks the parent chain starting at `e` until it finds an
  ## `InheritedWidget` of exactly type `T`. Returns nil if none.
  ##
  ## Note: in flit today this lookup is NOT cached and does NOT
  ## register `e` as a dependent of the inherited widget. If the
  ## inherited widget's data changes, callers must trigger a rebuild
  ## themselves.
  var cur = e
  while not cur.isNil:
    if cur.widget of T:
      return T(cur.widget)
    cur = cur.parent
  nil

# Debug

proc debugDescribe*(e: Element): DiagnosticsNode =
  ## Returns a `DiagnosticsNode` describing this element and its
  ## subtree. Each node carries the widget's runtime type name, depth,
  ## dirty flag and key. Used by the inspector / `prettyPrint`.
  let n = node(e.widget.widgetTypeName,
               "depth=" & $e.depth & (if e.dirty: " [dirty]" else: ""))
  if not e.widget.key.isNil:
    n.add("key", $e.widget.key)
  for c in e.children:
    n.add(debugDescribe(c))
  n
