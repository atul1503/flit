## Native file picker dialogs. `openFile`, `saveFile`, `pickFolder`
## each spawn the OS-native picker and return the selected path
## (or empty string if the user cancelled).
##
## Implementation strategy: shell out to a platform helper instead
## of binding to per-OS GUI frameworks. This trades a small fork
## overhead for zero native binding code:
##
## - macOS: `osascript` with AppleScript file-picker
## - Linux: `zenity` (GNOME) or `kdialog` (KDE), whichever is on PATH
## - Windows: PowerShell with `System.Windows.Forms.OpenFileDialog`
## - Web: not implemented; use `<input type=file>` directly
##
## Procs block until the user dismisses the picker.

import std/[osproc, strutils, os]

type
  FileFilter* = object
    ## A name + extension list for filtering the picker.
    ## Example: `FileFilter(name: "Images", exts: @["png", "jpg"])`
    name*: string
    exts*: seq[string]

# Pluggable backends. Tests can swap these to avoid spawning real
# native dialogs. Default implementations are installed below per
# platform.
var openFileImpl*: proc(title: string, filters: seq[FileFilter]): string {.closure.} =
  proc(title: string, filters: seq[FileFilter]): string = ""
  ## Backend used by `openFile`. Swap in tests to return a fake
  ## path without spawning a real OS picker. The platform-specific
  ## default is installed at module load time.

var saveFileImpl*: proc(title, defaultName: string): string {.closure.} =
  proc(title, defaultName: string): string = ""
  ## Backend used by `saveFile`. Swap in tests. The
  ## platform-specific default is installed at module load time.

var pickFolderImpl*: proc(title: string): string {.closure.} =
  proc(title: string): string = ""
  ## Backend used by `pickFolder`. Swap in tests. The
  ## platform-specific default is installed at module load time.

when defined(macosx):
  proc osascriptPick(script: string): string =
    try:
      let res = execProcess("/usr/bin/osascript",
        args = ["-e", script],
        options = {poStdErrToStdOut, poUsePath})
      result = res.strip()
      if result.startsWith("Error") or result.startsWith("execution error"):
        result = ""
    except CatchableError:
      result = ""

  proc macOpenFile(title: string, filters: seq[FileFilter]): string =
    var ofTypes = ""
    if filters.len > 0:
      var exts: seq[string]
      for f in filters:
        for e in f.exts: exts.add("\"" & e & "\"")
      if exts.len > 0:
        ofTypes = " of type {" & exts.join(",") & "}"
    let script = "POSIX path of (choose file with prompt \"" &
                 title & "\"" & ofTypes & ")"
    osascriptPick(script)

  proc macSaveFile(title, defaultName: string): string =
    let script = "POSIX path of (choose file name with prompt \"" &
                 title & "\" default name \"" & defaultName & "\")"
    osascriptPick(script)

  proc macPickFolder(title: string): string =
    let script = "POSIX path of (choose folder with prompt \"" & title & "\")"
    osascriptPick(script)

  openFileImpl = macOpenFile
  saveFileImpl = macSaveFile
  pickFolderImpl = macPickFolder

elif defined(linux):
  proc zenityAvailable(): bool =
    findExe("zenity").len > 0
  proc kdialogAvailable(): bool =
    findExe("kdialog").len > 0

  proc runProc(prog: string, args: seq[string]): string =
    try:
      let res = execProcess(prog, args = args,
                            options = {poStdErrToStdOut, poUsePath})
      result = res.strip()
    except CatchableError:
      result = ""

  proc linuxOpenFile(title: string, filters: seq[FileFilter]): string =
    if zenityAvailable():
      var args = @["--file-selection", "--title=" & title]
      for f in filters:
        var pat = ""
        for e in f.exts: pat.add("*." & e & " ")
        args.add("--file-filter=" & f.name & " | " & pat.strip())
      runProc("zenity", args)
    elif kdialogAvailable():
      runProc("kdialog", @["--getopenfilename", "", "", "--title", title])
    else: ""

  proc linuxSaveFile(title, defaultName: string): string =
    if zenityAvailable():
      runProc("zenity", @["--file-selection", "--save",
                          "--confirm-overwrite",
                          "--title=" & title,
                          "--filename=" & defaultName])
    elif kdialogAvailable():
      runProc("kdialog", @["--getsavefilename", defaultName, "", "--title", title])
    else: ""

  proc linuxPickFolder(title: string): string =
    if zenityAvailable():
      runProc("zenity", @["--file-selection", "--directory",
                          "--title=" & title])
    elif kdialogAvailable():
      runProc("kdialog", @["--getexistingdirectory", "", "--title", title])
    else: ""

  openFileImpl = linuxOpenFile
  saveFileImpl = linuxSaveFile
  pickFolderImpl = linuxPickFolder

