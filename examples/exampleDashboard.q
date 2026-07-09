
/ exampleDashboard.q - Streaming market-data dashboard.
/ A simulated high-frequency feed appends bursts of random-walk trades to a
/ q table ~30x per second; four panels redraw every frame from that table:
/   top left     price chart for the selected symbol, mouse crosshair
/   bottom left  volume bars and an all-symbols normalised overlay
/   right        clickable symbol list and session stats
/ Interaction (click the SDL window to focus it):
/   click a symbol row or press 1-6   select symbol
/   space                             pause and resume the feed
/   up and down arrows                grow and shrink the time window

system "l qVis.q"

W:800; H:500; SCALE:2;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

/ ---------------------------------------------------------------------------
/ Market state
/ ---------------------------------------------------------------------------
SYMS: `AAPL`MSFT`GOOG`AMZN`TSLA`NVDA;
LAST: SYMS ! 150 320 140 180 240 480f;          / latest price per symbol
TBL: ([] t: 0#0Np; s: 0#`; p: 0#0f; z: 0#0);    / rolling trade table
RATE: 0#0;                                      / trades per burst history
CUR: `AAPL; WINDOW: 400; PAUSED: 0b; PKEYS: 0#`;

/ One burst of trades: every symbol random-walks, busier names print more
genTicks:{
    n: 30 + rand 50;
    sm: n ? SYMS;
    px: LAST[sm] * 1f + (n ? 0.002) - 0.001;
    @[`LAST; sm; :; px];                  / dup syms: last write wins
    TBL,: ([] t: n#.z.p; s: sm; p: px; z: 1 + n?100);
    TBL:: -4000 sublist TBL;
    RATE,: n; RATE:: -60 sublist RATE; }

/ ---------------------------------------------------------------------------
/ Layout and colours
/ ---------------------------------------------------------------------------
PPX:8;   PPY:8;   PPW:560; PPH:260;   / price
VPX:8;   VPY:276; VPW:560; VPH:100;   / volume
APX:8;   APY:384; APW:560; APH:108;   / all-symbol overlay
SPX:576; SPY:8;   SPW:216; SPH:260;   / symbol list
TPX:576; TPY:276; TPW:216; TPH:216;   / stats

BG: 658448i; BGP: 1185308i; BORD: 2764856i; XHAIR: 3359829i;
SYMCOL: (.qvis.red; .qvis.green; .qvis.cyan; .qvis.yellow; .qvis.magenta; .qvis.white);

panel:{[x;y;pw;ph;title]
    .qvis.rect[x; y; pw; ph; BGP];
    .qvis.line[x; y; x+pw-1; y; BORD];      .qvis.line[x; y+ph-1; x+pw-1; y+ph-1; BORD];
    .qvis.line[x; y; x; y+ph-1; BORD];      .qvis.line[x+pw-1; y; x+pw-1; y+ph-1; BORD];
    .qvis.text[x+5; y+5; 1; .qvis.gray; title]; }

/ Scale a series into a box and draw it as a polyline; returns (min;max)
plotline:{[x0;y0;pw;ph;ser;col]
    n: count ser; if[n < 2; :0n 0n];
    if[n > pw; ser: ser `long$ (til pw) * n % pw; n: pw];   / 1 sample per px
    mn: min ser; mx: max ser; rg: 1e-9 | mx - mn;
    xs: x0 + `long$ (pw-1) * (til n) % n-1;
    ys: (y0 + ph - 2) - `long$ (ph-18) * (ser - mn) % rg;
    .qvis.line'[-1_xs; -1_ys; 1_xs; 1_ys; col];
    (mn; mx) }

fmt:{ string 0.01 * `long$ 100 * x }            / 2dp price formatting

/ ---------------------------------------------------------------------------
/ Frame
/ ---------------------------------------------------------------------------
draw:{
    m: .qvis.mouse[];
    .qvis.clear[BG];

    / --- price panel
    ser: (neg WINDOW) sublist exec p from TBL where s = CUR;
    up: $[1 < count ser; (last ser) >= first ser; 1b];
    panel[PPX; PPY; PPW; PPH; (string CUR), "  ", fmt LAST CUR];
    r: plotline[PPX+2; PPY+16; PPW-4; PPH-18; ser; $[up; .qvis.green; .qvis.red]];
    if[not null r 0;
        .qvis.text[PPX+PPW-60; PPY+18;      1; .qvis.gray; "HI ", fmt r 1];
        .qvis.text[PPX+PPW-60; PPY+PPH-12;  1; .qvis.gray; "LO ", fmt r 0]];

    / --- crosshair with price readout when hovering the price panel
    if[(2 < count ser) and ((m`x) within (PPX+2; PPX+PPW-3)) and (m`y) within (PPY+16; PPY+PPH-3);
        .qvis.line[m`x; PPY+16; m`x; PPY+PPH-2; XHAIR];
        .qvis.line[PPX+2; m`y; PPX+PPW-2; m`y; XHAIR];
        n: (count ser) & PPW-4;
        i: (n-1) & `long$ ((m`x) - PPX+2) * n % PPW-4;
        .qvis.text[16 + m`x; 4 + m`y; 1; .qvis.white; fmt ser `long$ i * (count ser) % n]];

    / --- volume panel: bucket sizes into one bar per 8px column
    panel[VPX; VPY; VPW; VPH; "VOLUME"];
    zs: (neg WINDOW) sublist exec z from TBL where s = CUR;
    if[7 < count zs;
        nb: 64;
        vols: sum each value group `long$ (til count zs) * nb % count zs;
        bh: `long$ (VPH-22) * vols % 1 | max vols;
        bw: (VPW-8) div nb;
        .qvis.rect'[VPX + 4 + bw * til count vols; (VPY+VPH-2) - bh; bw-1; bh; 3381759i]];

    / --- all-symbols overlay, each independently normalised
    panel[APX; APY; APW; APH; "ALL SYMBOLS, EACH NORMALISED"];
    {[i] plotline[APX+2; APY+16; APW-4; APH-18;
        (neg WINDOW) sublist exec p from TBL where s = SYMS i; SYMCOL i]; } each til count SYMS;

    / --- symbol list: hover highlight, click to select, 1-6 shortcuts
    panel[SPX; SPY; SPW; SPH; "SYMBOLS - CLICK OR 1-6"];
    / m passed in: q lambdas don't close over outer locals
    {[m;i]
        ry: SPY + 22 + 18 * i;
        hov: ((m`x) within (SPX+1; SPX+SPW-2)) and (m`y) within (ry; ry+15);
        if[hov; .qvis.rect[SPX+1; ry; SPW-2; 16; BORD]];
        if[CUR = SYMS i; .qvis.rect[SPX+1; ry; 3; 16; SYMCOL i]];
        ser: -2 sublist exec p from TBL where s = SYMS i;
        chg: $[2 = count ser; 100 * ((ser 1) - ser 0) % ser 0; 0f];
        .qvis.text[SPX+10; ry+4; 1; SYMCOL i; (string 1+i), " ", string SYMS i];
        .qvis.text[SPX+80; ry+4; 1; .qvis.white; fmt LAST SYMS i];
        .qvis.text[SPX+150; ry+4; 1; $[chg < 0; .qvis.red; .qvis.green]; $[chg < 0; ""; "+"], fmt chg];
        }[m;] each til count SYMS;

    / --- stats panel
    panel[TPX; TPY; TPW; TPH; "SESSION"];
    tps: `long$ (sum RATE) % 0.033 * 1 | count RATE;
    .qvis.text[TPX+10; TPY+24;  1; .qvis.white;  "ROWS   ", string count TBL];
    .qvis.text[TPX+10; TPY+40;  1; .qvis.white;  "TPS    ", string tps];
    .qvis.text[TPX+10; TPY+56;  1; .qvis.white;  "WINDOW ", string WINDOW];
    .qvis.text[TPX+10; TPY+72;  1; $[PAUSED; .qvis.red; .qvis.green]; $[PAUSED; "PAUSED"; "LIVE"]];
    .qvis.text[TPX+10; TPY+150; 1; .qvis.gray;   "SPACE  PAUSE"];
    .qvis.text[TPX+10; TPY+166; 1; .qvis.gray;   "UP,DN  WINDOW"];
    .qvis.text[TPX+10; TPY+182; 1; .qvis.gray;   "CLICK  SELECT"];

    .qvis.present[]; }

/ ---------------------------------------------------------------------------
/ Input: keys are level-polled; space is edge-detected so it toggles once
/ ---------------------------------------------------------------------------
NKEY: (`$/:string 1 + til count SYMS) ! til count SYMS;

handleInput:{
    ks: .qvis.keyz[];
    if[(`space in ks) and not `space in PKEYS; PAUSED:: not PAUSED];
    ns: ks inter key NKEY;
    if[count ns; CUR:: SYMS NKEY first ns];
    if[`up   in ks; WINDOW:: 2000 & WINDOW + 20];
    if[`down in ks; WINDOW:: 60   | WINDOW - 20];
    PKEYS:: ks;
    m: .qvis.mouse[];
    if[1 = m`l;
        ri: ((m`y) - SPY + 22) div 18;
        if[(ri within (0; -1 + count SYMS)) and ((m`x) within (SPX; SPX+SPW-1)) and (m`y) >= SPY + 22;
            CUR:: SYMS ri]]; }

.z.ts:{
    if[not PAUSED; genTicks[]];
    handleInput[];
    draw[]; }

system "t 33"
