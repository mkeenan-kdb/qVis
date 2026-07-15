
/ exampleSand.q - Falling-sand cellular automaton, fully vectorised. Every
/ grain moves at most once per pass, computed for the whole grid at once -
/ no per-cell loops, same trick exampleLife.q uses for Conway's Game of Life.
/ The classic hazard with a vectorised sand sim is collisions: if you let
/ every grain slide diagonally in whichever direction it likes in one shot,
/ two grains two columns apart can both target the same empty cell. The fix
/ here is to only ever slide the WHOLE grid in a single diagonal direction
/ per phase - column c always slides to c-1 (or always to c+1), which is an
/ injective mapping, so no two source cells can ever claim the same target.
/ Each substep runs three phases - straight down, then one diagonal each way
/ (alternating which side goes first) - so sand falls straight when it can
/ and slides off peaks when it can't.
/ Layout: the grid is one flat W*H vector, not an (H;W) matrix - "the cell
/ below" is a single `W rotate`, a diagonal is `(W+dc) rotate`, with no
/ per-row rotate' eaches. Occupancy lives in two boolean planes (S sand,
/ B wall) so the hot loop streams 1-byte vectors instead of 4-byte ints -
/ 4x less memory traffic, which is what pays for the bigger canvas and the
/ extra substeps. Rotate wrap-around (bottom row into top, row edges into
/ neighbouring rows) is harmless because the border cells are all wall, so
/ no grain ever sits where a wrapped move could start or land illegally.
/ Left-click pours sand, right-click draws walls. Click the window to
/ focus it first.

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

/ Native resolution: a grain is one screen pixel.
W:1280; H:960; SCALE:1;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

S: (W*H)#0b;                        / sand occupancy plane
B: (W*H)#0b;                        / wall occupancy plane
B: @[B; (W*til H),((W-1)+W*til H),(W*H-1)-til W; :; 1b];  / side walls + floor

colors: .qvis.black, 14729320i, .qvis.gray   / empty/sand(tan)/wall, indexed S+2*B

/ fall[] - sand with an empty cell directly below drops one row.
/ (S>x is boolean "S and not x"; (W rotate occ)[i] is occupancy at i+W.)
fall:{[]
    move: S > W rotate S|B;
    S:: (S>move) | neg[W] rotate move; }

/ slide[dc] - sand blocked from falling straight down slides diagonally by
/ dc columns (-1 left, 1 right) when that cell is empty. A single call only
/ ever slides in ONE direction, so column c can only ever target c+dc - a
/ bijection - which is what keeps this collision-free without arbitration.
slide:{[dc]
    occ: S|B;
    move: S & (W rotate occ) > (W+dc) rotate occ;
    S:: (S>move) | neg[W+dc] rotate move; }

/ brush: a BR-radius disk of flat-buffer offsets, clipped to stay inside
/ the border walls when stamped
BR:7; roff: (neg BR)+til 1+2*BR;
ox: ((count roff)*count roff)#roff;
oy: raze (count roff)#/:roff;
keep: where ((ox*ox)+oy*oy) <= BR*BR;
ox: ox keep; oy: oy keep;

/ paint[mx;my;sand] - stamps the brush at (mx;my): sand=1b pours sand,
/ 0b draws wall; either overwrites what was there (the planes stay disjoint)
paint:{[mx;my;sand]
    idx: (W * 1|(H-2)&my+oy) + 1|(W-2)&mx+ox;
    S:: @[S; idx; :; sand];
    B:: @[B; idx; :; not sand]; }

frame: 0;

/ Substeps per tick set the terminal fall speed (1px each); the cheap
/ boolean passes are what make this many affordable per frame.
SUBSTEPS: 6;

.z.ts:{
    m: .qvis.mouse[];
    if[m`l; paint[m`x; m`y; 1b]];
    if[m`r; paint[m`x; m`y; 0b]];

    do[SUBSTEPS;
        fall[];
        dc: $[frame mod 2; -1; 1];  / alternate which side slides first
        slide dc; slide neg dc;
        frame+: 1];

    .qvis.setpixels colors[S+2*B];
    .qvis.present[] }

/ The cooperative timer renders the next completed physical step on slower
/ hardware rather than building up a simulation backlog.
system "t 16"
