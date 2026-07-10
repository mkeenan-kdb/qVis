#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <pthread.h>
#include <unistd.h>
#include <vector>

#define KXVER 3
extern "C" {
#include "k.h"
}
#include <fcntl.h>

// ---------------------------------------------------------------------------
// Built-in 5x7 bitmap font (space, digits, upper+lowercase, a few
// punctuation). One hand-verified font, no external font files/libraries -
// if real typefaces matter later, that's an SDL_ttf upgrade.
// Each glyph is 7 rows; each row's low 5 bits are columns, MSB-first (bit4 =
// leftmost).
// ---------------------------------------------------------------------------
static const int FONT_W = 5, FONT_H = 7;
static const uint8_t FONT_GLYPHS[95][7] = {
    {0, 0, 0, 0, 0, 0, 0},        // ' '
    {4, 4, 4, 4, 4, 0, 4},        // '!'
    {10, 10, 0, 0, 0, 0, 0},      // '"'
    {10, 31, 10, 31, 10, 0, 0},   // '#'
    {4, 15, 16, 14, 1, 30, 4},    // '$'
    {17, 2, 4, 8, 16, 17, 0},     // '%'
    {12, 18, 20, 10, 21, 18, 0},  // '&'
    {4, 4, 0, 0, 0, 0, 0},        // '\''
    {2, 4, 8, 8, 8, 4, 2},        // '('
    {8, 4, 2, 2, 2, 4, 8},        // ')'
    {0, 4, 21, 14, 21, 4, 0},     // '*'
    {0, 4, 4, 31, 4, 4, 0},       // '+'
    {0, 0, 0, 0, 12, 12, 8},      // ','
    {0, 0, 0, 31, 0, 0, 0},       // '-'
    {0, 0, 0, 0, 0, 12, 12},      // '.'
    {1, 2, 4, 8, 16, 0, 0},       // '/'
    {14, 17, 19, 21, 25, 17, 14}, // '0'
    {4, 12, 4, 4, 4, 4, 14},      // '1'
    {14, 17, 1, 2, 4, 8, 31},     // '2'
    {31, 2, 4, 2, 1, 17, 14},     // '3'
    {2, 6, 10, 18, 31, 2, 2},     // '4'
    {31, 16, 30, 1, 1, 17, 14},   // '5'
    {6, 8, 16, 30, 17, 17, 14},   // '6'
    {31, 1, 2, 4, 8, 8, 8},       // '7'
    {14, 17, 17, 14, 17, 17, 14}, // '8'
    {14, 17, 17, 15, 1, 2, 12},   // '9'
    {0, 4, 4, 0, 4, 4, 0},        // ':'
    {0, 0, 4, 0, 4, 4, 8},        // ';'
    {2, 4, 8, 16, 8, 4, 2},       // '<'
    {0, 0, 31, 0, 31, 0, 0},      // '='
    {16, 8, 4, 2, 4, 8, 16},      // '>'
    {14, 17, 1, 2, 4, 0, 4},      // '?'
    {14, 17, 21, 21, 13, 1, 14},  // '@'
    {14, 17, 17, 31, 17, 17, 17}, // 'A'
    {30, 17, 17, 30, 17, 17, 30}, // 'B'
    {14, 17, 16, 16, 16, 17, 14}, // 'C'
    {28, 18, 17, 17, 17, 18, 28}, // 'D'
    {31, 16, 16, 30, 16, 16, 31}, // 'E'
    {31, 16, 16, 30, 16, 16, 16}, // 'F'
    {14, 17, 16, 23, 17, 17, 15}, // 'G'
    {17, 17, 17, 31, 17, 17, 17}, // 'H'
    {14, 4, 4, 4, 4, 4, 14},      // 'I'
    {1, 1, 1, 1, 1, 17, 14},      // 'J'
    {17, 18, 20, 24, 20, 18, 17}, // 'K'
    {16, 16, 16, 16, 16, 16, 31}, // 'L'
    {17, 27, 21, 21, 17, 17, 17}, // 'M'
    {17, 25, 21, 21, 19, 17, 17}, // 'N'
    {14, 17, 17, 17, 17, 17, 14}, // 'O'
    {30, 17, 17, 30, 16, 16, 16}, // 'P'
    {14, 17, 17, 17, 21, 18, 13}, // 'Q'
    {30, 17, 17, 30, 20, 18, 17}, // 'R'
    {15, 16, 16, 14, 1, 1, 30},   // 'S'
    {31, 4, 4, 4, 4, 4, 4},       // 'T'
    {17, 17, 17, 17, 17, 17, 14}, // 'U'
    {17, 17, 17, 17, 17, 10, 4},  // 'V'
    {17, 17, 17, 21, 21, 21, 10}, // 'W'
    {17, 17, 10, 4, 10, 17, 17},  // 'X'
    {17, 17, 10, 4, 4, 4, 4},     // 'Y'
    {31, 1, 2, 4, 8, 16, 31},     // 'Z'
    {14, 8, 8, 8, 8, 8, 14},      // '['
    {16, 8, 4, 2, 1, 0, 0},       // '\\'
    {14, 2, 2, 2, 2, 2, 14},      // ']'
    {4, 10, 17, 0, 0, 0, 0},      // '^'
    {0, 0, 0, 0, 0, 0, 31},       // '_'
    {8, 4, 0, 0, 0, 0, 0},        // '`'
    {0, 0, 14, 1, 15, 17, 15},    // 'a'
    {16, 16, 30, 17, 17, 17, 30}, // 'b'
    {0, 0, 14, 16, 16, 17, 14},   // 'c'
    {1, 1, 15, 17, 17, 17, 15},   // 'd'
    {0, 0, 14, 17, 31, 16, 14},   // 'e'
    {6, 9, 8, 28, 8, 8, 8},       // 'f'
    {0, 0, 15, 17, 15, 1, 14},    // 'g'
    {16, 16, 22, 25, 17, 17, 17}, // 'h'
    {4, 0, 12, 4, 4, 4, 14},      // 'i'
    {2, 0, 6, 2, 2, 18, 12},      // 'j'
    {16, 16, 18, 20, 24, 20, 18}, // 'k'
    {12, 4, 4, 4, 4, 4, 14},      // 'l'
    {0, 0, 26, 21, 21, 21, 21},   // 'm'
    {0, 0, 22, 25, 17, 17, 17},   // 'n'
    {0, 0, 14, 17, 17, 17, 14},   // 'o'
    {0, 0, 30, 17, 30, 16, 16},   // 'p'
    {0, 0, 15, 17, 15, 1, 1},     // 'q'
    {0, 0, 22, 25, 16, 16, 16},   // 'r'
    {0, 0, 14, 16, 14, 1, 30},    // 's'
    {8, 8, 28, 8, 8, 9, 6},       // 't'
    {0, 0, 17, 17, 17, 19, 13},   // 'u'
    {0, 0, 17, 17, 17, 10, 4},    // 'v'
    {0, 0, 17, 17, 21, 21, 10},   // 'w'
    {0, 0, 17, 10, 4, 10, 17},    // 'x'
    {0, 0, 17, 17, 15, 1, 14},    // 'y'
    {0, 0, 31, 2, 4, 8, 31},      // 'z'
    {2, 4, 4, 8, 4, 4, 2},        // '{'
    {4, 4, 4, 4, 4, 4, 4},        // '|'
    {8, 4, 4, 2, 4, 4, 8},        // '}'
    {0, 13, 18, 0, 0, 0, 0},      // '~'
};

