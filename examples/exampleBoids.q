
/ exampleBoids.q - Flocking simulation (Reynolds' boids), fully vectorised.
/ All pairwise distances are one N x N matrix; the three steering rules
/ (cohesion, alignment, separation) are matrix-vector products via mmu,
/ so the whole flock updates with zero per-boid loops. Edges wrap (torus).

system "l qVis.q"

W:640; H:400; SCALE:2;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

N: 200;
X: N ? `float$W;  Y: N ? `float$H;    / positions
VX: -1f + N?2f;   VY: -1f + N?2f;     / velocities, normalised to speed 2 below
sp0: sqrt (VX*VX) + VY*VY;
VX: 2f * VX % sp0; VY: 2f * VY % sp0;

.z.ts:{
    / pairwise square distances: d2[i;j] = |boid i - boid j|^2
    dxm: X -\: X; dym: Y -\: Y;
    d2: (dxm*dxm) + dym*dym;

    / neighbour masks as float matrices so mmu (BLAS matrix product) applies;
    / d2 > tiny excludes self from its own neighbourhood
    mf: "f"$ (d2 < 2500f) & d2 > 1e-9;   / flock radius 50px
    ms: "f"$ (d2 < 400f)  & d2 > 1e-9;   / crowding radius 20px
    cn: 1f | sum each mf;                / neighbour counts (1 floor avoids %0)
    cs: sum each ms;

    / steering: toward local centre, match local velocity, push off crowders
    VX +: (0.005 * ((mf mmu X) % cn) - X) + (0.05 * ((mf mmu VX) % cn) - VX) + 0.03 * (cs * X) - ms mmu X;
    VY +: (0.005 * ((mf mmu Y) % cn) - Y) + (0.05 * ((mf mmu VY) % cn) - VY) + 0.03 * (cs * Y) - ms mmu Y;

    / clamp speed to [1;3] px/tick
    sp: sqrt (VX*VX) + VY*VY;
    f: (1f | 3f & sp) % sp;
    VX *: f; VY *: f;

    X:: (X + VX) mod `float$W;
    Y:: (Y + VY) mod `float$H;

    / draw each boid as a short line along its heading
    .qvis.clear[.qvis.black];
    {[a;b;c;d] .qvis.line[a; b; c; d; .qvis.cyan]}'[`int$X; `int$Y; `int$X + 2*VX; `int$Y + 2*VY];
    .qvis.present[] }

/ ~60 fps
system "t 16"
