# 07. Performance

flit 0.7.0 has six performance subsystems you can opt into. None are
on by default beyond `SdlCanvas`; you choose them based on what your
app is bound by.

| Subsystem | When to use it | Cost |
|-----------|----------------|------|
| `RepaintBoundary` | Subtrees that paint complex content but rarely change | One GPU texture per boundary |
| `GpuCanvas` | UIs dominated by solid rectangles, lines, images | None |
| `GlCanvas` | UIs with many rounded rects, circles, antialiased shapes | Needs OpenGL 3.3 driver |
| `GlyphAtlas` | Apps with mostly-stable text labels | One texture per unique (text, size, color) |
| `HarfBuzz` | Text needs ligatures, kerning, or non-Latin shaping | Adds libharfbuzz dependency |
| `ListView.builder` | Long lists (10+ items, or thousands) | Tiny |
| `RasterPool` | CPU-heavy paint work you can offload | Worker threads stay alive |
| Identity short-circuit | Always on | None; automatic |

## RepaintBoundary

The biggest single perf lever. Wrap any subtree that paints a lot of
pixels but doesn't change often:

```nim
repaintBoundary(
  child = complexDecorativeBackground)
```

What happens:

1. First paint: the subtree rasterizes into an off-screen sub-canvas.
2. Subsequent paints: the sub-canvas is composited via `SDL_RenderCopy`
   (GPU) without re-rasterizing.
3. Anything inside the boundary that calls `markNeedsPaint` flips the
   boundary's `cacheDirty` flag, so the next paint re-rasterizes once.

Use it around:

- Backgrounds and decorations
- Card lists where each card stays still
- Complex shadows behind animated content
- Stable header / footer bars while the middle scrolls

Don't use it around things that change every frame; the cache will
re-rasterize every frame and you pay the boundary overhead for nothing.

Verifying it works: `tests/test_repaint_boundary.nim` shows the
expected behavior. The `createSubCanvas` count stays at 1 across many
paints with no changes.

## GpuCanvas

Replace `SdlCanvas` with the SDL_Renderer-based GPU canvas:

```nim
# Inside your platform runner (or pass via DesktopWindowConfig later).
let canvas = newGpuCanvas(window, renderer, w, h, fontPath)
```

What it does:

- `drawRect`, `drawLine`, `clear`: direct SDL_Renderer hardware
  primitives. Zero CPU work per draw.
- `drawRRect`, `drawCircle`: rasterizes once with Pixie into a cached
  texture keyed by `(dims, color)`. Subsequent draws are
  `SDL_RenderCopy` (GPU).
- `drawText`: goes through the glyph atlas. First draw of a label
  rasterizes once; subsequent draws are texture blits.

Pick this over `SdlCanvas` when most of your UI is solid colors, lines,
and images. Pick `SdlCanvas` when you need Pixie's anti-aliased paths
for arbitrary primitives every frame.

## GlCanvas

Real GPU path rasterization. Opens an OpenGL 3.3 context, compiles SDF
shaders for rounded rect, circle, line:

```nim
let canvas = newGlCanvas(window, renderer, w, h)
if canvas.isNil:
  # Driver doesn't support GL 3.3 core. Fall back.
  let canvas = newGpuCanvas(window, renderer, w, h, fontPath)
```

What it does:

- Antialiased rounded rect: one shader, one quad per draw. No CPU work,
  no texture cache.
- Antialiased circle: SDF distance shader.
- Stroked line: SDF segment.
- Solid rect, clear: direct GL calls.

Limitations:

- No scale or rotate on the fast path. Wrap rotating subtrees in a
  `repaintBoundary` so they composite via a sub-canvas.
- No text path yet; the GL canvas does not yet integrate the glyph
  atlas. Wrap text-heavy regions in a `repaintBoundary` and they will
  fall back to the parent canvas's text rendering.

Verifying it loads: `tests/test_canvas_gl.nim` exercises the API
surface. The actual context creation is tested by running an example
that calls `newGlCanvas`.

## GlyphAtlas

Cached rasterized text. Built into `GpuCanvas` automatically; standalone
usage:

```nim
let atlas = newGlyphAtlas(renderer, maxEntries = 1024)

# Optional: register a HarfBuzz font for proper shaping.
atlas.registerHbFont(hash("system"), "/path/to/font.ttf")

# Inside paint:
let entry = atlas.getOrRasterize(pixieFont, "Hello",
                                  fontSize = 14.0,
                                  color = 0xFF000000'u32,
                                  fontHash = hash("system"))
# Copy entry.texture onto the renderer at the desired position.
```

Tune `maxEntries` to your app:

- Small dashboard: 256
- Typical desktop app: 512 (default)
- Text-heavy app with many unique strings: 2048

The cache evicts oldest-first when full. For a typical UI with stable
button labels and headings, the working set fits in even 256 entries
and the cache hit rate is 100%.

## HarfBuzz

Proper text shaping with ligatures, kerning, and complex script
support. Requires libharfbuzz installed.