static const uint8_t *glyph_for(char ch) {
  if (ch >= 32 && ch <= 126)
    return FONT_GLYPHS[ch - 32];
  return FONT_GLYPHS[0]; // unsupported character -> blank (space)
}

// ---------------------------------------------------------------------------
// Global state
// All SDL calls happen on the main (q) thread.
// A background timer thread writes to a pipe every ~16 ms to wake q's
// select-loop so SDL events (resize, quit, etc.) stay responsive without
// blocking the q REPL.
// ---------------------------------------------------------------------------
static SDL_Window *g_window = nullptr;
static SDL_Renderer *g_renderer = nullptr;
static SDL_Texture *g_texture = nullptr;

static int g_width = 0;
static int g_height = 0;
static int g_scale = 1;

// Single pixel buffer – q draws here, present[] uploads it to the GPU.
static std::vector<uint32_t> g_pixels;
static std::vector<TTF_Font *> g_fonts;

static int g_pipe[2] = {-1, -1};
static pthread_t g_timer_thread;
static std::atomic<bool> g_running{false};

// Input state accumulated by the event pump (main thread only - the sd1
// callback and all q_ reads run on the q main thread, so no atomics needed).
static float g_wheel = 0;     // scroll wheel delta since last q_mouse read
static bool g_quit = false;   // set once the window close button is pressed
static std::string g_textbuf; // UTF-8 typed since last q_textin read

// ---------------------------------------------------------------------------
// Background timer thread: just tickles the pipe to wake sd1
// ---------------------------------------------------------------------------
static void *timer_loop(void *) {
  while (g_running) {
    char c = 'x';
    write(g_pipe[1], &c, 1);
    usleep(16000); // ~60 fps worth of event pumping
  }
  return nullptr;
}

// ---------------------------------------------------------------------------
// sd1 callback: called on the main thread whenever the pipe has data.
// Only responsible for draining the pipe and pumping SDL events.
// ---------------------------------------------------------------------------
extern "C" {

static K on_pipe_readable(I fd) {
  // Drain every byte the timer has queued up. The read end is O_NONBLOCK so
  // this loops until EAGAIN instead of stalling the q main thread when the
  // queued byte count happens to be an exact multiple of the buffer size.
  char buf[256];
  while (read(fd, buf, sizeof(buf)) > 0) {
  }

  // Pump SDL events on the main thread
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    if (event.type == SDL_EVENT_QUIT)
      g_quit = true; // surfaced to q as the `c key of q_mouse
    if (event.type == SDL_EVENT_MOUSE_WHEEL)
      g_wheel += event.wheel.y;
    if (event.type == SDL_EVENT_TEXT_INPUT)
      g_textbuf += event.text.text;
  }
  return (K)0;
}

