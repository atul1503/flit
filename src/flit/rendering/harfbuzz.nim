## Minimal Nim bindings to libharfbuzz. Covers the slice we need
## to shape a UTF-8 string with a TTF font and recover the glyph
## sequence with proper kerning, ligatures, and contextual forms.
##
## This is not a full HarfBuzz binding; it exposes only the
## entry points the glyph atlas calls. See HarfBuzz's `hb.h`
## for the full API.
##
## All procs use the `harfbuzz` dynlib, resolved via the standard
## library search path. macOS users get it from
## `/opt/homebrew/lib/libharfbuzz.dylib`; project-wide rpath
## (configured in `config.nims`) makes that work without
## `DYLD_LIBRARY_PATH`. On Linux, install via the system package
## manager (`libharfbuzz-dev` on Debian/Ubuntu, `harfbuzz-devel`
## on RHEL/Fedora).

when not defined(js):
  const
    libHarfbuzz =
      when defined(macosx):  "libharfbuzz.dylib"
      elif defined(windows): "libharfbuzz.dll"
      else:                  "libharfbuzz.so.0"

  type
    HbBlob* = distinct pointer
    HbFace* = distinct pointer
    HbFont* = distinct pointer
    HbBuffer* = distinct pointer

    HbDirection* {.size: sizeof(cint).} = enum
      HB_DIRECTION_INVALID = 0
      HB_DIRECTION_LTR = 4
      HB_DIRECTION_RTL = 5
      HB_DIRECTION_TTB = 6
      HB_DIRECTION_BTT = 7

    HbScript* = distinct uint32

    HbMemoryMode* {.size: sizeof(cint).} = enum
      HB_MEMORY_MODE_DUPLICATE = 0
      HB_MEMORY_MODE_READONLY = 1
      HB_MEMORY_MODE_WRITABLE = 2
      HB_MEMORY_MODE_READONLY_MAY_MAKE_WRITABLE = 3

    HbGlyphInfo* {.bycopy.} = object
      codepoint*: uint32   ## glyph index (post-shaping) or codepoint (pre)
      mask*:      uint32
      cluster*:   uint32   ## byte offset in source string
      var1*:      uint32
      var2*:      uint32

    HbGlyphPosition* {.bycopy.} = object
      xAdvance*: int32
      yAdvance*: int32
      xOffset*:  int32
      yOffset*:  int32
      var1*:     uint32

    HbFeature* {.bycopy.} = object
      tag*:   uint32
      value*: uint32
      start*: cuint
      `end`*: cuint

  # blob

  proc hb_blob_create*(data: cstring, length: cuint, mode: HbMemoryMode,
                       userData: pointer, destroy: pointer): HbBlob {.
    importc, dynlib: libHarfbuzz.}
  proc hb_blob_destroy*(blob: HbBlob) {.importc, dynlib: libHarfbuzz.}

  # face / font

  proc hb_face_create*(blob: HbBlob, index: cuint): HbFace {.
    importc, dynlib: libHarfbuzz.}
  proc hb_face_destroy*(face: HbFace) {.importc, dynlib: libHarfbuzz.}

  proc hb_font_create*(face: HbFace): HbFont {.importc, dynlib: libHarfbuzz.}
  proc hb_font_destroy*(font: HbFont) {.importc, dynlib: libHarfbuzz.}
  proc hb_font_set_scale*(font: HbFont, xScale, yScale: cint) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_font_set_ppem*(font: HbFont, xPpem, yPpem: cuint) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_font_get_glyph_extents*(font: HbFont, glyph: uint32,
                                  extents: pointer): cint {.
    importc, dynlib: libHarfbuzz.}

  # buffer

  proc hb_buffer_create*(): HbBuffer {.importc, dynlib: libHarfbuzz.}
  proc hb_buffer_destroy*(buf: HbBuffer) {.importc, dynlib: libHarfbuzz.}
  proc hb_buffer_clear_contents*(buf: HbBuffer) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_add_utf8*(buf: HbBuffer, text: cstring, textLen: cint,
                           itemOffset: cuint, itemLen: cint) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_set_direction*(buf: HbBuffer, dir: HbDirection) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_set_script*(buf: HbBuffer, script: HbScript) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_set_language*(buf: HbBuffer, lang: pointer) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_guess_segment_properties*(buf: HbBuffer) {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_get_length*(buf: HbBuffer): cuint {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_get_glyph_infos*(buf: HbBuffer, length: ptr cuint): ptr HbGlyphInfo {.
    importc, dynlib: libHarfbuzz.}
  proc hb_buffer_get_glyph_positions*(buf: HbBuffer, length: ptr cuint): ptr HbGlyphPosition {.
    importc, dynlib: libHarfbuzz.}

  # shape

  proc hb_shape*(font: HbFont, buf: HbBuffer, features: pointer, numFeatures: cuint) {.
    importc, dynlib: libHarfbuzz.}

  # High-level wrapper

  type
    ShapedGlyph* = object
      ## A single glyph after shaping. `index` is the glyph index
      ## in the font's glyph table (NOT a codepoint). `cluster` is
      ## the byte offset in the source UTF-8 string. Advances are
      ## in 26.6 fixed-point (1/64 of a pixel) coming out of
      ## HarfBuzz; the wrapper converts to pixels via the font's
      ## current scale.
      glyphIndex*: uint32
      cluster*:    uint32
      xAdvance*:   float32
      yAdvance*:   float32
      xOffset*:    float32
      yOffset*:    float32

    HarfBuzzAvailable* = object
      ## Sentinel for whether HarfBuzz is loadable at runtime.
      ## Cached after the first successful load.
      available*: bool
      checked*:   bool

  var hbAvail: HarfBuzzAvailable

  proc isHarfBuzzAvailable*(): bool =
    ## Returns true if libharfbuzz could be loaded. Caches the
    ## result. Safe to call frequently. When false, all shape
    ## calls in this module are no-ops and callers fall back to
    ## whatever non-shaped path they have (e.g. Pixie typeset).
    if hbAvail.checked: return hbAvail.available
    hbAvail.checked = true
    # Force a no-op call so the dynlib resolves. We use
    # hb_buffer_create which has no side effects beyond returning
    # a handle.
    try:
      let b = hb_buffer_create()
      if not pointer(b).isNil:
        hb_buffer_destroy(b)
        hbAvail.available = true
      else:
        hbAvail.available = false
    except CatchableError:
      hbAvail.available = false
    hbAvail.available

  proc shapeUtf8*(font: HbFont, text: string, fontSize: float32): seq[ShapedGlyph] =
    ## Shapes `text` with `font` at `fontSize` pixels. Returns the
    ## sequence of glyphs after shaping, with positions in pixels.
    ##
    ## The caller owns the font; this proc does not free it. The
    ## script and direction are auto-detected via
    ## `hb_buffer_guess_segment_properties`.
    ##
    ## Returns an empty seq if HarfBuzz is not available.
    if not isHarfBuzzAvailable(): return @[]
    if pointer(font).isNil or text.len == 0: return @[]

    let buf = hb_buffer_create()
    defer: hb_buffer_destroy(buf)
    hb_buffer_clear_contents(buf)
    hb_buffer_add_utf8(buf, text.cstring, cint(text.len), 0, cint(text.len))
    hb_buffer_guess_segment_properties(buf)

    # Scale up so HarfBuzz's 26.6 fixed-point output reflects
    # `fontSize` pixels. A scale of 64*fontSize means each unit
    # in the output equals 1/(64*fontSize) of a pixel.
    let scale = cint(fontSize * 64.0'f32)
    hb_font_set_scale(font, scale, scale)
    hb_font_set_ppem(font, cuint(fontSize), cuint(fontSize))

    hb_shape(font, buf, nil, 0)

    var n: cuint
    let infosPtr = hb_buffer_get_glyph_infos(buf, addr n)
    let posPtr = hb_buffer_get_glyph_positions(buf, addr n)
    if n == 0 or infosPtr.isNil or posPtr.isNil: return @[]
    let infos = cast[ptr UncheckedArray[HbGlyphInfo]](infosPtr)
    let pos = cast[ptr UncheckedArray[HbGlyphPosition]](posPtr)
    result = newSeqOfCap[ShapedGlyph](int(n))
    # 26.6 to pixels: divide by 64.
    for i in 0 ..< int(n):
      result.add(ShapedGlyph(
        glyphIndex: infos[i].codepoint,
        cluster:    infos[i].cluster,
        xAdvance:   float32(pos[i].xAdvance) / 64.0'f32,
        yAdvance:   float32(pos[i].yAdvance) / 64.0'f32,
        xOffset:    float32(pos[i].xOffset)  / 64.0'f32,
        yOffset:    float32(pos[i].yOffset)  / 64.0'f32))

  proc loadFontFromFile*(path: string): HbFont =
    ## Reads a font file from disk and produces a HarfBuzz font.
    ## The face and blob are kept alive by HarfBuzz's internal
    ## reference counting (we drop our references but the font
    ## retains them). Returns a default-initialized HbFont (with
    ## a nil pointer) on failure.
    if not isHarfBuzzAvailable(): return HbFont(nil)
    var data: string
    try:
      data = readFile(path)
    except IOError:
      return HbFont(nil)
    # HB_MEMORY_MODE_DUPLICATE makes HarfBuzz copy the bytes
    # internally, so our `data` string can be freed when we leave
    # scope.
    let blob = hb_blob_create(data.cstring, cuint(data.len),
                              HB_MEMORY_MODE_DUPLICATE, nil, nil)
    if pointer(blob).isNil: return HbFont(nil)
    let face = hb_face_create(blob, 0)
    hb_blob_destroy(blob)
    if pointer(face).isNil: return HbFont(nil)
    let font = hb_font_create(face)
    hb_face_destroy(face)
    font
