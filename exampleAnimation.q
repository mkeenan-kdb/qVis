
/ plasma.q - Full-frame plasma effect using vectorised q math
/ Every pixel is coloured each frame using overlapping sine waves.
/ Because q's sin[] is vectorised, the entire 320x240 = 76800-pixel
/ frame is computed in a handful of list operations, then pushed to
/ the screen in one setpixels[] call.

system "l qVis.q"

W:320; H:240; SCALE:1;
init[W; H; SCALE]

/ ---------------------------------------------------------------------------
/ Precompute coordinate grids (done once, reused every frame)
/ ---------------------------------------------------------------------------

/ x-coord of each pixel: 0..W-1 repeated H times
px: `float$ (W*H) # til W

/ y-coord of each pixel: each row value repeated W times
py: `float$ raze W #/: til H

/ distance from canvas centre - drives the radial ring component
dx: px - W%2f
dy: py - H%2f
dr: sqrt (dx*dx) + (dy*dy)

/ ---------------------------------------------------------------------------
/ Rainbow palette: 256 ARGB ints spanning the full hue wheel.
/ HSV(hue,1,1) converted to RGB; alpha byte left 0 (ignored by BLENDMODE_NONE).
/ IMPORTANT: use int literals (65536i, 256i) so palette type stays int,
/ matching the int list setpixels[] expects.
/ ---------------------------------------------------------------------------
pal: {[x]
    h6: 6f * x % 256f;
    i:  `int$ floor h6;
    f:  h6 - floor h6;
    R: (1f; 1f-f; 0f;    0f;   f;   1f   ) i;
    G: (f;  1f;   1f;    1f-f; 0f;  0f   ) i;
    B: (0f; 0f;   f;     1f;   1f;  1f-f ) i;
    r: `int$ floor 255*R;
    g: `int$ floor 255*G;
    b: `int$ floor 255*B;
    / int literals keep arithmetic in int range (max value = 16777215, fits i32)
    r*65536i + g*256i + b
    } each til 256

/ frame[t] - compute a full pixel buffer for time offset t (radians)
/ Four overlapping sine waves whose sum spans [-4,4] linearly mapped to [0,255]:
/   v1 - horizontal bands scrolling with t
/   v2 - vertical bands scrolling at a different speed (x1.13)
/   v3 - diagonal bands scrolling at x0.71
/   v4 - radial rings expanding from centre at x0.89

frame:{[t]
    v1:sin t+px*0.04;
    v2:sin (t*1.13)+py*0.04;
    v3:sin (t*0.71)+(px+py)*0.025;
    v4:sin (t*0.89)+dr*0.05;
    v:  v1 + v2 + v3 + v4;         / range [-4,4]
    / map to palette index [0,255], fill any stray nulls with 0
    idx: 0i ^ `int$ 255i & `int$ floor 127.5 + 31.875*v;
    pal idx                         / returns int list - same type as setpixels expects
    }

/ ---------------------------------------------------------------------------
/ Animation loop
/ ---------------------------------------------------------------------------
t:     0f       / time accumulator (radians)
dt:    0.06f    / target step per 16ms tick - increase for faster flow
speed: dt%0.016 / radians/sec, derived so playback speed is frame-time independent
lastT: .z.p

.z.ts:{
    now: .z.p;
    elapsed: 1e-9 * `float$ now-lastT;  / seconds since previous tick
    lastT:: now;
    setpixels frame t;
    present[];
    t+: speed*elapsed
    }

/ Start at ~60 fps
system "t 16"
