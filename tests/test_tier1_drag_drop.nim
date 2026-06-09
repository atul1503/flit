## Drag & drop: OS-level file drop dispatch and intra-app
## drag widget construction.

import std/unittest
import ../src/flit/widgets/drag_drop
import ../src/flit/widgets/basic
import ../src/flit/foundation/widget

suite "drag_drop - OS file drops":
  test "onFileDrop registers a handler":
    fileDropHandlers.setLen(0)
    var got: seq[string]
    onFileDrop(proc(p: string) = got.add(p))
    check fileDropHandlers.len == 1
    dispatchFileDrop("/tmp/test.txt")
    check got == @["/tmp/test.txt"]

  test "multiple handlers all fire in order":
    fileDropHandlers.setLen(0)
    var order: seq[int]
    onFileDrop(proc(p: string) = order.add(1))
    onFileDrop(proc(p: string) = order.add(2))
    onFileDrop(proc(p: string) = order.add(3))
    dispatchFileDrop("/tmp/x")
    check order == @[1, 2, 3]

  test "handler that throws does not block subsequent handlers":
    fileDropHandlers.setLen(0)
    var ran: seq[int]
    onFileDrop(proc(p: string) =
      ran.add(1)
      raise newException(ValueError, "boom"))
    onFileDrop(proc(p: string) = ran.add(2))
    dispatchFileDrop("/tmp/x")
    check ran == @[1, 2]

  test "dispatch with zero handlers is a no-op":
    fileDropHandlers.setLen(0)
    dispatchFileDrop("/tmp/x")
    check fileDropHandlers.len == 0

suite "drag_drop - widgets":
  test "dragData builder":
    let d = dragData("note-id", cast[pointer](42))
    check d.kind == "note-id"
    check cast[int](d.payload) == 42

  test "dragSource constructs a widget":
    let w = dragSource(child = text("drag me"),
                       data = dragData("file-path"))
    check not w.isNil
    check w.widgetTypeName == "DragSource"
    check w.data.kind == "file-path"

  test "dropTarget constructs a widget":
    var dropped = false
    let w = dropTarget(child = text("drop here"),
                       onDrop = proc(d: DragData) = dropped = true)
    check not w.isNil
    check w.widgetTypeName == "DropTarget"

  test "dropTarget accept filter is optional":
    let w = dropTarget(child = text("zone"),
                       onDrop = proc(d: DragData) = discard,
                       accept = nil)
    check w.accept.isNil
