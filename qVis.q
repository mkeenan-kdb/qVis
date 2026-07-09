// qVis.q - kdb+ wrapper for qSDL pixel grid library. Everything lives in the
// .qvis namespace so loading it into a session leaves the root clean.
// SDL window runs on the main thread; a background pipe-timer keeps it alive
// without blocking the q session. Call .qvis.present[] to flush the back buffer.

\d .qvis

// ---------------------------------------------------------------------------
// Internal: Load C functions from the shared library. qSDL.so is resolved via
// the QVIS env var (path to the qVis repo root) when set, else the current
// directory - so either run q from the repo root or export QVIS first.
// ---------------------------------------------------------------------------
LIB:{`$":",$[count e:getenv`QVIS; e,"/qSDL"; "./qSDL"]}[]

c_init:     LIB 2: (`q_init;     3)   // width; height; scale
c_shutdown: LIB 2: (`q_shutdown; 1)   // ::
c_clear:    LIB 2: (`q_clear;    1)   // color
c_pixel:    LIB 2: (`q_pixel;    3)   // x; y; color
c_line:     LIB 2: (`q_line;     5)   // x1; y1; x2; y2; color
c_rect:     LIB 2: (`q_rect;     5)   // x; y; w; h; color
c_circle:   LIB 2: (`q_circle;   4)   // x; y; r; color
c_present:  LIB 2: (`q_present;  1)   // ::
c_setpixels:LIB 2: (`q_setpixels;1)   // int-list of width*height ARGB values
c_text:     LIB 2: (`q_text;     5)   // x; y; scale; color; string
c_keys:     LIB 2: (`q_keys;     1)   // ::
c_mouse:    LIB 2: (`q_mouse;    1)   // ::
c_textin:   LIB 2: (`q_textin;   1)   // ::
c_clipboard:LIB 2: (`q_clipboard;1)   // ::
c_setclip:  LIB 2: (`q_setclip;  1)   // string
c_loadfont: LIB 2: (`q_load_font; 2)  // path; pt_size -> font_id
c_drawtext: LIB 2: (`q_draw_text; 5)  // x; y; font_id; color; string
c_textsize: LIB 2: (`q_text_size; 2)  // font_id; string -> (width; height)
// ---------------------------------------------------------------------------
// Colors - ARGB 32-bit integers (0xAARRGGBB, alpha is ignored)
// You can also pass any int literal, e.g. 0xFF8800i for orange
// ---------------------------------------------------------------------------
black:   0i
white:   16777215i // 0x00FFFFFF
red:     16711680i // 0x00FF0000
green:   65280i    // 0x0000FF00
blue:    255i      // 0x000000FF
yellow:  16776960i // 0x00FFFF00
cyan:    65535i    // 0x0000FFFF
magenta: 16711935i // 0x00FF00FF
gray:    8421504i  // 0x00808080

/util for casting ints
toInt:`int$'
// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

// init[w; h; s]
//   w - pixel width of the virtual canvas
//   h - pixel height of the virtual canvas
//   s - integer scale factor (each logical pixel becomes s x s screen pixels)
//   Opens the SDL window and starts the render loop. Must be called first.
init: { [w; h; s] c_init . toInt(w;h;s);}

// shutdown[]
//   Closes the SDL window and frees resources. Call before exiting q.
shutdown: { c_shutdown[::] }

// clear[color]
//   color - fill color (ARGB int, e.g. .qvis.black or 0i)
//   Fills the entire back buffer with a single color.
clear: { [color] c_clear[`int$color] }

// pixel[x; y; color]
//   x     - column (0 = left)
//   y     - row    (0 = top)
//   color - ARGB int
//   Plots a single pixel on the back buffer.
pixel: { [x; y; color] c_pixel . toInt(x;y;color);}

// line[x1; y1; x2; y2; color]
//   x1; y1 - start coordinate
//   x2; y2 - end coordinate
//   color  - ARGB int
//   Draws a straight line using Bresenham's algorithm.
line: { [x1; y1; x2; y2; color] c_line . toInt(x1;y1;x2;y2;color);}