elif defined(windows):
  proc psPick(script: string): string =
    try:
      let res = execProcess("powershell.exe",
        args = ["-NoProfile", "-NonInteractive", "-Command", script],
        options = {poStdErrToStdOut, poUsePath})
      result = res.strip()
    except CatchableError:
      result = ""

  proc winOpenFile(title: string, filters: seq[FileFilter]): string =
    var filter = "All files (*.*)|*.*"
    if filters.len > 0:
      var parts: seq[string]
      for f in filters:
        var pat = ""
        for e in f.exts: pat.add("*." & e & ";")
        parts.add(f.name & "|" & pat)
      filter = parts.join("|")
    let script = """
      Add-Type -AssemblyName System.Windows.Forms
      $d = New-Object System.Windows.Forms.OpenFileDialog
      $d.Title = '""" & title & """'
      $d.Filter = '""" & filter & """'
      if ($d.ShowDialog() -eq 'OK') { $d.FileName }
    """
    psPick(script)

  proc winSaveFile(title, defaultName: string): string =
    let script = """
      Add-Type -AssemblyName System.Windows.Forms
      $d = New-Object System.Windows.Forms.SaveFileDialog
      $d.Title = '""" & title & """'
      $d.FileName = '""" & defaultName & """'
      if ($d.ShowDialog() -eq 'OK') { $d.FileName }
    """
    psPick(script)

  proc winPickFolder(title: string): string =
    let script = """
      Add-Type -AssemblyName System.Windows.Forms
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = '""" & title & """'
      if ($d.ShowDialog() -eq 'OK') { $d.SelectedPath }
    """
    psPick(script)

  openFileImpl = winOpenFile
  saveFileImpl = winSaveFile
  pickFolderImpl = winPickFolder

proc openFile*(title: string = "Open file",
               filters: seq[FileFilter] = @[]): string =
  ## Opens a native file-open dialog. Returns the absolute path of
  ## the selected file, or empty string if the user cancelled.
  ## Blocks until the dialog is dismissed.
  openFileImpl(title, filters)

proc saveFile*(title: string = "Save file",
               defaultName: string = "untitled"): string =
  ## Opens a native file-save dialog. Returns the chosen path,
  ## or empty string if cancelled.
  saveFileImpl(title, defaultName)

proc pickFolder*(title: string = "Choose folder"): string =
  ## Opens a native folder-picker dialog. Returns the chosen
  ## directory path, or empty string if cancelled.
  pickFolderImpl(title)

# --- Async variant ---
#
# The blocking procs above stall the SDL event loop while the
# native dialog is up, so macOS shows the spinning beachball over
# the app window. `openFileAsync` runs the picker on a worker
# thread and delivers the result back on the UI thread via
# `pumpFilePickerEvents` (called by the desktop runner each frame).

when not defined(js):
  import std/locks

  type PickArgs = object
    title:   string
    filters: seq[FileFilter]

  var
    pickLock: Lock
    pickThread: Thread[PickArgs]
    pickInFlight: bool
    pickResultReady: bool
    pickResultPath: string
    pickCb: proc(path: string) {.closure.}
      ## Held on the UI side only; the worker never touches it.

  initLock(pickLock)

  proc pickWorker(args: PickArgs) {.thread.} =
    {.cast(gcsafe).}:
      let res = openFileImpl(args.title, args.filters)
      withLock pickLock:
        pickResultPath = res
        pickResultReady = true

  proc openFileAsync*(cb: proc(path: string),
                      title: string = "Open file",
                      filters: seq[FileFilter] = @[]): bool =
    ## Non-blocking variant of `openFile`. Spawns the native picker
    ## on a worker thread; `cb` fires ON THE UI THREAD (via the
    ## runner's per-frame pump) with the chosen path, or "" when the
    ## user cancelled. The app keeps animating and repainting while
    ## the dialog is up - no beachball.
    ##
    ## One request at a time: returns false (and does nothing) if a
    ## pick is already in flight.
    if pickInFlight: return false
    pickInFlight = true
    pickCb = cb
    createThread(pickThread, pickWorker,
                 PickArgs(title: title, filters: filters))
    true

  proc pumpFilePickerEvents*() =
    ## Called by the runtime once per frame. When the worker has a
    ## result waiting, fires the stored callback on this (UI)
    ## thread and clears the in-flight state.
    var path = ""
    var ready = false
    withLock pickLock:
      if pickResultReady:
        ready = true
        path = pickResultPath
        pickResultReady = false
    if ready:
      # Join the finished worker BEFORE clearing pickInFlight.
      # Reusing a Thread var with createThread while the previous
      # thread hasn't been joined is undefined behavior and
      # SIGSEGVs after a few picker cycles. The worker posted its
      # result as its final statement, so this join returns almost
      # immediately.
      joinThread(pickThread)
      pickInFlight = false
      let cb = pickCb
      pickCb = nil
      if not cb.isNil:
        try: cb(path) except CatchableError: discard
else:
  proc openFileAsync*(cb: proc(path: string),
                      title: string = "Open file",
                      filters: seq[FileFilter] = @[]): bool = false
  proc pumpFilePickerEvents*() = discard
