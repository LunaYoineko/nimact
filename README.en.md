# Nimact

A modern, minimal TUI framework for Nim. Build UIs declaratively with a component-based API.

## Features

- **Declarative API** — Build UIs by composing components
- **Auto layout** — No manual coordinate calculation with `vbox`, `hbox`, `center`
- **Auto docking** — `header` pins to top, `footer` pins to bottom automatically
- **Diff rendering** — Only redraws changed cells for smooth 60FPS rendering
- **TrueColor** — 24-bit color support
- **Unicode support** — Japanese text and emoji render correctly
- **Async event loop** — Built on `async/await`

## Installation

```bash
# 1. Create a project
mkdir myapp && cd myapp
nimble init

# 2. Install nimact
nimble install https://github.com/LunaYoineko/nimact

# 3. Add dependency to your .nimble file
# Add the following to the dependencies section of myapp.nimble:
#   requires "nimact"

# 4. Compile and run
nim c -r src/myapp.nim
```

## Quick Start

```nim
import std/asyncdispatch
import nimact

var count = 0

let app = newApp()

proc build(): Widget =
  vbox(
    header("My App", fg = colWhite, bg = colBlue, bold = true),
    center(40, 10,
      label("Counter: " & $count, fg = colGreen, bold = true),
      progress(count.float, max = 20.0, fg = colBlue)
    ),
    footer("SPACE: +1 | Q: Quit", fg = colTextMuted, bg = colBgDark)
  )

app.onKey(' ', proc() = inc count)
app.onKey('q', proc() = app.quit())

waitFor app.run(build)
```

`header` and `footer` are automatically docked to the top and bottom of the screen.

## Components

### label — Text display

```nim
label("Hello, World!")
label("Bold text", fg = colGreen, bold = true)
label("Colored", fg = colRed, bg = colBgCard)
```

| Parameter | Type | Description |
|---|---|---|
| `text` | `string` | Text to display |
| `fg` | `Color` | Foreground color (default: terminal default) |
| `bg` | `Color` | Background color |
| `bold` | `bool` | Bold text |

### vbox — Vertical layout

