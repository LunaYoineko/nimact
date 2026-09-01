/* =============================================================================
 * wayland_shim.c
 * Simple Wayland client wrapper for software rendering using wl_shm
 * =============================================================================*/

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include "xdg-shell-client.h"

/* Callback type for Nim */
typedef void (*event_callback)(int event_type, int arg1, int arg2, const char *key_str);

/* Event types matching GuiEventKind */
#define EVT_NONE        0
#define EVT_QUIT        1
#define EVT_KEY_PRESS   2
#define EVT_KEY_RELEASE 3
#define EVT_MOTION      4
#define EVT_BUTTON_PRESS   5
#define EVT_BUTTON_RELEASE 6
#define EVT_RESIZE      7
#define EVT_EXPOSE      8
#define EVT_FRAME       100

/* Global state */
static struct wl_display *display = NULL;
static struct wl_compositor *compositor = NULL;
static struct wl_surface *surface = NULL;
static struct xdg_wm_base *wm_base = NULL;
static struct xdg_surface *xdg_surface = NULL;
static struct xdg_toplevel *toplevel = NULL;
static struct wl_shm *shm = NULL;
static struct wl_shm_pool *pool = NULL;
static struct wl_buffer *buffer = NULL;
static struct wl_seat *seat = NULL;
static struct wl_pointer *pointer = NULL;
static struct wl_keyboard *keyboard = NULL;
static struct wl_callback *frame_callback = NULL;

static void *shm_data = NULL;
static int shm_fd = -1;
static size_t shm_size = 0;

static int win_width = 0;
static int win_height = 0;
static int win_closed = 0;

/* Event queue for polling */
#define MAX_EVENTS 256
typedef struct {
    int type;
    int arg1;
    int arg2;
    char key_str[32];
} EventQueueItem;

static EventQueueItem event_queue[MAX_EVENTS];
static int event_head = 0;
static int event_tail = 0;

/* Push an event to the queue */
static void push_event(int type, int arg1, int arg2, const char *key_str) {
    int next = (event_head + 1) % MAX_EVENTS;
    if (next == event_tail) return;  /* Queue full */
    event_queue[event_head].type = type;
    event_queue[event_head].arg1 = arg1;
    event_queue[event_head].arg2 = arg2;
    if (key_str) {
        strncpy(event_queue[event_head].key_str, key_str, 31);
        event_queue[event_head].key_str[31] = '\0';
    } else {
        event_queue[event_head].key_str[0] = '\0';
    }
    event_head = next;
}

/* Forward declarations */
static void pointer_motion(void *data, struct wl_pointer *pointer,
                           uint32_t time, wl_fixed_t surface_x, wl_fixed_t surface_y);
static void pointer_button(void *data, struct wl_pointer *pointer,
                           uint32_t serial, uint32_t time, uint32_t button,
                           uint32_t state);
static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
                            uint32_t format, int32_t fd, uint32_t size);
static void keyboard_key(void *data, struct wl_keyboard *keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state);
static void frame_callback_handler(void *data, struct wl_callback *callback,
                                   uint32_t time);

/* Registry handling */
static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
    if (strcmp(interface, "wl_compositor") == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, "wl_shm") == 0) {
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    } else if (strcmp(interface, "wl_seat") == 0) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
}

static struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

/* xdg_wm_base listener */
static void xdg_wm_base_ping(void *data, struct xdg_wm_base *xdg_wm_base,
                             uint32_t serial) {
    xdg_wm_base_pong(xdg_wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

/* xdg_surface listener */
static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
                                  uint32_t serial) {
    xdg_surface_ack_configure(xdg_surface, serial);
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

/* xdg_toplevel listener */
static void xdg_toplevel_configure(void *data, struct xdg_toplevel *xdg_toplevel,
                                   int32_t width, int32_t height,
                                   struct wl_array *states) {
    if (width > 0 && height > 0) {
        win_width = width;
        win_height = height;
        push_event(EVT_RESIZE, width, height, NULL);
    }
}

static void xdg_toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel) {
    win_closed = 1;
    push_event(EVT_QUIT, 0, 0, NULL);
}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = xdg_toplevel_configure,
    .close = xdg_toplevel_close,
};

/* Pointer listener */
static void pointer_motion(void *data, struct wl_pointer *pointer,
                           uint32_t time, wl_fixed_t surface_x, wl_fixed_t surface_y) {
    push_event(EVT_MOTION, wl_fixed_to_int(surface_x), wl_fixed_to_int(surface_y), NULL);
}

