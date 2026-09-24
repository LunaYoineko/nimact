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
## Cross-platform:
##   - Windows: Windows Console API (ReadConsoleInputW)
##   - Linux/macOS: POSIX read() + select()
## =============================================================================

when not defined(windows):
  import std/posix

# =============================================================================
# Key input types (shared)
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

const STDIN_FILENO = 0

# =============================================================================
# Platform-specific bindings
# =============================================================================

when defined(windows):
  {.passL: "-lkernel32".}

  type
    HANDLE* = pointer
    BOOL* = int32
    COORD = object
      X: int16
      Y: int16

    KEY_EVENT_RECORD = object
      bKeyDown: int32
      wRepeatCount: uint16
      wVirtualKeyCode: uint16
      wVirtualScanCode: uint16
      uChar: array[2, char]  # WCHAR (2 bytes)
      dwControlKeyState: uint32

    MOUSE_EVENT_RECORD = object
      dwMousePosition: COORD
      dwButtonState: uint32
      dwControlKeyState: uint32
      dwEventFlags: uint32

    WINDOW_BUFFER_SIZE_RECORD = object
      dwSize: COORD

    MENU_EVENT_RECORD = object
      dwCommandId: uint32

    FOCUS_EVENT_RECORD = object
      bSetFocus: int32

    InputRecordKind* = enum
      irkNone = 0,
      irkKeyEvent = 1,
      irkMouseEvent = 2,
      irkWindowBufferSizeEvent = 4,
      irkMenuEvent = 8,
      irkFocusEvent = 16

    INPUT_RECORD_UNION = object
      case kind: InputRecordKind
      of irkNone:
        dummy: int32
      of irkKeyEvent:
        keyEvent: KEY_EVENT_RECORD
      of irkMouseEvent:
        mouseEvent: MOUSE_EVENT_RECORD
      of irkWindowBufferSizeEvent:
        windowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD
      of irkMenuEvent:
        menuEvent: MENU_EVENT_RECORD
      of irkFocusEvent:
        focusEvent: FOCUS_EVENT_RECORD

    INPUT_RECORD = object
      eventType: uint16
      padding: uint16
      event: INPUT_RECORD_UNION

  const
    WIN_KEY_EVENT              = 0x0001
    WIN_MOUSE_EVENT            = 0x0002
    WIN_WINDOW_BUFFER_SIZE_EVENT = 0x0004
    WIN_MENU_EVENT             = 0x0008
    WIN_FOCUS_EVENT            = 0x0010

    # Virtual key codes
    VK_ESCAPE  = 0x1B
    VK_RETURN  = 0x0D
    VK_BACK    = 0x08
    VK_TAB     = 0x09
    VK_UP      = 0x26
    VK_DOWN    = 0x28
    VK_LEFT    = 0x25
    VK_RIGHT   = 0x27
    VK_SHIFT   = 0x10
    VK_CONTROL = 0x11
    VK_MENU    = 0x12  # Alt
    VK_SPACE   = 0x20

    # Control key state flags
    RIGHT_ALT_PRESSED     = 0x0001
    LEFT_ALT_PRESSED      = 0x0002
    RIGHT_CTRL_PRESSED    = 0x0004
    LEFT_CTRL_PRESSED     = 0x0008
    SHIFT_PRESSED         = 0x0010
    NUMLOCK_ON            = 0x0020
    SCROLLLOCK_ON         = 0x0040
    CAPSLOCK_ON           = 0x0080
    ENHANCED_KEY          = 0x0100

  proc GetStdHandle(nStdHandle: int32): HANDLE
    {.importc: "GetStdHandle", dynlib: "kernel32.dll".}

  proc ReadConsoleInputW(hConsoleInput: HANDLE, lpBuffer: pointer,
                          nLength: uint32, lpNumberOfEventsRead: ptr uint32): BOOL
    {.importc: "ReadConsoleInputW", dynlib: "kernel32.dll".}

  proc WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: uint32): uint32
    {.importc: "WaitForSingleObject", dynlib: "kernel32.dll".}

  proc GetNumberOfConsoleInputEvents(hConsoleInput: HANDLE,
                                      lpcNumberOfEvents: ptr uint32): BOOL
    {.importc: "GetNumberOfConsoleInputEvents", dynlib: "kernel32.dll".}

  const
    WAIT_OBJECT_0 = 0x00000000
    WAIT_TIMEOUT  = 0x00000102

  var hStdin: HANDLE

else:
  ## C read() binding
  proc c_read(fd: cint, buf: pointer, count: csize_t): csize_t
    {.importc: "read", header: "<unistd.h>".}

# =============================================================================
# Escape sequence parsing helpers (shared)
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

