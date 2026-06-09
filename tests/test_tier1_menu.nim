## Menu / MenuBar / ContextMenu construction.

import std/unittest
import ../src/flit/widgets/menu
import ../src/flit/widgets/basic

suite "menu":
  test "menuItem holds label, shortcut, onTap, enabled":
    var fired = false
    let it = menuItem("Save", onTap = proc() = fired = true,
                      shortcut = "Cmd+S", enabled = true)
    check it.label == "Save"
    check it.shortcut == "Cmd+S"
    check it.enabled
    check not it.isSeparator
    it.onTap()
    check fired

  test "menuItem default enabled is true":
    let it = menuItem("X")
    check it.enabled
    check not it.isSeparator

  test "menuSeparator is marked separator and disabled":
    let s = menuSeparator()
    check s.isSeparator
    check not s.enabled

  test "menuEntry collects items":
    let e = menuEntry("File", @[menuItem("Open"), menuItem("Quit")])
    check e.title == "File"
    check e.items.len == 2
    check e.items[0].label == "Open"

  test "menuBar wraps entries":
    let m = menuBar(@[
      menuEntry("File", @[menuItem("Open")]),
      menuEntry("Edit", @[menuItem("Undo")])])
    check not m.isNil
    check m.menus.len == 2
    check m.menus[1].title == "Edit"

  test "contextMenu wraps a child":
    let c = contextMenu(child = text("right click me"),
                       items = @[menuItem("Copy"), menuItem("Paste")])
    check not c.isNil
    check c.items.len == 2
    check not c.child.isNil
