## Glyph atlas: cached rasterized text. The first time a piece of
## text is drawn at a given font+size+color, it is rasterized via
## Pixie into an `SDL_Texture`. Every subsequent draw composites the
## cached texture with `SDL_RenderCopy` (GPU). Stable labels stop
## costing per-frame CPU work entirely.
##
## This is a string-level atlas, not a per-glyph atlas. The trade-off
## is simpler code and zero text-shaping overhead at the cost of
## memory when the app draws many unique strings. For typical UIs
## with a stable set of button labels, headings, and body copy, the
## working set is small and the cache hit rate is essentially 100%.
##
## Integration with HarfBuzz for proper text shaping (ligatures,
## complex scripts, contextual forms) is a follow-up; this atlas
## works on top of Pixie's `typeset` which handles Latin scripts
## fully.

import std/[tables, hashes]
import ./harfbuzz

when not defined(js):
  import pixie except Rect, rect
  import sdl2

  type
    GlyphKey = object
      ## Cache key: a string, plus everything that affects how it
      ## rasterizes. `fontHash` lets us distinguish fonts cheaply
      ## without holding a Font reference inside the hash key.
      text*:     string
      fontHash*: int
      size*:     uint16
      color*:    uint32

    GlyphEntry* = ref object
      ## A cached rasterized text run. `texture` is GPU-resident.
      ## `width` and `height` are the pixel dims used to size the
      ## destination rect when compositing.
      texture*:  TexturePtr
      width*:    int
      height*:   int

    GlyphAtlas* = ref object
      ## Owns the cache. `renderer` is the SDL renderer to upload
      ## textures with. `maxEntries` caps memory; oldest entries
      ## (by insertion order) are evicted past the cap.
      ##
      ## When HarfBuzz is available, callers may register
      ## per-font HarfBuzz handles via `registerHbFont` so the
      ## atlas can shape text with proper ligatures and kerning
      ## before rasterization. The mapping key is the same
      ## `fontHash` used in cache keys.
      renderer*:   RendererPtr
      cache*:      Table[GlyphKey, GlyphEntry]
      order*:      seq[GlyphKey]
      maxEntries*: int
      hbFonts*:    Table[int, HbFont]

  proc hash*(k: GlyphKey): Hash =
    var h: Hash = 0
    h = h !& hash(k.text)
    h = h !& k.fontHash
    h = h !& int(k.size)
    h = h !& int(k.color)
    !$h

  proc `==`*(a, b: GlyphKey): bool =
    a.text == b.text and a.fontHash == b.fontHash and
    a.size == b.size and a.color == b.color

  proc newGlyphAtlas*(renderer: RendererPtr, maxEntries = 512): GlyphAtlas =
    ## Builds a fresh atlas backed by `renderer`. `maxEntries` caps
    ## the cache; older textures are destroyed and removed past
    ## that point. Tune based on UI complexity; 512 covers a
    ## decent-sized desktop app.
    GlyphAtlas(renderer: renderer, maxEntries: maxEntries,
               cache: initTable[GlyphKey, GlyphEntry](),
               hbFonts: initTable[int, HbFont]())

  proc registerHbFont*(a: GlyphAtlas, fontHash: int, fontPath: string) =
    ## Registers a HarfBuzz font for shaping. Subsequent
    ## `getOrRasterize` calls with the matching `fontHash` will
    ## shape the text through HarfBuzz before rasterization.
    ## If HarfBuzz is not available or the font can't be loaded,
    ## this is a no-op and the atlas falls back to Pixie's
    ## internal typeset.
    if not isHarfBuzzAvailable(): return
    if a.hbFonts.hasKey(fontHash): return
    let f = loadFontFromFile(fontPath)
    if not pointer(f).isNil:
      a.hbFonts[fontHash] = f

  proc measureShaped*(a: GlyphAtlas, fontHash: int, text: string,
                     fontSize: float32): tuple[width, height: float32] =
    ## Returns the shaped width and font ascent height for `text`
    ## at `fontSize` using the HarfBuzz font registered for
    ## `fontHash`. Returns `(0, 0)` if no HarfBuzz font is
    ## registered.
    if not a.hbFonts.hasKey(fontHash): return (0.0'f32, 0.0'f32)
    let glyphs = shapeUtf8(a.hbFonts[fontHash], text, fontSize)
    var w = 0.0'f32
    for g in glyphs: w += g.xAdvance
    (w, fontSize * 1.2'f32)  # height approximated as 1.2x font size

  proc evictOldest*(a: GlyphAtlas) =
    ## Drops the oldest entry from the cache and destroys its
    ## texture. Called automatically when the cache exceeds
    ## `maxEntries`; can be called manually to trim memory.
    if a.order.len == 0: return
    let key = a.order[0]
    a.order.delete(0)
    if a.cache.hasKey(key):
      let e = a.cache[key]
      if not e.texture.isNil:
        destroyTexture(e.texture)
      a.cache.del(key)

  proc rasterize(a: GlyphAtlas, font: Font, fontHash: int,
                 text: string, size: uint16, color: uint32): GlyphEntry =
    ## Pixie-rasterizes `text` once into a small image, uploads as
    ## an SDL_Texture, returns a `GlyphEntry`. Caller is responsible
    ## for inserting into the cache.
    ##
    ## When a HarfBuzz font is registered for `fontHash`, we use
    ## HarfBuzz to compute the shaped width (handling ligatures
    ## and kerning correctly); otherwise we fall back to Pixie's
    ## `typeset.computeBounds`.
    font.size = float32(size)
    var tw, th: int
    let shaped = a.measureShaped(fontHash, text, float32(size))
    if shaped.width > 0:
      tw = max(int(shaped.width) + 2, 1)
      th = max(int(shaped.height) + 2, 1)
    else:
      let bounds = typeset(font, text).computeBounds()
      tw = max(int(bounds.w) + 2, 1)
      th = max(int(max(bounds.h, float32(size))) + 2, 1)
    var img = newImage(tw, th)
    var paint = newPaint(SolidPaint)
    let a8 = uint8((color shr 24) and 0xFF)
    let r8 = uint8((color shr 16) and 0xFF)
    let g8 = uint8((color shr  8) and 0xFF)
    let b8 = uint8( color         and 0xFF)
    paint.color = rgba(r8, g8, b8, a8).color
    font.paints = @[paint]
    img.fillText(font, text, translate(vec2(0, 0)))
    let tex = createTexture(a.renderer, SDL_PIXELFORMAT_ARGB8888,
                            SDL_TEXTUREACCESS_STATIC, cint(tw), cint(th))
    discard setTextureBlendMode(tex, BlendMode_Blend)
    # Pixie RGBA8 -> ARGB swizzle for SDL_PIXELFORMAT_ARGB8888.
    var buf = newSeq[uint32](tw * th)
    let src = cast[ptr UncheckedArray[uint32]](addr img.data[0])
    for i in 0 ..< tw * th:
      let px = src[i]
      let rr = (px shr 0)  and 0xFF
      let gg = (px shr 8)  and 0xFF
      let bb = (px shr 16) and 0xFF
      let aa = (px shr 24) and 0xFF
      buf[i] = (aa shl 24) or (rr shl 16) or (gg shl 8) or bb
    discard updateTexture(tex, nil, addr buf[0], cint(tw * 4))
    GlyphEntry(texture: tex, width: tw, height: th)

  proc getOrRasterize*(a: GlyphAtlas, font: Font, text: string,
                       fontSize: float32, color: uint32,
                       fontHash: int): GlyphEntry =
    ## Looks up a cached entry; rasterizes and caches one if missing.
    ## Returns the entry whose `texture` is GPU-ready for
    ## `SDL_RenderCopy`. Texture lifetime is managed by the atlas;
    ## callers must not destroy it.
    ##
    ## Inputs:
    ## - `font`: a Pixie font. The font's `size` is mutated during
    ##   rasterization but restored to `fontSize` on each call.
    ## - `text`: the string to draw.
    ## - `fontSize`: pixel size.
    ## - `color`: ARGB8 fill color.
    ## - `fontHash`: a stable hash distinguishing this font from
    ##   others. Callers typically use `cast[int](font)` for ref
    ##   identity, or hash by font family name.
    let key = GlyphKey(text: text, fontHash: fontHash,
                       size: uint16(fontSize), color: color)
    if a.cache.hasKey(key):
      return a.cache[key]
    let entry = rasterize(a, font, fontHash, text, uint16(fontSize), color)
    a.cache[key] = entry
    a.order.add(key)
    if a.cache.len > a.maxEntries:
      a.evictOldest()
    entry

  proc clear*(a: GlyphAtlas) =
    ## Drops every cached entry, destroying textures. Call before
    ## tearing down the renderer to avoid leaking GPU memory.
    for k, e in a.cache:
      if not e.texture.isNil:
        destroyTexture(e.texture)
    a.cache.clear()
    a.order.setLen(0)
