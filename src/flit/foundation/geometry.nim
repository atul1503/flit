## Geometry primitives used across layout, painting and gestures. Mirrors
## Flutter's dart:ui geometry types.

import std/[math, hashes]

type
  Offset* = object
    dx*, dy*: float32

  Size* = object
    width*, height*: float32

  Rect* = object
    left*, top*, right*, bottom*: float32

  Radius* = object
    x*, y*: float32

  RRect* = object
    rect*: Rect
    tl*, tr*, bl*, br*: Radius

  EdgeInsets* = object
    left*, top*, right*, bottom*: float32

  Alignment* = object
    x*, y*: float32  # -1.0..1.0 on each axis

  Axis* = enum
    axHorizontal, axVertical

  MainAxisAlignment* = enum
    maStart, maEnd, maCenter, maSpaceBetween, maSpaceAround, maSpaceEvenly

  CrossAxisAlignment* = enum
    caStart, caEnd, caCenter, caStretch, caBaseline

  MainAxisSize* = enum
    msMin, msMax

  TextDirection* = enum
    tdLtr, tdRtl

  VerticalDirection* = enum
    vdUp, vdDown

  Constraints* = object
    minWidth*, maxWidth*, minHeight*, maxHeight*: float32

const
  OffsetZero* = Offset(dx: 0, dy: 0)
  SizeZero*   = Size(width: 0, height: 0)
  RectZero*   = Rect(left: 0, top: 0, right: 0, bottom: 0)

# Offset

proc offset*(dx, dy: float32): Offset = Offset(dx: dx, dy: dy)
proc `+`*(a, b: Offset): Offset = Offset(dx: a.dx + b.dx, dy: a.dy + b.dy)
proc `-`*(a, b: Offset): Offset = Offset(dx: a.dx - b.dx, dy: a.dy - b.dy)
proc `*`*(a: Offset, s: float32): Offset = Offset(dx: a.dx * s, dy: a.dy * s)
proc distance*(a: Offset): float32 = sqrt(a.dx * a.dx + a.dy * a.dy)
proc hash*(o: Offset): Hash = !$ (hash(o.dx) !& hash(o.dy))

# Size

proc size*(w, h: float32): Size = Size(width: w, height: h)
proc area*(s: Size): float32 = s.width * s.height
proc isFinite*(s: Size): bool = s.width.classify != fcInf and s.height.classify != fcInf

# Rect

proc rect*(left, top, right, bottom: float32): Rect =
  Rect(left: left, top: top, right: right, bottom: bottom)

proc rectFromLTWH*(l, t, w, h: float32): Rect =
  Rect(left: l, top: t, right: l + w, bottom: t + h)

proc rectFromOffsetSize*(o: Offset, s: Size): Rect =
  rectFromLTWH(o.dx, o.dy, s.width, s.height)

proc width*(r: Rect): float32 = r.right - r.left
proc height*(r: Rect): float32 = r.bottom - r.top
proc topLeft*(r: Rect): Offset = Offset(dx: r.left, dy: r.top)
proc bottomRight*(r: Rect): Offset = Offset(dx: r.right, dy: r.bottom)
proc center*(r: Rect): Offset =
  Offset(dx: (r.left + r.right) * 0.5, dy: (r.top + r.bottom) * 0.5)
proc contains*(r: Rect, p: Offset): bool =
  p.dx >= r.left and p.dx < r.right and p.dy >= r.top and p.dy < r.bottom
proc shift*(r: Rect, o: Offset): Rect =
  Rect(left: r.left + o.dx, top: r.top + o.dy,
       right: r.right + o.dx, bottom: r.bottom + o.dy)
proc inflate*(r: Rect, d: float32): Rect =
  Rect(left: r.left - d, top: r.top - d, right: r.right + d, bottom: r.bottom + d)
proc deflate*(r: Rect, d: float32): Rect = inflate(r, -d)
proc intersect*(a, b: Rect): Rect =
  Rect(left: max(a.left, b.left), top: max(a.top, b.top),
       right: min(a.right, b.right), bottom: min(a.bottom, b.bottom))

# Radius / RRect

proc radius*(r: float32): Radius = Radius(x: r, y: r)
proc radiusElliptical*(x, y: float32): Radius = Radius(x: x, y: y)
proc rrect*(r: Rect, all: float32): RRect =
  let rad = radius(all)
  RRect(rect: r, tl: rad, tr: rad, bl: rad, br: rad)

# EdgeInsets

proc edgeInsetsAll*(v: float32): EdgeInsets =
  EdgeInsets(left: v, top: v, right: v, bottom: v)
proc edgeInsetsSymmetric*(horizontal, vertical: float32): EdgeInsets =
  EdgeInsets(left: horizontal, top: vertical, right: horizontal, bottom: vertical)
proc edgeInsetsOnly*(left=0.0'f32, top=0.0'f32, right=0.0'f32, bottom=0.0'f32): EdgeInsets =
  EdgeInsets(left: left, top: top, right: right, bottom: bottom)
proc edgeInsetsLTRB*(l, t, r, b: float32): EdgeInsets =
  EdgeInsets(left: l, top: t, right: r, bottom: b)
