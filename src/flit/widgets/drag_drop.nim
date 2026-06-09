## Drag and drop.
##
## Two distinct scopes:
##
## 1. OS-level file drops: a user drags a file from Finder/Explorer
##    into the flit window. Handled by registering a callback with
##    `onFileDrop(cb)`; the desktop runner dispatches incoming
##    SDL `DropFile` events to it.
##
## 2. Intra-app dragging: a user picks up a flit widget and drops
##    it on another flit widget. Provided as `DragSource` and
##    `DropTarget` widgets. The widget that wraps a Draggable
##    starts a pan; while the pan is active a "ghost" widget
##    follows the pointer; on release the topmost overlapping
##    DropTarget receives the data.
##
## Cross-process drag-out (drag a flit widget onto Finder) is
## platform-specific and is out of scope for this initial cut.

import std/[tables]
import ../foundation/[widget, render_object, geometry, color, key, runtime,
                       binding]
import ../widgets/basic
import ../gestures/detector

# --- OS file drop registration ---

type
  FileDropHandler* = proc(path: string) {.closure.}
    ## Callback fired when the OS drops a file path on the window.
    ## Receives one absolute path per call. If the user drops
    ## multiple files at once the runner calls the handler once
    ## per file.

var fileDropHandlers* {.threadvar.}: seq[FileDropHandler]
  ## Registry of file-drop callbacks. Mutate via `onFileDrop`;
  ## the platform runner reads this on SDL DropFile events.

proc onFileDrop*(cb: FileDropHandler) =
  ## Registers `cb` to be called when the OS drops a file path
  ## onto the window. Multiple handlers can register; each fires.
  ## Call from your app's startup after `runApp`.
  fileDropHandlers.add(cb)

proc dispatchFileDrop*(path: string) =
  ## Called by the platform runner when a DropFile event arrives.
  ## Public so runners can call it; users don't typically call
  ## this directly.
  let snapshot = fileDropHandlers
  for h in snapshot:
    try: h(path) except CatchableError: discard

# --- Intra-app drag and drop ---

type
  DragData* = ref object
    ## Opaque payload carried during an intra-app drag. Pass any
    ## ref or seq you want; the receiving DropTarget casts back.
    payload*: pointer
    kind*:    string   # tag for the receiver to filter on

  ActiveDrag = ref object
    data: DragData
    ghost: Widget
    startPos: Offset
    currentPos: Offset

var activeDrag* {.threadvar.}: ActiveDrag
  ## The drag currently in flight, or nil. Set by a `DragSource`
  ## when a pan starts; cleared by the matching DropTarget on
  ## release. Exposed so custom widgets can render a ghost or
  ## decide hit-test behavior during a drag.

type
  DragSource* = ref object of StatefulWidget
    ## A widget that initiates a drag when the user starts a pan
    ## on it. The data emitted is provided via `data`.
    data*:   DragData
    ghost*:  Widget     # what follows the pointer while dragging
    child*:  Widget

  DragSourceState = ref object of State

  DropTarget* = ref object of StatefulWidget
    ## A widget that accepts a drop. The `accept` predicate is
    ## called when a drag enters; the `onDrop` callback fires
    ## when the user releases over this widget.
    accept*:  proc(data: DragData): bool {.closure.}
    onDrop*:  proc(data: DragData) {.closure.}
    child*:   Widget

  DropTargetState = ref object of State
    hovering: bool

method widgetTypeName*(w: DragSource): string = "DragSource"
method createElement*(w: DragSource): Element = newElement(ekStateful, w)
method createState*(w: DragSource): State = DragSourceState()

method build*(s: DragSourceState, ctx: BuildContext): Widget =
  let host = DragSource(s.element.widget)
  let onStart: PointerCallback = proc(pos: Offset) =
    activeDrag = ActiveDrag(data: host.data, ghost: host.ghost,
                            startPos: pos, currentPos: pos)
  let onUpdate: DragUpdate = proc(pos, delta: Offset) =
    if not activeDrag.isNil:
      activeDrag.currentPos = pos
  let onEnd: TapCallback = proc() =
    if not activeDrag.isNil:
      activeDrag = nil
  gestureDetector(
    behavior = htOpaque,
    onPanStart = onStart,
    onPanUpdate = onUpdate,
    onPanEnd = onEnd,
    child = host.child)

method widgetTypeName*(w: DropTarget): string = "DropTarget"
method createElement*(w: DropTarget): Element = newElement(ekStateful, w)
method createState*(w: DropTarget): State = DropTargetState()

method build*(s: DropTargetState, ctx: BuildContext): Widget =
  let host = DropTarget(s.element.widget)
  let onUpdate: DragUpdate = proc(pos, delta: Offset) =
    if not activeDrag.isNil:
      let accepted = host.accept.isNil or host.accept(activeDrag.data)
      if accepted != s.hovering:
        setState(s, proc() = s.hovering = accepted)
  let onEnd: TapCallback = proc() =
    if not activeDrag.isNil:
      let accepted = host.accept.isNil or host.accept(activeDrag.data)
      if accepted and not host.onDrop.isNil:
        try: host.onDrop(activeDrag.data) except CatchableError: discard
      activeDrag = nil
      if s.hovering:
        setState(s, proc() = s.hovering = false)
  gestureDetector(
    behavior = htTranslucent,
    onPanUpdate = onUpdate,
    onPanEnd = onEnd,
    child = host.child)

# Public constructors

proc dragSource*(child: Widget,
                 data: DragData,
                 ghost: Widget = nil,
                 key: Key = nil): DragSource =
  ## Builds a `DragSource`.
  ##
  ## Wraps `child` so that a pan on it starts a drag carrying
  ## `data`. `ghost` is an optional preview widget; when nil the
  ## drag is "invisible" (the source widget stays in place).
  ##
  ## Inputs:
  ## - `child`: the widget the user can pick up.
  ## - `data`: the payload to deliver to a DropTarget on release.
  ## - `ghost`: optional widget that follows the pointer while
  ##   dragging. nil for no ghost.
  ## - `key`: optional reconciliation key.
  DragSource(key: key, child: child, data: data, ghost: ghost)

proc dropTarget*(child: Widget,
                 onDrop: proc(data: DragData),
                 accept: proc(data: DragData): bool = nil,
                 key: Key = nil): DropTarget =
  ## Builds a `DropTarget`.
  ##
  ## Wraps `child` so it receives drops. `onDrop` fires when the
  ## user releases a drag over this widget. `accept` filters
  ## (return true to accept, false to ignore); nil accepts all.
  ##
  ## Inputs:
  ## - `child`: the visible drop zone.
  ## - `onDrop`: called with the dragged payload on release.
  ## - `accept`: predicate that decides whether this target wants
  ##   the drag. nil accepts every drag. Use to scope drops by
  ##   `data.kind`.
  ## - `key`: optional reconciliation key.
  DropTarget(key: key, child: child, onDrop: onDrop, accept: accept)

proc dragData*(kind: string, payload: pointer = nil): DragData =
  ## Convenience builder. `kind` is a tag the receiver uses to
  ## decide whether to accept (e.g., `"note-id"`, `"file-path"`).
  DragData(kind: kind, payload: payload)
