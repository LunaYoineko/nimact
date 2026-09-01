## =============================================================================
## nimact/core/input.nim
## Terminal keyboard input module.
##
## Features:
##   - Non-blocking key read: select()-gated so pollKey() never blocks the
##     main loop; VTIME-based timeout is used only to gather multi-byte
##     escape sequences once a byte has arrived
##   - Escape sequence parsing: arrow keys, function keys, CSI/SS3 sequences
##   - Modified key support: Ctrl+KEY, Shift+KEY (kitty keyboard protocol / CSI-u)
##   - KeyEvent type: stores key kind, character data, and modifier
##
## Key mapping:
##   Arrow keys: \e[A-D -> nkUp/Down/Right/Left
##   Enter: \r or \e[13u -> nkEnter (modifier kmNone)
##   Ctrl+J / Ctrl+Enter: \n or \e[13;5u -> nkEnter (modifier kmCtrl)
##   Escape: \e (standalone) or \e[27u -> nkEscape
##   Backspace: \x7f, \x08, \e[127u -> nkBackspace
##   Tab: \t or \e[9u -> nkChar (ch = "\t")
##   Ctrl+A..Ctrl+Z: 0x01..0x1A -> nkChar (ch = control char, modifier = kmCtrl)
##   Other: nkChar (ch field holds the character)
##   Unknown CSI/SS3 sequences -> nkUnknown (residual bytes consumed)
##
## Modified keys (kitty keyboard protocol & CSI-u):
##   Shift+Enter:  \e[13;2u    Ctrl+Enter:  \e[13;5u
##   Shift+Up:     \e[1;2A     Ctrl+Up:     \e[1;5A
##   Shift+Tab:    \e[Z
##   xterm format: \e[27;2;13~ (Shift+Enter), \e[27;5;13~ (Ctrl+Enter)
##
## Press / repeat / release events (kitty keyboard protocol):
##   \e[<code>;<mod>;<event>u where event 1=press, 2=repeat, 3=release
##   e.g. 'w' press \e[119;1;1u, repeat \e[119;1;2u, release \e[119;1;3u
##   The associated-text codepoint is parsed from the 4th param when present.
##   Terminals without kitty support send plain bytes for everything, so
##   repeats are indistinguishable from presses (eventType stays kePress).
##
## Design: escape sequences up to 32 bytes are fully consumed to prevent
##         residual bytes from corrupting subsequent input reads.
## =============================================================================

import std/posix

## C read() binding
proc c_read(fd: cint, buf: pointer, count: csize_t): csize_t
    {.importc: "read", header: "<unistd.h>".}

const STDIN_FILENO = 0.cint

## Check whether data is available on `fd` without blocking.
## Returns true if a read of at least one byte would return immediately.
proc dataAvailable*(fd: cint): bool =
    var readfds: TFdSet
    FD_ZERO(readfds)
    FD_SET(fd, readfds)
    var tv: Timeval
    tv.tv_sec = Time(0)
    tv.tv_usec = 0
    select(fd + 1, addr readfds, nil, nil, addr tv) > 0

# =============================================================================
# キー入力の型定義
# =============================================================================

type
    ## 修飾キー (Shift / Ctrl) の状態
    KeyModifier* = enum
        kmNone,       ## 修飾キーなし
        kmShift,      ## Shift を押しながら
        kmCtrl,       ## Ctrl を押しながら
        kmShiftCtrl   ## Shift + Ctrl を押しながら

    KeyKind* = enum
        nkChar,       ## Normal character key
        nkBackspace,  ## Backspace key (\x7f or \x08)
        nkUp,         ## Arrow key up
        nkDown,       ## Arrow key down
        nkRight,      ## Arrow key right
        nkLeft,       ## Arrow key left
        nkEscape,     ## Escape key
        nkEnter,      ## Enter key (\r or \n)
        nkUnknown,    ## Unknown escape sequence
        nkNone        ## No input (timeout)

    ## イベントの種類 (キティキーボードプロトコルの press/repeat/release)
    ## 非対応端末ではキーリピートも press として届くため、区別できない
    KeyEventType* = enum
        kePress,       ## キー押下
        keRepeat,      ## キーリピート (押しっぱなし中に連続送信)
        keRelease,     ## キーを離した (キティプロトコルのみ)
        keUnknown      ## 種類不明

    KeyEvent* = object
        kind*: KeyKind
        ch*: string
        modifier*: KeyModifier
        eventType*: KeyEventType = kePress

# =============================================================================
# Escape sequence parsing helpers
# =============================================================================

## Extract numeric parameters from the parameter string of a CSI sequence.
## e.g. "1;2" -> [1, 2], "" -> @[], "27;2;13" -> [27, 2, 13]
proc parseCsiParams(paramsStr: string): seq[int] =
    if paramsStr.len == 0:
        return @[]
    var current = 0
    var hasDigit = false
    for c in paramsStr:
        if c >= '0' and c <= '9':
            current = current * 10 + (ord(c) - ord('0'))
            hasDigit = true
        elif c == ';':
            result.add(if hasDigit: current else: -1)
            current = 0
            hasDigit = false
        else:
            return @[]
    if hasDigit:
        result.add(current)

