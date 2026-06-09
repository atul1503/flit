## Haptics: today stubs on every platform. We just verify the
## API surface and that calling each variant is safe.

import std/unittest
import ../src/flit/platform/haptics

suite "haptics":
  test "HapticKind enum has all expected values":
    check ord(hkLight) == 0
    check ord(hkMedium) == 1
    check ord(hkHeavy) == 2
    check ord(hkSuccess) == 3
    check ord(hkWarning) == 4
    check ord(hkError) == 5
    check ord(hkSelection) == 6

  test "hapticFeedback with default kind is safe":
    hapticFeedback()
    check true

  test "hapticFeedback with every kind is safe":
    for k in HapticKind:
      hapticFeedback(k)
    check true
