## Row/Column rendering. Flex layout based on Flutter's RenderFlex.

import std/[options, math]
import ../foundation/[render_object, geometry, color]

type
  FlexFit* = enum
    ffLoose, ffTight

  FlexParentData* = ref object
    flex*: int
    fit*: FlexFit
    offset*: Offset

  RenderFlexChild* = ref object
    obj*: RenderObject
    pd*:  FlexParentData

  RenderFlex* = ref object of RenderObject
    direction*: Axis
    mainAxisAlignment*: MainAxisAlignment
    crossAxisAlignment*: CrossAxisAlignment
    mainAxisSize*: MainAxisSize
    textDirection*: TextDirection
    verticalDirection*: VerticalDirection
    children*: seq[RenderFlexChild]

proc mainAxisExtent(s: Size, axis: Axis): float32 =
  if axis == axHorizontal: s.width else: s.height

proc crossAxisExtent(s: Size, axis: Axis): float32 =
  if axis == axHorizontal: s.height else: s.width

proc sizeFromAxis(main, cross: float32, axis: Axis): Size =
  if axis == axHorizontal: Size(width: main, height: cross)
  else: Size(width: cross, height: main)

proc constraintsAlongAxis(c: Constraints, axis: Axis, main, cross: Slice[float32]): Constraints =
  if axis == axHorizontal:
    Constraints(minWidth: main.a, maxWidth: main.b, minHeight: cross.a, maxHeight: cross.b)
  else:
    Constraints(minWidth: cross.a, maxWidth: cross.b, minHeight: main.a, maxHeight: main.b)

method performLayout*(r: RenderFlex) =
  ## Two-pass: lay out inflexible children to find remaining space, then flex
  ## children fill the remainder weighted by their flex value.
  let axis = r.direction
  var totalFlex = 0
  var allocatedMain = 0.0'f32
  var crossSize = 0.0'f32
  let maxMain = if axis == axHorizontal: r.constraints.maxWidth  else: r.constraints.maxHeight
  let maxCross = if axis == axHorizontal: r.constraints.maxHeight else: r.constraints.maxWidth
  let minCross = if axis == axHorizontal: r.constraints.minHeight else: r.constraints.minWidth

  # Pass 1: inflexible children
  for child in r.children:
    if child.pd.flex > 0:
      totalFlex += child.pd.flex
      continue
    let innerMain = (0.0'f32 .. (maxMain - allocatedMain).max(0))
    let innerCross = (0.0'f32 .. maxCross)
    let inner = constraintsAlongAxis(r.constraints, axis, innerMain, innerCross)
    child.obj.layout(inner)
    allocatedMain += mainAxisExtent(child.obj.size, axis)
    crossSize = max(crossSize, crossAxisExtent(child.obj.size, axis))

  # Pass 2: flexible children
  let freeSpace = max(0.0'f32, maxMain - allocatedMain)
  if totalFlex > 0 and freeSpace > 0:
    let spacePerFlex = freeSpace / float32(totalFlex)
    for child in r.children:
      if child.pd.flex <= 0: continue
      let mainExtent = spacePerFlex * float32(child.pd.flex)
      let mainMin = if child.pd.fit == ffTight: mainExtent else: 0.0'f32
      let innerMain = (mainMin .. mainExtent)
      let innerCross = (0.0'f32 .. maxCross)
      let inner = constraintsAlongAxis(r.constraints, axis, innerMain, innerCross)
      child.obj.layout(inner)
      allocatedMain += mainAxisExtent(child.obj.size, axis)
      crossSize = max(crossSize, crossAxisExtent(child.obj.size, axis))

  # Determine our own size
  let myMain = if r.mainAxisSize == msMax: maxMain else: allocatedMain
  let myCross = max(crossSize, minCross)
  r.setSize(r.constraints.constrain(sizeFromAxis(myMain, myCross, axis)))

  # Place children along main axis
  let leadingMain = case r.mainAxisAlignment
    of maStart:        0.0'f32
    of maEnd:          myMain - allocatedMain
    of maCenter:       (myMain - allocatedMain) * 0.5
    of maSpaceBetween,
       maSpaceAround,
       maSpaceEvenly:  0.0'f32

  let between = block:
    let n = r.children.len
    if n == 0: 0.0'f32
    else:
      case r.mainAxisAlignment
      of maSpaceBetween:
        if n <= 1: 0.0'f32
        else: (myMain - allocatedMain) / float32(n - 1)
      of maSpaceAround:
        if n == 0: 0.0'f32
        else: (myMain - allocatedMain) / float32(n)
      of maSpaceEvenly:
        (myMain - allocatedMain) / float32(n + 1)
      else: 0.0'f32

  var cursor = leadingMain
  if r.mainAxisAlignment == maSpaceAround:  cursor += between * 0.5
  if r.mainAxisAlignment == maSpaceEvenly:  cursor += between

  for child in r.children:
    let childMain  = mainAxisExtent(child.obj.size, axis)
    let childCross = crossAxisExtent(child.obj.size, axis)
    let crossPos = case r.crossAxisAlignment
      of caStart:   0.0'f32
      of caEnd:     myCross - childCross
      of caCenter,
         caBaseline:  (myCross - childCross) * 0.5
      of caStretch: 0.0'f32
    child.pd.offset = if axis == axHorizontal:
        Offset(dx: cursor, dy: crossPos)
      else:
        Offset(dx: crossPos, dy: cursor)
    cursor += childMain + between

method paint*(r: RenderFlex, ctx: PaintingContext, offset: Offset) =
  for child in r.children:
    ctx.paintChild(child.obj, child.pd.offset)

method hitTest*(r: RenderFlex, htResult: HitTestResult, position: Offset): bool =
  for child in r.children:
    let local = position - child.pd.offset
    let cs = child.obj.size
    if local.dx >= 0 and local.dy >= 0 and local.dx < cs.width and local.dy < cs.height:
      if child.obj.hitTest(htResult, local):
        htResult.path.add(HitTestEntry(target: r, local: position))
        return true
  htResult.path.add(HitTestEntry(target: r, local: position))
  return true
