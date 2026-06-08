## Runtime: owns the build cycle. Mounts Elements, reconciles children on
## rebuild, links RenderObjects into a parent->child chain, and drives layout
## and paint.

import std/[options, deques, tables, hashes]
import ./widget
import ./render_object
import ./geometry
import ./key
import ./binding
import ./diagnostics
import ../widgets/basic
import ../gestures/detector
import ../rendering/[flex, stack, proxy_box, decoration, viewport]

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
  elif parent of RenderViewport:
    RenderViewport(parent).child = child
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
    elif e.renderObj of RenderViewport: RenderViewport(e.renderObj).child = nil
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
  elif w of ScrollView:
    if not ScrollView(w).child.isNil:
      result.add(ScrollView(w).child)
  elif w of ProxyWidget:
    let p = ProxyWidget(w)
    if not p.child.isNil: result.add(p.child)
  elif w of ConstrainedBox:
    if not ConstrainedBox(w).child.isNil: result.add(ConstrainedBox(w).child)
  elif w of AspectRatio:
    if not AspectRatio(w).child.isNil: result.add(AspectRatio(w).child)
  elif w of ClipRect:
    if not ClipRect(w).child.isNil: result.add(ClipRect(w).child)
  elif w of ClipRRect:
    if not ClipRRect(w).child.isNil: result.add(ClipRRect(w).child)
  elif w of OpacityWidget:
    if not OpacityWidget(w).child.isNil: result.add(OpacityWidget(w).child)

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

proc unmount(e: Element) =
  ## Recursively unmount: dispose any state, then clear children. Mirrors
  ## Flutter's Element.deactivate + unmount lifecycle so resources held in
  ## State.dispose (timers, controllers, listeners) get released when the
  ## element falls out of the tree.
  if e.isNil: return
  for c in e.children: unmount(c)
  e.children.setLen(0)
  if e.kind == ekStateful and not e.state.isNil:
    try: e.state.dispose() except CatchableError: discard
    e.state.mounted = false
    e.state = nil

proc reconcileChildren(parent: Element, newWidgets: seq[Widget]) =
  ## Two-pass match:
  ##   1. Build a map of old children that carry a Key; new widgets with
  ##      a matching key take ownership of that element.
  ##   2. Remaining new widgets are matched against remaining old children
  ##      by position. Unmatched old children are unmounted; unmatched new
  ##      widgets get fresh elements.
  ## Mirrors Flutter's MultiChildRenderObjectElement.updateChildren shape.
  var keyMap: Table[Hash, Element]
  for c in parent.children:
    if not c.widget.key.isNil:
      keyMap[hash(c.widget.key)] = c

  var unusedOld = parent.children
  proc removeFromUnused(e: Element) =
    var keep: seq[Element]
    for c in unusedOld:
      if c != e: keep.add(c)
    unusedOld = keep

  var newChildren: seq[Element] = newSeq[Element](newWidgets.len)
  # First pass: keyed matches.
  for i, nw in newWidgets:
    if nw.key.isNil: continue
    let h = hash(nw.key)
    if keyMap.hasKey(h):
      let old = keyMap[h]
      keyMap.del(h)
      removeFromUnused(old)
      if canUpdate(old.widget, nw):
        let oldWidget = old.widget
        old.widget = nw
        old.slot = i
        if old.kind == ekStateful and not old.state.isNil:
          try: old.state.didUpdateWidget(StatefulWidget(oldWidget))
          except CatchableError: discard
        old.dirty = true
        rebuildElement(old)
        newChildren[i] = old
      # else: same key but different type, fall through to positional
  # Second pass: positional matches for slots not yet filled.
  var oldIdx = 0
  for i, nw in newWidgets:
    if not newChildren[i].isNil: continue
    # Find next unused old at this slot or later.
    var old: Element = nil
    while oldIdx < unusedOld.len:
      let candidate = unusedOld[oldIdx]
      oldIdx.inc
      if candidate.widget.key.isNil and canUpdate(candidate.widget, nw):
        old = candidate
        break
    if not old.isNil:
      let oldWidget = old.widget
      old.widget = nw
      old.slot = i
      if old.kind == ekStateful and not old.state.isNil:
        try: old.state.didUpdateWidget(StatefulWidget(oldWidget))
        except CatchableError: discard
      old.dirty = true
      rebuildElement(old)
      newChildren[i] = old
    else:
      newChildren[i] = mountElement(parent, nw, i)

  # Anything left in unusedOld past our cursor needs to be unmounted.
  for j in oldIdx ..< unusedOld.len:
    unmount(unusedOld[j])
  # Any leftover keyed children that didn't match also need unmounting.
  for _, v in keyMap:
    unmount(v)

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

proc firstViewport(path: seq[HitTestEntry]): RenderViewport =
  for entry in path:
    if entry.target of RenderViewport:
      return RenderViewport(entry.target)
  nil

proc processPointerEvents*(b: Binding) =
  ## Drain pendingPointers, hit-test through the render tree, dispatch to
  ## the deepest matching GestureDetector. Pan continuity is preserved by
  ## capturing the detector on down and releasing on up.
  if b.isNil or b.rootElement.isNil: return
  let rE = descendantRenderElement(b.rootElement)
  if rE.isNil: return

  # Coalesce consecutive peMove events into just the last one: SDL emits
  # one mouse-motion event per pixel of travel and processing every one
  # rebuilds the tree per pixel. Only the final position matters.
  var coalesced: seq[PointerEvent]
  while b.pendingPointers.len > 0:
    let ev = b.pendingPointers.popFirst()
    if ev.kind == peMove and coalesced.len > 0 and coalesced[^1].kind == peMove:
      coalesced[^1] = ev
    else:
      coalesced.add(ev)

  for ev in coalesced:
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
    of peScroll:
      let res = HitTestResult(path: @[])
      discard rE.renderObj.hitTest(res, ev.position)
      let vp = firstViewport(res.path)
      if not vp.isNil:
        # SDL wheel events use positive Y = scroll up. We want positive
        # scrollOffset = content shifts up, so user sees content below.
        let delta = if vp.direction == axVertical: -ev.scrollDelta.dy
                    else: -ev.scrollDelta.dx
        vp.scrollOffset = vp.scrollOffset + delta * 40.0'f32
        vp.clampScroll()
        # Just repaint, don't rebuild the widget tree. The scroll offset
        # doesn't affect layout, only paint translation.
        b.needsRepaint = true
    else: discard
