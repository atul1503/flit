# Getting started with flit

## Install

```
git clone https://github.com/<you>/flit.git
cd flit
nimble install
```

This installs the `flit` library and the `flit_cli` binary. Add `~/.nimble/bin` to your PATH if it isn't already.

## Create an app

```
flit create hello
cd hello
flit run
```

A native window opens with a counter button.

## Build for a specific platform

```
flit build macos          # bin/hello (Mach-O)
flit build linux          # bin/hello (ELF)
flit build windows        # bin/hello.exe (cross-compile via mingw)
flit build web            # web/app.js (open web/index.html in a browser)
flit build apk            # build/android/libhello.so
flit build ipa            # build/ios/hello
```

## The widget catalogue (so far)

### Layout
- `container(child, width, height, color, padding, margin, decoration, alignment)`
- `padding(child, padding)`
- `center(child)` / `align(child, alignment)`
- `sizedBox(child, width, height)`
- `constrainedBox(child, boxConstraints)`
- `row(children, mainAxisAlignment, crossAxisAlignment, mainAxisSize)`
- `column(...)`
- `stack(children, alignment, fit)` plus `positioned(child, left, top, right, bottom, width, height)`
- `expanded(child, flex)` / `flexible(child, flex, fit)`

### Painting
- `text(data, style, textAlign, softWrap, maxLines)`
- `coloredBox(child, color)`
- `decoratedBox(child, decoration)` with `boxDecoration(color, borderRadius, border, shape, shadows)`

### Material
- `materialApp(home, theme, title)`
- `scaffold(body, appBar, floatingActionButton, backgroundColor)`
- `appBar(title, actions, backgroundColor)`
- `elevatedButton(child, onPressed)` / `textButton(child, onPressed)`
- `card(child, elevation, margin)`
- `floatingActionButton(child, onPressed)`

### Cupertino
- `cupertinoApp(home, theme)`
- `cupertinoNavigationBar(middle, leading, trailing)`
- `cupertinoButton(child, onPressed, filled)`

### Gestures
- `gestureDetector(child, onTap, onDoubleTap, onLongPress, onPanStart, onPanUpdate, onPanEnd)`

### Animation
- `newAnimationController(durationSec)` -> `.forward(binding, curveEaseInOut)` / `.reverse(...)`
- `tween[T](begin, end).evaluate(controller)` for any interpolable T

## Inspecting the tree

```nim
import flit
let root = mountElement(nil, myWidget, 0)
echo prettyPrint(debugDescribe(root))
```

## Theming

```nim
materialApp(theme = themeData(bDark, fontFamily = "Inter"), home = ...)
```

Tokens live on `ThemeData.colorScheme` and `ThemeData.typography`. Light and dark schemes ship out of the box.
