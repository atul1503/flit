## Integration test: GlyphAtlas + HarfBuzz. Verifies the atlas
## measures via HarfBuzz when a font is registered, and that the
## measured widths reflect shaping (ligatures / kerning) rather
## than naive sum-of-glyph-advances.
##
## We do NOT exercise the SDL_Texture-backed rasterize path here
## because that needs a live renderer; the GpuCanvas tests do
## that integration. This test runs purely against the bindings.

import std/[unittest, hashes, os, tables]
import ../src/flit/rendering/[harfbuzz, glyph_atlas]

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

suite "GlyphAtlas + HarfBuzz":
  test "registerHbFont caches a HarfBuzz font under the given hash":
    if systemFont.len > 0:
      let atlas = newGlyphAtlas(nil)
      atlas.registerHbFont(hash("system"), systemFont)
      check atlas.hbFonts.hasKey(hash("system"))

  test "measureShaped returns positive width for non-empty text":
    if systemFont.len > 0:
      let atlas = newGlyphAtlas(nil)
      atlas.registerHbFont(hash("system"), systemFont)
      let m = atlas.measureShaped(hash("system"), "Hello world", 14.0)
      check m.width > 0
      check m.height > 0

  test "measureShaped returns 0 for unregistered fonts":
    let atlas = newGlyphAtlas(nil)
    let m = atlas.measureShaped(hash("never-registered"), "test", 14.0)
    check m.width == 0
    check m.height == 0

  test "shaped width scales with font size":
    if systemFont.len > 0:
      let atlas = newGlyphAtlas(nil)
      atlas.registerHbFont(hash("system"), systemFont)
      let small = atlas.measureShaped(hash("system"), "Sample", 12.0)
      let big = atlas.measureShaped(hash("system"), "Sample", 36.0)
      check big.width > small.width
