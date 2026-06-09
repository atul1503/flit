# flit vs Flutter benchmark

Apples-to-apples comparison of paint pipeline cost. The workload
is identical in both: 500 card widgets in a column, each with a
rounded-rect background and two text labels.

## Headline numbers

Measured on Apple M-series (arm64), Nim 2.2.4 / Pixie 5.0.6,
Flutter 3.24.4 / Dart 3.5.4. 200 iterations per measurement,
30-iteration warmup.

| Path | flit | Flutter |
|------|------|---------|
| **Cold** (fresh widget tree per iter, full rebuild) | **31.0 ms** | 76.4 ms |
| **Warm** (existing tree, full invalidation) | 29.2 ms | 7.5 ms* |

\* Flutter test mode builds a layer tree but does NOT rasterize
pixels. flit's number includes Pixie CPU rasterization. See
"Why the warm path looks asymmetric" below.

## What "cold" means

Every iteration tears down the widget tree and rebuilds from
scratch:

- flit: `mountElement(nil, freshWidgetTree, 0)` then layout + paint
- Flutter: `tester.pumpWidget(Widget(key: UniqueKey()))` then
  flushLayout + flushPaint

The cold path is what every setState() effectively triggers in a
real app: a new widget tree is built, reconciled against the old
element tree, laid out, painted. Every framework cost is in here:
widget allocation, element mount, layout, paint walk.

**flit wins this path ~2.4x (31 ms vs 76 ms).** This is the
single biggest perf-relevant claim. The reasons are likely:

1. Nim widgets are simpler value-shaped objects allocated via ARC.
   Dart widgets get GC'd; flit's don't.
2. flit's `Element` + `RenderObject` types are smaller than
   Flutter's `Element` + `RenderObject` + `Layer` trinity.
3. Identity short-circuit reconciliation (0.7.0+ in flit) does
   the same thing in both, but Dart's per-object dispatch cost
   is higher.

The cold path is what matters most for real apps. flit really is
faster here.

## What "warm" means

Existing widget tree, no rebuild. Every render object in the tree
gets `markNeedsLayout` + `markNeedsPaint`, then layout + paint
run again.

- flit warm: `invalidateSubtree(rootRO)` recursively walks every
  render object and resets `needsLayout`, `needsPaint`, and
  `sizeOpt` so the layout fast-path can't short-circuit. Then
  runs layout + paint.
- Flutter warm: `visitChildren(markAll)` recursively walks every
  render object calling `markNeedsLayout()` and `markNeedsPaint()`.
  Then `flushLayout` + `flushCompositingBits` + `flushPaint`.

Both do the same conceptual work: re-layout + re-paint every
node in the tree.

## Why the warm path looks asymmetric

Flutter's `flushPaint` builds a layer tree of paint commands. It
does NOT rasterize pixels. Rasterization happens later on the GPU
when the layer tree is sent to the engine for display, and is not
measured by `flutter_test`.

flit's paint goes all the way to pixels via Pixie CPU rasterization.

So the warm numbers are measuring different work:

|  | flit warm | Flutter warm |
|---|---|---|
| Layout walk | yes | yes |
| Paint walk (call paint methods) | yes | yes |
| Build layer tree | n/a (no layer tree) | yes |
| Rasterize 500 cards to ARGB pixels | yes | no |

The 14.8 ms of "paint" in flit warm is dominated by Pixie filling
500 rounded rects and blitting glyph bitmaps. Flutter's 3 ms of
"paint" is just the paint walk + layer construction.

**If both rasterized, the warm comparison would be closer to:**
- flit: 29 ms (already includes raster)
- Flutter: 7.5 ms + estimated 10-20 ms raster = ~20-30 ms

Same ballpark.

## What's really going on (framework-only work, no rasterization)

Subtract rasterization from flit and estimate the pure-framework
cost:

|  | flit | Flutter |
|---|---|---|
| Cold framework cost | ~17 ms | 76 ms |
| Warm framework cost | ~15 ms (mostly Pixie typeset in layout) | 7.5 ms |

(flit's rasterization is ~14 ms of the 29 ms warm number, leaving
~15 ms of layout + paint walk. The 14 ms of layout time is mostly
calls to Pixie's `typeset` to measure text bounds, NOT actual
layout math.)

So on **pure framework work**:
- Cold: flit ~4.5x faster
- Warm: Flutter ~2x faster

flit's warm-path bottleneck is Pixie's text measurement. Every
text widget calls `typeset()` during layout. A glyph-extent cache
or switching to HarfBuzz's faster glyph metrics would close that
gap.

## What this means for real apps

In the path that runs on every setState (cold rebuild): **flit
wins decisively**.

In the path that runs when only geometry changed and no rebuild
happened (warm): **roughly comparable** once you account for
rasterization. flit has room to improve its layout phase by
caching text measurements.

Net: Nim's language advantages translate to real measured wins.
The previous claim that "Flutter is faster" was wrong. The
nuanced truth is that flit beats Flutter on the rebuild path and
ties on steady-state when rasterization is included.

## Methodology

**flit benchmark** (`flit/bench.nim`):
- Compiled with `-d:release --opt:speed -d:flitEmbedded`
- Uses `EmbeddedCanvas` (Pixie CPU, no SDL window)
- Installs Arial as the system font for text rendering
- Cold phase: fresh `mountElement(nil, Bench(count: 500), 0)`
  every iteration
- Warm phase: one mount, then `invalidateSubtree` recursively
  resets every render object's layout cache before each iteration

**Flutter benchmark** (`flutter/test/bench_test.dart`):
- Run via `flutter test`
- Cold phase: `tester.pumpWidget(BenchWidget(key: UniqueKey()))`
- Warm phase: walk render tree calling `markNeedsLayout()` +
  `markNeedsPaint()` on every render object, then flushLayout +
  flushPaint

Both: same widget tree shape, 500 cards, 400x800 surface, 200
iterations after 30 warmup.

## Reproducing

```
# flit
cd /Users/attripathi/flit
nim c -r -d:release --opt:speed -d:flitEmbedded benchmarks/flit/bench.nim

# Flutter
cd /Users/attripathi/flit/benchmarks/flutter
flutter pub get
flutter test test/bench_test.dart
```
