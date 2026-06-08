## Geometry primitives used across layout, painting and gestures. Mirrors
## Flutter's `dart:ui` geometry types: `Offset`, `Size`, `Rect`, `Radius`,
## `RRect`, `EdgeInsets`, `Alignment`, `Constraints`, plus the axis /
## alignment enums consumed by `Row`, `Column`, `Stack`.
##
## All values are float32 logical pixels. None of these procs have side
## effects: they return new values rather than mutating inputs.

import std/[math, hashes]

type
  Offset* = object
    ## A 2D point or vector. `dx` is horizontal, `dy` is vertical
    ## (positive = down, matching screen coordinates).
    dx*, dy*: float32

  Size* = object
    ## A 2D size, always non-negative by convention. `width` and
    ## `height` are in logical pixels.
    width*, height*: float32

  Rect* = object
    ## An axis-aligned rectangle expressed by its four edges (not by
    ## origin + size). `right >= left` and `bottom >= top` when the
    ## rect is normalized.
    left*, top*, right*, bottom*: float32

  Radius* = object
    ## A possibly-elliptical corner radius. `x` is the horizontal
    ## radius, `y` the vertical. Use `radius(r)` for circular corners.
    x*, y*: float32

  RRect* = object
    ## A rectangle with four corner radii. Use `rrect(rect, all)` to
    ## build one with uniform corners.
    rect*: Rect
    tl*, tr*, bl*, br*: Radius

  EdgeInsets* = object
    ## Insets on each side of a rectangle, in logical pixels. Used for
    ## padding, margins, and constraint deflation.
    left*, top*, right*, bottom*: float32

  Alignment* = object
    ## A 2D alignment in unit space. Each axis runs from `-1.0` (start /
    ## top / left) through `0` (center) to `+1.0` (end / bottom / right).
    ## Use the predefined `alignCenter`, `alignTopLeft` etc., or build
    ## one via `alignment(x, y)`.
    x*, y*: float32

  Axis* = enum
    ## Axis selector used by flex containers and scroll views.
    axHorizontal, axVertical

  MainAxisAlignment* = enum
    ## How children are placed along a flex container's main axis.
    ## `maStart` packs to the start. `maEnd` packs to the end.
    ## `maCenter` centers them as a group. `maSpaceBetween` puts equal
    ## gaps only BETWEEN children. `maSpaceAround` puts half-gaps at
    ## the ends. `maSpaceEvenly` puts equal gaps everywhere including
    ## the ends.
    maStart, maEnd, maCenter, maSpaceBetween, maSpaceAround, maSpaceEvenly

  CrossAxisAlignment* = enum
    ## How children are placed along the cross axis.
    ## `caStart`/`caEnd`/`caCenter` align to that edge.
    ## `caStretch` forces each child to fill the cross-axis extent.
    ## `caBaseline` aligns text baselines (treated as `caCenter` here).
    caStart, caEnd, caCenter, caStretch, caBaseline

  MainAxisSize* = enum
    ## Whether a flex container shrinks to its children (`msMin`) or
    ## expands to its parent's max constraint (`msMax`).
    msMin, msMax

  TextDirection* = enum
    ## Text directionality. `tdLtr` for left-to-right, `tdRtl` for
    ## right-to-left.
    tdLtr, tdRtl

  VerticalDirection* = enum
    ## Direction in which a column lays out its children.
    vdUp, vdDown

  Constraints* = object
    ## Min/max bounds on the size a child may take. A child receives
    ## constraints from its parent during layout, then returns a `Size`
    ## that must satisfy `minWidth <= size.width <= maxWidth` and
    ## similarly for height. `minWidth == maxWidth` means the width is
    ## "tight" - the child must be exactly that wide.
    minWidth*, maxWidth*, minHeight*, maxHeight*: float32

const
  OffsetZero* = Offset(dx: 0, dy: 0)
    ## The zero offset (origin).
  SizeZero*   = Size(width: 0, height: 0)
    ## The zero size.
  RectZero*   = Rect(left: 0, top: 0, right: 0, bottom: 0)
    ## The empty rect at the origin.

# Offset

proc offset*(dx, dy: float32): Offset =
  ## Builds an `Offset` from two components.
  Offset(dx: dx, dy: dy)

proc `+`*(a, b: Offset): Offset =
  ## Vector addition.
  Offset(dx: a.dx + b.dx, dy: a.dy + b.dy)
