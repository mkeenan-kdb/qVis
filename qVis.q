// qVis.q - kdb+ wrapper for qSDL pixel grid library. Everything lives in the
// .qvis namespace so loading it into a session leaves the root clean.
// SDL window runs on the main thread; a background pipe-timer keeps it alive
// without blocking the q session. Call .qvis.present[] to flush the back buffer.

\d .qvis

// ---------------------------------------------------------------------------
// Internal: Load C functions from the shared library. qSDL.so (built into
// native/) is resolved via the QVIS env var (path to the qVis repo root)
// when set, else the current directory - so either run q from the repo
// root or export QVIS first.
// ---------------------------------------------------------------------------
LIB:{`$":",$[count e:getenv`QVIS; e,"/native/qSDL"; "./native/qSDL"]}[]

c_init:     LIB 2: (`q_init;     3)        // width; height; scale
c_shutdown: LIB 2: (`q_shutdown; 1)        // ::
c_clear:    LIB 2: (`q_clear;    1)        // color
c_pixel:    LIB 2: (`q_pixel;    3)        // x; y; color
c_line:     LIB 2: (`q_line;     5)        // x1; y1; x2; y2; color
c_rect:     LIB 2: (`q_rect;     5)        // x; y; w; h; color
c_circle:   LIB 2: (`q_circle;   4)        // x; y; r; color
c_polygon:  LIB 2: (`q_polygon;  3)        // xs; ys; color
c_getpixel: LIB 2: (`q_getpixel; 2)        // x; y -> RGB int
c_present:  LIB 2: (`q_present;  1)        // ::
c_setpixels:LIB 2: (`q_setpixels;1)        // int-list of width*height ARGB values
c_text:     LIB 2: (`q_text;     5)        // x; y; scale; color; string
c_keys:     LIB 2: (`q_keys;     1)        // ::
c_mouse:    LIB 2: (`q_mouse;    1)        // ::
c_textin:   LIB 2: (`q_textin;   1)        // ::
c_clipboard:LIB 2: (`q_clipboard;1)        // ::
c_setclip:  LIB 2: (`q_setclip;  1)        // string
c_loadfont: LIB 2: (`q_load_font; 2)       // path; pt_size -> font_id
c_drawtext: LIB 2: (`q_draw_text; 5)       // x; y; font_id; color; string
c_textsize: LIB 2: (`q_text_size; 2)       // font_id; string -> (width; height)
c_textinkbox:LIB 2: (`q_text_ink_box;2)    // font_id; string -> (offsetX;offsetY;width;height)
c_displaysize:LIB 2: (`q_display_size; 1)  // :: -> (w; h)
c_seteventcb:LIB 2: (`q_seteventcb; 1)     // fn name string ("" disables)
// ---------------------------------------------------------------------------
// Colors - ARGB 32-bit integers (0xAARRGGBB).
// You can also pass any int literal, e.g. 0xFF8800i for orange.
// The alpha byte controls translucency: 0 (the default for every plain
// 0xRRGGBB constant below, since none of them set it) means "unspecified" and
// draws fully opaque, exactly as before this byte did anything. 1-254 blends
// the new color into whatever is already there by that weight; 255 is an
// explicit fully-opaque draw. Build a translucent color with fade[a;color].
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

// fade[a; color]
//   a     - alpha 1-255 (0 would round-trip as "unspecified"/opaque, so
//           there's no way to ask for a fully invisible draw - just skip it)
//   color - a plain 0xRRGGBB color (as above, or your own)
//   Returns color with its alpha byte set to a, for use with rect/circle/
//   polygon/line/pixel/text to draw a translucent shape. Builds the ARGB int
//   via a wraparound trick because q's `int$` clamps (rather than wraps) an
//   out-of-range long to 0W: any alpha>=128 needs the top bit set, which
//   makes the 32-bit value negative once reinterpreted as a signed int.
fade:{[a;color] v:(16777216*a)+color; `int$v-4294967296*v>2147483647}

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

// polygon[xs; ys; color]
//   xs; ys - equal-length int lists of vertex coordinates (>=3 points)
//   color  - ARGB int
//   Draws a filled simple polygon (scanline fill, even-odd winding) - e.g.
//   a shaded area under a line, or any translucent custom shape via fade[].
polygon: { [xs; ys; color] c_polygon[`int$xs; `int$ys; `int$color] }

// getpixel[x; y]
//   Returns the RGB currently sitting in the back buffer at (x;y) as an int
//   (no alpha - every stored pixel is fully opaque internally). Mainly for
//   tests/tooling that want to check a blend without a screenshot.
getpixel: { [x; y] c_getpixel . toInt(x;y)}

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

// displaysize[]
//   Returns the display size (usable bounds) of the primary monitor as a
//   dictionary `w`h! (width; height).
displaysize: { c_displaysize[::] }

// loadfont[path; pt_size]
//   path    - char vector path to TTF/OTF font file
//   pt_size - integer font size (points)
//   Returns an integer font id (>=0) on success.
loadfont: { [path; pt_size] c_loadfont[$[(type path)=-10h; enlist path; path]; `int$pt_size] }

// sysfonts
//   A dictionary of proportional (`prop) and monospace (`mono) bundled TTF font paths.
qvisBase:$[count e:getenv`QVIS; e; first system "pwd"];
sysfonts:()!()
sysfonts[`prop]:enlist qvisBase,"/assets/fonts/Roboto-Regular.ttf"
sysfonts[`mono]:enlist qvisBase,"/assets/fonts/RobotoMono-Regular.ttf"

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

// textinkbox[font_id; str]
//   font_id - integer font id
//   str     - string/char vector
//   Returns a 4-item int list (offsetX; offsetY; width; height): the tight
//   bounding box of actually-inked pixels, relative to the (x,y) anchor
//   passed to drawtext[]. textsize[] returns the font's full line metrics
//   (ascent+descent+leading), which is usually taller than the visible
//   glyphs - e.g. a string with no descenders leaves dead space below the
//   letters. Use textinkbox[] instead when you need a pixel-accurate
//   collision box, e.g. for bouncing text off a window edge.
textinkbox: { [font_id; str] c_textinkbox[`int$font_id; $[(type str)=-10h; enlist str; str]] }

// seteventcb[name]
//   name - char vector naming a unary q function (e.g. ".qos.FRAMETS"), or
//   "" to disable.
//   While set, the native event pump applies the function (with a dummy 0i
//   argument) on the q main thread whenever SDL activity arrives - keys,
//   mouse, text, window expose/resize/focus, quit - coalesced to one call
//   per ~16ms pump. The call fires from q's own select loop (sd1), so it
//   never interrupts a running q computation. This is the push complement
//   to poll[]: instead of redrawing on a fixed \t, set a callback that runs
//   a frame and reserve \t for animation. shutdown[] clears it; re-register
//   after the next init[].
seteventcb: { [s] c_seteventcb $[-10h=type s; enlist s; s]; }

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
// your own .z.ts loop; see apps/exampleText.q for usage.
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
