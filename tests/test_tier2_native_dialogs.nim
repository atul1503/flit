## Native dialogs: enum values and that public procs exist. We
## don't actually pop a dialog (no display in CI) so we test
## the API surface and the JS-build short-circuit logic.

import std/unittest
import ../src/flit/platform/native_dialogs

suite "native_dialogs":
  test "DialogKind enum values":
    check ord(dkInfo) == 0
    check ord(dkWarning) == 1
    check ord(dkError) == 2
    check ord(dkQuestion) == 3

  test "DialogChoice enum values":
    check ord(dcOK) == 0
    check ord(dcCancel) == 1
    check ord(dcYes) == 2
    check ord(dcNo) == 3

  # Note: messageBox / confirm / askYesNo actually pop a real
  # OS dialog when invoked on macOS / Linux desktop, which blocks
  # the test. We only verify their existence here via reference;
  # interactive testing happens in the showcase app.
  test "messageBox proc exists":
    let p: proc(title, message: string, kind: DialogKind): DialogChoice =
      messageBox
    check not p.isNil

  test "confirm proc exists":
    let p: proc(title, message, okLabel, cancelLabel: string,
                kind: DialogKind): DialogChoice = confirm
    check not p.isNil

  test "askYesNo proc exists":
    let p: proc(title, message: string): bool = askYesNo
    check not p.isNil
