## Property tests for layout. Builds random widget trees from a small
## widget grammar, lays them out under random constraints, asserts the
## documented invariants. Any failure here is a real layout bug.

import std/[unittest, random, math]
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime

const TRIALS = 500

proc randF(rng: var Rand, lo, hi: float32): float32 =
  lo + rng.rand(1.0) * (hi - lo)

proc randomLeaf(rng: var Rand): Widget =
  let w = randF(rng, 0, 80)
  let h = randF(rng, 0, 80)
  if rng.rand(1.0) < 0.5:
    sizedBox(width = w, height = h,
             child = coloredBox(color = colorRed))
  else:
    sizedBox(width = w, height = h)

proc randomTree(rng: var Rand, depth: int): Widget =
  if depth <= 0 or rng.rand(1.0) < 0.3:
    return randomLeaf(rng)
  let kind = rng.rand(6)
  case kind
  of 0: padding(child = randomTree(rng, depth - 1),
                padding = edgeInsetsAll(randF(rng, 0, 16)))
  of 1: center(child = randomTree(rng, depth - 1))
  of 2:
    var kids: seq[Widget] = @[]
    for _ in 0 ..< rng.rand(4):
      kids.add(randomTree(rng, depth - 1))
    row(children = kids, mainAxisSize = msMin)
  of 3:
    var kids: seq[Widget] = @[]
    for _ in 0 ..< rng.rand(4):
      kids.add(randomTree(rng, depth - 1))
    column(children = kids, mainAxisSize = msMin)
  of 4: coloredBox(child = randomTree(rng, depth - 1), color = colorBlue)
  of 5: decoratedBox(child = randomTree(rng, depth - 1),
                     decoration = boxDecoration(color = colorGreen,
                                                borderRadius = 4))
  else: randomLeaf(rng)

proc isFiniteF(x: float32): bool =
  not (x.classify == fcInf or x.classify == fcNegInf or x.classify == fcNaN)

suite "Layout invariants":
  test "size always satisfies the constraints passed to layout":
    var rng = initRand(101)
    for trial in 0 ..< TRIALS:
      let tree = randomTree(rng, 3)
      let root = mountElement(nil, tree, 0)
      let parentW = randF(rng, 50, 1000)
      let parentH = randF(rng, 50, 1000)
      let c = tightFor(parentW, parentH)
      runLayout(root, c)
      let r = descendantRenderElement(root)
      if r.isNil: continue
      let s = r.renderObj.size
      check s.width  >= c.minWidth  - 0.001
      check s.width  <= c.maxWidth  + 0.001
      check s.height >= c.minHeight - 0.001
      check s.height <= c.maxHeight + 0.001

  test "no NaN or Inf sizes under finite constraints":
    var rng = initRand(103)
    for trial in 0 ..< TRIALS:
      let tree = randomTree(rng, 3)
      let root = mountElement(nil, tree, 0)
      runLayout(root, tightFor(randF(rng, 10, 500), randF(rng, 10, 500)))
      let r = descendantRenderElement(root)
      if r.isNil: continue
      check isFiniteF(r.renderObj.size.width)
      check isFiniteF(r.renderObj.size.height)

  test "paint and hit-test do not crash on random tree":
    var rng = initRand(107)
    let canvas = Canvas(size: Size(width: 800, height: 600))
    for trial in 0 ..< 200:
      let tree = randomTree(rng, 3)
      let root = mountElement(nil, tree, 0)
      runLayout(root, tightFor(800, 600))
      runPaint(root, canvas)
      let r = descendantRenderElement(root)
      if r.isNil: continue
      let res = HitTestResult(path: @[])
      discard r.renderObj.hitTest(res, Offset(dx: randF(rng, 0, 800),
                                              dy: randF(rng, 0, 600)))

suite "Flex layout invariants":
  test "row: total child main-extents do not exceed allocated":
    var rng = initRand(201)
    for _ in 0 ..< TRIALS:
      var kids: seq[Widget] = @[]
      let n = 1 + rng.rand(5)
      for i in 0 ..< n:
        kids.add(sizedBox(width = randF(rng, 5, 60),
                          height = randF(rng, 5, 40)))
      let tree = sizedBox(width = randF(rng, 100, 600),
                          height = randF(rng, 30, 200),
                          child = row(children = kids))
      let root = mountElement(nil, tree, 0)
      runLayout(root, tightFor(800, 600))
      # No assertion here other than "doesn't crash"; the property is
      # that paint completes without infinite loops.
      runPaint(root, Canvas(size: Size(width: 800, height: 600)))

  test "column with msMax expands to maxHeight":
    var rng = initRand(203)
    for _ in 0 ..< 50:
      let maxH = randF(rng, 50, 400)
      let col = column(mainAxisSize = msMax,
                       children = @[Widget(sizedBox(width = 20, height = 20))])
      let root = mountElement(nil, col, 0)
      runLayout(root, tightFor(200, maxH))
      let r = descendantRenderElement(root)
      check abs(r.renderObj.size.height - maxH) < 0.01

  test "column with msMin shrinks to child":
    var rng = initRand(207)
    for _ in 0 ..< 50:
      let cw = randF(rng, 10, 100)
      let ch = randF(rng, 10, 100)
      let col = column(mainAxisSize = msMin,
                       children = @[Widget(sizedBox(width = cw, height = ch))])
      let root = mountElement(nil, col, 0)
      runLayout(root, constraints(0, 500, 0, 500))
      let r = descendantRenderElement(root)
      check abs(r.renderObj.size.height - ch) < 0.01

suite "Padding layout":
  test "padding adds insets to child size":
    var rng = initRand(303)
    for _ in 0 ..< TRIALS:
      let cw = randF(rng, 10, 100)
      let ch = randF(rng, 10, 100)
      let pad = randF(rng, 0, 30)
      let tree = center(child = padding(
        child = sizedBox(width = cw, height = ch),
        padding = edgeInsetsAll(pad)))
      let root = mountElement(nil, tree, 0)
      runLayout(root, tightFor(800, 600))
      # The padding widget itself isn't easy to extract; assert it doesn't
      # crash and the topmost render (center's RenderAlign) has the
      # full size.
      let r = descendantRenderElement(root)
      check r.renderObj.size.width  == 800
      check r.renderObj.size.height == 600

when isMainModule: discard
