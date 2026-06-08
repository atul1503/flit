# 04. State management

Three tools, three different scopes:

| Tool | Scope | Triggers rebuild of |
|------|-------|---------------------|
| `setState` | This widget only | The calling element |
| `ValueNotifier` + `ListenableBuilder` | Anywhere; explicit subscription | Only the watching ListenableBuilder |
| `InheritedWidget` + `dependOnInheritedOfType` | Anywhere down the tree; auto subscription | Every descendant that called `dependOnInheritedOfType` |

Pick the smallest tool that does the job.

## setState

Local mutable state inside a single `StatefulWidget`:

```nim
type
  CounterState = ref object of State
    count: int

method build(s: CounterState, ctx: BuildContext): Widget =
  elevatedButton(
    child = text($s.count),
    onPressed = proc() = setState(s, proc() = inc s.count))
```

`setState` runs the closure (which mutates state) and dirties the
element. The next frame rebuilds this widget and its descendants. Use
this for state that only one widget cares about: scroll offset, toggle
state, hover state, the contents of a text field.

Never call `setState` from `build`. It would recurse forever; flit
raises a Defect instead.

## ValueNotifier and ListenableBuilder

When state is shared across widgets that may be far apart in the tree:

```nim
import flit

# Module-level so multiple widgets can reference it.
let cartCount = newValueNotifier(0)

# Anywhere: read or change the value.
proc addToCart() = cartCount.value = cartCount.value + 1

# In a widget tree: subscribe.
listenableBuilder(cartCount, proc(ctx: BuildContext, value: int): Widget =
  text("Items: " & $value))
```

The builder closure runs once on mount and again every time
`cartCount.value` changes. Only this `ListenableBuilder` rebuilds, not
the rest of the tree.

### Custom equality

Notifications fire when the new value is not equal to the old. The
default comparison is `==`. For ref types or when you want to override:

```nim
type User = ref object
  name: string

let activeUser = newValueNotifier[User](
  initial = User(name: "Atul"),
  equals = proc(a, b: User): bool = a.name == b.name)
```

A notifier with custom equality only fires when `equals(new, old)`
returns false.

### Notify without changing the value

When the underlying data is a mutable object and you mutate it in place:

```nim
type Cart = ref object
  items: seq[string]

let cart = newValueNotifier(Cart(items: @[]))

proc addItem(name: string) =
  cart.value.items.add(name)
  cart.notify()           # value reference is the same; force notify
```

`notify()` fires listeners regardless of equality.

### Disposal

`ValueNotifier.dispose()` drops every listener. `ListenableBuilder` calls
`removeListener` automatically when its state's `dispose` runs.

Module-level notifiers usually live as long as the app, so disposal
rarely matters. Notifiers owned by a `State` should be disposed in the
state's `dispose` method.

## InheritedWidget

Provides a value to an entire subtree without explicit prop drilling.
Descendants subscribe by calling `dependOnInheritedOfType[T]`:

```nim
import flit

type
  AppTheme = ref object of InheritedWidget
    primaryColor: Color

method widgetTypeName(w: AppTheme): string = "AppTheme"
method createElement(w: AppTheme): Element = newElement(ekInherited, w)
method updateShouldNotify(new, old: AppTheme): bool =
  new.primaryColor != old.primaryColor

proc appTheme(primaryColor: Color, child: Widget): AppTheme =
  AppTheme(child: child, primaryColor: primaryColor)

# Somewhere deep in the tree:
type
  ThemedButton = ref object of StatelessWidget
    label: string

method build(w: ThemedButton, ctx: BuildContext): Widget =
  let theme = dependOnInheritedOfType[AppTheme](ctx)
  let color = if theme.isNil: colorBlue else: theme.primaryColor
  elevatedButton(
    child = text(w.label),
    onPressed = proc() = discard)  # color logic goes in your button

# Wrap your app:
runApp(appTheme(primaryColor = colorTeal,
  child = materialApp(home = scaffold(
    body = ThemedButton(label = "OK")))))
```

`updateShouldNotify(new, old)` decides whether to dirty the dependents.
Return false when the value changed but the change should not trigger
rebuilds (rare). Return true when the change matters.

`dependOnInheritedOfType[T](ctx)` does two things:

1. Walks up the element tree from `ctx` looking for the nearest ancestor
   of type `T`.
2. Registers the calling element as a dependent so the next time `T`
   reports `updateShouldNotify == true`, this element rebuilds.

If no matching ancestor exists, returns `nil`. Always check.

## Combining the three

A common pattern: one ValueNotifier per "store", exposed via an
InheritedWidget so descendants don't have to import the notifier
directly.

```nim
type
  CartStore = ref object of InheritedWidget
    notifier: ValueNotifier[int]

method updateShouldNotify(new, old: CartStore): bool = false
# notifier identity stays the same; rebuild is driven by ListenableBuilder

# Wrap the app:
let cart = newValueNotifier(0)
runApp(CartStore(notifier: cart, child = materialApp(home = ...)))

# In a deeply nested widget:
method build(w: SomeWidget, ctx: BuildContext): Widget =
  let store = dependOnInheritedOfType[CartStore](ctx)
  listenableBuilder(store.notifier, proc(_, count): Widget =
    text("Cart: " & $count))
```

This gives you Flutter's "Provider" pattern without a third-party
package.

## Next step

Read `05-gestures.md` for input handling.
