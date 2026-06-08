## Container composition: confirm padding, margin, decoration and size all
## end up wired up correctly via its stateless build.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/foundation/render_object
import ../src/flit/rendering/[proxy_box, decoration]

proc containerRender(c: Widget): RenderObject =
  ## Mount under a Center so the test gets loose constraints, then return
  ## the Container's actual render object (one level below RenderAlign).
  let root = mountElement(nil, center(child = c), 0)
  runLayout(root, tightFor(400, 300))
  let rootR = descendantRenderElement(root).renderObj
  return RenderAlign(rootR).child

suite "Container composition":
  test "size-only Container produces a constrained box":
    let r = containerRender(container(width = 100, height = 50))
    check r.size.width == 100
    check r.size.height == 50

  test "color-only Container wraps the child in a DecoratedBox":
    let r = containerRender(container(child = sizedBox(width = 40, height = 30),
                                       color = colorRed, hasColor = true))
    check r of RenderDecoratedBox
    check RenderDecoratedBox(r).decoration.color == colorRed
    check r.size.width == 40
    check r.size.height == 30

  test "padding adds to the box size":
    let r = containerRender(container(child = sizedBox(width = 40, height = 30),
                                       padding = edgeInsetsAll(10)))
    check r.size.width == 60   # 40 + 10*2
    check r.size.height == 50  # 30 + 10*2

  test "margin and padding combine":
    let r = containerRender(container(child = sizedBox(width = 20, height = 20),
                                       padding = edgeInsetsAll(4),
                                       margin = edgeInsetsAll(8)))
    check r.size.width == 44   # 20 + 4*2 + 8*2
    check r.size.height == 44

when isMainModule: discard
