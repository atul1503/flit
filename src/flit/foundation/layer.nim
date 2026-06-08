## Layer tree: a parallel tree to the render tree that captures
## rasterizable units. Each `Layer` knows how to paint itself onto a
## `Canvas`. The compositor walks the layer tree and either re-paints a
## layer (when its subtree is dirty) or composites a cached texture
## from the previous frame (when it isn't).
##
## A `RepaintBoundary` widget creates a `BoundaryLayer` that owns its
## own sub-canvas. The sub-canvas's pixel buffer is rasterized exactly
## once per change and then composited on every frame. For static
## subtrees the per-frame cost collapses to one GPU blit.
##
## Design parallels Flutter's `dart:ui` `Layer` hierarchy but is
## intentionally smaller: only the layer types we actually need.

import ./geometry
import ./render_object

type
  Layer* = ref object of RootObj
    ## Base type for every node in the layer tree. Concrete layers
    ## override `composite` to put their contents onto a parent canvas.
    ## Most layers are container-shaped (`children`); `BoundaryLayer`
    ## is the cache-bearing leaf-ish kind.
    parent*: Layer
    offset*: Offset
    needsComposite*: bool

  ContainerLayer* = ref object of Layer
    ## A layer with children. Compositing walks children in order.
    children*: seq[Layer]

  OffsetLayer* = ref object of ContainerLayer
    ## Translates the coordinate system of its children by `offset`.

  OpacityLayer* = ref object of ContainerLayer
    ## Multiplies the alpha of every primitive painted inside.
    opacity*: float32

  TransformLayer* = ref object of ContainerLayer
    ## Applies translate + rotate + scale to children.
    translation*: Offset
    rotation*: float32
    scale*: float32

  ClipRectLayer* = ref object of ContainerLayer
    ## Clips children to a rectangle.
    clipBounds*: Rect

  PictureLayer* = ref object of Layer
    ## A leaf layer whose contents are drawn by a `paintFn` callback.
    ## Used as a fallback for render objects that don't (yet) build
    ## their own specialized layers.
    paintFn*: proc(canvas: Canvas, offset: Offset) {.closure.}
    size*: Size

  BoundaryLayer* = ref object of ContainerLayer
    ## A cacheable layer. Owns a sub-canvas onto which its subtree
    ## rasterizes. When `dirty` is false, the cached sub-canvas is
    ## composited as-is. When `dirty` is true the sub-canvas is
    ## re-rasterized first.
    ##
    ## The actual sub-canvas object is backend-specific. We hold it
    ## opaquely as a `Canvas` ref. The backend that constructed the
    ## parent canvas is responsible for vending the sub-canvas and for
    ## the composite step.
    subCanvas*: Canvas
    size*: Size
    dirty*: bool

# Tree management

proc add*(parent: ContainerLayer, child: Layer) =
  ## Appends `child` to `parent.children` and sets `child.parent`.
  ## Safe for `child == nil` (no-op).
  if child.isNil: return
  child.parent = parent
  parent.children.add(child)

proc clearChildren*(parent: ContainerLayer) =
  ## Drops all children. Used when a layer is rebuilt from its render
  ## object during paint. Children become unreachable; their cached
  ## sub-canvases (if any) get released by the GC.
  parent.children.setLen(0)

proc markBoundaryDirty*(layer: Layer) =
  ## Walks up the layer chain marking the nearest enclosing
  ## `BoundaryLayer` as dirty. Render objects call this when their
  ## paint output would differ from the cached texture.
  var cur = layer
  while not cur.isNil:
    if cur of BoundaryLayer:
      BoundaryLayer(cur).dirty = true
      return
    cur = cur.parent

# Composition. The default `composite` paints children one by one;
# subclasses override to apply their effect (opacity, transform, etc).

method composite*(l: Layer, canvas: Canvas, offset: Offset) {.base.} = discard
  ## Paint this layer (and any subtree it owns) onto `canvas` at the
  ## given absolute `offset`. Subclasses override; the base no-op is
  ## useful for test stubs.

method composite*(l: ContainerLayer, canvas: Canvas, offset: Offset) =
  ## Default container composite: walks children in order, adding
  ## their per-child `offset` on top of the absolute origin.
  for c in l.children:
    composite(c, canvas, offset + c.offset)

method composite*(l: OffsetLayer, canvas: Canvas, offset: Offset) =
  ## Translates by the layer's own offset before descending.
  for c in l.children:
    composite(c, canvas, offset + c.offset)

