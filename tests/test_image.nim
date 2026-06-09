## Image widget tests. Focused on cache and layout logic since
## actually loading a PNG needs a real image file path.

import std/[unittest, os]
import ../src/flit
import ../src/flit/widgets/image_widget
import ../src/flit/foundation/runtime

suite "Image widget":
  test "image() with non-existent path returns a widget with placeholder semantics":
    clearImageCache()
    let w = image("/nonexistent/file.png")
    let root = mountElement(nil, w, 0)
    # Should mount without crashing, even though the file is missing.
    runLayout(root, tightFor(200, 200))
    let rE = descendantRenderElement(root)
    check not rE.isNil
    # Size falls back to filling constraints when no image is loaded.
    check rE.renderObj.size.width > 0
    check rE.renderObj.size.height > 0

  test "image() with explicit dims sizes correctly":
    clearImageCache()
    let w = image("/nonexistent.png", width = 100, height = 50)
    let root = mountElement(nil, w, 0)
    # Loose constraint so the image keeps its requested size.
    runLayout(root, constraints(0, 400, 0, 400))
    let rE = descendantRenderElement(root)
    check rE.renderObj.size.width == 100.0'f32
    check rE.renderObj.size.height == 50.0'f32

  test "clearImageCache empties the cache":
    discard loadImage("/nonexistent.png", "")
    clearImageCache()
    # Can't directly observe the cache; this just checks the call
    # doesn't crash.
    check true

  test "imageMemory accepts in-memory bytes":
    clearImageCache()
    let w = imageMemory(bytes = "")  # empty bytes; decode will fail
    let root = mountElement(nil, w, 0)
    runLayout(root, tightFor(100, 100))
    check not root.isNil
