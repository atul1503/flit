// Apples-to-apples Flutter benchmark vs flit.
//
// To be a fair comparison we must do the SAME work both frameworks
// do per iteration. flit's bench builds a fresh element tree every
// iteration; this test does the same by calling pumpWidget with a
// UniqueKey so Flutter rebuilds from scratch.
//
// We also measure a warm path: pumpWidget once, then mark dirty and
// re-pump. That measures steady-state, after layout caches are warm.
//
// Run:
//   flutter test test/bench_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/bench_widget.dart';

const int numCards = 500;
const int iterations = 200;
const int warmup = 30;

String fmtMs(int us) => '${(us / 1000.0).toStringAsFixed(3)}ms';

void report(String label, List<int> samplesUs) {
  final sorted = [...samplesUs]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  final p50 = sorted[sorted.length ~/ 2];
  final p99 = sorted[(sorted.length * 99) ~/ 100 - 1];
  final pMin = sorted.first;
  final pMax = sorted.last;
  final padded = label.padLeft(10);
  print('  $padded  mean=${fmtMs(mean.toInt())}  '
        'p50=${fmtMs(p50)}  p99=${fmtMs(p99)}  '
        'min=${fmtMs(pMin)}  max=${fmtMs(pMax)}');
}

void main() {
  testWidgets('cold: fresh widget tree per iteration', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    print('flutter benchmark (cold: fresh tree per iter)');
    print('  cards: $numCards');
    print('  surface: 400x800');
    print('  iterations: $iterations (warmup $warmup)');
    print('');

    final totalUs = <int>[];
    final sw = Stopwatch();

    for (int i = 0; i < warmup + iterations; i++) {
      // Fresh widget each iteration; UniqueKey forces full rebuild
      // of every descendant.
      sw.reset(); sw.start();
      await tester.pumpWidget(
        BenchWidget(count: numCards, key: UniqueKey()),
      );
      sw.stop();
      if (i >= warmup) totalUs.add(sw.elapsedMicroseconds);
    }

    print('results (per frame):');
    report('total', totalUs);
  });

  testWidgets('warm: same widget, mark dirty + repaint', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    print('');
    print('flutter benchmark (warm: existing tree, repaint)');
    print('  cards: $numCards');
    print('  iterations: $iterations (warmup $warmup)');
    print('');

    await tester.pumpWidget(const BenchWidget(count: numCards));

    final layoutUs = <int>[];
    final paintUs = <int>[];
    final totalUs = <int>[];
    final sw = Stopwatch();

    for (int i = 0; i < warmup + iterations; i++) {
      // Mark the entire render tree dirty so we measure full work
      // (not just incremental). Walk the tree and call
      // markNeedsLayout + markNeedsPaint on every render object.
      void markAll(RenderObject ro) {
        ro.markNeedsLayout();
        ro.markNeedsPaint();
        ro.visitChildren(markAll);
      }
      final root = tester.binding.renderViewElement?.renderObject;
      if (root is RenderObject) markAll(root);

      sw.reset(); sw.start();
      tester.binding.pipelineOwner.flushLayout();
      sw.stop();
      final lUs = sw.elapsedMicroseconds;

      sw.reset(); sw.start();
      tester.binding.pipelineOwner.flushCompositingBits();
      tester.binding.pipelineOwner.flushPaint();
      sw.stop();
      final pUs = sw.elapsedMicroseconds;

      if (i >= warmup) {
        layoutUs.add(lUs);
        paintUs.add(pUs);
        totalUs.add(lUs + pUs);
      }
    }

    print('results (per frame):');
    report('layout', layoutUs);
    report('paint',  paintUs);
    report('total',  totalUs);
  });
}
