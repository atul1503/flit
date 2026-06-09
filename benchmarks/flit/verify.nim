## Sanity check the flit benchmark output: paint the same 500-card
## tree, save the result as a PNG, count the non-background pixels
## to confirm the cards actually rendered.

import std/[strformat, os]
import pixie
import ../../src/flit
import ../../src/flit/foundation/runtime
import ../../src/flit/platform/embedded/runner as embed
import ../../src/flit/rendering/text as flitText

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
  if path.len == 0: return
  let font = pixie.readFont(path)
  embed.embeddedFont = font
  flitText.measureText = wrapMeasureWithCache(proc(text: string, style: TextStyle): Size =
    let f = font
    f.size = style.fontSize
    let b = pixie.typeset(f, text).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height)))

const
  NumCards = 500
  Width = 400
  Height = 2000   # tall enough to see many cards

type
  Bench = ref object of StatelessWidget
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

when isMainModule:
  installFont()
  let canvas = embed.newEmbeddedCanvas(Width, Height)
  let root = mountElement(nil, Bench(count: NumCards), 0)
  runLayout(root, tightFor(Width.float32, Height.float32))
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(root, canvas)

  # Sanity check: count distinct colors. The page background is
  # 0xF5F5F8, cards are 0xFFFFFF, text is 0x000000 / 0x6E6E6E. If
  # paint ran fully we should see all of these. If it silently
  # skipped, only the background color appears.
  var cardWhite = 0
  var bgGrey = 0
  var black = 0
  var dark = 0
  let data = cast[ptr UncheckedArray[uint32]](addr canvas.image.data[0])
  for i in 0 ..< Width * Height:
    let px = data[i]
    let r = px and 0xFF
    let g = (px shr 8) and 0xFF
    let b = (px shr 16) and 0xFF
    if r == 0xFF and g == 0xFF and b == 0xFF: inc cardWhite
    elif r == 0xF5 and g == 0xF5 and b == 0xF8: inc bgGrey
    elif r < 0x20 and g < 0x20 and b < 0x20: inc black
    elif r < 0x80 and g < 0x80 and b < 0x80: inc dark
  echo &"  card-white px:   {cardWhite}"
  echo &"  bg-grey px:      {bgGrey}"
  echo &"  black px:        {black} (text)"
  echo &"  dark px:         {dark} (anti-aliased text)"

  canvas.image.writeFile("/tmp/flit_bench_verify.png")
  echo &"painted {NumCards} cards into {Width}x{Height} surface"
  echo &"  total pixels:     {Width * Height}"
  echo &"  saved to:         /tmp/flit_bench_verify.png"