## Map a terminal modifier number to a KeyModifier.
## 1=none, 2=shift, 3=alt, 4=shift+alt, 5=ctrl, 6=shift+ctrl, ...
proc keyModifierFromNum(n: int): KeyModifier =
    case n
    of 2: kmShift
    of 5: kmCtrl
    of 6: kmShiftCtrl
    else: kmNone

## Map a CSI-u event-type number to a KeyEventType.
## 1=press, 2=repeat, 3=release (kitty keyboard protocol)
proc keyEventTypeFromNum(n: int): KeyEventType =
    case n
    of 2: keRepeat
    of 3: keRelease
    else: kePress

## Map a CSI-u / xterm key code to a KeyEvent with the given modifier.
## Codes: 1=Up, 2=Down, 3=Right, 4=Left, 9=Tab, 13=Enter,
##        27=Escape, 127=Backspace
proc csiCodeToKey(code: int, modifier: KeyModifier, eventType: KeyEventType = kePress): KeyEvent =
    case code
    of 1: return KeyEvent(kind: nkUp, modifier: modifier, eventType: eventType)
    of 2: return KeyEvent(kind: nkDown, modifier: modifier, eventType: eventType)
    of 3: return KeyEvent(kind: nkRight, modifier: modifier, eventType: eventType)
    of 4: return KeyEvent(kind: nkLeft, modifier: modifier, eventType: eventType)
    of 9: return KeyEvent(kind: nkChar, ch: "\t", modifier: modifier, eventType: eventType)
    of 13: return KeyEvent(kind: nkEnter, modifier: modifier, eventType: eventType)
    of 27: return KeyEvent(kind: nkEscape, modifier: modifier, eventType: eventType)
    of 127: return KeyEvent(kind: nkBackspace, modifier: modifier, eventType: eventType)
    else: return KeyEvent(kind: nkUnknown, modifier: modifier, eventType: eventType)

## Parse a CSI sequence (starting with "\e[") into a KeyEvent.
## Supports: arrows (\e[A), modified arrows (\e[1;2A),
##           Shift+Tab (\e[Z), CSI-u (\e[13;2u),
##           xterm modified keys (\e[27;2;13~)
proc parseCsiSequence(seq: string): KeyEvent =
    if seq.len < 3:
        return KeyEvent(kind: nkUnknown)

    let final = seq[^1]
    let paramsStr = if seq.len > 3: seq[2 .. ^2] else: ""
    let params = parseCsiParams(paramsStr)

    case final
    of 'A', 'B', 'C', 'D':
        # Arrow keys with optional modifier
        let arrowMod = if params.len >= 2: keyModifierFromNum(params[1]) else: kmNone
        case final
        of 'A': return KeyEvent(kind: nkUp, modifier: arrowMod)
        of 'B': return KeyEvent(kind: nkDown, modifier: arrowMod)
        of 'C': return KeyEvent(kind: nkRight, modifier: arrowMod)
        of 'D': return KeyEvent(kind: nkLeft, modifier: arrowMod)
        else: discard
    of 'Z':
        # Shift+Tab
        return KeyEvent(kind: nkChar, ch: "\t", modifier: kmShift)
    of 'u':
        # kitty keyboard protocol / CSI-u: \e[<code>;<mod>;<event>[;<text>]u
        #   code: key code (1=Up.., 13=Enter, or a printable codepoint)
        #   mod:  modifier (xterm-style 1/2/5/6, or CSI-u bitfield)
        #   event: 1=press, 2=repeat, 3=release (omitted when 1)
        #   text:  associated text codepoint (optional)
        if params.len >= 1:
            let csiMod =
                if params.len >= 2:
                    keyModifierFromNum(params[1])
                else:
                    kmNone
            let evType =
                if params.len >= 3:
                    keyEventTypeFromNum(params[2])
                else:
                    kePress

            # associated text: when present and printable, it is the char
            if params.len >= 4 and params[3] in 32 .. 126:
                return KeyEvent(kind: nkChar, ch: $char(params[3]),
                                modifier: csiMod, eventType: evType)

            # special keys (arrows, tab, enter, escape, backspace)
            if params[0] in {1, 2, 3, 4, 9, 13, 27, 127}:
                return csiCodeToKey(params[0], csiMod, evType)

            # printable key codes map directly to that character
            if params[0] in 32 .. 126:
                return KeyEvent(kind: nkChar, ch: $char(params[0]),
                                modifier: csiMod, eventType: evType)

            return KeyEvent(kind: nkUnknown, eventType: evType)
    of '~':
        # xterm modified key format: \e[27;<mod>;<code>~
        if params.len >= 3 and params[0] == 27:
            let xtermMod = keyModifierFromNum(params[1])
            return csiCodeToKey(params[2], xtermMod)
    else:
        discard

    return KeyEvent(kind: nkUnknown)

