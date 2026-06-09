## Multi-window registry. We avoid creating real SDL windows in
## the unit suite (no display in CI); instead we manipulate the
## window registry directly to verify the public lookup procs.

import std/[unittest, tables]
import ../src/flit/platform/desktop/multi_window

suite "multi_window registry":
  test "defaultWindowConfig provides sane defaults":
    let cfg = defaultWindowConfig()
    check cfg.title == "flit"
    check cfg.width == 800
    check cfg.height == 600
    check cfg.resizable
    check cfg.highDpi
    check cfg.vsync

  test "windowCount on empty registry is zero":
    windows.clear()
    check windowCount() == 0

  test "allWindows returns inserted windows":
    windows.clear()
    let w1 = FlitWindow(id: 1'u32, title: "w1")
    let w2 = FlitWindow(id: 2'u32, title: "w2")
    windows[1'u32] = w1
    windows[2'u32] = w2
    check windowCount() == 2
    let all = allWindows()
    check all.len == 2

  test "findWindow returns nil for missing ID":
    windows.clear()
    check findWindow(99'u32).isNil

  test "findWindow returns the registered window":
    windows.clear()
    let w = FlitWindow(id: 42'u32, title: "settings")
    windows[42'u32] = w
    let got = findWindow(42'u32)
    check not got.isNil
    check got.title == "settings"

  test "closeWindow on nil is safe":
    windows.clear()
    closeWindow(nil)
    check windowCount() == 0

  test "closeWindow with onClose callback fires it":
    windows.clear()
    var fired = false
    let w = FlitWindow(id: 7'u32, title: "x",
                       onClose: proc() = fired = true)
    windows[7'u32] = w
    # closeWindow tears down SDL resources too; we only test the
    # callback path by setting window/renderer to nil and verifying
    # the callback runs and the entry is removed.
    # destroy(nil) on SDL ptr is safe.
    closeWindow(w)
    check fired
    check not windows.hasKey(7'u32)