proc `-`*(a, b: Offset): Offset =
  ## Vector subtraction.
  Offset(dx: a.dx - b.dx, dy: a.dy - b.dy)
proc `*`*(a: Offset, s: float32): Offset =
  ## Scalar multiplication.
  Offset(dx: a.dx * s, dy: a.dy * s)

proc distance*(a: Offset): float32 =
  ## Euclidean magnitude `sqrt(dx*dx + dy*dy)`.
  sqrt(a.dx * a.dx + a.dy * a.dy)

proc hash*(o: Offset): Hash =
  ## Hash combining both components. Lets `Offset` be used as a `Table`
  ## key.
  !$ (hash(o.dx) !& hash(o.dy))

# Size

proc size*(w, h: float32): Size =
  ## Builds a `Size` from explicit width and height.
  Size(width: w, height: h)

proc area*(s: Size): float32 =
  ## Returns `width * height`.
  s.width * s.height

proc isFinite*(s: Size): bool =
  ## True when neither dimension is `Inf`.
  s.width.classify != fcInf and s.height.classify != fcInf

# Rect

proc rect*(left, top, right, bottom: float32): Rect =
  ## Builds a `Rect` from its four edges.
  Rect(left: left, top: top, right: right, bottom: bottom)

proc rectFromLTWH*(l, t, w, h: float32): Rect =
  ## Builds a `Rect` from origin + size.
  Rect(left: l, top: t, right: l + w, bottom: t + h)

proc rectFromOffsetSize*(o: Offset, s: Size): Rect =
  ## Builds a `Rect` from an `Offset` (top-left) and a `Size`.
  rectFromLTWH(o.dx, o.dy, s.width, s.height)

proc width*(r: Rect): float32 = r.right - r.left
  ## `right - left`.
proc height*(r: Rect): float32 = r.bottom - r.top
  ## `bottom - top`.
proc topLeft*(r: Rect): Offset = Offset(dx: r.left, dy: r.top)
  ## The top-left corner as an `Offset`.
proc bottomRight*(r: Rect): Offset = Offset(dx: r.right, dy: r.bottom)
  ## The bottom-right corner as an `Offset`.

proc center*(r: Rect): Offset =
  ## The center point of the rectangle.
  Offset(dx: (r.left + r.right) * 0.5, dy: (r.top + r.bottom) * 0.5)

proc contains*(r: Rect, p: Offset): bool =
  ## True when `p` lies inside `r`. The left/top edges are inclusive,
  ## the right/bottom edges are exclusive (matching half-open
  ## hit-testing conventions).
  p.dx >= r.left and p.dx < r.right and p.dy >= r.top and p.dy < r.bottom

proc shift*(r: Rect, o: Offset): Rect =
  ## Translates `r` by `o`.
  Rect(left: r.left + o.dx, top: r.top + o.dy,
       right: r.right + o.dx, bottom: r.bottom + o.dy)

proc inflate*(r: Rect, d: float32): Rect =
  ## Grows `r` outward by `d` on every side.
  Rect(left: r.left - d, top: r.top - d, right: r.right + d, bottom: r.bottom + d)

proc deflate*(r: Rect, d: float32): Rect = inflate(r, -d)
  ## Shrinks `r` inward by `d` on every side. Negative `d` grows.

proc intersect*(a, b: Rect): Rect =
  ## Returns the intersection of `a` and `b`. May be empty (right < left
  ## or bottom < top) if the rectangles don't overlap.
  Rect(left: max(a.left, b.left), top: max(a.top, b.top),
       right: min(a.right, b.right), bottom: min(a.bottom, b.bottom))

# Radius / RRect

proc radius*(r: float32): Radius =
  ## Builds a circular `Radius` of `r` pixels.
  Radius(x: r, y: r)
proc radiusElliptical*(x, y: float32): Radius =
  ## Builds an elliptical `Radius` with independent horizontal and
  ## vertical components.
  Radius(x: x, y: y)
proc rrect*(r: Rect, all: float32): RRect =
  ## Builds an `RRect` (rounded rectangle) with uniform corner radius
  ## `all`.
  let rad = radius(all)
  RRect(rect: r, tl: rad, tr: rad, bl: rad, br: rad)

# EdgeInsets

proc edgeInsetsAll*(v: float32): EdgeInsets =
  ## Equal insets on every side. Equivalent to Flutter's
  ## `EdgeInsets.all(v)`.
  EdgeInsets(left: v, top: v, right: v, bottom: v)

