## Bundled fallback font. Embeds Roboto Regular and Roboto Bold
## (Apache License 2.0, see assets/fonts/LICENSE-Roboto.txt) into
## the binary via `staticRead`, so every flit app has a working
## font even on systems where auto-discovery finds nothing (bare
## containers, minimal Linux images, kiosk devices).
##
## The desktop runner uses this automatically as the last-resort
## fallback. Apps can also opt in explicitly:
##
## .. code-block:: nim
##   import flit/rendering/bundled_font
##   let tf = bundledTypeface()          # pixie Typeface
##   let f  = bundledFont(size = 14)     # pixie Font, sized
##
## Embedding costs ~1 MB of binary size for the two weights. If
## that matters for your target (embedded devices), compile with
## `-d:flitNoBundledFont` to strip them; the procs then return nil
## and the runner falls back to its old "no font" warning.

when not defined(js):
  import pixie

  when not defined(flitNoBundledFont):
    const robotoRegularData = staticRead("../../../assets/fonts/Roboto-Regular.ttf")
    const robotoBoldData    = staticRead("../../../assets/fonts/Roboto-Bold.ttf")
  else:
    const robotoRegularData = ""
    const robotoBoldData    = ""

  var cachedRegular: Typeface
  var cachedBold: Typeface

  proc bundledTypeface*(): Typeface =
    ## Returns the bundled Roboto Regular typeface, parsing it on
    ## first call and caching thereafter. Returns nil when compiled
    ## with -d:flitNoBundledFont.
    when defined(flitNoBundledFont):
      nil
    else:
      if cachedRegular.isNil:
        cachedRegular = parseTtf(robotoRegularData)
      cachedRegular

  proc bundledBoldTypeface*(): Typeface =
    ## Returns the bundled Roboto Bold typeface. Same caching and
    ## -d:flitNoBundledFont behavior as `bundledTypeface`.
    when defined(flitNoBundledFont):
      nil
    else:
      if cachedBold.isNil:
        cachedBold = parseTtf(robotoBoldData)
      cachedBold

  proc bundledFont*(size: float32 = 14): Font =
    ## Returns a ready-to-use pixie Font backed by the bundled
    ## Roboto Regular at the given size. Returns nil when compiled
    ## with -d:flitNoBundledFont.
    let tf = bundledTypeface()
    if tf.isNil: return nil
    result = newFont(tf)
    result.size = size

  proc bundledBoldFont*(size: float32 = 14): Font =
    ## Bold variant of `bundledFont`.
    let tf = bundledBoldTypeface()
    if tf.isNil: return nil
    result = newFont(tf)
    result.size = size

  proc hasBundledFont*(): bool =
    ## True unless compiled with -d:flitNoBundledFont.
    not defined(flitNoBundledFont)
else:
  proc hasBundledFont*(): bool = false
