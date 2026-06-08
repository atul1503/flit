# 01. Quickstart

Five minutes from zero to a running counter app.

## Install

flit needs Nim 2.0+, SDL2, and (for the GPU canvas) HarfBuzz and an OpenGL
driver. On macOS:

```
brew install nim sdl2 harfbuzz
```

On Debian or Ubuntu:

```
sudo apt install nim libsdl2-dev libharfbuzz-dev
```

Then install flit itself from the local checkout:

```
cd /Users/attripathi/flit
nimble install
```

`nimble install` also installs the `flit` CLI binary.

## Your first app

Create a directory and an app file:

```
mkdir hello_flit && cd hello_flit
```

`hello.nim`:

```nim
import flit

type
  Counter = ref object of StatefulWidget
  CounterState = ref object of State
    count: int

method widgetTypeName(w: Counter): string = "Counter"
method createElement(w: Counter): Element = newElement(ekStateful, w)
method createState(w: Counter): State = CounterState(count: 0)
method build(s: CounterState, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(title = text("Hello flit")),
    body = center(child = column(mainAxisAlignment = maCenter, children = @[
      Widget(text("You tapped " & $s.count & " times.")),
      elevatedButton(
        child = text("Tap me"),
        onPressed = proc() = setState(s, proc() = inc s.count))])))

when isMainModule:
  runApp(Counter())
```

Run it:

```
nim c -r hello.nim
```

A window opens. Click the button; the counter increments.

## What just happened

Three things to notice:

1. `Counter` is a `StatefulWidget`. flit creates an `Element` for it
   (via `createElement`) and a `State` (via `createState`).
2. `build` returns a fresh widget tree on every rebuild. It is called
   once on mount and again every time `setState` runs.
3. `setState(s, proc() = inc s.count)` runs the closure (which mutates
   state), then marks the element dirty. The runtime walks dirty elements
   on the next frame and calls `build` again. The widget tree is
   reconciled against the previous tree to find what to update.

You did not write any rendering code. flit picked the SDL2 desktop runner
because you called `runApp` from a desktop binary.

## Switching to the flit CLI

Instead of `nim c -r` directly, use the project scaffold:

```
flit create my_app
cd my_app
flit run
```

`flit create` lays down the same kind of file plus a `.nimble`, a
`web/index.html`, and a `.gitignore`. `flit run` does the compile-and-run
for the current platform. See `08-cli.md` for the full command list.

## Next step

Read `02-widgets.md` to understand the three widget kinds and when to use
each.
