## Locale-aware date / number / currency formatting.
##
## Native APIs:
## - macOS: `NSNumberFormatter`, `NSDateFormatter`
## - Linux: ICU (`libicu`) or the C `strftime` / `setlocale`
## - Windows: `Windows.Globalization.NumberFormatting`
##
## This module ships a pure-Nim implementation that handles the
## common cases (English, German, French, Japanese number /
## currency separators; ISO-8601 dates). Real CLDR coverage
## would mean shipping the CLDR data or binding to ICU.

import std/[times, strutils, strformat]

type
  NumberFormat* = enum
    ## What kind of number a value represents. Drives which
    ## formatter to call (`formatNumber`, `formatPercent`,
    ## `formatCurrency`). Exposed for users building dynamic
    ## formatter dispatch on top of this module.
    nfDecimal, nfPercent, nfCurrency

  LocaleConfig* = object
    ## Per-locale separators and currency settings. Returned by
    ## `localeFor`. Pass a custom `LocaleConfig` to extend beyond
    ## the built-in locales.
    locale*:     string         # BCP-47 (e.g. "en-US", "de-DE", "ja-JP")
    decimal*:    string         # "." or ","
    thousands*:  string         # "," or "." or " "
    currency*:   string         # "USD", "EUR", "JPY"
    currencyBeforeAmount*: bool # "$10" vs "10€"

# Built-in locales. Extend by passing a custom LocaleConfig.

proc localeFor*(locale: string): LocaleConfig =
  ## Returns the `LocaleConfig` for a BCP-47 locale string.
  ## Accepts both dash and underscore forms (`"en-US"` /
  ## `"en_US"`). Falls back to en-US when the locale is unknown.
  ##
  ## Built-in locales: en-US, en-GB, de-DE, fr-FR, ja-JP, hi-IN.
  ## Extend by constructing your own `LocaleConfig` and passing
  ## it directly to the formatters that take one.
  case locale.replace("_", "-")
  of "en-US", "en":
    LocaleConfig(locale: "en-US", decimal: ".", thousands: ",",
                 currency: "USD", currencyBeforeAmount: true)
  of "en-GB":
    LocaleConfig(locale: "en-GB", decimal: ".", thousands: ",",
                 currency: "GBP", currencyBeforeAmount: true)
  of "de-DE", "de":
    LocaleConfig(locale: "de-DE", decimal: ",", thousands: ".",
                 currency: "EUR", currencyBeforeAmount: false)
  of "fr-FR", "fr":
    LocaleConfig(locale: "fr-FR", decimal: ",", thousands: " ",
                 currency: "EUR", currencyBeforeAmount: false)
  of "ja-JP", "ja":
    LocaleConfig(locale: "ja-JP", decimal: ".", thousands: ",",
                 currency: "JPY", currencyBeforeAmount: true)
  of "hi-IN", "hi":
    LocaleConfig(locale: "hi-IN", decimal: ".", thousands: ",",
                 currency: "INR", currencyBeforeAmount: true)
  else:
    # Fallback to en-US.
    LocaleConfig(locale: "en-US", decimal: ".", thousands: ",",
                 currency: "USD", currencyBeforeAmount: true)

proc formatNumber*(n: float, decimals: int = 2,
                  locale: string = "en-US"): string =
  ## Formats a number with the locale's decimal and thousands
  ## separators. `decimals` is how many fractional digits to show.
  let cfg = localeFor(locale)
  var s = formatFloat(n, ffDecimal, decimals)
  let dotIdx = s.find(".")
  var intPart = if dotIdx >= 0: s[0 ..< dotIdx] else: s
  let fracPart = if dotIdx >= 0: s[dotIdx + 1 ..< s.len] else: ""
  let neg = intPart.startsWith("-")
  if neg: intPart = intPart[1 ..< intPart.len]
  # Insert thousands separators every 3 digits from the right.
  var grouped = ""
  var count = 0
  for i in countdown(intPart.high, 0):
    if count > 0 and count mod 3 == 0:
      grouped = cfg.thousands & grouped
    grouped = $intPart[i] & grouped
    inc count
  result = (if neg: "-" else: "") & grouped
  if decimals > 0:
    result.add(cfg.decimal & fracPart)

proc formatCurrency*(n: float, currency: string = "",
                    locale: string = "en-US"): string =
  ## Formats `n` as a currency amount in the given (or locale's
  ## default) currency. Default 2 decimal places, except JPY
  ## which traditionally shows none.
  let cfg = localeFor(locale)
  let cur = if currency.len > 0: currency else: cfg.currency
  let decimals = if cur == "JPY": 0 else: 2
  let amount = formatNumber(n, decimals, locale)
  case cur
  of "USD": (if cfg.currencyBeforeAmount: "$" & amount else: amount & " $")
  of "GBP": (if cfg.currencyBeforeAmount: "£" & amount else: amount & " £")
  of "EUR": (if cfg.currencyBeforeAmount: "€" & amount else: amount & " €")
  of "JPY": (if cfg.currencyBeforeAmount: "¥" & amount else: amount & " ¥")
  of "INR": (if cfg.currencyBeforeAmount: "₹" & amount else: amount & " ₹")
  else:     (if cfg.currencyBeforeAmount: cur & " " & amount
             else: amount & " " & cur)

proc formatPercent*(n: float, decimals: int = 1,
                   locale: string = "en-US"): string =
  ## Formats a fraction in `[0, 1]` as a percentage. 0.456 → "45.6%".
  formatNumber(n * 100.0, decimals, locale) & "%"

proc formatDate*(t: DateTime, pattern: string = "yyyy-MM-dd",
                locale: string = "en-US"): string =
  ## Formats a date with the given pattern. Patterns follow Nim's
  ## `times` format directives; locale-aware month / weekday names
  ## are not implemented (Nim's `format` uses English; full CLDR
  ## locale data would need shipping).
  t.format(pattern)
