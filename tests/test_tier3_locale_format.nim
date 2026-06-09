## Locale-aware number / currency / percent / date formatting.

import std/[unittest, times]
import ../src/flit/platform/locale_format

suite "localeFor":
  test "en-US":
    let c = localeFor("en-US")
    check c.decimal == "."
    check c.thousands == ","
    check c.currency == "USD"
    check c.currencyBeforeAmount

  test "de-DE swaps decimal and thousands":
    let c = localeFor("de-DE")
    check c.decimal == ","
    check c.thousands == "."
    check c.currency == "EUR"
    check not c.currencyBeforeAmount

  test "fr-FR uses space thousands":
    let c = localeFor("fr-FR")
    check c.thousands == " "
    check c.decimal == ","

  test "ja-JP uses JPY":
    let c = localeFor("ja-JP")
    check c.currency == "JPY"

  test "hi-IN uses INR":
    let c = localeFor("hi-IN")
    check c.currency == "INR"

  test "unknown locale falls back to en-US":
    let c = localeFor("xx-YY")
    check c.locale == "en-US"

  test "underscore form normalises (en_US)":
    let c = localeFor("en_US")
    check c.locale == "en-US"

suite "formatNumber":
  test "en-US groups thousands with commas":
    check formatNumber(1234567.89, 2, "en-US") == "1,234,567.89"

  test "de-DE groups thousands with dots and uses comma decimal":
    check formatNumber(1234567.89, 2, "de-DE") == "1.234.567,89"

  test "fr-FR groups thousands with spaces":
    check formatNumber(1234.5, 2, "fr-FR") == "1 234,50"

  test "zero decimals omits the fractional part":
    check formatNumber(42.0, 0, "en-US") == "42"

  test "negative numbers keep the minus sign":
    check formatNumber(-1234.5, 1, "en-US") == "-1,234.5"

  test "small numbers (no thousands) format correctly":
    check formatNumber(5.0, 2, "en-US") == "5.00"

suite "formatCurrency":
  test "en-US uses $ before amount":
    check formatCurrency(99.95, "USD", "en-US") == "$99.95"

  test "de-DE uses € after amount":
    check formatCurrency(99.95, "EUR", "de-DE") == "99,95 €"

  test "JPY has no decimals":
    check formatCurrency(1500.0, "JPY", "ja-JP") == "¥1,500"

  test "GBP en-GB uses £":
    check formatCurrency(10.0, "GBP", "en-GB") == "£10.00"

  test "INR hi-IN uses ₹":
    check formatCurrency(100.0, "INR", "hi-IN") == "₹100.00"

  test "blank currency falls back to locale's currency":
    check formatCurrency(50.0, "", "en-US") == "$50.00"

suite "formatPercent":
  test "0.456 -> 45.6%":
    check formatPercent(0.456, 1, "en-US") == "45.6%"

  test "0 decimals":
    check formatPercent(0.5, 0, "en-US") == "50%"

  test "de-DE uses comma for decimal":
    check formatPercent(0.123, 1, "de-DE") == "12,3%"

suite "formatDate":
  test "default pattern is yyyy-MM-dd":
    let d = dateTime(2024, mJan, 15, zone = utc())
    check formatDate(d) == "2024-01-15"

  test "custom pattern applies":
    let d = dateTime(2024, mDec, 25, zone = utc())
    check formatDate(d, "dd/MM/yyyy") == "25/12/2024"
