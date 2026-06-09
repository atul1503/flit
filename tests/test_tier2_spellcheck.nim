## Spell check: pluggable provider + the built-in demoSpellChecker.

import std/unittest
import ../src/flit/platform/spellcheck

suite "spellcheck":
  test "default checker returns empty when no provider installed":
    activeSpellChecker = nil
    let r = checkSpelling("anything weird", "en-US")
    check r.len == 0

  test "setSpellChecker installs a custom provider":
    setSpellChecker(proc(text: string, locale: string): seq[MisspelledRange] =
      @[MisspelledRange(start: 0, length: text.len, suggestions: @[])])
    let r = checkSpelling("dummy", "en-US")
    check r.len == 1
    check r[0].start == 0
    check r[0].length == 5
    activeSpellChecker = nil

  test "demoSpellChecker flags 3+ consecutive same letters":
    let r = demoSpellChecker("loooong word", "en-US")
    check r.len == 1
    check r[0].start == 0
    check r[0].length == 7

  test "demoSpellChecker accepts clean text":
    let r = demoSpellChecker("hello world", "en-US")
    check r.len == 0

  test "demoSpellChecker flags multiple misspelled words":
    let r = demoSpellChecker("waaaay tooooo loooong", "en-US")
    check r.len == 3

  test "MisspelledRange holds suggestions":
    let m = MisspelledRange(start: 5, length: 4,
                            suggestions: @["wait", "way"])
    check m.suggestions == @["wait", "way"]