// ---------------------------------------------------------------------------
// Pipe + timer lifecycle. start_pipe_timer / stop_pipe_timer are the only
// places that touch g_pipe / g_timer_thread, so q_init called twice in a row
// (e.g. an example left its window open and the inspector re-inits) tears the
// old pair down instead of leaking a pipe, an sd1 registration and a thread.
// ---------------------------------------------------------------------------
// returns true on success (krr's return value is null, so callers raise the
// q error themselves)
static bool start_pipe_timer(void) {
  if (pipe(g_pipe) != 0)
    return false;
  fcntl(g_pipe[0], F_SETFL, O_NONBLOCK);
  fcntl(g_pipe[1], F_SETFL, O_NONBLOCK);
  sd1(g_pipe[0], on_pipe_readable);
  g_running = true;
  pthread_create(&g_timer_thread, nullptr, timer_loop, nullptr);
  return true;
}

static void stop_pipe_timer(void) {
  if (!g_running)
    return;
  g_running = false;
  pthread_join(g_timer_thread, nullptr);
  // sd0 would also close the fd; use sd0x with f=0 and close both ends
  // ourselves exactly once to avoid a double-close.
  sd0x(g_pipe[0], 0);
  close(g_pipe[0]);
  close(g_pipe[1]);
  g_pipe[0] = g_pipe[1] = -1;
}

// ---------------------------------------------------------------------------
// q_init[w; h; s]
// ---------------------------------------------------------------------------
K q_init(K w, K h, K s) {
  if (w->t != -KI || h->t != -KI || s->t != -KI)
    return krr((S) "type");

  if (!TTF_WasInit()) {
    if (!TTF_Init()) {
      return krr((S) "TTF_Init failed");
    }
  }

  int new_w = w->i, new_h = h->i, new_s = s->i;
  if (new_w <= 0 || new_h <= 0 || new_s <= 0)
    return krr((S) "invalid dimensions");

  // Already running (init without an intervening shutdown): recycle cleanly.
  stop_pipe_timer();

  // --- Reuse a previously hidden window (after shutdown) -----------------
  if (g_window) {
    g_width = new_w * new_s;
    g_height = new_h * new_s;
    g_scale = new_s;
    g_pixels.assign(g_width * g_height, 0xFF000000u); // opaque black

    // Recreate the texture for (possibly) new dimensions
    if (g_texture) {
      SDL_DestroyTexture(g_texture);
      g_texture = nullptr;
    }
    g_texture =
        SDL_CreateTexture(g_renderer, SDL_PIXELFORMAT_ARGB8888,
                          SDL_TEXTUREACCESS_STREAMING, g_width, g_height);
    if (!g_texture)
      return krr((S) "texture creation failed");
    SDL_SetTextureScaleMode(g_texture, SDL_SCALEMODE_NEAREST);
    SDL_SetTextureBlendMode(g_texture, SDL_BLENDMODE_BLEND);

    SDL_SetWindowSize(g_window, g_width, g_height);
    SDL_SetWindowAspectRatio(g_window, (float)g_width / g_height,
                             (float)g_width / g_height);
    SDL_ShowWindow(g_window);
    SDL_RaiseWindow(g_window);
    SDL_RenderClear(g_renderer);
    SDL_RenderPresent(g_renderer);

    // Restart pipe + timer
    if (!start_pipe_timer())
      return krr((S) "pipe failed");
    SDL_StartTextInput(g_window);
    g_wheel = 0;
    g_quit = false;
    g_textbuf.clear();
    return (K)0;
  }

  // --- First-time initialisation ----------------------------------------
  g_width = new_w * new_s;
  g_height = new_h * new_s;
  g_scale = new_s;

  g_pixels.assign(g_width * g_height, 0xFF000000u); // opaque black

  // SDL must be initialised on the main thread on macOS
  if (!SDL_Init(SDL_INIT_VIDEO))
    return krr((S) "sdl init failed");

  g_window = SDL_CreateWindow("qVis", g_width, g_height,
                              SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_RESIZABLE);
  if (!g_window)
    return krr((S) "window creation failed");

  SDL_SetWindowAspectRatio(g_window, (float)g_width / g_height,
                           (float)g_width / g_height);

  g_renderer = SDL_CreateRenderer(g_window, nullptr);
  if (!g_renderer)
    return krr((S) "renderer creation failed");

  // Lock presentation to the display's refresh. Without this, q_present()
  // pushes frames the moment q's software timer fires - and that timer is
  // a cooperative, best-effort poll (not hard real-time), so frames land
  // off-cadence from the monitor and show up as intermittent jumps.
  SDL_SetRenderVSync(g_renderer, 1);

  // ARGB8888 streaming texture – we push pixel data with SDL_UpdateTexture
  g_texture = SDL_CreateTexture(g_renderer, SDL_PIXELFORMAT_ARGB8888,
                                SDL_TEXTUREACCESS_STREAMING, g_width, g_height);
  if (!g_texture)
    return krr((S) "texture creation failed");

  // Disable bilinear interpolation to make the scaled pixels crisp
  SDL_SetTextureScaleMode(g_texture, SDL_SCALEMODE_NEAREST);

  // set_pixel/q_clear always store a forced-opaque alpha byte (see below),
  // so every pixel reaching the texture is fully opaque - BLEND is safe and
  // lets q_polygon/q_rect/etc. composite translucent fills into g_pixels.
  SDL_SetTextureBlendMode(g_texture, SDL_BLENDMODE_BLEND);

  // Show an initial black frame immediately
  SDL_RenderClear(g_renderer);
  SDL_RenderPresent(g_renderer);

  // Create the pipe, register with q's event loop via sd1, start the timer
  if (!start_pipe_timer())
    return krr((S) "pipe failed");

  // Deliver SDL_EVENT_TEXT_INPUT (layout/shift-aware characters) alongside
  // raw scancode state - q_keys can't produce shifted chars like ` or {.
  SDL_StartTextInput(g_window);

  return (K)0;
}