method composite*(l: OpacityLayer, canvas: Canvas, offset: Offset) =
  ## Pushes opacity onto the canvas stack, composites children, pops.
  canvas.pushOpacity(l.opacity)
  for c in l.children:
    composite(c, canvas, offset + c.offset)
  canvas.popOpacity()

method composite*(l: TransformLayer, canvas: Canvas, offset: Offset) =
  ## Applies translate + rotate + scale via canvas state.
  canvas.save()
  canvas.translate(offset.dx + l.translation.dx, offset.dy + l.translation.dy)
  if l.rotation != 0: canvas.rotate(l.rotation)
  if l.scale != 0 and l.scale != 1: canvas.scale(l.scale, l.scale)
  for c in l.children:
    composite(c, canvas, c.offset)
  canvas.restore()

method composite*(l: ClipRectLayer, canvas: Canvas, offset: Offset) =
  canvas.save()
  canvas.clipRect(Rect(left: offset.dx + l.clipBounds.left,
                       top: offset.dy + l.clipBounds.top,
                       right: offset.dx + l.clipBounds.right,
                       bottom: offset.dy + l.clipBounds.bottom))
  for c in l.children:
    composite(c, canvas, offset + c.offset)
  canvas.restore()

method composite*(l: PictureLayer, canvas: Canvas, offset: Offset) =
  ## Calls the stored `paintFn` to draw at `offset`.
  if l.paintFn != nil:
    l.paintFn(canvas, offset)

# Boundary layer composite is intentionally backend-aware: it needs to
# know how to draw `subCanvas` onto `canvas`. That logic lives in the
# canvas backend (canvas_sdl.nim and equivalents) which can implement
# the blit as a GPU texture copy. We expose a hook proc the backend
# overrides via `method` so the default boundary composite stays here.

method compositeBoundary*(canvas: Canvas, sub: Canvas,
                         offset: Offset, size: Size) {.base.} = discard
  ## Backend hook for compositing a `BoundaryLayer`'s sub-canvas onto
  ## the parent canvas. Default no-op. Concrete canvases override to
  ## implement the GPU-side blit (SDL: upload `sub` to an SDL texture,
  ## then `SDL_RenderCopy`; embedded: per-pixel image copy).

method composite*(l: BoundaryLayer, canvas: Canvas, offset: Offset) =
  ## If `dirty`, ask the backend to re-rasterize children into
  ## `subCanvas` (the caller is expected to have done this already via
  ## `paintIntoBoundary`; we just composite). Then composite the sub
  ## canvas onto the parent at the given absolute `offset`.
  ##
  ## When `subCanvas` is nil (no backend support) we fall back to
  ## directly painting children onto the parent canvas; the perf win
  ## is lost but correctness is preserved.
  if l.subCanvas.isNil:
    for c in l.children:
      composite(c, canvas, offset + c.offset)
  else:
    compositeBoundary(canvas, l.subCanvas, offset, l.size)

# Helpers used by render objects to push painting through a layer

proc paintIntoSubCanvas*(boundary: BoundaryLayer,
                         paintFn: proc(sub: Canvas) {.closure.}) =
  ## Re-rasterizes the boundary by clearing its sub-canvas and running
  ## `paintFn` against it. Only call when `boundary.dirty` is true.
  ## Resets `dirty` to false on success.
  ##
  ## Inputs:
  ## - `boundary`: the cached layer.
  ## - `paintFn`: a closure that draws the subtree onto the sub-canvas.
  ##
  ## Effect: subtree is rasterized into `boundary.subCanvas`; future
  ## composites can blit directly without redrawing.
  if boundary.subCanvas.isNil: return
  boundary.subCanvas.clear(0x00000000'u32)
  paintFn(boundary.subCanvas)
  boundary.dirty = false

proc isDirty*(boundary: BoundaryLayer): bool =
  ## Returns true if this boundary needs re-rasterization on this
  ## frame.
  boundary.dirty

proc newPictureLayer*(paintFn: proc(canvas: Canvas, offset: Offset) {.closure.},
                     size: Size = SizeZero): PictureLayer =
  ## Builds a `PictureLayer` from a paint closure. Used as a leaf
  ## layer for the fallback "just paint normally" path.
  PictureLayer(paintFn: paintFn, size: size)

proc newBoundaryLayer*(size: Size): BoundaryLayer =
  ## Builds a `BoundaryLayer` of the given size. The `subCanvas`
  ## field is left nil; the backend fills it in via
  ## `attachSubCanvas` when it sees the boundary during paint.
  BoundaryLayer(size: size, dirty: true)
