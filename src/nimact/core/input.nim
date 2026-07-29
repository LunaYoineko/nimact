## =============================================================================
## nimact/core/input.nim
## Terminal keyboard input module.
##
## Features:
##   - Non-blocking key read: reads from stdin with VTIME-based timeout
##   - Escape sequence parsing: arrow keys, function keys, CSI/SS3 sequences
##   - KeyEvent type: stores key kind and character data
##
## Key mapping:
##   Arrow keys: \e[A-D -> nkUp/Down/Right/Left
##   Enter: \r or \n -> nkEnter
##   Escape: \e (standalone) -> nkEscape
##   Other: nkChar (ch field holds the character)
##   Unknown CSI/SS3 sequences -> nkUnknown (residual bytes consumed)
##
## Design: escape sequences up to 16 bytes are fully consumed to prevent
##         residual bytes from corrupting subsequent input reads.
## =============================================================================

## C read() binding
proc c_read(fd: cint, buf: pointer, count: csize_t): csize_t
    {.importc: "read", header: "<unistd.h>".}

const STDIN_FILENO = 0.cint

# =============================================================================
# キー入力の型定義
# =============================================================================

type
    KeyKind* = enum
        nkChar,     ## Normal character key
        nkBackspace, ## Backspace key (\x7f or \x08)
        nkUp,       ## Arrow key up
        nkDown,     ## Arrow key down
        nkRight,    ## Arrow key right
        nkLeft,     ## Arrow key left
        nkEscape,   ## Escape key
        nkEnter,    ## Enter key (\r or \n)
        nkUnknown,  ## Unknown escape sequence
        nkNone,     ## No input (timeout)

    KeyEvent* = object
        kind*: KeyKind
        ch*: string

# =============================================================================
# Key input reading
# =============================================================================

## Read from stdin and return a KeyEvent (non-blocking).
## Escape sequences up to 16 bytes are fully consumed to prevent
## residual bytes from corrupting subsequent reads.
proc pollKey*(): KeyEvent =
    var buf: array[16, char]

    let bytesRead = c_read(STDIN_FILENO, buf[0].addr, 1)

    if bytesRead <= 0:
        return KeyEvent(kind: nkNone)

    case buf[0]
    of '\e':
        # Read remaining bytes of the escape sequence with timeout
        var pos = 1
        while pos < buf.len:
            let n = c_read(STDIN_FILENO, buf[pos].addr, 1)
            if n <= 0: break
            # BEL or ST terminates the sequence
            if buf[pos] == '\x07' or buf[pos] == '\\':
                pos += 1
                break
            pos += 1

        if pos == 1:
            return KeyEvent(kind: nkEscape)

        if buf[1] == '[':
            # CSI sequence: final byte determines the key
            let final = buf[pos - 1]
            case final
            of 'A': return KeyEvent(kind: nkUp)
            of 'B': return KeyEvent(kind: nkDown)
            of 'C': return KeyEvent(kind: nkRight)
            of 'D': return KeyEvent(kind: nkLeft)
            else:
                # Home, End, Delete, PgUp, PgDn, F-keys, etc.
                return KeyEvent(kind: nkUnknown)
        elif buf[1] == 'O':
            # SS3 sequence: F1-F4 (\eOP - \eOS)
            return KeyEvent(kind: nkUnknown)

        return KeyEvent(kind: nkEscape)

    of '\r', '\n':
        return KeyEvent(kind: nkEnter)

    of '\x7f', '\x08':
        return KeyEvent(kind: nkBackspace)

    else:
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
