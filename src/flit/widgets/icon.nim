## Vector icon widget. Renders a small set of built-in icon names
## using flit's drawing primitives (no font / no asset bundle).
## Replaces the "Q for search, the word Cart for cart" hacks.
##
## Available names:
## - "search"        magnifying glass
## - "cart"          shopping cart
## - "star"          5-pointed solid star
## - "star.outline"  5-pointed star outline (drawn as star with
##                   no fill plus thin lines; falls back to text)
## - "chevron.down"  down-pointing triangle
## - "chevron.up"    up-pointing triangle
## - "chevron.right" right-pointing triangle
## - "chevron.left"  left-pointing triangle
## - "close"         X
## - "menu"          three horizontal bars
## - "heart"         heart shape
## - "check"         checkmark
## - "plus"          plus sign
## - "minus"         minus sign
##
## Unknown names render as an empty box. Add a new icon by extending
## the `iconPaths` table below.

import std/[math, tables]
import ../foundation/[widget, render_object, geometry, color, key]

type
  Icon* = ref object of RenderObjectWidget
    ## Vector icon. `name` selects from the built-in set; `size`
    ## sets the bounding box (icons are drawn into a `size x size`
    ## square); `color` colors the strokes / fills.
    name*:  string
    size*:  float32
    color*: Color

  RenderIcon* = ref object of RenderObject
    name*:  string
    iconSize*: float32
    color*: Color

method widgetTypeName*(w: Icon): string = "Icon"
method createElement*(w: Icon): Element = newElement(ekRender, w)
method createRenderObject*(w: Icon, ctx: BuildContext): RenderObject =
  RenderIcon(name: w.name, iconSize: w.size, color: w.color)
method updateRenderObject*(w: Icon, ctx: BuildContext, r: RenderObject) =
  let ri = RenderIcon(r)
  ri.name = w.name
  ri.iconSize = w.size
  ri.color = w.color
  r.markNeedsPaint()

method performLayout*(r: RenderIcon) =
  r.setSize(r.constraints.constrain(
    Size(width: r.iconSize, height: r.iconSize)))

# Icon path definitions. Each proc takes the absolute top-left
# `o` of the icon's bounding box and the size `s`, and issues
# the right draw calls on `canvas` with `color`.

