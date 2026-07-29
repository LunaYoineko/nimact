## =============================================================================
## nimact/core/term.nim
## Terminal control and differential rendering engine.
##
## Features:
##   - Raw Mode: disables line buffering for immediate key input
##   - Alternate screen buffer: TUI rendering without clobbering the main screen
##   - Terminal size detection via ioctl
##   - Differential rendering: only redraws changed cells (fast)
##
## Direct C POSIX API bindings:
##   - <termios.h>: terminal attribute control
##   - <sys/ioctl.h>: ioctl for terminal size queries
## =============================================================================

import ./buffer
import std/exitprocs

# =============================================================================
# C binding for termios struct
# =============================================================================
type
    CTermios* {.importc: "struct termios", header: "<termios.h>".} = object
        c_iflag*: uint32    ## input flags
        c_oflag*: uint32    ## output flags
        c_cflag*: uint32    ## control flags
        c_lflag*: uint32    ## local flags (echo, canonical mode, etc.)
        c_cc*: array[32, uint8]  ## control characters (VMIN, VTIME, etc.)

const
    STDIN_FILENO* = 0.cint   ## stdin file descriptor
    TCSAFLUSH* = 2.cint      ## flush pending input before applying changes

# =============================================================================
# termios flag constants
# =============================================================================
var
    # --- local flags (c_lflag) ---
    ECHO*   {.importc: "ECHO",   header: "<termios.h>".}: uint32  ## echo typed characters
    ICANON* {.importc: "ICANON", header: "<termios.h>".}: uint32  ## canonical (line-buffered) mode
    IEXTEN* {.importc: "IEXTEN", header: "<termios.h>".}: uint32  ## extended input processing
    ISIG*   {.importc: "ISIG",   header: "<termios.h>".}: uint32  ## signal generation (Ctrl+C, Ctrl+Z)

    # --- input flags (c_iflag) ---
    BRKINT* {.importc: "BRKINT", header: "<termios.h>".}: uint32  ## break signal
    ICRNL*  {.importc: "ICRNL",  header: "<termios.h>".}: uint32  ## CR to NL conversion
    INPCK*  {.importc: "INPCK",  header: "<termios.h>".}: uint32  ## parity checking
    ISTRIP* {.importc: "ISTRIP", header: "<termios.h>".}: uint32  ## strip high bit
    IXON*   {.importc: "IXON",   header: "<termios.h>".}: uint32  ## XON/XOFF flow control

    # --- output flags (c_oflag) ---
    OPOST*  {.importc: "OPOST",  header: "<termios.h>".}: uint32  ## output post-processing (NL->CRNL, etc.)

    # --- control flags (c_cflag) ---
    CS8*    {.importc: "CS8",    header: "<termios.h>".}: uint32   ## 8-bit character size

    # --- control character indices ---
    VMIN*   {.importc: "VMIN",  header: "<termios.h>".}: cint    ## min bytes for non-blocking read
    VTIME*  {.importc: "VTIME", header: "<termios.h>".}: cint    ## non-blocking read timeout (10ms units)

# =============================================================================
# termios function bindings
# =============================================================================

## Get terminal attributes (C: tcgetattr)
proc tcgetattr*(fd: cint, termios_p: ptr CTermios): cint
    {.importc: "tcgetattr", header: "<termios.h>".}

## Set terminal attributes (C: tcsetattr)
proc tcsetattr*(fd: cint, optional_actions: cint, termios_p: ptr CTermios): cint
    {.importc: "tcsetattr", header: "<termios.h>".}

# =============================================================================
# Raw Mode control
# =============================================================================

## Saved original terminal settings for restore in disableRawMode
var origTermios: CTermios
var rawModeEnabled = false

proc disableRawMode*()  # forward declaration