// ---------------------------------------------------------------------------
// q_shutdown[::]
// On macOS, SDL_DestroyWindow dispatches a Cocoa [NSWindow close] event
// that requires the main run-loop to process it.  Since shutdown is called
// from kdb+'s .z.ts (which IS the main thread), the Cocoa dispatch
// deadlocks.  We therefore just hide the window and tear down the pipe/
// timer.  q_init will show + reuse the same window on the next open.
// ---------------------------------------------------------------------------
K q_shutdown(K unused) {
  fflush(stderr);
  if (!g_window)
    return (K)0;

  // Stop the timer thread, unregister and close the pipe
  stop_pipe_timer();

  // Hide the window instead of destroying it (avoids macOS deadlock)
  SDL_HideWindow(g_window);
  // Pump events so macOS's Cocoa backend actually processes the hide
  SDL_PumpEvents();
  SDL_PumpEvents();
  g_pixels.clear();
  g_wheel = 0;
  g_quit = false;
  g_textbuf.clear();

  // Close and clean up all loaded fonts
  for (auto font : g_fonts) {
    if (font) {
      TTF_CloseFont(font);
    }
  }
  g_fonts.clear();

  if (TTF_WasInit()) {
    TTF_Quit();
  }

  return (K)0;
}

// ---------------------------------------------------------------------------
// q_textin[::]
// Char vector of UTF-8 text typed since the previous call (read-and-reset).
// Fed by SDL_EVENT_TEXT_INPUT, so shift/layout/IME are handled by the OS -
// this is the right source for a text editor, unlike q_keys' scancodes.
// ---------------------------------------------------------------------------
K q_textin(K unused) {
  K r = kpn((S)g_textbuf.data(), (J)g_textbuf.size());
  g_textbuf.clear();
  return r;
}

// ---------------------------------------------------------------------------
// q_clipboard[::]
// Current system clipboard contents as a char vector ("" when empty).
// ---------------------------------------------------------------------------
K q_clipboard(K unused) {
  char *t = SDL_GetClipboardText();
  if (!t)
    return kpn((S) "", 0);
  K r = kpn((S)t, (J)strlen(t));
  SDL_free(t);
  return r;
}

// ---------------------------------------------------------------------------
// q_setclip[str]
// Replaces the system clipboard contents with the given char vector.
// ---------------------------------------------------------------------------
K q_setclip(K s) {
  if (!s || s->t != KC)
    return krr((S) "type");
  std::string t((char *)kC(s), (size_t)s->n); // NUL-terminate for SDL
  SDL_SetClipboardText(t.c_str());
  return (K)0;
}

// ---------------------------------------------------------------------------
// Drawing primitives – all write into g_pixels (the CPU-side buffer).
// Nothing is visible until q_present is called.
// ---------------------------------------------------------------------------

// Composites src's RGB onto bg's RGB with alpha weight a (0-255) and returns
// a fully-opaque 0xFF?????? pixel. Shared by set_pixel and blend_surface,
// which each decide separately what an a==0/255 edge means for their caller.
static inline uint32_t blend_rgb(uint32_t bg, uint32_t src, uint8_t a) {
  uint8_t r = (uint8_t)((((src >> 16) & 0xFF) * a + ((bg >> 16) & 0xFF) * (255 - a)) / 255);
  uint8_t g = (uint8_t)((((src >> 8) & 0xFF) * a + ((bg >> 8) & 0xFF) * (255 - a)) / 255);
  uint8_t b = (uint8_t)(((src & 0xFF) * a + (bg & 0xFF) * (255 - a)) / 255);
  return 0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

// color is 0xAARRGGBB. Colors defined without an alpha byte (the whole
// existing palette) have a==0, which we treat as "unspecified" -> fully
// opaque, so every pre-existing caller keeps drawing solid. Pass a==1-254 for
// a translucent fill, or 255 for an explicit fully-opaque draw.
static inline void set_pixel(int x, int y, uint32_t color) {
  if ((unsigned)x >= (unsigned)g_width || (unsigned)y >= (unsigned)g_height)
    return;
  uint8_t a = (uint8_t)(color >> 24);
  uint32_t &dst = g_pixels[y * g_width + x];
  dst = (a == 0 || a == 255) ? (0xFF000000u | (color & 0xFFFFFFu))
                              : blend_rgb(dst, color, a);
}

K q_clear(K color) {
  if (color->t != -KI)
    return krr((S) "type");
  // Clear always lays down a fully opaque base layer - there's nothing
  // beneath it in g_pixels to blend against, so any alpha byte is ignored.
  uint32_t c = 0xFF000000u | ((uint32_t)color->i & 0xFFFFFFu);
  std::fill(g_pixels.begin(), g_pixels.end(), c);
  return (K)0;
}

// Stamps one logical pixel as a g_scale x g_scale block of physical pixels.
static inline void stamp_pixel(int x, int y, uint32_t color) {
  for (int j = y; j < y + g_scale; ++j)
    for (int i = x; i < x + g_scale; ++i)
      set_pixel(i, j, color);
}

K q_pixel(K x, K y, K color) {
  if (x->t != -KI || y->t != -KI || color->t != -KI)
    return krr((S) "type");
  stamp_pixel(x->i * g_scale, y->i * g_scale, (uint32_t)color->i);
  return (K)0;
}

// q_getpixel[x;y] - reads back the composited RGB already sitting in
// g_pixels (no alpha byte - every stored pixel is forced fully opaque).
// Mainly for tests/tooling to verify blending without a screenshot.
K q_getpixel(K x, K y) {
  if (x->t != -KI || y->t != -KI)
    return krr((S) "type");
  int rx = x->i * g_scale, ry = y->i * g_scale;
  if ((unsigned)rx >= (unsigned)g_width || (unsigned)ry >= (unsigned)g_height)
    return krr((S) "out of bounds");
  return ki((int)(g_pixels[ry * g_width + rx] & 0xFFFFFFu));
}

K q_line(K x1, K y1, K x2, K y2, K color) {
  if (x1->t != -KI || y1->t != -KI || x2->t != -KI || y2->t != -KI ||
      color->t != -KI)
    return krr((S) "type");

  int ax = x1->i * g_scale, ay = y1->i * g_scale, bx = x2->i * g_scale, by = y2->i * g_scale;
  uint32_t c = (uint32_t)color->i;

  int dx = std::abs(bx - ax), sx = ax < bx ? 1 : -1;
  int dy = -std::abs(by - ay), sy = ay < by ? 1 : -1;
  int err = dx + dy;
  for (;;) {
    stamp_pixel(ax, ay, c);
    if (ax == bx && ay == by)
      break;
    int e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      ax += sx;
    }
    if (e2 <= dx) {
      err += dx;
      ay += sy;
    }
  }
  return (K)0;
}

