## =============================================================================
## nimact/core/platform_wayland.nim
## Wayland プラットフォーム抽象化レイヤー
##
## Wayland クライアントプロトコルを直接 FFI で使い、
## ウィンドウ作成・イベント処理・ピクセル描画を担当
## X11 プラットフォームモジュールの代替実装
## =============================================================================

const
  libWaylandClient* = "libwayland-client.so.0"
  libWaylandCursor* = "libwayland-cursor.so.0"
  libWlEgl* = "libwayland-egl.so.1"

# =============================================================================
# Wayland 基本型
# =============================================================================

type
  WlDisplay* = pointer
  WlRegistry* = pointer
  WlRegistryListener* = object
  WlCompositor* = pointer
  WlSurface* = pointer
  WlShm* = pointer
  WlShmPool* = pointer
  WlBuffer* = pointer
  WlOutput* = pointer
  WlOutputListener* = object
  WlSeat* = pointer
  WlSeatListener* = object
  WlPointer* = pointer
  WlPointerListener* = object
  WlKeyboard* = pointer
  WlKeyboardListener* = object
  WlCallback* = pointer
  WlCallbackListener* = object
  WlXdgWmBase* = pointer
  WlXdgWmBaseListener* = object
  WlXdgSurface* = pointer
  WlXdgSurfaceListener* = object
  WlXdgToplevel* = pointer
  WlXdgToplevelListener* = object

  WlFixed* = cint32  # actually int31.1 fixed-point

# =============================================================================
# Wayland C API 関数バインディング
# =============================================================================

proc wlDisplayConnect*(name: cstring): WlDisplay
  {.importc: "wl_display_connect", dynlib: libWaylandClient.}

proc wlDisplayDisconnect*(display: WlDisplay)
  {.importc: "wl_display_disconnect", dynlib: libWaylandClient.}

proc wlDisplayGetFd*(display: WlDisplay): cint
  {.importc: "wl_display_get_fd", dynlib: libWaylandClient.}

proc wlDisplayRoundtrip*(display: WlDisplay): cint
  {.importc: "wl_display_roundtrip", dynlib: libWaylandClient.}

proc wlDisplayDispatch*(display: WlDisplay): cint
  {.importc: "wl_display_dispatch", dynlib: libWaylandClient.}

proc wlDisplayDispatchPending*(display: WlDisplay): cint
  {.importc: "wl_display_dispatch_pending", dynlib: libWaylandClient.}

proc wlDisplayFlush*(display: WlDisplay): cint
  {.importc: "wl_display_flush", dynlib: libWaylandClient.}

proc wlRegistryGet*(display: WlDisplay, interface: cstring,
                    version: cuint, id: cuint): WlRegistry
  {.importc: "wl_display_create_queue", dynlib: libWaylandClient.}

proc wlRegistryBind*(registry: WlRegistry, name: cuint,
                     interfacePtr: pointer, version: cuint, id: cuint): pointer
  {.importc: "wl_registry_bind", dynlib: libWaylandClient.}

proc wlShmCreatePool*(shm: WlShm, fd: cint, size: cint): WlShmPool
  {.importc: "wl_shm_create_pool", dynlib: libWaylandClient.}

proc wlShmPoolCreateBuffer*(pool: WlShmPool, offset: cint,
                            width, height, stride: cint,
                            format: cuint): WlBuffer
  {.importc: "wl_shm_pool_create_buffer", dynlib: libWaylandClient.}

proc wlShmPoolDestroy*(pool: WlShmPool)
  {.importc: "wl_shm_pool_destroy", dynlib: libWaylandClient.}

proc wlSurfaceAttach*(surface: WlSurface, buffer: WlBuffer,
                      x, y: cint): cint
  {.importc: "wl_surface_attach", dynlib: libWaylandClient.}

proc wlSurfaceDamageBuffer*(surface: WlSurface, x, y, width, height: cint)
  {.importc: "wl_surface_damage_buffer", dynlib: libWaylandClient.}

proc wlSurfaceCommit*(surface: WlSurface)
  {.importc: "wl_surface_commit", dynlib: libWaylandClient.}

proc wlSurfaceDestroy*(surface: WlSurface)
  {.importc: "wl_surface_destroy", dynlib: libWaylandClient.}

proc wlCompositorCreateSurface*(compositor: WlCompositor): WlSurface
  {.importc: "wl_compositor_create_surface", dynlib: libWaylandClient.}

proc wlCallbackAddListener*(callback: WlCallback,
                            listener: ptr WlCallbackListener,
                            data: pointer): cint
  {.importc: "wl_callback_add_listener", dynlib: libWaylandClient.}

