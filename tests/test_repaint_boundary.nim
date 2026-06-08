## RepaintBoundary tests. Verifies cache-bearing layers actually cache:
## first paint rasterizes into a sub-canvas, subsequent paints reuse
## the cache, and `markNeedsPaint` invalidates it.

import std/unittest
import ../src/flit
import ../src/flit/foundation/[runtime, render_object]
import ../src/flit/rendering/proxy_box

type
  CountingCanvas = ref object of Canvas
    drawCalls*: int
    createSubCalls*: int
    compositeCalls*: int

method drawRect*(c: CountingCanvas, r: Rect, fill: uint32) =
  inc c.drawCalls

method clear*(c: CountingCanvas, color: uint32) = discard

method createSubCanvas*(c: CountingCanvas, w, h: int): Canvas =
  inc c.createSubCalls
  let sub = CountingCanvas(size: Size(width: float32(w), height: float32(h)))
  Canvas(sub)

method compositeSubCanvas*(c: CountingCanvas, sub: Canvas,
                          offset: Offset, size: Size) =
  inc c.compositeCalls

proc newCountingCanvas(w, h: float32): CountingCanvas =
  CountingCanvas(size: Size(width: w, height: h))

suite "RepaintBoundary cache":
  test "first paint rasterizes into the sub-canvas (createSubCanvas called once)":
    let tree = repaintBoundary(
      coloredBox(color = colorRed,
        child = sizedBox(width = 50, height = 50)))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(200, 200))
    let canvas = newCountingCanvas(200, 200)
    runPaint(root, canvas)
    check canvas.createSubCalls == 1
    check canvas.compositeCalls == 1

  test "second paint with no changes does NOT call createSubCanvas again":
    let tree = repaintBoundary(
      coloredBox(color = colorRed,
        child = sizedBox(width = 50, height = 50)))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(200, 200))
    let canvas = newCountingCanvas(200, 200)
    runPaint(root, canvas)
    let firstCreates = canvas.createSubCalls
    # Now repaint without changing anything.
    runPaint(root, canvas)
    check canvas.createSubCalls == firstCreates  # sub-canvas reused
    check canvas.compositeCalls == 2             # but still composited

  test "markNeedsPaint inside the boundary sets cacheDirty":
    let inner = coloredBox(color = colorRed,
                           child = sizedBox(width = 50, height = 50))
    let tree = repaintBoundary(inner)
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(200, 200))
    let canvas = newCountingCanvas(200, 200)
    runPaint(root, canvas)
    # Reach into the render tree, find the boundary, find a descendant
    # render object, mark it as needing paint. The mark should
    # propagate up and flip the boundary's cacheDirty flag.
    let rE = descendantRenderElement(root)
    let boundary = RenderRepaintBoundary(rE.renderObj)
    check boundary.cacheDirty == false
    if not boundary.child.isNil:
      boundary.child.markNeedsPaint()
    check boundary.cacheDirty == true

  test "boundary survives child reuse without losing cache identity":
    # Two renders in a row should not throw, should not regenerate
    # the sub-canvas. This is the core perf property.
    let tree = repaintBoundary(
      coloredBox(color = colorBlue,
        child = sizedBox(width = 40, height = 40)))
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(100, 100))
    let canvas = newCountingCanvas(100, 100)
    runPaint(root, canvas)
    runPaint(root, canvas)
    runPaint(root, canvas)
    check canvas.createSubCalls == 1   # made once
    check canvas.compositeCalls == 3   # composited three times
