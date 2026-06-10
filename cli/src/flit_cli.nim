## `flit` CLI: project scaffold, dev runner with hot reload, and per-platform
## builders modeled after the Flutter CLI.
##
## Usage:
##   flit create my_app
##   flit run                # current dir, auto-detect platform
##   flit build apk          # android
##   flit build ipa          # ios
##   flit build web          # nim js
##   flit build macos|linux|windows
##   flit doctor             # check toolchain
##   flit clean
##   flit pub get            # alias for `nimble install`
##   flit devices            # connected adb/xcrun devices
##   flit upgrade            # update flit itself

import std/[os, osproc, strutils, strformat, parseopt, tables, times]

const flitVersion* = "0.13.0"

proc usage() =
  echo """
flit v""" & flitVersion & """, a Flutter-style cross-platform UI toolkit for Nim.

Common commands:

  flit create <name>           create a new flit project
  flit run [--device <id>]     compile and run for the current platform
  flit build <target>          build an app bundle (apk/ipa/web/macos/linux/windows)
  flit doctor                  diagnose your toolchain
  flit devices                 list attached devices
  flit clean                   remove build artifacts
  flit pub get                 nimble install the project's deps
  flit upgrade                 update flit
  flit hot                     run with hot reload watcher

Run `flit <command> -h` for command-specific help.
"""

# ----- create -----

const sampleMain = """
import flit

type
  App* = ref object of StatefulWidget
  AppState = ref object of State
    count: int

method widgetTypeName*(w: App): string = "App"
method createElement*(w: App): Element = newElement(ekStateful, w)
method createState*(w: App): State = AppState(count: 0)
method build*(s: AppState, ctx: BuildContext): Widget =
  materialApp(home = scaffold(
    appBar = appBar(title = text("$1")),
    body = center(child = column(mainAxisAlignment = maCenter, children = @[
      Widget(text("Tap the button.")),
      text($$s.count, style = textStyle(fontSize = 40))])),
    floatingActionButton = floatingActionButton(
      child = text("+", style = textStyle(fontSize = 28, color = colorWhite)),
      onPressed = proc() = setState(s, proc() = inc s.count))))

when isMainModule: runApp(App())
"""

const sampleNimble = """
# Package

version       = "0.1.0"
author        = "you"
description   = "$1"
license       = "MIT"
srcDir        = "src"
bin           = @["$1"]

# Dependencies

requires "nim >= 2.0.0"
requires "flit >= 0.1.0"
"""

proc cmdCreate(name: string) =
  if name.len == 0:
    echo "usage: flit create <name>"; quit(1)
  createDir(name & "/src")
  createDir(name & "/assets")
  createDir(name & "/web")
  writeFile(name & "/src/" & name & ".nim", sampleMain % [name])
  writeFile(name & "/" & name & ".nimble", sampleNimble % [name])
  writeFile(name & "/.gitignore", "nimcache/\nbin/\n*.exe\nweb/*.js\n")
  writeFile(name & "/README.md", "# " & name & "\n\nBuilt with flit.\n\n```\nflit run\n```\n")
  writeFile(name & "/web/index.html", """<!doctype html>
<html><head><meta charset="utf-8"/><title>""" & name & """</title>
<style>html,body{margin:0;height:100%}canvas{width:100vw;height:100vh;display:block}</style>
</head><body><canvas id="flit-canvas" width="1024" height="768"></canvas>
<script src="./app.js"></script></body></html>
""")
  echo "Created project ", name
  echo "Next: cd ", name, " && nimble install && flit run"

# ----- platform detection -----

proc detectPlatform(): string =
  when defined(macosx): "macos"
  elif defined(linux): "linux"
  elif defined(windows): "windows"
  else: "linux"

# ----- run / build -----

proc projectName(): string =
  for f in walkFiles("*.nimble"):
    return f.changeFileExt("")
  "app"

proc cmdRun(extraArgs: seq[string]) =
  let name = projectName()
  let entry = "src/" & name & ".nim"
  if not fileExists(entry):
    echo "no entrypoint at ", entry; quit(1)
  let cmd = &"nim c -r --hints:off -d:release -o:bin/{name} {entry}"
  echo "+ ", cmd
  quit execShellCmd(cmd)

