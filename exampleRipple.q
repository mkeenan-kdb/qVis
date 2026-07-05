
/ exampleRipple.q - Full-frame water-ripple interference pattern.
/ Three fixed point sources emit waves that decay with distance; the
/ interference of all three is rendered as a blue-tinted grayscale.
/ Distances are precomputed once (grid is static), only the phase (t)
/ animates - same vectorised-math approach as exampleAnimation.q.

system "l qVis.q"

W:440; H:360; SCALE:2;
init[W; H; SCALE]

px: `float$ (W*H) # til W
py: `float$ raze W #/: til H

/ wave sources: x,y pairs
/ NOTE: use decimal literals (60.0), not `f`-suffixed ones (60f) - q parses
/ a run of `Nf` tokens as separate expressions, not a single float vector.
srcx: 120.0 100.0 240.0
srcy: 120.0 180.0 90.0

/ distance from every pixel to each source
dist: {[sx;sy] sqrt ((px-sx)*(px-sx)) + ((py-sy)*(py-sy))}'[srcx;srcy]

t: 0f
lastT: .z.p

.z.ts:{
    now: .z.p;
    elapsed: 1e-9 * `float$ now-lastT;
    lastT:: now;
    / each source: amplitude decays with distance, phase driven by t (bounded - t is inside sin)
    waves: {[d] (sin (d*0.15)-t) % 1+d*0.03}'[dist];
    v: sum waves;                       / interference sum
    / map to 0-255 brightness, clamp both ends explicitly (not relying on null-fill)
    g: 0i|255i& `int$ floor 128+42*v;
    r: `int$ 0.15*g; gc: `int$ 0.45*g;  / blue-tinted water look
    setpixels r*65536i + gc*256i + g;
    present[];
    t+: 1.5*elapsed
    }

/ Start at ~60 fps
system "t 16"
