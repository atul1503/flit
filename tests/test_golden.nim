## Golden screenshot tests. Renders representative example screens
## offscreen with the bundled (deterministic) font and compares
## against committed golden PNGs pixel by pixel.
##
## First run with no golden present: records the golden and passes
## with a note. Subsequent runs: any pixel drift beyond the
## tolerance fails the test.
##
## To intentionally update a golden after a visual change:
##   rm tests/golden/<name>.png && nim c -r tests/test_golden.nim
## then commit the regenerated file.

import std/[unittest, os, strformat]
import pixie except Rect, rect
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/platform/embedded/runner as embed
import ../src/flit/rendering/text as flitText
import ../src/flit/rendering/bundled_font
import ../examples/amazon/main as amzn
import ../examples/pulse/main as pulse
import ../examples/chat/main as chat

# Deterministic rendering: bundled Roboto, never the host system's
# fonts, so the goldens match across machines and CI.
embed.embeddedFont = bundledFont(14)
flitText.measureText = flitText.wrapMeasureWithCache(
  proc(s: string, style: TextStyle): Size =
    let f = embed.embeddedFont
    f.size = style.fontSize
    let b = pixie.typeset(f, s).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height)))

const GoldenDir = "tests/golden"
const W = 1024
const H = 768

# Allowed fraction of differing pixels. Zero would be ideal, but a
# tiny tolerance shields against pixie point-release antialiasing
# changes without masking real layout regressions.
const TolerancePct = 0.5

proc renderScreen(w: Widget): pixie.Image =
  let canvas = newEmbeddedCanvas(W, H)
  let root = mountElement(nil, w, 0)
  runLayout(root, tightFor(float32(W), float32(H)))
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(root, canvas)
  canvas.image

proc checkGolden(name: string, img: pixie.Image) =
  createDir(GoldenDir)
  let path = GoldenDir / name & ".png"
  if not fileExists(path):
    img.writeFile(path)
    echo "  [golden] recorded new golden: ", path
    return
  let golden = readImage(path)
  doAssert golden.width == img.width and golden.height == img.height,
    "golden " & name & " has different dimensions; delete it to re-record"
  var diff = 0
  let pa = cast[ptr UncheckedArray[uint32]](addr golden.data[0])
  let pb = cast[ptr UncheckedArray[uint32]](addr img.data[0])
  for i in 0 ..< img.width * img.height:
    if pa[i] != pb[i]: inc diff
  let pct = diff.float / (img.width * img.height).float * 100.0
  if pct > TolerancePct:
    # Write the actual render next to the golden for inspection.
    let actualPath = GoldenDir / name & ".actual.png"
    img.writeFile(actualPath)
    echo &"  [golden] {name}: {diff} pixels differ ({pct:.2f}% > {TolerancePct}%)"
    echo &"  [golden] actual render written to {actualPath}"
  check pct <= TolerancePct

suite "golden screenshots":
  test "amazon home":
    checkGolden("amazon_home", renderScreen(amzn.homeScreen()))

  test "amazon category":
    checkGolden("amazon_category", renderScreen(amzn.categoryScreen("Electronics")))

  test "amazon cart (empty)":
    checkGolden("amazon_cart_empty", renderScreen(amzn.cartScreen()))

  test "amazon sign-in":
    checkGolden("amazon_signin", renderScreen(amzn.signInScreen()))

  test "amazon product detail":
    checkGolden("amazon_product", renderScreen(amzn.productScreen(1)))

  test "pulse home":
    checkGolden("pulse_home", renderScreen(pulse.homeScreen()))

  test "pulse now playing":
    checkGolden("pulse_nowplaying", renderScreen(pulse.nowPlayingScreen(3)))

  test "chat":
    checkGolden("chat", renderScreen(chat.chatScreen()))
