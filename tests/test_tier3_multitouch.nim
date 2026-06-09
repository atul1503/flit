## Multi-touch dispatch.

import std/unittest
import ../src/flit/gestures/multitouch

suite "multitouch":
  test "PinchEvent fields":
    let e = PinchEvent(deltaScale: 0.1, deltaTheta: 0.05,
                      x: 100, y: 200)
    check e.deltaScale == 0.1'f32
    check e.deltaTheta == 0.05'f32
    check e.x == 100'f32
    check e.y == 200'f32

  test "dispatchMultiGesture fans out to registered listeners":
    pinchListeners.setLen(0)
    var got: seq[float32]
    pinchListeners.add(proc(ev: PinchEvent) = got.add(ev.deltaScale))
    pinchListeners.add(proc(ev: PinchEvent) = got.add(ev.deltaScale * 2))
    dispatchMultiGesture(PinchEvent(deltaScale: 0.5))
    check got.len == 2
    check got[0] == 0.5'f32
    check got[1] == 1.0'f32

  test "dispatchMultiGesture with no listeners is a no-op":
    pinchListeners.setLen(0)
    dispatchMultiGesture(PinchEvent(deltaScale: 1.0))
    check pinchListeners.len == 0

  test "listener that throws does not block subsequent listeners":
    pinchListeners.setLen(0)
    var ran: seq[int]
    pinchListeners.add(proc(ev: PinchEvent) =
      ran.add(1)
      raise newException(ValueError, "oops"))
    pinchListeners.add(proc(ev: PinchEvent) = ran.add(2))
    dispatchMultiGesture(PinchEvent(deltaScale: 0.1))
    check ran == @[1, 2]

  test "pinchDetector constructs a widget":
    let w = pinchDetector(child = nil,
                          onPinch = proc(s: float32) = discard)
    check not w.isNil
    check w.widgetTypeName == "PinchDetector"

  test "rotateDetector constructs a widget":
    let w = rotateDetector(child = nil,
                           onRotate = proc(r: float32) = discard)
    check not w.isNil
    check w.widgetTypeName == "RotateDetector"
