## Text rendering. A simplified single-style text layout. Backends (SDL2,
## canvas, mobile) provide actual glyph rendering; here we compute the box
## size given metrics from the canvas.

import std/strutils
import ../foundation/[render_object, geometry, color]

type
  TextAlign* = enum
    taLeft, taRight, taCenter, taJustify, taStart, taEnd

  TextStyle* = object
    color*:        Color
    fontSize*:     float32
    fontFamily*:   string
    fontWeight*:   int    # 100..900
    italic*:       bool
    letterSpacing*: float32
    height*:       float32  # line height multiplier

  RenderParagraph* = ref object of RenderObject
    text*:  string
    style*: TextStyle
    align*: TextAlign
    maxLines*: int          # 0 = unlimited
    softWrap*: bool
    lines*: seq[string]     # computed during performLayout

const defaultTextStyle* = TextStyle(
  color: colorBlack, fontSize: 14, fontFamily: "system",
  fontWeight: 400, italic: false, letterSpacing: 0, height: 1.2)

proc textStyle*(color = colorBlack, fontSize = 14.0'f32,
                fontFamily = "system", fontWeight = 400,
                italic = false, letterSpacing = 0.0'f32,
                height = 1.2'f32): TextStyle =
  TextStyle(color: color, fontSize: fontSize, fontFamily: fontFamily,
            fontWeight: fontWeight, italic: italic,
            letterSpacing: letterSpacing, height: height)

# We approximate width: 0.55 * fontSize per glyph; height: fontSize * lineHeight.
# A real backend measures via its font engine and overrides via a callback.

var measureText*: proc(text: string, style: TextStyle): Size =
  proc(text: string, style: TextStyle): Size =
    Size(width:  float32(text.len) * style.fontSize * 0.55'f32,
         height: style.fontSize * style.height)

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
