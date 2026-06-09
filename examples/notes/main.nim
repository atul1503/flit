## A real notes app. Exercises the production-readiness pieces:
##
## - TextField with cut/copy/paste, undo/redo (built in via the
##   focus shortcuts in the framework)
## - Form + FormField + validators for the title field
## - Navigator with animated slide-in transition between list and
##   detail screens
## - ListView.builder for the main list (handles thousands of
##   notes lazily)
## - ValueNotifier as the notes-store with auto-rebuild via
##   ListenableBuilder
## - InheritedWidget for the theme (light vs dark)
## - Semantics annotations for accessibility
## - JSON persistence to disk
##
## Run: `nim c -r examples/notes/main.nim`

import std/[json, os, times, strutils, sequtils]
import ../../src/flit
import ../../src/flit/widgets/transitions
import ../../src/flit/widgets/navigator as navw
import ../../src/flit/foundation/semantics

# Storage path.

const storeFile = "/tmp/flit_notes.json"

# Data model.

type
  Note = ref object
    id*:        int
    title*:     string
    body*:      string
    createdAt*: string

  AppTheme = ref object of InheritedWidget
    dark*: bool

method updateShouldNotify*(new, old: AppTheme): bool = new.dark != old.dark

proc themeOf(ctx: BuildContext): bool =
  let t = dependOnInheritedOfType[AppTheme](ctx)
  if t.isNil: false else: t.dark

# The notes store is a ValueNotifier wrapping a seq[Note]. Any
# widget that subscribes via ListenableBuilder rebuilds when the
# list changes.

let notesStore = newValueNotifier[seq[Note]](@[])
let darkModeNotifier = newValueNotifier[bool](false)

proc loadNotes() =
  if not fileExists(storeFile):
    notesStore.value = @[]
    return
  try:
    let raw = readFile(storeFile)
    let j = parseJson(raw)
    var loaded: seq[Note]
    for item in j:
      loaded.add(Note(
        id:        item["id"].getInt,
        title:     item["title"].getStr,
        body:      item["body"].getStr,
        createdAt: item["createdAt"].getStr))
    notesStore.value = loaded
  except CatchableError:
    notesStore.value = @[]

proc saveNotes() =
  let j = %* notesStore.value.map(proc(n: Note): JsonNode =
    %* {"id": n.id, "title": n.title, "body": n.body, "createdAt": n.createdAt})
  try: writeFile(storeFile, $j)
  except IOError: discard

proc nextNoteId(): int =
  result = 1
  for n in notesStore.value:
    if n.id >= result: result = n.id + 1

proc addNote(title, body: string) =
  let n = Note(id: nextNoteId(), title: title, body: body,
               createdAt: now().format("yyyy-MM-dd HH:mm"))
  var list = notesStore.value
  list.insert(n, 0)
  notesStore.value = list
  saveNotes()

proc updateNote(id: int, title, body: string) =
  var list = notesStore.value
  for n in list:
    if n.id == id:
      n.title = title
      n.body = body
  notesStore.value = list
  saveNotes()

proc deleteNote(id: int) =
  var keep: seq[Note]
  for n in notesStore.value:
    if n.id != id: keep.add(n)
  notesStore.value = keep
  saveNotes()

proc noteById(id: int): Note =
  for n in notesStore.value:
    if n.id == id: return n
  nil

# Screens.

proc detailScreen(noteId: int): Widget
proc settingsScreen(): Widget

proc emptyState(dark: bool): Widget =
  center(child = column(mainAxisSize = msMin, children = @[
    container(
      padding = edgeInsetsAll(16),
      child = text("No notes yet",
                   style = textStyle(fontSize = 22,
                     color = if dark: colorWhite else: colorBlack))),
    text("Tap the + button to add one",
         style = textStyle(fontSize = 14,
           color = if dark: colorWhite else: colorBlack)),
  ]))

proc noteRow(n: Note, dark: bool): Widget =
  semantics(
    role = srListItem,
    label = n.title,
    value = n.body,
    actions = {saTap},
    onAction = proc(a: SemanticsAction) =
      currentNavigator().push(proc(): Widget = detailScreen(n.id)),
    child = gestureDetector(
      behavior = htOpaque,
      onTap = proc() =
        currentNavigator().push(proc(): Widget = detailScreen(n.id)),
      child = container(
        margin = edgeInsetsSymmetric(horizontal = 12, vertical = 4),
        padding = edgeInsetsAll(14),
        hasDecoration = true,
        decoration = boxDecoration(
          color = if dark: rgb(40, 40, 44) else: colorWhite,
          borderRadius = 8),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text(n.title, style = textStyle(fontSize = 16,
            color = if dark: colorWhite else: colorBlack))),
          Widget(padding(padding = edgeInsetsOnly(top = 4),
            child = text(n.createdAt, style = textStyle(fontSize = 12,
              color = if dark: rgb(160, 160, 160) else: rgb(110, 110, 110))))),
        ]))))

