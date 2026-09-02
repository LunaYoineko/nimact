## =============================================================================
## nimact/core/platform.nim
## プラットフォーム抽象化レイヤー
##
## Wayland または X11 をサポート:
## - $WAYLAND_DISPLAY 環境変数が設定されている場合 → Wayland バックエンド
## - それ以外 → X11 バックエンド (XWayland 経由も含む)
## =============================================================================

import std/os

# =============================================================================
# Event type (shared between both backends)
# =============================================================================

type
  GuiEventKind* = enum
    geNone, geQuit, geKeyPress, geKeyRelease,
    geButtonPress, geButtonRelease, geMotion,
    geResize, geExpose

  GuiEvent* = object
    kind*: GuiEventKind
    keySym*: culong
    keyString*: string
    button*: int
    mouseX*, mouseY*: int
    width*, height*: int

const
  isWayland* = getEnv("WAYLAND_DISPLAY") != ""

# =============================================================================
# Wayland 実装 (ネイティブ)
# =============================================================================

when isWayland:
  const
    libWaylandClient* = "libwayland-client.so.0"
    libShim* = "/home/luna/.local/lib/libwayland_shim.so"

  type
    WlDisplay* = pointer
    WlSurface* = pointer

  # Shim C API bindings
  type
    WlEventCallback* = proc(eventType: cint, arg1: cint, arg2: cint,
                             keyStr: cstring) {.cdecl.}

  proc wlInitWindow*(title: cstring, width, height: cint,
                     cb: WlEventCallback): WlSurface
    {.importc: "wl_init_window", dynlib: libShim.}

  proc wlCloseWindow*(win: WlSurface)
    {.importc: "wl_close_window", dynlib: libShim.}

  proc wlPollEvents*(win: WlSurface): cint
    {.importc: "wl_poll_events", dynlib: libShim.}

  proc wlPopEvent*(eventType, arg1, arg2: var cint, keyStr: pointer, keyStrSize: cint): cint
    {.importc: "wl_pop_event", dynlib: libShim.}

  proc wlHasEvents*(): cint
    {.importc: "wl_has_events", dynlib: libShim.}

  proc wlGetPixels*(win: WlSurface, width, height: var cint): pointer
    {.importc: "wl_get_pixels", dynlib: libShim.}

  proc wlFlushBuffer*(win: WlSurface)
    {.importc: "wl_flush_buffer", dynlib: libShim.}

  proc wlGetFd*(win: WlSurface): cint
    {.importc: "wl_get_fd", dynlib: libShim.}

  # Empty callback for C interop
  proc emptyCallback(eventType: cint, arg1: cint, arg2: cint, keyStr: cstring) {.cdecl.} =
    discard

  # PlatformWindow for Wayland
  type
    PlatformWindow* = ref object
      display*: WlDisplay
      window*: WlSurface
      width*, height*: int
      pixels*: seq[uint32]

  proc newPlatformWindow*(title: string, width, height: int): PlatformWindow =
    let surface = wlInitWindow(title.cstring, width.cint, height.cint, emptyCallback)
    if surface == nil:
      raise newException(IOError, "Cannot create Wayland window")

    result = PlatformWindow(
      window: surface,
      width: width,
      height: height,
      pixels: newSeq[uint32](width * height)
    )

  proc close*(win: PlatformWindow) =
    wlCloseWindow(win.window)

  proc flush*(win: PlatformWindow) =
    wlFlushBuffer(win.window)

  proc resize*(win: PlatformWindow, width, height: int) =
    win.width = width
    win.height = height
    win.pixels.setLen(width * height)

  proc pollEvent*(win: PlatformWindow): GuiEvent =
    result = GuiEvent(kind: geNone)

    # Get all pending Wayland events
    let rc = wlPollEvents(win.window)
    if rc == -1:
      result = GuiEvent(kind: geQuit)
      return
    if rc == 1:
      result = GuiEvent(kind: geQuit)
      return

    # Pop one event from the C-side queue
    if wlHasEvents() != 0:
      var evtType: cint
      var arg1: cint
      var arg2: cint
      var keyBufArr: array[32, char]
      let hasEvent = wlPopEvent(evtType, arg1, arg2, cast[pointer](addr keyBufArr[0]), 32.cint)
      if hasEvent != 0:
        case evtType
        of 1:  # EVT_QUIT
          result = GuiEvent(kind: geQuit)
        of 2:  # EVT_KEY_PRESS
          result = GuiEvent(kind: geKeyPress, keySym: cast[culong](arg1), keyString: $cast[ptr char](addr keyBufArr[0]))
        of 3:  # EVT_KEY_RELEASE
          result = GuiEvent(kind: geKeyRelease, keySym: cast[culong](arg1))
        of 4:  # EVT_MOTION
          result = GuiEvent(kind: geMotion, mouseX: arg1, mouseY: arg2)
        of 5:  # EVT_BUTTON_PRESS
          result = GuiEvent(kind: geButtonPress, button: arg1, mouseX: arg1, mouseY: arg2)
        of 6:  # EVT_BUTTON_RELEASE
          result = GuiEvent(kind: geButtonRelease, button: arg1, mouseX: arg1, mouseY: arg2)
        of 7:  # EVT_RESIZE
          result = GuiEvent(kind: geResize, width: arg1, height: arg2)
        of 8:  # EVT_EXPOSE
          result = GuiEvent(kind: geExpose)
        of 100:  # EVT_FRAME
          result = GuiEvent(kind: geNone)
        else:
          result = GuiEvent(kind: geNone)
      else:
        result = GuiEvent(kind: geNone)

  proc symToChar*(sym: culong): char =
    if sym >= 0x20 and sym <= 0x7e:
      result = char(sym)
    else:
      result = char(0)