## Enable raw mode. Returns false if stdin is not a terminal.
proc enableRawMode*(): bool =
    if tcgetattr(STDIN_FILENO, origTermios.addr) < 0:
        stderr.write("Warning: not a terminal, raw mode disabled\n")
        return false
    var raw = origTermios

    # disable local flags: echo, canonical, extended input, signals
    raw.c_lflag = raw.c_lflag and not (ECHO or ICANON or IEXTEN or ISIG)
    # disable input flags: break, CRNL, parity, strip, XON/XOFF
    raw.c_iflag = raw.c_iflag and not (BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    # enable 8-bit character size
    raw.c_cflag = raw.c_cflag or CS8
    # disable output post-processing
    raw.c_oflag = raw.c_oflag and not (OPOST)

    # VMIN=0: return immediately even with no data
    # VTIME=1: 100ms timeout when data is available
    raw.c_cc[VMIN] = 0
    raw.c_cc[VTIME] = 1

    # apply settings (flush pending input)
    if tcsetattr(STDIN_FILENO, TCSAFLUSH, raw.addr) < 0:
        stderr.write("Warning: failed to set raw mode\n")
        return false

    rawModeEnabled = true
    addExitProc(proc() = disableRawMode())

    # switch to alternate screen buffer and hide cursor
    stdout.write("\e[?1049h\e[?25l")
    stdout.flushFile()
    return true

## Restore terminal to normal mode (safe to call multiple times)
proc disableRawMode*() =
    if not rawModeEnabled: return
    rawModeEnabled = false
    stdout.write("\e[?25h\e[?1049l")
    stdout.flushFile()
    discard tcsetattr(STDIN_FILENO, TCSAFLUSH, origTermios.addr)

## Clear the entire screen (\e[2J)
proc clearScreen*() =
    stdout.write("\e[2J")
    stdout.flushFile()

# =============================================================================
# Terminal size detection (ioctl)
# =============================================================================

type Winsize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
    ws_row, ws_col: uint16      ## rows and columns (in characters)
    ws_xpixel, ws_ypixel: uint16  ## size in pixels (rarely used)

var TIOCGWINSZ {.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: culong

proc ioctl(fd: cint, request: culong, arg: pointer): cint
    {.importc: "ioctl", header: "<sys/ioctl.h>".}

## Get terminal size as (columns, rows). Falls back to 80x24 on failure.
proc getTerminalSize*(): (int, int) =
    var ws: Winsize
    if ioctl(STDIN_FILENO, TIOCGWINSZ, ws.addr) == 0 and ws.ws_col > 0:
        return (ws.ws_col.int, ws.ws_row.int)
    return (80, 24)  # fallback: classic VT100 dimensions

# =============================================================================
# ANSI escape sequence generation
# =============================================================================

## Convert a Style to an ANSI escape sequence string.
## Resets all styles first (\e[0m) to avoid leaking from previous cells.
proc ansiStyle(s: Style): string =
    var res = "\e[0m"             # reset all styles
    if s.bold: res.add("\e[1m")
    if s.dim: res.add("\e[2m")
    if s.italic: res.add("\e[3m")
    if s.underline: res.add("\e[4m")
    if s.reverse: res.add("\e[7m")
    # TrueColor foreground (38;2;R;G;B)
    if not s.fg.isDefault:
        res.add("\e[38;2;" & $s.fg.r & ";" & $s.fg.g & ";" & $s.fg.b & "m")
    # TrueColor background (48;2;R;G;B)
    if not s.bg.isDefault:
        res.add("\e[48;2;" & $s.bg.r & ";" & $s.bg.g & ";" & $s.bg.b & "m")
    return res

# =============================================================================
# Differential rendering engine
# =============================================================================

## Compare two buffers and emit only changed cells to the terminal.
##
## Benefits over full redraw:
##   - Significantly faster
##   - Minimizes I/O to the terminal
##   - Reduces screen flicker
##
## Algorithm:
##  1. Scan 2D grid as 1D (y * width + x)
##  2. Compare current vs next cell
##  3. On difference: emit cursor move + styled cell to output buffer
##  4. Flush to stdout once at the end (minimizes syscalls)
proc renderDiff*(current, next: Buffer) =
    var outBuf = ""

    for y in 0 ..< next.height:
        for x in 0 ..< next.width:
            let idx = y * next.width + x

            let cCell = if idx < current.cells.len: current.cells[idx] else: newCell()
            let nCell = next.cells[idx]

            # empty cell (second half of wide char): skip — terminal handles it
            if nCell.ch.len == 0:
                continue

            # only draw cells that changed
            if cCell != nCell:
                outBuf.add("\e[" & $(y + 1) & ";" & $(x + 1) & "H")
                outBuf.add(ansiStyle(nCell.style))
                outBuf.add(nCell.ch)

    # flush only if there were changes
    if outBuf.len > 0:
        stdout.write(outBuf)
        stdout.flushFile()