## Parse a full escape sequence string (starting with "\e") into a KeyEvent.
## Exported so parsers can be unit-tested without reading stdin.
proc parseEscapeSequence*(seq: string): KeyEvent =
    if seq.len == 0:
        return KeyEvent(kind: nkUnknown)
    if seq[0] != '\e':
        return KeyEvent(kind: nkUnknown)
    if seq.len == 1:
        return KeyEvent(kind: nkEscape)
    if seq[1] == '[':
        return parseCsiSequence(seq)
    elif seq[1] == 'O':
        # SS3 sequence: F1-F4 (\eOP - \eOS)
        return KeyEvent(kind: nkUnknown)
    return KeyEvent(kind: nkEscape)

# =============================================================================
# Key input reading
# =============================================================================

## Read from stdin and return a KeyEvent (non-blocking).
## Escape sequences up to 32 bytes are fully consumed to prevent
## residual bytes from corrupting subsequent reads.
proc pollKey*(): KeyEvent =
    var buf: array[32, char]

    # Truly non-blocking: return immediately when no input is pending so the
    # main loop can keep running at a fixed frame rate (rendering + onUpdate)
    # even while no keys are pressed.
    if not dataAvailable(STDIN_FILENO):
        return KeyEvent(kind: nkNone)

    let bytesRead = c_read(STDIN_FILENO, buf[0].addr, 1)

    if bytesRead <= 0:
        return KeyEvent(kind: nkNone)

    case buf[0]
    of '\e':
        # Read remaining bytes of the escape sequence. Uses select() with a
        # short per-byte timeout instead of relying on the terminal's VTIME
        # (which would block 100ms per byte on SSH-split sequences).
        var seq = "\e"
        while seq.len < buf.len:
            # Wait up to 10ms for the next byte (SSH-tolerant)
            var readfds: TFdSet
            FD_ZERO(readfds)
            FD_SET(STDIN_FILENO, readfds)
            var tv: Timeval
            tv.tv_sec = Time(0)
            tv.tv_usec = 10_000  # 10ms
            if select(STDIN_FILENO + 1, addr readfds, nil, nil, addr tv) <= 0:
                break
            var c: array[1, char]
            let n = c_read(STDIN_FILENO, c[0].addr, 1)
            if n <= 0: break
            seq.add(c[0])
            # BEL or ST terminates the sequence
            if c[0] == '\x07' or c[0] == '\\':
                break
            # A CSI final byte (ECMA-48: 0x40..0x7E) completes the sequence.
            # Stop here so that a neighbouring escape sequence already pending
            # in the input buffer is NOT swallowed into this one (which would
            # corrupt parsing and lose the following key event).
            if seq.len >= 3 and seq[1] == '[' and c[0].byte in 0x40'u8 .. 0x7E'u8:
                break
        return parseEscapeSequence(seq)

    of '\r':
        # Enter key sends \r (0x0D) in raw mode.
        return KeyEvent(kind: nkEnter)

    of '\n':
        # Ctrl+J sends \n (0x0A) in raw mode. This is the same byte as LF,
        # and differs from the Enter key (\r). Treat it as Ctrl+Enter so the
        # Ctrl+KEY API (onCtrlKey(nkEnter)) can distinguish it from plain Enter.
        return KeyEvent(kind: nkEnter, modifier: kmCtrl)

    of '\x7f', '\x08':
        return KeyEvent(kind: nkBackspace)

    else:
        let b = buf[0].byte
        # Ctrl+A..Ctrl+Z generates 0x01..0x1A.
        # Ambiguous control chars (Tab 0x09, Enter 0x0A/0x0D, Backspace 0x08,
        # Esc 0x1B) are handled by the cases above, so the rest are unambiguous.
        if b in 1.byte .. 26.byte:
            return KeyEvent(kind: nkChar, ch: $buf[0], modifier: kmCtrl)
        if b == 0x00:
            # Ctrl+Space / Ctrl+@
            return KeyEvent(kind: nkChar, ch: "\x00", modifier: kmCtrl)

        var chStr = $buf[0]
        if (buf[0].byte and 0xC0) == 0xC0:
            let firstByte = buf[0].byte
            var expectedBytes = 1
            if (firstByte and 0xE0) == 0xE0: expectedBytes = 2
            elif (firstByte and 0xF0) == 0xF0: expectedBytes = 3

            for i in 1..expectedBytes:
                var nextByte: array[1, char]
                let n = c_read(STDIN_FILENO, nextByte[0].addr, 1)
                if n > 0:
                    chStr.add(nextByte[0])
                else:
                    break
        return KeyEvent(kind: nkChar, ch: chStr)