# =============================================================================
# X11 実装
# =============================================================================

when not isWayland:
  const
    libX11* = "libX11.so.6"

  type
    XDisplay* = pointer
    XWindow* = culong
    XAtom* = culong
    XStatus* = cint
    XID* = culong
    XVisual* = pointer
    XColormap* = culong
    XCursor* = culong

    XSetWindowAttributes* = object
      background_pixel*: culong
      border_pixel*: culong
      bit_gravity*: cint
      win_gravity*: cint
      backing_store*: cint
      backing_planes*: culong
      backing_pixel*: culong
      save_under*: cint
      event_mask*: clong
      do_not_propagate_mask*: clong
      override_redirect*: cint
      colormap*: XColormap
      cursor*: XCursor

    PXWindowAttributes* = ptr XWindowAttributesObj
    XWindowAttributesObj* = object
      x*, y*: cint
      width*, height*: cint
      border_width*: cint
      depth*: cint
      visual*: XVisual
      root*: XWindow
      class*: cint
      bit_gravity*: cint
      win_gravity*: cint
      backing_store*: cint
      backing_planes*: culong
      backing_pixel*: culong
      map_is_installed*: cint
      map_state*: cint
      all_event_masks*: clong
      your_event_mask*: clong
      do_not_propagate_mask*: clong
      override_redirect*: cint
      screen*: pointer

    PXKeyEvent* = ptr XKeyEventObj
    XKeyEventObj* = object
      eventKind*: cint
      serial*: culong
      send_event*: cint
      display*: XDisplay
      window*, root*, subwindow*: XWindow
      time*: culong
      x*, y*, x_root*, y_root*: cint
      state*: cuint
      keycode*: cuint
      same_screen*: cint

    PXButtonEvent* = ptr XButtonEventObj
    XButtonEventObj* = object
      eventKind*: cint
      serial*: culong
      send_event*: cint
      display*: XDisplay
      window*, root*, subwindow*: XWindow
      time*: culong
      x*, y*, x_root*, y_root*: cint
      state*, button*: cuint
      same_screen*: cint

    PXMotionEvent* = ptr XMotionEventObj
    XMotionEventObj* = object
      eventKind*: cint
      serial*: culong
      send_event*: cint
      display*: XDisplay
      window*, root*, subwindow*: XWindow
      time*: culong
      x*, y*, x_root*, y_root*: cint
      state*: cuint
      is_hint*: char
      same_screen*: cint

    PXConfigureEvent* = ptr XConfigureEventObj
    XConfigureEventObj* = object
      eventKind*: cint
      serial*: culong
      send_event*: cint
      display*: XDisplay
      event*, window*: XWindow
      x*, y*: cint
      width*, height*: cint
      border_width*: cint
      above*: XWindow
      override_redirect*: cint

    PXExposeEvent* = ptr XExposeEventObj
    XExposeEventObj* = object
      eventKind*: cint
      serial*: culong
      send_event*: cint
      display*: XDisplay
      window*: XWindow
      x*, y*: cint
      width*, height*: cint
      count*: cint

    XImageObj* = object
      data*: pointer
      width*, height*: cint
      xoffset*, depth*: cint
      bits_per_pixel*, bytes_per_line*: cint
      byte_order*, bitmap_unit*, bitmap_bit_order*: cint
      bitmap_pad*: cint
      red_mask*, green_mask*, blue_mask*: culong
      obdata*: pointer

    PXImage* = ptr XImageObj

    XEventObj* = object
      kind*: cint
      padding: array[96, byte]

    PXEvent* = ptr XEventObj

  # Xlib function bindings
  proc XOpenDisplay*(display_name: cstring): XDisplay
    {.importc: "XOpenDisplay", dynlib: libX11.}

  proc XCloseDisplay*(display: XDisplay): cint
    {.importc: "XCloseDisplay", dynlib: libX11.}

  proc XDefaultScreen*(display: XDisplay): cint
    {.importc: "XDefaultScreen", dynlib: libX11.}

  proc XRootWindow*(display: XDisplay, screen_number: cint): XWindow
    {.importc: "XRootWindow", dynlib: libX11.}

  proc XDefaultVisual*(display: XDisplay, screen_number: cint): XVisual
    {.importc: "XDefaultVisual", dynlib: libX11.}

  proc XDefaultDepth*(display: XDisplay, screen_number: cint): cint
    {.importc: "XDefaultDepth", dynlib: libX11.}

  proc XCreateWindow*(display: XDisplay, parent: XWindow, x, y: cint,
    width, height, border_width: cuint, depth: cint, class: cuint,
    visual: XVisual, value_mask: culong, attributes: ptr XSetWindowAttributes): XWindow
    {.importc: "XCreateWindow", dynlib: libX11.}

  proc XMapWindow*(display: XDisplay, window: XWindow): cint
    {.importc: "XMapWindow", dynlib: libX11.}

  proc XDestroyWindow*(display: XDisplay, window: XWindow): cint
    {.importc: "XDestroyWindow", dynlib: libX11.}

  proc XStoreName*(display: XDisplay, window: XWindow, name: cstring): cint
    {.importc: "XStoreName", dynlib: libX11.}

  proc XSelectInput*(display: XDisplay, window: XWindow, event_mask: clong): cint
    {.importc: "XSelectInput", dynlib: libX11.}

  proc XPending*(display: XDisplay): cint
    {.importc: "XPending", dynlib: libX11.}

  proc XNextEvent*(display: XDisplay, event_return: PXEvent): cint
    {.importc: "XNextEvent", dynlib: libX11.}

  proc XFlush*(display: XDisplay): cint
    {.importc: "XFlush", dynlib: libX11.}

  proc XDefaultGC*(display: XDisplay, screen_number: cint): pointer
    {.importc: "XDefaultGC", dynlib: libX11.}

  proc XCreateImage*(display: XDisplay, visual: XVisual, depth: cint,
    format: cint, offset: cint, data: cstring, width, height: cuint,
    bitmap_pad: cint, bytes_per_line: cint): PXImage
    {.importc: "XCreateImage", dynlib: libX11.}

  proc XDestroyImage*(image: PXImage): cint
    {.importc: "XDestroyImage", dynlib: libX11.}

  proc XPutImage*(display: XDisplay, drawable: XID, gc: pointer,
    image: PXImage, src_x, src_y, dest_x, dest_y: cint,
    width, height: cuint): cint
    {.importc: "XPutImage", dynlib: libX11.}

  proc XLookupString*(event: PXKeyEvent, buffer: cstring, nbytes: cint,
    keysym_return: ptr culong, status: pointer): cint
    {.importc: "XLookupString", dynlib: libX11.}

  # Event mask constants
  const
    ExposureMask*       = clong(1 shl 15)
    KeyPressMask*       = clong(1 shl 0)
    KeyReleaseMask*     = clong(1 shl 1)
    ButtonPressMask*    = clong(1 shl 2)
    ButtonReleaseMask*  = clong(1 shl 3)
    PointerMotionMask*  = clong(1 shl 6)
    StructureNotifyMask* = clong(1 shl 17)
    ResizeRedirectMask* = clong(1 shl 18)

  # XEvent kind constants
  const
    XKeyPress*        = 2
    XKeyRelease*      = 3
    XButtonPress*     = 4
    XButtonRelease*   = 5
    XMotionNotify*    = 6
    XExpose*          = 12
    XDestroyNotify*   = 17
    XConfigureNotify* = 22

  # X11 constants
  const
    InputOutput* = cuint(1)
    CWBackPixel* = culong(1 shl 1)
    CWBorderPixel* = culong(1 shl 3)
    CWEventMask* = culong(1 shl 11)
    CWOverrideRedirect* = culong(1 shl 9)

  # Key codes (common)
  const
    XK_Escape* = 0xff1b
    XK_Return* = 0xff0d
    XK_BackSpace* = 0xff08
    XK_Tab* = 0xff09
    XK_Up* = 0xff52
    XK_Down* = 0xff54
    XK_Left* = 0xff51
    XK_Right* = 0xff53
    XK_Home* = 0xff50
    XK_End* = 0xff57
    XK_Delete* = 0xffff
    XK_Shift_L* = 0xffe1
    XK_Control_L* = 0xffe3

  proc lookupString*(ev: PXKeyEvent): string =
    var buf: array[32, char]
    var keysym: culong = 0
    discard XLookupString(ev, cast[cstring](buf[0].addr), 32, addr keysym, nil)
    result = ""
    for i in 0 ..< buf.len:
      if buf[i] == char(0): break
      result.add(buf[i])

  proc getKeySym*(ev: PXKeyEvent): culong =
    var ks: culong = 0
    discard XLookupString(ev, nil, 0, addr ks, nil)
    ks

  # X11 PlatformWindow type
  type
    PlatformWindow* = ref object
      display*: XDisplay
      window*: XWindow
      width*, height*: int
      xImage*: PXImage
      pixels*: seq[uint32]

  proc newPlatformWindow*(title: string, width, height: int): PlatformWindow =
    let display = XOpenDisplay(nil)
    if display == nil:
      raise newException(IOError, "Cannot open X11 display")

    let screen = XDefaultScreen(display)
    let rootWin = XRootWindow(display, screen)
    let visual = XDefaultVisual(display, screen)
    let depth = XDefaultDepth(display, screen)

    var attrs: XSetWindowAttributes
    attrs.background_pixel = 0x1e222a'u32
    attrs.border_pixel = 0x282c34'u32
    attrs.event_mask = ExposureMask or KeyPressMask or KeyReleaseMask or
      ButtonPressMask or ButtonReleaseMask or PointerMotionMask or
      StructureNotifyMask or ResizeRedirectMask

    let win = XCreateWindow(display, rootWin, 0, 0,
      width.cuint, height.cuint, 0, depth, InputOutput, visual,
      CWBackPixel or CWBorderPixel or CWEventMask, addr attrs)

    discard XStoreName(display, win, title.cstring)
    discard XMapWindow(display, win)
    discard XFlush(display)

    result = PlatformWindow(
      display: display,
      window: win,
      width: width,
      height: height,
      pixels: newSeq[uint32](width * height)
    )

    result.xImage = XCreateImage(display, visual, 24, 2, 0,
      cast[cstring](result.pixels[0].addr),
      width.cuint, height.cuint, 32, (width * 4).cint)

  proc close*(win: PlatformWindow) =
    if win.xImage != nil:
      win.xImage.data = nil
      discard XDestroyImage(win.xImage)
      win.xImage = nil
    if win.window != 0:
      discard XDestroyWindow(win.display, win.window)
      win.window = 0
    if win.display != nil:
      discard XCloseDisplay(win.display)
      win.display = nil

  proc flush*(win: PlatformWindow) =
    if win.xImage != nil:
      discard XPutImage(win.display, win.window,
        XDefaultGC(win.display, XDefaultScreen(win.display)),
        win.xImage, 0, 0, 0, 0, win.width.cuint, win.height.cuint)
    discard XFlush(win.display)

  proc resize*(win: PlatformWindow, width, height: int) =
    if width == win.width and height == win.height:
      return
    win.width = width
    win.height = height
    win.pixels.setLen(width * height)
    if win.xImage != nil:
      win.xImage.data = nil
      discard XDestroyImage(win.xImage)
    let visual = XDefaultVisual(win.display, XDefaultScreen(win.display))
    win.xImage = XCreateImage(win.display, visual, 24, 2, 0,
      cast[cstring](win.pixels[0].addr),
      width.cuint, height.cuint, 32, (width * 4).cint)

  proc pollEvent*(win: PlatformWindow): GuiEvent =
    result = GuiEvent(kind: geNone)

    while XPending(win.display) > 0:
      var ev: XEventObj
      discard XNextEvent(win.display, addr ev)

      case ev.kind
      of XKeyPress:
        var xev: XKeyEventObj
        copyMem(addr xev, addr ev, sizeof(XKeyEventObj))
        let ks = getKeySym(addr xev)
        let ksStr = lookupString(addr xev)
        result = GuiEvent(kind: geKeyPress, keySym: ks, keyString: ksStr)
        return
      of XKeyRelease:
        var xev: XKeyEventObj
        copyMem(addr xev, addr ev, sizeof(XKeyEventObj))
        result = GuiEvent(
          kind: geKeyRelease,
          keySym: getKeySym(addr xev),
          keyString: lookupString(addr xev)
        )
        return
      of XButtonPress:
        var xev: XButtonEventObj
        copyMem(addr xev, addr ev, sizeof(XButtonEventObj))
        result = GuiEvent(
          kind: geButtonPress,
          button: xev.button.int,
          mouseX: xev.x.int,
          mouseY: xev.y.int
        )
        return
      of XButtonRelease:
        var xev: XButtonEventObj
        copyMem(addr xev, addr ev, sizeof(XButtonEventObj))
        result = GuiEvent(
          kind: geButtonRelease,
          button: xev.button.int,
          mouseX: xev.x.int,
          mouseY: xev.y.int
        )
        return
      of XMotionNotify:
        var xev: XMotionEventObj
        copyMem(addr xev, addr ev, sizeof(XMotionEventObj))
        result = GuiEvent(
          kind: geMotion,
          mouseX: xev.x.int,
          mouseY: xev.y.int
        )
        return
      of XConfigureNotify:
        var xev: XConfigureEventObj
        copyMem(addr xev, addr ev, sizeof(XConfigureEventObj))
        if xev.width.int != win.width or xev.height.int != win.height:
          win.resize(xev.width.int, xev.height.int)
          result = GuiEvent(
            kind: geResize,
            width: win.width,
            height: win.height
          )
          return
      of XExpose:
        result = GuiEvent(kind: geExpose)
        return
      of XDestroyNotify:
        result = GuiEvent(kind: geQuit)
        return
      else: discard

  proc symToChar*(sym: culong): char =
    if sym >= 0x20 and sym <= 0x7e:
      result = char(sym)
    else:
      result = char(0)
