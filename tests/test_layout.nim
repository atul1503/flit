## Layout tests. Exercise Constraints arithmetic and the flex layout pass
## without bringing up a window.

import std/[unittest, math]
import ../src/flit/foundation/geometry
import ../src/flit/foundation/render_object
import ../src/flit/rendering/[proxy_box, flex]

suite "Constraints":
  test "tightFor produces equal min/max":
    let c = tightFor(100, 50)
    check c.minWidth == 100 and c.maxWidth == 100
    check c.minHeight == 50 and c.maxHeight == 50
    check c.isTight

  test "loosen drops the min":
    let c = tightFor(100, 50).loosen()
    check c.minWidth == 0 and c.maxWidth == 100
    check c.minHeight == 0 and c.maxHeight == 50

  test "deflate by edge insets":
    let c = tightFor(100, 50).deflate(edgeInsetsAll(10))
    check c.maxWidth == 80 and c.maxHeight == 30

suite "EdgeInsets":
  test "deflateSize never negative":
    let s = edgeInsetsAll(50).deflateSize(Size(width: 40, height: 40))
    check s.width  == 0
    check s.height == 0

suite "Alignment":
  test "center places child in the middle":
    let o = alignCenter.resolveOffset(
      Size(width: 100, height: 100), Size(width: 20, height: 20))
    check o.dx == 40 and o.dy == 40
  test "topLeft places at origin":
    let o = alignTopLeft.resolveOffset(
      Size(width: 100, height: 100), Size(width: 20, height: 20))
    check o.dx == 0 and o.dy == 0

suite "RenderConstrainedBox":
  test "applies tighter constraints":
    let b = RenderConstrainedBox(additionalConstraints: tightFor(50, 30))
    b.layout(unbounded())
    check b.size == Size(width: 50, height: 30)

suite "RenderFlex":
  test "row distributes flex evenly across children":
    proc child(width: float32): RenderObject =
      let b = RenderSizedBox(requestedWidth: width, requestedHeight: 10)
      RenderObject(b)
    let r = RenderFlex(direction: axHorizontal, mainAxisSize: msMax,
                       mainAxisAlignment: maStart, crossAxisAlignment: caCenter)
    r.children = @[
      RenderFlexChild(obj: child(30), pd: FlexParentData(flex: 0)),
      RenderFlexChild(obj: child(0),  pd: FlexParentData(flex: 1, fit: ffTight)),
      RenderFlexChild(obj: child(0),  pd: FlexParentData(flex: 1, fit: ffTight)),
    ]
    r.layout(tightFor(130, 100))
    check r.size.width == 130
    # The two flex children should split the remaining 100px evenly.
    check r.children[1].obj.size.width == 50
    check r.children[2].obj.size.width == 50

when isMainModule: discard
