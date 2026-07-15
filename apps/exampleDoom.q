
/ exampleDoom.q - Wolfenstein-style 2.5D raycaster, fully vectorised.
/ One ray per screen column, but no per-ray loops: every ray marches every
/ step at once as a W x NSTEP matrix of map lookups, and the first wall hit
/ per column falls out of a cumulative-min. Walls are drawn as W one-pixel
/ rects, distance-shaded, with fisheye correction.
/ Click the SDL window to focus it, then HOLD keys (polled ~20x/s):
/   w / s / up / down    walk        a / d          strafe
/   q / e / left / right turn

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

W:320; H:200; SCALE:4;
.qvis.init[W; H; SCALE]

/ The map: 16x16, # = wall. Borders are solid so rays always terminate.
MAP: (
    "################";
    "#..............#";
    "#..##....##....#";
    "#..##....##..###";
    "#..............#";
    "#......##......#";
    "#..#...##...#..#";
    "#..#........#..#";
    "#..####..####..#";
    "#..............#";
    "#....#....#....#";
    "#....#....#....#";
    "#..............#";
    "###..........###";
    "#..............#";
    "################")
MAPW: count first MAP;
MFLAT: raze "#" = MAP;

/ Player
PX: 8.5; PY: 12.5; PA: -1.5708;   / facing north (negative y is up the map)

/ Rays: one per column; ANGOFF spreads them across a ~60 degree FOV
FOC: (W % 2) % tan 0.5236;
ANGOFF: atan ((`float$ til W) - W % 2) % FOC;
STEP: 0.04; NSTEP: 400;
DSTEPS: STEP * 1f + til NSTEP;

/ cast[] - wall distance per column (fisheye-corrected).
/ xm/ym are W x NSTEP matrices of sample points along every ray; MFLAT
/ indexed by the whole matrix gives hits, and sum-of-cumulative-min of the
/ misses counts the steps each ray survived.
cast:{
    ra: PA + ANGOFF;
    dxc: cos ra; dyc: sin ra;
    xm: PX + dxc *\: DSTEPS;
    ym: PY + dyc *\: DSTEPS;
    / floor, not `long$: q casts round to nearest, which shifts cells half a unit
    hitm: MFLAT (MAPW * 15 & 0 | floor ym) + 15 & 0 | floor xm;
    d: STEP * 1f + sum each mins each not hitm;
    d * cos ANGOFF }

renderD:{
    d: cast[];
    hgt: `long$ H & (H * 1.1) % d | 0.05;
    top: `long$ (H - hgt) % 2;
    br: 1f % 1f + 0.18 * d;                    / distance shading
    colz: ((`int$ 235*br) * 65536i) + ((`int$ 150*br) * 256i) + `int$ 110*br;
    .qvis.rect[0; 0; W; H div 2; 2109504i];          / ceiling 0x203040
    .qvis.rect[0; H div 2; W; H div 2; 3153952i];    / floor   0x302020
    {[i;t;h;c] .qvis.rect[i; t; 1; h; c]}'[til W; top; hgt; colz];
    .qvis.text[6; 6; 1; .qvis.white; "WASD MOVE, QE OR ARROWS TURN"];
    .qvis.present[] }

/ Movement with wall collision: only step if the target cell is open
mvD:{[ch]
    nx: PX; ny: PY;
    $[ch="w"; [nx+: 0.22 * cos PA; ny+: 0.22 * sin PA];
      ch="s"; [nx-: 0.22 * cos PA; ny-: 0.22 * sin PA];
      ch="a"; [nx+: 0.22 * sin PA; ny-: 0.22 * cos PA];
      ch="d"; [nx-: 0.22 * sin PA; ny+: 0.22 * cos PA];
      ch="q"; PA-: 0.07;
      ch="e"; PA+: 0.07;
      ::];
    if[not MFLAT (MAPW * floor ny) + floor nx; PX:: nx; PY:: ny]; }

KM: `w`a`s`d`q`e`up`down`left`right ! "wasdqewsqe"
.z.ts:{ if[count h: .qvis.keyz[] inter key KM; mvD each KM h; renderD[]] }
system "t 50"

renderD[]
