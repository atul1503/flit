## Project-wide Nim compile flags.
##
## macOS needs an explicit rpath to `/opt/homebrew/lib` (Apple Silicon)
## and `/usr/local/lib` (Intel) so the SDL2 dynlib loader can find
## `libSDL2.dylib` without `DYLD_LIBRARY_PATH` being set in the
## environment. macOS dyld since Sierra strips DYLD_LIBRARY_PATH from
## the env of child processes for SIP reasons, and the default fallback
## search paths do not include the Homebrew prefix; without an embedded
## rpath the binary fails to load libSDL2 at startup as soon as any
## SDL2 symbol is referenced anywhere in the call graph (even via a
## virtual method that is never actually called).

when defined(macosx):
  switch("passL", "-Wl,-rpath,/opt/homebrew/lib")
  switch("passL", "-Wl,-rpath,/usr/local/lib")
