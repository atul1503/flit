## Regression tests for "seq length changed during iteration"
## crashes. Every observer-style callback in flit (notifier
## listeners, focus, inherited dependents, animation, text
## controller, runner dirtyRoots) must tolerate callbacks that
## register or remove other callbacks during the notification.

import std/unittest
import ../src/flit
import ../src/flit/foundation/[focus, widget]
import ../src/flit/widgets/text_field

suite "Iteration safety":

  test "ValueNotifier: listener can addListener during notify":
    let n = newValueNotifier(0)
    var called = 0
    let added = proc(v: int) = inc called
    n.addListener(proc(v: int) =
      # Adds a NEW listener while we're being iterated.
      n.addListener(added))
    n.value = 1
    # No crash. The newly added listener fires on the NEXT notify.
    check called == 0
    n.value = 2
    check called >= 1   # added listener now fires

  test "ValueNotifier: listener can addListener many times during notify":
    # The point of the snapshot is to keep iteration stable when
    # the seq grows mid-loop. This test forces many additions.
    let n = newValueNotifier(0)
    var fires = 0
    n.addListener(proc(v: int) =
      inc fires
      for _ in 0 ..< 10:
        n.addListener(proc(v: int) = discard))
    # Before the fix this would crash with the length-changed assertion.
    n.value = 1
    check fires == 1
    # 10 new listeners now registered; next notify fires the
    # original + those 10.
    n.value = 2
    check fires == 2

  test "AnimationController: listener can addListener during fire":
    let c = newAnimationController(durationSec = 0.1)
    var calls = 0
    c.addListener(proc(v: float32) =
      inc calls
      c.addListener(proc(v: float32) = discard))
    c.value = 0.5   # fires listeners
    check calls == 1   # only original fires this call
    c.value = 0.7
    # No crash; new listeners that registered during the previous
    # call now fire too.
    check true

  test "TextEditingController: listener can addListener during fire":
    let c = newTextEditingController("hello")
    var calls = 0
    c.addListener(proc(v: string) =
      inc calls
      c.addListener(proc(v: string) = discard))
    c.value = "hi"
    check calls == 1
    c.value = "bye"
    check true   # no crash

  test "FocusManager: focus callback can remove the node":
    let m = FocusManager()
    let a = newFocusNode()
    let b = newFocusNode()
    var calls = 0
    a.onFocusChange = proc(focused: bool) =
      if focused:
        inc calls
        m.remove(a)   # mutates m.nodes during the focus transition
    m.add(a); m.add(b)
    m.focus(a)
    check calls == 1
    # After remove, focus is cleared.
    check m.current.isNil

suite "InheritedWidget dependent iteration":

  test "notification can register a new dependent during rebuild":
    # We can't easily simulate a full mount/build here, but we
    # can check the snapshot semantics by constructing an
    # Element + dependents directly and forcing the notification.
    let parent = newElement(ekInherited, nil)
    let dep1 = newElement(ekStateless, nil)
    let dep2 = newElement(ekStateless, nil)
    # newElement starts with dirty: true; clear so the notify
    # actually does work.
    dep1.dirty = false
    dep2.dirty = false
    parent.dependents.add(dep1)
    parent.dependents.add(dep2)

    # `onSetStateRoot` is the hook that runs when dirty is set.
    # Replace with a callback that mutates dependents.
    let oldHook = onSetStateRoot
    var hookFired = 0
    onSetStateRoot = proc(e: Element) =
      inc hookFired
      # Simulate: a rebuild registers a new dependent on parent.
      parent.dependents.add(newElement(ekStateless, nil))
    defer: onSetStateRoot = oldHook

    # This used to crash with "seq length changed". Now it
    # iterates the snapshot.
    notifyInheritedDependents(parent)
    check hookFired == 2   # one per original dependent
