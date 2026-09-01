#ifndef WAYLAND_SHIM_H
#define WAYLAND_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*event_callback)(int event_type, int arg1, int arg2, const char *key_str);

/* Event types */
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

/* Initialize a Wayland window
 * Returns window handle (wl_surface*) or NULL on failure
 * cb: unused callback (events are queued internally)
 */
void *wl_init_window(const char *title, int width, int height, event_callback cb);

/* Close the window and clean up */
void wl_close_window(void *win);

/* Poll for events. Returns: 0=continue, 1=window closed, -1=error */
int wl_poll_events(void *win);

/* Pop one event from the queue. Returns 0 if no event, 1 if retrieved */
int wl_pop_event(int *event_type, int *arg1, int *arg2, char *key_str, int key_str_size);

/* Check if there are pending events */
int wl_has_events(void);

/* Get pointer to the pixel buffer */
void *wl_get_pixels(void *win, int *width, int *height);

/* Flush the pixel buffer to the Wayland surface */
void wl_flush_buffer(void *win);

/* Get the Wayland display file descriptor */
int wl_get_fd(void *win);

#ifdef __cplusplus
}
#endif

#endif
