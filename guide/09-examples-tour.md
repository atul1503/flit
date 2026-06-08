# 09. Examples tour

The `examples/` folder contains complete, runnable apps. Each
demonstrates a different slice of flit. Run any of them with `nim c -r`
on the entry point.

## Counter

`examples/counter/main.nim`

The smallest possible app. One `StatefulWidget` with one integer of
state and a button that increments it. Open this first when you need to
remind yourself what the minimum surface looks like.

```
nim c -r examples/counter/main.nim
```

What to read for:

- The `StatefulWidget` + `State` pair shape.
- `setState` call site.
- How `runApp` opens a window from a widget.

## Todo

`examples/todo/main.nim`

A list of tasks with add, toggle, delete. Demonstrates:

- `seq[T]` state held in the State object.
- Building child widgets from a dynamic list (mapping `for i in items`).
- `gestureDetector` for tap-to-toggle and tap-to-delete.

What to read for:

- How keyed children preserve state across reorders (each row has a
  `ValueKey`).
- A common pattern of `setState(s, proc() = mutateTheList())`.

## Calculator

`examples/calculator/main.nim`

A 4x4 grid calculator. Demonstrates:

- Manual grid layout via nested rows.
- Mapping button labels to a switch-on-string for operations.
- A 16-button keypad with consistent styling.

What to read for:

- How to factor a grid into a small helper proc.
- Sharing button visual styling without inheriting.

## Gallery

`examples/gallery/main.nim`

A grid of color tiles. Demonstrates:

- A simple infinite-scroll-feeling list.
- `aspectRatio` and `decoratedBox` together.
- Random-but-deterministic content generation.

## Showcase

`examples/showcase/main.nim`

The biggest one. A six-tab demo touching almost every public API:

| Tab | What it shows |
|-----|---------------|
| Home | Material widgets, theme toggle, basic layout |
| Layout | Row / Column / Stack / Positioned / Container |
| Style | Decorations, opacity, clipping, aspect ratio |
| Inputs | All gesture kinds: tap, double-tap, pan |
| Animation | AnimationController across every built-in curve |
| State | ValueNotifier + ListenableBuilder + InheritedWidget |
| Cupertino | iOS-styled widgets |

What to read for:

- A real switch on a discriminated state type (the tab enum).
- How to compose tabs without rebuilding the whole app on switch.
- Concrete usage of `repaintBoundary` if you want to wrap any tab in
  one to see the perf difference.

Run it:

```
nim c -r examples/showcase/main.nim
```

## State demo

`examples/state_demo/main.nim`

A pared-down standalone state-management demo. Two notifiers
(`userName`, `cartItemCount`) shared across the tree. Two
`ListenableBuilder`s subscribe to them independently. Buttons mutate
the notifiers and you can see exactly which subtree rebuilds.

What to read for:

- How to expose module-scope notifiers and have widgets subscribe.
- A minimal `InheritedWidget` that exposes a notifier via the tree
  instead of via module scope.

## Web

`examples/counter/web.nim`

Same counter app, built for the JS backend:

```
nim js -d:release -o:web/app.js examples/counter/web.nim
```

Open `examples/counter/web.html` in a browser. The widget tree is the
same; the canvas backend swaps to `WebCanvas` (HTML5 canvas via JS
interop).

What to read for:

- Confirming that flit's widget API genuinely works unchanged across
  desktop and web.
- The platform runner pattern (`runWeb` instead of `runDesktop`).

## A typical exploration order

If you are reading flit code top-down for the first time, this order
works well:

1. `examples/counter/main.nim` (10 lines of widget code)
2. `src/flit/foundation/widget.nim` (the three widget base types)
3. `src/flit/widgets/basic.nim` (the layout widgets)
4. `examples/showcase/main.nim` (everything wired together)
5. `src/flit/foundation/runtime.nim` (mount, rebuild, reconcile)
6. `src/flit/rendering/proxy_box.nim` (render-object templates)

## Next step

Read `10-api-reference.md` for how to generate and navigate the
generated API docs.