K q_rect(K x, K y, K w, K h, K color) {
  if (x->t != -KI || y->t != -KI || w->t != -KI || h->t != -KI ||
      color->t != -KI)
    return krr((S) "type");

  int rx = x->i * g_scale, ry = y->i * g_scale, rw = w->i * g_scale, rh = h->i * g_scale;
  uint32_t c = (uint32_t)color->i;
  for (int j = ry; j < ry + rh; ++j)
    for (int i = rx; i < rx + rw; ++i)
      set_pixel(i, j, c);
  return (K)0;
}

K q_circle(K x, K y, K r, K color) {
  if (x->t != -KI || y->t != -KI || r->t != -KI || color->t != -KI)
    return krr((S) "type");

  int cx = x->i * g_scale, cy = y->i * g_scale, radius = r->i * g_scale;
  uint32_t c = (uint32_t)color->i;
  // Filled circle via midpoint / scanline
  for (int dy2 = -radius; dy2 <= radius; ++dy2) {
    int hw = (int)std::sqrt((double)(radius * radius - dy2 * dy2));
    for (int dx2 = -hw; dx2 <= hw; ++dx2)
      set_pixel(cx + dx2, cy + dy2, c);
  }
  return (K)0;
}

// q_polygon[xs; ys; color] - filled simple polygon via scanline fill, in the
// same logical coordinate space as the other primitives (scaled by g_scale).
// Point-in-polygon per scanline uses the standard edge-crossing test, so
// self-intersecting polygons fill by even-odd parity. This is what backs
// .qvis.polygon and inspect.q's area-under-line shading.
K q_polygon(K poly_x, K poly_y, K color) {
  if (poly_x->t != KI || poly_y->t != KI || color->t != -KI)
    return krr((S) "type");
  J n = poly_x->n;
  if (poly_y->n != n)
    return krr((S) "length - xs and ys must be the same length");
  if (n < 3)
    return (K)0;

  int *px = kI(poly_x), *py = kI(poly_y);
  uint32_t c = (uint32_t)color->i;

  int ymin = py[0], ymax = py[0];
  for (J i = 1; i < n; ++i) {
    ymin = std::min(ymin, py[i]);
    ymax = std::max(ymax, py[i]);
  }
  ymin = std::max(ymin * g_scale, 0);
  ymax = std::min(ymax * g_scale + g_scale - 1, g_height - 1);

  std::vector<int> xints;
  for (int y = ymin; y <= ymax; ++y) {
    xints.clear();
    for (J i = 0; i < n; ++i) {
      J j = (i + 1) % n;
      int y0 = py[i] * g_scale, y1 = py[j] * g_scale;
      if (y0 == y1)
        continue;
      if ((y >= y0 && y < y1) || (y >= y1 && y < y0)) {
        int x0 = px[i] * g_scale, x1 = px[j] * g_scale;
        xints.push_back(x0 + (int)std::lround((double)(y - y0) * (x1 - x0) / (y1 - y0)));
      }
    }
    std::sort(xints.begin(), xints.end());
    for (size_t k = 0; k + 1 < xints.size(); k += 2)
      for (int x = xints[k]; x < xints[k + 1]; ++x)
        set_pixel(x, y, c);
  }
  return (K)0;
}

