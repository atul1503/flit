## Accessibility semantics. The `Semantics` widget annotates its
## subtree with role, label, value, hint, and actions; a
## `SemanticsTree` walk produces a flat list of nodes for a
## screen reader to consume.
##
## Today this is a tree-building primitive and a JSON export, not
## a wire to OS accessibility services. Platform integration with
## AppKit (NSAccessibility), AT-SPI (Linux), and UIAutomation
## (Windows) is a separate cross-platform project; the tree this
## module produces is the data such an integration would consume.
##
## Public surface:
## - `semantics(...)` widget constructor.
## - `buildSemanticsTree(root)`: walk the element tree, return
##   the flat node list.
## - `toJson(nodes)`: serialize the tree for tools.

import std/[tables, strutils, options]
import ./widget
import ./geometry
import ./key

type
  SemanticsRole* = enum
    ## Roles a node can advertise. Maps cleanly to AT-SPI and
    ## UIAutomation roles; AppKit has a smaller set so we collapse
    ## several roles when bridging.
    srNone, srButton, srLink, srTextField, srCheckbox, srRadio,
    srImage, srHeading, srList, srListItem, srTab, srTabList,
    srSlider, srProgressBar, srSearchBox, srStatic

  SemanticsAction* = enum
    ## Actions a node supports. Screen readers expose these to the
    ## user; selecting one dispatches the bound callback.
    saTap, saLongPress, saIncrement, saDecrement, saScrollUp,
    saScrollDown, saScrollLeft, saScrollRight, saDismiss

  Semantics* = ref object of ProxyWidget
    ## Annotates its child with accessibility metadata. The
    ## metadata is invisible at runtime; assistive tech reads it
    ## via the semantics tree.
    role*:        SemanticsRole
    label*:       string
    value*:       string
    hint*:        string
    enabled*:     bool
    focused*:     bool
    actions*:     set[SemanticsAction]
    onAction*:    proc(action: SemanticsAction) {.closure.}

  SemanticsNode* = object
    ## A single node in the flat semantics list. Position is in
    ## screen pixels; size is in screen pixels too. Parent / child
    ## relationships are encoded by `parentIndex` (`-1` for the
    ## root).
    id*:          int
    parentIndex*: int
    role*:        SemanticsRole
    label*:       string
    value*:       string
    hint*:        string
    enabled*:     bool
    focused*:     bool
    actions*:     set[SemanticsAction]
    bounds*:      Rect

method widgetTypeName*(w: Semantics): string = "Semantics"
method createElement*(w: Semantics): Element = newElement(ekProxy, w)

proc semantics*(child: Widget,
                role: SemanticsRole = srNone,
                label: string = "",
                value: string = "",
                hint: string = "",
                enabled: bool = true,
                focused: bool = false,
                actions: set[SemanticsAction] = {},
                onAction: proc(action: SemanticsAction) = nil,
                key: Key = nil): Semantics =
  ## Wraps `child` in a semantics annotation.
  ##
  ## Inputs:
  ## - `child`: the subtree this annotation describes. Required.
  ## - `role`: what kind of widget this is (button, text field,
  ##   image, etc.). Drives assistive tech behavior.
  ## - `label`: short human-readable name. The thing a screen
  ##   reader announces.
  ## - `value`: current value (the text in a text field, the
  ##   position in a slider).
  ## - `hint`: longer description, what activating this does.
  ## - `enabled`: false means greyed-out / non-interactive.
  ## - `focused`: true when this widget owns keyboard focus.
  ## - `actions`: set of actions this widget supports.
  ## - `onAction`: dispatcher for assistive-tech actions. Receives
  ##   the chosen action.
  ## - `key`: reconciliation key.
  Semantics(key: key, child: child, role: role, label: label,
            value: value, hint: hint, enabled: enabled,
            focused: focused, actions: actions, onAction: onAction)

# Walking the element tree to extract semantics nodes. We can't
# easily get screen positions without the render tree, so for now
# `bounds` stays as `Rect()` (zero) unless the caller wires
# coordinates externally. A future pass can plumb the render tree
# in.

proc buildSemanticsTree*(root: Element): seq[SemanticsNode] =
  ## Walks the element tree from `root` and returns a flat list
  ## of `SemanticsNode`s, parent-referenced. The first entry is
  ## the root (which may itself not have a Semantics wrapper).
  result = @[]
  if root.isNil: return
  var stack: seq[(Element, int)]   # (element, parent-index-in-result)
  stack.add((root, -1))
  while stack.len > 0:
    let (e, parentIdx) = stack.pop()
    if e.isNil: continue
    let myIdx =
      if e.widget of Semantics:
        let s = Semantics(e.widget)
        let node = SemanticsNode(
          id: result.len,
          parentIndex: parentIdx,
          role: s.role,
          label: s.label,
          value: s.value,
          hint: s.hint,
          enabled: s.enabled,
          focused: s.focused,
          actions: s.actions)
        result.add(node)
        result.len - 1
      else:
        parentIdx
    # Walk children in reverse so they pop in order.
    for i in countdown(e.children.len - 1, 0):
      stack.add((e.children[i], myIdx))

proc roleName(r: SemanticsRole): string =
  case r
  of srNone: "none"
  of srButton: "button"
  of srLink: "link"
  of srTextField: "textfield"
  of srCheckbox: "checkbox"
  of srRadio: "radio"
  of srImage: "image"
  of srHeading: "heading"
  of srList: "list"
  of srListItem: "listitem"
  of srTab: "tab"
  of srTabList: "tablist"
  of srSlider: "slider"
  of srProgressBar: "progressbar"
  of srSearchBox: "searchbox"
  of srStatic: "static"

proc actionName(a: SemanticsAction): string =
  case a
  of saTap: "tap"
  of saLongPress: "longpress"
  of saIncrement: "increment"
  of saDecrement: "decrement"
  of saScrollUp: "scrollup"
  of saScrollDown: "scrolldown"
  of saScrollLeft: "scrollleft"
  of saScrollRight: "scrollright"
  of saDismiss: "dismiss"

proc escapeJson(s: string): string =
  result = newStringOfCap(s.len + 2)
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\t': result.add("\\t")
    of '\r': result.add("\\r")
    else: result.add(c)

proc toJson*(nodes: seq[SemanticsNode]): string =
  ## Serializes the semantics tree as a JSON array. Each entry is
  ## an object with `id`, `parent`, `role`, `label`, `value`,
  ## `hint`, `enabled`, `focused`, `actions`. Use to dump the
  ## tree to disk for accessibility audits, or to send over a
  ## platform IPC.
  var parts: seq[string]
  for n in nodes:
    var actionParts: seq[string]
    for a in n.actions: actionParts.add("\"" & actionName(a) & "\"")
    let obj = "{\"id\":" & $n.id &
              ",\"parent\":" & $n.parentIndex &
              ",\"role\":\"" & roleName(n.role) & "\"" &
              ",\"label\":\"" & escapeJson(n.label) & "\"" &
              ",\"value\":\"" & escapeJson(n.value) & "\"" &
              ",\"hint\":\"" & escapeJson(n.hint) & "\"" &
              ",\"enabled\":" & (if n.enabled: "true" else: "false") &
              ",\"focused\":" & (if n.focused: "true" else: "false") &
              ",\"actions\":[" & actionParts.join(",") & "]}"
    parts.add(obj)
  "[" & parts.join(",") & "]"
