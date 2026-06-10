# 02. Widgets

Everything in flit is a widget. Widgets are immutable configuration
objects; flit turns them into Elements (mounted instances) and Render
Objects (layout and paint).

## The three widget kinds

| Kind | Use when | Lifecycle | Example |
|------|----------|-----------|---------|
| `StatelessWidget` | Output depends only on inputs | Built fresh on every rebuild | `Container`, `Padding`, custom presentational widgets |
| `StatefulWidget` | Output depends on mutable state | `createState` once; `build` repeatedly; `dispose` on unmount | `Counter`, anything with `setState`, animations |
| `RenderObjectWidget` | You need direct control of layout or painting | `createRenderObject` once; `updateRenderObject` on rebuild | `Row`, `Column`, `Text`, custom render widgets |

There are also two helper kinds for tree shape, not new behavior:

| Kind | Purpose |
|------|---------|
| `ProxyWidget` | Wraps a single child to attach parent data (`Flexible`, `Positioned`) |
| `InheritedWidget` | Provides a value down the tree that descendants can subscribe to |

## StatelessWidget

Subclass and override `build`:

```nim
import flit

type
  Greeting = ref object of StatelessWidget
    name: string

method widgetTypeName(w: Greeting): string = "Greeting"
method createElement(w: Greeting): Element = newElement(ekStateless, w)
method build(w: Greeting, ctx: BuildContext): Widget =
  text("Hello, " & w.name & "!")

# Use it
when isMainModule:
  runApp(materialApp(home = scaffold(
    body = center(child = Greeting(name: "Atul")))))
```

`build` is called once on mount, and again whenever the parent rebuilds
and reconciliation gives this widget a fresh instance. Output must
depend only on the widget's own fields and the `BuildContext`.

## StatefulWidget

Subclass it, plus subclass `State`. flit wires them together via
`createState`:

```nim
import flit

type
  Toggle = ref object of StatefulWidget
  ToggleState = ref object of State
    on: bool

method widgetTypeName(w: Toggle): string = "Toggle"
method createElement(w: Toggle): Element = newElement(ekStateful, w)
method createState(w: Toggle): State = ToggleState(on: false)

method build(s: ToggleState, ctx: BuildContext): Widget =
  elevatedButton(
    child = text(if s.on: "ON" else: "OFF"),
    onPressed = proc() = setState(s, proc() = s.on = not s.on))
```

`setState(s, proc())` is the only way to change visible state. It runs
the closure (which mutates state fields) and then dirties the element so
the next frame rebuilds.

### State lifecycle

In order:

1. `createState()` once when the widget is first mounted.
2. `initState()` once after the state is attached to its element. Override
   to set up subscriptions, controllers, listeners.
3. `didChangeDependencies()` once after initState and again whenever an
   inherited widget the state depends on changes.
4. `build(ctx)` runs as many times as needed.
5. `didUpdateWidget(oldWidget)` whenever the parent rebuilds with a new
   instance of this widget type (you keep the State, just the config
   changes).
6. `dispose()` once when the element unmounts. Release controllers,
   listeners, timers here.

Don't call `setState` from inside `build`. flit raises a Defect if you
do, the same way Flutter does.

## RenderObjectWidget

When you need control over layout or painting, drop down to a render
widget. Two things to subclass: the widget (carries config) and the
render object (does the work).

```nim
import flit

type
  TinyBox = ref object of RenderObjectWidget
    color: Color

  RenderTinyBox = ref object of RenderObject
    fill: Color

method widgetTypeName(w: TinyBox): string = "TinyBox"
method createElement(w: TinyBox): Element = newElement(ekRender, w)
method createRenderObject(w: TinyBox, ctx: BuildContext): RenderObject =
  RenderTinyBox(fill: w.color)
method updateRenderObject(w: TinyBox, ctx: BuildContext, r: RenderObject) =
  RenderTinyBox(r).fill = w.color
  r.markNeedsPaint()

method performLayout(r: RenderTinyBox) =
  # Be a 32x32 box.
  r.setSize(r.constraints.constrain(Size(width: 32, height: 32)))

method paint(r: RenderTinyBox, ctx: PaintingContext, offset: Offset) =
  ctx.canvas.drawRect(rectFromOffsetSize(offset, r.size), r.fill.value)
```