static void pointer_button(void *data, struct wl_pointer *pointer,
                           uint32_t serial, uint32_t time, uint32_t button,
                           uint32_t state) {
    push_event(state ? EVT_BUTTON_PRESS : EVT_BUTTON_RELEASE, button, 0, NULL);
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = NULL,
    .leave = NULL,
    .motion = pointer_motion,
    .button = pointer_button,
    .axis = NULL,
    .axis_source = NULL,
    .axis_stop = NULL,
    .frame = NULL
};

/* Keyboard listener */
static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
                            uint32_t format, int32_t fd, uint32_t size) {
    close(fd);
}

static void keyboard_key(void *data, struct wl_keyboard *keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state) {
    if (state != 1) return;
    uint32_t keysym = 0;
    const char *keystr = NULL;

    switch (key) {
        case 1:   /* Escape */
            keysym = 0xff1b;
            keystr = "\x1b";
            break;
        case 28:  /* Return */
            keysym = 0xff0d;
            keystr = "\r";
            break;
        case 29:  /* Left Ctrl */
            keysym = 0xffe3;
            break;
        case 42:  /* Left Shift */
            keysym = 0xffe1;
            break;
        case 16:  /* Q - uppercase */
            keysym = 0x51;
            keystr = "Q";
            break;
        case 44:  /* A - lowercase */
            keysym = 0x61;
            keystr = "a";
            break;
    }

    if (keysym != 0) {
        push_event(EVT_KEY_PRESS, keysym, 0, keystr);
    }
}

static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = keyboard_keymap,
    .enter = NULL,
    .leave = NULL,
    .key = keyboard_key,
    .modifiers = NULL,
    .repeat_info = NULL
};

/* Seat capabilities listener */
static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t caps) {
    if (caps & WL_SEAT_CAPABILITY_POINTER) {
        if (!pointer) {
            pointer = wl_seat_get_pointer(wl_seat);
            wl_pointer_add_listener(pointer, &pointer_listener, NULL);
        }
    } else {
        if (pointer) {
            wl_pointer_release(pointer);
            pointer = NULL;
        }
    }

    if (caps & WL_SEAT_CAPABILITY_KEYBOARD) {
        if (!keyboard) {
            keyboard = wl_seat_get_keyboard(wl_seat);
            wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
        }
    } else {
        if (keyboard) {
            wl_keyboard_release(keyboard);
            keyboard = NULL;
        }
    }
}

static void seat_name(void *data, struct wl_seat *wl_seat,
                      const char *name) {
}

static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

/* Frame callback for vsync */
static void frame_callback_handler(void *data, struct wl_callback *callback,
                                   uint32_t time) {
    if (callback == frame_callback) {
        wl_callback_destroy(frame_callback);
        frame_callback = NULL;
    }
    push_event(EVT_FRAME, time, 0, NULL);
    /* Queue next frame */
    if (surface) {
        frame_callback = wl_surface_frame(surface);
        wl_callback_add_listener(frame_callback, &(struct wl_callback_listener){
            .done = frame_callback_handler
        }, NULL);
    }
}

