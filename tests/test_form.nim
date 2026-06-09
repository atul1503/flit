## Form / FormField / validator tests.

import std/unittest
import ../src/flit/widgets/form_widget

suite "Validators":
  test "validatorRequired rejects empty and whitespace":
    let v = validatorRequired()
    check v("") == "Required"
    check v("   ") == "Required"
    check v("ok") == ""

  test "validatorMinLength":
    let v = validatorMinLength(3)
    check v("ab") == "Must be at least 3 characters"
    check v("abc") == ""
    check v("abcd") == ""

  test "validatorEmail":
    let v = validatorEmail()
    check v("hi") == "Invalid email"
    check v("hi@") == "Invalid email"
    check v("@x.com") == "Invalid email"
    check v("hi@x") == "Invalid email"        # no dot in domain
    check v("hi@x.com") == ""

  test "validators compose into FormFieldState":
    # FormFieldState is a plain value object; we can build one
    # outside of a form for unit testing.
    let v = validatorRequired()
    var f = FormFieldState(name: "email", value: "",
                           initial: "", validator: v)
    check v(f.value) == "Required"
    f.value = "x"
    check v(f.value) == ""
