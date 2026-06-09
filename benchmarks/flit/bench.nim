## flit benchmark: 500 cards in a column, headless paint via the
## embedded canvas (Pixie CPU rasterizer). Measures framework
## overhead + rasterization time per frame.
##
## Run:
##   nim c -d:release --opt:speed -d:flitEmbedded -r benchmarks/flit/bench.nim

import std/[times, monotimes, algorithm, stats, strformat, strutils, os, options]
import pixie except Rect, rect
import ../../src/flit
import ../../src/flit/foundation/runtime
import ../../src/flit/foundation/render_object
import ../../src/flit/platform/embedded/runner as embed
import ../../src/flit/rendering/text as flitText
import ../../src/flit/rendering/[proxy_box, flex, stack, viewport, decoration]

# Install a real font so drawText actually paints glyphs. Without
# this the benchmark would silently skip text rendering, making
# the comparison unfair vs Flutter.
proc installFont() =
  const candidates = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "C:/Windows/Fonts/arial.ttf",
  ]
  var path = ""
  for c in candidates:
    if fileExists(c): path = c; break
  if path.len == 0:
    echo "ERROR: no system font found; text won't render"
    quit(1)
  let font = pixie.readFont(path)
  embed.embeddedFont = font
  flitText.measureText = proc(text: string, style: TextStyle): Size =
    let f = font
    f.size = style.fontSize
    let b = pixie.typeset(f, text).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height))

const
  NumCards = 500
  Width = 400
  Height = 800     # viewport height; cards extend past
  Iterations = 200
  Warmup = 30

type
  Bench = ref object of StatelessWidget
    ## A column of `count` rounded-rect cards each with two text
    ## labels. Mirrors a typical list-of-items screen.
    count: int

