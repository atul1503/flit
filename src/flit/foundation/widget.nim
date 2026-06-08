## Widget framework. Three trees, just like Flutter:
##
##   Widget  immutable description of part of UI (config object)
##   Element a long-lived instance of a Widget at a position in the tree
##   Render  the actual layout/paint tree
##
## Widgets can be StatelessWidget, StatefulWidget, ProxyWidget (e.g.
## InheritedWidget), or RenderObjectWidget. The framework reconciles
## newly-built widgets against existing Elements to decide whether to
## update in place or rebuild a subtree.

import std/[tables, options]
import ./key
import ./render_object
import ./geometry
import ./diagnostics
export key

type
  Widget* = ref object of RootObj
    key*: Key

  StatelessWidget*    = ref object of Widget
  StatefulWidget*     = ref object of Widget
  RenderObjectWidget* = ref object of Widget
  ProxyWidget*        = ref object of Widget
    child*: Widget
  InheritedWidget*    = ref object of ProxyWidget

  ElementKind* = enum
    ekStateless, ekStateful, ekRender, ekProxy, ekInherited, ekRoot

  Element* = ref object of RootObj
    kind*:   ElementKind
    widget*: Widget
    parent*: Element
    children*: seq[Element]
    dirty*:  bool
    depth*:  int
    renderObj*: RenderObject
    inheritedAncestors*: Table[string, Element]  # type-name -> nearest inherited
    state*: State    # only for ekStateful
    slot*: int

  State* = ref object of RootObj
    element*: Element
    mounted*: bool

  BuildContext* = Element  # in Flutter BuildContext is an Element interface

# ---- Widget API ----

method createElement*(w: Widget): Element {.base.} =
  raise newException(Defect, "Widget.createElement must be overridden")

method widgetTypeName*(w: Widget): string {.base.} = "Widget"
  ## Subclasses override to return a stable identifier for runtime-type
  ## comparison. The framework uses this for reconciliation.

method canUpdate*(oldW, newW: Widget): bool {.base.} =
  ## Two widgets can update an existing Element only if they have the same
  ## runtime type AND the same key.
  if oldW.isNil or newW.isNil: return false
  if oldW.widgetTypeName != newW.widgetTypeName: return false
  oldW.key == newW.key

# StatelessWidget
method build*(w: StatelessWidget, ctx: BuildContext): Widget {.base.} =
  raise newException(Defect, "StatelessWidget.build must be overridden")

# StatefulWidget
method createState*(w: StatefulWidget): State {.base.} =
  raise newException(Defect, "StatefulWidget.createState must be overridden")

# State
method build*(s: State, ctx: BuildContext): Widget {.base.} =
  raise newException(Defect, "State.build must be overridden")
method initState*(s: State) {.base.} = s.mounted = true
method didChangeDependencies*(s: State) {.base.} = discard
method dispose*(s: State) {.base.} = s.mounted = false
method didUpdateWidget*(s: State, old: StatefulWidget) {.base.} = discard
method reassemble*(s: State) {.base.} = discard

# RenderObjectWidget
method createRenderObject*(w: RenderObjectWidget, ctx: BuildContext): RenderObject {.base.} =
  raise newException(Defect, "RenderObjectWidget.createRenderObject must be overridden")
method updateRenderObject*(w: RenderObjectWidget, ctx: BuildContext, r: RenderObject) {.base.} =
  discard

# ProxyWidget / InheritedWidget
method child*(p: ProxyWidget): Widget {.base.} = p.child
method updateShouldNotify*(w: InheritedWidget, old: InheritedWidget): bool {.base.} = true

# ---- Element machinery ----

var nextElementId {.compileTime.} = 0

proc newElement*(kind: ElementKind, widget: Widget): Element =
  Element(kind: kind, widget: widget, dirty: true, children: @[],
          inheritedAncestors: initTable[string, Element]())

# Rebuild scheduler hook. Assigned by the runtime in `app.nim`.
# Declared before `setState` so the proc can capture it.
var onSetStateRoot*: proc(root: Element) = proc(_: Element) = discard

proc setState*(s: State, fn: proc()) =
  ## Mark THIS state's element dirty (not the whole root). The runner
  ## rebuilds only that subtree, which is much cheaper when the state
  ## change is local to one widget.
  fn()
  if not s.element.isNil:
    s.element.dirty = true
    onSetStateRoot(s.element)

proc markNeedsBuild*(e: Element) =
  if e.isNil or e.dirty: return
  e.dirty = true
  onSetStateRoot(e)

# Reconciliation

proc updateChild*(parent: Element, oldChild: Element, newWidget: Widget, slot: int): Element =
  ## Compare oldChild with newWidget and either update in place, replace,
  ## or insert a fresh child.
  if newWidget.isNil:
    if not oldChild.isNil:
      # unmount oldChild (recursive)
      discard
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
  e.dirty = false

# Walk

proc visit*(e: Element, fn: proc(child: Element)) =
  for c in e.children: fn(c)

proc visitDeep*(e: Element, fn: proc(child: Element)) =
  fn(e)
  for c in e.children: visitDeep(c, fn)

# Inherited lookup

proc findInheritedOfType*[T: InheritedWidget](e: Element): T =
  ## Walk up the tree until we find an InheritedWidget of exactly type T.
  var cur = e
  while not cur.isNil:
    if cur.widget of T:
      return T(cur.widget)
    cur = cur.parent
  nil

# Debug

proc debugDescribe*(e: Element): DiagnosticsNode =
  let n = node(e.widget.widgetTypeName,
               "depth=" & $e.depth & (if e.dirty: " [dirty]" else: ""))
  if not e.widget.key.isNil:
    n.add("key", $e.widget.key)
  for c in e.children:
    n.add(debugDescribe(c))
  n
