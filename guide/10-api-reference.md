# 10. API reference

Every exported symbol in flit has a docstring. Run `nim doc` against
the umbrella module to produce HTML for everything.

## Generate the docs

```
nimble docs
```

This runs:

```
nim doc --project --index:on --outdir:docs/api src/flit.nim
```

Output lands in `docs/api/`. Open `docs/api/index.html` in a browser.

## What gets documented

Every `*` exported symbol has a `## ...` doc comment describing:

- Inputs (parameter names, types, defaults)
- Output / return value
- Side effects
- The Flutter analog (when one exists)

The umbrella `src/flit.nim` re-exports every public module so the docs
form a single navigable tree.

## Pages of interest

| Page | Covers |
|------|--------|
| `docs/api/flit.html` | Umbrella; lists every re-exported module |
| `docs/api/widget.html` | `Widget`, `Element`, `State`, `BuildContext` |
| `docs/api/render_object.html` | `RenderObject`, `Canvas`, `PaintingContext` |
| `docs/api/geometry.html` | `Offset`, `Size`, `Rect`, `Constraints`, `EdgeInsets`, `Alignment` |
| `docs/api/color.html` | `Color`, `colorRed` etc., `withOpacity`, `withAlpha` |
| `docs/api/basic.html` | All layout widgets: `Container`, `Row`, `Column`, `Stack`, ... |
| `docs/api/material.html` | Material widgets: `MaterialApp`, `Scaffold`, `AppBar`, buttons |
| `docs/api/cupertino.html` | iOS-styled widgets |
| `docs/api/animation.html` | `AnimationController`, `Tween`, curves |
| `docs/api/listenable.html` | `ValueNotifier`, `ListenableBuilder` |
| `docs/api/lazy_list.html` | `ListView.builder` |
| `docs/api/harfbuzz.html` | HarfBuzz bindings |
| `docs/api/canvas_gpu.html` | `GpuCanvas` |
| `docs/api/canvas_gl.html` | `GlCanvas` |
| `docs/api/glyph_atlas.html` | `GlyphAtlas` |
| `docs/api/raster_pool.html` | `RasterPool` |

## Source-as-documentation

When the HTML docs are not handy, the source itself is heavily
documented. The convention:

- Every type has a `##` block above its definition.
- Every exported proc / method has a `##` block describing inputs and
  effects.
- `src/flit/foundation/widget.nim` is the place to read first; it
  defines the lifecycle and is the contract every other module follows.

Look at `src/flit/widgets/basic.nim` for the canonical pattern for
building a new widget: type definition with docstring, then
`widgetTypeName` / `createElement` / `createRenderObject` /
`updateRenderObject` methods, then a constructor proc.

## Versioning

Public-facing changes bump the version in:

- `flit.nimble` (`version = "X.Y.Z"`)
- `cli/src/flit_cli.nim` (`const flitVersion* = "X.Y.Z"`)
- `CLAUDE.md` (add a `Version history` entry)

Semver:

- MAJOR for breaking API changes
- MINOR for additive features
- PATCH for bug fixes

flit currently follows the rule that public APIs are never broken once
shipped. New features arrive as new symbols (additive). When that rule
is finally broken it will be a 1.0.0 bump with a migration note.

## Finding things

A useful workflow when looking for "where is X defined":

```
grep -rn "X" src/flit/
```

The `src/flit/` tree is small (~5000 lines) so a `grep` finishes
instantly.

For "what calls X":

```
grep -rn "X(" src/flit/ tests/ examples/
```

This catches both definition and use sites; pipe through `grep -v` to
filter out the definition line.

## End of guide

You have read the full guide. From here, browse the examples and the
source. The README at `guide/README.md` is the table of contents if
you want to jump back.