/* Create anonymous file for SHM */
static int create_shm_file(size_t size) {
    int fd = memfd_create("nimact_buffer", 0);
    if (fd < 0) {
        fd = shm_open("/nimact_buffer", O_CREAT | O_RDWR, 0600);
    }
    if (fd < 0) return -1;
    if (ftruncate(fd, size) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/* =============================================================================
 * Public API
 * =============================================================================*/

void *wl_init_window(const char *title, int width, int height, event_callback cb) {
    (void)cb; /* We use internal event queue instead of callback */

    /* Connect to Wayland display */
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "wayland_shim: Failed to connect to Wayland display\n");
        return NULL;
    }

    win_width = width;
    win_height = height;

    /* Get registry */
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor) {
        fprintf(stderr, "wayland_shim: No compositor\n");
        return NULL;
    }

    /* Create surface */
    surface = wl_compositor_create_surface(compositor);
    if (!surface) {
        fprintf(stderr, "wayland_shim: Cannot create surface\n");
        return NULL;
    }

    /* Set up xdg_wm_base */
    if (wm_base) {
        xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);

        xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
        xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);

        toplevel = xdg_surface_get_toplevel(xdg_surface);
        xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
        xdg_toplevel_set_title(toplevel, title);
        xdg_toplevel_set_app_id(toplevel, "nimact-gui");

        /* Set geometry and commit */
        xdg_surface_set_window_geometry(xdg_surface, 0, 0, width, height);
        wl_surface_commit(surface);
    }

    /* Set up SHM */
    if (shm) {
        shm_size = width * height * 4;  /* ARGB8888 */
        shm_fd = create_shm_file(shm_size);
        if (shm_fd >= 0) {
            shm_data = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
            if (shm_data == MAP_FAILED) {
                close(shm_fd);
                shm_fd = -1;
            } else {
                pool = wl_shm_create_pool(shm, shm_fd, (int32_t)shm_size);
                buffer = wl_shm_pool_create_buffer(pool, 0, width, height,
                                                    width * 4, WL_SHM_FORMAT_ARGB8888);
            }
        }
    }

    /* Set up seat */
    if (seat) {
        wl_seat_add_listener(seat, &seat_listener, NULL);
        /* Force capabilities check */
        wl_display_roundtrip(display);
    }

    /* Start frame callback for smooth rendering */
    if (surface) {
        frame_callback = wl_surface_frame(surface);
        wl_callback_add_listener(frame_callback, &(struct wl_callback_listener){
            .done = frame_callback_handler
        }, NULL);
    }

    /* Initial flush */
    wl_display_flush(display);

    return surface;
}

void wl_close_window(void *win) {
    (void)win;
    if (frame_callback) {
        wl_callback_destroy(frame_callback);
        frame_callback = NULL;
    }
    if (buffer) {
        wl_buffer_destroy(buffer);
        buffer = NULL;
    }
    if (pool) {
        wl_shm_pool_destroy(pool);
        pool = NULL;
    }
    if (shm_data && shm_data != MAP_FAILED) {
        munmap(shm_data, shm_size);
        shm_data = NULL;
    }
    if (shm_fd >= 0) {
        close(shm_fd);
        shm_fd = -1;
    }
    if (toplevel) {
        xdg_toplevel_destroy(toplevel);
        toplevel = NULL;
    }
    if (xdg_surface) {
        xdg_surface_destroy(xdg_surface);
        xdg_surface = NULL;
    }
    if (surface) {
        wl_surface_destroy(surface);
        surface = NULL;
    }
    if (keyboard) {
        wl_keyboard_release(keyboard);
        keyboard = NULL;
    }
    if (pointer) {
        wl_pointer_release(pointer);
        pointer = NULL;
    }
    if (display) {
        wl_display_disconnect(display);
        display = NULL;
    }
    compositor = NULL;
    shm = NULL;
    wm_base = NULL;
    seat = NULL;
}

int wl_poll_events(void *win) {
    (void)win;
    if (!display) return -1;

    /* Process Wayland events (which will push to our queue) */
    if (wl_display_dispatch(display) == -1) {
        if (wl_display_get_error(display) != 0) {
            fprintf(stderr, "wayland_shim: Fatal error in dispatch\n");
            return -1;
        }
    }

    return win_closed ? 1 : 0;
}

/* Pop one event from the queue
 * Returns 0 if no event available, 1 if event was retrieved
 * Event data is written to the provided pointers
 */
int wl_pop_event(int *event_type, int *arg1, int *arg2, char *key_str, int key_str_size) {
    if (event_head == event_tail) return 0;  /* No events */

    *event_type = event_queue[event_tail].type;
    *arg1 = event_queue[event_tail].arg1;
    *arg2 = event_queue[event_tail].arg2;
    if (key_str && key_str_size > 0) {
        strncpy(key_str, event_queue[event_tail].key_str, key_str_size - 1);
        key_str[key_str_size - 1] = '\0';
    }
    event_tail = (event_tail + 1) % MAX_EVENTS;
    return 1;
}

/* Check if there are pending events */
int wl_has_events(void) {
    return event_head != event_tail;
}

void *wl_get_pixels(void *win, int *width, int *height) {
    (void)win;
    *width = win_width;
    *height = win_height;
    return shm_data;
}

void wl_flush_buffer(void *win) {
    (void)win;
    if (buffer && surface) {
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_damage_buffer(surface, 0, 0, win_width, win_height);
        wl_surface_commit(surface);
    }
    wl_display_flush(display);
}

int wl_get_fd(void *win) {
    (void)win;
    return wl_display_get_fd(display);
}
