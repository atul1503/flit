## Spell check. Returns ranges of misspelled words in a string so
## the TextField (or any text-rendering widget) can draw squiggle
## underlines.
##
## Native APIs:
## - macOS: `NSSpellChecker.sharedSpellChecker.checkSpellingOfString`
## - Linux: Hunspell via `libhunspell`
## - Windows: `Windows.Globalization.SpellCheckGenerator`
##
## Each is a real binding job. This module exposes the public API
## and a pluggable provider; ships a tiny built-in checker that
## flags only words containing weird patterns (no real dictionary).
## Real integrations register via `setSpellChecker(fn)`.

import std/strutils

type
  MisspelledRange* = object
    ## Byte offsets into the checked string for a single
    ## misspelled word. `suggestions` are alternatives (best
    ## first); may be empty.
    start*:        int
    length*:       int
    suggestions*:  seq[string]

  SpellChecker* = proc(text: string, locale: string): seq[MisspelledRange] {.closure.}

var activeSpellChecker* {.threadvar.}: SpellChecker

proc defaultSpellChecker(text: string, locale: string): seq[MisspelledRange] =
  ## Trivial built-in: returns no misspellings. Replaces with a
  ## real provider via `setSpellChecker`.
  @[]

proc setSpellChecker*(fn: SpellChecker) =
  ## Installs a spell-check provider. Apps that integrate Hunspell
  ## or platform spell check call this once at startup.
  activeSpellChecker = fn

proc checkSpelling*(text: string, locale: string = "en-US"): seq[MisspelledRange] =
  ## Returns a sequence of misspelled-word ranges in `text`. Empty
  ## seq means "all good." When no spell-check provider is
  ## installed, always returns empty.
  if activeSpellChecker.isNil:
    return defaultSpellChecker(text, locale)
  activeSpellChecker(text, locale)

# A *very* basic example checker that flags repeated letters
# (three or more of the same character in a row) as a common typo.
# Not a substitute for a real dictionary; use as a starting point
# for testing your wiring.

proc demoSpellChecker*(text: string, locale: string): seq[MisspelledRange] =
  ## Demo / smoke-test checker. Flags words with 3+ consecutive
  ## identical letters (e.g. "aaaa", "loooong"). Not a real
  ## spell check; just enough to verify the underline path works.
  var i = 0
  while i < text.len:
    # Find start of a word.
    while i < text.len and not text[i].isAlphaAscii: inc i
    let wordStart = i
    while i < text.len and text[i].isAlphaAscii: inc i
    let word = text[wordStart ..< i]
    var run = 1
    var maxRun = 1
    for j in 1 ..< word.len:
      if word[j] == word[j-1]: inc run
      else: run = 1
      if run > maxRun: maxRun = run
    if maxRun >= 3:
      result.add(MisspelledRange(
        start: wordStart, length: word.len,
        suggestions: @[]))
