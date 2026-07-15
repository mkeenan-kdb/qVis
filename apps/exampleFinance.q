/
 exampleFinance.q - Interactive L2 Order Book Heatmap

 Simulates a high-frequency financial limit order book.
 A fast-moving mid-price randomly walks up and down the y-axis, 
 while bid and ask volumes are clustered around it, dropping off 
 via exponential decay.

 The entire rolling history (Time x Price) is maintained as a list
 of columns, transposed and blasted to the screen at 60fps via setpixels.

 Controls:
   W / S       : Shift the mid-price manually
   Up / Down   : Increase/Decrease market volatility
   Left / Right: Widen/Tighten the spread
\

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

W:400; H:300; SCALE:2
.qvis.init[W; H; SCALE]

/ ---------------------------------------------------------------------------
/ Thermal Palette: 256 colours
/ Maps 0->255 smoothly through: Black -> Blue -> Magenta -> Red -> Yellow
/ ---------------------------------------------------------------------------
pal: {[x]
    c: ( (0i;0i;0i);       / 0: Black
         (0i;0i;255i);     / 1: Blue
         (255i;0i;255i);   / 2: Magenta
         (255i;0i;0i);     / 3: Red
         (255i;255i;0i) ); / 4: Yellow
    
    idx: `int$ floor x % 64;
    idx2: 4i & idx + 1;
    f: (x mod 64) % 64.0;
    
    r: `int$ floor (c[idx;0]*(1f-f)) + (c[idx2;0]*f);
    g: `int$ floor (c[idx;1]*(1f-f)) + (c[idx2;1]*f);
    b: `int$ floor (c[idx;2]*(1f-f)) + (c[idx2;2]*f);
    r*65536i + g*256i + b
    } each til 256

/ ---------------------------------------------------------------------------
/ State Variables
/ ---------------------------------------------------------------------------
mid: 150.0       / Mid price (Y coordinate, 0 is top)
vol: 5.0         / Volatility (spread of orders)
spread: 2.0      / Distance from mid where orders are dense

qkeys: .qvis.keyz / SDL keyboard state via the public API

/ Rolling grid of W columns, each column has H price levels
grid: W # enlist H # 0i

/ ---------------------------------------------------------------------------
/ Update loop
/ ---------------------------------------------------------------------------
.z.ts:{
    / 1. Input handling - interactive tweaking of market params
    k: qkeys[::];
    if[`w in k; mid -:: 2.0];
    if[`s in k; mid +:: 2.0];
    if[`up in k; vol +:: 0.5];
    if[`down in k; vol -:: 0.5; vol:: 1f | vol];
    if[`left in k; spread -:: 0.5; spread:: 0f | spread];
    if[`right in k; spread +:: 0.5];
    
    mid:: 1f | (H-2f) & mid; / Clamp mid to screen limits
    
    / 2. Simulate new orderbook depth column
    / Random walk the mid-price
    mid +:: ((rand 2.0) - 1.0) * sqrt vol;
    mid:: 1f | (H-2f) & mid;
    
    / Calculate volume at each price level
    d: abs (til H) - mid;
    noise: H ? 1.0;
    
    / Depth is highest near the spread, and decays exponentially as we move away
    v: 255f * noise * exp neg (abs d - spread) % vol;
    v: v * d >= spread; / Hollow out the spread (no orders inside)
    
    col: 0i ^ `int$ 255i & `int$ floor v;
    
    / 3. Update the rolling matrix
    grid :: 1_grid, enlist col;
    
    / 4. Render
    / `grid` is W lists of H. `flip grid` is H lists of W.
    / `raze` flattens it to row-major H*W items for setpixels.
    .qvis.setpixels pal raze flip grid;
    
    / Overlay UI text
    .qvis.text[10; 10; 2; 16777215i; "MID:    ", string `int$mid];
    .qvis.text[10; 30; 2; 16777215i; "VOL:    ", string vol];
    .qvis.text[10; 50; 2; 16777215i; "SPREAD: ", string spread];
    .qvis.text[10; H - 15; 1; 16777215i; "[W/S] Move Mid  [UP/DN] Volatility  [L/R] Spread"];
    
    .qvis.present[];
    }

system "t 16"
