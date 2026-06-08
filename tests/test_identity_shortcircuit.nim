## Verifies the widget-identity short-circuit in reconciliation:
## when a parent's rebuild returns the same widget reference,
## the child subtree is not re-walked.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime

type
  CountingWidget* = ref object of StatefulWidget
    child*: Widget
  CountingWidgetState* = ref object of State
    builds*: int

method widgetTypeName*(w: CountingWidget): string = "CountingWidget"
method createElement*(w: CountingWidget): Element = newElement(ekStateful, w)
method createState*(w: CountingWidget): State = CountingWidgetState(builds: 0)
method build*(s: CountingWidgetState, ctx: BuildContext): Widget =
  inc s.builds
  CountingWidget(s.element.widget).child

type
  Outer* = ref object of StatefulWidget
  OuterState* = ref object of State
    cached: Widget  # stable inner widget; same ref on every build
    forceRebuilds: int

method widgetTypeName*(w: Outer): string = "Outer"
method createElement*(w: Outer): Element = newElement(ekStateful, w)
method createState*(w: Outer): State =
  let inner = CountingWidget(child: sizedBox(width = 10, height = 10))
  OuterState(cached: inner, forceRebuilds: 0)
method build*(s: OuterState, ctx: BuildContext): Widget =
  inc s.forceRebuilds
  s.cached  # same reference every time

suite "Identity short-circuit":
  test "stable child widget skips inner rebuild":
    let outer = Outer()
    let root = mountElement(nil, outer, 0)
    let outerState = OuterState(root.state)
    let innerWidget = outerState.cached
    # Mount triggered initial build.
    check outerState.forceRebuilds == 1

    # Find inner element + state.
    var innerElem: Element
    proc findCounting(e: Element): Element =
      if e.widget == innerWidget: return e
      for c in e.children:
        let r = findCounting(c)
        if not r.isNil: return r
      nil
    innerElem = findCounting(root)
    check not innerElem.isNil
    let innerState = CountingWidgetState(innerElem.state)
    let innerBuildsAfterMount = innerState.builds

    # Force outer to rebuild. Inner widget reference is identical
    # so identity short-circuit should fire and skip inner.build.
    root.dirty = true
    rebuildElement(root)
    check innerState.builds == innerBuildsAfterMount  # NOT incremented
