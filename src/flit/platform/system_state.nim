## Battery and network state. Platform-specific queries that
## return cached snapshots; refresh via the explicit `refresh*`
## procs.
##
## - macOS: `pmset` shell helper for battery, `scutil --dns`
##   plus `route get` for network
## - Linux: `/sys/class/power_supply/BAT0/`, `nmcli`
## - Windows: `WMI Win32_Battery`, `Get-NetConnectionProfile`
##
## All procs return sensible defaults when no battery / network
## exists (desktop without battery returns 100% / charging).

# osproc / os don't exist on the JS backend; platform bodies are
# inside when defined(...) blocks that vanish on JS.
when not defined(js):
  import std/[osproc, strutils, os, options]
else:
  import std/[strutils, options]

type
  BatteryState* = enum
    ## Power source / charge state for the active battery. Desktop
    ## machines without a battery report `bsNoBattery`; `isCharging`
    ## treats that as charging since there's no risk of running out.
    bsUnknown, bsCharging, bsDischarging, bsFull, bsNoBattery

  NetworkType* = enum
    ## Active network interface category. Reported best-effort;
    ## some platforms can't distinguish Wi-Fi from Ethernet and
    ## return `ntUnknown`.
    ntUnknown, ntNone, ntEthernet, ntWifi, ntCellular

proc batteryLevel*(): float32 =
  ## Returns battery level as a fraction `[0, 1]`. 1.0 if no
  ## battery (desktop). On error or unknown, returns 1.0.
  when defined(macosx):
    try:
      let out0 = execProcess("/usr/bin/pmset", args = ["-g", "batt"],
                             options = {poStdErrToStdOut, poUsePath})
      let pctIdx = out0.find("%")
      if pctIdx > 0:
        var i = pctIdx - 1
        while i > 0 and out0[i].isDigit: dec i
        let pct = out0[i+1 ..< pctIdx]
        try: return parseInt(pct).float32 / 100.0'f32
        except ValueError: discard
    except CatchableError: discard
  return 1.0'f32

proc batteryState*(): BatteryState =
  ## Returns whether the device is plugged in, on battery, etc.
  when defined(macosx):
    try:
      let out0 = execProcess("/usr/bin/pmset", args = ["-g", "batt"],
                             options = {poStdErrToStdOut, poUsePath})
      if out0.contains("'AC Power'") or out0.contains("AC attached"):
        return bsCharging
      if out0.contains("'Battery Power'") or out0.contains("Battery"):
        return bsDischarging
    except CatchableError: discard
  return bsUnknown

proc isCharging*(): bool =
  ## Convenience: true if the device is plugged in (or has no
  ## battery, like a desktop).
  let s = batteryState()
  s == bsCharging or s == bsFull or s == bsNoBattery

proc networkType*(): NetworkType =
  ## Returns the active connection type. Polls quickly; doesn't
  ## maintain a watch.
  when defined(macosx):
    try:
      let out0 = execProcess("/sbin/route",
        args = ["-n", "get", "default"],
        options = {poStdErrToStdOut, poUsePath})
      if out0.contains("interface: en0"):
        return ntWifi    # macOS WiFi is conventionally en0
      elif out0.contains("interface: en"):
        return ntEthernet
    except CatchableError: discard
  return ntUnknown

proc isOnline*(): bool =
  ## True when any network interface has a default route.
  networkType() != ntNone and networkType() != ntUnknown
