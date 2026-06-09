## System tray: configuration storage and removal.

import std/unittest
import ../src/flit/platform/system_tray

suite "system_tray":
  test "setTrayIcon stores the icon":
    activeTray = nil
    setTrayIcon("/tmp/icon.png", tooltip = "hello")
    check not activeTray.isNil
    check activeTray.iconPath == "/tmp/icon.png"
    check activeTray.tooltip == "hello"

  test "setTrayIcon stores the menu":
    activeTray = nil
    var fired = false
    setTrayIcon("/tmp/icon.png", menu = @[
      trayMenuItem("Show", onTap = proc() = fired = true),
      trayMenuSeparator(),
      trayMenuItem("Quit")])
    check activeTray.menu.len == 3
    check activeTray.menu[0].label == "Show"
    check activeTray.menu[1].separator
    check activeTray.menu[2].label == "Quit"
    activeTray.menu[0].onTap()
    check fired

  test "setTrayIcon stores onClick":
    activeTray = nil
    var clicked = false
    setTrayIcon("/tmp/icon.png", onClick = proc() = clicked = true)
    check not activeTray.onClick.isNil
    activeTray.onClick()
    check clicked

  test "removeTrayIcon clears the registration":
    setTrayIcon("/tmp/icon.png")
    check not activeTray.isNil
    removeTrayIcon()
    check activeTray.isNil

  test "removeTrayIcon on empty is safe":
    activeTray = nil
    removeTrayIcon()
    check activeTray.isNil

  test "trayMenuSeparator returns a separator-flagged item":
    let s = trayMenuSeparator()
    check s.separator
    check s.label == ""
