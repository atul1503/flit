## Desktop notifications. Shows a transient OS notification with
## title, body, and optional icon.
##
## Implementation: shell out to platform helpers for portability.
## - macOS: `osascript` with `display notification`
## - Linux: `notify-send` (libnotify)
## - Windows: PowerShell + Windows.UI.Notifications toast XML
##
## Notification handlers (onClick, custom actions) require deeper
## OS integration (a notification listener / app delegate) that
## isn't in this initial cut. The notification appears; tapping
## it does the default OS action (focus the app on macOS, open
## Action Center on Windows).
##
## On mobile (iOS / Android), push notifications need app
## entitlements and a server backend (APNs / FCM); those are out
## of scope for this module.

# osproc / os don't exist on the JS backend; platform bodies are
# inside when defined(...) blocks that vanish on JS.
when not defined(js):
  import std/[osproc, os, strutils, options]
else:
  import std/[strutils, options]

type
  NotificationKind* = enum
    ## Urgency / styling hint for the notification. On Linux this
    ## maps to `notify-send --urgency=low|normal|critical`; on
    ## macOS and Windows the platform ignores it.
    nkInfo, nkWarning, nkError

# Pluggable backend. Tests can swap this to count invocations
# without spawning real native notifications.
var showNotificationImpl*: proc(title, body, icon: string,
                                kind: NotificationKind): bool {.closure.} =
  proc(title, body, icon: string, kind: NotificationKind): bool = false
  ## Backend used by `showNotification`. Swap in tests to count
  ## invocations without firing a real OS notification. The
  ## platform-specific default is installed at module load time.

proc defaultShowNotification(title, body, icon: string,
                             kind: NotificationKind): bool =
  let safeTitle = title.replace("\"", "\\\"")
  let safeBody = body.replace("\"", "\\\"")
  when defined(macosx):
    let script = "display notification \"" & safeBody &
                 "\" with title \"" & safeTitle & "\""
    try:
      discard execProcess("/usr/bin/osascript", args = ["-e", script],
                          options = {poStdErrToStdOut, poUsePath})
      return true
    except CatchableError:
      return false
  elif defined(linux):
    if findExe("notify-send").len == 0: return false
    var args = @[safeTitle, safeBody]
    case kind
    of nkError:   args.add("--urgency=critical")
    of nkWarning: args.add("--urgency=normal")
    else:         args.add("--urgency=low")
    if icon.len > 0: args.add("--icon=" & icon)
    try:
      discard execProcess("notify-send", args = args,
                          options = {poStdErrToStdOut, poUsePath})
      return true
    except CatchableError:
      return false
  elif defined(windows):
    let script = """
      [Windows.UI.Notifications.ToastNotificationManager,
       Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
      $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
        [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
      $xml = $template.GetXml()
      $xml = $xml -replace 'HeadlineText', '""" & safeTitle & """'
      $xml = $xml -replace 'BodyText',     '""" & safeBody & """'
      $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
      $doc.LoadXml($xml)
      $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('flit').Show($toast)
    """
    try:
      discard execProcess("powershell.exe",
        args = ["-NoProfile", "-Command", script],
        options = {poStdErrToStdOut, poUsePath})
      return true
    except CatchableError:
      return false
  else:
    return false

showNotificationImpl = defaultShowNotification

proc showNotification*(title, body: string,
                       icon: string = "",
                       kind: NotificationKind = nkInfo): bool =
  ## Shows a transient OS notification. Returns true if the
  ## platform helper was found and invoked successfully.
  ##
  ## Inputs:
  ## - `title`: notification title (bold line).
  ## - `body`: notification body text.
  ## - `icon`: absolute path to a PNG icon. Some platforms ignore
  ##   this; pass empty for default.
  ## - `kind`: hint for urgency / styling. Linux notify-send maps
  ##   these to `--urgency`; macOS and Windows ignore.
  ##
  ## Effect: fires-and-forgets. The notification appears in the
  ## OS notification center / popup.
  showNotificationImpl(title, body, icon, kind)