proc horizontal*(e: EdgeInsets): float32 = e.left + e.right
proc vertical*(e: EdgeInsets): float32 = e.top + e.bottom
proc topLeftOffset*(e: EdgeInsets): Offset = Offset(dx: e.left, dy: e.top)
proc deflateRect*(e: EdgeInsets, r: Rect): Rect =
  Rect(left: r.left + e.left, top: r.top + e.top,
       right: r.right - e.right, bottom: r.bottom - e.bottom)
proc deflateSize*(e: EdgeInsets, s: Size): Size =
  Size(width: max(0.0, s.width - e.left - e.right),
       height: max(0.0, s.height - e.top - e.bottom))

# Alignment

proc alignment*(x, y: float32): Alignment = Alignment(x: x, y: y)
const
  alignTopLeft*      = Alignment(x: -1, y: -1)
  alignTopCenter*    = Alignment(x:  0, y: -1)
  alignTopRight*     = Alignment(x:  1, y: -1)
  alignCenterLeft*   = Alignment(x: -1, y:  0)
  alignCenter*       = Alignment(x:  0, y:  0)
  alignCenterRight*  = Alignment(x:  1, y:  0)
  alignBottomLeft*   = Alignment(x: -1, y:  1)
  alignBottomCenter* = Alignment(x:  0, y:  1)
  alignBottomRight*  = Alignment(x:  1, y:  1)

proc resolveOffset*(a: Alignment, parent, child: Size): Offset =
  ## Returns the offset of `child` within `parent` for this alignment.
  let dx = (parent.width  - child.width)  * 0.5'f32 * (1.0'f32 + a.x)
  let dy = (parent.height - child.height) * 0.5'f32 * (1.0'f32 + a.y)
  Offset(dx: dx, dy: dy)

# Constraints

proc constraints*(minW, maxW, minH, maxH: float32): Constraints =
  Constraints(minWidth: minW, maxWidth: maxW, minHeight: minH, maxHeight: maxH)

proc tightFor*(w, h: float32): Constraints =
  Constraints(minWidth: w, maxWidth: w, minHeight: h, maxHeight: h)

proc tightFor*(s: Size): Constraints = tightFor(s.width, s.height)

proc looseFor*(s: Size): Constraints =
  Constraints(minWidth: 0, maxWidth: s.width, minHeight: 0, maxHeight: s.height)

proc unbounded*(): Constraints =
  Constraints(minWidth: 0, maxWidth: Inf, minHeight: 0, maxHeight: Inf)

proc hasBoundedWidth*(c: Constraints): bool  = c.maxWidth  < Inf
proc hasBoundedHeight*(c: Constraints): bool = c.maxHeight < Inf
proc isTight*(c: Constraints): bool =
  c.minWidth == c.maxWidth and c.minHeight == c.maxHeight
proc constrain*(c: Constraints, s: Size): Size =
  Size(width:  clamp(s.width,  c.minWidth,  c.maxWidth),
       height: clamp(s.height, c.minHeight, c.maxHeight))
proc enforce*(c, parent: Constraints): Constraints =
  Constraints(
    minWidth:  clamp(c.minWidth,  parent.minWidth,  parent.maxWidth),
    maxWidth:  clamp(c.maxWidth,  parent.minWidth,  parent.maxWidth),
    minHeight: clamp(c.minHeight, parent.minHeight, parent.maxHeight),
    maxHeight: clamp(c.maxHeight, parent.minHeight, parent.maxHeight))
proc loosen*(c: Constraints): Constraints =
  Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight)
proc deflate*(c: Constraints, e: EdgeInsets): Constraints =
  let h = e.horizontal
  let v = e.vertical
  Constraints(
    minWidth:  max(0.0, c.minWidth  - h),
    maxWidth:  max(0.0, c.maxWidth  - h),
    minHeight: max(0.0, c.minHeight - v),
    maxHeight: max(0.0, c.maxHeight - v))

# Interpolation - used by Tween[Offset] / Tween[Size] for animations.

proc lerp*(a, b: Offset, t: float32): Offset =
  Offset(dx: a.dx + (b.dx - a.dx) * t, dy: a.dy + (b.dy - a.dy) * t)

proc lerp*(a, b: Size, t: float32): Size =
  Size(width:  a.width  + (b.width  - a.width)  * t,
       height: a.height + (b.height - a.height) * t)

proc lerp*(a, b: EdgeInsets, t: float32): EdgeInsets =
  EdgeInsets(
    left:   a.left   + (b.left   - a.left)   * t,
    top:    a.top    + (b.top    - a.top)    * t,
    right:  a.right  + (b.right  - a.right)  * t,
    bottom: a.bottom + (b.bottom - a.bottom) * t)

proc `$`*(s: Size): string = "Size(" & $s.width & ", " & $s.height & ")"
proc `$`*(o: Offset): string = "Offset(" & $o.dx & ", " & $o.dy & ")"
proc `$`*(r: Rect): string =
  "Rect(l=" & $r.left & ", t=" & $r.top & ", r=" & $r.right & ", b=" & $r.bottom & ")"
proc `$`*(c: Constraints): string =
  "Constraints(w: " & $c.minWidth & ".." & $c.maxWidth &
  ", h: " & $c.minHeight & ".." & $c.maxHeight & ")"