```nim
vbox(
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

With gap:

```nim
vbox(1,
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

With background color:

```nim
vbox(style(bg = colBgCard),
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

With gap and background color:

```nim
vbox(1, style(bg = colBgCard),
  label("1st"),
  label("2nd"),
  label("3rd")
)
```

| Parameter | Type | Description |
|---|---|---|
| `gap` | `int` | Space between children (rows) |
| `style` | `Style` | Container style (background color, etc.) |

### hbox — Horizontal layout

```nim
hbox(
  label("Left"),
  label("Center"),
  label("Right")
)
```

With gap:

```nim
hbox(2,
  label("A"),
  label("B"),
  label("C")
)
```

With background color:

```nim
hbox(style(bg = colBgCard),
  label("Left"),
  label("Center"),
  label("Right")
)
```

With gap and background color:

```nim
hbox(2, style(bg = colBgCard),
  label("A"),
  label("B"),
  label("C")
)
```

| Parameter | Type | Description |
|---|---|---|
| `gap` | `int` | Space between children (columns) |
| `style` | `Style` | Container style (background color, etc.) |

### center — Centered box

Renders child widgets centered within a fixed-size region.

```nim
center(40, 10,
  label("This is centered"),
  label("Inside a 40x10 box")
)
```

| Parameter | Type | Description |
|---|---|---|
| `w` | `int` | Box width |
| `h` | `int` | Box height |

### box — Bordered panel

Creates a bordered box with child widgets rendered inside.

```nim
box(30, 8, style(fg = colBlue), bsRounded,
  label("Title", bold = true),
  label("Content")
)
```

| Parameter | Type | Description |
|---|---|---|
| `w` | `int` | Box width (including borders) |
| `h` | `int` | Box height (including borders) |
| `style` | `Style` | Border and interior style |
| `borderType` | `BorderStyle` | Border style (default: `bsRounded`) |

Border styles:

| Constant | Border |
|---|---|
| `bsSingle` | `┌┐└┘─│` |
| `bsDouble` | `╔╗╚╝═║` |
| `bsRounded` | `╭╮╰╯─│` |
| `bsBold` | `┏┓┗┛━┃` |

### header — Header bar

Full-width bar at the top of the screen. When used as a child of `vbox`, it is automatically pinned to the top.

```nim
header("My App", fg = colWhite, bg = colBlue, bold = true)
```

### footer — Footer bar

Full-width bar at the bottom of the screen. When used as a child of `vbox`, it is automatically pinned to the bottom.

```nim
footer("Q: Quit | SPACE: Action", fg = colTextMuted, bg = colBgDark)
```

### progress — Progress bar

```nim
progress(0.75)              # 75% (default max = 1.0)
progress(50.0, max = 100.0) # 50%
progress(5.0, max = 10.0, fg = colCyan)
```

| Parameter | Type | Description |
|---|---|---|
| `value` | `float` | Current value |
| `max` | `float` | Maximum value (default: 1.0) |
| `fg` | `Color` | Fill color |

### separator — Divider line

```nim
separator(fg = colTextMuted)
```

### spacer — Blank space

```nim
spacer(2) # 2 rows of blank space
```

## Key Events

### Character keys

```nim
app.onKey(' ', proc() = doSomething())
app.onKey('q', proc() = app.quit())
```

### Special keys

```nim
app.onKey(nkUp,     proc() = moveUp())
app.onKey(nkDown,   proc() = moveDown())
app.onKey(nkLeft,   proc() = moveLeft())
app.onKey(nkRight,  proc() = moveRight())
app.onKey(nkEscape, proc() = app.quit())
app.onKey(nkEnter,  proc() = submit())
```

Available `KeyKind` values:

| Value | Key |
|---|---|
| `nkUp` | ↑ |
| `nkDown` | ↓ |
| `nkLeft` | ← |
| `nkRight` | → |
| `nkEscape` | Esc |
| `nkEnter` | Enter |

## Color Palette

Built-in color constants:

| Constant | RGB | Use case |
|---|---|---|
| `colBlue` | `(97, 175, 239)` | Accent |
| `colPurple` | `(198, 120, 221)` | Title |
| `colGreen` | `(152, 195, 121)` | Success |
| `colYellow` | `(229, 192, 123)` | Warning |
| `colRed` | `(224, 108, 117)` | Error |
| `colCyan` | `(86, 182, 194)` | Info |
| `colText` | `(220, 223, 228)` | Main text |
| `colTextMuted` | `(92, 99, 112)` | Muted text |
| `colWhite` | `(255, 255, 255)` | White |
| `colBgDark` | `(30, 34, 42)` | Dark background |
| `colBgCard` | `(40, 44, 52)` | Card background |
| `colBgFocus` | `(50, 56, 66)` | Focus background |

Custom color:

```nim
let myColor = rgb(255, 128, 0) # Orange
label("Custom color", fg = myColor)
```

## Style

```nim
style(fg = colGreen, bg = colBgCard, bold = true, dim = true, italic = true, underline = true, reverse = true)
```

| Parameter | Type | Description |
|---|---|---|
| `fg` | `Color` | Foreground color |
| `bg` | `Color` | Background color |
| `bold` | `bool` | Bold |
| `dim` | `bool` | Dim (darken) |
| `italic` | `bool` | Italic |
| `underline` | `bool` | Underline |
| `reverse` | `bool` | Reverse video |

## Utility Functions

### drawString — Low-level text rendering

```nim
buf.drawString(10, 5, "Hello", style(fg = colGreen))
```

### drawBox — Low-level box rendering

```nim
buf.drawBox(5, 3, 30, 10, style(fg = colBlue), bsRounded)
```

## Examples

The `examples/` directory contains samples organized by difficulty:

| File | Difficulty | Description |
|---|---|---|
| `hello.nim` | Beginner | Minimal "Hello World" |
| `counter.nim` | Beginner-Intermediate | Counter + progress bar |
| `dashboard.nim` | Intermediate | Multi-panel layout with status display |
| `todo.nim` | Advanced | Interactive TODO list |

Run an example:

```bash
nim c -r examples/hello.nim
```

## Troubleshooting

### `cannot open file: nimact`

This error occurs when `requires "nimact"` is missing from your `.nimble` file.

Open `myapp.nimble` and add the following to the dependencies section:

```
requires "nimact"
```

## License

MIT
