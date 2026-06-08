# 08. The flit command

`flit` is a project scaffold and runner modeled on Flutter's CLI. Once
you've run `nimble install` from the flit checkout, the `flit` binary
is on your `$PATH`.

## Commands at a glance

```
flit create <name>    create a new flit project
flit run              compile and run for the current platform
flit build <target>   build an app bundle (apk/ipa/web/macos/linux/windows)
flit doctor           diagnose your toolchain
flit devices          list attached devices
flit clean            remove build artifacts
flit pub get          install the project's nimble deps
flit upgrade          update flit
flit hot              run with hot reload (file watcher)
flit --version        print version
```

## flit create

Lays down a starter project:

```
flit create my_app
```

Produces:

```
my_app/
  src/my_app.nim       counter widget
  my_app.nimble        nimble manifest with flit dependency
  assets/              empty; put images, fonts here
  web/index.html       HTML harness for the web build
  .gitignore
  README.md
```

Then:

```
cd my_app
nimble install
flit run
```

## flit run

Picks the right platform based on which binary host you are on (macOS,
Linux, Windows). Compiles in release mode with `--hints:off`, runs the
result.

Equivalent to:

```
nim c -r --hints:off -d:release -o:bin/<name> src/<name>.nim
```

## flit build

Targeted builds:

| Target | What it does |
|--------|--------------|
| `flit build macos` | Native macOS binary in `bin/<name>` |
| `flit build linux` | Native Linux binary |
| `flit build windows` | Native Windows binary |
| `flit build web` | Nim JS backend, output to `web/app.js` |
| `flit build apk` | Android ARM64 shared object in `build/android/lib<name>.so` |
| `flit build ipa` | iOS ARM64 binary in `build/ios/<name>` |

The mobile targets compile flit's code; you still need an Android Studio
or Xcode shell to wrap the binary into an installable artifact.

## flit doctor

Reports the state of your toolchain:

```
flit doctor
```

Sample output:

```
flit doctor
  flit version       : 0.7.0
  os                 : MacOSX
  cpu                : arm64
  nim                : /opt/homebrew/bin/nim
  nimble             : /opt/homebrew/bin/nimble
  android adb        : /Users/.../platform-tools/adb
  xcode xcrun        : /usr/bin/xcrun
  pkg-config (sdl2)  : 2.32.10
```

If any field is empty, install the corresponding tool.

## flit devices

Lists connected Android and iOS devices:

```
flit devices
```

Calls `adb devices -l` and `xcrun xctrace list devices` under the hood.

## flit clean

Removes build artifacts:

```
flit clean
```

Wipes `nimcache/`, `bin/`, `build/`, `web/app.js`, `web/app.js.map`.

## flit hot

Watches `src/` for changes; rebuilds and restarts the child binary on
each save:

```
flit hot
```

Polls file modification times every 500ms. Not a true HMR (the binary
restarts and loses state), but fast enough that an edit-save-see cycle
takes under a second for small projects.

For widgets, state is lost. For pure UI tweaks, the visual change
appears as fast as Nim can compile the file.

## flit pub get

Alias for `nimble install --depsOnly`. Installs the project's
dependencies without installing the project itself.

## flit upgrade

Updates flit itself via nimble:

```
flit upgrade
```

Run this after pulling a new flit release.

## Common workflows

### Start a fresh project

```
flit create dashboard
cd dashboard
flit pub get
flit run
```

### Add a dependency

Edit `dashboard.nimble`:

```nim
requires "flit >= 0.7.0"
requires "ws"              # new
```

Then:

```
flit pub get
```

### Build a release for distribution

```
flit clean
flit build macos    # or linux, windows, web
ls bin/             # binary is here
```

### Develop with auto-reload

```
flit hot
# edit src/dashboard.nim; on save, watcher rebuilds and re-launches
```

## Next step

Read `09-examples-tour.md` for a walk through the shipped examples.
