## Animation runs end-to-end: ticker schedules frame callbacks, callbacks
## drive the controller, controller's listener gets called with progress.

import std/[unittest, os, times]
import ../src/flit
import ../src/flit/foundation/binding

suite "Animation pump":
  test "forward() fires listener and reaches completion":
    # We need a Binding to schedule frames against.
    let canvas = Canvas(size: Size(width: 100, height: 100))
    let b = newBinding(canvas, Size(width: 100, height: 100))

    var values: seq[float32] = @[]
    var statuses: seq[AnimationStatus] = @[]
    let ctrl = newAnimationController(durationSec = 0.05'f32)
    ctrl.addListener(proc(v: float32) = values.add(v))
    ctrl.addStatusListener(proc(s: AnimationStatus) = statuses.add(s))
    ctrl.forward(b, curveLinear)

    # Manually run the pump. snapshot+clear, then call back, mirroring the
    # runner's animation pump logic.
    let deadline = epochTime() + 0.5
    while ctrl.status != asCompleted and epochTime() < deadline:
      if b.frameCallbacks.len == 0:
        sleep(2)
        continue
      let pending = b.frameCallbacks
      b.frameCallbacks.setLen(0)
      let now = b.currentTime
      for cb in pending:
        cb(now)

    check ctrl.status == asCompleted
    check values.len > 1
    check values[^1] >= 0.99'f32
    check asCompleted in statuses

when isMainModule: discard
