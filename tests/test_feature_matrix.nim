## Pairwise feature-combination tests. Every framework bug found
## during the 0.11.x app probes lived in the interaction zone
## between two features that each worked alone:
##
## - bitmap caches x transform widgets (0.11.9, 0.12.x)
## - repaint boundaries x dirty-mark propagation (0.11.5)
## - scroll events x repaint pipeline (0.11.0)
##
## This file exercises those pairs mechanically on the embedded
## canvas so regressions fail in CI instead of in a user's app.

import std/[unittest, os]
import pixie except Rect, rect
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/foundation/binding
import ../src/flit/platform/embedded/runner as embed
import ../src/flit/rendering/text as flitText
import ../src/flit/rendering/bundled_font

# Deterministic font: the bundled Roboto, never the host system's.
embed.embeddedFont = bundledFont(14)
flitText.measureText = flitText.wrapMeasureWithCache(
  proc(s: string, style: TextStyle): Size =
    let f = embed.embeddedFont
    f.size = style.fontSize
    let b = pixie.typeset(f, s).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height)))

const W = 400
const H = 200
const BG = 0xFF101010'u32

proc render(w: Widget): EmbeddedCanvas =
  ## Mounts `w`, lays out at WxH, paints onto a fresh canvas.
  result = newEmbeddedCanvas(W, H)
  let root = mountElement(nil, w, 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  result.clear(BG)
  runPaint(root, result)

proc paintedBounds(c: EmbeddedCanvas): tuple[minX, minY, maxX, maxY: int] =
  ## Bounding box of every pixel that differs from the background.
  result = (W, H, -1, -1)
  let px = cast[ptr UncheckedArray[uint32]](addr c.image.data[0])
  for y in 0 ..< H:
    for x in 0 ..< W:
      # Pixie stores RGBA; background BG is ARGB 0xFF101010 which
      # round-trips to a stable value. Compare against the corner
      # pixel (guaranteed background in these scenes).
      if px[y * W + x] != px[0]:
        if x < result.minX: result.minX = x
        if y < result.minY: result.minY = y
        if x > result.maxX: result.maxX = x
        if y > result.maxY: result.maxY = y

proc hasPaint(c: EmbeddedCanvas): bool =
  paintedBounds(c).maxX >= 0

suite "transform x primitives":
  # The widget under test sits in the top-left at its natural
  # position. The transform translates it +150px right. If the
  # primitive's draw path ignores the canvas transform (the cached
  # bitmap-blit bug), the paint lands at x < 150 and the test fails.

  test "transform(translation) x text":
    let c = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(translation = Offset(dx: 150, dy: 0),
          child = text("Shifted",
            style = textStyle(fontSize = 20, color = colorWhite)))),
      ]))
    let b = paintedBounds(c)
    check b.maxX >= 0          # something painted
    check b.minX >= 145        # ...and it painted at the SHIFTED position

  test "transform(translation) x rounded rect":
    let c = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(translation = Offset(dx: 150, dy: 0),
          child = container(width = 40, height = 40,
            hasDecoration = true,
            decoration = boxDecoration(color = colorRed, borderRadius = 8)))),
      ]))
    let b = paintedBounds(c)
    check b.maxX >= 0
    check b.minX >= 145

  test "transform(translation) x icon":
    let c = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(translation = Offset(dx: 150, dy: 0),
          child = icon("star", size = 32, color = colorYellow))),
      ]))
    let b = paintedBounds(c)
    check b.maxX >= 0
    check b.minX >= 145

  test "transform(translation) x plain rect":
    let c = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(translation = Offset(dx: 150, dy: 0),
          child = container(width = 40, height = 40,
            hasColor = true, color = colorBlue))),
      ]))
    let b = paintedBounds(c)
    check b.maxX >= 0
    check b.minX >= 145

  test "transform(scale) x text shrinks the painted extent":
    # Full-size text first, measure its width; then 0.5x scaled
    # text must paint a strictly smaller extent.
    let cFull = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(text("MEASURE ME WIDE",
          style = textStyle(fontSize = 24, color = colorWhite))),
      ]))
    let cHalf = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(scale = 0.5,
          child = text("MEASURE ME WIDE",
            style = textStyle(fontSize = 24, color = colorWhite)))),
      ]))
    let bFull = paintedBounds(cFull)
    let bHalf = paintedBounds(cHalf)
    check bFull.maxX > 0
    check bHalf.maxX > 0
    check bHalf.maxX < bFull.maxX   # scaled-down text is narrower