// rect[x; y; w; h; color]
//   x; y  - top-left corner
//   w     - width  in pixels
//   h     - height in pixels
//   color - ARGB int
//   Draws a filled rectangle.
rect: { [x; y; w; h; color] c_rect . toInt(x;y;w;h;color);}

// circle[x; y; r; color]
//   x; y  - centre coordinate
//   r     - radius in pixels
//   color - ARGB int
//   Draws a filled circle.
circle: { [x; y; r; color] c_circle . toInt(x;y;r;color);}

// present[]
//   Copies the back buffer to the front buffer and triggers a screen update.
//   Call once per frame after all drawing is done.
present: { c_present[::]; }

// setpixels[buf]
//   buf - int list of exactly width*height ARGB values (e.g. output of a
//         vectorised frame computation)
//   Copies the entire list directly into the pixel buffer in one C call.
//   Far faster than looping pixel[] for full-frame effects like plasma.
setpixels: { [buf] c_setpixels[buf]; }

// text[x; y; scale; color; str]
//   x; y  - top-left corner of the first character
//   scale - integer pixel size per font dot (1 = 5x7px per character)
//   color - ARGB int
//   str   - a string (char list), e.g. "HELLO WORLD"
//   Draws with a built-in 5x7 bitmap font: space, 0-9, A-Z, a-z and a
//   handful of punctuation ! ' , - . : ?. Unsupported characters render
//   blank. One font, no external font files - swap in SDL_ttf later if
//   real typefaces are needed.
text: { [x; y; scale; color; str] c_text . (`int$x; `int$y; `int$scale; `int$color; $[(type str)=-10h; enlist str; str]); }

// keyz[]
//   Returns a symbol list of every key currently held down, e.g. `w`up.
//   The SDL window must have focus (click it first). Names are lowercased
//   SDL key names with spaces as underscores (`left_shift`). Poll from a
//   .z.ts loop for real-time input - no Enter key or terminal involved.
keyz: { c_keys[::] }

// mouse[]
//   Returns a dictionary `x`y`l`r`w`c!
//   (x; y; left_click; right_click; wheel_delta; window_closed)
//   Coordinates are in the same pixel space as drawing primitives,
//   scaled down automatically based on init[W; H; SCALE].
//   w is the scroll-wheel movement since the previous mouse[] call
//   (positive = up); c becomes 1 once the window close button is
//   pressed and stays 1 until shutdown[].
mouse: { c_mouse[::] }

// textin[]
//   Returns the text typed into the window since the previous call as a
//   char vector (read-and-reset, "" when nothing was typed). Sourced from
//   SDL text-input events, so shift, keyboard layout and IME composition
//   are already applied - use this (not keyz[]) to implement typing.
textin: { c_textin[::] }

// clipboard[]
//   Returns the system clipboard contents as a char vector ("" when empty).
clipboard: { c_clipboard[::] }

// setclip[str]
//   Replaces the system clipboard contents with str (char vector or atom).
setclip: { [s] c_setclip $[-10h=type s; enlist s; s]; }

// loadfont[path; pt_size]
//   path    - char vector path to TTF/OTF font file
//   pt_size - integer font size (points)
//   Returns an integer font id (>=0) on success.
loadfont: { [path; pt_size] c_loadfont[$[(type path)=-10h; enlist path; path]; `int$pt_size] }

// sysfonts
//   A dictionary of proportional (`prop) and monospace (`mono) TTF font paths
//   across different systems (macOS, Linux, Windows), ordered by preference.
sysfonts:()!()
sysfonts[`prop]:(
  "/System/Library/Fonts/Supplemental/Arial.ttf";
  "/System/Library/Fonts/Arial.ttf";
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
  "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
  "/usr/share/fonts/TTF/DejaVuSans.ttf";
  "/usr/share/fonts/liberation/LiberationSans-Regular.ttf";
  "C:/Windows/Fonts/arial.ttf"
  )
sysfonts[`mono]:(
  "/System/Library/Fonts/SFNSMono.ttf";
  "/System/Library/Fonts/Supplemental/Courier New.ttf";
  "/System/Library/Fonts/Courier New.ttf";
  "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";
  "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf";
  "/usr/share/fonts/TTF/DejaVuSansMono.ttf";
  "/usr/share/fonts/liberation/LiberationMono-Regular.ttf";
  "C:/Windows/Fonts/cour.ttf";
  "C:/Windows/Fonts/consola.ttf"
  )

// loadsysfont[style; pt_size]
//   style   - `prop or `mono
//   pt_size - integer font size (points)
//   Tries to load common system fonts for the given style until one succeeds.
//   Returns the font id (>=0) on success, or -1i on failure.
loadsysfont:{[style; pt_size]
  paths:sysfonts style;
  fid:-1i;
  i:0;
  while[(i<count paths) & fid<0;
    fid:.[loadfont;(paths[i];`int$pt_size);-1i];
    i+:1;
    ];
  fid
  }

