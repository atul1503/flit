## Render one frame of the showcase to a PNG so we can verify pixels
## without opening a window. Uses the embedded backend (pure Pixie) so it
## works without SDL.

import pixie except Rect, rect, measureText
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../src/flit/platform/embedded/runner as embed
import ../examples/showcase/main as showcaseApp

const W = 1024
const H = 768

# Load Arial so text actually draws on the embedded canvas.
proc installFont() =
  let font = readFont("/System/Library/Fonts/Supplemental/Arial.ttf")
  embed.embeddedFont = font
  measureText = proc(text: string, style: TextStyle): Size =
    let f = font
    f.size = style.fontSize
    let b = typeset(f, text).computeBounds()
    Size(width: b.w, height: max(b.h, style.fontSize * style.height))

when isMainModule:
  installFont()
  let canvas = embed.newEmbeddedCanvas(W, H)

  # Mount and lay out the showcase.
  let root = mountElement(nil, Showcase(), 0)
  runLayout(root, tightFor(W, H))

  # Paint via the canvas pipeline.
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(root, canvas)

  canvas.image.writeFile("/tmp/flit_showcase_frame.png")
  echo "wrote /tmp/flit_showcase_frame.png"
