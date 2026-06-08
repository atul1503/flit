## BoxDecoration: background color, gradient, border, shadow, border radius.
## This is what gives Container its visual style in Flutter.

import ../foundation/[render_object, geometry, color]

type
  BoxShape* = enum
    bsRectangle, bsCircle

  Border* = object
    color*: Color
    width*: float32

  BoxShadow* = object
    color*:    Color
    offset*:   Offset
    blur*:     float32
    spread*:   float32

  GradientKind* = enum
    gkLinear, gkRadial

  Gradient* = object
    kind*:   GradientKind
    begin*:  Alignment
    `end`*:  Alignment
    colors*: seq[Color]
    stops*:  seq[float32]

  BoxDecoration* = object
    color*:        Color
    gradient*:     Gradient
    border*:       Border
    borderRadius*: float32
    shape*:        BoxShape
    shadows*:      seq[BoxShadow]
    hasGradient*:  bool
    hasBorder*:    bool

  RenderDecoratedBox* = ref object of RenderObject
    decoration*: BoxDecoration
    child*: RenderObject

proc boxDecoration*(color = colorTransparent, borderRadius = 0.0'f32,
                    border = Border(color: colorTransparent, width: 0),
                    shape = bsRectangle): BoxDecoration =
  BoxDecoration(color: color, borderRadius: borderRadius, border: border,
                shape: shape, hasBorder: border.width > 0)

method performLayout*(r: RenderDecoratedBox) =
  if r.child.isNil:
    let w = if r.constraints.hasBoundedWidth:  r.constraints.maxWidth  else: 0.0'f32
    let h = if r.constraints.hasBoundedHeight: r.constraints.maxHeight else: 0.0'f32
    r.setSize(r.constraints.constrain(Size(width: w, height: h)))
  else:
    r.child.layout(r.constraints)
    r.setSize(r.constraints.constrain(r.child.size))

method paint*(r: RenderDecoratedBox, ctx: PaintingContext, offset: Offset) =
  let rect = rectFromOffsetSize(offset, r.size)

  # Shadows behind the box
  for s in r.decoration.shadows:
    let sr = rect.shift(s.offset).inflate(s.spread)
    if r.decoration.borderRadius > 0:
      ctx.canvas.drawRRect(rrect(sr, r.decoration.borderRadius), s.color.value)
    else:
      ctx.canvas.drawRect(sr, s.color.value)

  case r.decoration.shape
  of bsRectangle:
    if r.decoration.borderRadius > 0:
      ctx.canvas.drawRRect(rrect(rect, r.decoration.borderRadius),
                           r.decoration.color.value)
    else:
      ctx.canvas.drawRect(rect, r.decoration.color.value)
  of bsCircle:
    ctx.canvas.drawCircle(rect.center,
                          min(r.size.width, r.size.height) * 0.5'f32,
                          r.decoration.color.value)

  if r.decoration.hasBorder:
    let bw = r.decoration.border.width
    let bc = r.decoration.border.color.value
    ctx.canvas.drawLine(rect.topLeft, Offset(dx: rect.right, dy: rect.top), bc, bw)
    ctx.canvas.drawLine(Offset(dx: rect.right, dy: rect.top), rect.bottomRight, bc, bw)
    ctx.canvas.drawLine(rect.bottomRight, Offset(dx: rect.left, dy: rect.bottom), bc, bw)
    ctx.canvas.drawLine(Offset(dx: rect.left, dy: rect.bottom), rect.topLeft, bc, bw)

  if not r.child.isNil:
    ctx.paintChild(r.child, OffsetZero)

method hitTest*(r: RenderDecoratedBox, htResult: HitTestResult, position: Offset): bool =
  if not r.child.isNil:
    discard r.child.hitTest(htResult, position)
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true