proc wlPointerAddListener*(pointer: WlPointer,
                           listener: ptr WlPointerListener,
                           data: pointer): cint
  {.importc: "wl_pointer_add_listener", dynlib: libWaylandClient.}

proc wlKeyboardAddListener*(keyboard: WlKeyboard,
                            listener: ptr WlKeyboardListener,
                            data: pointer): cint
  {.importc: "wl_keyboard_add_listener", dynlib: libWaylandClient.}

proc wlSeatAddListener*(seat: WlSeat,
                        listener: ptr WlSeatListener,
                        data: pointer): cint
  {.importc: "wl_seat_add_listener", dynlib: libWaylandClient.}

proc wlOutputAddListener*(output: WlOutput,
                          listener: ptr WlOutputListener,
                          data: pointer): cint
  {.importc: "wl_output_add_listener", dynlib: libWaylandClient.}

# xdg-shell
proc xdgWmBaseGetSurface*(wmBase: WlXdgWmBase, surface: WlSurface): WlXdgSurface
  {.importc: "xdg_wm_base_get_xdg_surface", dynlib: libWaylandClient.}

proc xdgSurfaceGetToplevel*(xdgSurface: WlXdgSurface): WlXdgToplevel
  {.importc: "xdg_surface_get_toplevel", dynlib: libWaylandClient.}

proc xdgToplevelSetTitle*(toplevel: WlXdgToplevel, title: cstring)
  {.importc: "xdg_toplevel_set_title", dynlib: libWaylandClient.}

proc xdgToplevelSetAppID*(toplevel: WlXdgToplevel, appId: cstring)
  {.importc: "xdg_toplevel_set_app_id", dynlib: libWaylandClient.}

proc xdgToplevelAddListener*(toplevel: WlXdgToplevel,
                             listener: ptr WlXdgToplevelListener,
                             data: pointer): cint
  {.importc: "xdg_toplevel_add_listener", dynlib: libWaylandClient.}

proc xdgSurfaceAddListener*(xdgSurface: WlXdgSurface,
                            listener: ptr WlXdgSurfaceListener,
                            data: pointer): cint
  {.importc: "xdg_surface_add_listener", dynlib: libWaylandClient.}

proc xdgWmBaseAddListener*(wmBase: WlXdgWmBase,
                           listener: ptr WlXdgWmBaseListener,
                           data: pointer): cint
  {.importc: "xdg_wm_base_add_listener", dynlib: libWaylandClient.}

# Linux SHM format constants
const
  WL_SHM_FORMAT_ARGB32* = cuint(0)
  WL_SHM_FORMAT_XRGB32* = cuint(1)

# xdg-shellstable v1 protocol version
const XDG_SHELL_VERSION = 5

# Wayland interface structs (for wl_registry_bind)
type
  WlInterface* = object
    name*: cstring
    version*: cint
    implem:* pointer

# Get interface from registry
proc wlRegistryGetWlCompositor*(registry: WlRegistry, name: cuint): WlCompositor
proc wlRegistryGetWlShm*(registry: WlRegistry, name: cuint): WlShm
proc wlRegistryGetWlSeat*(registry: WlRegistry, name: cuint): WlSeat
proc wlRegistryGetWlOutput*(registry: WlRegistry, name: cuint): WlOutput
proc wlRegistryGetXdgWmBase*(registry: WlRegistry, name: cuint): WlXdgWmBase

# =============================================================================
# Wayland event listener structs
# =============================================================================

type
  WaylandAppState* = object
    wmBase*: WlXdgWmBase
    surface*: WlSurface
    buffer*: WlBuffer
    pool*: WlShmPool
    shm*: WlShm
    seat*: WlSeat
    pointer*: WlPointer
    keyboard*: WlKeyboard
    output*: WlOutput
    display*: WlDisplay
    registry*: WlRegistry
    width*: int
    height*: int
    pixels*: seq[uint32]
    closed*: bool
    fd*: cint

  PlatformWindow* = ref object
    waylandState*: WaylandAppState
    display*: WlDisplay
    window*: WlSurface
    width*, height*: int
    pixels*: seq[uint32]
    shmFd*: cint
    shmSize*: cint

# Wayland interface names
const
  WL_COMPOSITOR_NAME* = "wl_compositor"
  WL_SHM_NAME* = "wl_shm"
  WL_SEAT_NAME* = "wl_seat"
  WL_OUTPUT_NAME* = "wl_output"
  XDG_WM_BASE_NAME* = "xdg_wm_base"