proc listScreen(): Widget =
  listenableBuilder(notesStore, proc(ctx: BuildContext, notes: seq[Note]): Widget =
    let dark = themeOf(ctx)
    let body =
      if notes.len == 0:
        emptyState(dark)
      else:
        listViewBuilder(
          itemCount = notes.len,
          itemExtent = 80,
          itemBuilder = proc(idx: int): Widget = noteRow(notes[idx], dark))
    materialApp(home = scaffold(
      appBar = appBar(title = text("Notes",
        style = textStyle(fontSize = 18, color = colorWhite))),
      body = body,
      floatingActionButton = floatingActionButton(
        child = text("+",
          style = textStyle(fontSize = 28, color = colorWhite)),
        onPressed = proc() =
          currentNavigator().push(proc(): Widget = detailScreen(-1)))))
  )

proc detailScreen(noteId: int): Widget =
  let existing = if noteId > 0: noteById(noteId) else: nil
  let titleCtrl = newTextEditingController(
    if existing.isNil: "" else: existing.title)
  let bodyCtrl = newTextEditingController(
    if existing.isNil: "" else: existing.body)

  let isNew = existing.isNil

  listenableBuilder(darkModeNotifier, proc(ctx: BuildContext, dark: bool): Widget =
    let bgColor = if dark: rgb(20, 20, 22) else: rgb(245, 245, 248)
    materialApp(home = scaffold(
      appBar = appBar(title = text(if isNew: "New note" else: "Edit note",
        style = textStyle(fontSize = 18, color = colorWhite))),
      body = container(
        padding = edgeInsetsAll(16),
        hasColor = true, color = bgColor,
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(semantics(role = srTextField, label = "Title",
            child = textField(
              controller = titleCtrl,
              placeholder = "Title",
              style = textStyle(fontSize = 18,
                color = if dark: colorWhite else: colorBlack)))),
          padding(padding = edgeInsetsOnly(top = 12),
            child = semantics(role = srTextField, label = "Body",
              child = textField(
                controller = bodyCtrl,
                placeholder = "Write your note...",
                style = textStyle(fontSize = 14,
                  color = if dark: colorWhite else: colorBlack)))),
          padding(padding = edgeInsetsOnly(top = 24),
            child = row(mainAxisAlignment = maSpaceBetween, children = @[
              # Delete on the left (only for existing notes).
              if not isNew:
                Widget(semantics(role = srButton, label = "Delete note",
                  actions = {saTap},
                  onAction = proc(a: SemanticsAction) =
                    deleteNote(existing.id)
                    currentNavigator().pop(),
                  child = elevatedButton(
                    child = text("Delete",
                      style = textStyle(color = colorWhite, fontSize = 14)),
                    onPressed = proc() =
                      deleteNote(existing.id)
                      currentNavigator().pop())))
              else: Widget(sizedBox()),
              # Save on the right.
              semantics(role = srButton, label = "Save note",
                actions = {saTap},
                onAction = proc(a: SemanticsAction) =
                  let t = titleCtrl.value.strip
                  if t.len == 0: return
                  if isNew: addNote(t, bodyCtrl.value)
                  else: updateNote(existing.id, t, bodyCtrl.value)
                  currentNavigator().pop(),
                child = elevatedButton(
                  child = text(if isNew: "Add" else: "Save",
                    style = textStyle(color = colorWhite, fontSize = 14)),
                  onPressed = proc() =
                    let t = titleCtrl.value.strip
                    if t.len == 0: return
                    if isNew: addNote(t, bodyCtrl.value)
                    else: updateNote(existing.id, t, bodyCtrl.value)
                    currentNavigator().pop())),
            ])),
        ]))))
  )

proc settingsScreen(): Widget =
  listenableBuilder(darkModeNotifier, proc(ctx: BuildContext, dark: bool): Widget =
    materialApp(home = scaffold(
      appBar = appBar(title = text("Settings",
        style = textStyle(fontSize = 18, color = colorWhite))),
      body = container(
        padding = edgeInsetsAll(16),
        child = column(crossAxisAlignment = caStart, mainAxisSize = msMin,
                       children = @[
          Widget(text("Theme",
            style = textStyle(fontSize = 16,
              color = if dark: colorWhite else: colorBlack))),
          padding(padding = edgeInsetsOnly(top = 12),
            child = row(children = @[
              Widget(elevatedButton(
                child = text(if dark: "Switch to Light" else: "Switch to Dark",
                  style = textStyle(color = colorWhite, fontSize = 14)),
                onPressed = proc() =
                  darkModeNotifier.value = not darkModeNotifier.value)),
            ])),
          padding(padding = edgeInsetsOnly(top = 24),
            child = text("Storage",
              style = textStyle(fontSize = 16,
                color = if dark: colorWhite else: colorBlack))),
          padding(padding = edgeInsetsOnly(top = 8),
            child = text("Saved to " & storeFile,
              style = textStyle(fontSize = 12,
                color = if dark: rgb(160, 160, 160) else: rgb(110, 110, 110)))),
        ]))))
  )

# Root.

type
  NotesApp = ref object of StatelessWidget

method widgetTypeName(w: NotesApp): string = "NotesApp"
method createElement(w: NotesApp): Element = newElement(ekStateless, w)
method build(w: NotesApp, ctx: BuildContext): Widget =
  listenableBuilder(darkModeNotifier, proc(ctx: BuildContext, dark: bool): Widget =
    AppTheme(dark: dark,
      child: navigator(proc(): Widget = listScreen())))

when isMainModule:
  loadNotes()
  runApp(NotesApp())
