## Keys identify widgets across rebuilds so the framework can preserve element
## state when the widget tree is regenerated. Mirrors Flutter's Key hierarchy.

import std/[hashes, strutils]

type
  KeyKind* = enum
    kkUnique, kkValue, kkGlobal, kkObject

  Key* = ref object of RootObj
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
    typedValue*: T

  GlobalKey* = ref object of Key
    currentElement*: pointer  # set by framework when the key is in the tree

var uniqueKeyCounter: int = 0

proc newUniqueKey*(): Key =
  inc uniqueKeyCounter
  Key(kind: kkUnique, uniqueId: uniqueKeyCounter)

proc newValueKey*(value: string): Key =
  Key(kind: kkValue, value: value)

proc newValueKey*[T](value: T): ValueKey[T] =
  ValueKey[T](kind: kkValue, value: $value, typedValue: value)

proc newGlobalKey*(label: string = ""): GlobalKey =
  GlobalKey(kind: kkGlobal, label: label)

proc newObjectKey*(obj: pointer): Key =
  Key(kind: kkObject, objRef: obj)

proc hash*(k: Key): Hash =
  if k.isNil: return 0
  result = case k.kind
    of kkUnique: hash(k.uniqueId)
    of kkValue:  hash(k.value)
    of kkGlobal: hash(cast[int](k))
    of kkObject: hash(cast[int](k.objRef))
  result = result !& ord(k.kind)
  result = !$result

proc `==`*(a, b: Key): bool =
  if a.isNil or b.isNil: return a.isNil and b.isNil
  if a.kind != b.kind: return false
  case a.kind
  of kkUnique: a.uniqueId == b.uniqueId
  of kkValue:  a.value == b.value
  of kkGlobal: cast[int](a) == cast[int](b)
  of kkObject: a.objRef == b.objRef

proc `$`*(k: Key): string =
  if k.isNil: return "<noKey>"
  case k.kind
  of kkUnique: "UniqueKey#" & $k.uniqueId
  of kkValue:  "ValueKey(" & k.value & ")"
  of kkGlobal: "GlobalKey(" & k.label & ")"
  of kkObject: "ObjectKey(0x" & toHex(cast[int](k.objRef)) & ")"
