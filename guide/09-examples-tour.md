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

## Notes

`examples/notes/main.nim`

A complete real app: list of notes, edit screen, settings,
persistent storage. Demonstrates almost every flit feature
working together:

- ValueNotifier-backed store with ListenableBuilder subscribers
- ListView.builder for the main list
- Navigator with animated push (trSlideLeft) and pop
- TextField with cursor, selection, clipboard, undo, redo
- InheritedWidget for theme (light / dark)
- Semantics annotations for accessibility
- JSON persistence to /tmp/flit_notes.json
- GestureDetector for tap-to-open

Run it:

```
nim c -r examples/notes/main.nim
```

This is the example to study when you're ready to build a real
app. Every pattern you'll need in production is in it.

## Amazon

`examples/amazon/main.nim`

A 1600-line Amazon storefront clone. The largest example and the
one closest to a production e-commerce UI. Used internally as the
"does the framework actually scale to a real app" smoke test.

Screens:

- Home: navy header (logo, address picker, search, language,
  account, returns, cart badge), sub-nav bar, hero banner,
  2x2 category grid, recommendation rows, dark footer
- Product detail: image, brand link, title, star rating, price
  with strikethrough list, About-this-item bullets, side buy box
  with Qty stepper + Add to Cart + Buy Now + Add to List
- Cart: line items with Qty controls, running subtotal,
  checkout box
- Search results: filter sidebar + sort dropdown + product list
- Category browse: filter sidebar + sort dropdown + 3-column grid
- Today's Deals: 4-column grid of discounted products
- Orders, Sign in (with obscured-password TextField), Account &
  Lists, Wishlist, Customer Service, Gift Cards, Sell

Things to study here:

- 12-product fake catalog with `imageUrl` pointing at
  picsum.photos; uses `networkImage` to load real product photos
  asynchronously
- Per-URL `notifierForUrl` so each NetworkImage subscribes only
  to its own URL's load event (avoids "every image rebuild
  invalidates every card" flicker)
- `repaintBoundary` wrappers on every productCard, categoryCard,
  hero, header, sub-nav, and footer - steady-state scroll paint
  drops from ~60 ms to ~0.5 ms because most widgets are cached
  composites
- `gridView`, `dropdown`, `icon` (search / cart / heart / star /
  chevron / check) replacing what used to be text-glyph hacks
- ValueNotifier-backed `cartStore`, `wishlistStore`,
  `ordersStore`, `signedInUser`. The header reactively updates
  ("Hello, sign in" vs "Hello, <name>") based on whichever store
  is observed via `listenableBuilder`
- `currentNavigator().push(proc(): Widget = X(), transition = trNone)`
  for instant navigation. Drop `transition = trNone` to get the
  default 250ms slide-in.
- `pageChrome(title, body)` helper that gives every secondary
  screen the same header / sub-nav / footer chrome

Run it:

```
nim c -d:release -o:bin/amazon examples/amazon/main.nim
bin/amazon
```

Then tap "See more" on a category card, the cart icon, "Hello,
sign in" - every clickable should route instantly.

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
5. `examples/notes/main.nim` (state, navigation, persistence)
6. `examples/amazon/main.nim` (a real-world-shaped app)
7. `src/flit/foundation/runtime.nim` (mount, rebuild, reconcile)
8. `src/flit/rendering/proxy_box.nim` (render-object templates)

## Next step

Read `10-api-reference.md` for how to generate and navigate the
generated API docs.