// ---------------------------------------------------------------------------
// q_text[x; y; scale; color; str]
// Draws str (a char vector) starting at top-left (x,y) using the built-in
// 5x7 font. scale is an integer pixel multiplier (font pixel -> scale x
// scale block); 1 column of gap is left between characters.
// ---------------------------------------------------------------------------
K q_text(K x, K y, K scale, K color, K str) {
  if (x->t != -KI || y->t != -KI || scale->t != -KI || color->t != -KI ||
      str->t != KC)
    return krr((S) "type");
  if (scale->i <= 0)
    return krr((S) "invalid scale");

  int oy = y->i * g_scale, s = scale->i * g_scale;
  uint32_t c = (uint32_t)color->i;
  G *chars = kC(str);
  int cx = x->i * g_scale;
  for (J k = 0; k < str->n; ++k) {
    const uint8_t *g = glyph_for((char)chars[k]);
    for (int ry = 0; ry < FONT_H; ++ry)
      for (int rx = 0; rx < FONT_W; ++rx)
        if (g[ry] & (1 << (FONT_W - 1 - rx)))
          for (int sy = 0; sy < s; ++sy)
            for (int sx = 0; sx < s; ++sx)
              set_pixel(cx + rx * s + sx, oy + ry * s + sy, c);
    cx += (FONT_W + 1) * s;
  }
  return (K)0;
}

// ---------------------------------------------------------------------------
// q_present[::]
// Uploads g_pixels to the GPU texture and renders to the screen immediately.
// Called synchronously on the main thread so the result is visible at once.
// ---------------------------------------------------------------------------
K q_present(K unused) {
  if (!g_window)
    return krr((S) "not initialised");

  // macOS throttles presentation to occluded/minimised windows; with vsync on
  // that can block the q main thread for up to a second per frame. Nobody can
  // see the window anyway - skip, and the next tick redraws once visible.
  if (SDL_GetWindowFlags(g_window) &
      (SDL_WINDOW_MINIMIZED | SDL_WINDOW_OCCLUDED))
    return (K)0;

  SDL_UpdateTexture(g_texture, nullptr, g_pixels.data(),
                    g_width * (int)sizeof(uint32_t));

  int win_w = 0, win_h = 0;
  SDL_GetRenderOutputSize(g_renderer, &win_w, &win_h);

  float canvas_aspect = (float)g_width / g_height;
  float window_aspect = (float)win_w / win_h;

  SDL_FRect dst_rect;
  if (window_aspect > canvas_aspect) {
    // Window is wider -> Pillarbox (bars on left/right)
    dst_rect.h = (float)win_h;
    dst_rect.w = (float)win_h * canvas_aspect;
    dst_rect.x = (win_w - dst_rect.w) / 2.0f;
    dst_rect.y = 0.0f;
  } else {
    // Window is taller -> Letterbox (bars on top/bottom)
    dst_rect.w = (float)win_w;
    dst_rect.h = (float)win_w / canvas_aspect;
    dst_rect.x = 0.0f;
    dst_rect.y = (win_h - dst_rect.h) / 2.0f;
  }

  SDL_RenderClear(g_renderer);
  SDL_RenderTexture(g_renderer, g_texture, nullptr, &dst_rect);
  SDL_RenderPresent(g_renderer);
  // Pump OS events so macOS's compositor flushes the frame immediately.
  SDL_PumpEvents();
  return (K)0;
}

// ---------------------------------------------------------------------------
// q_setpixels[pixels]
// Bulk-upload an entire frame from a q int list.
// pixels - int list (type KI) of exactly width*height ARGB values.
// Much faster than calling pixel[] in a loop; lets q compute frames as
// pure vector operations and push them in a single C call.
// ---------------------------------------------------------------------------
K q_setpixels(K pixels) {
  if (!g_window)
    return krr((S) "not initialised");
  if (pixels->t != KI)
    return krr((S) "type - expected int list");
  int logical_w = g_width / g_scale;
  int logical_h = g_height / g_scale;
  if (pixels->n != (J)(logical_w * logical_h))
    return krr((S) "length - must equal width*height");

  // Bulk frame blit, same as q_clear - full-buffer callers (Mandelbrot,
  // Doom, Life, the finance heatmap...) build plain 0xRRGGBB colors with no
  // alpha byte, so force opaque rather than reading it as "0 = invisible".
  uint32_t *src = (uint32_t *)kI(pixels);
  for (int y = 0; y < logical_h; ++y) {
    for (int x = 0; x < logical_w; ++x) {
      uint32_t color = 0xFF000000u | (src[y * logical_w + x] & 0xFFFFFFu);
      for (int sy = 0; sy < g_scale; ++sy) {
        for (int sx = 0; sx < g_scale; ++sx) {
          g_pixels[(y * g_scale + sy) * g_width + (x * g_scale + sx)] = color;
        }
      }
    }
  }
  return (K)0;
}

// ---------------------------------------------------------------------------
// q_keys[::]
// Symbol list of every key currently held down on the SDL window (which must
// have focus), e.g. `w`up`left. Names are SDL scancode names lowercased with
// spaces replaced by underscores (`left_shift`). State is refreshed by the
// event pump the pipe timer already runs, so this is a cheap live snapshot -
// poll it from .z.ts for real-time input with no terminal involvement.
// ---------------------------------------------------------------------------
K q_keys(K unused) {
  if (!g_window)
    return ktn(KS, 0); // return empty list instead of error after shutdown

  int n = 0;
  const bool *held = SDL_GetKeyboardState(&n);
  K out = ktn(KS, 0);
  for (int i = 0; i < n; ++i) {
    if (!held[i])
      continue;
    const char *nm = SDL_GetScancodeName((SDL_Scancode)i);
    if (!nm || !*nm)
      continue;
    char buf[32];
    size_t j = 0;
    for (; nm[j] && j < sizeof(buf) - 1; ++j)
      buf[j] = nm[j] == ' ' ? '_' : (char)tolower((unsigned char)nm[j]);
    buf[j] = 0;
    js(&out, ss(buf));
  }
  return out;
}

