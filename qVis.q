// qVis.q - kdb+ wrapper for qSDL pixel grid library
// SDL window runs on the main thread; a background pipe-timer keeps it alive
// without blocking the q session. Call present[] to flush the back buffer.

// ---------------------------------------------------------------------------
// Internal: Load C functions from shared library (qSDL.so must be on the path)
// ---------------------------------------------------------------------------
LIB: `$":./qSDL"

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
//   color - fill color (ARGB int, e.g. black or 0i)
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
//   Draws with a built-in 5x7 bitmap font: space, 0-9, A-Z (lowercase is
//   upper-cased) and a handful of punctuation ! ' , - . : ?. Unsupported
//   characters render blank. One font, no external font files - swap in
//   SDL_ttf later if real typefaces/lowercase glyphs are needed.
text: { [x; y; scale; color; str] c_text . (toInt(x;y;scale;color)),enlist str; }