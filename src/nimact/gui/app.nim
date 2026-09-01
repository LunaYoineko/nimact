## =============================================================================
## nimact/gui/app.nim
## GUI アプリケーションライフサイクルとレンダリングループ
##
## X11 ウィンドウの作成、イベントループ、ウィジェットツリーの
## レンダリングを統合するトップレベルモジュール
## =============================================================================

import std/exitprocs
import ../core/platform
import ../core/graphics
import ../core/text
import ./widget

{.passC: "-D_XOPEN_SOURCE=700".}

{.emit: """
#include <time.h>
""".}

export platform, graphics, text, widget

# =============================================================================
# GUI App type
# =============================================================================

type
  GuiApp* = ref object
    window*: PlatformWindow
    buffer*: PixelBuffer
    graphics*: GraphicsContext
    running*: bool
    frameRate*: int
    lastFrameTime*: float
    needsRedraw*: bool
    font*: Font
    mouseX*, mouseY*: int

proc newGuiApp*(title: string = "Nimact GUI",
                width: int = 800,
                height: int = 600,
                frameRate: int = 60): GuiApp =
  let window = newPlatformWindow(title, width, height)
  let buffer = newPixelBuffer(width, height)
  let gc = newGraphicsContext(buffer)

  result = GuiApp(
    window: window,
    buffer: buffer,
    graphics: gc,
    running: false,
    frameRate: frameRate,
    needsRedraw: true,
    font: loadFont("", 16),
    mouseX: 0,
    mouseY: 0
  )

  setDefaultFont(result.font)
  var appRef = result
  addExitProc(proc() =
    if appRef.window != nil:
      appRef.window.close()
      appRef.window = nil
  )

# =============================================================================
# Event processing
# =============================================================================

type
  GuiEventHandler* = ref object
    onKeyPress*: proc(keySym: culong, keyStr: string): bool  # return true to consume
    onKeyRelease*: proc(keySym: culong, keyStr: string)
    onMousePress*: proc(button, x, y: int): bool
    onMouseRelease*: proc(button, x, y: int)
    onMouseMove*: proc(x, y: int)
    onResize*: proc(width, height: int)
    onQuit*: proc()

proc newGuiEventHandler*(): GuiEventHandler =
  GuiEventHandler()

proc processEvents*(app: GuiApp, handler: GuiEventHandler = nil) =
  while true:
    let ev = app.window.pollEvent()
    case ev.kind
    of geNone:
      break
    of geQuit:
      app.running = false
      if handler != nil and handler.onQuit != nil:
        handler.onQuit()
    of geKeyPress:
      if handler != nil and handler.onKeyPress != nil:
        if handler.onKeyPress(ev.keySym, ev.keyString):
          app.needsRedraw = true
    of geKeyRelease:
      if handler != nil and handler.onKeyRelease != nil:
        handler.onKeyRelease(ev.keySym, ev.keyString)
    of geButtonPress:
      app.needsRedraw = true
      if handler != nil and handler.onMousePress != nil:
        if handler.onMousePress(ev.button, ev.mouseX, ev.mouseY):
          app.needsRedraw = true
    of geButtonRelease:
      app.needsRedraw = true
      if handler != nil and handler.onMouseRelease != nil:
        handler.onMouseRelease(ev.button, ev.mouseX, ev.mouseY)
    of geMotion:
      app.mouseX = ev.mouseX
      app.mouseY = ev.mouseY
      if handler != nil and handler.onMouseMove != nil:
        handler.onMouseMove(ev.mouseX, ev.mouseY)
    of geResize:
      app.buffer = newPixelBuffer(ev.width, ev.height)
      app.graphics = newGraphicsContext(app.buffer)
      app.needsRedraw = true
      if handler != nil and handler.onResize != nil:
        handler.onResize(ev.width, ev.height)
    of geExpose:
      app.needsRedraw = true

# =============================================================================
# Rendering
# =============================================================================

proc renderFrame*(app: GuiApp, build: proc(): Widget) =
  if not app.needsRedraw:
    return

  # Clear buffer
  app.buffer.clear(colBgDark)

  # Build widget tree
  let root = build()

  # Measure and render
  let constraints = LayoutConstraints(
    minWidth: app.window.width,
    maxWidth: app.window.width,
    minHeight: app.window.height,
    maxHeight: app.window.height
  )
  let size = root.measure(constraints)
  root.render(app.graphics, 0, 0, app.window.width, app.window.height)

  # Flush to window
  block:
    let count = min(app.window.pixels.len, app.buffer.pixels.len)
    for i in 0 ..< count:
      app.window.pixels[i] = app.buffer.pixels[i]
  app.window.flush()
  app.needsRedraw = false

proc renderOnce*(app: GuiApp, build: proc(): Widget) =
  ## Render a single frame without the event loop
  app.buffer.clear(colBgDark)
  let root = build()
  let constraints = LayoutConstraints(
    minWidth: app.window.width,
    maxWidth: app.window.width,
    minHeight: app.window.height,
    maxHeight: app.window.height
  )
  root.render(app.graphics, 0, 0, app.window.width, app.window.height)
  block:
    let count = min(app.window.pixels.len, app.buffer.pixels.len)
    for i in 0 ..< count:
      app.window.pixels[i] = app.buffer.pixels[i]
  app.window.flush()

# =============================================================================
# Main loop
# =============================================================================

proc run*(app: GuiApp, build: proc(): Widget,
          handler: GuiEventHandler = nil) =
  ## Start the GUI application main loop
  ##
  ## build: Called each frame; returns the widget tree to render
  ## handler: Optional event handler for keyboard/mouse events
  app.running = true
  app.needsRedraw = true

  let fps = app.frameRate
  let frameTimeMs = 1000 div fps

  while app.running:
    app.processEvents(handler)
    app.renderFrame(build)

    # Simple frame rate limiting
    {.emit: """
      struct timespec ts;
      ts.tv_sec = 0;
      ts.tv_nsec = `frameTimeMs` * 1000000L;
      nanosleep(&ts, NULL);
    """.}

  app.window.close()

# =============================================================================
# Convenience: Simple run with auto quit on Escape/Q
# =============================================================================

proc runSimple*(app: GuiApp, build: proc(): Widget) =
  ## Run with default handlers (Escape/Q to quit)
  let handler = newGuiEventHandler()
  handler.onKeyPress = proc(keySym: culong, keyStr: string): bool =
    if keySym == 0xff1b or keyStr == "q" or keyStr == "Q":
      app.running = false
      return true
    return false
  app.run(build, handler)

# =============================================================================
# Helper: Create a standard GUI app with common setup
# =============================================================================

proc newApp*(title: string = "Nimact GUI",
             width: int = 800,
             height: int = 600): GuiApp =
  ## Create a new GUI application with standard settings
  newGuiApp(title, width, height)
