## =============================================================================
## nimact/core/term.nim
## Terminal control and differential rendering engine.
##
## Features:
##   - Raw Mode: disables line buffering for immediate key input
##   - Alternate screen buffer: TUI rendering without clobbering the main screen
##   - Terminal size detection
##   - Differential rendering: only redraws changed cells (fast)
##
## Cross-platform:
##   - Windows: Windows Console API
##   - Linux/macOS: POSIX termios/ioctl
## =============================================================================

import ./buffer
import std/exitprocs

# =============================================================================
# Platform-specific imports
# =============================================================================

const
  STDIN_FILENO* = 0

when defined(windows):
  {.passL: "-lkernel32".}
  {.passL: "-luser32".}

  type
    HANDLE* = pointer
    BOOL* = int32

    COORD = object
      X: int16
      Y: int16

    SMALL_RECT = object
      Left: int16
      Top: int16
      Right: int16
      Bottom: int16

    CONSOLE_SCREEN_BUFFER_INFO = object
      dwSize: COORD
      dwCursorPosition: COORD
      wAttributes: uint16
      srWindow: SMALL_RECT
      dwMaximumWindowSize: COORD

    CONSOLE_CURSOR_INFO = object
      dwSize: uint32
      bVisible: int32

    CONSOLE_MODE = uint32

  const
    ENABLE_PROCESSED_INPUT      = 0x0001
    ENABLE_LINE_INPUT           = 0x0002
    ENABLE_ECHO_INPUT           = 0x0004
    ENABLE_WINDOW_INPUT         = 0x0008
    ENABLE_MOUSE_INPUT          = 0x0010
    ENABLE_INSERT_MODE          = 0x0020
    ENABLE_QUICK_EDIT_MODE      = 0x0040
    ENABLE_EXTENDED_FLAGS       = 0x0080
    ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200

    ENABLE_PROCESSED_OUTPUT     = 0x0001
    ENABLE_WRAP_AT_EOL_OUTPUT   = 0x0002
    ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
    DISABLE_NEWLINE_AUTO_RETURN = 0x0008
    ENABLE_LVB_GRID_WORLDWIDE   = 0x0010

  proc GetStdHandle(nStdHandle: int32): HANDLE
    {.importc: "GetStdHandle", dynlib: "kernel32.dll".}

  proc GetConsoleMode(hConsoleHandle: HANDLE, lpMode: ptr CONSOLE_MODE): BOOL
    {.importc: "GetConsoleMode", dynlib: "kernel32.dll".}

  proc SetConsoleMode(hConsoleHandle: HANDLE, dwMode: CONSOLE_MODE): BOOL
    {.importc: "SetConsoleMode", dynlib: "kernel32.dll".}

  proc GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE,
                                  lpConsoleScreenBufferInfo: ptr CONSOLE_SCREEN_BUFFER_INFO): BOOL
    {.importc: "GetConsoleScreenBufferInfo", dynlib: "kernel32.dll".}

  proc SetConsoleScreenBufferSize(hConsoleOutput: HANDLE, dwSize: COORD): BOOL
    {.importc: "SetConsoleScreenBufferSize", dynlib: "kernel32.dll".}

  proc SetConsoleCursorInfo(hConsoleOutput: HANDLE,
                            lpConsoleCursorInfo: ptr CONSOLE_CURSOR_INFO): BOOL
    {.importc: "SetConsoleCursorInfo", dynlib: "kernel32.dll".}

  proc SetConsoleActiveScreenBuffer(hConsoleOutput: HANDLE): BOOL
    {.importc: "SetConsoleActiveScreenBuffer", dynlib: "kernel32.dll".}

  proc CreateConsoleScreenBuffer(dwDesiredAccess: uint32, dwShareMode: uint32,
                                 lpSecurityAttributes: pointer, dwFlags: uint32,
                                 lpScreenBufferData: pointer): HANDLE
    {.importc: "CreateConsoleScreenBuffer", dynlib: "kernel32.dll".}

  const
    GENERIC_READ    = 0x80000000'u32
    GENERIC_WRITE   = 0x40000000'u32
    FILE_SHARE_READ  = 0x00000001'u32
    FILE_SHARE_WRITE = 0x00000002'u32
    CONSOLE_TEXTMODE_BUFFER = 1'u32

# =============================================================================
# POSIX bindings (Linux/macOS)
# =============================================================================

