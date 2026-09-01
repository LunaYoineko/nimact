import std/unittest
import nimact/core/input
import nimact/core/event

suite "Escape sequence parsing":

  test "standalone ESC is nkEscape":
    let ev = parseEscapeSequence("\e")
    check ev.kind == nkEscape
    check ev.modifier == kmNone

  test "arrow keys":
    check parseEscapeSequence("\e[A").kind == nkUp
    check parseEscapeSequence("\e[B").kind == nkDown
    check parseEscapeSequence("\e[C").kind == nkRight
    check parseEscapeSequence("\e[D").kind == nkLeft

  test "modified arrow keys (\e[1;2A etc.)":
    let up = parseEscapeSequence("\e[1;2A")
    check up.kind == nkUp
    check up.modifier == kmShift
    let ctrlDown = parseEscapeSequence("\e[1;5B")
    check ctrlDown.kind == nkDown
    check ctrlDown.modifier == kmCtrl
    let shiftCtrlRight = parseEscapeSequence("\e[1;6C")
    check shiftCtrlRight.kind == nkRight
    check shiftCtrlRight.modifier == kmShiftCtrl

  test "Shift+Tab (\e[Z)":
    let ev = parseEscapeSequence("\e[Z")
    check ev.kind == nkChar
    check ev.ch == "\t"
    check ev.modifier == kmShift

  test "kitty protocol plain keys":
    check parseEscapeSequence("\e[13u").kind == nkEnter
    check parseEscapeSequence("\e[27u").kind == nkEscape
    check parseEscapeSequence("\e[127u").kind == nkBackspace
    check parseEscapeSequence("\e[9u").ch == "\t"
    check parseEscapeSequence("\e[1u").kind == nkUp
    check parseEscapeSequence("\e[2u").kind == nkDown
    check parseEscapeSequence("\e[3u").kind == nkRight
    check parseEscapeSequence("\e[4u").kind == nkLeft

  test "kitty CSI-u press/repeat/release event types":
    let press = parseEscapeSequence("\e[119;1;1u")
    check press.kind == nkChar
    check press.ch == "w"
    check press.eventType == kePress

    let repeatEv = parseEscapeSequence("\e[119;1;2u")
    check repeatEv.kind == nkChar
    check repeatEv.ch == "w"
    check repeatEv.eventType == keRepeat

    let release = parseEscapeSequence("\e[119;1;3u")
    check release.kind == nkChar
    check release.ch == "w"
    check release.eventType == keRelease

  test "kitty CSI-u printable key without event type":
    let ev = parseEscapeSequence("\e[119;1u")
    check ev.kind == nkChar
    check ev.ch == "w"
    check ev.eventType == kePress

  test "kitty CSI-u associated text (4th param)":
    let ev = parseEscapeSequence("\e[119;1;1;119u")
    check ev.kind == nkChar
    check ev.ch == "w"
    check ev.eventType == kePress

  test "kitty CSI-u modified printable key":
    let ev = parseEscapeSequence("\e[97;5u")
    check ev.kind == nkChar
    check ev.ch == "a"
    check ev.modifier == kmCtrl

  test "kitty CSI-u special key with event type":
    let ev = parseEscapeSequence("\e[13;1;3u")
    check ev.kind == nkEnter
    check ev.eventType == keRelease

  test "Shift+Enter via CSI-u (\e[13;2u)":
    let ev = parseEscapeSequence("\e[13;2u")
    check ev.kind == nkEnter
    check ev.modifier == kmShift

  test "Ctrl+Enter via CSI-u (\e[13;5u)":
    let ev = parseEscapeSequence("\e[13;5u")
    check ev.kind == nkEnter
    check ev.modifier == kmCtrl

  test "Shift+Ctrl+Enter via CSI-u (\e[13;6u)":
    let ev = parseEscapeSequence("\e[13;6u")
    check ev.kind == nkEnter
    check ev.modifier == kmShiftCtrl

  test "xterm modified format Shift+Enter (\e[27;2;13~)":
    let ev = parseEscapeSequence("\e[27;2;13~")
    check ev.kind == nkEnter
    check ev.modifier == kmShift

  test "xterm modified format Ctrl+Enter (\e[27;5;13~)":
    let ev = parseEscapeSequence("\e[27;5;13~")
    check ev.kind == nkEnter
    check ev.modifier == kmCtrl

  test "SS3 sequences are nkUnknown":
    check parseEscapeSequence("\eOP").kind == nkUnknown
    check parseEscapeSequence("\eOQ").kind == nkUnknown

  test "unknown CSI sequences are nkUnknown":
    check parseEscapeSequence("\e[5~").kind == nkUnknown
    check parseEscapeSequence("\e[?25l").kind == nkUnknown

  test "empty / non-escape input is nkUnknown":
    check parseEscapeSequence("").kind == nkUnknown
    check parseEscapeSequence("a").kind == nkUnknown

suite "Event dispatch with modifiers":

  test "Shift+Enter does not trigger the plain Enter handler":
    let bus = newEventBus()
    var enterCount = 0
    var shiftEnterCount = 0
    bus.onEnter(proc() = inc enterCount)
    bus.onShiftKey(nkEnter, proc() = inc shiftEnterCount)

    bus.dispatch(KeyEvent(kind: nkEnter, modifier: kmNone))
    check enterCount == 1
    check shiftEnterCount == 0

    bus.dispatch(KeyEvent(kind: nkEnter, modifier: kmShift))
    check enterCount == 1
    check shiftEnterCount == 1

  test "Shift+Enter falls back to Enter handler when not registered":
    let bus = newEventBus()
    var enterCount = 0
    bus.onEnter(proc() = inc enterCount)
    bus.dispatch(KeyEvent(kind: nkEnter, modifier: kmShift))
    check enterCount == 1

  test "Ctrl+letter dispatches via control char":
    let bus = newEventBus()
    var ctrlLCount = 0
    bus.onCtrlKey("l", proc() = inc ctrlLCount)

    # Ctrl+L arrives as nkChar with the control char 0x0C
    bus.dispatch(KeyEvent(kind: nkChar, ch: "\x0c", modifier: kmCtrl))
    check ctrlLCount == 1

  test "Ctrl+Enter has its own handler":
    let bus = newEventBus()
    var enterCount = 0
    var ctrlEnterCount = 0
    bus.onEnter(proc() = inc enterCount)
    bus.onCtrlKey(nkEnter, proc() = inc ctrlEnterCount)

    bus.dispatch(KeyEvent(kind: nkEnter, modifier: kmCtrl))
    check enterCount == 0
    check ctrlEnterCount == 1

  test "modified arrow keys dispatch to default when no modifier handler":
    let bus = newEventBus()
    var upCount = 0
    bus.onArrow(akUp, proc() = inc upCount)
    bus.dispatch(KeyEvent(kind: nkUp, modifier: kmShift))
    check upCount == 1
