## Notifications: pluggable backend (so tests don't fire real
## OS notifications) and enum surface.

import std/unittest
import ../src/flit/platform/notifications

suite "notifications":
  test "NotificationKind enum values":
    check ord(nkInfo) == 0
    check ord(nkWarning) == 1
    check ord(nkError) == 2

  test "showNotification delegates to showNotificationImpl":
    var seenTitle, seenBody, seenIcon: string
    var seenKind: NotificationKind
    showNotificationImpl = proc(t, b, i: string,
                                k: NotificationKind): bool =
      seenTitle = t; seenBody = b; seenIcon = i; seenKind = k
      true
    let ok = showNotification("Hello", "World",
                              icon = "/tmp/icon.png", kind = nkWarning)
    check ok
    check seenTitle == "Hello"
    check seenBody == "World"
    check seenIcon == "/tmp/icon.png"
    check seenKind == nkWarning

  test "showNotification returns false when impl reports failure":
    showNotificationImpl = proc(t, b, i: string,
                                k: NotificationKind): bool = false
    check not showNotification("x", "y")

  test "default kind is nkInfo":
    var seenKind: NotificationKind
    showNotificationImpl = proc(t, b, i: string,
                                k: NotificationKind): bool =
      seenKind = k
      true
    discard showNotification("a", "b")
    check seenKind == nkInfo
