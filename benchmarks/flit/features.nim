## Per-feature benchmark suite. One scenario per framework feature,
## each timed over repeated layout+paint cycles on the embedded
## canvas with the bundled font (fully deterministic, no SDL).
##
## Run:
##   nim c -d:release --opt:speed -r benchmarks/flit/features.nim
##
## Output: one line per scenario with mean / p50 / p99 in ms.
## Compare against the 16.6ms (60fps) and 6.9ms (144fps) budgets.

import std/[times, monotimes, algorithm, strformat, strutils, os]
import pixie except Rect, rect
import ../../src/flit
import ../../src/flit/foundation/runtime
import ../../src/flit/foundation/binding
import ../../src/flit/foundation/focus
import ../../src/flit/platform/embedded/runner as embed
import ../../src/flit/rendering/text as flitText
import ../../src/flit/rendering/bundled_font
import ../../src/flit/foundation/color as fcol

# Deterministic font.
embed.embeddedFont = bundledFont(14)
flitText.measureText = flitText.wrapMeasureWithCache(
  proc(s: string, style: TextStyle): Size =
    let f = embed.embeddedFont
    f.size = style.fontSize
    let b = pixie.typeset(f, s).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height)))

const W = 800
const H = 600
const Iters = 100
const Warmup = 10

type Sample = object
  name: string
  mean, p50, p99: float

var results: seq[Sample]

proc report(name: string, timings: var seq[float]) =
  timings.sort()
  var total = 0.0
  for t in timings: total += t
  let mean = total / timings.len.float
  let p50 = timings[timings.len div 2]
  let p99 = timings[min(timings.len - 1, timings.len * 99 div 100)]
  results.add(Sample(name: name, mean: mean, p50: p50, p99: p99))
  echo &"  {name:<42} mean={mean:7.3f}ms  p50={p50:7.3f}ms  p99={p99:7.3f}ms"

proc benchPaint(name: string, w: Widget, iters = Iters) =
  ## Times layout+paint of a static tree (warm path: same render
  ## tree, repeated paint).
  let canvas = newEmbeddedCanvas(W, H)
  let root = mountElement(nil, w, 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  for i in 0 ..< Warmup:
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
  var timings: seq[float]
  for i in 0 ..< iters:
    let t0 = getMonoTime()
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report(name, timings)

proc benchMount(name: string, builder: proc(): Widget, iters = Iters) =
  ## Times mount+layout+paint of a FRESH tree each iteration (cold
  ## path: what a navigation push or first build costs).
  let canvas = newEmbeddedCanvas(W, H)
  for i in 0 ..< Warmup:
    let root = mountElement(nil, builder(), 0)
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
  var timings: seq[float]
  for i in 0 ..< iters:
    let t0 = getMonoTime()
    let root = mountElement(nil, builder(), 0)
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report(name, timings)

# ---- Scenario builders ----

proc manyTexts(n: int): Widget =
  var rows: seq[Widget]
  for i in 0 ..< n:
    rows.add(text("Label number " & $(i mod 25),
      style = textStyle(fontSize = 14, color = colorWhite)))
  column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = rows)

proc manyRRects(n: int): Widget =
  var rows: seq[Widget]
  for i in 0 ..< n:
    rows.add(container(width = 120, height = 4,
      margin = edgeInsetsAll(1),
      hasDecoration = true,
      decoration = boxDecoration(
        color = fcol.rgb(uint8(i mod 256), 100'u8, 150'u8), borderRadius = 2)))
  column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = rows)

proc manyIcons(n: int): Widget =
  var cells: seq[Widget]
  let names = ["star", "heart", "cart", "search", "check", "plus"]
  for i in 0 ..< n:
    cells.add(icon(names[i mod names.len], size = 16, color = colorYellow))
  gridView(children = cells, crossAxisCount = 20,
           crossAxisSpacing = 2, mainAxisSpacing = 2)

proc deepNesting(depth: int): Widget =
  result = text("leaf", style = textStyle(fontSize = 12, color = colorWhite))
  for i in 0 ..< depth:
    result = container(padding = edgeInsetsAll(1), child = result)

