
/ exampleBounce.q - Bouncing ball using the immediate-mode primitives
/ (clear/circle/present) instead of a full-buffer setpixels effect.
/ Contrast with exampleAnimation.q's vectorised approach.

system "l qVis.q"

W:320; H:240; SCALE:2;
.qvis.init[W; H; SCALE]

r:  12i               / ball radius
bx: 150f; by: 100f    / position (px) 
vx: 220f; vy: 170f    / velocity (px/sec)
lastT: .z.p

.z.ts:{
    now: .z.p;
    dt: 1e-9 * `float$ now-lastT;
    lastT:: now;

    bx+: vx*dt;
    by+: vy*dt;

    / bounce off walls - clamp position and flip velocity sign
    if[bx<=r;    bx::r;   vx::abs vx];
    if[bx>=W-r;  bx::W-r; vx::neg abs vx];
    if[by<=r;    by::r;   vy::abs vy];
    if[by>=H-r;  by::H-r; vy::neg abs vy];

    / fade the previous frame toward black instead of clearing it outright -
    / a translucent full-canvas overlay leaves a trailing streak behind the
    / ball, showing off alpha blending (qVis.q's fade[])
    .qvis.rect[0; 0; W; H; .qvis.fade[40; .qvis.black]];
    .qvis.circle[`int$bx; `int$by; r; .qvis.yellow];
    .qvis.present[]
    }

/ Start at ~60 fps
system "t 16"
