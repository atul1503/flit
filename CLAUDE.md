# Flit project guide for Claude

A Flutter-inspired UI toolkit for Nim. Single codebase targets macOS, Linux, Windows, iOS, Android, web, and embedded Linux. See `README.md` for the user-facing pitch and `docs/ARCHITECTURE.md` for the design.

## Repo layout

- `src/flit.nim` is the top-level umbrella import (`import flit`).
- `src/flit/foundation/` holds the framework primitives. Touch carefully.
- `src/flit/rendering/` holds RenderObjects.
- `src/flit/widgets/basic.nim` holds the layout widgets (Container, Row, Column, etc.).
- `src/flit/material/` and `src/flit/cupertino/` are design system wrappers.
- `src/flit/platform/{desktop,web,mobile,embedded}/runner.nim` are the per-target event loops.
- `cli/src/flit_cli.nim` is the `flit` command.

## Adding a new widget

1. Decide: is it stateless, stateful, or render-object?
2. For render widgets: define a `RenderXxx` in `rendering/`, then a `Xxx` widget in `widgets/basic.nim` (or in a design module). Override `widgetTypeName`, `createElement`, `createRenderObject`, and `updateRenderObject`.
3. If the widget has children, teach `childrenOf` in `foundation/runtime.nim` how to extract them.
4. If the child needs special parent data (like Flexible's `flex`), extend `attachChildRenders`.

## Versioning

Semver. Bump before publishing user-facing changes. `flitVersion` lives in `cli/src/flit_cli.nim`; `version` lives in `flit.nimble`. Keep them in lockstep. Version history below.

## Version history

- 0.3.0: Flutter-parity API fixes. Container now composes properly (padding > decoration > constrained > padding > align > child); AspectRatio, ClipRect, ClipRRect, Opacity widgets added; State.didUpdateWidget and dispose actually called by reconciliation; key-based reconciliation preserves element identity across reorders; AnimationController.dispose / removeListener / value= setter; layout caching skips performLayout when constraints unchanged and not dirty; canvas-level opacity stack so Opacity attenuates every primitive painted inside it.
- 0.2.0: showcase example. Six-tab demo app that exercises Material+Cupertino in one screen, every MainAxisAlignment, Stack+Positioned, every box decoration (solid/rounded/circle/border/shadow), gestureDetector pan+tap+hold, AnimationController with every built-in curve, theme toggling, and Keys.
- 0.1.0: initial release. Widget framework, layout, painting, Material + Cupertino starter widgets, all five backends (SDL2 desktop, JS web, SDL2 mobile, framebuffer embedded), CLI with create/run/build/doctor/devices/clean/hot/pub-get/upgrade, examples (counter, gallery, todo, calculator), tests.
