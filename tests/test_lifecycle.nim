## Reconciliation lifecycle tests: didUpdateWidget fires when widget config
## changes, dispose runs when state leaves the tree, keyed reconciliation
## preserves identity across reorders.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime

type
  Probe* = ref object of StatefulWidget
    label*: string

  ProbeState = ref object of State
    inits*: int
    updates*: int
    disposes*: int
    lastOldLabel*: string

var globalProbe: ProbeState  # so the test can read its counters after unmount

method widgetTypeName(w: Probe): string = "Probe"
method createElement(w: Probe): Element = newElement(ekStateful, w)
method createState(w: Probe): State = ProbeState()
method initState(s: ProbeState) =
  inc s.inits
  s.mounted = true
  globalProbe = s
method didUpdateWidget(s: ProbeState, old: StatefulWidget) =
  inc s.updates
  s.lastOldLabel = Probe(old).label
method dispose(s: ProbeState) =
  inc s.disposes
  s.mounted = false
method build(s: ProbeState, ctx: BuildContext): Widget =
  text(Probe(s.element.widget).label)

suite "State lifecycle":
  test "initState fires once, didUpdateWidget fires on widget swap":
    # Wrap the probe in a column so the parent's reconcileChildren is what
    # swaps the probe widget (the standard rebuild path).
    let root = mountElement(nil,
      column(children = @[Widget(Probe(label: "a"))]), 0)
    runLayout(root, tightFor(200, 100))
    check globalProbe.inits == 1
    check globalProbe.updates == 0
    # New column with a new Probe widget at the same slot.
    root.widget = column(children = @[Widget(Probe(label: "b"))])
    root.dirty = true
    rebuildElement(root)
    check globalProbe.inits == 1
    check globalProbe.updates == 1
    check globalProbe.lastOldLabel == "a"

  test "dispose fires when a keyed child disappears":
    var captured: ProbeState
    let col = column(children = @[
      Widget(Probe(key: newValueKey("x"), label: "x")),
      Widget(Probe(key: newValueKey("y"), label: "y")),
    ])
    let root = mountElement(nil, col, 0)
    runLayout(root, tightFor(400, 200))
    # The state created for x is now globalProbe (last init wins, so it's y).
    # Reach into the element tree to capture x's state.
    for c in root.children:
      if c.widget.key == newValueKey("x"):
        captured = ProbeState(c.state)
        break
    check not captured.isNil
    let before = captured.disposes
    # Rebuild without the "x" child.
    root.widget = column(children = @[
      Widget(Probe(key: newValueKey("y"), label: "y")),
    ])
    root.dirty = true
    rebuildElement(root)
    check captured.disposes == before + 1

  test "keyed reorder preserves element identity":
    var states: array[2, ProbeState]
    let root = mountElement(nil, column(children = @[
      Widget(Probe(key: newValueKey("a"), label: "a")),
      Widget(Probe(key: newValueKey("b"), label: "b")),
    ]), 0)
    runLayout(root, tightFor(400, 200))
    for c in root.children:
      if c.widget.key == newValueKey("a"): states[0] = ProbeState(c.state)
      elif c.widget.key == newValueKey("b"): states[1] = ProbeState(c.state)
    # Swap order; with key-based matching the same State objects should be
    # reused (no extra initState, no dispose).
    let initsBefore = states[0].inits + states[1].inits
    let dispsBefore = states[0].disposes + states[1].disposes
    root.widget = column(children = @[
      Widget(Probe(key: newValueKey("b"), label: "b")),
      Widget(Probe(key: newValueKey("a"), label: "a")),
    ])
    root.dirty = true
    rebuildElement(root)
    check states[0].inits + states[1].inits == initsBefore
    check states[0].disposes + states[1].disposes == dispsBefore

when isMainModule: discard
