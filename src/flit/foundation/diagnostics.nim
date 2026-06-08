## Diagnostic / debug printing for the widget and render trees, plus
## a tiny leveled logger used by the engine.
##
## A `DiagnosticsNode` is a name-and-value pair with optional children,
## used by `debugDescribe` on `Element` and `RenderObject`. Render
## inspector dumps and the test `debug_dump.nim` helper print these
## via `prettyPrint`.

import std/[strutils, strformat]

type
  DiagnosticLevel* = enum
    ## Severity tag attached to a `DiagnosticsNode`. Currently
    ## informational; reserved for filtering in a future inspector
    ## UI.
    dlHidden, dlFine, dlDebug, dlInfo, dlWarning, dlHint, dlSummary, dlError

  DiagnosticsNode* = ref object
    ## A node in the diagnostic tree. `name` is the label,
    ## `value` an optional descriptive string. Children form a
    ## sub-tree.
    name*: string
    value*: string
    children*: seq[DiagnosticsNode]
    level*: DiagnosticLevel

proc node*(name: string, value: string = "",
           level: DiagnosticLevel = dlInfo): DiagnosticsNode =
  ## Builds a `DiagnosticsNode` with no children.
  DiagnosticsNode(name: name, value: value, level: level, children: @[])

proc add*(parent: DiagnosticsNode, child: DiagnosticsNode) =
  ## Appends `child` to `parent.children`.
  parent.children.add(child)

proc add*(parent: DiagnosticsNode, name, value: string) =
  ## Convenience: builds a leaf node from `name` and `value` and
  ## appends it.
  parent.children.add(node(name, value))

proc prettyPrint*(n: DiagnosticsNode, indent = 0): string =
  ## Renders `n` and its subtree as an indented multi-line string.
  ## Each level of nesting adds two spaces. Returns an empty string
  ## if `n` is nil.
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
    ## Severity for the engine logger. Ordering is from quietest
    ## (`llTrace`) to loudest (`llFatal`). The runner emits `llInfo`
    ## messages such as "flit desktop runner started 1024x768".
    llTrace, llDebug, llInfo, llWarn, llError, llFatal

var minLogLevel* = llInfo
  ## Minimum level to actually print. Set lower at startup to enable
  ## debug/trace output, e.g. `minLogLevel = llDebug`.

proc logf*(level: LogLevel, msg: string) =
  ## Prints `msg` to stdout with a level tag (e.g. `[info ]`). Skips
  ## the print if `level < minLogLevel`. Used by `flog` and the
  ## per-level shortcuts.
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
  ## Stringifies `args` (via `$`), joins them, and logs at `level`.
  logf(level, args.join(""))

template flogi*(args: varargs[string, `$`]) = flog(llInfo, args)
  ## Convenience: log at `llInfo`.
template flogd*(args: varargs[string, `$`]) = flog(llDebug, args)
  ## Convenience: log at `llDebug`.
template flogw*(args: varargs[string, `$`]) = flog(llWarn, args)
  ## Convenience: log at `llWarn`.
template floge*(args: varargs[string, `$`]) = flog(llError, args)
  ## Convenience: log at `llError`.