proc edgeInsetsSymmetric*(horizontal, vertical: float32): EdgeInsets =
  ## Same inset on the left and right (`horizontal`) and on the top and
  ## bottom (`vertical`).
  EdgeInsets(left: horizontal, top: vertical, right: horizontal, bottom: vertical)

proc edgeInsetsOnly*(left=0.0'f32, top=0.0'f32, right=0.0'f32, bottom=0.0'f32): EdgeInsets =
  ## Per-side insets, defaulting to zero on the sides you don't pass.
  EdgeInsets(left: left, top: top, right: right, bottom: bottom)

proc edgeInsetsLTRB*(l, t, r, b: float32): EdgeInsets =
  ## All four sides specified positionally in LTRB order.
  EdgeInsets(left: l, top: t, right: r, bottom: b)

proc horizontal*(e: EdgeInsets): float32 = e.left + e.right
  ## Total horizontal inset (`left + right`).
proc vertical*(e: EdgeInsets): float32 = e.top + e.bottom
  ## Total vertical inset (`top + bottom`).
proc topLeftOffset*(e: EdgeInsets): Offset = Offset(dx: e.left, dy: e.top)
  ## The `(left, top)` corner as an `Offset` - used to position a child
  ## inside its padding container.

proc deflateRect*(e: EdgeInsets, r: Rect): Rect =
  ## Shrinks `r` inward by `e` on each side.
  Rect(left: r.left + e.left, top: r.top + e.top,
       right: r.right - e.right, bottom: r.bottom - e.bottom)

proc deflateSize*(e: EdgeInsets, s: Size): Size =
  ## Subtracts the insets from a size, clamping at zero so the result
  ## is never negative.
  Size(width: max(0.0, s.width - e.left - e.right),
       height: max(0.0, s.height - e.top - e.bottom))

# Alignment

proc alignment*(x, y: float32): Alignment =
  ## Builds an `Alignment` from explicit components in `[-1, +1]`.
  Alignment(x: x, y: y)

const
  alignTopLeft*      = Alignment(x: -1, y: -1)
    ## Top-left anchor.
  alignTopCenter*    = Alignment(x:  0, y: -1)
    ## Top-center anchor.
  alignTopRight*     = Alignment(x:  1, y: -1)
    ## Top-right anchor.
  alignCenterLeft*   = Alignment(x: -1, y:  0)
    ## Vertically centered, left anchor.
  alignCenter*       = Alignment(x:  0, y:  0)
    ## Centered both axes.
  alignCenterRight*  = Alignment(x:  1, y:  0)
    ## Vertically centered, right anchor.
  alignBottomLeft*   = Alignment(x: -1, y:  1)
    ## Bottom-left anchor.
  alignBottomCenter* = Alignment(x:  0, y:  1)
    ## Bottom-center anchor.
  alignBottomRight*  = Alignment(x:  1, y:  1)
    ## Bottom-right anchor.

proc resolveOffset*(a: Alignment, parent, child: Size): Offset =
  ## Returns the offset where `child` should be placed inside `parent`
  ## to satisfy alignment `a`. For example with `alignCenter` the result
  ## is `((parent.width - child.width)/2, (parent.height - child.height)/2)`.
  let dx = (parent.width  - child.width)  * 0.5'f32 * (1.0'f32 + a.x)
  let dy = (parent.height - child.height) * 0.5'f32 * (1.0'f32 + a.y)
  Offset(dx: dx, dy: dy)

# Constraints

proc constraints*(minW, maxW, minH, maxH: float32): Constraints =
  ## Builds a `Constraints` from explicit bounds. Caller is responsible
  ## for ensuring `minW <= maxW` and `minH <= maxH`.
  Constraints(minWidth: minW, maxWidth: maxW, minHeight: minH, maxHeight: maxH)

proc tightFor*(w, h: float32): Constraints =
  ## Builds tight constraints: `minWidth == maxWidth == w` and similarly
  ## for `h`. The child MUST take exactly that size.
  Constraints(minWidth: w, maxWidth: w, minHeight: h, maxHeight: h)

proc tightFor*(s: Size): Constraints = tightFor(s.width, s.height)
  ## Convenience overload taking a `Size`.

proc looseFor*(s: Size): Constraints =
  ## Loose constraints with min 0 and max equal to `s`'s dimensions.
  ## The child may be any size from zero up to `s`.
  Constraints(minWidth: 0, maxWidth: s.width, minHeight: 0, maxHeight: s.height)

