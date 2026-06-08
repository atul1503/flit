## ValueNotifier and ListenableBuilder behavior. Confirms:
##  - setting .value fires listeners exactly once per change
##  - equal values do NOT fire listeners
##  - removeListener stops notifications
##  - ListenableBuilder rebuilds when notifier fires
##  - Sibling widgets (separate ListenableBuilders or static widgets)
##    do NOT rebuild when an unrelated notifier fires.
##  - dispose removes the listener so the notifier doesn't keep
##    holding a dead State alive.

import std/unittest
import ../src/flit
import ../src/flit/foundation/runtime
import ../src/flit/foundation/binding
import ../src/flit/foundation/listenable
import ../src/flit/foundation/render_object

# Helper: build a Binding so onSetStateRoot wires up to a real dirty
# queue, and drain that queue to simulate the runner's frame loop.
proc setupBinding(): Binding =
  let canvas = Canvas(size: Size(width: 400, height: 200))
  result = newBinding(canvas, Size(width: 400, height: 200))

proc pump(b: Binding) =
  while b.dirtyRoots.len > 0:
    let pending = b.dirtyRoots
    b.dirtyRoots = @[]
    for e in pending:
      rebuildElement(e)

suite "ValueNotifier":
  test "value= fires every listener with the new value":
    let n = newValueNotifier(0)
    var seen: seq[int] = @[]
    n.addListener(proc(v: int) = seen.add(v))
    n.value = 5
    n.value = 5     # no-op: equal
    n.value = 7
    check seen == @[5, 7]

  test "removeListener stops further notifications":
    let n = newValueNotifier("a")
    var hits = 0
    let l = proc(v: string) = inc hits
    n.addListener(l)
    n.value = "b"
    check hits == 1
    n.removeListener(l)
    n.value = "c"
    check hits == 1

  test "notify() fires listeners even when value didn't change":
    let n = newValueNotifier(@[1, 2])
    var hits = 0
    n.addListener(proc(v: seq[int]) = inc hits)
    n.notify()
    check hits == 1

  test "dispose drops all listeners":
    let n = newValueNotifier(0)
    n.addListener(proc(v: int) = discard)
    n.addListener(proc(v: int) = discard)
    check n.hasListeners
    n.dispose()
    check not n.hasListeners

  test "custom equality function suppresses notification":
    let n = newValueNotifier(1.0001'f32,
      equals = proc(a, b: float32): bool = abs(a - b) < 0.01'f32)
    var hits = 0
    n.addListener(proc(v: float32) = inc hits)
    n.value = 1.0002'f32   # within tolerance
    check hits == 0
    n.value = 2.0'f32      # outside tolerance
    check hits == 1

# ---------------------------------------------------------------------------
# A small "did this widget build N times" counter widget so we can
# observe which subtrees actually rebuild.

type
  BuildProbe* = ref object of StatefulWidget
    label*: string

  ProbeState* = ref object of State
    builds*: int

var probes: seq[ProbeState]

method widgetTypeName(w: BuildProbe): string = "BuildProbe"
method createElement(w: BuildProbe): Element = newElement(ekStateful, w)
method createState(w: BuildProbe): State =
  let s = ProbeState()
  probes.add(s)
  s
method build(s: ProbeState, ctx: BuildContext): Widget =
  inc s.builds
  text("probe")

suite "ListenableBuilder":
  test "builder runs on every notifier change":
    let b = setupBinding()
    let n = newValueNotifier(0)
    var values: seq[int] = @[]
    let tree = listenableBuilder(n, proc(ctx: BuildContext, v: int): Widget =
      values.add(v)
      text($v))
    let root = mountElement(nil, tree, 0)
    b.rootElement = root
    runLayout(root, tightFor(100, 100))
    check values == @[0]
    n.value = 1
    pump(b)
    n.value = 2
    pump(b)
    check values == @[0, 1, 2]

  test "rebuilds reach only the watching subtree, not siblings":
    probes.setLen(0)
    let b = setupBinding()
    let n = newValueNotifier(0)
    # Two siblings in a column. One watches the notifier, the other
    # is a static BuildProbe whose build count must NOT increase
    # when the notifier fires.
    let tree = column(children = @[
      Widget(listenableBuilder(n, proc(ctx: BuildContext, v: int): Widget =
        text("n = " & $v))),
      BuildProbe(label: "static"),
    ])
    let root = mountElement(nil, tree, 0)
    b.rootElement = root
    runLayout(root, tightFor(400, 200))
    check probes.len == 1
    let staticBuilds = probes[0].builds
    # Fire the notifier several times, pumping each one.
    n.value = 1; pump(b)
    n.value = 2; pump(b)
    n.value = 3; pump(b)
    # The static probe must NOT have rebuilt. Its build count stays
    # at whatever it was after the initial mount.
    check probes[0].builds == staticBuilds

  test "dispose removes the listener so future updates are silent":
    let b = setupBinding()
    let n = newValueNotifier(0)
    var fires = 0
    # Wrap in a column so we can swap the child via the parent's
    # reconcileChildren (the proper unmount path that calls dispose).
    let withBuilder = column(children = @[
      Widget(listenableBuilder(n, proc(ctx: BuildContext, v: int): Widget =
        inc fires
        text("x"))),
    ])
    let root = mountElement(nil, withBuilder, 0)
    b.rootElement = root
    runLayout(root, tightFor(100, 100))
    let before = fires
    n.value = 1; pump(b)
    check fires == before + 1
    # Swap the column's child to something else: this unmounts the
    # ListenableBuilder element and calls dispose() on its State,
    # which must remove the listener.
    root.widget = column(children = @[Widget(text("done"))])
    root.dirty = true
    rebuildElement(root)
    let after = fires
    # Future notifier updates must NOT call the builder anymore.
    n.value = 99
    pump(b)
    check fires == after
    check not n.hasListeners

when isMainModule: discard
