## Async file picker tests. The repeated-cycle case regresses the
## 0.13.2 SIGSEGV: reusing the worker Thread var without joining
## the previous thread crashed after a few attach / cancel rounds.

import std/[unittest, os]
import ../src/flit/platform/file_picker

# Fake backend so no real dialog opens. Sleeps briefly to mimic a
# user interacting with the dialog off the main thread.
openFileImpl = proc(title: string, filters: seq[FileFilter]): string =
  sleep(30)
  if title == "cancel-me": "" else: "/tmp/picked.png"

proc runOnePick(title: string): string =
  var got = "UNSET"
  var fired = false
  check openFileAsync(
    cb = proc(path: string) =
      got = path
      fired = true,
    title = title)
  for i in 0 ..< 300:
    pumpFilePickerEvents()
    if fired: break
    sleep(5)
  check fired
  got

suite "openFileAsync":
  test "delivers the picked path on the pumping thread":
    check runOnePick("pick") == "/tmp/picked.png"

  test "cancellation delivers empty string":
    check runOnePick("cancel-me") == ""

  test "ten sequential cycles do not crash (0.13.2 SIGSEGV regression)":
    # The bug: createThread on an un-joined Thread var is undefined
    # behavior; it survived one or two rounds then SIGSEGVed. Ten
    # rounds of pick / cancel alternation reproduce it reliably
    # without the joinThread fix.
    for i in 0 ..< 10:
      let title = if i mod 2 == 0: "pick" else: "cancel-me"
      let expected = if i mod 2 == 0: "/tmp/picked.png" else: ""
      check runOnePick(title) == expected

  test "second request while one is in flight is refused":
    var fired = false
    check openFileAsync(cb = proc(path: string) = fired = true)
    # In flight now; a second request must be refused.
    check not openFileAsync(cb = proc(path: string) = discard)
    for i in 0 ..< 300:
      pumpFilePickerEvents()
      if fired: break
      sleep(5)
    check fired
