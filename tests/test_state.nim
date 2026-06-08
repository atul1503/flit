## State and reconciliation tests.

import std/unittest
import ../src/flit/foundation/[widget, key, geometry, runtime]
import ../src/flit/widgets/basic

type
  Counter = ref object of StatefulWidget
  CounterState = ref object of State
    count: int

method widgetTypeName(w: Counter): string = "TestCounter"
method createElement(w: Counter): Element = newElement(ekStateful, w)
method createState(w: Counter): State = CounterState(count: 0)
method build(s: CounterState, ctx: BuildContext): Widget =
  text("count=" & $s.count)

suite "Stateful widget":
  test "createState is called once on mount":
    let e = mountElement(nil, Counter(), 0)
    check e.kind == ekStateful
    check e.children.len == 1
    let s = CounterState(e.state)
    check s.count == 0

  test "rebuild after setState reflects new state":
    let e = mountElement(nil, Counter(), 0)
    let s = CounterState(e.state)
    s.count = 5
    e.dirty = true
    rebuildElement(e)
    check e.children.len == 1
    let txt = Text(e.children[0].widget)
    check txt.data == "count=5"

when isMainModule: discard
