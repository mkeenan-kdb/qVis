
/exampleRay.q - Interactive ray tracer, fully vectorised.
/Every pixel's ray is traced in parallel as flat float vectors: sphere
/intersections, checkerboard floor, hard shadows, specular highlights and
/ a sky gradient - no per-pixel loops anywhere.
/ Click the SDL window to focus it, then HOLD keys to walk in real time
/ (a .z.ts loop polls keyz[] ~20x/s; arrows work, the terminal never sees them):
/   w / s / up / down      forward / back      a / d   strafe left / right
/   q / e / left / right   turn                r / f   rise / fall
/ Typing wasdqerf at the q prompt + Enter still works via .z.pi, and any
/ other input is evaluated as normal q, so the REPL stays live
/ (e.g. "exit 0" to quit).

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

W:320; H:240; SCALE:3;
.qvis.init[W; H; SCALE]

/ ---------------------------------------------------------------------------
/ Scene: three spheres resting on the y=0 checkerboard plane
/ ---------------------------------------------------------------------------
SX: 0 -2.4 2.4f;      / centres
SY: 1 0.8 0.8f;
SZ: 7 5.5 5.5f;
SR: 1 0.8 0.8f;       / radii
CR: 1 0.2 0.25f;      / per-sphere base colour (r;g;b in 0-1)
CG: 0.25 0.85 0.45f;
CB: 0.2 0.35 1f;
L: 0.35 0.8 -0.4f; L: L % sqrt sum L*L;   / directional light (surface -> light)

/ Extended per-object arrays: index 3 = the plane (values only used where valid)
SXP: SX,0f; SYP: SY,0f; SZP: SZ,0f; SRP: SR,1f;

/ Camera
CX: 0f; CY: 1.6f; CZ: -3f; YAW: 0f;

/ ---------------------------------------------------------------------------
/ Precomputed camera-space ray directions (normalised; yaw applied per frame)
/ ---------------------------------------------------------------------------
px: `float$ (W*H) # til W;
py: `float$ raze W #/: til H;
u: (W%H) * (px % W-1) - 0.5;
v: 0.5 - py % H-1;
nrm: sqrt ((u*u) + (v*v)) + 1f;
RDX: u % nrm; RDY: v % nrm; RDZ: 1f % nrm;

/ ---------------------------------------------------------------------------
/ isect[i; ox;oy;oz; dx;dy;dz] - ray/sphere i hit distance per ray, 0w = miss.
/ Origins and dirs may be atoms or vectors (q arithmetic pervades either way),
/ so the same code serves primary rays (atom origin) and shadow rays (vector
/ origins at each hit point). Dirs must be normalised (half-b quadratic, a=1).
/ ---------------------------------------------------------------------------
isect:{[i; ox;oy;oz; dx;dy;dz]
    ax: ox - SX i; ay: oy - SY i; az: oz - SZ i;
    b: (ax*dx) + (ay*dy) + (az*dz);
    d: (b*b) - ((ax*ax) + (ay*ay) + (az*az)) + (SR i) * SR i;
    t: (neg b) - sqrt d;
    ?[(d > 0f) & t > 1e-3; t; 0w] }

/ Fold step: keep the nearest hit and which object it was
upd:{[st; t; i] m: t < st 0; (?[m; t; st 0]; ?[m; i; st 1]) }

