## Render-tree inspector. Mounts the showcase, lays it out at 1024x768, and
## walks the render tree printing each node's size, offset and type so we
## can see what the layout pass actually produced.

import std/[strutils]
import ../src/flit
import ../src/flit/foundation/render_object
import ../src/flit/foundation/runtime
import ../examples/showcase/main as showcaseApp

proc nameOf(r: RenderObject): string =
  if r.isNil: "nil"
  elif r of RenderConstrainedBox: "ConstrainedBox"
  elif r of RenderSizedBox:       "SizedBox"
  elif r of RenderPadding:        "Padding"
  elif r of RenderAlign:          "Align"
  elif r of RenderColoredBox:     "ColoredBox"
  elif r of RenderOpacity:        "Opacity"
  elif r of RenderTransform:      "Transform"
  elif r of RenderDecoratedBox:   "DecoratedBox"
  elif r of RenderFlex:
    let f = RenderFlex(r)
    "Flex(" & (if f.direction == axHorizontal: "row" else: "col") & ")"
  elif r of RenderStack:          "Stack"
  elif r of RenderParagraph:      "Paragraph(\"" & RenderParagraph(r).text & "\")"
  elif r of RenderProxyBox:       "ProxyBox"
  else: "?"

proc dump(r: RenderObject, depth = 0, absX = 0.0'f32, absY = 0.0'f32) =
  if r.isNil: return
  let pad = "  ".repeat(depth)
  echo pad, nameOf(r),
    " size=", $r.size,
    " abs=(", absX, ",", absY, ")",
    " childOffset=", $r.offset
  if r of RenderFlex:
    for fc in RenderFlex(r).children:
      dump(fc.obj, depth + 1, absX + fc.pd.offset.dx, absY + fc.pd.offset.dy)
  elif r of RenderStack:
    for sc in RenderStack(r).children:
      dump(sc.obj, depth + 1, absX + sc.pd.offset.dx, absY + sc.pd.offset.dy)
  elif r of RenderDecoratedBox:
    dump(RenderDecoratedBox(r).child, depth + 1, absX, absY)
  elif r of RenderProxyBox:
    let c = RenderProxyBox(r).child
    if not c.isNil:
      dump(c, depth + 1, absX + c.offset.dx, absY + c.offset.dy)

when isMainModule:
  let root = mountElement(nil, Showcase(), 0)
  runLayout(root, tightFor(1024, 768))
  let rE = descendantRenderElement(root)
  echo "=== render tree ==="
  dump(rE.renderObj, 0, 0, 0)