proc cardList(n: int): Widget =
  var rows: seq[Widget]
  for i in 0 ..< n:
    rows.add(container(
      margin = edgeInsetsSymmetric(horizontal = 8, vertical = 3),
      padding = edgeInsetsAll(10),
      hasDecoration = true,
      decoration = boxDecoration(color = fcol.rgb(40, 40, 48), borderRadius = 8),
      child = row(crossAxisAlignment = caCenter, children = @[
        Widget(container(width = 32, height = 32,
          hasDecoration = true,
          decoration = boxDecoration(color = colorBlue, borderRadius = 16))),
        sizedBox(width = 8),
        expanded(child = column(crossAxisAlignment = caStart,
                                mainAxisSize = msMin, children = @[
          Widget(text("Card title " & $(i mod 10),
            style = textStyle(fontSize = 14, color = colorWhite))),
          text("subtitle line",
            style = textStyle(fontSize = 11, color = fcol.rgb(150, 150, 160))),
        ])),
        icon("chevron.right", size = 14, color = fcol.rgb(120, 120, 130)),
      ])))
  column(crossAxisAlignment = caStretch, mainAxisSize = msMin, children = rows)

proc boundaryCards(n: int): Widget =
  var rows: seq[Widget]
  for i in 0 ..< n:
    rows.add(repaintBoundary(child = container(
      margin = edgeInsetsSymmetric(horizontal = 8, vertical = 3),
      padding = edgeInsetsAll(10),
      hasDecoration = true,
      decoration = boxDecoration(color = fcol.rgb(40, 40, 48), borderRadius = 8),
      child = text("Boundary card " & $(i mod 10),
        style = textStyle(fontSize = 14, color = colorWhite)))))
  column(crossAxisAlignment = caStretch, mainAxisSize = msMin, children = rows)

# Counter-style stateful widget for the setState benchmark.
# Methods must be top-level, so it lives here.
type
  Bump = ref object of StatefulWidget
  BumpState = ref object of State
    n: int

method widgetTypeName(w: Bump): string = "Bump"
method createElement(w: Bump): Element = newElement(ekStateful, w)
method createState(w: Bump): State = BumpState()
method build(s: BumpState, ctx: BuildContext): Widget =
  column(mainAxisSize = msMin, children = @[
    Widget(text("count " & $s.n,
      style = textStyle(fontSize = 20, color = colorWhite))),
    cardList(30),
  ])

# ---- Run everything ----

echo "flit feature benchmarks (", W, "x", H, ", ", Iters, " iters)"
echo ""
echo "Paint-heavy primitives (warm: repeated layout+paint):"
benchPaint("text x200 (cached bitmaps)", manyTexts(200))
benchPaint("rounded rects x200 (cached bitmaps)", manyRRects(200))
benchPaint("icons x200 (fillPolygon)", manyIcons(200))
benchPaint("card list x100 (mixed primitives)", cardList(100))
benchPaint("card list x100 in repaint boundaries", boundaryCards(100))

echo ""
echo "Layout stress:"
benchPaint("deep nesting x200 levels", deepNesting(200))
benchPaint("gridView 300 cells / 10 cols",
  gridView(children = (proc(): seq[Widget] =
    for i in 0 ..< 300:
      result.add(container(width = 60, height = 30,
        hasColor = true, color = colorTeal)))(),
    crossAxisCount = 10))

echo ""
echo "Cold mount (fresh tree per iteration):"
benchMount("mount card list x100", proc(): Widget = cardList(100))
benchMount("mount text x200", proc(): Widget = manyTexts(200))

