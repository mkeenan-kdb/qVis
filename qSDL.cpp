#include <SDL3/SDL.h>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <pthread.h>
#include <unistd.h>
#include <vector>

#define KXVER 3
extern "C" {
#include "k.h"
}

// ---------------------------------------------------------------------------
// Built-in 5x7 bitmap font (space, digits, uppercase, a few punctuation).
// One hand-verified font, no external font files/libraries - if real
// typefaces or lowercase glyphs matter later, that's an SDL_ttf upgrade.
// Each glyph is 7 rows; each row's low 5 bits are columns, MSB-first (bit4 =
// leftmost).
// ---------------------------------------------------------------------------
static const int FONT_W = 5, FONT_H = 7;
static const char FONT_CHARS[] = " !',-.0123456789:?ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static const uint8_t FONT_GLYPHS[][7] = {
    {0, 0, 0, 0, 0, 0, 0},        // ' '
    {4, 4, 4, 4, 4, 0, 4},        // '!'
    {4, 4, 0, 0, 0, 0, 0},        // '''
    {0, 0, 0, 0, 12, 12, 8},      // ','
    {0, 0, 0, 31, 0, 0, 0},       // '-'
    {0, 0, 0, 0, 0, 12, 12},      // '.'
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
    {14, 17, 1, 2, 4, 0, 4},      // '?'
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
};

static const uint8_t *glyph_for(char ch) {
  if (ch >= 'a' && ch <= 'z')
    ch = (char)toupper((unsigned char)ch);
  for (size_t i = 0; i < sizeof(FONT_CHARS) - 1; ++i)
    if (FONT_CHARS[i] == ch)
      return FONT_GLYPHS[i];
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

static int g_pipe[2] = {-1, -1};
static pthread_t g_timer_thread;
static std::atomic<bool> g_running{false};

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
  // Drain every byte the timer has queued up
  char buf[64];
  ssize_t n;
  do {
    n = read(fd, buf, sizeof(buf));
  } while (n == sizeof(buf));

  // Pump SDL events on the main thread
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    if (event.type == SDL_EVENT_QUIT) {
      // Window was closed – could signal q here; for now just let it be
    }
  }
  return (K)0;
}

// ---------------------------------------------------------------------------
// q_init[w; h; s]
// ---------------------------------------------------------------------------
K q_init(K w, K h, K s) {
  if (w->t != -KI || h->t != -KI || s->t != -KI)
    return krr((S) "type");
  if (g_window)
    return krr((S) "already initialised");

  g_width = w->i;
  g_height = h->i;
  g_scale = s->i;

  if (g_width <= 0 || g_height <= 0 || g_scale <= 0)
    return krr((S) "invalid dimensions");

  // Allocate pixel buffer (initialised to black)
  g_pixels.assign(g_width * g_height, 0u);

  // SDL must be initialised on the main thread on macOS
  if (!SDL_Init(SDL_INIT_VIDEO))
    return krr((S) "sdl init failed");

  g_window = SDL_CreateWindow("qVis", g_width * g_scale, g_height * g_scale, 0);
  if (!g_window)
    return krr((S) "window creation failed");

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

  // Disable alpha blending so pixels are copied as-is.
  // Without this, alpha=0x00 colours (e.g. 0x00FF0000 red) are fully
  // transparent and the window always appears black.
  SDL_SetTextureBlendMode(g_texture, SDL_BLENDMODE_NONE);

  // Show an initial black frame immediately
  SDL_RenderClear(g_renderer);
  SDL_RenderPresent(g_renderer);

  // Create the pipe and register with q's event loop via sd1
  if (pipe(g_pipe) != 0)
    return krr((S) "pipe failed");
  sd1(g_pipe[0], on_pipe_readable);

  // Start the timer thread
  g_running = true;
  pthread_create(&g_timer_thread, nullptr, timer_loop, nullptr);

  return (K)0;
}

// ---------------------------------------------------------------------------
// q_shutdown[::]
// ---------------------------------------------------------------------------
K q_shutdown(K unused) {
  if (!g_window)
    return (K)0;

  g_running = false;
  pthread_join(g_timer_thread, nullptr);

  sd0(g_pipe[0]);
  close(g_pipe[0]);
  close(g_pipe[1]);
  g_pipe[0] = g_pipe[1] = -1;

  SDL_DestroyTexture(g_texture);
  g_texture = nullptr;
  SDL_DestroyRenderer(g_renderer);
  g_renderer = nullptr;
  SDL_DestroyWindow(g_window);
  g_window = nullptr;
  SDL_Quit();
  g_pixels.clear();
  return (K)0;
}

// ---------------------------------------------------------------------------
// Drawing primitives – all write into g_pixels (the CPU-side buffer).
// Nothing is visible until q_present is called.
// ---------------------------------------------------------------------------
static inline void set_pixel(int x, int y, uint32_t color) {
  if ((unsigned)x < (unsigned)g_width && (unsigned)y < (unsigned)g_height)
    g_pixels[y * g_width + x] = color;
}

K q_clear(K color) {
  if (color->t != -KI)
    return krr((S) "type");
  std::fill(g_pixels.begin(), g_pixels.end(), (uint32_t)color->i);
  return (K)0;
}

K q_pixel(K x, K y, K color) {
  if (x->t != -KI || y->t != -KI || color->t != -KI)
    return krr((S) "type");
  set_pixel(x->i, y->i, (uint32_t)color->i);
  return (K)0;
}

K q_line(K x1, K y1, K x2, K y2, K color) {
  if (x1->t != -KI || y1->t != -KI || x2->t != -KI || y2->t != -KI ||
      color->t != -KI)
    return krr((S) "type");

  int ax = x1->i, ay = y1->i, bx = x2->i, by = y2->i;
  uint32_t c = (uint32_t)color->i;

  int dx = std::abs(bx - ax), sx = ax < bx ? 1 : -1;
  int dy = -std::abs(by - ay), sy = ay < by ? 1 : -1;
  int err = dx + dy;
  for (;;) {
    set_pixel(ax, ay, c);
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

  int rx = x->i, ry = y->i, rw = w->i, rh = h->i;
  uint32_t c = (uint32_t)color->i;
  for (int j = ry; j < ry + rh; ++j)
    for (int i = rx; i < rx + rw; ++i)
      set_pixel(i, j, c);
  return (K)0;
}

K q_circle(K x, K y, K r, K color) {
  if (x->t != -KI || y->t != -KI || r->t != -KI || color->t != -KI)
    return krr((S) "type");

  int cx = x->i, cy = y->i, radius = r->i;
  uint32_t c = (uint32_t)color->i;
  // Filled circle via midpoint / scanline
  for (int dy2 = -radius; dy2 <= radius; ++dy2) {
    int hw = (int)std::sqrt((double)(radius * radius - dy2 * dy2));
    for (int dx2 = -hw; dx2 <= hw; ++dx2)
      set_pixel(cx + dx2, cy + dy2, c);
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

  int oy = y->i, s = scale->i;
  uint32_t c = (uint32_t)color->i;
  G *chars = kC(str);
  int cx = x->i;
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

  SDL_UpdateTexture(g_texture, nullptr, g_pixels.data(),
                    g_width * (int)sizeof(uint32_t));
  SDL_RenderClear(g_renderer);
  SDL_RenderTexture(g_renderer, g_texture, nullptr, nullptr);
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
  if (pixels->n != (J)(g_width * g_height))
    return krr((S) "length - must equal width*height");
  memcpy(g_pixels.data(), kI(pixels), g_width * g_height * sizeof(uint32_t));
  return (K)0;
}

} // extern "C"
