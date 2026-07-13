
/ exampleBoids.q - Flocking simulation (Reynolds' boids), fully vectorised.
/ Neighbour search is the same vectorised spatial hash as exampleFluid.q:
/ boids are binned into perception-radius cells with `group`, candidate
/ pairs gathered from each boid's 3x3 cell neighbourhood in one flat
/ dictionary lookup, and the three steering rules (cohesion, alignment,
/ separation) all run as scatter-adds (@[;;+;]) over flat pair vectors -
/ O(N) work instead of N x N distance matrices, which is what lets N reach
/ the thousands. What makes it read as a murmuration rather than a bouncing
/ ball of dots:
/   - alignment-dominant gains: heavy cohesion collapses the flock into a
/     blob, so matching neighbours' heading does most of the steering
/   - wall force ramps with penetration depth over a wide margin, so edges
/     produce smooth arcing turns instead of billiard bounces
/   - per-boid wander is persistent (a decaying gust, not white noise -
/     white noise averages to nothing across a neighbourhood)
/   - a phantom predator drifts through the flock; the scatter-and-regroup
/     waves of a real murmuration are predator-driven
/ Birds render as dark 5px streaks along their heading, stamped into a
/ precomputed dusk-sky gradient and pushed with one .qvis.setpixels call
/ (exampleNBody.q style) - no per-boid draw loops.
/ Hold the left mouse button to be a second predator. Press p for a slider
/ panel (ported from exampleNBody.q) to tune the steering gains live.

system "l qVis.q"

W:1280; H:900; SCALE:1;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

N: 3500;

/ R1/R2/SEP set the flock's packing density, and the hash gather's cost is
/ proportional to R1^2 * density - this tuning holds a worst-case clumped
/ flock at ~8ms/frame (N=3500), inside the 16ms timer
R1: 36f;                            / perception radius; also the hash cell size
R2: 16f;                            / crowding radius
COH: 0.0032;                        / steer toward neighbourhood centre
ALI: 0.10;                          / match neighbourhood mean velocity
SEP: 0.064;                         / push off crowders, harder when closer
NOI: 0.04;                          / per-boid gust/wander gain
PRED: 0.427f;                       / predator repulsion strength
VMIN: 2.5f; VMAX: 4.5f;             / tight speed band: starlings can't hover
MARG: 120f; TURN: 0.3;              / soft wall: force ramps inside the margin
CTR: 0.00008;                       / faint roost pull discourages corner-hugging

/ cell-id offsets of the 3x3 hash-grid neighbourhood; 4096 is the row
/ stride, comfortably above the 36 cells a 1280px row actually spans
OFFS: raze (-1 0 1) +\: 4096*-1 0 1;

/ dusk sky, computed once: pale blue-grey up top to warm peach at the
/ horizon - birds stamp over a copy of this each frame
ys: (til H)%H-1;
BG: raze W#'(65536i*`int$140+ys*95) + (256i*`int$158+ys*24) + `int$188-ys*52;

/ per-bird silhouette shade: near-black with slight variation so the flock
/ reads as depth rather than a flat stencil
sh: `int$N?26;
COL: (65536i*18+sh) + (256i*20+sh) + 28+sh;
SO: -2 -1 0 1 2f;                   / streak sample offsets along the heading

seed:{[]
    X:: `float$N?W; Y:: `float$N?H;
    ang: 6.28318530718*N?1f;
    VX:: 3f*cos ang; VY:: 3f*sin ang;
    WX:: N#0f; WY:: N#0f; }         / per-boid wander (gust) state

/ phantom predator: wanders on smoothed random velocity, reflects at edges
PPX: W%3f; PPY: H%3f; PVX: 3f; PVY: 1f;

/ radial repulsion from (qx;qy), fading to zero at radius sqrt r2m
flee:{[qx;qy;s;r2m]
    ddx: X-qx; ddy: Y-qy;
    d2: 1f|(ddx*ddx)+ddy*ddy;
    k: s*(0f|1f-d2%r2m)%sqrt d2;
    (k*ddx;k*ddy) }

/ --- parameter panel: p toggles, drag a knob to tune the sim live ----------
/ (global; min; max) - the knob writes straight to the named root global
PANEL:0b; DRAG:-1;
SLD: ((`COH;0f;0.005);(`ALI;0f;0.25);(`SEP;0f;0.8);(`NOI;0f;0.4);(`PRED;0f;16f);(`VMAX;3f;7f));
PX:14; PY:36; TW:150; RH:16;

slider:{[ev;i]
    lbl: SLD[i;0]; mn: SLD[i;1]; mx: SLD[i;2];
    y: PY+RH*i;
    f: 0f|1f&((`float$value lbl)-mn)%mx-mn;
    .qvis.rect[PX; y+5; TW; 2; .qvis.gray];
    .qvis.rect[PX+(f*TW)-2; y; 5; 12; .qvis.white];
    v: `float$value lbl;
    .qvis.text[PX+TW+10; y+3; 1; .qvis.white;
        string[lbl]," ",string $[v<0.01; 1e-4*`long$v*1e4; v<10; 0.001*`long$v*1000; `long$v]];
    if[(ev`click)&((ev`my) within (y;y+13))&(ev`mx) within (PX-4;PX+TW+4); DRAG::i]; }

panelFrame:{[ev]
    if[`p in ev`new; PANEL::not PANEL];
    if[not PANEL; :(::)];
    .qvis.rect[PX-8; PY-12; TW+170; 30+RH*count SLD; .qvis.fade[190;1973790i]];
    slider[ev] each til count SLD;
    if[not .qvis.PL; DRAG::-1];
    if[DRAG>=0; (SLD[DRAG;0]) set SLD[DRAG;1]+(SLD[DRAG;2]-SLD[DRAG;1])*0f|1f&((ev`mx)-PX)%TW];
    by: PY+RH*count SLD;
    .qvis.rect[PX; by+2; 44; 13; .qvis.fade[120;.qvis.gray]];
    .qvis.text[PX+7; by+5; 1; .qvis.white; "RESET"];
    if[(ev`click)&((ev`my) within (by+2;by+15))&(ev`mx) within (PX;PX+44); seed[]]; }

.z.ts:{
    ev: .qvis.poll[];

    / candidate pairs via the spatial hash: miss -> empty list, so edges
    / just work; I/J are flat pair-index vectors, (dx;dy) points i->j
    c: (floor X%R1) + 4096*floor Y%R1;
    g: group c;
    vals: g raze c +\: OFFS;
    J: raze vals;
    I: (where count each vals) div 9;
    dx: X[J]-X I; dy: Y[J]-Y I;
    r2: (dx*dx)+dy*dy;
    kp: where (r2>1e-9) & r2<R1*R1;
    I: I kp; J: J kp; dx: dx kp; dy: dy kp; r2: r2 kp;

    / cohesion + alignment need per-boid neighbourhood means; the m mask
    / zeroes both for isolated boids (a 1-floor alone would read as drag)
    cn: @[N#0f; I; +; 1f];
    m: "f"$cn>0f; cn: 1f|cn;
    ax: (COH*@[N#0f; I; +; dx]%cn) + ALI*m*((@[N#0f; I; +; VX J]%cn)-VX);
    ay: (COH*@[N#0f; I; +; dy]%cn) + ALI*m*((@[N#0f; I; +; VY J]%cn)-VY);

    / separation: push away from crowding pairs along the unit vector,
    / weighted (1-r/R2) so the closest neighbours push hardest
    s: where r2<R2*R2;
    r: sqrt r2 s;
    w: (1f-r%R2)%r;
    ax-: SEP*@[N#0f; I s; +; w*dx s];
    ay-: SEP*@[N#0f; I s; +; w*dy s];

    / walls: force grows with penetration depth into the margin, so the
    / flock arcs away from an edge instead of bouncing off it
    ax+: TURN*(0f|1f-X%MARG)-0f|1f-(W-X)%MARG;
    ay+: TURN*(0f|1f-Y%MARG)-0f|1f-(H-Y)%MARG;
    ax+: CTR*(W%2f)-X; ay+: CTR*(H%2f)-Y;

    / persistent per-boid gusts: an AR(1) wander that individual birds
    / carry for ~a second, which is what breaks up the static ball
    WX:: (0.92*WX)+(N?1f)-0.5f; WY:: (0.92*WY)+(N?1f)-0.5f;
    ax+: NOI*WX; ay+: NOI*WY;

    / phantom predator drifts on smoothed random velocity; the flock's
    / scatter-and-regroup waves come from its passes
    PVX:: (0.985*PVX)+0.25*(first 1?1f)-0.5f;
    PVY:: (0.985*PVY)+0.25*(first 1?1f)-0.5f;
    psp: sqrt (PVX*PVX)+PVY*PVY;
    pf: (1.5f|5f&psp)%psp+1e-12;
    PVX*: pf; PVY*: pf;
    PPX:: PPX+PVX; PPY:: PPY+PVY;
    if[PPX<40f; PPX::40f; PVX::abs PVX];   if[PPX>W-40f; PPX::W-40f; PVX::neg abs PVX];
    if[PPY<40f; PPY::40f; PVY::abs PVY];   if[PPY>H-40f; PPY::H-40f; PVY::neg abs PVY];
    fp: flee[PPX;PPY;PRED;16900f];
    ax+: fp 0; ay+: fp 1;

    / second predator: hold left mouse anywhere off the panel
    op: PANEL and ((ev`mx) within (PX-8;PX+TW+161)) and (ev`my) within (PY-12;PY+17+RH*count SLD);
    if[.qvis.PL and not op;
        fm: flee[`float$ev`mx;`float$ev`my;12f;22500f];
        ax+: fm 0; ay+: fm 1];

    VX+: ax; VY+: ay;
    sp: sqrt (VX*VX)+VY*VY;
    spc: VMIN|VMAX&sp;
    f: spc%sp+1e-12;
    VX*: f; VY*: f;
    nx: VX%spc; ny: VY%spc;            / unit heading for the streak stamp
    X:: 2f|(W-3f)&X+VX;                / clamp keeps every stamp in-buffer
    Y:: 2f|(H-3f)&Y+VY;

    / render: 5 samples along each heading -> a tiny oriented dash, the
    / whole flock stamped in one ragged scatter over a copy of the sky
    idx: raze (W*`long$Y+/:SO*\:ny) + `long$X+/:SO*\:nx;
    .qvis.setpixels @[BG; idx; :; raze 5#enlist COL];
    .qvis.circle[`int$PPX; `int$PPY; 3; 2367518i];   / the raptor
    if[not PANEL; .qvis.text[8; H-22; 2; .qvis.gray; "Press p to open menu"]];
    panelFrame ev;
    .qvis.present[] }

seed[]
/ Cooperative timer: slower hardware renders the next completed step rather
/ than accumulating a simulation backlog.
system "t 16"
