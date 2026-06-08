## Material 3 theme. Holds the color scheme, typography and shape tokens
## that Material widgets read via the ambient Theme.

import ../foundation/[color, geometry]
import ../rendering/text

type
  Brightness* = enum
    bLight, bDark

  ColorScheme* = object
    primary*:        Color
    onPrimary*:      Color
    primaryContainer*: Color
    secondary*:      Color
    onSecondary*:    Color
    background*:     Color
    onBackground*:   Color
    surface*:        Color
    onSurface*:      Color
    error*:          Color
    onError*:        Color
    outline*:        Color

  Typography* = object
    displayLarge*:   TextStyle
    headlineLarge*:  TextStyle
    titleLarge*:     TextStyle
    bodyLarge*:      TextStyle
    bodyMedium*:     TextStyle
    bodySmall*:      TextStyle
    labelLarge*:     TextStyle

  ThemeData* = object
    brightness*:    Brightness
    colorScheme*:   ColorScheme
    typography*:    Typography
    defaultRadius*: float32
    fontFamily*:    string

const defaultLightScheme* = ColorScheme(
  primary: rgb(98, 0, 238), onPrimary: colorWhite,
  primaryContainer: rgb(234, 221, 255),
  secondary: rgb(98, 91, 113), onSecondary: colorWhite,
  background: rgb(255, 251, 254), onBackground: rgb(28, 27, 31),
  surface: colorWhite, onSurface: rgb(28, 27, 31),
  error: rgb(179, 38, 30), onError: colorWhite,
  outline: rgb(121, 116, 126))

const defaultDarkScheme* = ColorScheme(
  primary: rgb(208, 188, 255), onPrimary: rgb(56, 30, 114),
  primaryContainer: rgb(79, 55, 139),
  secondary: rgb(204, 194, 220), onSecondary: rgb(50, 47, 65),
  background: rgb(28, 27, 31), onBackground: rgb(230, 225, 229),
  surface: rgb(28, 27, 31), onSurface: rgb(230, 225, 229),
  error: rgb(242, 184, 181), onError: rgb(96, 20, 16),
  outline: rgb(147, 143, 153))

proc defaultTypography*(fontFamily = "system"): Typography =
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
  let scheme = if brightness == bLight: defaultLightScheme else: defaultDarkScheme
  ThemeData(brightness: brightness, colorScheme: scheme,
            typography: defaultTypography(fontFamily),
            defaultRadius: defaultRadius, fontFamily: fontFamily)

# Ambient theme. Replaces the previous push/pop stack: that pattern only
# helped when nested subtrees needed local overrides, and it didn't update
# parent-visible state when MaterialApp.build re-pushed, because the user's
# tree was already constructed by then (capturing the OLD top of stack).
#
# Now currentTheme is a single var the app can set BEFORE constructing the
# tree, so every `let scheme = currentTheme().colorScheme` line in user
# code reads the freshly-set value.

var currentThemeVar*: ThemeData = themeData()

proc currentTheme*(): ThemeData = currentThemeVar
proc setTheme*(t: ThemeData) = currentThemeVar = t

# Backward-compatible aliases.
proc pushTheme*(t: ThemeData) = setTheme(t)
proc popTheme*() = discard
