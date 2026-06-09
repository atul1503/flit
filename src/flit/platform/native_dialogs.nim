## Native dialogs: alert, confirm, prompt. Each blocks the calling
## thread until the user dismisses, returning the user's choice.
##
## Implementation uses SDL2's `SDL_ShowMessageBox` which delegates
## to the platform's native dialog (Cocoa NSAlert, GTK MessageDialog,
## Win32 MessageBox). prompt() is a flit-rendered modal because
## SDL doesn't ship a text-input dialog; we build a small modal
## widget around the existing TextField.
##
## All procs are no-ops on the JS backend (use `window.alert` and
## `window.prompt` directly from your widget code there).

when not defined(js):
  import sdl2

type
  DialogKind* = enum
    ## Visual style hint passed to native dialog APIs. Maps to
    ## `SDL_MESSAGEBOX_INFORMATION`, `SDL_MESSAGEBOX_WARNING`,
    ## `SDL_MESSAGEBOX_ERROR`. `dkQuestion` is treated as info on
    ## platforms that have no native question icon.
    dkInfo, dkWarning, dkError, dkQuestion

  DialogChoice* = enum
    ## Result returned by an interactive dialog. `dcOK` and
    ## `dcCancel` are the standard two-button outcomes; `dcYes`
    ## and `dcNo` are reserved for future yes/no variants.
    dcOK, dcCancel, dcYes, dcNo

proc messageBox*(title, message: string,
                 kind: DialogKind = dkInfo): DialogChoice =
  ## Shows a modal OK-only dialog. Returns `dcOK`.
  ## Blocks the calling thread. Use this for non-interactive
  ## "something happened" notifications; for asks, use `confirm`.
  when defined(js):
    return dcOK
  else:
    let flags: uint32 =
      case kind
      of dkError:    SDL_MESSAGEBOX_ERROR
      of dkWarning:  SDL_MESSAGEBOX_WARNING
      else:          SDL_MESSAGEBOX_INFORMATION
    discard sdl2.showSimpleMessageBox(flags, title.cstring,
                                      message.cstring, nil)
    return dcOK

proc confirm*(title, message: string,
              okLabel: string = "OK",
              cancelLabel: string = "Cancel",
              kind: DialogKind = dkQuestion): DialogChoice =
  ## Shows a modal dialog with two buttons. Returns the user's
  ## choice. Default button is OK; pressing Escape returns Cancel.
  ##
  ## Inputs:
  ## - `title`: window title text.
  ## - `message`: body text shown to the user.
  ## - `okLabel`: text of the confirm button. Default `"OK"`.
  ## - `cancelLabel`: text of the cancel button. Default `"Cancel"`.
  ## - `kind`: visual style. Use `dkQuestion` for "are you sure"
  ##   prompts.
  ##
  ## Returns `dcOK` if the user picked the confirm button (or
  ## pressed Enter), `dcCancel` for cancel / Escape / close-box.
  ## Blocks the calling thread until dismissed. On JS targets
  ## this is a no-op that returns `dcCancel`.
  when defined(js):
    return dcCancel
  else:
    var buttons = [
      MessageBoxButtonData(
        flags: SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT,
        buttonid: cint(1), text: cancelLabel.cstring),
      MessageBoxButtonData(
        flags: SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT,
        buttonid: cint(0), text: okLabel.cstring),
    ]
    let flags: uint32 =
      case kind
      of dkError:    SDL_MESSAGEBOX_ERROR
      of dkWarning:  SDL_MESSAGEBOX_WARNING
      else:          SDL_MESSAGEBOX_INFORMATION
    var data = MessageBoxData(
      flags: cint(flags),
      window: nil,
      title: title.cstring,
      message: message.cstring,
      numbuttons: 2,
      buttons: addr buttons[0],
      colorScheme: nil)
    var buttonId: cint = -1
    discard sdl2.showMessageBox(addr data, buttonId)
    return if buttonId == 0: dcOK else: dcCancel

proc askYesNo*(title, message: string): bool =
  ## Convenience: returns true if the user picked Yes, false for No.
  ## Equivalent to `confirm(title, message, okLabel = "Yes",
  ## cancelLabel = "No") == dcOK`.
  confirm(title, message, okLabel = "Yes", cancelLabel = "No") == dcOK

# `prompt` (text-input dialog) is not in SDL's message-box API.
# We don't ship a synchronous prompt(); the right pattern in flit
# is to push a modal route via Navigator that contains a TextField
# and resolves to the entered string via the popResult callback.
# A future addition could spawn a native NSAlert / GTK dialog with
# a text field via per-platform native code.
