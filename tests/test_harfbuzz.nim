## HarfBuzz binding smoke test. Verifies the library loads, fonts
## can be created from a TTF on disk, and shaping produces non-empty
## glyph runs. Skips assertions silently when HarfBuzz isn't
## available on the build machine.

import std/[unittest, os]
import ../src/flit/rendering/harfbuzz

const candidateFonts = [
  "/System/Library/Fonts/Supplemental/Arial.ttf",
  "/Library/Fonts/Arial.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  "/usr/share/fonts/TTF/DejaVuSans.ttf",
  "C:/Windows/Fonts/arial.ttf",
]

proc findSystemFont(): string =
  for c in candidateFonts:
    if fileExists(c): return c
  ""

let systemFont = findSystemFont()

suite "HarfBuzz bindings":
  test "library loads on this machine":
    check isHarfBuzzAvailable()

  test "loadFontFromFile succeeds on a system font":
    if systemFont.len > 0:
      let f = loadFontFromFile(systemFont)
      check not pointer(f).isNil

  test "shapeUtf8 produces glyphs for 'Hello'":
    if systemFont.len > 0:
      let f = loadFontFromFile(systemFont)
      let glyphs = shapeUtf8(f, "Hello", 14.0)
      check glyphs.len == 5
      check glyphs[0].cluster == 0
      for g in glyphs:
        check g.xAdvance > 0

  test "ligatures collapse short runs (font-dependent)":
    if systemFont.len > 0:
      let f = loadFontFromFile(systemFont)
      let glyphs = shapeUtf8(f, "fi", 14.0)
      check glyphs.len <= 2
      check glyphs.len > 0

  test "shapeUtf8 on empty string returns empty":
    if systemFont.len > 0:
      let f = loadFontFromFile(systemFont)
      let glyphs = shapeUtf8(f, "", 14.0)
      check glyphs.len == 0
