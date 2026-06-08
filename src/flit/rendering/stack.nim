## Z-stack rendering. Children paint back-to-front in the order they
## appear in `children`. Each child can be either:
## - `positioned`: absolute placement via `StackParentData` (left,
##   top, right, bottom, width, height; NaN means "not specified"),
## - non-positioned: laid out under stack constraints and aligned by
##   `RenderStack.alignment`.
##
## Backs the `Stack` widget; `Positioned` contributes the parent data.

import std/[math]
import ../foundation/[render_object, geometry, color]

type
  StackFit* = enum
    ## Constraint policy for non-positioned stack children.
    ## - `sfLoose`: loose constraints (each child picks its size).
    ## - `sfExpand`: tight max-size constraints (each child fills).
    ## - `sfPassthrough`: pass the stack's own constraints unchanged.
    sfLoose, sfExpand, sfPassthrough

  StackParentData* = ref object
    ## Parent-data attached to each stack child. NaN-valued fields
    ## mean "not specified". `positioned` is true when at least one
    ## position/size field is specified.
    left*, top*, right*, bottom*, width*, height*: float32
    positioned*: bool
    offset*: Offset

  RenderStackChild* = ref object
    ## A single child slot in a `RenderStack`.
    obj*: RenderObject
    pd*:  StackParentData

  RenderStack* = ref object of RenderObject
    ## Render object behind `Stack`. Lays out positioned children at
    ## absolute offsets and non-positioned children with the stack's
    ## `alignment`.
    alignment*: Alignment
    fit*: StackFit
    children*: seq[RenderStackChild]

const unsetF*: float32 = float32(NaN)
  ## Sentinel "not specified" value for `StackParentData` fields.
  ## Pass to `Positioned`'s side parameters to leave them unset.

proc newStackParentData*(left = unsetF, top = unsetF, right = unsetF,
                         bottom = unsetF, width = unsetF,
                         height = unsetF): StackParentData =
  ## Builds a `StackParentData`. Any specified field flips
  ## `positioned` to true so the layout treats this child as
  ## absolutely positioned.
  StackParentData(
    left: left, top: top, right: right, bottom: bottom,
    width: width, height: height,
    positioned: not (left.isNaN and top.isNaN and right.isNaN and
                     bottom.isNaN and width.isNaN and height.isNaN))

method performLayout*(r: RenderStack) =
  var maxW = 0.0'f32
  var maxH = 0.0'f32
  let childConstraints = case r.fit
    of sfLoose:       r.constraints.loosen()
    of sfExpand:      tightFor(r.constraints.maxWidth, r.constraints.maxHeight)
    of sfPassthrough: r.constraints

  # Non-positioned children
  for child in r.children:
    if child.pd.positioned: continue
    child.obj.layout(childConstraints)
    maxW = max(maxW, child.obj.size.width)
    maxH = max(maxH, child.obj.size.height)

  r.setSize(r.constraints.constrain(Size(width: maxW, height: maxH)))

  # Position non-positioned via alignment
  for child in r.children:
    if child.pd.positioned: continue
    child.pd.offset = r.alignment.resolveOffset(r.size, child.obj.size)

  # Positioned children. width/height/left/right/top/bottom are NaN when
  # not specified by the Positioned widget.
  for child in r.children:
    if not child.pd.positioned: continue
    let hasL = not child.pd.left.isNaN
    let hasR = not child.pd.right.isNaN
    let hasT = not child.pd.top.isNaN
    let hasB = not child.pd.bottom.isNaN
    let hasW = not child.pd.width.isNaN
    let hasH = not child.pd.height.isNaN
    var childW = 0.0'f32
    var childH = 0.0'f32
    if hasW: childW = child.pd.width
    elif hasL and hasR: childW = r.size.width - child.pd.left - child.pd.right
    if hasH: childH = child.pd.height
    elif hasT and hasB: childH = r.size.height - child.pd.top - child.pd.bottom
    let pc = if childW > 0 and childH > 0: tightFor(childW, childH)
             else: r.constraints.loosen()
    child.obj.layout(pc)
    let x = if hasL: child.pd.left
            elif hasR: r.size.width - child.pd.right - child.obj.size.width
            else: 0.0'f32
    let y = if hasT: child.pd.top
            elif hasB: r.size.height - child.pd.bottom - child.obj.size.height
            else: 0.0'f32
    child.pd.offset = Offset(dx: x, dy: y)

method paint*(r: RenderStack, ctx: PaintingContext, offset: Offset) =
  for child in r.children:
    ctx.paintChild(child.obj, child.pd.offset)

method hitTest*(r: RenderStack, htResult: HitTestResult, position: Offset): bool =
  # Iterate from top to bottom (last child paints on top, so it should
  # receive the event first).
  for i in countdown(r.children.high, 0):
    let child = r.children[i]
    let local = position - child.pd.offset
    let cs = child.obj.size
    if local.dx >= 0 and local.dy >= 0 and local.dx < cs.width and local.dy < cs.height:
      if child.obj.hitTest(htResult, local):
        htResult.path.add(HitTestEntry(target: r, local: position))
        return true
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true