```nim
# Once per font, at startup:
atlas.registerHbFont(hash("system"), "/path/to/Arial.ttf")

# Then drawText through the canvas goes through HarfBuzz for
# measurement. Pixie still does the glyph rasterization.
```

Without HarfBuzz, flit uses Pixie's `typeset`, which handles Latin
scripts but does not produce proper ligatures or kerning.

Check at runtime:

```nim
import flit/rendering/harfbuzz
if isHarfBuzzAvailable():
  echo "HarfBuzz loaded"
else:
  echo "HarfBuzz missing; falling back to Pixie typeset"
```

Install: `brew install harfbuzz` (macOS) or `apt install libharfbuzz-dev`
(Debian).

## ListView.builder

Lazy lists. Use this for any list with more than a few dozen items:

```nim
listViewBuilder(
  itemCount = 10_000,
  itemExtent = 60.0,
  itemBuilder = proc(idx: int): Widget =
    container(
      padding = edgeInsetsAll(8),
      child = text("Item " & $idx)))
```

What it does:

- Only mounts the items currently visible in the viewport (plus a small
  buffer).
- Items that scroll out of view get unmounted; their State runs
  `dispose`.
- Scrollbar geometry reflects the full `itemCount * itemExtent`, so
  the thumb size and position are correct even though most items have
  never been built.

### Variable item heights

When item heights vary, pass `extentFor`:

```nim
listViewBuilder(
  itemCount = 1000,
  extentFor = proc(idx: int): float32 =
    if idx mod 2 == 0: 40.0 else: 80.0,
  extentEstimate = 60.0,
  itemBuilder = proc(idx: int): Widget = ...)
```

The sliver maintains a prefix-sum cache and uses binary search for
offset-to-index queries. `extentEstimate` seeds the scrollbar geometry
before items have been measured.

Tradeoff: stateful items lose their state when they scroll out of view.
Store per-item state in an `InheritedWidget` plus `ValueNotifier` if you
need persistence across scroll.

## RasterPool

Worker-thread pool for CPU-only paint work:

```nim
import flit/rendering/raster_pool

let pool = newRasterPool(2)

proc heavyWork() {.gcsafe, nimcall.} =
  # Anything CPU-bound that doesn't touch SDL or shared Pixie state.
  discard

pool.submit(heavyWork)
pool.drain()       # wait for all submitted work to finish
pool.shutdown()    # at app exit
```

Constraints:

- Tasks must be `{.gcsafe, nimcall.}` procs, not closures. Nim's ORC
  doesn't safely capture heap state across thread boundaries.
- Workers must not touch `RendererPtr`, `TexturePtr`, `WindowPtr`, or
  `GlContextPtr`. SDL renderers are bound to the thread that created
  them.
- Pixie `Font` and `Image` are not thread-safe. Either clone per worker
  or serialize calls through a single worker.

Use for: pre-rasterizing complex shapes that will be needed soon,
parallel image decoding, anything else CPU-heavy.

A shared global pool is available via `sharedRasterPool()`. It's
lazily created and lives for the process lifetime.

## Identity short-circuit

Already on by default. When a parent's rebuild returns the same widget
instance as last frame, flit detects the identity match and skips the
child rebuild walk entirely. Lets you cache subtrees trivially:

```nim
type
  Outer = ref object of StatefulWidget
  OuterState = ref object of State
    cachedInner: Widget   # built once

method initState(s: OuterState) =
  s.cachedInner = expensiveStaticContent()

method build(s: OuterState, ctx: BuildContext): Widget =
  column(children = @[
    s.cachedInner,       # same ref every frame; reconciliation skips it
    dynamicHeader(s.someValue),
  ])
```

The `cachedInner` subtree is reconciled in O(1) (just a slot update),
not O(size of subtree).

Verifying it works: `tests/test_identity_shortcircuit.nim` confirms
that a stable child reference does not trigger inner `build` calls.

## Putting it together: a fast list

A lazy list of cards, each with a cached complex header:

```nim
listViewBuilder(
  itemCount = 1000,
  itemExtent = 120.0,
  itemBuilder = proc(idx: int): Widget =
    repaintBoundary(child = container(
      margin = edgeInsetsAll(8),
      padding = edgeInsetsAll(12),
      hasDecoration = true,
      decoration = boxDecoration(
        color = colorWhite,
        borderRadius = 8,
        boxShadow = @[boxShadow(color = colorBlack.withOpacity(0.1),
                                offset = Offset(dx: 0, dy: 2),
                                blurRadius = 4)]),
      child = column(crossAxisAlignment = caStart, children = @[
        text("Item " & $idx, style = textStyle(fontSize = 16)),
        text("subtitle text", style = textStyle(fontSize = 12)),
      ]))))
```

Each card is its own repaint boundary, so when one card animates (say,
on hover), only that card's texture re-rasterizes. The list itself only
mounts the visible cards. Net cost per scroll frame: one mount of any
newly-visible card + N composites of unchanged boundaries (one GPU
texture copy each).

## Next step

Read `08-cli.md` for the flit command line.
