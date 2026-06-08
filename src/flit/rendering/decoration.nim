## `BoxDecoration` and `RenderDecoratedBox`: background fill, border,
## shadow, border radius, and shape. This is what gives `Container`
## and `Card` their visual style.

import ../foundation/[render_object, geometry, color]

type
  BoxShape* = enum
    ## Outline shape of a `BoxDecoration`. `bsRectangle` (the default)
    ## fills with `borderRadius` rounding; `bsCircle` fills a circle
    ## whose diameter is `min(box.width, box.height)`.
    bsRectangle, bsCircle

  Border* = object
    ## A simple uniform border. Set `width = 0` for no border.
    color*: Color
    width*: float32

  BoxShadow* = object
    ## A drop shadow attached to a `BoxDecoration`. Currently rendered
    ## as a solid-colored rect at `offset` inflated by `spread`; the
    ## `blur` field is stored but not yet rasterized (the canvas
    ## backends lack proper gaussian blur).
    color*:    Color
    offset*:   Offset
    blur*:     float32
    spread*:   float32

  GradientKind* = enum
    ## Gradient flavor. `gkLinear` interpolates along a line from
    ## `begin` to `end` alignment; `gkRadial` interpolates outward
    ## from `begin`. Neither is rendered today; flit's canvas backends
    ## don't yet implement gradient fills.
    gkLinear, gkRadial

  Gradient* = object
    ## Linear or radial gradient definition. Currently a placeholder:
    ## `BoxDecoration.gradient` is stored but not drawn. Reserved API
    ## surface for forward compatibility.
    kind*:   GradientKind
    begin*:  Alignment
    `end`*:  Alignment
    colors*: seq[Color]
    stops*:  seq[float32]

  BoxDecoration* = object
    ## Visual style of a decorated box. Build via `boxDecoration(...)`.
    ##
    ## Fields:
    ## - `color`: solid fill color.
    ## - `gradient`: NOT YET RENDERED.
    ## - `border`: uniform-width outline.
    ## - `borderRadius`: corner rounding in logical pixels.
    ## - `shape`: rectangle or circle.
    ## - `shadows`: list of drop shadows. Rendered as solid offset
    ##   rectangles (no blur yet).
    ## - `hasGradient`, `hasBorder`: opt-in flags so default zero
    ##   values don't accidentally enable rendering.
    color*:        Color
    gradient*:     Gradient
    border*:       Border
    borderRadius*: float32
    shape*:        BoxShape
    shadows*:      seq[BoxShadow]
    hasGradient*:  bool
    hasBorder*:    bool

  RenderDecoratedBox* = ref object of RenderObject
    ## Render object that paints a `BoxDecoration` underneath its
    ## optional child. Backs the `DecoratedBox` widget.
    decoration*: BoxDecoration
    child*: RenderObject

proc boxDecoration*(color = colorTransparent, borderRadius = 0.0'f32,
                    border = Border(color: colorTransparent, width: 0),
                    shape = bsRectangle): BoxDecoration =
  ## Builds a `BoxDecoration` from the most common knobs.
  ##
  ## Inputs:
  ## - `color`: solid fill color. Default `colorTransparent` (no fill).
  ## - `borderRadius`: corner rounding in logical pixels. `0` =
  ##   sharp corners.
  ## - `border`: a `Border` value. Set `border.width > 0` to enable
  ##   an outline. Default no border.
  ## - `shape`: `bsRectangle` (default) or `bsCircle`.
  ##
  ## Output: a `BoxDecoration` value ready to pass to
  ## `decoratedBox(...)` or to assign to `Container.decoration`.
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
