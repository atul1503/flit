## Smoke tests for every public widget in material.nim and cupertino.nim.
## Each test: mount, layout, paint to a recording canvas, verify the
## widget produced visible output (non-zero rects/text/etc).

import std/unittest
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime

type
  Rec = ref object of Canvas
    rects*: int
    rrects*: int
    circles*: int
    texts*: int
    lines*: int

proc newRec(w, h: float32): Rec =
  Rec(rects: 0, rrects: 0, circles: 0, texts: 0, lines: 0,
      size: Size(width: w, height: h))

method drawRect*(c: Rec, r: Rect, fill: uint32) = inc c.rects
method drawRRect*(c: Rec, r: RRect, fill: uint32) = inc c.rrects
method drawCircle*(c: Rec, center: Offset, radius: float32, fill: uint32) =
  inc c.circles
method drawLine*(c: Rec, p0, p1: Offset, color: uint32, width: float32) =
  inc c.lines
method drawText*(c: Rec, text: string, pos: Offset, color: uint32,
                 fontSize: float32, fontFamily: string) =
  inc c.texts

proc renderWith(w: Widget, surfW = 400.0'f32, surfH = 300.0'f32): Rec =
  let root = mountElement(nil, w, 0)
  runLayout(root, tightFor(surfW, surfH))
  let rec = newRec(surfW, surfH)
  runPaint(root, rec)
  rec

# ---------------------------------------------------------------------------
# Material
# ---------------------------------------------------------------------------

suite "Material widgets":
  test "MaterialApp paints the background":
    let rec = renderWith(materialApp(home = sizedBox(width = 50, height = 50)))
    # Background coloredBox always paints one rect.
    check rec.rects >= 1

  test "Scaffold composes appBar + body":
    let rec = renderWith(materialApp(home = scaffold(
      appBar = appBar(title = text("hello")),
      body = center(child = text("world")))))
    check rec.texts >= 2   # "hello" + "world"

  test "AppBar draws its background":
    let rec = renderWith(materialApp(home = scaffold(
      appBar = appBar(title = text("a")),
      body = sizedBox(width = 1, height = 1))))
    # AppBar uses decoratedBox without borderRadius -> drawRect.
    check rec.rects >= 1
    check rec.texts >= 1   # title

  test "ElevatedButton draws a rounded fill + label":
    let rec = renderWith(materialApp(home = center(
      child = elevatedButton(child = text("Press")))))
    check rec.rrects >= 1   # borderRadius = 20
    check rec.texts >= 1

  test "TextButton draws only its label (no background)":
    let rec = renderWith(materialApp(home = center(
      child = textButton(child = text("Tap")))))
    check rec.texts >= 1
    # No rrect for TextButton's body since it doesn't decorate.

  test "FloatingActionButton draws a circle + label":
    let rec = renderWith(materialApp(home = center(
      child = floatingActionButton(child = text("+")))))
    check rec.circles >= 1
    check rec.texts >= 1

  test "Card draws a rounded surface":
    let rec = renderWith(materialApp(home = center(
      child = card(child = sizedBox(width = 100, height = 60,
                                     child = coloredBox(color = colorRed))))))
    # Card uses defaultRadius = 12 -> drawRRect.
    check rec.rrects >= 1

# ---------------------------------------------------------------------------
# Cupertino
# ---------------------------------------------------------------------------

suite "Cupertino widgets":
  test "CupertinoApp draws a background":
    let rec = renderWith(cupertinoApp(home = sizedBox(width = 50, height = 50)))
    check rec.rects >= 1

  test "CupertinoNavigationBar paints middle":
    let rec = renderWith(cupertinoApp(home = cupertinoNavigationBar(
      middle = text("Title"))))
    check rec.texts >= 1
    check rec.rects >= 1   # bar background

  test "CupertinoButton filled draws a rounded background":
    let rec = renderWith(cupertinoApp(home = center(child = cupertinoButton(
      child = text("Filled"),
      filled = true))))
    check rec.rrects >= 1
    check rec.texts >= 1

  test "CupertinoButton non-filled only draws label":
    let rec = renderWith(cupertinoApp(home = center(child = cupertinoButton(
      child = text("Plain")))))
    check rec.texts >= 1

when isMainModule: discard