proc unbounded*(): Constraints =
  ## Loose constraints with infinite max on both axes. Use sparingly:
  ## children with no fixed size will not know how big to be.
  Constraints(minWidth: 0, maxWidth: Inf, minHeight: 0, maxHeight: Inf)

proc hasBoundedWidth*(c: Constraints): bool  = c.maxWidth  < Inf
  ## True if `maxWidth` is finite.
proc hasBoundedHeight*(c: Constraints): bool = c.maxHeight < Inf
  ## True if `maxHeight` is finite.
proc isTight*(c: Constraints): bool =
  ## True when both axes are tight (min == max).
  c.minWidth == c.maxWidth and c.minHeight == c.maxHeight

proc constrain*(c: Constraints, s: Size): Size =
  ## Clamps `s` to the `c` bounds component-wise. Useful in
  ## `performLayout` to compute the final size after measuring a child.
  Size(width:  clamp(s.width,  c.minWidth,  c.maxWidth),
       height: clamp(s.height, c.minHeight, c.maxHeight))

proc enforce*(c, parent: Constraints): Constraints =
  ## Clamps each bound of `c` to lie within `parent`'s bounds.
  ## Equivalent to Flutter's `BoxConstraints.enforce(parent)`.
  ## Use this when a widget wants to apply additional constraints on
  ## top of what its parent already gave it.
  Constraints(
    minWidth:  clamp(c.minWidth,  parent.minWidth,  parent.maxWidth),
    maxWidth:  clamp(c.maxWidth,  parent.minWidth,  parent.maxWidth),
    minHeight: clamp(c.minHeight, parent.minHeight, parent.maxHeight),
    maxHeight: clamp(c.maxHeight, parent.minHeight, parent.maxHeight))

proc loosen*(c: Constraints): Constraints =
  ## Returns a copy of `c` with both `min` set to zero. Caller can pass
  ## any size from 0 up to the original `max`.
  Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight)

proc deflate*(c: Constraints, e: EdgeInsets): Constraints =
  ## Shrinks both `max` and `min` by the corresponding `e` totals
  ## (`e.horizontal`, `e.vertical`). All results are clamped at zero.
  ## Used by `Padding` to compute the constraints passed to its child.
  let h = e.horizontal
  let v = e.vertical
  Constraints(
    minWidth:  max(0.0, c.minWidth  - h),
    maxWidth:  max(0.0, c.maxWidth  - h),
    minHeight: max(0.0, c.minHeight - v),
    maxHeight: max(0.0, c.maxHeight - v))

# Interpolation - used by Tween[Offset] / Tween[Size] for animations.

proc lerp*(a, b: Offset, t: float32): Offset =
  ## Linear interpolation between `a` and `b` component-wise. `t = 0`
  ## returns `a`, `t = 1` returns `b`. Values outside `[0, 1]`
  ## extrapolate.
  Offset(dx: a.dx + (b.dx - a.dx) * t, dy: a.dy + (b.dy - a.dy) * t)

proc lerp*(a, b: Size, t: float32): Size =
  ## Linear interpolation between two sizes.
  Size(width:  a.width  + (b.width  - a.width)  * t,
       height: a.height + (b.height - a.height) * t)

proc lerp*(a, b: EdgeInsets, t: float32): EdgeInsets =
  ## Linear interpolation between two `EdgeInsets` (per-side).
  EdgeInsets(
    left:   a.left   + (b.left   - a.left)   * t,
    top:    a.top    + (b.top    - a.top)    * t,
    right:  a.right  + (b.right  - a.right)  * t,
    bottom: a.bottom + (b.bottom - a.bottom) * t)

proc `$`*(s: Size): string = "Size(" & $s.width & ", " & $s.height & ")"
  ## Debug string representation.
proc `$`*(o: Offset): string = "Offset(" & $o.dx & ", " & $o.dy & ")"
  ## Debug string representation.
proc `$`*(r: Rect): string =
  ## Debug string representation.
  "Rect(l=" & $r.left & ", t=" & $r.top & ", r=" & $r.right & ", b=" & $r.bottom & ")"
proc `$`*(c: Constraints): string =
  ## Debug string representation showing both ranges.
  "Constraints(w: " & $c.minWidth & ".." & $c.maxWidth &
  ", h: " & $c.minHeight & ".." & $c.maxHeight & ")"
