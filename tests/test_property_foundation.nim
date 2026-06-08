## Property tests for the foundation types: throws thousands of random
## inputs at Constraints, Color, Alignment, EdgeInsets and asserts the
## documented invariants hold. Any failure here is a real API bug.

import std/[unittest, random, math]
import ../src/flit

const TRIALS = 2000

proc randF(rng: var Rand, lo, hi: float32): float32 =
  lo + rng.rand(1.0) * (hi - lo)

proc randConstraints(rng: var Rand, maxV = 1000.0'f32): Constraints =
  let minW = randF(rng, 0, maxV)
  let maxW = minW + randF(rng, 0, maxV)
  let minH = randF(rng, 0, maxV)
  let maxH = minH + randF(rng, 0, maxV)
  constraints(minW, maxW, minH, maxH)

proc randSize(rng: var Rand, maxV = 2000.0'f32): Size =
  Size(width: randF(rng, -100, maxV), height: randF(rng, -100, maxV))

proc randInsets(rng: var Rand, maxV = 200.0'f32): EdgeInsets =
  edgeInsetsLTRB(randF(rng, 0, maxV), randF(rng, 0, maxV),
                 randF(rng, 0, maxV), randF(rng, 0, maxV))

suite "Constraints.constrain":
  test "result is always within [min, max]":
    var rng = initRand(42)
    for _ in 0 ..< TRIALS:
      let c = randConstraints(rng)
      let s = randSize(rng)
      let r = c.constrain(s)
      check r.width  >= c.minWidth  - 0.001
      check r.width  <= c.maxWidth  + 0.001
      check r.height >= c.minHeight - 0.001
      check r.height <= c.maxHeight + 0.001

  test "constrain is idempotent":
    var rng = initRand(7)
    for _ in 0 ..< TRIALS:
      let c = randConstraints(rng)
      let s = randSize(rng)
      let r1 = c.constrain(s)
      let r2 = c.constrain(r1)
      check r1 == r2

suite "Constraints.enforce":
  test "result fits inside parent constraints":
    var rng = initRand(13)
    for _ in 0 ..< TRIALS:
      let p = randConstraints(rng)
      let c = randConstraints(rng)
      let e = c.enforce(p)
      check e.minWidth  >= p.minWidth  - 0.001
      check e.maxWidth  <= p.maxWidth  + 0.001
      check e.minHeight >= p.minHeight - 0.001
      check e.maxHeight <= p.maxHeight + 0.001

suite "Constraints.deflate":
  test "deflated max never exceeds original max":
    var rng = initRand(99)
    for _ in 0 ..< TRIALS:
      let c = randConstraints(rng)
      let e = randInsets(rng)
      let d = c.deflate(e)
      check d.maxWidth  <= c.maxWidth  + 0.001
      check d.maxHeight <= c.maxHeight + 0.001
      check d.minWidth  >= 0
      check d.minHeight >= 0
      check d.minWidth  <= d.maxWidth  + 0.001
      check d.minHeight <= d.maxHeight + 0.001

  test "deflate(zero insets) preserves constraints":
    var rng = initRand(5)
    for _ in 0 ..< TRIALS:
      let c = randConstraints(rng)
      let d = c.deflate(edgeInsetsAll(0))
      check d == c

suite "Constraints.tightFor / loosen":
  test "tightFor produces equal min and max":
    var rng = initRand(3)
    for _ in 0 ..< TRIALS:
      let w = rng.rand(1000.0).float32
      let h = rng.rand(1000.0).float32
      let t = tightFor(w, h)
      check t.minWidth  == t.maxWidth
      check t.minHeight == t.maxHeight
      check t.minWidth  == w
      check t.minHeight == h
      check t.isTight

  test "loosen zeroes min":
    var rng = initRand(11)
    for _ in 0 ..< TRIALS:
      let c = randConstraints(rng)
      let l = c.loosen()
      check l.minWidth  == 0
      check l.minHeight == 0
      check l.maxWidth  == c.maxWidth
      check l.maxHeight == c.maxHeight

suite "Color.lerp":
  test "endpoints are reached exactly":
    var rng = initRand(2)
    for _ in 0 ..< TRIALS:
      let a = rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                   uint8(rng.rand(255)), uint8(rng.rand(255)))
      let b = rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                   uint8(rng.rand(255)), uint8(rng.rand(255)))
      check lerp(a, b, 0.0'f32) == a
      check lerp(a, b, 1.0'f32) == b

  test "channels stay in [0, 255]":
    var rng = initRand(8)
    for _ in 0 ..< TRIALS:
      let a = rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                   uint8(rng.rand(255)), uint8(rng.rand(255)))
      let b = rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                   uint8(rng.rand(255)), uint8(rng.rand(255)))
      let t = randF(rng, -1, 2)   # include out-of-range t
      let c = lerp(a, b, t)
      check c.red.int   in 0..255
      check c.green.int in 0..255
      check c.blue.int  in 0..255
      check c.alpha.int in 0..255

suite "Color.withOpacity":
  test "opacity is clamped to [0, 1]":
    var rng = initRand(14)
    for _ in 0 ..< TRIALS:
      let c = rgba(uint8(rng.rand(255)), uint8(rng.rand(255)),
                   uint8(rng.rand(255)), 255)
      let o = randF(rng, -2, 3)
      let r = c.withOpacity(o)
      check r.alpha.int in 0..255

  test "0 opacity gives alpha 0; 1.0 gives alpha 255 (Flutter replaces)":
    var rng = initRand(21)
    for _ in 0 ..< TRIALS:
      let alpha = uint8(rng.rand(255))
      let c = rgba(0, 0, 0, alpha)
      check c.withOpacity(0.0'f32).alpha == 0
      check c.withOpacity(1.0'f32).alpha == 255

suite "Alignment.resolveOffset":
  test "alignCenter on equal-size child returns zero":
    var rng = initRand(31)
    for _ in 0 ..< TRIALS:
      let w = randF(rng, 0, 1000)
      let h = randF(rng, 0, 1000)
      let s = Size(width: w, height: h)
      let o = alignCenter.resolveOffset(s, s)
      check abs(o.dx) < 0.001
      check abs(o.dy) < 0.001

  test "alignTopLeft always returns origin":
    var rng = initRand(33)
    for _ in 0 ..< TRIALS:
      let parent = Size(width: randF(rng, 0, 1000), height: randF(rng, 0, 1000))
      let child  = Size(width: randF(rng, 0, parent.width.max(1)),
                        height: randF(rng, 0, parent.height.max(1)))
      let o = alignTopLeft.resolveOffset(parent, child)
      check abs(o.dx) < 0.001
      check abs(o.dy) < 0.001

  test "alignBottomRight places child at parent.size - child.size":
    var rng = initRand(35)
    for _ in 0 ..< TRIALS:
      let parent = Size(width: randF(rng, 100, 1000), height: randF(rng, 100, 1000))
      let child  = Size(width: randF(rng, 0, parent.width),
                        height: randF(rng, 0, parent.height))
      let o = alignBottomRight.resolveOffset(parent, child)
      check abs(o.dx - (parent.width  - child.width))  < 0.01
      check abs(o.dy - (parent.height - child.height)) < 0.01

suite "EdgeInsets":
  test "horizontal == left + right":
    var rng = initRand(41)
    for _ in 0 ..< TRIALS:
      let e = randInsets(rng)
      check abs(e.horizontal - (e.left + e.right)) < 0.001
      check abs(e.vertical   - (e.top  + e.bottom)) < 0.001

  test "deflateSize never produces negative":
    var rng = initRand(43)
    for _ in 0 ..< TRIALS:
      let e = randInsets(rng, 500)
      let s = Size(width: randF(rng, 0, 200), height: randF(rng, 0, 200))
      let d = e.deflateSize(s)
      check d.width  >= 0
      check d.height >= 0

  test "all/symmetric/only/LTRB constructors compose consistently":
    var rng = initRand(45)
    for _ in 0 ..< TRIALS:
      let v = randF(rng, 0, 100)
      check edgeInsetsAll(v) == edgeInsetsLTRB(v, v, v, v)
      let h = randF(rng, 0, 100)
      check edgeInsetsSymmetric(horizontal = h, vertical = v) ==
            edgeInsetsLTRB(h, v, h, v)
      check edgeInsetsOnly(top = v) == edgeInsetsLTRB(0, v, 0, 0)

suite "Geometry interpolation":
  test "lerp Offset is component-wise":
    var rng = initRand(51)
    for _ in 0 ..< TRIALS:
      let a = Offset(dx: randF(rng, -100, 100), dy: randF(rng, -100, 100))
      let b = Offset(dx: randF(rng, -100, 100), dy: randF(rng, -100, 100))
      let t = rng.rand(1.0).float32
      let l = lerp(a, b, t)
      check abs(l.dx - (a.dx + (b.dx - a.dx) * t)) < 0.001
      check abs(l.dy - (a.dy + (b.dy - a.dy) * t)) < 0.001

  test "lerp Size at t=0.5 averages":
    var rng = initRand(53)
    for _ in 0 ..< TRIALS:
      let a = Size(width: randF(rng, 0, 200), height: randF(rng, 0, 200))
      let b = Size(width: randF(rng, 0, 200), height: randF(rng, 0, 200))
      let l = lerp(a, b, 0.5'f32)
      check abs(l.width  - (a.width  + b.width)  / 2) < 0.001
      check abs(l.height - (a.height + b.height) / 2) < 0.001

when isMainModule: discard