## Check whether data is available on stdin without blocking.
proc dataAvailable*(fd: cint): bool {.inline.} =
  when defined(windows):
    var numEvents: uint32
    discard GetNumberOfConsoleInputEvents(hStdin, addr numEvents)
    return numEvents > 0
  else:
    var readfds: TFdSet
    FD_ZERO(readfds)
    FD_SET(fd, readfds)
    var tv: Timeval
    tv.tv_sec = Time(0)
    tv.tv_usec = 0
    select(fd + 1, addr readfds, nil, nil, addr tv) > 0

## Initialize input subsystem (called once at startup).
proc initInput*() =
  when defined(windows):
    hStdin = GetStdHandle(-10)  # STD_INPUT_HANDLE

## Read from stdin and return a KeyEvent (non-blocking).
proc pollKey*(): KeyEvent =
  when defined(windows):
    # Check if any input events are available
    if not dataAvailable(STDIN_FILENO):
      return KeyEvent(kind: nkNone)

    var records: array[16, INPUT_RECORD]
    var numRead: uint32 = 0

    # Read available events
    if ReadConsoleInputW(hStdin, addr records[0], 16, addr numRead) == 0:
      return KeyEvent(kind: nkNone)

    # Process events in order, return first key event
    for i in 0 ..< int(numRead):
      let rec = records[i]
      if rec.eventType == WIN_KEY_EVENT:
        let keyRec = rec.event.keyEvent
        if keyRec.bKeyDown == 0:
          # Key release - kitty keyboard protocol style
          continue  # For now, ignore key releases

        let vk = keyRec.wVirtualKeyCode
        let ctrlState = keyRec.dwControlKeyState
        let isShift = (ctrlState and SHIFT_PRESSED) != 0
        let isCtrl = (ctrlState and (LEFT_CTRL_PRESSED or RIGHT_CTRL_PRESSED)) != 0
        let isAlt = (ctrlState and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) != 0

        let modifier =
          if isShift and isCtrl: kmShiftCtrl
          elif isShift: kmShift
          elif isCtrl: kmCtrl
          else: kmNone

        # Convert virtual key to KeyEvent
        case vk
        of VK_ESCAPE:
          return KeyEvent(kind: nkEscape, modifier: modifier)
        of VK_RETURN:
          return KeyEvent(kind: nkEnter, modifier: modifier)
        of VK_BACK:
          return KeyEvent(kind: nkBackspace, modifier: modifier)
        of VK_TAB:
          if isShift:
            return KeyEvent(kind: nkChar, ch: "\t", modifier: kmShift)
          else:
            return KeyEvent(kind: nkChar, ch: "\t", modifier: modifier)
        of VK_UP:
          return KeyEvent(kind: nkUp, modifier: modifier)
        of VK_DOWN:
          return KeyEvent(kind: nkDown, modifier: modifier)
        of VK_LEFT:
          return KeyEvent(kind: nkLeft, modifier: modifier)
        of VK_RIGHT:
          return KeyEvent(kind: nkRight, modifier: modifier)
        of VK_SPACE:
          if isCtrl:
            return KeyEvent(kind: nkChar, ch: " ", modifier: kmCtrl)
          else:
            return KeyEvent(kind: nkChar, ch: " ", modifier: modifier)
        else:
          # Check for printable character
          let charVal = keyRec.uChar[0]
          if charVal != '\x00':
            let chStr = $charVal
            # Handle Ctrl+A..Ctrl+Z (ASCII 1..26)
            if charVal.ord in 1 .. 26:
              return KeyEvent(kind: nkChar, ch: chStr, modifier: kmCtrl)
            return KeyEvent(kind: nkChar, ch: chStr, modifier: modifier)

    return KeyEvent(kind: nkNone)

  else:
    # POSIX implementation
    var buf: array[32, char]

    if not dataAvailable(STDIN_FILENO):
      return KeyEvent(kind: nkNone)

    let bytesRead = c_read(STDIN_FILENO, buf[0].addr, 1)

    if bytesRead <= 0:
      return KeyEvent(kind: nkNone)

    case buf[0]
    of '\e':
      var seq = "\e"
      while seq.len < buf.len:
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
        if c[0] == '\x07' or c[0] == '\\':
          break
        if seq.len >= 3 and seq[1] == '[' and c[0].byte in 0x40'u8 .. 0x7E'u8:
          break
      return parseEscapeSequence(seq)

    of '\r':
      return KeyEvent(kind: nkEnter)

    of '\n':
      return KeyEvent(kind: nkEnter, modifier: kmCtrl)

    of '\x7f', '\x08':
      return KeyEvent(kind: nkBackspace)

    else:
      let b = buf[0].byte
      if b in 1.byte .. 26.byte:
        return KeyEvent(kind: nkChar, ch: $buf[0], modifier: kmCtrl)
      if b == 0x00:
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