# flit

A Flutter-inspired UI toolkit for Nim. Declarative widgets, real GPU
rendering, single codebase for desktop, mobile, web, and embedded
Linux.

[![ci](https://github.com/atul1503/flit/actions/workflows/ci.yml/badge.svg)](https://github.com/atul1503/flit/actions/workflows/ci.yml)
[![docs](https://img.shields.io/badge/docs-atul1503.github.io%2Fflit-blue)](https://atul1503.github.io/flit/)
[![version](https://img.shields.io/badge/version-0.9.2-orange)](#)
[![license](https://img.shields.io/badge/license-BSD--3--Clause-green)](#license)

## Status

**Pre-1.0.** The framework compiles, the test suite is green
(200+ assertions across 30 test files), the examples run on macOS and
Linux. It is **not** production-tested by any real-world app yet. If
that matters to you, watch the repo and revisit at 1.0.

## Performance vs Flutter

Apples-to-apples benchmark (500-card column, identical workload, same
machine; see [`benchmarks/`](benchmarks/) for the source and full
methodology):

| Path | flit | Flutter |
|------|------|---------|
| Cold (fresh widget tree, full rebuild) | **31 ms** | 76 ms |
| Warm (existing tree, full invalidation) | 29 ms | 7.5 ms* |

\* Flutter test mode builds a layer tree but doesn't rasterize pixels;
flit's 29 ms includes Pixie CPU rasterization. With rasterization
equalized the warm path is roughly comparable.

**flit is ~2.4x faster than Flutter on the cold rebuild path** — the
path every `setState` triggers. Nim's lack of GC pauses, simpler
runtime, and lighter object model translate to real measured wins.

On pure framework cost (subtracting rasterization), Flutter wins the
warm path by ~2x because flit's layout phase is dominated by Pixie's
text measurement. A glyph-extent cache would close that gap.

## Why

Nim is the right language for desktop and embedded UIs that need
small binaries, low memory, and no garbage-collection pauses. It just
didn't have a usable framework for declarative, cross-platform UIs.
flit fills that gap with a familiar API (widgets, state, layout) and
real performance primitives (GPU shaders, layer caching, lazy lists,
HarfBuzz text shaping).

## Hello

```nim
import flit

type
  Counter = ref object of StatefulWidget
  CounterState = ref object of State
    count: int

method widgetTypeName(w: Counter): string = "Counter"
method createElement(w: Counter): Element = newElement(ekStateful, w)
method createState(w: Counter): State = CounterState(count: 0)
method build(s: CounterState, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(title = text("Hello flit")),
    body = center(child = column(mainAxisAlignment = maCenter, children = @[
      Widget(text("You tapped " & $s.count & " times.")),
      elevatedButton(child = text("Tap me"),
        onPressed = proc() = setState(s, proc() = inc s.count))])))

when isMainModule:
  runApp(Counter())
```

Run it:

```
nim c -r hello.nim
```

## Install

```
brew install nim sdl2 harfbuzz                       # macOS
sudo apt install nim libsdl2-dev libharfbuzz-dev    # Debian / Ubuntu

git clone https://github.com/atul1503/flit
cd flit
nimble install
```

`nimble install` puts the `flit` CLI on your path.

```
flit create my_app
cd my_app
flit run
```

## What you get

Core framework:

- Three widget kinds (Stateless, Stateful, RenderObject) and the
  Element + RenderObject + Canvas architecture you know from Flutter
- Constraints-based layout with Row / Column / Stack / Expanded /
  Flexible / Positioned
- Material and Cupertino design system widgets
- Reconciliation with key-based stability across reorders
- State lifecycle (initState, didUpdateWidget, dispose)

Inputs and forms:

- TextField with cursor, selection, focus, IME integration
- FocusNode + FocusManager with Tab traversal
- Form, FormField, and built-in validators (required, minLength, email)
- GestureDetector with tap, double-tap, pan

Navigation and structure:

- Navigator with push, pop, popUntil, pushReplacement
- Directionality for LTR / RTL support
- InheritedWidget for dependency injection

State management:

- setState for local state
- ValueNotifier + ListenableBuilder for shared mutable state
- InheritedWidget + dependOnInheritedOfType for tree-scoped state

Performance:

- RepaintBoundary with GPU texture caching
- GpuCanvas: SDL_Renderer-based hardware draws
- GlCanvas: OpenGL 3.3 SDF shaders for paths
- GlyphAtlas for cached rasterized text
- HarfBuzz bindings for ligatures and kerning
- ListView.builder with fixed and variable item extents
- RasterPool for off-main-thread paint work
- Identity short-circuit in reconciliation

Animations:

- AnimationController with forward, reverse, animateTo, repeat, stop
- Tween for float, int, Color, Offset, Size, EdgeInsets
- Built-in curves: easeIn, easeOut, easeInOut, bounceOut, elasticIn

Images:

- Image widget with PNG / JPEG / BMP / GIF loading via Pixie
- Multiple fit modes: contain, cover, fill, none

Tooling:

- `flit` CLI: create, run, build, doctor, devices, clean, hot, pub get
- Per-target build commands for desktop, web (JS backend), mobile, embedded
- API documentation via `nim doc`

## Platforms

| Platform | Status |
|----------|--------|
| macOS | working, manually tested + CI |
| Linux | CI green; counter and notes run natively |
| Windows | CI green |
| Web (JS) | compiles, output parses cleanly, demo opens in browser |
| iOS | cross-compiles to ARM64 binary; Xcode wrapper still manual |
| Android | cross-compiles to ARM64 `.so`; Android Studio wrapper still manual |
| Embedded Linux | framebuffer backend compiles + runs (see `examples/embedded/`) |

## Documentation

- **Guide:** [guide/](guide/)
- **API reference:** [atul1503.github.io/flit](https://atul1503.github.io/flit/)
- **Examples:** [`examples/`](examples/)

Start with `guide/01-quickstart.md`.

## What's missing

Pre-1.0 means real gaps. The honest list:

- **Battle-testing**: only one demo app (`examples/notes`) so far; no
  production deployment yet
- **Mobile and embedded backends**: implemented but not exercised
  end-to-end
- **Accessibility**: the semantics tree exists, but the OS-side
  bridge (NSAccessibility, AT-SPI, UIAutomation) isn't wired
- **Mouse-drag selection** in TextField (keyboard selection works)
- **HTTP / network**: out of scope; bring your own
- **Drag and drop**: outside scope today
- **Built-in form widgets** like checkbox, radio, slider, dropdown
  (you can compose them today from primitives, but they aren't
  ergonomic one-liners)

PRs welcome on any of these.

## Contributing

```
# Run the test suite
nimble test

# Run the examples
nim c -r examples/showcase/main.nim

# Regenerate API docs
nimble docs
```

CI runs the test suite + builds the examples on macOS and Linux for
every PR. New code should land with tests.

Commit message style: `version: summary` for version bumps,
`area: summary` for everything else. See `git log` for examples.

## License

BSD-3-Clause.