Use it the same way as any other widget. See `src/flit/rendering/`
for the built-in render objects you can study as templates.

## Keys

Two children of the same parent that have the same key keep their state
across reorders. Without keys, reconciliation matches by position only,
which means dragging a stateful widget to a new position resets its
state.

```nim
column(children = @[
  todoItem(text = "Buy milk",  key = ValueKey(1)),
  todoItem(text = "Pay bills", key = ValueKey(2)),
  todoItem(text = "Call mom",  key = ValueKey(3)),
])
```

Reordering this list (say, by dragging) preserves each row's internal
state because the keys travel with the widgets.

Available key kinds:

- `ValueKey(v)`: any hashable value. Use for stable IDs.
- `UniqueKey()`: a fresh, never-equal-to-anything-else key. Use when
  you want to force re-creation.
- `ObjectKey(obj)`: identity by Nim ref. Use when an object IS the
  identity.
- `GlobalKey()`: a key whose identity is stable across the entire app.
  Used in advanced scenarios (cross-tree state sharing).

## Built-in widget reference (added in 0.11.x)

A few widgets added in the 0.11 series that round out a typical
app's UI:

| Widget | Where | Purpose |
|---|---|---|
| `gridView(children, crossAxisCount, ...)` | `widgets/basic.nim` | Fixed N-column grid. Pass any number of children; they wrap to a new row every `crossAxisCount`. |
| `icon(name, size, color)` | `widgets/icon.nim` | Vector glyphs drawn through `Canvas.fillPolygon`. Built-in names: `search`, `cart`, `star`, `chevron.{up,down,left,right}`, `close`, `menu`, `heart`, `check`, `plus`, `minus`. |
| `dropdown[T](items, value, onChange, displayBuilder, width)` | `widgets/dropdown.nim` | Generic select. Tap to open a panel of `items`; tap an option to fire `onChange(v)`. |
| `networkImage(url, width, height, fit, placeholderColor)` | `widgets/network_image.nim` | Fetches an image over HTTP in a background worker, caches per URL, blits when bytes arrive. Subscribes only to its own URL's notifier so unrelated images don't rebuild it. |
| `repaintBoundary(child)` | `widgets/basic.nim` | Caches the rasterized output of `child` in a sub-canvas. Composite on subsequent paints is a single GPU blit. Use on static-shape subtrees inside a scrolling list (product cards, list rows, hero banners) to avoid re-rasterizing on every scroll frame. See `07-performance.md`. |
| `newScrollController()` + `scrollView(controller = sc)` | `rendering/viewport.nim` | Programmatic scrolling. `sc.scrollToEnd()` applies after the next layout pass, so calling it in the same setState that appends content lands on the new end (the chat stick-to-latest pattern). Also `jumpTo(px)`, `offset`, `atEnd`. |

### Example: a 3-column product grid

```nim
gridView(
  crossAxisCount = 3,
  crossAxisSpacing = 12,
  mainAxisSpacing = 12,
  children = products.mapIt(Widget(productCard(it))))
```

### Example: an icon button

```nim
gestureDetector(onTap = openCart,
  child = container(
    width = 40, height = 40,
    hasDecoration = true,
    decoration = boxDecoration(color = amazonOrange, borderRadius = 20),
    child = center(child = icon("cart", size = 22, color = colorWhite))))
```

### Example: a dropdown bound to a ValueNotifier

```nim
let sortBy = newValueNotifier[string]("Featured")

dropdown[string](
  items = @["Featured", "Price: Low to High",
            "Price: High to Low", "Avg. Customer Review"],
  value = sortBy.value,
  onChange = proc(v: string) = sortBy.value = v,
  width = 200)
```

### Example: a network image with placeholder

```nim
networkImage(url = product.imageUrl,
             width = 200, height = 200,
             fit = ifCover,
             placeholderColor = rgb(228, 230, 235))
```

## Next step

Read `03-layout.md` to learn how widgets size and position themselves.
