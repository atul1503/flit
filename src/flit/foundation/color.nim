## Color model. A 32-bit ARGB value packed into a `uint32`, mirroring
## Flutter's `dart:ui` `Color`. The byte order is `0xAARRGGBB`:
## alpha in the highest 8 bits, then red, green, blue.
##
## All operations are pure: they return new `Color` values rather than
## mutating inputs.

import std/strutils

type
  Color* = object
    ## A 32-bit packed ARGB color value. Read components via `alpha`,
    ## `red`, `green`, `blue`. Build via `rgb`, `rgba`, `fromARGB`,
    ## `fromHex`, or pick a constant like `colorRed`.
    value*: uint32

proc color*(value: uint32): Color =
  ## Builds a `Color` from a raw `0xAARRGGBB` integer.
  Color(value: value)

proc rgba*(r, g, b, a: uint8): Color =
  ## Builds a `Color` from four 0..255 channels.
  Color(value: (uint32(a) shl 24) or (uint32(r) shl 16) or
                (uint32(g) shl 8)  or  uint32(b))

proc rgb*(r, g, b: uint8): Color = rgba(r, g, b, 255)
  ## Builds an opaque `Color` (alpha 255).

proc fromARGB*(a, r, g, b: uint8): Color = rgba(r, g, b, a)
  ## Builds a `Color` from ARGB components in Flutter's argument order.

proc fromHex*(hex: string): Color =
  ## Parses a CSS-style hex string. Accepts `"#RRGGBB"`, `"#AARRGGBB"`,
  ## `"RRGGBB"`, or `"AARRGGBB"`. Six-character inputs are taken as
  ## fully opaque. Raises `ValueError` for any other length.
  var s = hex
  if s.startsWith("#"): s = s[1..^1]
  case s.len
  of 6: Color(value: 0xFF000000'u32 or parseHexInt(s).uint32)
  of 8: Color(value: parseHexInt(s).uint32)
  else: raise newException(ValueError, "invalid hex color: " & hex)

proc alpha*(c: Color): uint8 = uint8((c.value shr 24) and 0xFF)
  ## Extracts the alpha channel (0 = transparent, 255 = opaque).
proc red*(c: Color):   uint8 = uint8((c.value shr 16) and 0xFF)
  ## Extracts the red channel.
proc green*(c: Color): uint8 = uint8((c.value shr 8)  and 0xFF)
  ## Extracts the green channel.
proc blue*(c: Color):  uint8 = uint8( c.value         and 0xFF)
  ## Extracts the blue channel.

proc withAlpha*(c: Color, a: uint8): Color =
  ## Returns a copy of `c` with the alpha channel set to `a`. Red,
  ## green, blue are preserved.
  Color(value: (c.value and 0x00FFFFFF'u32) or (uint32(a) shl 24))

proc withOpacity*(c: Color, opacity: float32): Color =
  ## Returns a copy of `c` with the alpha channel REPLACED by
  ## `clamp(opacity, 0, 1) * 255`. Matches Flutter's `Color.withOpacity`:
  ## the original alpha is discarded.
  withAlpha(c, uint8(clamp(opacity, 0.0, 1.0) * 255))

proc opacity*(c: Color): float32 = float32(alpha(c)) / 255.0
  ## Returns the alpha channel as a 0..1 float.

proc lerp*(a, b: Color, t: float32): Color =
  ## Linear interpolation between two colors, component-wise. `t = 0`
  ## returns `a`, `t = 1` returns `b`. Each channel is clamped to
  ## `[0, 255]` so out-of-range `t` values are safe.
  proc mix(x, y: uint8): uint8 =
    uint8(clamp(float32(x) + (float32(y) - float32(x)) * t, 0.0, 255.0))
  rgba(mix(a.red, b.red), mix(a.green, b.green), mix(a.blue, b.blue),
       mix(a.alpha, b.alpha))

proc `==`*(a, b: Color): bool = a.value == b.value
  ## Two colors are equal when their packed values match.
proc `$`*(c: Color): string = "#" & toHex(c.value, 8)
  ## Hex string in `"#AARRGGBB"` form.

# Common colors

const
  colorTransparent* = Color(value: 0x00000000'u32)
    ## Fully transparent black. Default for unset color fields.
  colorBlack*       = Color(value: 0xFF000000'u32)
  colorWhite*       = Color(value: 0xFFFFFFFF'u32)
  colorRed*         = Color(value: 0xFFF44336'u32)
    ## Material red 500.
  colorGreen*       = Color(value: 0xFF4CAF50'u32)
    ## Material green 500.
  colorBlue*        = Color(value: 0xFF2196F3'u32)
    ## Material blue 500.
  colorYellow*      = Color(value: 0xFFFFEB3B'u32)
  colorOrange*      = Color(value: 0xFFFF9800'u32)
  colorPurple*      = Color(value: 0xFF9C27B0'u32)
  colorPink*        = Color(value: 0xFFE91E63'u32)
  colorTeal*        = Color(value: 0xFF009688'u32)
  colorIndigo*      = Color(value: 0xFF3F51B5'u32)
  colorCyan*        = Color(value: 0xFF00BCD4'u32)
  colorAmber*       = Color(value: 0xFFFFC107'u32)
  colorGrey*        = Color(value: 0xFF9E9E9E'u32)
  colorBrown*       = Color(value: 0xFF795548'u32)
  colorBlueGrey*    = Color(value: 0xFF607D8B'u32)