method widgetTypeName(w: Bench): string = "Bench"
method createElement(w: Bench): Element = newElement(ekStateless, w)
method build(w: Bench, ctx: BuildContext): Widget =
  var rows: seq[Widget] = @[]
  for i in 0 ..< w.count:
    rows.add(Widget(container(
      margin = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
      padding = edgeInsetsAll(12),
      hasDecoration = true,
      decoration = boxDecoration(color = colorWhite, borderRadius = 8),
      child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                     children = @[
        Widget(text("Item " & $(i + 1),
          style = textStyle(fontSize = 16, color = colorBlack))),
        text("subtitle line " & $(i + 1),
          style = textStyle(fontSize = 12, color = flit.Color(value: 0xFF6E6E6E'u32))),
      ]))))
  container(
    hasColor = true, color = flit.Color(value: 0xFFF5F5F8'u32),
    child = column(crossAxisAlignment = caStretch, mainAxisSize = msMax,
                   children = rows))

proc benchmarkFrameCold(): tuple[layoutNs, paintNs: int64] =
  ## Cold path: fresh widget tree, mount, layout, paint.
  let canvas = embed.newEmbeddedCanvas(Width, Height)
  let root = mountElement(nil, Bench(count: NumCards), 0)

  let tLayoutStart = getMonoTime()
  runLayout(root, tightFor(Width.float32, Height.float32))
  let tLayoutEnd = getMonoTime()

  canvas.clear(0xFFFFFFFF'u32)
  let tPaintStart = getMonoTime()
  runPaint(root, canvas)
  let tPaintEnd = getMonoTime()

  return ((tLayoutEnd - tLayoutStart).inNanoseconds,
          (tPaintEnd - tPaintStart).inNanoseconds)

proc visitRenderChildren(r: RenderObject, fn: proc(c: RenderObject)) =
  ## Walks the direct render children of `r`. We have to switch on
  ## concrete type because there's no generic child accessor (each
  ## render object stores children differently: RenderProxyBox has
  ## `child`, RenderFlex has `children` of `RenderFlexChild`, etc).
  if r.isNil: return
  if r of RenderFlex:
    for c in RenderFlex(r).children: fn(c.obj)
  elif r of RenderStack:
    for c in RenderStack(r).children: fn(c.obj)
  elif r of RenderViewport:
    fn(RenderViewport(r).child)
  elif r of RenderDecoratedBox:
    fn(RenderDecoratedBox(r).child)
  elif r of RenderProxyBox:
    fn(RenderProxyBox(r).child)

proc invalidateSubtree(r: RenderObject) =
  ## Recursively resets layout + paint dirty state on every render
  ## object so the next layout pass does FULL work (no fast-path
  ## short-circuit). This is what Flutter's `markNeedsLayout`
  ## walk effectively does because Flutter's framework propagates
  ## the dirty mark down to relayout boundaries (which, for this
  ## flat tree, means every leaf).
  if r.isNil: return
  r.needsLayout = true
  r.needsPaint = true
  r.sizeOpt = options.none(Size)
  visitRenderChildren(r, invalidateSubtree)

proc benchmarkFrameWarm(root: Element,
                        canvas: embed.EmbeddedCanvas): tuple[layoutNs, paintNs: int64] =
  ## Warm path: existing tree, mark dirty, re-layout, re-paint.
  ## This is the steady-state cost a real app pays per frame
  ## when something has changed.
  let rE = descendantRenderElement(root)
  if not rE.isNil:
    # Full subtree invalidation so layout actually does the work
    # (not the relayout-cached fast path). Matches Flutter's warm
    # bench which marks every render object dirty.
    invalidateSubtree(rE.renderObj)

  let tLayoutStart = getMonoTime()
  runLayout(root, tightFor(Width.float32, Height.float32))
  let tLayoutEnd = getMonoTime()

  canvas.clear(0xFFFFFFFF'u32)
  let tPaintStart = getMonoTime()
  runPaint(root, canvas)
  let tPaintEnd = getMonoTime()

  return ((tLayoutEnd - tLayoutStart).inNanoseconds,
          (tPaintEnd - tPaintStart).inNanoseconds)

proc fmtMs(ns: int64): string =
  &"{(ns.float64 / 1_000_000.0):.3f}ms"

proc report(label: string, samples: seq[int64]) =
  var s = samples
  s.sort()
  var rs: RunningStat
  for v in s: rs.push(v.float64)
  let p50 = s[s.len div 2]
  let p99 = s[max(0, (s.len * 99) div 100 - 1)]
  let pMin = s[0]
  let pMax = s[^1]
  echo &"  {label:>10}  mean={fmtMs(int64(rs.mean()))}  ",
       &"p50={fmtMs(p50)}  p99={fmtMs(p99)}  ",
       &"min={fmtMs(pMin)}  max={fmtMs(pMax)}"

when isMainModule:
  installFont()
  echo "flit benchmark"
  echo "  cards: ", NumCards
  echo "  surface: ", Width, "x", Height
  echo "  iterations: ", Iterations, " (warmup ", Warmup, ")"
  echo ""

  # --- COLD: fresh widget tree every iteration. ---
  for _ in 0 ..< Warmup: discard benchmarkFrameCold()

  var layoutNs = newSeq[int64](Iterations)
  var paintNs  = newSeq[int64](Iterations)
  var totalNs  = newSeq[int64](Iterations)
  for i in 0 ..< Iterations:
    let (l, p) = benchmarkFrameCold()
    layoutNs[i] = l
    paintNs[i]  = p
    totalNs[i]  = l + p
  echo "cold (fresh widget tree per iter):"
  report("layout", layoutNs)
  report("paint",  paintNs)
  report("total",  totalNs)
  echo ""

  # --- WARM: reuse tree, mark all dirty, re-layout + re-paint. ---
  let canvas = embed.newEmbeddedCanvas(Width, Height)
  let root = mountElement(nil, Bench(count: NumCards), 0)
  for _ in 0 ..< Warmup: discard benchmarkFrameWarm(root, canvas)

  for i in 0 ..< Iterations:
    let (l, p) = benchmarkFrameWarm(root, canvas)
    layoutNs[i] = l
    paintNs[i]  = p
    totalNs[i]  = l + p
  echo "warm (existing tree, dirty + repaint):"
  report("layout", layoutNs)
  report("paint",  paintNs)
  report("total",  totalNs)