when not defined(windows):
  type
    CTermios* {.importc: "struct termios", header: "<termios.h>".} = object
      c_iflag*: uint32
      c_oflag*: uint32
      c_cflag*: uint32
      c_lflag*: uint32
      c_cc*: array[32, uint8]

  const
    STDIN_FILENO* = 0.cint
    TCSAFLUSH* = 2.cint

  var
    ECHO*   {.importc: "ECHO",   header: "<termios.h>".}: uint32
    ICANON* {.importc: "ICANON", header: "<termios.h>".}: uint32
    IEXTEN* {.importc: "IEXTEN", header: "<termios.h>".}: uint32
    ISIG*   {.importc: "ISIG",   header: "<termios.h>".}: uint32
    BRKINT* {.importc: "BRKINT", header: "<termios.h>".}: uint32
    ICRNL*  {.importc: "ICRNL",  header: "<termios.h>".}: uint32
    INPCK*  {.importc: "INPCK",  header: "<termios.h>".}: uint32
    ISTRIP* {.importc: "ISTRIP", header: "<termios.h>".}: uint32
    IXON*   {.importc: "IXON",   header: "<termios.h>".}: uint32
    OPOST*  {.importc: "OPOST",  header: "<termios.h>".}: uint32
    CS8*    {.importc: "CS8",    header: "<termios.h>".}: uint32
    VMIN*   {.importc: "VMIN",  header: "<termios.h>".}: cint
    VTIME*  {.importc: "VTIME", header: "<termios.h>".}: cint

  proc tcgetattr*(fd: cint, termios_p: ptr CTermios): cint
    {.importc: "tcgetattr", header: "<termios.h>".}

  proc tcsetattr*(fd: cint, optional_actions: cint, termios_p: ptr CTermios): cint
    {.importc: "tcsetattr", header: "<termios.h>".}

  type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
    ws_row, ws_col: uint16
    ws_xpixel, ws_ypixel: uint16

  var TIOCGWINSZ {.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: culong

  proc ioctl(fd: cint, request: culong, arg: pointer): cint
    {.importc: "ioctl", header: "<sys/ioctl.h>".}

# =============================================================================
# Cross-platform state
# =============================================================================

var
  rawModeEnabled = false
  origConsoleMode: uint32
  origConsoleModeOut: uint32
  hStdin: HANDLE
  hStdout: HANDLE
  hAltBuffer: HANDLE

when not defined(windows):
  var origTermios: CTermios

# =============================================================================
# Cross-platform raw mode
# =============================================================================

proc disableRawMode*()

## Enable raw mode. Returns false if stdin is not a terminal.
proc enableRawMode*(): bool =
  when defined(windows):
    hStdin = GetStdHandle(-10)  # STD_INPUT_HANDLE
    hStdout = GetStdHandle(-11) # STD_OUTPUT_HANDLE

    if hStdin == nil:
      stderr.write("Warning: not a console, raw mode disabled\n")
      return false

    var modeIn: CONSOLE_MODE
    var modeOut: CONSOLE_MODE
    if GetConsoleMode(hStdin, addr modeIn) == 0:
      stderr.write("Warning: GetConsoleMode failed\n")
      return false
    if GetConsoleMode(hStdout, addr modeOut) == 0:
      stderr.write("Warning: GetConsoleMode failed for stdout\n")
      return false

    origConsoleMode = modeIn
    origConsoleModeOut = modeOut

    # Disable line input, echo, and processed input
    # Enable virtual terminal input for escape sequences
    let newModeIn = modeIn and CONSOLE_MODE(not (ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT or ENABLE_PROCESSED_INPUT)) or ENABLE_VIRTUAL_TERMINAL_INPUT
    let newModeOut = modeOut or ENABLE_VIRTUAL_TERMINAL_PROCESSING

    if SetConsoleMode(hStdin, newModeIn) == 0:
      stderr.write("Warning: SetConsoleMode failed for stdin\n")
      return false
    if SetConsoleMode(hStdout, newModeOut) == 0:
      stderr.write("Warning: SetConsoleMode failed for stdout\n")
      return false

    # Create alternate screen buffer
    hAltBuffer = CreateConsoleScreenBuffer(GENERIC_READ or GENERIC_WRITE,
                                            FILE_SHARE_READ or FILE_SHARE_WRITE,
                                            nil, CONSOLE_TEXTMODE_BUFFER, nil)
    if hAltBuffer != nil:
      discard SetConsoleActiveScreenBuffer(hAltBuffer)

    # Hide cursor
    var cursorInfo: CONSOLE_CURSOR_INFO
    cursorInfo.dwSize = 25
    cursorInfo.bVisible = 0
    discard SetConsoleCursorInfo(hAltBuffer, addr cursorInfo)

    # Enable VT processing on alt buffer too
    var altMode: CONSOLE_MODE
    if GetConsoleMode(hAltBuffer, addr altMode) != 0:
      discard SetConsoleMode(hAltBuffer, altMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING)

    rawModeEnabled = true
    addExitProc(proc() = disableRawMode())

    # Clear screen and enable kitty keyboard protocol
    stdout.write("\e[2J\e[?25l\e[>1u")
    stdout.flushFile()
    return true

  else:
    # POSIX implementation
    if tcgetattr(STDIN_FILENO, origTermios.addr) < 0:
      stderr.write("Warning: not a terminal, raw mode disabled\n")
      return false
    var raw = origTermios

    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or IEXTEN or ISIG)
    raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    raw.c_cflag = raw.c_cflag or CS8
    raw.c_oflag = raw.c_oflag and not (OPOST)

    raw.c_cc[VMIN] = 0
    raw.c_cc[VTIME] = 1

    if tcsetattr(STDIN_FILENO, TCSAFLUSH, raw.addr) < 0:
      stderr.write("Warning: failed to set raw mode\n")
      return false

    rawModeEnabled = true
    addExitProc(proc() = disableRawMode())

    stdout.write("\e[?1049h\e[?25l\e[>1u")
    stdout.flushFile()
    return true

