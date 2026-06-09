## Form and FormField widgets. A `Form` collects `FormField`s
## registered during build; `Form.validate()` runs every field's
## validator and returns the aggregate result. Each field can show
## an `errorText` when its validator returns a non-empty error.
##
## Public surface:
## - `formScope(...)`: wraps a subtree in a Form scope.
## - `formField(...)`: registers a field with the enclosing scope.
## - `FormHandle.validate()`: runs every registered field's
##   validator, returns true iff every field is valid.
## - `FormHandle.reset()`: clears every field's value to its
##   initial state.
##
## A common pattern: pair this with `TextField` for inputs. The
## form field wraps the text field and adds validation visuals
## (an error message below the input when validation fails).

import std/[options, strutils]
import ../foundation/[widget, render_object, geometry, color, key, runtime]
import ../rendering/text
import ./text_field
import ./basic

type
  FieldValidator* = proc(value: string): string {.closure.}
    ## Returns "" when the value is valid, or an error message.

  FormFieldState* = ref object
    ## Per-field record kept by the form. Public so applications
    ## can read the current value via `field.value`.
    name*:        string
    value*:       string
    initial*:     string
    error*:       string
    validator*:   FieldValidator
    controller*:  TextEditingController

  FormState* = ref object of State
    ## Holds the registered fields. Populated during build as each
    ## `formField` widget runs. Reset on each rebuild so removed
    ## fields drop out.
    fields*:      seq[FormFieldState]
    handle*:      FormHandle

  FormHandle* = ref object
    ## External handle. Pass to button callbacks so they can call
    ## `validate()` / `reset()`.
    state*: FormState

  FormScope* = ref object of StatefulWidget
    child*: Widget

  FormFieldWidget* = ref object of StatelessWidget
    name*:        string
    initial*:     string
    placeholder*: string
    validator*:   FieldValidator
    onChanged*:   proc(value: string) {.closure.}

# Currently-building form. Set by FormScope.build before its child
# builds, cleared after. Allows FormFieldWidget.build to register
# with the nearest enclosing form.

var currentForm {.threadvar.}: FormState

method widgetTypeName*(w: FormScope): string = "Form"
method createElement*(w: FormScope): Element = newElement(ekStateful, w)
method createState*(w: FormScope): State =
  result = FormState(fields: @[])
  FormState(result).handle = FormHandle(state: FormState(result))

method build*(s: FormState, ctx: BuildContext): Widget =
  let host = FormScope(s.element.widget)
  # Clear registered fields; rebuild repopulates.
  s.fields.setLen(0)
  let prev = currentForm
  currentForm = s
  let built = host.child
  currentForm = prev
  built

proc validate*(h: FormHandle): bool =
  ## Runs every registered field's validator. Returns true iff
  ## every field is valid. Mutates each field's `error` and
  ## triggers a rebuild so the visuals reflect the result.
  if h.isNil or h.state.isNil: return false
  var ok = true
  for f in h.state.fields:
    if f.validator.isNil:
      f.error = ""
    else:
      f.error = f.validator(f.value)
      if f.error.len > 0: ok = false
  setState(h.state, proc() = discard)
  ok

proc reset*(h: FormHandle) =
  ## Resets every field to its initial value and clears errors.
  if h.isNil or h.state.isNil: return
  for f in h.state.fields:
    f.value = f.initial
    f.error = ""
    if not f.controller.isNil:
      f.controller.value = f.initial
  setState(h.state, proc() = discard)

proc fields*(h: FormHandle): seq[FormFieldState] =
  ## Read-only access to the field list. Each entry carries the
  ## current `value` and (after `validate`) the latest `error`.
  if h.isNil or h.state.isNil: @[] else: h.state.fields

proc valueOf*(h: FormHandle, name: string): string =
  ## Returns the value of the field with the given name, or "" if
  ## no such field is registered.
  for f in h.fields:
    if f.name == name: return f.value
  ""

# FormFieldWidget: a stateless widget that registers with the
# enclosing form on build, then renders a TextField + optional
# error label.

