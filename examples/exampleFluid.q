
/ exampleFluid.q - Particle fluid (SPH, Clavet-style "double density
/ relaxation"), fully vectorised. A block of water is suspended near the top
/ of the screen, falls under gravity, and splashes off the floor with
/ turbulence, sloshing and settling into a pool. Neighbour search is a
/ vectorised spatial hash: particles are binned into h-sized cells with
/ `group`, candidate pairs gathered from each particle's 3x3 cell
/ neighbourhood in one flat dictionary lookup, and every interaction then
/ runs on flat pair vectors with scatter-adds (`@[;;+;]` accumulates
/ duplicate indices) - O(N) work instead of exampleNBody.q's O(N^2)
/ matrices, which is what lets N reach the thousands. No per-particle loops:
/   - density  rho_i  = sum_j (1 - r/h)^2  over neighbours within radius h
/   - pressure displacements push overdense pairs apart along their unit
/     vector; a "near" pressure term (cubic kernel) prevents particle
/     clumping and gives the surface-tension-ish beading water needs
/   - viscosity applies impulses along the pair axis proportional to the
/     approach speed, which damps jitter and makes the splash coherent
/ Positions are relaxed directly and velocity is recomputed as
/ (pos-prevpos)/dt (prediction-relaxation), which stays stable at large
/ time steps where explicit-force SPH explodes.
/ Particles are coloured by speed - deep blue at rest through cyan to white
/ foam in the splash - and stamped as small disks into one flat pixel
/ buffer pushed with a single .qvis.setpixels, as in exampleNBody.q.
/ Left-click blasts the water away from the cursor (make your own splash).
/ across substeps with a margin) if the rebuild ever dominates a profile.

system "l qVis.q"

W:960; H:720; SCALE:1;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

/ The hash grid does ~30 pair interactions per particle regardless of N,
/ so 3,000 fine-grained particles cost less than 875 did under the old
/ all-pairs matrices (~3.5ms per substep at full pool density).
NC:120; NR:100; N:NC*NR;
SP:5f;                              / initial lattice spacing (px)

ix: til[N] mod NC; iy: til[N] div NC;
X: ((W-SP*NC-1)%2f) + (SP*ix) + 0.5*N?1f;   / jitter breaks lattice symmetry
Y: 36f + (SP*iy) + 0.5*N?1f;
VX: N#0f; VY: N#0f;

HR: 12.5f;                          / interaction radius h = 2.5*SP, also the hash cell size
GRAV: 0.18f;                        / gravity per substep^2 (dt=1, px units)
RHO0: 2.6f;                         / rest density for the lattice above
K: 0.5f;                            / pressure stiffness
KN: 4f;                             / near-pressure stiffness (anti-clumping)
VISC: 0.25f;                        / XSPH velocity-smoothing strength (0..1)
DT: 1f; SUBSTEPS: 3;
DMAX: 3f;                           / relaxation displacement cap per substep
PAD: 6f;                            / wall inset; also guarantees disk stamps stay in-buffer

/ cell-id offsets of the 3x3 hash-grid neighbourhood; 4096 is the row
/ stride, comfortably above the ~77 cells a 960px row actually spans
OFFS: raze (-1 0 1) +\: 4096*-1 0 1;