/ ---------------------------------------------------------------------------
/ render[] - trace the whole frame from the current camera and present it
/ ---------------------------------------------------------------------------
render:{
    cy: cos YAW; sy: sin YAW;
    dx: (RDX*cy) + RDZ*sy;          / rotate camera-space dirs by yaw
    dz: (RDZ*cy) - RDX*sy;
    dy: RDY;

    / nearest hit across plane (id 3) and spheres (ids 0 1 2)
    tp: (neg CY) % dy;
    tb: ?[tp > 1e-3; tp; 0w];
    id: ?[tb < 0w; 3; -1];
    ts: isect[; CX;CY;CZ; dx;dy;dz] each til count SX;
    r: upd/[(tb;id); ts; til count SX];
    tb: r 0; id: r 1;
    miss: id = -1; ispl: id = 3; io: 0 | id;

    / hit point and surface normal
    hx: CX + tb*dx; hy: CY + tb*dy; hz: CZ + tb*dz;
    nx: ?[ispl; 0f; (hx - SXP io) % SRP io];
    ny: ?[ispl; 1f; (hy - SYP io) % SRP io];
    nz: ?[ispl; 0f; (hz - SZP io) % SRP io];

    / hard shadows: any sphere between hit point and the light
    sh: any 0w > isect[; hx+0.01*nx; hy+0.01*ny; hz+0.01*nz; L 0; L 1; L 2] each til count SX;

    / lambert + ambient, specular (Blinn-Phong) on the spheres only
    dif: 0f | (nx*L 0) + (ny*L 1) + (nz*L 2);
    lum: 0.15 + 0.85 * dif * not sh;
    sx2: (L 0)-dx; sy2: (L 1)-dy; sz2: (L 2)-dz;               / half vector
    hn: sqrt (sx2*sx2) + (sy2*sy2) + sz2*sz2;
    spc: (0f | ((nx*sx2) + (ny*sy2) + nz*sz2) % hn) xexp 32f;
    spc: 0.5 * spc * (not sh) & not ispl;

    / base colour: checkerboard on the plane, per-sphere colour otherwise
    ck: 0 < ((floor hx) + floor hz) mod 2;
    br: ?[ispl; ?[ck; 0.9; 0.15]; CR io];
    bg: ?[ispl; ?[ck; 0.9; 0.15]; CG io];
    bb: ?[ispl; ?[ck; 0.9; 0.15]; CB io];

    / sky gradient for misses
    m01: 0f | dy;
    R: ?[miss; 0.6 - 0.25*m01; (br*lum) + spc];
    G: ?[miss; 0.75 - 0.25*m01; (bg*lum) + spc];
    B: ?[miss; 0.95 - 0.15*m01; (bb*lum) + spc];

    ri: `int$ 255f * 0f | 1f & R;
    gi: `int$ 255f * 0f | 1f & G;
    bi: `int$ 255f * 0f | 1f & B;
    .qvis.setpixels (ri*65536i) + (gi*256i) + bi;

    .qvis.text[6; 6; 1; .qvis.white; "WASD MOVE, QE TURN, RF UP-DOWN, THEN ENTER"];
    .qvis.text[6; 16; 1; .qvis.yellow; "POS ", (" " sv string 0.1 * `long$ 10*(CX;CY;CZ)), "  YAW ", string `long$ 57.2958*YAW];
    .qvis.present[] }

/ ---------------------------------------------------------------------------
/ Input: one movement per char, applied in order; unknown chars ignored
/ ---------------------------------------------------------------------------
mv:{[ch]
    $[ch="w"; [CX+: 0.15*sin YAW; CZ+: 0.15*cos YAW];
      ch="s"; [CX-: 0.15*sin YAW; CZ-: 0.15*cos YAW];
      ch="a"; [CX-: 0.15*cos YAW; CZ+: 0.15*sin YAW];
      ch="d"; [CX+: 0.15*cos YAW; CZ-: 0.15*sin YAW];
      ch="q"; YAW-: 0.05;
      ch="e"; YAW+: 0.05;
      ch="r"; CY+: 0.12;
      ch="f"; CY-: 0.12;
      ::];
    CY|: 0.2; }

/ Movement chars re-render; anything else is evaluated as regular q input
.z.pi:{
    c: trim x except "\n";
    $[all c in "wasdqerf ";
      [mv each c; render[]; ""];
      @[{.Q.s value x}; c; {"'",x,"\n"}]] }

/ Real-time input: poll held keys while the SDL window has focus.
/ Renders only while something is held, so the session idles otherwise.
KEYMAP: `w`a`s`d`q`e`r`f`up`down`left`right ! "wasdqerfwsqe"
.z.ts:{ if[count h: .qvis.keyz[] inter key KEYMAP; mv each KEYMAP h; render[]] }
system "t 50"

render[]
