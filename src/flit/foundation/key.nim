## Keys identify widgets across rebuilds so the framework can preserve
## element (and state) identity when the widget tree is regenerated.
## Mirrors Flutter's `Key` hierarchy.
##
## When two sibling widgets have the same runtime type, the framework
## decides whether to reuse the existing element for either of them by
## comparing keys. Without a key, sibling reorders force a re-mount; with
## a key, the element follows the keyed widget to its new slot and any
## `State` it owns is preserved.

import std/[hashes, strutils]

type
  KeyKind* = enum
    ## Discriminator for the `Key` variant types.
    ## - `kkUnique`: per-allocation unique counter (`newUniqueKey`).
    ## - `kkValue`:  equality by a wrapped string / value
    ##   (`newValueKey`).
    ## - `kkGlobal`: equality by reference identity, addressable from
    ##   anywhere in the tree (`newGlobalKey`).
    ## - `kkObject`: equality by an external object pointer
    ##   (`newObjectKey`).
    kkUnique, kkValue, kkGlobal, kkObject

  Key* = ref object of RootObj
    ## A reconciliation key. Variant fields are selected by `kind`.
    case kind*: KeyKind
    of kkUnique:
      uniqueId*: int
    of kkValue:
      value*: string
    of kkGlobal:
      label*: string
    of kkObject:
      objRef*: pointer

  ValueKey*[T] = ref object of Key
    ## A `Key` that wraps an arbitrary typed value `T`. The string form
    ## is what's used for equality and hashing (so `T` needs `$T`).
    typedValue*: T

  GlobalKey* = ref object of Key
    ## A `Key` whose identity persists across the entire app and that
    ## the framework can resolve to the currently mounted `Element`.
    ## Equality is by reference (two distinct `GlobalKey` instances
    ## never compare equal).
    currentElement*: pointer

var uniqueKeyCounter: int = 0

proc newUniqueKey*(): Key =
  ## Returns a brand-new `Key` that doesn't equal any other key. Useful
  ## when you want to force-recreate a subtree on every rebuild.
  inc uniqueKeyCounter
  Key(kind: kkUnique, uniqueId: uniqueKeyCounter)

proc newValueKey*(value: string): Key =
  ## Returns a `Key` whose equality is the string `value`. Two
  ## `ValueKey("a")` instances are equal.
  Key(kind: kkValue, value: value)

proc newValueKey*[T](value: T): ValueKey[T] =
  ## Generic variant that remembers the original typed value as well
  ## as its string form.
  ValueKey[T](kind: kkValue, value: $value, typedValue: value)

proc newGlobalKey*(label: string = ""): GlobalKey =
  ## Returns a `GlobalKey` whose `label` is just a debug aid. Each call
  ## returns a distinct key.
  GlobalKey(kind: kkGlobal, label: label)

proc newObjectKey*(obj: pointer): Key =
  ## Returns a `Key` whose equality is by the wrapped pointer. Useful
  ## for tying a widget's identity to an external Nim object.
  Key(kind: kkObject, objRef: obj)

proc hash*(k: Key): Hash =
  ## Hashes a key. `nil` hashes to 0. The hash incorporates the kind
  ## and the value-determining field for that kind.
  if k.isNil: return 0
  result = case k.kind
    of kkUnique: hash(k.uniqueId)
    of kkValue:  hash(k.value)
    of kkGlobal: hash(cast[int](k))
    of kkObject: hash(cast[int](k.objRef))
  result = result !& ord(k.kind)
  result = !$result

proc `==`*(a, b: Key): bool =
  ## Equality across the variant types. Two `nil` keys are equal.
  ## Different `kind`s never compare equal.
  if a.isNil or b.isNil: return a.isNil and b.isNil
  if a.kind != b.kind: return false
  case a.kind
  of kkUnique: a.uniqueId == b.uniqueId
  of kkValue:  a.value == b.value
  of kkGlobal: cast[int](a) == cast[int](b)
  of kkObject: a.objRef == b.objRef

proc `$`*(k: Key): string =
  ## Debug representation. Used by `debugDescribe` to show keys in
  ## inspector output.
  if k.isNil: return "<noKey>"
  case k.kind
  of kkUnique: "UniqueKey#" & $k.uniqueId
  of kkValue:  "ValueKey(" & k.value & ")"
  of kkGlobal: "GlobalKey(" & k.label & ")"
  of kkObject: "ObjectKey(0x" & toHex(cast[int](k.objRef)) & ")"