echo ""
echo "Scrolling (paint with cull rect active):"
block:
  let canvas = newEmbeddedCanvas(W, H)
  let sc = newScrollController()
  let root = mountElement(nil,
    scrollView(controller = sc, child = cardList(500)), 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  for i in 0 ..< Warmup:
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
  var timings: seq[float]
  for i in 0 ..< Iters:
    sc.jumpTo(float32(i mod 100) * 30.0'f32)   # scrub through content
    let t0 = getMonoTime()
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report("scroll frame, 500-card scrollView", timings)

echo ""
echo "Images:"
block:
  # Large source: downscale-cache path. First paint includes the
  # one-time resize; steady state blits the small copy.
  let big = pixie.newImage(3000, 2000)
  big.fill(pixie.rgba(90, 120, 200, 255))
  let tmp = getTempDir() / "flit_bench_big.png"
  big.writeFile(tmp)
  let canvas = newEmbeddedCanvas(W, H)
  let root = mountElement(nil,
    image(tmp, width = 240, height = 180, fit = ifCover), 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  var first: seq[float]
  let t0 = getMonoTime()
  canvas.clear(0xFF101010'u32)
  runPaint(root, canvas)
  first.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report("6MP image first paint (one-time resize)", first)
  var timings: seq[float]
  for i in 0 ..< Iters:
    let t1 = getMonoTime()
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t1)) / 1e6)
  report("6MP image steady paint (cached downscale)", timings)
  removeFile(tmp)

echo ""
echo "Interaction (full frame cycles through the real input path):"
block:
  # TextField keystroke: focus + key event + dirty drain + paint.
  let canvas = newEmbeddedCanvas(W, H)
  let b = newBinding(canvas, Size(width: float32(W), height: float32(H)))
  let root = mountElement(nil,
    container(padding = edgeInsetsAll(20),
      child = container(height = 40,
        hasColor = true, color = colorWhite,
        child = textField(initialValue = "",
          style = textStyle(fontSize = 14, color = colorBlack)))), 0)
  b.rootElement = root
  runLayout(root, tightFor(float32(W), float32(H)))
  runPaint(root, canvas)
  let fm = focusManager()
  fm.focus(fm.nodes[^1])
  proc pump() =
    if b.dirtyRoots.len > 0:
      let snap = b.dirtyRoots
      b.dirtyRoots.setLen(0)
      for r in snap: rebuildElement(r)
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
  pump()
  var timings: seq[float]
  for i in 0 ..< Iters:
    let t0 = getMonoTime()
    discard fm.handleKeyEvent(KeyEvent(kind: keDown, text: $chr(97 + i mod 26)))
    pump()
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report("TextField keystroke (event->rebuild->paint)", timings)

block:
  # setState rebuild cycle on a counter-style app. (Bump type +
  # methods live at top level, above; methods can't nest in blocks.)
  let canvas = newEmbeddedCanvas(W, H)
  let b = newBinding(canvas, Size(width: float32(W), height: float32(H)))
  let root = mountElement(nil, Bump(), 0)
  b.rootElement = root
  runLayout(root, tightFor(float32(W), float32(H)))
  runPaint(root, canvas)
  # Find the state to drive setState.
  var st: BumpState
  proc findState(e: Element) =
    if e.isNil: return
    if not e.state.isNil and e.state of BumpState:
      st = BumpState(e.state)
    for c in e.children: findState(c)
  findState(root)
  doAssert not st.isNil
  var timings: seq[float]
  for i in 0 ..< Iters:
    let t0 = getMonoTime()
    setState(st, proc() = inc st.n)
    if b.dirtyRoots.len > 0:
      let snap = b.dirtyRoots
      b.dirtyRoots.setLen(0)
      for r in snap: rebuildElement(r)
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report("setState rebuild (30-card subtree)", timings)

echo ""
echo "Animation (transform paint per frame):"
block:
  let canvas = newEmbeddedCanvas(W, H)
  let root = mountElement(nil,
    column(mainAxisSize = msMin, children = (proc(): seq[Widget] =
      for i in 0 ..< 30:
        result.add(transform(
          rotation = float32(i) * 0.1'f32,
          scale = 0.8'f32 + float32(i mod 5) * 0.05'f32,
          child = container(width = 100, height = 14,
            hasDecoration = true,
            decoration = boxDecoration(color = colorPurple, borderRadius = 4),
            child = text("spin", style = textStyle(fontSize = 10,
              color = colorWhite))))))()), 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  for i in 0 ..< Warmup:
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
  var timings: seq[float]
  for i in 0 ..< Iters:
    let t0 = getMonoTime()
    canvas.clear(0xFF101010'u32)
    runPaint(root, canvas)
    timings.add(float(inNanoseconds(getMonoTime() - t0)) / 1e6)
  report("30 transformed (rotate+scale) widgets", timings)

echo ""
echo "Summary (sorted by mean):"
results.sort(proc(a, b: Sample): int = cmp(b.mean, a.mean))
for r in results:
  let budget =
    if r.mean <= 6.9: "OK 144fps"
    elif r.mean <= 16.6: "OK 60fps"
    else: "OVER BUDGET"
  echo &"  {r.name:<42} {r.mean:7.3f}ms  [{budget}]"
