## File picker: tests verify the injectable backend pattern so
## tests don't pop a real OS dialog. The native implementations
## are wired in `when defined()` blocks; here we swap them.

import std/unittest
import ../src/flit/platform/file_picker

suite "file_picker":
  test "FileFilter holds name + extensions":
    let f = FileFilter(name: "Images", exts: @["png", "jpg"])
    check f.name == "Images"
    check f.exts.len == 2
    check f.exts[1] == "jpg"

  test "openFile delegates to openFileImpl":
    var capturedTitle: string
    var capturedFilters: int
    openFileImpl = proc(title: string, filters: seq[FileFilter]): string =
      capturedTitle = title
      capturedFilters = filters.len
      "/tmp/chosen.txt"
    let r = openFile("Pick something",
                     @[FileFilter(name: "Text", exts: @["txt"])])
    check r == "/tmp/chosen.txt"
    check capturedTitle == "Pick something"
    check capturedFilters == 1

  test "saveFile delegates to saveFileImpl":
    var capturedDefault: string
    saveFileImpl = proc(title, defaultName: string): string =
      capturedDefault = defaultName
      "/Users/me/out.txt"
    let r = saveFile("Save as", "draft.txt")
    check r == "/Users/me/out.txt"
    check capturedDefault == "draft.txt"

  test "pickFolder delegates to pickFolderImpl":
    pickFolderImpl = proc(title: string): string = "/Users/me/Documents"
    let r = pickFolder("Pick folder")
    check r == "/Users/me/Documents"

  test "empty string indicates user cancelled":
    openFileImpl = proc(title: string, filters: seq[FileFilter]): string = ""
    check openFile() == ""
