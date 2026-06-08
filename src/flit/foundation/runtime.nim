## Runtime: owns the build cycle. Mounts Elements, reconciles children on
## rebuild, links RenderObjects into a parent->child chain, and drives layout
## and paint.

import std/[options, deques]
import ./widget
import ./render_object
import ./geometry
import ./key
import ./binding
import ./diagnostics
import ../widgets/basic
import ../gestures/detector
import ../rendering/[flex, stack, proxy_box, decoration]

# Find the nearest descendant Element whose widget produces a RenderObject.
# Walk through stateless/stateful/proxy until we hit a render or end of tree.
proc descendantRenderElement*(e: Element): Element =
  if e.isNil: return nil
  case e.kind
  of ekRender: return e
  of ekStateless, ekStateful, ekProxy, ekInherited, ekRoot:
    for c in e.children:
      let r = descendantRenderElement(c)
      if not r.isNil: return r
    return nil

# Attach the child render objects of an element into the slot under
# `parentRender`. Handles the multi-child container case for Row/Column/Stack.
proc attachChildRenders*(e: Element)

proc attachAsChild(parent: RenderObject, child: RenderObject) =
  ## Attach `child` under `parent` based on `parent`'s concrete type.
  if parent of RenderFlex:
    let pf = RenderFlex(parent)
    var pd = FlexParentData(flex: 0, fit: ffLoose)
    pf.children.add(RenderFlexChild(obj: child, pd: pd))
  elif parent of RenderStack:
    let ps = RenderStack(parent)
    ps.children.add(RenderStackChild(obj: child, pd: newStackParentData()))
  elif parent of RenderProxyBox:
    RenderProxyBox(parent).child = child
  elif parent of RenderDecoratedBox:
    RenderDecoratedBox(parent).child = child
  child.parent = parent

proc attachChildRenders*(e: Element) =
  if e.kind == ekRender:
    # Clear existing then re-attach all child renders found in subtree
    if e.renderObj of RenderFlex: RenderFlex(e.renderObj).children.setLen(0)
    elif e.renderObj of RenderStack: RenderStack(e.renderObj).children.setLen(0)
    elif e.renderObj of RenderProxyBox: RenderProxyBox(e.renderObj).child = nil
    elif e.renderObj of RenderDecoratedBox: RenderDecoratedBox(e.renderObj).child = nil

    for c in e.children:
      let rE = descendantRenderElement(c)
      if rE.isNil: continue
      attachAsChild(e.renderObj, rE.renderObj)
      # Apply per-child parent data from intervening proxy widgets
      # (Flexible, Positioned).
      var anc = c
      while not anc.isNil and anc != rE:
        if anc.widget of Flexible and e.renderObj of RenderFlex:
          let fw = Flexible(anc.widget)
          let pf = RenderFlex(e.renderObj)
          # Find the just-added entry for this child render object
          for fc in pf.children:
            if fc.obj == rE.renderObj:
              fc.pd.flex = fw.flex
              fc.pd.fit  = fw.fit
              break
        elif anc.widget of Positioned and e.renderObj of RenderStack:
          let pw = Positioned(anc.widget)
          let ps = RenderStack(e.renderObj)
          for sc in ps.children:
            if sc.obj == rE.renderObj:
              sc.pd = newStackParentData(
                left = pw.left, top = pw.top, right = pw.right,
                bottom = pw.bottom, width = pw.width, height = pw.height)
              break
        if anc.children.len == 0: break
        anc = anc.children[0]

# Mount: create the element tree from widgets.

proc mountElement*(parent: Element, w: Widget, slot: int): Element

proc childrenOf(w: Widget): seq[Widget] =
  ## Extract the configuration children for a widget, since we don't have a
  ## generic "visitChildren" virtual on Widget itself.
  if w of Container:
    let c = Container(w)
    if not c.child.isNil: result.add(c.child)
  elif w of SizedBox:
    if not SizedBox(w).child.isNil: result.add(SizedBox(w).child)
  elif w of Padding:
    if not Padding(w).child.isNil: result.add(Padding(w).child)
  elif w of Align:
    if not Align(w).child.isNil: result.add(Align(w).child)
  elif w of ColoredBox:
    if not ColoredBox(w).child.isNil: result.add(ColoredBox(w).child)
  elif w of DecoratedBox:
    if not DecoratedBox(w).child.isNil: result.add(DecoratedBox(w).child)
  elif w of Row:        result = Row(w).children
  elif w of Column:     result = Column(w).children
  elif w of Stack:      result = Stack(w).children
  elif w of GestureDetector:
    if not GestureDetector(w).child.isNil:
      result.add(GestureDetector(w).child)
  elif w of ProxyWidget:
    let p = ProxyWidget(w)
    if not p.child.isNil: result.add(p.child)
  elif w of ConstrainedBox:
    if not ConstrainedBox(w).child.isNil: result.add(ConstrainedBox(w).child)

proc kindFor*(w: Widget): ElementKind =
  if   w of StatelessWidget:    ekStateless
  elif w of StatefulWidget:     ekStateful
  elif w of InheritedWidget:    ekInherited
  elif w of ProxyWidget:        ekProxy
  elif w of RenderObjectWidget: ekRender
  else: ekRoot