// drawtext[x; y; font_id; color; str]
//   x; y    - top-left corner coordinate of the text
//   font_id - integer font id returned by loadfont
//   color   - ARGB int
//   str     - string/char vector to draw
//   Draws text using a loaded TrueType/OpenType font.
drawtext: { [x; y; font_id; color; str] c_drawtext[`int$x; `int$y; `int$font_id; `int$color; $[(type str)=-10h; enlist str; str]] }

// textsize[font_id; str]
//   font_id - integer font id
//   str     - string/char vector
//   Returns a 2-item int list (width; height) of the text bounds in pixels.
textsize: { [font_id; str] c_textsize[`int$font_id; $[(type str)=-10h; enlist str; str]] }

// ---------------------------------------------------------------------------
// Edge-detected input - poll[] wraps keyz[]/mouse[] and diffs against the
// previous call, so callers get clean "just pressed" / "just clicked" events
// instead of level state. State lives in .qvis.PK / .qvis.PL.
// ---------------------------------------------------------------------------
PK:0#`; PL:0b; PR:0b

// pollReset[]
//   Clears the edge-detection state; call when (re)opening a UI so stale
//   keys from a previous session aren't reported as new.
pollReset: { [] PK::0#`; PL::0b; PR::0b; }

// poll[]
//   Returns `new`held`click`rclick`mx`my`wheel`closed`text!
//     new    - keys pressed since the previous poll[] (symbol list)
//     held   - every key currently down (symbol list)
//     click  - 1b on the frame the left button goes down
//     rclick - 1b on the frame the right button goes down
//     mx; my - mouse position in canvas pixel space
//     wheel  - scroll delta since the previous poll[] (0 when idle)
//     closed - 1b once the window close button has been pressed
//     text   - characters typed since the previous poll[] (see textin[])
poll: { []
  ks:keyz[]; m:mouse[];
  r:`new`held`click`rclick`mx`my`wheel`closed`text!
    (ks except PK; ks; (1=m`l) and not PL; (1=m`r) and not PR; m`x; m`y; 0^m`w; 1=m`c; textin[]);
  PK::ks; PL::1=m`l; PR::1=m`r;
  r}

// ---------------------------------------------------------------------------
// Text effect utilities - stateless helpers for animating text[]. Each takes
// the elapsed/animation time t (seconds) and returns a value to plug into
// your own .z.ts loop; see examples/exampleText.q for usage.
// ---------------------------------------------------------------------------

// textWidth[scale; str]
//   Pixel width of a string drawn with text[] at the given scale (5x7 font,
//   6px advance per character - matches qSDL.cpp's glyph spacing).
textWidth: { [scale; str] scale * 6 * count str }

// blink[period; t]
//   period - full on+off cycle length in seconds
//   t      - elapsed time in seconds
//   Returns 1b for the first half of each period, 0b for the second half.
//   Skip the text[] call when this is 0b to make it flash.
blink: { [period; t] (t mod period) < period % 2 }

// marqueeX[speed; w; textW; t]
//   speed  - travel speed in px/sec (positive = leftward, negative = rightward)
//   w      - canvas width
//   textW  - pixel width of the string (see textWidth)
//   t      - elapsed time in seconds
//   Returns an x coordinate that starts just off the right edge, scrolls
//   across, and wraps back once the text fully exits the left edge -
//   loops forever.
marqueeX: { [speed; w; textW; t] `int$ w - ((speed * t) mod (w + textW)) }

\d .
