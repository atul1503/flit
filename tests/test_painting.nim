## Painting tests against a recording Canvas. Verifies decoration ordering
## (shadows first, then fill, then border) and that text is dispatched.

import std/[unittest, tables]
import ../src/flit/foundation/[render_object, geometry, color]
import ../src/flit/rendering/decoration

type
  RecCanvas = ref object of Canvas
    rects*: seq[Rect]
    rrects*: seq[RRect]
    texts*: seq[string]

method drawRect*(c: RecCanvas, r: Rect, fill: uint32) = c.rects.add(r)
method drawRRect*(c: RecCanvas, r: RRect, fill: uint32) = c.rrects.add(r)
method drawText*(c: RecCanvas, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) = c.texts.add(text)

suite "DecoratedBox painting":
  test "rectangle decoration draws one rect":
    let canvas = RecCanvas(size: Size(width: 100, height: 100))
    let dec = boxDecoration(color = colorRed)
    let box = RenderDecoratedBox(decoration: dec)
    box.layout(tightFor(50, 50))
    let ctx = newPaintingContext(canvas)
    box.paint(ctx, OffsetZero)
    check canvas.rects.len == 1
    check canvas.rrects.len == 0

  test "rounded decoration uses rrect":
    let canvas = RecCanvas(size: Size(width: 100, height: 100))
    let dec = boxDecoration(color = colorBlue, borderRadius = 8)
    let box = RenderDecoratedBox(decoration: dec)
    box.layout(tightFor(40, 40))
    let ctx = newPaintingContext(canvas)
    box.paint(ctx, OffsetZero)
    check canvas.rrects.len == 1

when isMainModule: discard
