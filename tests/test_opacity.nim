## Opacity widget actually attenuates the alpha channel of every primitive
## the canvas draws inside it.

import std/unittest
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime

type
  RecCanvas = ref object of Canvas
    fills*: seq[uint32]

method drawRect*(c: RecCanvas, r: Rect, fill: uint32) =
  c.fills.add(c.applyOpacity(fill))

suite "Opacity":
  test "currentOpacity defaults to 1.0":
    let c = RecCanvas(size: Size(width: 100, height: 100))
    check c.currentOpacity == 1.0'f32

  test "pushOpacity multiplies; pop restores":
    let c = RecCanvas(size: Size(width: 100, height: 100))
    c.pushOpacity(0.5)
    check c.currentOpacity == 0.5'f32
    c.pushOpacity(0.5)
    check c.currentOpacity == 0.25'f32   # multiplied
    c.popOpacity()
    check c.currentOpacity == 0.5'f32
    c.popOpacity()
    check c.currentOpacity == 1.0'f32

  test "applyOpacity halves the alpha of an opaque red":
    let c = RecCanvas(size: Size(width: 100, height: 100))
    c.pushOpacity(0.5)
    let dim = c.applyOpacity(0xFFFF0000'u32)
    let alpha = (dim shr 24) and 0xFF
    check alpha >= 126 and alpha <= 128

  test "Opacity widget pushes/pops around its child":
    let tree = opacity(
      child = coloredBox(color = colorRed),
      opacity = 0.5'f32)
    let root = mountElement(nil, tree, 0)
    runLayout(root, tightFor(100, 100))
    let c = RecCanvas(size: Size(width: 100, height: 100))
    runPaint(root, c)
    check c.fills.len >= 1
    let alpha = (c.fills[0] shr 24) and 0xFF
    check alpha >= 126 and alpha <= 128
    # Canvas opacity stack should be empty again after paint.
    check c.currentOpacity == 1.0'f32

when isMainModule: discard
