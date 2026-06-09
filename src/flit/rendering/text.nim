## Text rendering. A simplified single-style text layout. Concrete
## backends (`canvas_sdl`, `canvas_js`, `canvas_embedded`) provide the
## glyph rendering and font metrics; this file produces the box size
## and line layout from those metrics.

import std/[strutils, tables, hashes]
import ../foundation/[render_object, geometry, color]

type
  TextAlign* = enum
    ## Horizontal alignment of each laid-out line within the paragraph
    ## box. `taStart`/`taEnd` are LTR-aware aliases for left/right;
    ## `taJustify` is currently treated as left.
    taLeft, taRight, taCenter, taJustify, taStart, taEnd

  TextStyle* = object
    ## Per-string text styling. Build via `textStyle(...)`. Fields:
    ## - `color`: glyph fill color.
    ## - `fontSize`: em size in logical pixels.
    ## - `fontFamily`: font name to look up in the backend's font
    ##   registry. `"system"` resolves to the auto-loaded system font.
    ## - `fontWeight`: 100..900 (currently informational; backends
    ##   don't yet load weighted fonts).
    ## - `italic`: informational.
    ## - `letterSpacing`: extra spacing between glyphs.
    ## - `height`: line-height multiplier (each line consumes
    ##   `fontSize * height` vertical pixels).
    color*:        Color
    fontSize*:     float32
    fontFamily*:   string
    fontWeight*:   int
    italic*:       bool
    letterSpacing*: float32
    height*:       float32

  RenderParagraph* = ref object of RenderObject
    ## Render object backing the `Text` widget. Computes and caches
    ## the wrapped `lines` during `performLayout`, then paints each
    ## line with `textAlign` during `paint`.
    text*:  string
    style*: TextStyle
    align*: TextAlign
    maxLines*: int           ## 0 = unlimited.
    softWrap*: bool
    lines*: seq[string]

const defaultTextStyle* = TextStyle(
    ## Default `TextStyle` used by `text()` if the caller doesn't
    ## supply one: 14pt black system font, weight 400, line height 1.2.
  color: colorBlack, fontSize: 14, fontFamily: "system",
  fontWeight: 400, italic: false, letterSpacing: 0, height: 1.2)

