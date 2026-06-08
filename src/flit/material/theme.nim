## Material 3 theme. Holds the color scheme, typography and shape tokens
## that Material widgets (`AppBar`, `ElevatedButton`, `Card`, etc.)
## read via the ambient theme accessor `currentTheme()`.
##
## To set the theme: either let `MaterialApp` install it (the standard
## path), or call `setTheme(themeData(...))` directly before constructing
## a tree that uses Material widgets.

import ../foundation/[color, geometry]
import ../rendering/text

type
  Brightness* = enum
    ## Whether the theme is intended for light or dark surfaces.
    ## `bLight` swaps to the dark scheme via `themeData(bDark)`.
    bLight, bDark

  ColorScheme* = object
    ## Material 3 color roles. Pair each "X" color with the "onX"
    ## color used for content drawn ON TOP of it.
    primary*:        Color  ## brand accent (buttons, FABs).
    onPrimary*:      Color  ## text/icons drawn on `primary`.
    primaryContainer*: Color  ## tinted surface for primary content.
    secondary*:      Color  ## supporting accent.
    onSecondary*:    Color  ## text/icons drawn on `secondary`.
    background*:     Color  ## page background.
    onBackground*:   Color  ## text on `background`.
    surface*:        Color  ## elevated surface (cards, sheets).
    onSurface*:      Color  ## text on `surface`.
    error*:          Color  ## error indication color.
    onError*:        Color  ## text/icons on `error`.
    outline*:        Color  ## subtle borders / dividers.

  Typography* = object
    ## A small set of named text styles roughly matching Material 3's
    ## scale. Widgets pick whichever matches their role (a title bar
    ## uses `titleLarge`, body text uses `bodyMedium`, etc.).
    displayLarge*:   TextStyle
    headlineLarge*:  TextStyle
    titleLarge*:     TextStyle
    bodyLarge*:      TextStyle
    bodyMedium*:     TextStyle
    bodySmall*:      TextStyle
    labelLarge*:     TextStyle

  ThemeData* = object
    ## Complete bundle of theme tokens. Material widgets read this
    ## (via `currentTheme()`) to pick colors and type styles.
    brightness*:    Brightness
    colorScheme*:   ColorScheme
    typography*:    Typography
    defaultRadius*: float32   ## rounding for cards and surfaces.
    fontFamily*:    string

const defaultLightScheme* = ColorScheme(
    ## Default Material 3 light color scheme. Used when
    ## `themeData(bLight)` is called.
  primary: rgb(98, 0, 238), onPrimary: colorWhite,
  primaryContainer: rgb(234, 221, 255),
  secondary: rgb(98, 91, 113), onSecondary: colorWhite,
  background: rgb(255, 251, 254), onBackground: rgb(28, 27, 31),
  surface: colorWhite, onSurface: rgb(28, 27, 31),
  error: rgb(179, 38, 30), onError: colorWhite,
  outline: rgb(121, 116, 126))

const defaultDarkScheme* = ColorScheme(
    ## Default Material 3 dark color scheme. Used when
    ## `themeData(bDark)` is called.
  primary: rgb(208, 188, 255), onPrimary: rgb(56, 30, 114),
  primaryContainer: rgb(79, 55, 139),
  secondary: rgb(204, 194, 220), onSecondary: rgb(50, 47, 65),
  background: rgb(28, 27, 31), onBackground: rgb(230, 225, 229),
  surface: rgb(28, 27, 31), onSurface: rgb(230, 225, 229),
  error: rgb(242, 184, 181), onError: rgb(96, 20, 16),
  outline: rgb(147, 143, 153))

proc defaultTypography*(fontFamily = "system"): Typography =
  ## Builds the default Material type scale using `fontFamily` for all
  ## styles. Override individual `TextStyle` entries on the returned
  ## value to customize.
  Typography(
    displayLarge:  textStyle(fontSize = 57, fontFamily = fontFamily, fontWeight = 400),
    headlineLarge: textStyle(fontSize = 32, fontFamily = fontFamily, fontWeight = 400),
    titleLarge:    textStyle(fontSize = 22, fontFamily = fontFamily, fontWeight = 500),
    bodyLarge:     textStyle(fontSize = 16, fontFamily = fontFamily, fontWeight = 400),
    bodyMedium:    textStyle(fontSize = 14, fontFamily = fontFamily, fontWeight = 400),
    bodySmall:     textStyle(fontSize = 12, fontFamily = fontFamily, fontWeight = 400),
    labelLarge:    textStyle(fontSize = 14, fontFamily = fontFamily, fontWeight = 500))

proc themeData*(brightness = bLight, fontFamily = "system",
                defaultRadius = 12.0'f32): ThemeData =
  ## Builds a `ThemeData` from a small set of high-level parameters.
  ##
  ## Inputs:
  ## - `brightness`: `bLight` (default) or `bDark`. Selects the
  ##   color scheme.
  ## - `fontFamily`: default font family for every typography role.
  ## - `defaultRadius`: rounding applied to cards and surfaces.
  ##
  ## Output: a populated `ThemeData`. Install via `setTheme(...)` or
  ## by passing to `materialApp(theme = ...)`.
  let scheme = if brightness == bLight: defaultLightScheme else: defaultDarkScheme
  ThemeData(brightness: brightness, colorScheme: scheme,
            typography: defaultTypography(fontFamily),
            defaultRadius: defaultRadius, fontFamily: fontFamily)

# Ambient theme. Single mutable var that Material widgets read in
# `build()`. Set BEFORE constructing the tree so children see the
# new value.

var currentThemeVar*: ThemeData = themeData()
  ## The current theme. Read it via `currentTheme()`. Replace via
  ## `setTheme(t)` or by mounting a `MaterialApp` with a different
  ## `theme` field.

proc currentTheme*(): ThemeData = currentThemeVar
  ## Returns the active theme. Material widgets call this during
  ## their `build` to pick colors and styles.

proc setTheme*(t: ThemeData) = currentThemeVar = t
  ## Replaces the active theme. Has no automatic rebuild effect; the
  ## caller is responsible for triggering a rebuild (typically via
  ## `setState` on the root stateful widget).

# Backward-compatible aliases for the old push/pop API.

proc pushTheme*(t: ThemeData) = setTheme(t)
  ## Deprecated alias for `setTheme`. Kept for code that predates the
  ## switch from a stack-based theme model.

proc popTheme*() = discard
  ## Deprecated no-op. The push/pop stack is gone; nothing to pop.
