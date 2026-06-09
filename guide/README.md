# Flit guide

A Flutter-inspired UI toolkit for Nim. Single codebase, declarative widgets,
real GPU rendering, runs on macOS, Linux, Windows, web, iOS, Android, and
embedded Linux.

This guide is task-oriented: each page tells you what to do for a specific
goal. Read them in order if you are new, or jump straight to the one that
matches your problem.

## Contents

| File | What it covers |
|------|----------------|
| [01-quickstart.md](01-quickstart.md) | Install, your first counter app, `flit run` |
| [02-widgets.md](02-widgets.md) | Widget hierarchy, the three widget kinds, lifecycle, gridView / icon / dropdown / networkImage / repaintBoundary |
| [03-layout.md](03-layout.md) | Constraints, Row / Column / Stack, Container |
| [04-state.md](04-state.md) | setState, ValueNotifier, ListenableBuilder, InheritedWidget |
| [05-gestures.md](05-gestures.md) | Taps, double-taps, pans, scroll wheel |
| [06-animations.md](06-animations.md) | AnimationController, Tween, curves |
| [07-performance.md](07-performance.md) | RepaintBoundary, GpuCanvas, GlCanvas, glyph atlas, lazy lists, HarfBuzz, raster pool, SDL canvas perf caches, diagnostic env vars (FLIT_FRAME_LOG, FLIT_PAINT_PROBE, FLIT_TAP_PROBE, FLIT_TYPE_PROBE, FLIT_SAVE_FRAME, FLIT_INPUT_LOG) |
| [08-cli.md](08-cli.md) | `flit create`, `flit run`, `flit build`, `flit doctor` |
| [09-examples-tour.md](09-examples-tour.md) | Counter, todo, calculator, showcase, notes, amazon |
| [10-api-reference.md](10-api-reference.md) | Generating `nim doc` HTML; where each symbol lives |
| [11-production.md](11-production.md) | TextField clipboard/undo, animated transitions, semantics, what production-ready means |
| [12-platform-builds.md](12-platform-builds.md) | Build commands, artifacts, runtime requirements per platform |

## Conventions in this guide

Every code block is a complete, compilable snippet unless explicitly marked
`partial`. Paste, save, and `nim c -r` to see it run.

When a sample requires a desktop window, the entry point is always
`runApp(WidgetType())`. When a sample is a test fixture (no window), the
entry point is plain Nim and uses `mountElement` + `runLayout` directly.

Paths are absolute from the repo root: `src/flit/...` is the framework,
`examples/...` is the runnable demos, `tests/...` is the test suite.

## Where to ask questions

Issues and discussions: https://github.com/anthropics/claude-code/issues
(this is the Claude Code issue tracker; flit lives in your local
`/Users/attripathi/flit` directory).
