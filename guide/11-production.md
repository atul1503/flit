# 11. Production-readiness

What 0.9.0 added to close production-readiness gaps, what you get
out of the box, and the honest limits.

## TextField: clipboard, undo, redo

Standard shortcuts work out of the box. SDL2's clipboard backs
them; nothing to wire.

| Shortcut | Effect |
|----------|--------|
| Cmd/Ctrl+C | Copy selection to clipboard |
| Cmd/Ctrl+X | Cut selection (copy + delete) |
| Cmd/Ctrl+V | Paste at cursor |
| Cmd/Ctrl+A | Select all |
| Cmd/Ctrl+Z | Undo |
| Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y | Redo |

The undo history is capped at 256 entries. New edits clear the
redo branch (so undo + new edit + redo doesn't replay the
abandoned branch).

For programmatic access:

```nim
let c = newTextEditingController("hello")
c.cursor = 5
c.insertText(" world", 0)
echo c.text  # "hello world"
discard c.undo()
echo c.text  # "hello"
discard c.redo()
echo c.text  # "hello world"

# Selection / copy
c.selectAll()
let selected = c.copyToString()
```

## Animated Navigator transitions

`Navigator.push` accepts a `transition` parameter:

```nim
currentNavigator().push(
  proc(): Widget = detailScreen(),
  transition = trSlideLeft)
```

Options:

| Kind | Effect |
|------|--------|
| `trNone` | No animation; instant |
| `trFade` | Fade from 0 to 1 over 200ms |
| `trSlideLeft` | Slide in from the right (iOS-style push) |
| `trSlideRight` | Slide in from the left |
| `trSlideUp` | Slide in from below (modal sheet) |
| `trSlideDown` | Slide in from above |
| `trScale` | Scale from 85% to 100% with ease-out |

For custom transitions, wrap the route in any widget that animates
on mount. `widgets/transitions.nim` shows the pattern (a
StatefulWidget that owns an `AnimationController`, runs forward in
`initState`, applies the transform in `build`).

The default if you omit `transition` is `trSlideLeft`. Pass
`trNone` for non-visual screen swaps (settings dialogs, anywhere
the animation feels wrong).

## Accessibility semantics

The `Semantics` widget annotates its subtree:

```nim
semantics(
  role = srButton,
  label = "Delete this note",
  hint = "Removes the note permanently",
  actions = {saTap},
  onAction = proc(a: SemanticsAction) =
    deleteNote(),
  child = elevatedButton(
    child = text("Delete"),
    onPressed = proc() = deleteNote()))
```

Roles flit knows about: `srNone`, `srButton`, `srLink`,
`srTextField`, `srCheckbox`, `srRadio`, `srImage`, `srHeading`,
`srList`, `srListItem`, `srTab`, `srTabList`, `srSlider`,
`srProgressBar`, `srSearchBox`, `srStatic`.

Actions: `saTap`, `saLongPress`, `saIncrement`, `saDecrement`,
`saScrollUp`, `saScrollDown`, `saScrollLeft`, `saScrollRight`,
`saDismiss`.

To extract the tree as data:

```nim
let nodes = buildSemanticsTree(root)
echo toJson(nodes)
```

This produces a flat JSON array your tests, audit tools, or
accessibility-bridge code can consume.

**Limit:** flit does NOT yet bridge the semantics tree to the OS
(NSAccessibility on macOS, AT-SPI on Linux, UIAutomation on
Windows). Wiring those is a per-platform project; the data is
already shaped correctly for them. PRs welcome.

## What production-ready actually means

Three independent dimensions:

1. **Technical completeness**: do the primitives exist to build
   a real app? **Yes as of 0.9.0**. TextField with editing,
   Navigator with transitions, Form with validation, Image,
   accessibility hooks, CI on three OSes.
2. **Battle-testing**: have real apps been shipped with it?
   **No.** Only the demo apps in `examples/`. Bugs you find at
   10,000 users are different from bugs you find at zero.
3. **Ecosystem**: is there a community to find bugs, contribute
   widgets, write tutorials? **No.** flit is one person's
   project today.

Use flit for personal projects, internal tools, prototypes,
hobby apps. For customer-facing production, watch the repo and
wait for the project to gather real-world usage signals.

## The notes example

`examples/notes/main.nim` is a complete app that exercises the
entire 0.9.0 surface. Read it after this guide; it shows how the
pieces compose:

- A `ValueNotifier[seq[Note]]` as the data store
- `listenableBuilder` watching it
- `ListView.builder` rendering the list
- `Navigator.push(transition = trSlideLeft)` for detail screen
- `TextField` with controller for edit
- `Form` validation via the title field
- `Semantics` annotations on every interactive widget
- JSON persistence
- `InheritedWidget` for light / dark theme

Run it:

```
nim c -r examples/notes/main.nim
```

The notes file lives at `/tmp/flit_notes.json`. Delete it to start
fresh.