// ---------------------------------------------------------------------------
// q_mouse[::]
// Returns a dictionary `x`y`l`r`w`c!
//   (x; y; left_click; right_click; wheel_delta; window_closed)
// w is the scroll accumulated since the previous call (read-and-reset);
// c goes 1 once the window close button is pressed and stays 1.
// ---------------------------------------------------------------------------
K q_mouse(K unused) {
  if (!g_window) {
    // Return zeroed dict instead of error after shutdown
    K keys = ktn(KS, 6);
    kS(keys)[0] = ss((S) "x");
    kS(keys)[1] = ss((S) "y");
    kS(keys)[2] = ss((S) "l");
    kS(keys)[3] = ss((S) "r");
    kS(keys)[4] = ss((S) "w");
    kS(keys)[5] = ss((S) "c");
    K vals = ktn(KJ, 6);
    kJ(vals)[0] = 0;
    kJ(vals)[1] = 0;
    kJ(vals)[2] = 0;
    kJ(vals)[3] = 0;
    kJ(vals)[4] = 0;
    kJ(vals)[5] = 0;
    return xD(keys, vals);
  }

  float mx, my;
  uint32_t btns = SDL_GetMouseState(&mx, &my);

  int win_w = 0, win_h = 0;
  SDL_GetWindowSize(g_window, &win_w, &win_h);

  float canvas_aspect = (float)g_width / g_height;
  float window_aspect = (float)win_w / win_h;

  SDL_FRect dst_rect;
  if (window_aspect > canvas_aspect) {
    dst_rect.h = (float)win_h;
    dst_rect.w = (float)win_h * canvas_aspect;
    dst_rect.x = (win_w - dst_rect.w) / 2.0f;
    dst_rect.y = 0.0f;
  } else {
    dst_rect.w = (float)win_w;
    dst_rect.h = (float)win_w / canvas_aspect;
    dst_rect.x = 0.0f;
    dst_rect.y = (win_h - dst_rect.h) / 2.0f;
  }

  int logical_w = g_width / g_scale;
  int logical_h = g_height / g_scale;

  float local_x = mx - dst_rect.x;
  float local_y = my - dst_rect.y;

  int lx = (int)(local_x * logical_w / dst_rect.w);
  int ly = (int)(local_y * logical_h / dst_rect.h);

  if (lx < 0) lx = 0;
  if (lx >= logical_w) lx = logical_w - 1;
  if (ly < 0) ly = 0;
  if (ly >= logical_h) ly = logical_h - 1;

  K keys = ktn(KS, 6);
  kS(keys)[0] = ss((S) "x");
  kS(keys)[1] = ss((S) "y");
  kS(keys)[2] = ss((S) "l");
  kS(keys)[3] = ss((S) "r");
  kS(keys)[4] = ss((S) "w");
  kS(keys)[5] = ss((S) "c");

  K vals = ktn(KJ, 6);
  kJ(vals)[0] = (J)lx;
  kJ(vals)[1] = (J)ly;
  kJ(vals)[2] = (btns & SDL_BUTTON_LMASK) ? 1 : 0;
  kJ(vals)[3] = (btns & SDL_BUTTON_RMASK) ? 1 : 0;
  kJ(vals)[4] = (J)lroundf(g_wheel);
  kJ(vals)[5] = g_quit ? 1 : 0;
  g_wheel = 0;

  return xD(keys, vals);
}

static void blend_surface(SDL_Surface *src, int dst_x, int dst_y) {
  if (!src)
    return;

  SDL_Surface *converted = SDL_ConvertSurface(src, SDL_PIXELFORMAT_ARGB8888);
  if (!converted)
    return;

  uint32_t *src_pixels = (uint32_t *)converted->pixels;
  int src_w = converted->w;
  int src_h = converted->h;

  for (int y = 0; y < src_h; ++y) {
    int target_y = dst_y + y;
    if (target_y < 0 || target_y >= g_height)
      continue;

    for (int x = 0; x < src_w; ++x) {
      int target_x = dst_x + x;
      if (target_x < 0 || target_x >= g_width)
        continue;

      uint32_t src_color = src_pixels[y * src_w + x];
      uint8_t a = (src_color >> 24) & 0xFF;
      // Unlike set_pixel, a==0 here means the glyph rasterizer left this
      // pixel fully transparent (background/anti-aliasing edge) - skip it
      // rather than treating it as an opaque draw.
      if (a == 0)
        continue;

      uint32_t &dst = g_pixels[target_y * g_width + target_x];
      dst = (a == 255) ? src_color : blend_rgb(dst, src_color, a);
    }
  }
  SDL_DestroySurface(converted);
}

K q_load_font(K path, K pt_size) {
  if (path->t != KC || pt_size->t != -KI)
    return krr((S) "type");

  std::string font_path((char *)kC(path), path->n);
  int size = pt_size->i;

  if (!TTF_WasInit()) {
    if (!TTF_Init()) {
      return krr((S) "TTF_Init failed");
    }
  }

  TTF_Font *font = TTF_OpenFont(font_path.c_str(), (float)(size * g_scale));
  if (!font) {
    return krr((S) "failed to open font");
  }

  g_fonts.push_back(font);
  return ki((int)g_fonts.size() - 1);
}

