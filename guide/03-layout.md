# 03. Layout

flit's layout model is identical to Flutter's: constraints flow down,
sizes flow up. Read that sentence twice. It is the single most important
thing about layout in this framework.

## Constraints flow down, sizes flow up

The parent asks the child: "given these constraints (min and max width
and height), how big do you want to be?" The child picks a size within
those constraints and reports it back. The parent then positions the
child within its own area.

```
parent.layout(c) {
  for each child:
    child.constraints = derive from c          # constraints flow down
    child.size = child.computeSize()           # sizes flow up
    child.offset = derive from c               # parent positions child
  self.size = derive from children's sizes
}
```

Every render object's `performLayout` follows this pattern.

## Constraints

`Constraints` is a struct of four floats:

```nim
Constraints(minWidth: 0, maxWidth: 400, minHeight: 0, maxHeight: 600)
```

Three useful constructors:

```nim
tightFor(width, height)         # min == max for both axes
constraints(minW, maxW, minH, maxH)
Constraints()                    # zero, zero, zero, zero
```

"Tight" means min equals max; the child has no choice. "Loose" means min
is zero; the child can be smaller than max.

## Container

The swiss-army knife. Composes margin, decoration, constrained size,
padding, alignment, and a child in that order:

```nim
container(
  margin = edgeInsetsAll(8),
  padding = edgeInsetsAll(16),
  hasDecoration = true,
  decoration = boxDecoration(
    color = colorBlue,
    borderRadius = 8,
    border = border(width = 2, color = colorBlack)),
  hasAlignment = true,
  alignment = alignCenter,
  width = 200, height = 100,
  child = text("Hi"))
```

Use `hasAlignment`, `hasColor`, `hasDecoration` flags because their
zero values are real colors and alignments, not "unset".

## Sizing widgets

| Widget | Effect |
|--------|--------|
| `sizedBox(width, height, child)` | Forces a specific size, or acts as a spacer when no child |
| `constrainedBox(child, boxConstraints)` | Adds extra constraints on top of the parent's |
| `aspectRatio(child, ratio)` | Sizes child to width/height = ratio |
| `padding(child, padding)` | Insets the child by EdgeInsets |
| `align(child, alignment)` | Positions child within itself |
| `center(child)` | Shortcut for `align(alignment = alignCenter)` |

```nim
# 100x50 red rectangle, centered in its parent
center(child = sizedBox(width = 100, height = 50,
  child = coloredBox(color = colorRed)))
```

## Flex layout: Row and Column

`Row` and `Column` are flex containers. Children get laid out along the
main axis (horizontal for Row, vertical for Column), with cross-axis
alignment perpendicular.

### Basic row

```nim
row(children = @[
  text("left"),
  text("middle"),
  text("right"),
])
```

Default `mainAxisAlignment` is `maStart` (pack to the start), default
`crossAxisAlignment` is `caCenter`.

### Alignment options

`mainAxisAlignment`:

| Value | Effect |
|-------|--------|
| `maStart` | Pack to the start |
| `maEnd` | Pack to the end |
| `maCenter` | Center as a group |
| `maSpaceBetween` | Gaps between, none at ends |
| `maSpaceAround` | Half-gaps at ends |
| `maSpaceEvenly` | Equal gaps including at ends |

`crossAxisAlignment`:

| Value | Effect |
|-------|--------|
| `caStart` | Top (Row) or left (Column) |
| `caEnd` | Bottom (Row) or right (Column) |
| `caCenter` | Center cross-axis |
| `caStretch` | Fill the cross axis (tight constraint) |
| `caBaseline` | Align text baselines |

### Flex children

Wrap a child in `expanded` or `flexible` to give it a slice of the
remaining main-axis space:

```nim
row(children = @[
  text("fixed"),
  expanded(child = sizedBox(child = coloredBox(color = colorBlue)), flex = 1),
  expanded(child = sizedBox(child = coloredBox(color = colorRed)), flex = 2),
])
```

`expanded` is tight fit (child fills exactly). `flexible` is loose fit
(child gets the max but can be smaller).

If `flex = 1` and `flex = 2`, the second child gets twice the remaining
space.

### MainAxisSize

`msMax` (default): the flex container fills the parent's main-axis
extent. `msMin`: shrink-wraps the children. Use `msMin` for inner
columns inside cards or inside scrollable content; otherwise they will
eat all available height.

## Stack: layered layout

For absolute positioning:

```nim
stack(children = @[
  # background
  coloredBox(color = colorBlue),
  # absolutely positioned label
  positioned(
    top = 10, right = 10,
    child = container(
      padding = edgeInsetsAll(4),
      hasColor = true, color = colorWhite,
      child = text("badge"))),
])
```

Non-`positioned` children align by the stack's `alignment` parameter.
`positioned` children get absolute offsets from any combination of
`left`, `top`, `right`, `bottom`, `width`, `height`. Unspecified sides
default to `unsetF`.

Painting order: index 0 paints first (background), later children paint
on top. Hit testing is the reverse (top child catches events first).

## ScrollView

Wrap content that may exceed its viewport:

```nim
scrollView(direction = axVertical, child = column(children = manyRows))
```

The viewport handles scroll wheel events and clips content. For very
long lists, use `listViewBuilder` instead (see `07-performance.md`).

## Putting it together

A typical app layout:

```nim
method build(s: HomeState, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(title = text("Inbox")),
    body = scrollView(child = column(mainAxisSize = msMin, children = @[
      container(
        padding = edgeInsetsAll(16),
        child = row(children = @[
          expanded(child = text("Important")),
          text("3 new"),
        ])),
      # ... rows ...
    ])),
    floatingActionButton = floatingActionButton(
      child = text("+"),
      onPressed = proc() = discard)))
```

## Debugging layout

When something looks wrong, dump the render tree. `tests/debug_dump.nim`
in the repo walks the tree and prints type, size, offset for each render
object. Copy the pattern when you need to inspect a live layout.

For visual debugging without a window, write to PNG via the embedded
canvas; `tests/dump_frame.nim` does this for the showcase.

## Next step

Read `04-state.md` for state management beyond `setState`.
