## Render one frame of the showcase to a PNG so we can verify pixels
## without opening a window. Uses the embedded backend (pure Pixie) so it
## works without SDL.

import pixie except Rect, rect, measureText
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../src/flit/platform/embedded/runner as embed
import ../examples/showcase/main as showcaseApp
import ../src/flit/foundation/widget

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

proc renderFrame(tab: Tab, dark: bool, path: string) =
  let canvas = embed.newEmbeddedCanvas(W, H)
  let app = Showcase()
  let root = mountElement(nil, app, 0)
  let st = ShowcaseState(root.state)
  st.darkMode = dark
  st.tab = tab
  root.dirty = true
  rebuildElement(root)
  runLayout(root, tightFor(W, H))
  canvas.clear(0xFFFFFFFF'u32)
  runPaint(root, canvas)
  canvas.image.writeFile(path)
  echo "wrote ", path

when isMainModule:
  installFont()
  renderFrame(tabHome,      dark = false, path = "/tmp/flit_showcase_light.png")
  renderFrame(tabHome,      dark = true,  path = "/tmp/flit_showcase_dark.png")
  renderFrame(tabLayout,    dark = false, path = "/tmp/flit_showcase_layout.png")
  renderFrame(tabStyle,     dark = false, path = "/tmp/flit_showcase_style.png")
  renderFrame(tabInputs,    dark = false, path = "/tmp/flit_showcase_inputs.png")
  renderFrame(tabAnimation, dark = false, path = "/tmp/flit_showcase_animation.png")
  renderFrame(tabCupertino, dark = false, path = "/tmp/flit_showcase_cupertino.png")