proc textStyle*(color = colorBlack, fontSize = 14.0'f32,
                fontFamily = "system", fontWeight = 400,
                italic = false, letterSpacing = 0.0'f32,
                height = 1.2'f32): TextStyle =
  ## Builds a `TextStyle` with sensible defaults.
  ##
  ## Inputs (all optional):
  ## - `color`: text color.
  ## - `fontSize`: em size in logical pixels.
  ## - `fontFamily`: font name to look up at draw time.
  ## - `fontWeight`: 100..900 (Material-style weights). Informational.
  ## - `italic`: informational.
  ## - `letterSpacing`: extra horizontal pixels between glyphs.
  ## - `height`: line-height multiplier.
  ##
  ## Output: a populated `TextStyle` value.
  TextStyle(color: color, fontSize: fontSize, fontFamily: fontFamily,
            fontWeight: fontWeight, italic: italic,
            letterSpacing: letterSpacing, height: height)

var measureText*: proc(text: string, style: TextStyle): Size
  ## Returns the bounding-box size of `text` in `style`. Backends
  ## replace this with their font-aware implementation at startup;
  ## the default approximation is `len * fontSize * 0.55` wide by
  ## `fontSize * style.height` tall. Used by layout to wrap and
  ## clamp.

measureText = proc(text: string, style: TextStyle): Size =
  Size(width:  float32(text.len) * style.fontSize * 0.55'f32,
       height: style.fontSize * style.height)

# --- Measurement cache ---
#
# Layout calls `measureText` once per text widget per frame. For a
# 500-card list that's 1000+ calls into Pixie's `typeset` per frame
# even when the text values haven't changed.
#
# `wrapMeasureWithCache(fn)` returns a memoizing wrapper around `fn`
# keyed by (text, fontFamily, fontSize, fontWeight). Stable strings
# like "Save", "Cancel", "Item 42" become cache hits and the layout
# pass drops to near-zero for text-heavy UIs.
#
# `clearMeasureTextCache()` wipes the cache. Use when fonts change
# at runtime.

type
  MeasureKey* = object
    text*: string
    family*: string
    size*: float32
    weight*: int16

var measureCache* {.threadvar.}: Table[MeasureKey, Size]
var measureCacheHits* {.threadvar.}: int
var measureCacheMisses* {.threadvar.}: int

proc hash*(k: MeasureKey): Hash =
  var h: Hash = 0
  h = h !& hash(k.text)
  h = h !& hash(k.family)
  h = h !& hash(int(k.size * 100))   # 0.01 px granularity
  h = h !& int(k.weight)
  !$h

proc `==`*(a, b: MeasureKey): bool =
  a.text == b.text and a.family == b.family and
  abs(a.size - b.size) < 0.001'f32 and a.weight == b.weight

proc wrapMeasureWithCache*(inner: proc(text: string, style: TextStyle): Size):
                          proc(text: string, style: TextStyle): Size =
  ## Returns a memoizing wrapper around `inner`. Cache key is
  ## (text, fontFamily, fontSize, fontWeight); the same string at
  ## the same style returns the cached `Size` without calling
  ## `inner` again.
  ##
  ## Wire this up in your backend's font-installation hook:
  ##
  ## .. code-block:: nim
  ##   measureText = wrapMeasureWithCache(proc(text, style): Size =
  ##     # actual Pixie typeset here
  ##     ...)
  ##
  ## Empty cache before first call.
  result = proc(text: string, style: TextStyle): Size =
    let key = MeasureKey(text: text, family: style.fontFamily,
                         size: style.fontSize,
                         weight: int16(style.fontWeight))
    if measureCache.hasKey(key):
      inc measureCacheHits
      return measureCache[key]
    inc measureCacheMisses
    let s = inner(text, style)
    measureCache[key] = s
    s

proc clearMeasureTextCache*() =
  ## Drops every entry from the text measurement cache. Call when
  ## the font set changes at runtime.
  measureCache.clear()
  measureCacheHits = 0
  measureCacheMisses = 0

proc wrapText(text: string, maxWidth: float32, style: TextStyle): seq[string] =
  ## Greedy word-wrap that respects measureText. Falls back to char-wrap if
  ## a single word exceeds maxWidth. Returns at least one line.
  result = @[]
  var current = ""
  proc width(s: string): float32 = measureText(s, style).width
  for word in text.split(' '):
    let candidate = if current.len == 0: word else: current & " " & word
    if width(candidate) <= maxWidth:
      current = candidate
    else:
      if current.len > 0:
        result.add(current)
        current = ""
      # Word might still be too wide alone. Char-wrap it.
      var w = word
      while width(w) > maxWidth and w.len > 1:
        var cut = w.len - 1
        while cut > 1 and width(w[0 ..< cut]) > maxWidth: dec cut
        result.add(w[0 ..< cut])
        w = w[cut ..< w.len]
      current = w
  if current.len > 0: result.add(current)
  if result.len == 0: result.add("")

method performLayout*(r: RenderParagraph) =
  ## Measures the text with the active `measureText`. If `softWrap`
  ## is false or the single-line width fits within `maxWidth`, sizes
  ## to one line. Otherwise word-wraps via `wrapText`, clamps to
  ## `maxLines` if positive, and sizes height to
  ## `lines.len * fontSize * style.height`. Width is the widest
  ## measured line. Stores `lines` for `paint`.
  let singleLineSize = measureText(r.text, r.style)
  if not r.softWrap or singleLineSize.width <= r.constraints.maxWidth:
    r.lines = @[r.text]
    r.setSize(r.constraints.constrain(singleLineSize))
    return
  r.lines = wrapText(r.text, r.constraints.maxWidth, r.style)
  if r.maxLines > 0 and r.lines.len > r.maxLines:
    r.lines.setLen(r.maxLines)
  let lineH = r.style.fontSize * r.style.height
  var widest = 0.0'f32
  for line in r.lines:
    widest = max(widest, measureText(line, r.style).width)
  r.setSize(r.constraints.constrain(Size(
    width: widest, height: lineH * float32(r.lines.len))))

method paint*(r: RenderParagraph, ctx: PaintingContext, offset: Offset) =
  ## Iterates the lines computed during layout and calls
  ## `canvas.drawText` for each one. Horizontal placement per line
  ## respects `textAlign`: `taStart`/`taLeft` -> 0, `taEnd`/`taRight`
  ## -> `size.width - lineWidth`, `taCenter` -> centered. Vertical
  ## spacing is `fontSize * style.height` per line.
  let lineH = r.style.fontSize * r.style.height
  let lines = if r.lines.len > 0: r.lines else: @[r.text]
  for i, line in lines:
    # Apply textAlign: left/start = 0, right/end = box.right - lineWidth,
    # center = (box.width - lineWidth)/2.
    var x = offset.dx
    if r.align != taLeft and r.align != taStart:
      let lineW = measureText(line, r.style).width
      case r.align
      of taRight, taEnd:    x = offset.dx + r.size.width - lineW
      of taCenter:          x = offset.dx + (r.size.width - lineW) * 0.5'f32
      else: discard
    ctx.canvas.drawText(line, Offset(dx: x, dy: offset.dy + float32(i) * lineH),
                        r.style.color.value,
                        r.style.fontSize, r.style.fontFamily)
