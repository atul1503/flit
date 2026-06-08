## Coverage for widgets/render objects that didn't have dedicated tests:
## AspectRatio, ClipRect, ClipRRect, ConstrainedBox, Flexible (loose vs
## tight), additional AnimationController operations (animateTo, repeat
## with reverse, reverse, stop).

import std/[unittest, math, os, times]
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../src/flit/foundation/binding
import ../src/flit/rendering/proxy_box

suite "AspectRatio":
  test "picks largest fitting box at ratio when bounded by width":
    # Parent gives 200x500; aspect 2.0 (w/h) -> 200 wide, 100 tall.
    let r = RenderAspectRatio(aspectRatio: 2.0'f32)
    r.layout(constraints(0, 200, 0, 500))
    check abs(r.size.width  - 200) < 0.01
    check abs(r.size.height - 100) < 0.01

  test "picks largest fitting box at ratio when bounded by height":
    # Parent gives 500x100; aspect 2.0 -> 200 wide, 100 tall.
    let r = RenderAspectRatio(aspectRatio: 2.0'f32)
    r.layout(constraints(0, 500, 0, 100))
    check abs(r.size.width  - 200) < 0.01
    check abs(r.size.height - 100) < 0.01

  test "square (ratio 1.0)":
    let r = RenderAspectRatio(aspectRatio: 1.0'f32)
    r.layout(constraints(0, 300, 0, 300))
    check r.size.width == r.size.height

suite "ConstrainedBox":
  test "tightens to additionalConstraints when parent allows":
    let cb = RenderConstrainedBox(additionalConstraints: tightFor(80, 40))
    cb.layout(constraints(0, 200, 0, 200))
    check cb.size.width == 80
    check cb.size.height == 40

  test "parent's tight constraints override additional":
    let cb = RenderConstrainedBox(additionalConstraints: tightFor(80, 40))
    cb.layout(tightFor(300, 200))
    # Flutter behavior: parent's tight wins.
    check cb.size.width == 300
    check cb.size.height == 200

suite "Flexible fit":
  test "ffLoose lets child be smaller than allocated extent":
    proc kid(w: float32, flex: int, fit: FlexFit): RenderFlexChild =
      RenderFlexChild(
        obj: RenderSizedBox(requestedWidth: w, requestedHeight: 10),
        pd: FlexParentData(flex: flex, fit: fit))
    let r = RenderFlex(direction: axHorizontal, mainAxisSize: msMax,
                       mainAxisAlignment: maStart,
                       crossAxisAlignment: caCenter)
    # 400 wide; one flex=1 ffLoose child requesting only 50px.
    r.children = @[kid(50, 1, ffLoose)]
    r.layout(tightFor(400, 30))
    check r.children[0].obj.size.width == 50   # loose, took its natural size

  test "ffTight forces child to the allocated extent":
    proc kid(w: float32, flex: int, fit: FlexFit): RenderFlexChild =
      RenderFlexChild(
        obj: RenderSizedBox(requestedWidth: w, requestedHeight: 10),
        pd: FlexParentData(flex: flex, fit: fit))
    let r = RenderFlex(direction: axHorizontal, mainAxisSize: msMax,
                       mainAxisAlignment: maStart,
                       crossAxisAlignment: caCenter)
    r.children = @[kid(50, 1, ffTight)]
    r.layout(tightFor(400, 30))
    check r.children[0].obj.size.width == 400  # forced to allocated extent

type
  SaveRec = ref object of Canvas
    saves*: int
    restores*: int

proc newSaveRec(): SaveRec =
  SaveRec(saves: 0, restores: 0, size: Size(width: 100, height: 100))

method save*(c: SaveRec) = inc c.saves
method restore*(c: SaveRec) = inc c.restores
method clipRect*(c: SaveRec, r: Rect) = discard
method drawRect*(c: SaveRec, r: Rect, fill: uint32) = discard

suite "ClipRect / ClipRRect saves & restores canvas state":
  test "RenderClipRect wraps child paint with save/restore":
    let clip = RenderClipRect()
    clip.child = RenderColoredBox(fill: colorRed)
    clip.layout(tightFor(50, 50))
    let rec = newSaveRec()
    let ctx = newPaintingContext(rec)
    clip.paint(ctx, OffsetZero)
    check rec.saves == 1
    check rec.restores == 1

  test "RenderClipRRect also save/restores":
    let clip = RenderClipRRect(radius: 8)
    clip.child = RenderColoredBox(fill: colorBlue)
    clip.layout(tightFor(50, 50))
    let rec = newSaveRec()
    let ctx = newPaintingContext(rec)
    clip.paint(ctx, OffsetZero)
    check rec.saves == 1
    check rec.restores == 1

suite "AnimationController extra operations":
  test "reverse from value back to lower":
    let canvas = Canvas(size: Size(width: 100, height: 100))
    let b = newBinding(canvas, Size(width: 100, height: 100))
    let ctrl = newAnimationController(durationSec = 0.05'f32)
    ctrl.value = 1.0
    ctrl.reverse(b)
    let deadline = epochTime() + 0.5
    while ctrl.status != asDismissed and epochTime() < deadline:
      if b.frameCallbacks.len == 0:
        sleep(2)
        continue
      let pending = b.frameCallbacks
      b.frameCallbacks.setLen(0)
      let now = b.currentTime
      for cb in pending: cb(now)
    check ctrl.status == asDismissed
    check ctrl.value < 0.05

  test "animateTo arrives at target":
    let canvas = Canvas(size: Size(width: 100, height: 100))
    let b = newBinding(canvas, Size(width: 100, height: 100))
    let ctrl = newAnimationController(durationSec = 0.05'f32)
    ctrl.animateTo(b, 0.7'f32)
    let deadline = epochTime() + 0.5
    while ctrl.status notin {asCompleted, asDismissed} and epochTime() < deadline:
      if b.frameCallbacks.len == 0:
        sleep(2)
        continue
      let pending = b.frameCallbacks
      b.frameCallbacks.setLen(0)
      for cb in pending: cb(b.currentTime)
    check abs(ctrl.value - 0.7'f32) < 0.05

  test "stop halts mid-animation":
    let canvas = Canvas(size: Size(width: 100, height: 100))
    let b = newBinding(canvas, Size(width: 100, height: 100))
    let ctrl = newAnimationController(durationSec = 1.0'f32)
    ctrl.forward(b)
    # Pump one frame so we have a non-zero value.
    let pending = b.frameCallbacks
    b.frameCallbacks.setLen(0)
    for cb in pending: cb(b.currentTime + 0.1)
    ctrl.stop()
    let mid = ctrl.value
    sleep(20)
    # After stop the ticker should no longer fire callbacks (its active=false).
    # We can verify by checking that pumping again doesn't change value.
    let p2 = b.frameCallbacks
    b.frameCallbacks.setLen(0)
    for cb in p2: cb(b.currentTime + 0.5)
    check ctrl.value == mid

suite "Tween":
  test "Tween[float32] from -10 to 10 at t=0.5 yields 0":
    let c = newAnimationController(durationSec = 1.0'f32, lower = 0, upper = 1)
    c.value = 0.5
    let tw = tween(-10.0'f32, 10.0'f32)
    check abs(evaluate(tw, c)) < 0.01

  test "Tween[int] rounds appropriately":
    let c = newAnimationController(durationSec = 1.0'f32, lower = 0, upper = 1)
    c.value = 0.5
    let tw = tween(0, 100)
    check evaluate(tw, c) == 50

when isMainModule: discard
