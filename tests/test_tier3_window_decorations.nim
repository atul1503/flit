## Window decorations: WindowEffect enum surface + that the
## non-window-creating helpers don't crash. setWindowBorderless
## and friends require a real SDL window so are exercised in
## the showcase manually.

import std/unittest
import ../src/flit/platform/window_decorations

suite "window_decorations":
  test "WindowEffect enum values":
    check ord(weNone) == 0
    check ord(weVibrancyLight) == 1
    check ord(weVibrancyDark) == 2
    check ord(weAcrylic) == 3
    check ord(weBlur) == 4

  test "setWindowEffect with weNone on nil window is a no-op":
    setWindowEffect(nil, weNone)
    check true

  test "setAlwaysOnTop is a safe stub":
    setAlwaysOnTop(nil, true)
    setAlwaysOnTop(nil, false)
    check true

  test "setOpacity is a safe stub":
    setOpacity(nil, 0.5'f32)
    setOpacity(nil, 1.0'f32)
    check true
