# 12. Building for every platform

flit targets seven platforms from one codebase: macOS, Linux,
Windows, web, iOS, Android, and embedded Linux. This page covers
the build command, expected artifact, and runtime requirements
for each.

## Quick reference

| Target | CLI | Artifact | Runs where |
|--------|-----|----------|------------|
| macOS | `flit build macos` | `bin/<name>` Mach-O | Any Mac |
| Linux | `flit build linux` | `bin/<name>` ELF | Any Linux with SDL2 + HarfBuzz |
| Windows | `flit build windows` | `bin/<name>.exe` | Any Windows with SDL2 + HarfBuzz |
| Web | `flit build web` | `web/app.js` | Any modern browser |
| iOS | `flit build ipa` | `build/ios/<name>` ARM64 binary | Wrap in Xcode for device install |
| Android | `flit build apk` | `build/android/lib<name>.so` | Wrap in Android Studio for APK |
| Embedded | `nim c -d:flitEmbedded ...` | Native binary | Any Linux with framebuffer access |

## macOS

```
nim c -d:release --opt:speed -o:bin/counter examples/counter/main.nim
./bin/counter
```

Produces a Mach-O binary that links dynamically to libSDL2 and
libharfbuzz from Homebrew. Requires:

- `brew install sdl2 harfbuzz`
- macOS 11+ (Big Sur or later)
- arm64 or x86_64

The desktop runner auto-discovers a system font on macOS, so no
font configuration is needed.

## Linux

```
nim c -d:release --opt:speed -o:bin/counter examples/counter/main.nim
./bin/counter
```

Requires:

- `sudo apt install libsdl2-dev libharfbuzz-dev` (Debian / Ubuntu)
- `sudo dnf install SDL2-devel harfbuzz-devel` (Fedora / RHEL)
- glibc 2.31+

System fonts are auto-discovered from `/usr/share/fonts/`. If your
distribution puts fonts elsewhere, pass an explicit path via
`DesktopWindowConfig.fontPath`.

## Windows

```
nim c -d:release --opt:speed -o:bin/counter.exe examples/counter/main.nim
.\bin\counter.exe
```

Requires SDL2 and HarfBuzz DLLs in the same directory as the
binary, or on `%PATH%`. Install via:

- `choco install sdl2`
- `vcpkg install sdl2 harfbuzz` (then add the install dir to PATH)

Auto font discovery checks `C:\Windows\Fonts\arial.ttf`.

## Web

```
nim js -d:release -o:web/app.js examples/counter/web.nim
```

Produces a single JavaScript file. Pair with an HTML harness:

```html
<!doctype html>
<html><body>
  <canvas id="flit-canvas" width="1024" height="768"></canvas>
  <script src="app.js"></script>
</body></html>
```

The web runner uses HTML5 Canvas 2D for paint. No SDL, no
HarfBuzz, no native code. Bundle size is around 500-600 KB
uncompressed; gzip cuts it to roughly 100 KB.

Note: the web entry point file must import flit directly, not
just the main.nim of your app, because Nim's import semantics
don't re-export transitively.

```nim
import ../../src/flit       # required for runApp
import ./main               # required for your Counter type

when isMainModule:
  runApp(Counter(), "flit-canvas")
```

## iOS

```
nim c -d:release -d:ios --os:ios --cpu:arm64 \
  -o:build/ios/counter examples/counter/main.nim
```

Produces an ARM64 Mach-O binary for iOS. To turn it into an
installable `.ipa`:

1. Create an Xcode project for an iOS app.
2. Add the produced binary as a library target.
3. Link SDL2 (XCFramework from libsdl-org/SDL).
4. Configure provisioning and code signing.
5. Build for device.

flit does not ship the Xcode wrapper today. Adding one is on the
roadmap; for now the binary is the artifact and the wrapper is
manual.

## Android

```
nim c -d:release -d:android --os:android --cpu:arm64 \
  -o:build/android/libcounter.so examples/counter/main.nim
```

Produces an ARM64 shared library. The Android JNI wrapper around
SDL2 loads this `.so` at runtime. To package as an APK:

1. Use SDL2's official Android project template
   (`SDL/android-project/` in the SDL source tree).
2. Drop the `.so` into `app/jniLibs/arm64-v8a/`.
3. Run `./gradlew assembleRelease`.

Same caveat as iOS: flit doesn't ship the Gradle wrapper. PRs
welcome.

## Embedded Linux

```
nim c -d:release -d:flitEmbedded \
  -o:bin/kiosk examples/embedded/main.nim
```

Produces a native binary that doesn't open a window. Your code
provides a `flush` callback that receives ARGB pixels each frame
and writes them to whatever output you control:

```nim
proc flushToFramebuffer(pixels: ptr UncheckedArray[uint32],
                       w, h: int) =
  let fb = open("/dev/fb0", fmReadWrite)
  defer: fb.close()
  fb.write(toOpenArray(cast[ptr UncheckedArray[byte]](pixels),
                       0, w * h * 4 - 1))

runApp(KioskApp(), width = 1920, height = 1080,
       flush = flushToFramebuffer, frameRateHz = 30)
```

Common targets: Raspberry Pi kiosks, industrial HMI displays,
custom devices with /dev/fb0 or DRM output.

## Cross-compiling

Nim cross-compiles cleanly from macOS / Linux / Windows to all
targets if you have the right toolchain. On macOS:

- macOS to Linux: install `aarch64-elf-gcc` or `x86_64-elf-gcc`
  via Homebrew, then `nim c --os:linux --cpu:amd64 ...`
- macOS to Windows: install mingw-w64 via Homebrew, then
  `nim c --os:windows --cpu:amd64 ...`
- macOS to iOS: built-in (Xcode toolchain is the host compiler)
- macOS to Android: needs the Android NDK; set `CC` and `AR` to
  the NDK's `aarch64-linux-android30-clang` and `llvm-ar`.

flit's CI (`.github/workflows/ci.yml`) does native builds on
macOS, Linux, and Windows for every push. Cross builds are not
in CI today because the toolchain setup is per-host.

## Smoke test: compile every target locally

The repo's test suite covers the framework; here is a one-shot
script that confirms every target at least compiles:

```bash
# Native macOS (run on macOS)
nim c -c examples/counter/main.nim

# Cross-compile to other OSes (compile-only; no link toolchain
# needed for `-c`)
nim c --os:linux   --cpu:amd64 -c examples/counter/main.nim
nim c --os:windows --cpu:amd64 -c examples/counter/main.nim
nim c --os:ios     --cpu:arm64 -c examples/counter/main.nim
nim c --os:android --cpu:arm64 -c examples/counter/main.nim

# Web
nim js -o:/tmp/app.js examples/counter/web.nim

# Embedded
nim c -d:flitEmbedded -c examples/embedded/main.nim
```

If all of those succeed, the codebase compiles cleanly for every
target flit supports.
