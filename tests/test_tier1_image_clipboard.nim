## Image clipboard: tests swap the var-proc backends to verify
## the injection pattern without hitting the system clipboard.

import std/unittest
import ../src/flit/platform/image_clipboard

suite "image_clipboard":
  test "copyImagePng delegates to copyImagePngImpl":
    var captured: string
    copyImagePngImpl = proc(bytes: string): bool =
      captured = bytes
      true
    check copyImagePng("\x89PNG fake")
    check captured == "\x89PNG fake"

  test "copyImagePng can fail":
    copyImagePngImpl = proc(bytes: string): bool = false
    check not copyImagePng("anything")

  test "pasteImagePng delegates to pasteImagePngImpl":
    pasteImagePngImpl = proc(): string = "fake-png-bytes"
    check pasteImagePng() == "fake-png-bytes"

  test "pasteImagePng with empty clipboard returns empty string":
    pasteImagePngImpl = proc(): string = ""
    check pasteImagePng() == ""
