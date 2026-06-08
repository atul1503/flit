## Text rendering. A simplified single-style text layout. Backends (SDL2,
## canvas, mobile) provide actual glyph rendering; here we compute the box
## size given metrics from the canvas.

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
    maxLines*: int
    softWrap*: bool

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

method performLayout*(r: RenderParagraph) =
  var sz = measureText(r.text, r.style)
  if r.softWrap and sz.width > r.constraints.maxWidth:
    let avgCharW = max(1.0'f32, r.style.fontSize * 0.55'f32)
    let charsPerLine = max(1, int(r.constraints.maxWidth / avgCharW))
    let lines = (r.text.len + charsPerLine - 1) div charsPerLine
    sz = Size(width: r.constraints.maxWidth,
              height: r.style.fontSize * r.style.height * float32(lines))
  r.setSize(r.constraints.constrain(sz))

method paint*(r: RenderParagraph, ctx: PaintingContext, offset: Offset) =
  ctx.canvas.drawText(r.text, offset, r.style.color.value,
                      r.style.fontSize, r.style.fontFamily)