method widgetTypeName*(w: FormFieldWidget): string = "FormField"
method createElement*(w: FormFieldWidget): Element = newElement(ekStateless, w)
method build*(w: FormFieldWidget, ctx: BuildContext): Widget =
  # Register the field with the enclosing form, if any. We
  # synthesize a fresh FormFieldState per build; the controller
  # persists state across builds.
  var fieldState: FormFieldState
  if not currentForm.isNil:
    # If this name is already registered, reuse its state. Lets us
    # keep the field's value across form rebuilds.
    for existing in currentForm.fields:
      if existing.name == w.name:
        fieldState = existing
        break
    if fieldState.isNil:
      fieldState = FormFieldState(name: w.name, value: w.initial,
                                  initial: w.initial,
                                  validator: w.validator,
                                  controller: newTextEditingController(w.initial))
      currentForm.fields.add(fieldState)
    else:
      fieldState.validator = w.validator
  else:
    fieldState = FormFieldState(name: w.name, value: w.initial,
                                initial: w.initial,
                                validator: w.validator,
                                controller: newTextEditingController(w.initial))

  let captured = fieldState
  let onChange = w.onChanged
  let field = textField(
    controller = captured.controller,
    placeholder = w.placeholder,
    onChanged = proc(v: string) =
      captured.value = v
      # Clear error on edit so the user sees "you fixed it".
      if captured.error.len > 0:
        captured.error = ""
      if not onChange.isNil:
        try: onChange(v) except CatchableError: discard)

  if fieldState.error.len > 0:
    column(crossAxisAlignment = caStart, mainAxisSize = msMin, children = @[
      field,
      padding(padding = edgeInsetsAll(4),
        child = text(fieldState.error,
                     style = textStyle(color = colorRed, fontSize = 12.0))),
    ])
  else:
    Widget(field)

proc formScope*(child: Widget, key: Key = nil): FormScope =
  ## Wraps `child` in a Form scope. Every `formField` widget
  ## inside `child` is registered with this form on build, and
  ## can be validated / reset via the form's handle.
  ##
  ## To get the handle: keep a `ValueNotifier[FormHandle]` or a
  ## ref-holding helper; the form sets `activeNavigator`-style
  ## globals are deliberately avoided because forms can nest.
  ##
  ## Simplest pattern: read the handle from the FormState in a
  ## post-frame callback, or pass a closure that takes the handle
  ## once mounted.
  FormScope(key: key, child: child)

proc formField*(name: string,
                initial: string = "",
                placeholder: string = "",
                validator: FieldValidator = nil,
                onChanged: proc(value: string) = nil,
                key: Key = nil): FormFieldWidget =
  ## Builds a form field. The field registers itself with the
  ## enclosing `formScope` on build.
  ##
  ## Inputs:
  ## - `name`: identifier used to read the value via
  ##   `handle.valueOf(name)`.
  ## - `initial`: initial value.
  ## - `placeholder`: dimmed text shown when empty.
  ## - `validator`: returns "" for valid, error message otherwise.
  ##   Run on `handle.validate()`.
  ## - `onChanged`: fires on every keystroke with the new value.
  ## - `key`: reconciliation key.
  FormFieldWidget(key: key, name: name, initial: initial,
                  placeholder: placeholder, validator: validator,
                  onChanged: onChanged)

# Built-in validators

proc validatorRequired*(message: string = "Required"): FieldValidator =
  ## Returns a validator that rejects empty / whitespace-only values.
  result = proc(value: string): string =
    if value.strip.len == 0: message else: ""

proc validatorMinLength*(min: int, message: string = ""): FieldValidator =
  ## Rejects values shorter than `min` characters.
  let msg = if message.len > 0: message
            else: "Must be at least " & $min & " characters"
  result = proc(value: string): string =
    if value.len < min: msg else: ""

proc validatorEmail*(message: string = "Invalid email"): FieldValidator =
  ## A basic, intentionally simple email check: must contain
  ## exactly one `@`, with non-empty halves on either side, and
  ## the second half must contain a `.`. For real email
  ## validation, use a server-side check; client-side validation
  ## is just a usability hint.
  result = proc(value: string): string =
    let parts = value.split('@')
    if parts.len != 2: return message
    if parts[0].len == 0 or parts[1].len == 0: return message
    if '.' notin parts[1]: return message
    ""
