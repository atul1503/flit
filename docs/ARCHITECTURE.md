# Architecture

Flit copies Flutter's three-tree model and adapts it to Nim's object/method system.

## The three trees

```
   Widget tree           Element tree             Render tree
   (immutable            (long-lived              (layout + paint)
    config)               instances)
   +-----------+         +-----------+           +-----------+
   |Container  |  builds |Container  |  owns     |RenderBox  |
   |  child:   |-------> |  Element  |---------->|  Decorated|
   |  Padding  |         |  children |           |   Padding |
   |   child:  |         |     +     |           |    Flex   |
   |   Row...  |         |     |     |           +-----------+
   +-----------+         +-----------+
```

A `Widget` is an immutable descriptor. Every time we rebuild, we throw the widget tree away.

An `Element` is a runtime instance attached to a position in the tree. It lives across rebuilds and is the unit of identity: when we rebuild and the new widget at slot `i` has the same `widgetTypeName` and `Key`, we reuse the element and call `updateRenderObject` on its render object. Otherwise we tear down and replace.

A `RenderObject` is what knows how to lay out under `Constraints` and paint onto a `Canvas`. RenderObjects form a parallel parent/child tree that the framework wires up automatically from the widget tree.

## Reconciliation

`canUpdate(oldW, newW)` returns true when `widgetTypeName` matches and `Key` is equal. When true, we reuse the element. When false, we mount a fresh subtree. Keys let users force-recreate (`UniqueKey`) or pin identity (`ValueKey`, `GlobalKey`).

## Layout

`Constraints { minWidth, maxWidth, minHeight, maxHeight }` flow top-down. A child returns its `Size` after `performLayout`, which the parent stores. `RenderFlex` does this in two passes: inflexible children first, then flexible children split the remainder weighted by `flex`. `RenderStack` does z-stacking with absolute or aligned positioning.

## Painting

`paint(ctx, offset)` walks the render tree and issues primitive draw calls on a `Canvas` (`drawRect`, `drawRRect`, `drawCircle`, `drawLine`, `drawText`). Each backend implements `Canvas` differently:

- `SdlCanvas` (`rendering/canvas_sdl.nim`): paints with Pixie into an ARGB buffer, blits with SDL2.
- `WebCanvas` (`platform/web/runner.nim`): proxies to the browser's CanvasRenderingContext2D via the Nim JS backend.
- `EmbeddedCanvas` (`platform/embedded/runner.nim`): Pixie -> raw pixel buffer + flush callback.

## The frame loop

```
  poll events  ->  rebuild dirty subtrees  ->  layout  ->  paint  ->  present
       ^                                                                |
       +----------------------------------------------------------------+
```

`setState` marks the State's element dirty and pushes it onto `Binding.dirtyRoots`. The runner notices on the next frame.

## Hot reload

Today: `flit hot` watches `src/**.nim`, recompiles on change, and restarts the child process. The element tree is rebuilt from scratch. Full incremental patching (where state is preserved across rebuilds) is on the roadmap.

## Cross-platform

A single widget tree compiles to every target. The only platform-specific code is the runner (`platform/*/runner.nim`). `app.nim` picks the right runner via `when defined(...)`. Adding a new backend is just: implement `Canvas`, write a runner that mounts the tree and pumps frames, and add a branch to `runApp`.