## Restore terminal to normal mode (safe to call multiple times)
proc disableRawMode*() =
  if not rawModeEnabled: return
  rawModeEnabled = false

  when defined(windows):
    # Restore original screen buffer
    if hAltBuffer != nil:
      discard SetConsoleActiveScreenBuffer(hStdout)
    # Restore console modes
    if hStdin != nil:
      discard SetConsoleMode(hStdin, origConsoleMode)
    if hStdout != nil:
      discard SetConsoleMode(hStdout, origConsoleModeOut)

    # Show cursor and disable kitty protocol
    stdout.write("\e[?25h\e[<1u")
    stdout.flushFile()
  else:
    stdout.write("\e[<1u\e[?25h\e[?1049l")
    stdout.flushFile()
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, origTermios.addr)

# =============================================================================
# Kitty keyboard protocol
# =============================================================================

## Enable the kitty keyboard protocol (disambiguate escape codes).
proc enableKittyKeyboardProtocol*() =
  stdout.write("\e[>1u")
  stdout.flushFile()

## Disable (pop) the kitty keyboard protocol.
proc disableKittyKeyboardProtocol*() =
  stdout.write("\e[<1u")
  stdout.flushFile()

## Clear the entire screen
proc clearScreen*() =
  stdout.write("\e[2J")
  stdout.flushFile()

# =============================================================================
# Terminal size detection
# =============================================================================

## Get terminal size as (columns, rows). Falls back to 80x24 on failure.
proc getTerminalSize*(): (int, int) =
  when defined(windows):
    var csbi: CONSOLE_SCREEN_BUFFER_INFO
    if GetConsoleScreenBufferInfo(hStdout, addr csbi) != 0:
      let width = (csbi.srWindow.Right - csbi.srWindow.Left + 1).int
      let height = (csbi.srWindow.Bottom - csbi.srWindow.Top + 1).int
      if width > 0 and height > 0:
        return (width, height)
    return (80, 24)
  else:
    var ws: Winsize
    if ioctl(STDIN_FILENO, TIOCGWINSZ, ws.addr) == 0 and ws.ws_col > 0:
      return (ws.ws_col.int, ws.ws_row.int)
    return (80, 24)

# =============================================================================
# ANSI escape sequence generation
# =============================================================================

## Convert a Style to an ANSI escape sequence string.
proc ansiStyle(s: Style): string =
  var res = "\e[0m"
  if s.bold: res.add("\e[1m")
  if s.dim: res.add("\e[2m")
  if s.italic: res.add("\e[3m")
  if s.underline: res.add("\e[4m")
  if s.reverse: res.add("\e[7m")
  if not s.fg.isDefault:
    res.add("\e[38;2;" & $s.fg.r & ";" & $s.fg.g & ";" & $s.fg.b & "m")
  if not s.bg.isDefault:
    res.add("\e[48;2;" & $s.bg.r & ";" & $s.bg.g & ";" & $s.bg.b & "m")
  return res

# =============================================================================
# Differential rendering engine
# =============================================================================

## Compare two buffers and emit only changed cells to the terminal.
proc renderDiff*(current, next: Buffer) =
  var outBuf = ""

  for y in 0 ..< next.height:
    for x in 0 ..< next.width:
      let idx = y * next.width + x

      let cCell = if idx < current.cells.len: current.cells[idx] else: newCell()
      let nCell = next.cells[idx]

      if nCell.ch.len == 0:
        continue

      if cCell != nCell:
        outBuf.add("\e[" & $(y + 1) & ";" & $(x + 1) & "H")
        outBuf.add(ansiStyle(nCell.style))
        outBuf.add(nCell.ch)

  if outBuf.len > 0:
    stdout.write(outBuf)
    stdout.flushFile()