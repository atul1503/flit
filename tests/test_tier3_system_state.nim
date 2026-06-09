## System state: battery / network queries. Real values are
## platform-dependent; we test that the procs return sensible
## values within expected ranges and that the convenience helpers
## behave correctly.

import std/unittest
import ../src/flit/platform/system_state

suite "system_state":
  test "batteryLevel returns a value in [0.0, 1.0]":
    let l = batteryLevel()
    check l >= 0.0'f32
    check l <= 1.0'f32

  test "batteryState returns a known value":
    let s = batteryState()
    check s in {bsUnknown, bsCharging, bsDischarging, bsFull, bsNoBattery}

  test "isCharging returns a bool (doesn't crash)":
    discard isCharging()
    check true

  test "networkType returns a known value":
    let n = networkType()
    check n in {ntUnknown, ntNone, ntEthernet, ntWifi, ntCellular}

  test "isOnline returns a bool":
    discard isOnline()
    check true

  test "BatteryState enum has all values":
    check ord(bsUnknown) == 0
    check ord(bsCharging) == 1
    check ord(bsDischarging) == 2
    check ord(bsFull) == 3
    check ord(bsNoBattery) == 4

  test "NetworkType enum has all values":
    check ord(ntUnknown) == 0
    check ord(ntNone) == 1
    check ord(ntEthernet) == 2
    check ord(ntWifi) == 3
    check ord(ntCellular) == 4