suite "repaintBoundary x dirty marking":
  # The 0.11.5 bug: after the first paint, markNeedsPaint
  # short-circuited on a stale needsPaint flag and never reached
  # the boundary's absorbPaintMark, so the boundary composited a
  # stale cache forever. The fix guarantees absorbPaintMark fires
  # on every call. This test paints, mutates, paints again, and
  # asserts the second paint shows the new content.

  test "second keystroke after a full paint still invalidates the boundary":
    # Drive through the REAL input path, exactly like the desktop
    # runner: focus the TextField, send text events, drain the
    # binding's dirtyRoots, rebuild those elements, paint.
    # Rebuilding from the root would hit the identity short-circuit
    # (same widget refs) and skip the subtree, which is why this
    # test goes through setState's dirty-root queue instead.
    let canvas = newEmbeddedCanvas(W, H)
    let b = newBinding(canvas, Size(width: float32(W), height: float32(H)))
    let root = mountElement(nil,
      repaintBoundary(child = container(
        width = 300, height = 60,
        hasColor = true, color = colorWhite,
        child = textField(initialValue = "",
          style = textStyle(fontSize = 20, color = colorBlack)))), 0)
    b.rootElement = root
    runLayout(root, tightFor(float32(W), float32(H)))
    canvas.clear(BG)
    runPaint(root, canvas)
    let first = canvas.image.copy()

    let fm = focusManager()
    check fm.nodes.len > 0
    fm.focus(fm.nodes[^1])   # the field mounted just above

    proc pump() =
      ## One runner frame: drain dirty roots, rebuild, layout, paint.
      if b.dirtyRoots.len > 0:
        let snap = b.dirtyRoots
        b.dirtyRoots.setLen(0)
        for r in snap: rebuildElement(r)
      runLayout(root, tightFor(float32(W), float32(H)))
      canvas.clear(BG)
      runPaint(root, canvas)

    pump()  # settle the focus-change setState

    # Keystroke one + full paint cycle.
    discard fm.handleKeyEvent(KeyEvent(kind: keDown, text: "B"))
    pump()

    # Keystroke TWO + paint. This is where the 0.11.5 bug bit:
    # needsPaint was still true from cycle one, the markNeedsPaint
    # walk stopped early, the boundary's cache never re-rasterized,
    # and the user saw no characters appear.
    discard fm.handleKeyEvent(KeyEvent(kind: keDown, text: "C"))
    pump()
    let third = canvas.image

    var differs = false
    let p1 = cast[ptr UncheckedArray[uint32]](addr first.data[0])
    let p3 = cast[ptr UncheckedArray[uint32]](addr third.data[0])
    for i in 0 ..< W * H:
      if p1[i] != p3[i]:
        differs = true
        break
    check differs

suite "repaintBoundary x transform":
  test "boundary inside a translated transform paints at the shifted position":
    let c = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(transform(translation = Offset(dx: 150, dy: 0),
          child = repaintBoundary(child = container(
            width = 40, height = 40,
            hasColor = true, color = colorGreen)))),
      ]))
    let b = paintedBounds(c)
    check b.maxX >= 0
    check b.minX >= 145

suite "opacity x text cache":
  test "same string at different opacities paints differently":
    # The text bitmap cache keys on color (with opacity baked in).
    # If opacity were ignored by the key, both renders would blit
    # the identical bitmap.
    let cFull = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(text("GHOST", style = textStyle(fontSize = 24, color = colorWhite))),
      ]))
    let cDim = render(
      column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
        Widget(opacity(opacity = 0.25,
          child = text("GHOST", style = textStyle(fontSize = 24, color = colorWhite)))),
      ]))
    # Compare brightest pixel in each: the dim render must be darker.
    proc maxLum(c: EmbeddedCanvas): int =
      let px = cast[ptr UncheckedArray[uint32]](addr c.image.data[0])
      for i in 0 ..< W * H:
        let v = px[i]
        let r = int((v shr 0) and 0xFF)
        let g = int((v shr 8) and 0xFF)
        let b = int((v shr 16) and 0xFF)
        let lum = r + g + b
        if lum > result: result = lum
    check maxLum(cDim) < maxLum(cFull)
