## Directionality tests.

import std/unittest
import ../src/flit
import ../src/flit/widgets/directionality
import ../src/flit/foundation/runtime

type
  Probe = ref object of StatelessWidget
    captured: ref geometry.TextDirection

method widgetTypeName(w: Probe): string = "Probe"
method createElement(w: Probe): Element = newElement(ekStateless, w)
method build(w: Probe, ctx: BuildContext): Widget =
  w.captured[] = textDirectionOf(ctx)
  text("probe")

suite "Directionality":
  test "defaults to tdLtr when no ancestor":
    let cap = new(geometry.TextDirection)
    let p = Probe(captured: cap)
    discard mountElement(nil, p, 0)
    check cap[] == tdLtr

  test "directionality ancestor propagates tdRtl":
    let cap = new(geometry.TextDirection)
    let p = Probe(captured: cap)
    let tree = directionality(tdRtl, child = p)
    discard mountElement(nil, tree, 0)
    check cap[] == tdRtl

  test "innermost directionality wins":
    let cap = new(geometry.TextDirection)
    let p = Probe(captured: cap)
    let tree = directionality(tdRtl,
      child = directionality(tdLtr, child = p))
    discard mountElement(nil, tree, 0)
    check cap[] == tdLtr