proc cmdBuild(target: string) =
  let name = projectName()
  let entry = "src/" & name & ".nim"
  case target
  of "web":
    createDir("web")
    let cmd = &"nim js -d:release -o:web/app.js {entry}"
    echo "+ ", cmd
    quit execShellCmd(cmd)
  of "macos", "linux", "windows":
    createDir("bin")
    let cmd = &"nim c -d:release --opt:speed -o:bin/{name} {entry}"
    echo "+ ", cmd
    quit execShellCmd(cmd)
  of "apk", "android":
    let cmd = &"nim c -d:release -d:android --os:android --cpu:arm64 " &
              &"-o:build/android/lib{name}.so {entry}"
    echo "+ ", cmd
    echo "(after .so is built, wrap with an Android Studio shell)"
    quit execShellCmd(cmd)
  of "ipa", "ios":
    # iOS uses a POSIX-like target with the Apple toolchain.
    # Nim's `--os:ios` accepts lowercase. Linking to a runnable
    # bundle still requires Xcode + provisioning; this step only
    # produces the ARM64 binary that an Xcode shell would wrap.
    let cmd = &"nim c -d:release -d:ios --os:ios --cpu:arm64 " &
              &"-o:build/ios/{name} {entry}"
    echo "+ ", cmd
    echo "(after binary is built, wrap with an Xcode shell)"
    quit execShellCmd(cmd)
  else:
    echo "unknown build target: ", target
    echo "valid: apk ipa web macos linux windows"; quit(1)

# ----- doctor -----

proc which(cmd: string): string =
  let r = execProcess("/bin/sh", args = ["-c", "command -v " & cmd],
                      options = {poStdErrToStdOut, poUsePath})
  r.strip()

proc cmdDoctor() =
  echo "flit doctor"
  echo "  flit version       : ", flitVersion
  echo "  os                 : ", hostOS
  echo "  cpu                : ", hostCPU
  echo "  nim                : ", which("nim")
  echo "  nimble             : ", which("nimble")
  echo "  android adb        : ", which("adb")
  echo "  xcode xcrun        : ", which("xcrun")
  echo "  pkg-config (sdl2)  : ",
    if which("pkg-config").len > 0:
      try:
        execProcess("/bin/sh", args = ["-c", "pkg-config --modversion sdl2"],
                    options = {poStdErrToStdOut, poUsePath}).strip()
      except OSError:
        "(not configured)"
    else: "(missing)"

# ----- devices -----

proc cmdDevices() =
  echo "Android devices:"
  if which("adb").len > 0:
    discard execShellCmd("adb devices -l")
  else:
    echo "  adb not found"
  echo ""
  echo "iOS devices:"
  if which("xcrun").len > 0:
    discard execShellCmd("xcrun xctrace list devices")
  else:
    echo "  xcrun not found"

# ----- clean -----

proc cmdClean() =
  for p in ["nimcache", "bin", "build", "web/app.js", "web/app.js.map"]:
    if dirExists(p): removeDir(p)
    elif fileExists(p): removeFile(p)
  echo "cleaned."

# ----- hot reload -----

proc cmdHot(extra: seq[string]) =
  ## Lightweight file-watch loop: rebuild + restart child on src/ changes.
  let name = projectName()
  let entry = "src/" & name & ".nim"
  var lastMtime: Table[string, Time]
  for f in walkDirRec("src"):
    if f.endsWith(".nim"):
      lastMtime[f] = getLastModificationTime(f)
  var child: Process
  proc spawn() =
    if not child.isNil:
      try: child.terminate() except CatchableError: discard
    discard execShellCmd(&"nim c --hints:off -d:release -o:bin/{name} {entry}")
    child = startProcess("./bin/" & name, options = {poParentStreams})
  spawn()
  while true:
    sleep(500)
    var changed = false
    for f in walkDirRec("src"):
      if not f.endsWith(".nim"): continue
      let m = getLastModificationTime(f)
      if not lastMtime.hasKey(f) or lastMtime[f] != m:
        lastMtime[f] = m
        changed = true
    if changed:
      echo "[flit hot] change detected, rebuilding..."
      spawn()

# ----- pub get / upgrade -----

proc cmdPubGet() =
  quit execShellCmd("nimble install -y --depsOnly")

proc cmdUpgrade() =
  quit execShellCmd("nimble install -y flit")

# ----- dispatch -----

when isMainModule:
  let args = commandLineParams()
  if args.len == 0:
    usage(); quit(0)
  case args[0]
  of "create":  cmdCreate(if args.len >= 2: args[1] else: "")
  of "run":     cmdRun(args[1..^1])
  of "build":   cmdBuild(if args.len >= 2: args[1] else: detectPlatform())
  of "doctor":  cmdDoctor()
  of "devices": cmdDevices()
  of "clean":   cmdClean()
  of "hot":     cmdHot(args[1..^1])
  of "pub":
    if args.len >= 2 and args[1] == "get": cmdPubGet()
    else: echo "usage: flit pub get"
  of "upgrade": cmdUpgrade()
  of "--version", "-v", "version": echo flitVersion
  of "--help", "-h", "help": usage()
  else:
    echo "unknown command: ", args[0]
    usage(); quit(1)
