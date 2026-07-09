
/ exampleLife.q - Conway's Game of Life on a large, high-res toroidal grid.
/ Fully vectorised: the whole board steps in a handful of matrix ops, no
/ per-cell loops. Rendering is one palette-index + setpixels per frame.

system "l qVis.q"

W:1620; H:980; SCALE:1;   / 518,400 cells in a 1920x1080 window; shrink W/H for more fps
.qvis.init[W; H; SCALE]

/ seed the RNG from the clock so every run gets a different soup
system "S ",string `int$.z.t

/ grid: H rows x W cols of booleans (1b = alive), edges wrap (torus)
grid: (H;W) # 0.08 > (H*W)?1f

/ step[g] - one generation, vectorised over the whole board.
/ Trick: c = 3-cell vertical sums (row above + row + row below, via rotate,
/ which wraps - giving toroidal edges for free). Adding c's left and right
/ rotations gives every cell its full 3x3 sum; subtract self for the
/ neighbour count. Standard rules: born on 3, survive on 2 or 3.
step:{[g]
    c: g + (1 rotate g) + (-1 rotate g);
    n: ((1 rotate' c) + (-1 rotate' c) + c) - g;
    (n=3) | g & n=2 }

colors: .qvis.black, .qvis.green   / indexed by cell state: 0b = dead, 1b = alive
gen: 0

.z.ts:{
    grid:: step grid;
    gen+: 1;
    .qvis.setpixels raze colors grid;
    .qvis.text[8; 8; 2; .qvis.white; "GEN ", string gen];
    .qvis.present[] }

/ ~30 fps - Life reads better slightly slower than the 60fps demos
system "t 33"