K q_draw_text(K x, K y, K font_id, K color, K str) {
  if (x->t != -KI || y->t != -KI || font_id->t != -KI || color->t != -KI ||
      str->t != KC)
    return krr((S) "type");

  int font_idx = font_id->i;
  if (font_idx < 0 || font_idx >= (int)g_fonts.size() || !g_fonts[font_idx])
    return krr((S) "invalid font id");

  std::string text((char *)kC(str), str->n);
  if (text.empty())
    return (K)0;

  TTF_Font *font = g_fonts[font_idx];
  uint32_t c = (uint32_t)color->i;

  SDL_Color sdl_color;
  sdl_color.r = (c >> 16) & 0xFF;
  sdl_color.g = (c >> 8) & 0xFF;
  sdl_color.b = c & 0xFF;
  sdl_color.a = 255;

  SDL_Surface *surf =
      TTF_RenderText_Blended(font, text.c_str(), text.length(), sdl_color);
  if (!surf)
    return (K)0;

  blend_surface(surf, x->i * g_scale, y->i * g_scale);
  SDL_DestroySurface(surf);

  return (K)0;
}

K q_text_size(K font_id, K str) {
  if (font_id->t != -KI || str->t != KC)
    return krr((S) "type");

  int font_idx = font_id->i;
  if (font_idx < 0 || font_idx >= (int)g_fonts.size() || !g_fonts[font_idx])
    return krr((S) "invalid font id");

  std::string text((char *)kC(str), str->n);
  TTF_Font *font = g_fonts[font_idx];

  int w = 0, h = 0;
  if (!TTF_GetStringSize(font, text.c_str(), text.length(), &w, &h)) {
    return krr((S) "TTF_GetStringSize failed");
  }

  K r = ktn(KI, 2);
  kI(r)[0] = w / g_scale;
  kI(r)[1] = h / g_scale;
  return r;
}

// q_text_ink_box[font_id; str] -> (offsetX; offsetY; width; height)
// TTF_GetStringSize (q_text_size) reports the font's full line metrics
// (ascent+descent+leading), which is usually taller than the pixels a given
// string actually inks - e.g. a string with no descenders like "DVD" leaves
// dead descender space below the glyphs. This renders the string exactly as
// drawtext[] does and scans the alpha channel for the tight bounding box of
// non-transparent pixels, so callers doing pixel-accurate collision (like
// bouncing text off a window edge) can use the real visible extent instead.
// offsetX/offsetY are relative to the (x,y) anchor passed to drawtext[].
K q_text_ink_box(K font_id, K str) {
  if (font_id->t != -KI || str->t != KC)
    return krr((S) "type");

  int font_idx = font_id->i;
  if (font_idx < 0 || font_idx >= (int)g_fonts.size() || !g_fonts[font_idx])
    return krr((S) "invalid font id");

  std::string text((char *)kC(str), str->n);
  TTF_Font *font = g_fonts[font_idx];

  int minX = 0, minY = 0, w = 0, h = 0;
  if (!text.empty()) {
    SDL_Color white = {255, 255, 255, 255};
    SDL_Surface *surf =
        TTF_RenderText_Blended(font, text.c_str(), text.length(), white);
    if (!surf)
      return krr((S) "TTF_RenderText_Blended failed");

    SDL_Surface *converted = SDL_ConvertSurface(surf, SDL_PIXELFORMAT_ARGB8888);
    SDL_DestroySurface(surf);
    if (!converted)
      return krr((S) "surface conversion failed");

    uint32_t *pixels = (uint32_t *)converted->pixels;
    int sw = converted->w, sh = converted->h;
    int maxX = -1, maxY = -1;
    minX = sw;
    minY = sh;
    for (int y = 0; y < sh; ++y) {
      for (int x = 0; x < sw; ++x) {
        if ((pixels[y * sw + x] >> 24) & 0xFF) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    SDL_DestroySurface(converted);

    if (maxX >= minX) {
      w = maxX - minX + 1;
      h = maxY - minY + 1;
    } else {
      // fully transparent render (e.g. an all-space string) - no ink
      minX = 0;
      minY = 0;
    }
  }

  K r = ktn(KI, 4);
  kI(r)[0] = minX / g_scale;
  kI(r)[1] = minY / g_scale;
  kI(r)[2] = w / g_scale;
  kI(r)[3] = h / g_scale;
  return r;
}

K q_display_size(K unused) {
  SDL_Init(SDL_INIT_VIDEO);
  SDL_DisplayID primaryDisplay = SDL_GetPrimaryDisplay();
  SDL_Rect bounds = {0, 0, 800, 600}; // fallback
  if (primaryDisplay != 0) {
    SDL_GetDisplayUsableBounds(primaryDisplay, &bounds);
  }
  K keys = ktn(KS, 2);
  kS(keys)[0] = ss((S)"w");
  kS(keys)[1] = ss((S)"h");
  K vals = ktn(KI, 2);
  kI(vals)[0] = bounds.w;
  kI(vals)[1] = bounds.h;
  return xD(keys, vals);
}

} // extern "C"