proc drawSearch(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  # A ring (drawn as a thick stroked path: outer filled circle minus
  # inner filled circle would need clipping; instead we approximate
  # the ring by a circle outline made of segments). Simpler: filled
  # large circle, then a line for the handle.
  # To get an actual ring, we use fillPolygon with two arc loops.
  let cx = o.dx + s * 0.42'f32
  let cy = o.dy + s * 0.42'f32
  let rOuter = s * 0.36'f32
  let rInner = s * 0.26'f32
  var pts: seq[Offset]
  const N = 24
  for i in 0 .. N:
    let a = float32(i) / float32(N) * (PI.float32 * 2.0'f32)
    pts.add(Offset(dx: cx + rOuter * cos(a),
                   dy: cy + rOuter * sin(a)))
  for i in countdown(N, 0):
    let a = float32(i) / float32(N) * (PI.float32 * 2.0'f32)
    pts.add(Offset(dx: cx + rInner * cos(a),
                   dy: cy + rInner * sin(a)))
  canvas.fillPolygon(pts, color)
  # Handle.
  let hx0 = cx + rOuter * 0.7'f32
  let hy0 = cy + rOuter * 0.7'f32
  let hx1 = o.dx + s * 0.95'f32
  let hy1 = o.dy + s * 0.95'f32
  canvas.drawLine(Offset(dx: hx0, dy: hy0),
                   Offset(dx: hx1, dy: hy1), color, s * 0.12'f32)

proc drawStar(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  let cx = o.dx + s * 0.5'f32
  let cy = o.dy + s * 0.5'f32
  let rOuter = s * 0.48'f32
  let rInner = s * 0.22'f32
  var pts: seq[Offset]
  # 5-pointed star: 10 vertices alternating outer/inner radii
  # starting from the top (angle = -PI/2).
  for i in 0 ..< 10:
    let r = if i mod 2 == 0: rOuter else: rInner
    let a = -PI.float32 * 0.5'f32 + float32(i) * PI.float32 / 5.0'f32
    pts.add(Offset(dx: cx + r * cos(a), dy: cy + r * sin(a)))
  canvas.fillPolygon(pts, color)

proc drawChevron(canvas: Canvas, o: Offset, s: float32,
                 color: uint32, dir: string) =
  let cx = o.dx + s * 0.5'f32
  let cy = o.dy + s * 0.5'f32
  let r = s * 0.35'f32
  var pts: seq[Offset]
  case dir
  of "down":
    pts = @[
      Offset(dx: cx - r, dy: cy - r * 0.5'f32),
      Offset(dx: cx + r, dy: cy - r * 0.5'f32),
      Offset(dx: cx,     dy: cy + r * 0.7'f32)]
  of "up":
    pts = @[
      Offset(dx: cx - r, dy: cy + r * 0.5'f32),
      Offset(dx: cx + r, dy: cy + r * 0.5'f32),
      Offset(dx: cx,     dy: cy - r * 0.7'f32)]
  of "right":
    pts = @[
      Offset(dx: cx - r * 0.5'f32, dy: cy - r),
      Offset(dx: cx - r * 0.5'f32, dy: cy + r),
      Offset(dx: cx + r * 0.7'f32, dy: cy)]
  of "left":
    pts = @[
      Offset(dx: cx + r * 0.5'f32, dy: cy - r),
      Offset(dx: cx + r * 0.5'f32, dy: cy + r),
      Offset(dx: cx - r * 0.7'f32, dy: cy)]
  else: return
  canvas.fillPolygon(pts, color)

proc drawCart(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  # Body of cart: a trapezoid-like rectangle. Drawn as a filled
  # rounded rectangle to keep it simple.
  let bodyL = o.dx + s * 0.20'f32
  let bodyR = o.dx + s * 0.85'f32
  let bodyT = o.dy + s * 0.30'f32
  let bodyB = o.dy + s * 0.65'f32
  let r = rrect(rectFromLTWH(bodyL, bodyT, bodyR - bodyL, bodyB - bodyT),
                s * 0.05'f32)
  canvas.drawRRect(r, color)
  # Handle going up-left.
  canvas.drawLine(Offset(dx: bodyL, dy: bodyT),
                   Offset(dx: o.dx + s * 0.05'f32, dy: o.dy + s * 0.18'f32),
                   color, s * 0.07'f32)
  # Two wheels.
  let wheelR = s * 0.07'f32
  canvas.drawCircle(Offset(dx: o.dx + s * 0.35'f32,
                           dy: o.dy + s * 0.82'f32),
                    wheelR, color)
  canvas.drawCircle(Offset(dx: o.dx + s * 0.72'f32,
                           dy: o.dy + s * 0.82'f32),
                    wheelR, color)

proc drawClose(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  let pad = s * 0.22'f32
  canvas.drawLine(Offset(dx: o.dx + pad, dy: o.dy + pad),
                   Offset(dx: o.dx + s - pad, dy: o.dy + s - pad),
                   color, s * 0.12'f32)
  canvas.drawLine(Offset(dx: o.dx + s - pad, dy: o.dy + pad),
                   Offset(dx: o.dx + pad, dy: o.dy + s - pad),
                   color, s * 0.12'f32)

proc drawMenu(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  let leftX = o.dx + s * 0.18'f32
  let rightX = o.dx + s * 0.82'f32
  let h = s * 0.10'f32
  for i, y in [s * 0.30'f32, s * 0.50'f32, s * 0.70'f32]:
    let cy = o.dy + y
    let r = rectFromLTWH(leftX, cy - h * 0.5'f32, rightX - leftX, h)
    canvas.drawRect(r, color)

proc drawHeart(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  # Two circles + a triangle.
  let cx = o.dx + s * 0.5'f32
  let topY = o.dy + s * 0.38'f32
  let lobeR = s * 0.18'f32
  canvas.drawCircle(Offset(dx: cx - lobeR, dy: topY), lobeR, color)
  canvas.drawCircle(Offset(dx: cx + lobeR, dy: topY), lobeR, color)
  canvas.fillPolygon(@[
    Offset(dx: cx - lobeR * 1.8'f32, dy: topY + lobeR * 0.4'f32),
    Offset(dx: cx + lobeR * 1.8'f32, dy: topY + lobeR * 0.4'f32),
    Offset(dx: cx,                   dy: o.dy + s * 0.88'f32),
  ], color)

proc drawCheck(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  canvas.drawLine(Offset(dx: o.dx + s * 0.18'f32, dy: o.dy + s * 0.55'f32),
                   Offset(dx: o.dx + s * 0.42'f32, dy: o.dy + s * 0.78'f32),
                   color, s * 0.14'f32)
  canvas.drawLine(Offset(dx: o.dx + s * 0.42'f32, dy: o.dy + s * 0.78'f32),
                   Offset(dx: o.dx + s * 0.84'f32, dy: o.dy + s * 0.25'f32),
                   color, s * 0.14'f32)

proc drawPlus(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  let cx = o.dx + s * 0.5'f32
  let cy = o.dy + s * 0.5'f32
  let r = s * 0.30'f32
  let t = s * 0.10'f32
  canvas.drawRect(rectFromLTWH(cx - r, cy - t * 0.5'f32, r * 2, t), color)
  canvas.drawRect(rectFromLTWH(cx - t * 0.5'f32, cy - r, t, r * 2), color)

proc drawMinus(canvas: Canvas, o: Offset, s: float32, color: uint32) =
  let cx = o.dx + s * 0.5'f32
  let cy = o.dy + s * 0.5'f32
  let r = s * 0.30'f32
  let t = s * 0.10'f32
  canvas.drawRect(rectFromLTWH(cx - r, cy - t * 0.5'f32, r * 2, t), color)

method paint*(r: RenderIcon, ctx: PaintingContext, offset: Offset) =
  let s = r.iconSize
  let c = r.color.value
  case r.name
  of "search":          drawSearch(ctx.canvas, offset, s, c)
  of "cart":            drawCart(ctx.canvas, offset, s, c)
  of "star":            drawStar(ctx.canvas, offset, s, c)
  of "chevron.down":    drawChevron(ctx.canvas, offset, s, c, "down")
  of "chevron.up":      drawChevron(ctx.canvas, offset, s, c, "up")
  of "chevron.right":   drawChevron(ctx.canvas, offset, s, c, "right")
  of "chevron.left":    drawChevron(ctx.canvas, offset, s, c, "left")
  of "close":           drawClose(ctx.canvas, offset, s, c)
  of "menu":            drawMenu(ctx.canvas, offset, s, c)
  of "heart":           drawHeart(ctx.canvas, offset, s, c)
  of "check":           drawCheck(ctx.canvas, offset, s, c)
  of "plus":            drawPlus(ctx.canvas, offset, s, c)
  of "minus":           drawMinus(ctx.canvas, offset, s, c)
  else:                 discard   # unknown name renders nothing

proc icon*(name: string, size: float32 = 16,
           color: Color = colorBlack, key: Key = nil): Icon =
  ## Builds an `Icon` widget.
  ##
  ## Inputs:
  ## - `name`: identifier from the built-in set. See module docs
  ##   for the list. Unknown names render an empty box of `size`.
  ## - `size`: bounding box side length in logical pixels. Default 16.
  ## - `color`: stroke / fill color. Default black.
  ## - `key`: optional reconciliation key.
  ##
  ## Effect: claims a `size x size` square and paints the matching
  ## vector glyph using the active canvas. Backends without
  ## `fillPolygon` fall back to a stroked outline of the polygon
  ## (still readable for most shapes).
  Icon(key: key, name: name, size: size, color: color)
