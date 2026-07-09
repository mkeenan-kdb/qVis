
/ exampleMandelbrot.q - Interactive Mandelbrot explorer, fully vectorised.
/ All pixels iterate z = z*z + c simultaneously as flat float vectors; the
/ escape count per pixel indexes a rainbow palette. Escaped points run to
/ inf/nan harmlessly - their comparisons go false and they stop counting,
/ so no masking is needed inside the loop.
/ Click the SDL window to focus it, then HOLD keys (polled ~16x/s):
/   w a s d / arrows   pan       r / f   zoom in / out
/ Deep zooms eventually pixelate: float64 runs out near SPAN ~1e-13, and
/ banding sharpens as you go - raise MAXIT for crisper deep frames.

system "l qVis.q"

W:800; H:600; SCALE:1;
.qvis.init[W; H; SCALE]

/ View: centre of the complex window and its real-axis width
CTRX: -0.6; CTRY: 0f; SPAN: 3.2; MAXIT: 100;

px: `float$ (W*H) # til W;
py: `float$ raze W #/: til H;

/ Rainbow palette: 256 ARGB ints around the hue wheel (same as exampleAnimation)
PAL: {[x]
    h6: 6f * x % 256f;
    i:  `int$ floor h6;
    f:  h6 - floor h6;
    R: (1f; 1f-f; 0f;    0f;   f;   1f   ) i;
    G: (f;  1f;   1f;    1f-f; 0f;  0f   ) i;
    B: (0f; 0f;   f;     1f;   1f;  1f-f ) i;
    ((`int$ floor 255*R) * 65536i) + ((`int$ floor 255*G) * 256i) + `int$ floor 255*B
    } each til 256

/ One iteration for every pixel at once.
/ State: (zr; zi; count-still-inside; cr; ci) - c rides along so the fold
/ needs no globals (q lambdas don't close over locals).
stepM:{[s]
    zr: s 0; zi: s 1;
    zr2: zr*zr; zi2: zi*zi;
    / within, not <4f: escaped orbits overflow to inf then nan, and q nulls
    / compare less-than everything - within stays false for both
    m: (zr2 + zi2) within 0 4f;
    ((zr2 - zi2) + s 3; (2f * zr * zi) + s 4; (s 2) + m; s 3; s 4) }

frameM:{
    cr: CTRX + SPAN * (px % W-1) - 0.5;
    ci: CTRY + (SPAN * H%W) * (py % H-1) - 0.5;
    s: MAXIT stepM/ (0f*cr; 0f*cr; (count cr)#0; cr; ci);
    esc: s 2;
    ?[esc = MAXIT; 0i; PAL `int$ (esc * 5) mod 256] }

renderM:{
    .qvis.setpixels frameM[];
    .qvis.text[6; 6; 1; .qvis.white; "WASD PAN, RF ZOOM"];
    .qvis.text[6; 16; 1; .qvis.yellow; "ZOOM ", (string 3.2 % SPAN), "X"];
    .qvis.present[] }

mvM:{[ch]
    $[ch="w"; CTRY-: 0.08*SPAN;
      ch="s"; CTRY+: 0.08*SPAN;
      ch="a"; CTRX-: 0.08*SPAN;
      ch="d"; CTRX+: 0.08*SPAN;
      ch="r"; SPAN*: 0.88;
      ch="f"; SPAN*: 1.136;
      ::]; }

KM: `w`a`s`d`r`f`up`down`left`right ! "wasdrfwsad"
.z.ts:{ if[count h: .qvis.keyz[] inter key KM; mvM each KM h; renderM[]] }
system "t 60"

renderM[]