proc mountElement*(parent: Element, w: Widget, slot: int): Element =
  result = newElement(kindFor(w), w)
  result.parent = parent
  result.depth = if parent.isNil: 0 else: parent.depth + 1
  result.slot = slot

  case result.kind
  of ekStateless:
    let built = StatelessWidget(w).build(result)
    if not built.isNil:
      result.children.add(mountElement(result, built, 0))
  of ekStateful:
    let state = StatefulWidget(w).createState()
    state.element = result
    state.initState()
    result.state = state
    let built = state.build(result)
    if not built.isNil:
      result.children.add(mountElement(result, built, 0))
  of ekRender:
    result.renderObj = RenderObjectWidget(w).createRenderObject(result)
    let kids = childrenOf(w)
    for i, k in kids:
      result.children.add(mountElement(result, k, i))
    attachChildRenders(result)
  of ekProxy, ekInherited:
    let kids = childrenOf(w)
    for i, k in kids:
      result.children.add(mountElement(result, k, i))
  of ekRoot: discard

  result.dirty = false

# Rebuild: recreate widget tree for a dirty subtree.

proc rebuildElement*(e: Element)

proc reconcileChildren(parent: Element, newWidgets: seq[Widget]) =
  ## Match old children with new widgets via canUpdate; preserve elements
  ## when possible, otherwise replace.
  var newChildren: seq[Element] = @[]
  for i, nw in newWidgets:
    let old = if i < parent.children.len: parent.children[i] else: nil
    if not old.isNil and canUpdate(old.widget, nw):
      old.widget = nw
      old.dirty = true
      rebuildElement(old)
      newChildren.add(old)
    else:
      newChildren.add(mountElement(parent, nw, i))
  parent.children = newChildren

proc rebuildElement*(e: Element) =
  if e.isNil: return
  case e.kind
  of ekStateless:
    let built = StatelessWidget(e.widget).build(e)
    reconcileChildren(e, if built.isNil: @[] else: @[built])
  of ekStateful:
    if e.state.isNil:
      let state = StatefulWidget(e.widget).createState()
      state.element = e
      state.initState()
      e.state = state
    let built = e.state.build(e)
    reconcileChildren(e, if built.isNil: @[] else: @[built])
  of ekRender:
    # Update parameters on the render object (delegated to widget impl).
    RenderObjectWidget(e.widget).updateRenderObject(e, e.renderObj)
    reconcileChildren(e, childrenOf(e.widget))
    attachChildRenders(e)
  of ekProxy, ekInherited:
    reconcileChildren(e, childrenOf(e.widget))
  of ekRoot:
    if e.children.len > 0:
      rebuildElement(e.children[0])
  e.dirty = false

# Layout/paint pass entry points

proc runLayout*(root: Element, c: Constraints) =
  let rE = descendantRenderElement(root)
  if not rE.isNil:
    rE.renderObj.layout(c)

proc runPaint*(root: Element, canvas: Canvas) =
  let rE = descendantRenderElement(root)
  if rE.isNil: return
  let ctx = newPaintingContext(canvas, OffsetZero)
  rE.renderObj.paint(ctx, OffsetZero)

# ---- Event dispatch ----

type
  EventDispatcher* = ref object
    captured*: RenderGestureDetector  # current pan target, sticky across moves
    lastDown*: Offset
    lastMove*: Offset

var globalDispatcher* = EventDispatcher()

proc firstGestureDetector(path: seq[HitTestEntry]): tuple[g: RenderGestureDetector, local: Offset] =
  for entry in path:
    if entry.target of RenderGestureDetector:
      return (RenderGestureDetector(entry.target), entry.local)
  (nil, OffsetZero)

proc processPointerEvents*(b: Binding) =
  ## Drain pendingPointers, hit-test through the render tree, dispatch to
  ## the deepest matching GestureDetector. Pan continuity is preserved by
  ## capturing the detector on down and releasing on up.
  if b.isNil or b.rootElement.isNil: return
  let rE = descendantRenderElement(b.rootElement)
  if rE.isNil: return
  while b.pendingPointers.len > 0:
    let ev = b.pendingPointers.popFirst()
    case ev.kind
    of peDown:
      let res = HitTestResult(path: @[])
      discard rE.renderObj.hitTest(res, ev.position)
      let (g, _) = firstGestureDetector(res.path)
      if not g.isNil:
        globalDispatcher.captured = g
        globalDispatcher.lastDown = ev.position
        globalDispatcher.lastMove = ev.position
        # Pass screen coords to all handlers so the tap-distance check in
        # handleUp can subtract them sanely.
        handleDown(g, ev.position)
    of peMove:
      if not globalDispatcher.captured.isNil:
        let delta = ev.position - globalDispatcher.lastMove
        globalDispatcher.lastMove = ev.position
        handleMove(globalDispatcher.captured, ev.position, delta)
    of peUp:
      if not globalDispatcher.captured.isNil:
        handleUp(globalDispatcher.captured, ev.position)
        globalDispatcher.captured = nil
    of peCancel:
      globalDispatcher.captured = nil
    else: discard
