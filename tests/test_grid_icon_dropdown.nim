## Smoke tests for the four widgets added in 0.10.3: gridView,
## icon, dropdown, network_image. Verifies construction + basic
## layout / structural properties without launching SDL.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/widgets/icon as icon_widget
import ../src/flit/widgets/dropdown
import ../src/flit/widgets/network_image

suite "gridView":
  test "empty children produces an empty grid":
    let g = gridView(@[], crossAxisCount = 2)
    check not g.isNil
    check g.children.len == 0

  test "one item produces one row":
    let g = gridView(@[Widget(text("a"))], crossAxisCount = 2)
    check g.children.len == 1

  test "three items at crossAxisCount=2 produces two rows":
    let g = gridView(@[Widget(text("a")), text("b"), text("c")],
                     crossAxisCount = 2)
    # Two row widgets + one spacing widget between them.
    check g.children.len == 3

  test "crossAxisCount clamped to >= 1":
    let g = gridView(@[Widget(text("a"))], crossAxisCount = 0)
    check g.children.len == 1

  test "mounts and lays out":
    let g = gridView(@[Widget(text("a")), text("b"), text("c"), text("d")],
                     crossAxisCount = 2)
    let root = mountElement(nil, g, 0)
    runLayout(root, tightFor(400, 400))
    check not root.isNil

suite "icon":
  test "constructs":
    let i = icon("search", size = 24, color = colorBlack)
    check i.name == "search"
    check i.size == 24'f32

  test "every built-in name renders at the requested size":
    for name in ["search", "cart", "star", "chevron.down", "chevron.up",
                 "chevron.left", "chevron.right", "close", "menu",
                 "heart", "check", "plus", "minus"]:
      let w = icon(name, size = 16)
      let root = mountElement(nil, w, 0)
      # Loose constraints so the icon can pick its requested 16x16
      # rather than being pinned to the parent's tight min.
      runLayout(root, constraints(0, 200, 0, 200))
      let rE = descendantRenderElement(root)
      check not rE.isNil
      check rE.renderObj.size.width == 16'f32
      check rE.renderObj.size.height == 16'f32

  test "unknown icon still occupies its size slot":
    let w = icon("not-a-real-icon", size = 20)
    let root = mountElement(nil, w, 0)
    runLayout(root, constraints(0, 200, 0, 200))
    let rE = descendantRenderElement(root)
    check rE.renderObj.size.width == 20'f32

suite "dropdown":
  test "constructs":
    let d = dropdown[string](items = @["a", "b", "c"], value = "a",
                              width = 120)
    check d.items.len == 3
    check d.value == "a"
    check d.width == 120'f32

  test "onChange callback fires on selection":
    var picked = ""
    let d = dropdown[string](items = @["x", "y"], value = "x",
                              onChange = proc(v: string) = picked = v)
    check not d.onChange.isNil
    d.onChange("y")
    check picked == "y"

  test "displayBuilder is optional":
    let d = dropdown[int](items = @[1, 2, 3], value = 2)
    check d.displayBuilder.isNil

suite "network_image":
  test "constructs with defaults":
    let n = networkImage(url = "https://example.com/x.png",
                          width = 200, height = 200)
    check n.url == "https://example.com/x.png"
    check n.width == 200'f32
    check n.fit == ifCover

  test "requestNetworkImage returns pending on first call":
    let s = requestNetworkImage("https://example.invalid/never.png")
    check s == nfsPending

  test "networkImageBytes returns empty for unfetched URL":
    check networkImageBytes("https://example.invalid/never.png") == ""
