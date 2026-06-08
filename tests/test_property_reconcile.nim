## Property tests for reconciliation. Generates random sequences of keyed
## children and runs them through reconcileChildren, asserting that
## State objects survive reorder/insert/remove operations correctly.

import std/[unittest, random, tables, algorithm]
import ../src/flit
import ../src/flit/foundation/runtime

const TRIALS = 200

type
  KeyedProbe = ref object of StatefulWidget
    id*: int

  KeyedProbeState* = ref object of State
    initCount*: int
    disposeCount*: int

method widgetTypeName(w: KeyedProbe): string = "KeyedProbe"
method createElement(w: KeyedProbe): Element = newElement(ekStateful, w)
method createState(w: KeyedProbe): State = KeyedProbeState()
method initState(s: KeyedProbeState) =
  inc s.initCount
  s.mounted = true
method dispose(s: KeyedProbeState) =
  inc s.disposeCount
  s.mounted = false
method build(s: KeyedProbeState, ctx: BuildContext): Widget =
  text("p")

proc probe(id: int): Widget =
  KeyedProbe(key: newValueKey($id), id: id)

proc childIds(e: Element): seq[int] =
  for c in e.children:
    if c.widget of KeyedProbe:
      result.add(KeyedProbe(c.widget).id)

proc childStates(e: Element): Table[int, KeyedProbeState] =
  result = initTable[int, KeyedProbeState]()
  for c in e.children:
    if c.widget of KeyedProbe:
      result[KeyedProbe(c.widget).id] = KeyedProbeState(c.state)

suite "Reconciliation":
  test "shuffling N keyed children preserves their states":
    var rng = initRand(401)
    for _ in 0 ..< TRIALS:
      let n = 1 + rng.rand(7)
      var ids: seq[int] = @[]
      for i in 0 ..< n: ids.add(i)
      var widgets: seq[Widget] = @[]
      for i in ids: widgets.add(probe(i))
      let root = mountElement(nil, column(children = widgets), 0)
      runLayout(root, tightFor(400, 400))
      let initial = childStates(root)
      check initial.len == n
      # Now shuffle and rebuild.
      rng.shuffle(ids)
      var newKids: seq[Widget] = @[]
      for i in ids: newKids.add(probe(i))
      root.widget = column(children = newKids)
      root.dirty = true
      rebuildElement(root)
      let after = childStates(root)
      check after.len == n
      # Every state object must be the SAME instance as before.
      for id, s in initial:
        check after.hasKey(id)
        check after[id] == s
        check s.initCount == 1
        check s.disposeCount == 0

  test "removing keyed children calls dispose on exactly those removed":
    var rng = initRand(403)
    for _ in 0 ..< TRIALS:
      let n = 2 + rng.rand(6)
      var ids: seq[int] = @[]
      for i in 0 ..< n: ids.add(i)
      var widgets: seq[Widget] = @[]
      for i in ids: widgets.add(probe(i))
      let root = mountElement(nil, column(children = widgets), 0)
      runLayout(root, tightFor(400, 400))
      let initial = childStates(root)
      # Remove a random subset.
      let toRemove = 1 + rng.rand(n - 1)
      var keep = ids
      for _ in 0 ..< toRemove:
        keep.delete(rng.rand(keep.len - 1))
      var newKids: seq[Widget] = @[]
      for i in keep: newKids.add(probe(i))
      root.widget = column(children = newKids)
      root.dirty = true
      rebuildElement(root)
      # Each removed id's state should have dispose called once.
      for id, s in initial:
        if id notin keep:
          check s.disposeCount == 1
        else:
          check s.disposeCount == 0

  test "inserting new keyed children mounts only those":
    var rng = initRand(405)
    for _ in 0 ..< TRIALS:
      let n = 2 + rng.rand(4)
      var ids: seq[int] = @[]
      for i in 0 ..< n: ids.add(i)
      var widgets: seq[Widget] = @[]
      for i in ids: widgets.add(probe(i))
      let root = mountElement(nil, column(children = widgets), 0)
      runLayout(root, tightFor(400, 400))
      let initial = childStates(root)
      # Insert one new id at random position.
      let newId = 100 + rng.rand(1000)
      var keep = ids
      keep.insert(newId, rng.rand(keep.len))
      var newKids: seq[Widget] = @[]
      for i in keep: newKids.add(probe(i))
      root.widget = column(children = newKids)
      root.dirty = true
      rebuildElement(root)
      # Existing states untouched.
      for id, s in initial:
        check s.initCount == 1
        check s.disposeCount == 0
      # New child has fresh state with initCount=1.
      let after = childStates(root)
      check after.hasKey(newId)
      check after[newId].initCount == 1

when isMainModule: discard
