## Layer tree tests. Pure data-structure tests; no rendering.
## Verifies parenting, dirty propagation through `markBoundaryDirty`,
## and the default container composite walks children.

import std/unittest
import ../src/flit/foundation/[layer, geometry, render_object]

type
  RecordingCanvas = ref object of Canvas
    rects*: seq[Rect]

method drawRect*(c: RecordingCanvas, r: Rect, fill: uint32) =
  c.rects.add(r)

suite "Layer tree":
  test "add() sets parent and appends to children":
    let parent = ContainerLayer()
    let child = PictureLayer()
    parent.add(child)
    check parent.children.len == 1
    check child.parent == Layer(parent)

  test "add(nil) is a safe no-op":
    let parent = ContainerLayer()
    parent.add(nil)
    check parent.children.len == 0

  test "markBoundaryDirty walks up to the nearest boundary":
    let root = ContainerLayer()
    let boundary = BoundaryLayer(size: Size(width: 100, height: 100))
    let leaf = PictureLayer()
    root.add(boundary)
    boundary.add(leaf)
    boundary.dirty = false
    leaf.markBoundaryDirty()
    check boundary.dirty == true

  test "markBoundaryDirty stops at the first boundary":
    let root = ContainerLayer()
    let outerBoundary = BoundaryLayer(size: Size(width: 200, height: 200))
    let innerBoundary = BoundaryLayer(size: Size(width: 100, height: 100))
    let leaf = PictureLayer()
    root.add(outerBoundary)
    outerBoundary.add(innerBoundary)
    innerBoundary.add(leaf)
    outerBoundary.dirty = false
    innerBoundary.dirty = false
    leaf.markBoundaryDirty()
    check innerBoundary.dirty == true
    check outerBoundary.dirty == false  # outer is unaffected

  test "container composite walks children in order":
    let parent = ContainerLayer()
    var seen: seq[Rect]
    let l1 = newPictureLayer(proc(canvas: Canvas, offset: Offset) =
      canvas.drawRect(Rect(left: 0, top: 0, right: 10, bottom: 10), 0xFF000000'u32))
    let l2 = newPictureLayer(proc(canvas: Canvas, offset: Offset) =
      canvas.drawRect(Rect(left: 20, top: 20, right: 30, bottom: 30), 0xFF000000'u32))
    parent.add(l1)
    parent.add(l2)
    let canvas = RecordingCanvas()
    composite(parent, Canvas(canvas), OffsetZero)
    check canvas.rects.len == 2

  test "clearChildren drops the child list":
    let parent = ContainerLayer()
    parent.add(PictureLayer())
    parent.add(PictureLayer())
    parent.clearChildren()
    check parent.children.len == 0
