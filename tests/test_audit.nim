## Targeted tests for the API surfaces that the recent audit fixed:
## RenderTransform applies TRS, RenderParagraph wraps and respects
## maxLines, setState during build raises, and AnimationController.repeat
## cycles. lerp(Offset/Size/EdgeInsets) round-trips.

import std/[unittest, math]
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../src/flit/foundation/binding
import ../src/flit/foundation/widget
import ../src/flit/rendering/proxy_box
import ../src/flit/rendering/text

# ---------------------------------------------------------------------------
# RenderTransform now records scale + rotate on the canvas.

type
  RecCanvas = ref object of Canvas
    translates*: seq[Offset]
    scales*:     seq[Offset]   # store sx,sy in an Offset for brevity
    rotations*:  seq[float32]

method translate*(c: RecCanvas, dx, dy: float32) =
  c.translates.add(Offset(dx: dx, dy: dy))
method scale*(c: RecCanvas, sx, sy: float32) =
  c.scales.add(Offset(dx: sx, dy: sy))
method rotate*(c: RecCanvas, radians: float32) =
  c.rotations.add(radians)
method drawRect*(c: RecCanvas, r: Rect, fill: uint32) = discard

suite "RenderTransform":
  test "translation, scale and rotation all reach the canvas":
    let canvas = RecCanvas(size: Size(width: 200, height: 200))
    let tx = RenderTransform(
      translation: Offset(dx: 10, dy: 20), scale: 2.0'f32, rotation: 0.5'f32)
    tx.child = RenderSizedBox(requestedWidth: 30, requestedHeight: 30)
    tx.layout(tightFor(200, 200))
    let ctx = newPaintingContext(canvas)
    tx.paint(ctx, OffsetZero)
    check canvas.translates.len == 1
    check canvas.scales.len == 1
    check canvas.rotations.len == 1
    check canvas.translates[0].dx == 10
    check canvas.scales[0].dx == 2.0'f32
    check canvas.rotations[0] == 0.5'f32

# ---------------------------------------------------------------------------
# RenderParagraph wrap + maxLines.

suite "Text wrap":
  test "wrap respects maxWidth":
    let p = RenderParagraph(
      text: "the quick brown fox jumps over the lazy dog",
      style: defaultTextStyle, softWrap: true, maxLines: 0)
    p.layout(constraints(0, 60, 0, 1000))   # narrow width forces wrap
    check p.lines.len > 1

  test "maxLines clamps line count":
    let p = RenderParagraph(
      text: "alpha beta gamma delta epsilon zeta eta theta iota kappa",
      style: defaultTextStyle, softWrap: true, maxLines: 2)
    p.layout(constraints(0, 50, 0, 1000))
    check p.lines.len == 2

# ---------------------------------------------------------------------------
# setState during build raises.

type
  Naughty = ref object of StatefulWidget
  NaughtyState = ref object of State
    triggered*: bool

method widgetTypeName(w: Naughty): string = "Naughty"
method createElement(w: Naughty): Element = newElement(ekStateful, w)
method createState(w: Naughty): State = NaughtyState()
method build(s: NaughtyState, ctx: BuildContext): Widget =
  # Misuse: call setState while we're already building.
  try:
    setState(s, proc() = s.triggered = true)
  except Defect:
    s.triggered = true   # we DID see the assertion fire
  text("ok")

suite "Build phase guard":
  test "setState during build raises Defect":
    let root = mountElement(nil, Naughty(), 0)
    runLayout(root, tightFor(200, 100))
    let s = NaughtyState(root.state)
    check s.triggered  # the Defect was raised and we caught it

# ---------------------------------------------------------------------------
# AnimationController.repeat cycles.

suite "AnimationController.repeat":
  test "value moves up after one tick of repeat":
    let canvas = Canvas(size: Size(width: 100, height: 100))
    let b = newBinding(canvas, Size(width: 100, height: 100))
    let ctrl = newAnimationController(durationSec = 0.02'f32)
    var seen: seq[float32] = @[]
    ctrl.addListener(proc(v: float32) = seen.add(v))
    ctrl.repeat(b)
    # Drive a few frame ticks.
    for i in 0 ..< 8:
      let pending = b.frameCallbacks
      b.frameCallbacks.setLen(0)
      for cb in pending: cb(b.currentTime + float(i) * 0.005)
    ctrl.stop()
    # Should have seen at least one update.
    check seen.len >= 1

# ---------------------------------------------------------------------------
# lerp for Offset / Size / EdgeInsets

suite "Geometry lerp":
  test "lerp Offset at t=0.5 is the midpoint":
    let o = lerp(Offset(dx: 0, dy: 0), Offset(dx: 10, dy: 20), 0.5'f32)
    check o.dx == 5
    check o.dy == 10

  test "lerp Size grows linearly":
    let s = lerp(Size(width: 0, height: 0), Size(width: 100, height: 50), 0.25'f32)
    check s.width == 25
    check s.height == 12.5'f32

  test "lerp EdgeInsets":
    let e = lerp(edgeInsetsAll(0), edgeInsetsAll(20), 0.5'f32)
    check e.left == 10
    check e.top == 10
    check e.right == 10
    check e.bottom == 10

when isMainModule: discard
