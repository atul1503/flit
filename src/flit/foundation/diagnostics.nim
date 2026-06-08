## Diagnostic / debug printing for the widget tree. Used by `debugDumpApp()`
## and the inspector.

import std/[strutils, strformat]

type
  DiagnosticLevel* = enum
    dlHidden, dlFine, dlDebug, dlInfo, dlWarning, dlHint, dlSummary, dlError

  DiagnosticsNode* = ref object
    name*: string
    value*: string
    children*: seq[DiagnosticsNode]
    level*: DiagnosticLevel

proc node*(name: string, value: string = "",
           level: DiagnosticLevel = dlInfo): DiagnosticsNode =
  DiagnosticsNode(name: name, value: value, level: level, children: @[])

proc add*(parent: DiagnosticsNode, child: DiagnosticsNode) =
  parent.children.add(child)

proc add*(parent: DiagnosticsNode, name, value: string) =
  parent.children.add(node(name, value))

proc prettyPrint*(n: DiagnosticsNode, indent = 0): string =
  if n.isNil: return ""
  let pad = "  ".repeat(indent)
  if n.value.len > 0:
    result.add(fmt"{pad}{n.name}: {n.value}" & "\n")
  else:
    result.add(fmt"{pad}{n.name}" & "\n")
  for c in n.children:
    result.add(prettyPrint(c, indent + 1))

# Lightweight logging used by the engine
type
  LogLevel* = enum
    llTrace, llDebug, llInfo, llWarn, llError, llFatal

var minLogLevel* = llInfo

proc logf*(level: LogLevel, msg: string) =
  if level < minLogLevel: return
  let tag = case level
    of llTrace: "[trace]"
    of llDebug: "[debug]"
    of llInfo:  "[info ]"
    of llWarn:  "[warn ]"
    of llError: "[error]"
    of llFatal: "[fatal]"
  echo tag, " ", msg

template flog*(level: LogLevel, args: varargs[string, `$`]) =
  logf(level, args.join(""))

template flogi*(args: varargs[string, `$`]) = flog(llInfo, args)
template flogd*(args: varargs[string, `$`]) = flog(llDebug, args)
template flogw*(args: varargs[string, `$`]) = flog(llWarn, args)
template floge*(args: varargs[string, `$`]) = flog(llError, args)