/ One physics substep: predict positions under gravity, relax them against
/ density error, recover velocities, then damp with viscosity impulses.
/ Interactions run on flat pair-index vectors (I;J): gather with X[I]-X J,
/ accumulate per particle with @[;I;+;] scatter-adds. No loops anywhere.
step:{[]
    VY:: VY+DT*GRAV;
    px: X; py: Y;
    X:: X+DT*VX; Y:: Y+DT*VY;

    / spatial hash: bin into HR-sized cells, then each particle's candidate
    / neighbours are the members of its 3x3 surrounding cells, gathered in
    / one flat lookup. `where count each` expands ragged hits back to a
    / particle index per candidate without any per-particle iteration.
    c: (floor X%HR) + 4096*floor Y%HR;
    g: group c;
    vals: g raze c +\: OFFS;         / miss -> empty list, so edges just work
    J: raze vals;
    I: (where count each vals) div 9;

    / exact filter: inside h and not the particle itself; (ex;ey) is the
    / unit vector i->j, qq the linear kernel (1-r/h)
    dx: X[I]-X J; dy: Y[I]-Y J;
    r2: (dx*dx)+dy*dy;
    kp: where (r2>1e-9) & r2<HR*HR;
    I: I kp; J: J kp; dx: dx kp; dy: dy kp;
    r: sqrt r2 kp;
    qq: 1f-r%HR;
    ex: neg dx%r; ey: neg dy%r;

    / double density relaxation; displacement of i sums both halves of each
    / pair's push, hence the symmetric (P_i+P_j) terms
    qq2: qq*qq;
    rho: @[N#0f; I; +; qq2]; rhon: @[N#0f; I; +; qq2*qq];
    P: K*rho-RHO0; PN: KN*rhon;
    D: ((P[I]+P J)*qq) + (PN[I]+PN J)*qq2;
    mx: 0.5*DT*DT*@[N#0f; I; +; D*ex];
    my: 0.5*DT*DT*@[N#0f; I; +; D*ey];
    / cap the relaxation displacement: crowded wall corners can otherwise
    / build one-substep pressure spikes that eject "popcorn" particles at
    / unphysical speed long after the pool has settled
    cap: 1f&DMAX%1e-12+sqrt (mx*mx)+my*my;
    X:: X-mx*cap;
    Y:: Y-my*cap;

    / walls: clamp into the box (top open); recovered velocity below makes
    / wall hits inelastic, which is what water against concrete looks like
    X:: PAD|(W-PAD)&X;
    Y:: PAD|(H-PAD)&Y;

    VX:: (X-px)%DT; VY:: (Y-py)%DT;

    / XSPH viscosity: blend each velocity toward its kernel-weighted
    / neighbourhood mean. Bounded by construction (a convex mix), unlike a
    / Clavet quadratic impulse, which overshoots and explodes at dt=1 when
    / the falling block slams into the floor at speed ~ h/2 per step.
    / Reuses this substep's neighbour list rather than paying a second pass.
    w: 1e-9+@[N#0f; I; +; qq];
    VX:: VX-VISC*@[N#0f; I; +; qq*VX[I]-VX J]%w;
    VY:: VY-VISC*@[N#0f; I; +; qq*VY[I]-VY J]%w; }

/ disk stamp offsets (radius 2): big enough that neighbouring particles at
/ rest spacing (5px) overlap into a continuous body of water, not dots
off: -1+til 5;
/OX: `int$25#off; OY: `int$raze 5#'off;
OX: enlist 0i; OY: enlist 0i;
kp: where ((OX*OX)+OY*OY)<=5; OX: OX kp; OY: OY kp;

.z.ts:{
    m: .qvis.mouse[];
    if[m`l;                          / radial blast away from the cursor
        ddx: X-`float$m`x; ddy: Y-`float$m`y;
        d2: 1f|(ddx*ddx)+ddy*ddy;
        s: 3f*(0f|1f-d2%10000f)%sqrt d2;
        VX:: VX+s*ddx; VY:: VY+s*ddy];

    do[SUBSTEPS; step[]];

    / colour by speed: deep blue -> cyan -> white foam
    f: 1f&(sqrt (VX*VX)+VY*VY)%5f;
    col: (65536i*`int$30+f*225)+(256i*`int$100+f*150)+`int$205+f*50;

    buf: (W*H)#.qvis.black;
    ixs: `int$X; iys: `int$Y;
    idx: raze (W*iys+/:OY)+ixs+/:OX; / PAD > stamp radius: always in-buffer
    buf: @[buf; idx; :; raze count[OX]#enlist col];
    .qvis.setpixels buf;
    .qvis.present[] }

/ Cooperative timer: slower hardware renders the next completed step rather
/ than accumulating a simulation backlog.
system "t 25"
