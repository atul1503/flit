## System tray / menu-bar icon. Adds a small icon next to the
## clock that opens a menu when clicked.
##
## Each platform has a fundamentally different native API:
## - macOS: NSStatusItem + NSMenu via Cocoa
## - Linux: AppIndicator (GTK) or KStatusNotifierItem (Qt)
## - Windows: Shell_NotifyIcon
##
## A robust cross-platform implementation needs per-platform
## binding code. This module ships the public API and a stub
## that logs the registration; real platform integration is
## a follow-up requiring native binding work.
##
## Stub behavior: `setTrayIcon` and `setTrayMenu` accept the
## parameters and store them but don't render anything. Apps
## structure their code around the API so the real
## implementation slots in later without changes.

import std/[options]

type
  TrayMenuItem* = object
    label*: string
    onTap*: proc() {.closure.}
    separator*: bool

  TrayIcon* = ref object
    iconPath*: string
    tooltip*:  string
    menu*:     seq[TrayMenuItem]
    onClick*:  proc() {.closure.}

var activeTray* {.threadvar.}: TrayIcon

proc setTrayIcon*(iconPath: string,
                  tooltip: string = "",
                  menu: seq[TrayMenuItem] = @[],
                  onClick: proc() = nil) =
  ## Installs (or replaces) the system tray icon. Currently a
  ## stub: stores the configuration and logs intent. Real
  ## platform integration (NSStatusItem etc.) lands as a
  ## follow-up.
  ##
  ## Inputs:
  ## - `iconPath`: absolute path to a PNG icon (16x16 or 22x22
  ##   pixel size is typical; will be scaled by the OS).
  ## - `tooltip`: hover-over text.
  ## - `menu`: items shown when the user clicks the icon.
  ## - `onClick`: optional callback for plain click (no menu).
  activeTray = TrayIcon(iconPath: iconPath, tooltip: tooltip,
                        menu: menu, onClick: onClick)
  echo "[flit/tray] installed icon at: ", iconPath
  echo "[flit/tray]   note: tray icon implementation is currently a stub. ",
       "Real per-platform binding is a follow-up."

proc removeTrayIcon*() =
  ## Removes the tray icon if any. No-op if none was installed.
  activeTray = nil

proc trayMenuItem*(label: string, onTap: proc() = nil): TrayMenuItem =
  TrayMenuItem(label: label, onTap: onTap, separator: false)

proc trayMenuSeparator*(): TrayMenuItem =
  TrayMenuItem(separator: true)
