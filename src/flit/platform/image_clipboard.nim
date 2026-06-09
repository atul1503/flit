## Image clipboard: copy/paste raw PNG bytes through the OS
## clipboard. Text clipboard already works via SDL2; this
## complements it for image data.
##
## Strategy: shell out to platform helpers for portability:
## - macOS: osascript with NSPasteboard accessors
## - Linux: xclip (X11) or wl-copy (Wayland)
## - Windows: PowerShell with System.Windows.Forms.Clipboard
##
## All procs return immediately if the platform helper is missing.
## Bytes are PNG-encoded.

import std/[osproc, os, base64, strutils, streams]

proc commandExists(name: string): bool = findExe(name).len > 0

var copyImagePngImpl*: proc(pngBytes: string): bool =
  proc(pngBytes: string): bool = false
  ## Backend used by `copyImagePng`. Swap in tests to capture the
  ## bytes without writing to the real system clipboard. The
  ## platform-specific default is installed at module load time.

var pasteImagePngImpl*: proc(): string =
  proc(): string = ""
  ## Backend used by `pasteImagePng`. Swap in tests to return
  ## fake PNG bytes. The platform-specific default is installed
  ## at module load time.

when defined(macosx):
  proc macCopyImage(pngBytes: string): bool =
    # Write the PNG to a temp file, then have osascript read it
    # into the clipboard as a TIFF.
    let tmp = getTempDir() / ("flit_clip_" & $getCurrentProcessId() & ".png")
    try:
      writeFile(tmp, pngBytes)
      let script = "set the clipboard to (read POSIX file \"" & tmp &
                   "\" as TIFF picture)"
      discard execProcess("/usr/bin/osascript", args = ["-e", script],
                          options = {poStdErrToStdOut, poUsePath})
      removeFile(tmp)
      return true
    except CatchableError:
      return false

  proc macPasteImage(): string =
    # Use osascript to write the clipboard PNG to a temp file,
    # then read it back.
    let tmp = getTempDir() / ("flit_paste_" & $getCurrentProcessId() & ".png")
    try:
      # AppleScript: if the clipboard contains a picture, write it.
      let script = """
        try
          set the imgData to (the clipboard as «class PNGf»)
        on error
          return ""
        end try
        set fh to open for access POSIX file "$1" with write permission
        try
          write the imgData to fh
        end try
        close access fh
        return "$1"
      """.replace("$1", tmp)
      let path = execProcess("/usr/bin/osascript", args = ["-e", script],
                             options = {poStdErrToStdOut, poUsePath}).strip()
      if path == "": return ""
      if not fileExists(tmp): return ""
      result = readFile(tmp)
      removeFile(tmp)
    except CatchableError:
      result = ""

  copyImagePngImpl = macCopyImage
  pasteImagePngImpl = macPasteImage

elif defined(linux):
  proc linuxCopyImage(pngBytes: string): bool =
    if commandExists("xclip"):
      let tmp = getTempDir() / "flit_clip.png"
      try:
        writeFile(tmp, pngBytes)
        discard execProcess("xclip",
          args = ["-selection", "clipboard", "-t", "image/png", "-i", tmp],
          options = {poStdErrToStdOut, poUsePath})
        removeFile(tmp)
        return true
      except CatchableError:
        return false
    elif commandExists("wl-copy"):
      try:
        let p = startProcess("wl-copy",
          args = ["-t", "image/png"],
          options = {poStdErrToStdOut, poUsePath})
        p.inputStream.write(pngBytes)
        p.inputStream.close()
        discard p.waitForExit()
        return true
      except CatchableError:
        return false
    else: false

  proc linuxPasteImage(): string =
    if commandExists("xclip"):
      try:
        result = execProcess("xclip",
          args = ["-selection", "clipboard", "-t", "image/png", "-o"],
          options = {poStdErrToStdOut, poUsePath})
      except CatchableError:
        result = ""
    elif commandExists("wl-paste"):
      try:
        result = execProcess("wl-paste",
          args = ["-t", "image/png"],
          options = {poStdErrToStdOut, poUsePath})
      except CatchableError:
        result = ""
    else: result = ""

  copyImagePngImpl = linuxCopyImage
  pasteImagePngImpl = linuxPasteImage

elif defined(windows):
  proc winCopyImage(pngBytes: string): bool =
    let tmp = getTempDir() / "flit_clip.png"
    try:
      writeFile(tmp, pngBytes)
      let script = """
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile('""" & tmp & """')
        [System.Windows.Forms.Clipboard]::SetImage($img)
        $img.Dispose()
      """
      discard execProcess("powershell.exe",
        args = ["-NoProfile", "-Command", script],
        options = {poStdErrToStdOut, poUsePath})
      removeFile(tmp)
      return true
    except CatchableError:
      return false

  proc winPasteImage(): string =
    let tmp = getTempDir() / "flit_paste.png"
    let script = """
      Add-Type -AssemblyName System.Windows.Forms
      Add-Type -AssemblyName System.Drawing
      $img = [System.Windows.Forms.Clipboard]::GetImage()
      if ($img -ne $null) {
        $img.Save('""" & tmp & """', [System.Drawing.Imaging.ImageFormat]::Png)
        '""" & tmp & """'
      }
    """
    try:
      let path = execProcess("powershell.exe",
        args = ["-NoProfile", "-Command", script],
        options = {poStdErrToStdOut, poUsePath}).strip()
      if path.len == 0 or not fileExists(tmp): return ""
      result = readFile(tmp)
      removeFile(tmp)
    except CatchableError:
      result = ""

  copyImagePngImpl = winCopyImage
  pasteImagePngImpl = winPasteImage

proc copyImagePng*(pngBytes: string): bool =
  ## Copies `pngBytes` to the system clipboard as a PNG image.
  ## Returns true on success.
  copyImagePngImpl(pngBytes)

proc pasteImagePng*(): string =
  ## Returns the system clipboard's image as PNG bytes, or empty
  ## string if the clipboard doesn't contain an image.
  pasteImagePngImpl()
