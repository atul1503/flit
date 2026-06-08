# flit

A Flutter-inspired cross-platform UI toolkit for Nim. Write your UI in idiomatic, declarative Nim once; ship the same codebase to macOS, Linux, Windows, iOS, Android, the web, and embedded Linux.

```
                                  +-------------+
                                  |   flit app  |
                                  +------+------+
              +--------+--------+--------+--------+--------+
              |        |        |                 |        |
            macOS    Linux   Windows  iOS  Android  Web  Embedded
              |        |        |     |     |       |       |
                  SDL2 + Pixie               JS canvas    framebuffer
```

## Highlights

- Three-tree architecture: Widget (config), Element (instance), RenderObject (layout and paint), exactly like Flutter.
- Declarative composition: `column(children = @[...])`, `row(...)`, `padding(...)`, `center(...)`, `stack(...)`.
- Stateful widgets with `setState`, mount/unmount lifecycle, didChangeDependencies, dispose.
- Constraint-based layout with `Constraints`, `tightFor`, `loosen`, `deflate`, flex children, positioned children.
- Material 3 (`materialApp`, `scaffold`, `appBar`, `elevatedButton`, `card`, `floatingActionButton`) and Cupertino (`cupertinoApp`, `cupertinoNavigationBar`, `cupertinoButton`) widget libraries.
- Hot reload via `flit hot` (file watcher + restart). Inspector via `debugDescribe(root)`.
- Animation primitives: `AnimationController`, `Tween`, curves (`curveEaseInOut`, `curveBounceOut`, etc.).
- Gestures: `gestureDetector` with onTap, onPanStart/Update/End, onLongPress.
- A `flit` CLI that mirrors `flutter`: `flit create`, `flit run`, `flit build apk|ipa|web|macos|linux|windows`, `flit doctor`, `flit devices`.

## Hello, counter

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
    appBar = appBar(title = text("flit demo")),
    body = center(child = column(mainAxisAlignment = maCenter, children = @[
      Widget(text("You pressed the button:")),
      text($s.count, style = textStyle(fontSize: 48))])),
    floatingActionButton = floatingActionButton(
      child = text("+", style = textStyle(fontSize: 28, color: colorWhite)),
      onPressed = proc() = setState(s, proc() = inc s.count))))

when isMainModule: runApp(Counter())
```

Build and run for the host:

```
nimble install
nim c -d:release -r examples/counter/main.nim
```

Or, with the CLI:

```
flit create my_app
cd my_app
flit run
```

## Targets

| Target  | Backend            | Command                                            |
|---------|--------------------|----------------------------------------------------|
| macOS   | SDL2 + Pixie       | `flit build macos`                                 |
| Linux   | SDL2 + Pixie       | `flit build linux`                                 |
| Windows | SDL2 + Pixie       | `flit build windows`                               |
| iOS     | SDL2 (mobile)      | `flit build ipa`                                   |
| Android | SDL2 (mobile)      | `flit build apk`                                   |
| Web     | HTMLCanvas (nim js)| `flit build web`                                   |
| Embed   | framebuffer        | `nim c -d:flitPlatform=embedded examples/embed.nim`|

## Project layout

```
flit/
  src/flit.nim                 top-level umbrella import
  src/flit/
    foundation/                Key, Widget, Element, RenderObject, geometry, color
    rendering/                 RenderProxyBox, RenderFlex, RenderStack, RenderDecoratedBox,
                               text, canvas backends
    widgets/basic.nim          Container, Row, Column, Stack, Text, Padding, Align, ...
    material/                  MaterialApp, Scaffold, AppBar, ElevatedButton, Card, ...
    cupertino/                 CupertinoApp, CupertinoNavigationBar, CupertinoButton
    gestures/                  GestureDetector
    animation/                 AnimationController, Tween, curves, Ticker
    platform/                  desktop/, web/, mobile/, embedded/ runners
    app.nim                    runApp(widget)
  cli/src/flit_cli.nim         the `flit` command-line tool
  examples/                    counter, gallery, todo, calculator, showcase
  tests/                       layout, widgets, state, painting
  docs/                        ARCHITECTURE.md, getting_started.md
```

## The showcase example

`examples/showcase/main.nim` is the broad sampler. Six tabs:

- **Home**: stateful counter, two button styles, light/dark toggle.
- **Layout**: every MainAxisAlignment value in a row, Expanded with flex weights, Stack + Positioned with a circle overlay.
- **Style**: solid, rounded, circular, bordered and shadowed boxes; four border radii; four EdgeInsets variants; TextStyle variations.
- **Inputs**: ElevatedButton + TextButton + FloatingActionButton, a draggable puck (`onPanUpdate`), and a press-and-hold charge bar (`onPanStart` / `onPanUpdate` / `onPanEnd`).
- **Anim**: pick from six curves (linear, easeIn, easeOut, easeInOut, bounceOut, elasticIn), then drive a Tween via an AnimationController.
- **Cupertino**: a CupertinoNavigationBar plus filled and plain CupertinoButtons living inside the same Material shell.

Run it:

```
nim c -d:release -o:bin/showcase examples/showcase/main.nim
./bin/showcase    # mac users may need DYLD_LIBRARY_PATH=/opt/homebrew/lib
```

## Status

0.2.0 adds the showcase example. 0.1.0 was the initial slice: full widget framework, layout, painting, the Material/Cupertino starter libraries, all five backends, and the CLI. Not yet shipped: text editing, scroll views, image decoding, accessibility tree, true hot patching (today's `flit hot` restarts the process). PRs welcome.

## License

BSD-3-Clause.
