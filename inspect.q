/ inspect.q - .vis visual inspector toolkit for kdb+/q, built on qVis (.qvis).
/ Load into any q session:  \l inspect.q
/ Run q from the qVis repo root, or export QVIS=/path/to/qVis first so
/ qVis.q and qSDL.so can be found.
/ Entry points:
/   .vis.tab t        table browser (in-memory, keyed, splayed, partitioned)
/   .vis.ns[]         namespace explorer (click to drill down)
/   .vis.plot x       line plot: numeric vector, list of vectors, or table
/   .vis.hist[x;n]    histogram of a numeric vector with n bins
/   .vis.scatter[x;y] scatter plot
/   .vis.candle t     OHLC candlestick chart (open/high/low/close columns)
/   .vis.bar[x;y]     bar chart of y values with x labels
/   .vis.watch[t;ms]  live plot of a table's tail, re-fetched every ms
/   .vis.watchAs[t;ms;k] live view of kind k: `plot, `candle, `tab, `hist or `bar
/   .vis.dash panels  tile several live views into one window - click a panel
/                     to zoom into it full-screen, esc returns to the grid
/   .vis.db[]         partitioned-database overview
/   .vis.mem[]        live memory monitor (.Q.w)
/   .vis.repl[]       q editor/REPL: type multiline q code, cmd+enter runs it
/ Every view has a one-line q) prompt at the bottom: type code, enter runs it
/ (system commands like \l db work; \\ exits q, console-style). The result
/ shows above the bar and the view refreshes, so deletes/updates in the
/ session appear immediately. Code can open views (.vis.plot, .vis.tab ...)
/ which stack on top - esc returns to where you were.
/ In the window: click drills down, right-click opens a context menu (copy,
/ filter by value, plot column...), typing /clause at the prompt filters the
/ view (where-clause on tables, substring on namespaces),
/ wheel/arrows/pgup/pgdn scroll, esc goes back (quits at the root view),
/ close button quits.
/ Your previous .z.ts handler and \t interval are restored on close.
/ NOTE if the window ever freezes: q pauses timers while the session is
/ suspended at a debug prompt (q)) after an error) or busy evaluating -
/ type \ to leave the debugger and the inspector resumes.

/ load qVis (.qvis namespace) unless the session already has it
if[()~@[key;`.qvis;()];
  {[d] @[system;"l ",$[count d;d;"."],"/qVis.q";
    {'"inspect.q: could not load qVis.q - run q from the qVis repo root ",
      "or export QVIS=/path/to/qVis (",x,")"}];} getenv`QVIS];

/ ---------------------------------------------------------------------------
/ Constants and state
/ ---------------------------------------------------------------------------
.vis.screen:.qvis.displaysize[];
.vis.SC:2;
.vis.W:`int$(0.8*.vis.screen`w) div .vis.SC; /width is 80% of screen size
.vis.H:`int$(0.8*.vis.screen`h) div .vis.SC; /height is 80% of screen size
.vis.BOX:(56;24;.vis.W-72;.vis.H-60);        / default chart plot area (x0;y0;pw;ph);
                                             / ph is recomputed in .vis.open once the
                                             / real tick-label font height is known
.vis.TBOX:(8;18;.vis.W-16;.vis.H-53);        / default table-browser box
.vis.boxOr:{[st;dflt] $[`box in key st; st`box; dflt]}  / dashboard panels override this
.vis.YLGUT:54;                               / gap reserved left of x0 for y-axis tick labels
                                             / (56-2 in the default BOX above) - qSDL has no
                                             / clip rect, so a dashboard panel must reserve
                                             / this itself or its neighbour's labels bleed in
.vis.TROWS:`int$(.vis.H-70) div 10;          / visible rows in table/text views
.vis.TXTC:130;                               / wrap width (chars) in text views
.vis.BG:658448i; .vis.GRID:2105376i; .vis.BORD:2764856i; /colors: background, grid, border
.vis.SELC:2046556i;                          / selected-line highlight (muted blue)
.vis.HOVER:.qvis.fade[50;.qvis.green];        / translucent row/panel/menu-item hover tint
.vis.SHADOW:.qvis.fade[120;.qvis.black];      / translucent drop shadow behind floating overlays

/ hoverIx[mx;my;x0;y0;w;rh;n] - index (0..n-1) of the row of height rh under
/ (mx;my) within a w-wide column starting at (x0;y0), or -1 if the mouse is
/ outside the block entirely (used to draw a hover highlight before content)
.vis.hoverIx:{[mx;my;x0;y0;w;rh;n]
  i:(my-y0) div rh;
  $[(mx within (x0;x0+w-1)) and i within (0;n-1); i; -1]}
.vis.CMDKS:`left_gui`right_gui`left_ctrl`right_ctrl`left_command`right_command`left_meta`right_meta`left_windows`right_windows;
.vis.PAL:(.qvis.cyan;.qvis.green;.qvis.yellow;.qvis.magenta;.qvis.red;.qvis.white); /our palette 

.vis.STACK:(); / view stack (drill-down)
.vis.FONT_PROP:-1i;
.vis.FONT_MONO:-1i;
.vis.MONOW:6;

.vis.drawText:{[x;y;fid;color;str]
  $[fid>=0; .qvis.drawtext[x;y;fid;color;str]; .qvis.text[x;y;1;color;str]]}

.vis.textWidth:{[fid;str]
  $[fid>=0; first .qvis.textsize[fid;str]; 6 * count str]}

.vis.HOT:([] x:0#0; y:0#0; w:0#0; h:0#0; rc:0#0b; act:());  / this frame's hotspots
.vis.OZTS:(::); .vis.OT:0;                                  / saved .z.ts and \t
.vis.RUN:0b;
.vis.DEBUG:`debug in lower key .Q.opt .z.x;

/ ---------------------------------------------------------------------------
/ Framework - one .z.ts loop, a stack of views, a hotspot table.
/ A view is a dict `name`draw`state; draw is monadic, receiving the polled
/ input event dict each frame, and reads/writes state via .vis.st / .vis.put.
/ ---------------------------------------------------------------------------
/ while the inspector is running, opening a view pushes it onto the stack
/ (so .vis.plot typed at the command bar stacks on the current view and esc
/ returns); the first open starts the window and render loop
.vis.open:{[v]
  if[.vis.RUN; .vis.push v; :(::)];
  .[.qvis.init;(.vis.W;.vis.H;.vis.SC);{[e]::}];  / tolerate an already-open window
  .vis.FONT_PROP:.qvis.loadsysfont[`prop;8];
  .vis.FONT_MONO:.qvis.loadsysfont[`mono;8];
  if[.vis.FONT_MONO>=0; .vis.MONOW:first .qvis.textsize[.vis.FONT_MONO;"a"]];
  / x-axis tick labels sit below the chart box, 4px under it, above the 25px
  / command bar - reserve exactly enough room for the loaded font's real
  / height (TTF fonts render taller than the old fixed 7px bitmap font, so a
  / hardcoded gutter clipped their bottom under the command bar's repaint)
  labelH:$[.vis.FONT_PROP>=0; last .qvis.textsize[.vis.FONT_PROP;"Ag"]; 7];
  .vis.BOX:(56;24;.vis.W-72;.vis.H-(24+25+4+labelH));
  .vis.OZTS:@[get;`.z.ts;{[e](::)}];
  .vis.OT:system"t";
  .vis.RUN:1b;
  .vis.STACK:enlist v;
  .vis.HOT:0#.vis.HOT; .qvis.pollReset[];
  .z.ts:{$[.vis.DEBUG;.vis.frame[];@[.vis.frame;(::);.vis.err]]};
  system"t 33";}

.vis.close:{[]
  if[not .vis.RUN; -1"[qVis] close: already stopped, returning"; :(::)];
  .vis.RUN:0b; .vis.STACK:();
  system"t ",string .vis.OT;
  $[(::)~.vis.OZTS; @[system;"x .z.ts";::]; .z.ts:.vis.OZTS];
  .qvis.shutdown[];
  }

/ a broken view shouldn't take the whole inspector down: pop back to the
/ parent; close only when the root view itself is the one failing
.vis.err:{[e]
  -1"[qVis] view error: ",e;
  $[2>count .vis.STACK; .vis.close[]; .vis.pop[]];}

.vis.push:{[v] .vis.STACK,:enlist v;}
.vis.pop:{[] $[2>count .vis.STACK; .vis.close[]; .vis.STACK:-1_.vis.STACK];}
.vis.popTo:{[i;e] .vis.STACK:(i+1) sublist .vis.STACK;}

/ current view's state dict / amend one key of it / replace it wholesale
/ dashboard panels reuse the ordinary draw fns (tabDraw, plotDraw, ...), which
/ all read/write "the current view's state" via .vis.st/.vis.put/.vis.putAll.
/ While drawing one panel, .vis.dashPanelDraw points STO at that panel's own
/ state dict so those calls land there instead of on the view stack; STO is
/ (::) - not overridden - everywhere else
.vis.STO:(::);
.vis.st:{[] $[(::)~.vis.STO; (last .vis.STACK)`state; .vis.STO]}
.vis.put:{[k;v]
  $[(::)~.vis.STO; .[`.vis.STACK;(-1+count .vis.STACK;`state;k);:;v]; .vis.STO[k]::v];}
.vis.putAll:{[st] $[(::)~.vis.STO; .[`.vis.STACK;(-1+count .vis.STACK;`state);:;st]; .vis.STO::st];}

/ edge-detected input from .qvis.poll, plus the inspector's own gestures:
/ esc = back (quits at the root view), window close button = quit. Every
/ other key is typeable - q/backspace go to the command bar (or the REPL
/ editor's buffer), not navigation.
.vis.poll:{[]
  r:.qvis.poll[];
  r[`back]:`escape in r`new;
  r[`close]:r`closed;
  r}

/ register a clickable rect for this frame; act is called with :: on click
/ (spot = left button, spotR = right button)
.vis.spot:{[x0;y0;w0;h0;a] .vis.HOT,:(x0;y0;w0;h0;0b;a);}
.vis.spotR:{[x0;y0;w0;h0;a] .vis.HOT,:(x0;y0;w0;h0;1b;a);}

/ does the current view own the keyboard (`capture in its state)? Checked by
/ key membership, not indexing: a missing-key lookup builds its null from the
/ state dict's first value, which throws 'par when that value is a
/ partitioned table (tabView's `t)
.vis.cap:{[]
  st:(last .vis.STACK)`state;
  $[`capture in key st; 1b~st`capture; 0b]}

/ hit-test a click against last frame's hotspots (one frame of lag);
/ r picks the button, last wins so overlays drawn later sit on top
.vis.hit:{[mx;my;r]
  a:exec act from .vis.HOT where rc=r, mx>=x, mx<x+w, my>=y, my<y+h;
  if[count a; (last a)(::)];}

/ context-menu overlay - one at a time; items are labels, acts are unary
/ functions. Opened by right-click spots (which call .vis.menu), closed by
/ any left click, esc, or choosing an item.
.vis.MENU:(); .vis.RCX:0; .vis.RCY:0;       / open menu + last right-click pos
.vis.menu:{[items;acts] .vis.MENU:`x`y`items`acts!(.vis.RCX;.vis.RCY;items;acts);}
.vis.menuDraw:{[mx;my]
  if[not count .vis.MENU; :(::)];
  m:.vis.MENU; its:m`items;
  w:14+max .vis.textWidth[.vis.FONT_PROP;] each its; h:4+12*count its;
  x0:0|(.vis.W-w)&m`x; y0:0|(.vis.H-25-h)&m`y;  / keep clear of the command bar
  .qvis.rect[x0+3;y0+3;w;h;.vis.SHADOW];        / drop shadow so the menu reads as floating
  .qvis.rect[x0;y0;w;h;.vis.BG];
  .qvis.line[x0;y0;x0+w;y0;.vis.BORD]; .qvis.line[x0;y0+h;x0+w;y0+h;.vis.BORD];
  .qvis.line[x0;y0;x0;y0+h;.vis.BORD]; .qvis.line[x0+w;y0;x0+w;y0+h;.vis.BORD];
  .vis.menuItem[x0;y0;w;mx;my]'[til count its;its;m`acts];}
.vis.menuItem:{[x0;y0;w;mx;my;i;s;a]
  y:y0+3+12*i;
  if[(mx within (x0;x0+w-1)) and my within (y-2;y+9); .qvis.rect[x0;y-2;w;12;.vis.HOVER]];
  .vis.drawText[x0+7;y;.vis.FONT_PROP;.qvis.white;s];
  .vis.spot[x0;y-2;w;12;{[a;e] .vis.MENU:(); a e}[a]];}

.vis.frame:{[]
  if[not .vis.RUN; :(::)];
  ev:.vis.poll[];
  if[ev`close; .vis.close[]; :(::)];
  if[ev`back; $[count .vis.MENU; .vis.MENU:(); .vis.pop[]]];  / esc closes an open menu first
  if[not count .vis.STACK; :(::)];
  / views with `capture (the REPL editor) own the keyboard; everyone else
  / gets the one-line command bar, which eats its keys before the view sees them
  bar:not .vis.cap[];
  if[bar; ev:.vis.cmdIn ev];
  if[not .vis.RUN; :(::)];                  / a command may have closed
  if[not count .vis.STACK; :(::)];
  if[ev`click;
    $[bar and (ev`my)>=.vis.H-25; .vis.cmdClick ev; .vis.hit[ev`mx;ev`my;0b]];
    .vis.MENU:()];                          / any left click closes the menu
  if[ev`rclick;
    .vis.RCX:ev`mx; .vis.RCY:ev`my; .vis.MENU:();
    .vis.hit[ev`mx;ev`my;1b]];
  if[not .vis.RUN; :(::)];                  / a hotspot action may have closed
  .vis.HOT:0#.vis.HOT;
  .qvis.clear .vis.BG;
  .vis.crumbs[];
  (last .vis.STACK)[`draw] ev;
  / re-test: a command may have pushed a different view this frame
  if[not .vis.cap[]; .vis.cmdDraw[]];
  .vis.menuDraw[ev`mx;ev`my];
  .qvis.present[];}

/ breadcrumb trail; clicking a crumb pops back to that view
.vis.crumbs:{[]
  nms:{string x`name} each .vis.STACK;
  ws:{.vis.textWidth[.vis.FONT_PROP;x]} each nms;
  xs:4+sums 0,-1_ws+12;
  .vis.crumb[count nms]'[til count nms;nms;xs;ws];}
.vis.crumb:{[n;i;nm;x0;wd]
  .vis.drawText[x0;4;.vis.FONT_PROP;$[i=n-1;.qvis.white;.qvis.gray];nm];
  if[i<n-1; .vis.drawText[x0+wd+3;4;.vis.FONT_PROP;.qvis.gray;">"]];
  .vis.spot[x0;2;wd;10;.vis.popTo[i]];}

/ shared scroll-offset update: arrows move on press, auto-repeat after ~1/3s
/ and accelerate on a long hold (big tables); page keys, wheel, home/end.
/ One global repeat counter is enough - only the top view scrolls.
.vis.SRC:0;
.vis.scroll:{[ev;page;mx;off]
  ks:(ev`new) inter `up`down;
  .vis.SRC:$[any `up`down in ev`held; 1+.vis.SRC; 0];
  if[.vis.SRC>10; ks:distinct ks,(ev`held) inter `up`down];
  stp:$[.vis.SRC>75; 25; 1];                / accelerate after ~2.5s hold
  off+:stp*(sum `down=ks)-sum `up=ks;
  if[`pagedown in ev`new; off+:page];
  if[`pageup in ev`new; off-:page];
  off-:3*ev`wheel;
  if[`home in ev`new; off:0];
  if[`end in ev`new; off:mx];
  0|off&mx}

/ ---------------------------------------------------------------------------
/ Pure helpers
/ ---------------------------------------------------------------------------
/ null or +-infinity - both break range/scale math (.vis.nice divides by the
/ span, so a single 0w in a series throws 'domain instead of just drawing)
.vis.bad:{(null x) or 0w=abs x}
.vis.finite:{x where not .vis.bad x}

/ scale a value (or vector) v in [lo;lo+rg] to a pixel y inside a y0..y0+ph
/ box, flipped so larger values sit higher on screen - shared by every chart
.vis.py:{[y0;ph;lo;rg;v] (y0+ph-1)-`long$(ph-1)*(v-lo)%rg}

/ index of the xs element closest to v - xss isn't guaranteed sorted (a
/ temporal column need not be), so this is a linear scan, not a binary search
.vis.nearest:{[xs;v] d:abs xs-v; d?min d}

.vis.r1:{string .01*"j"$100*x}
.vis.r2:{string .001*"j"$1000*x}

/ nice[lo;hi;n] - up to n+1 round tick values covering lo..hi
.vis.nice:{[lo;hi;n]
  lo:"f"$lo; hi:"f"$hi; if[lo=hi; hi:lo+1f];
  raw:(hi-lo)%n;
  mag:10 xexp floor 10 xlog raw;
  cand:mag*1 2 5 10f;
  step:first cand where cand>=raw;
  t0:step*ceiling lo%step;
  t0+step*til `long$1+floor (hi-t0)%step}

/ nicex[xt;lo;hi;n] - x-axis ticks; temporal types (xt is the meta type
/ char, " " = ordinal/numeric) snap to round time steps (1s 5s 1m 1h 1d ...)
/ instead of decimal ones. lo/hi are floats in the type's native units.
.vis.XSTEPS:1 2 5 10 15 30 60 120 300 600 900 1800 3600 7200 14400 21600 43200f,86400f*1 2 5 10 30 90 180 365 730 1825f;
.vis.XUPS:"pntvudz"!(1e9;1e9;1e3;1f;1%60;1%86400;1%86400);  / native units per second
.vis.nicex:{[xt;lo;hi;n]
  ups:.vis.XUPS xt;
  if[null ups; :.vis.nice[lo;hi;n]];
  if[lo=hi; hi:lo+1f];
  cand:ups*.vis.XSTEPS;
  step:first cand where cand>=(hi-lo)%n;
  if[null step; :.vis.nice[lo;hi;n]];      / span beyond the ladder (years)
  t0:step*ceiling lo%step;
  t0+step*til `long$1+floor (hi-t0)%step}

/ format one x tick: cast the float back to its temporal type; timestamps
/ show time-of-day inside a single-day span, the date beyond it
.vis.fmtx:{[xt;lo;hi;v]
  if[not xt in "pmdznuvt"; :.vis.fmtnum v];
  s:string xt$$[xt="z";v;"j"$v];
  $[xt in "pz"; $[(hi-lo)<$[xt="p";8.64e13;1f]; 8 sublist 11 _ s; 10 sublist s];
    xt="n"; 8 sublist 2_s;
    xt="t"; 8 sublist s;
    s]}

/ vertical grid lines + labels along the x axis
/ index) - exact placement would need per-point x coords in the render path
.vis.xticks:{[x0;y0;pw;ph;xt;xlo;xhi]
  if[any null (xlo;xhi); :(::)];
  tks:.vis.nicex[xt;xlo;xhi;5];
  .vis.xtick[x0;y0;pw;ph;xt;xlo;xhi] each tks where tks within (xlo;xhi);}
.vis.xtick:{[x0;y0;pw;ph;xt;xlo;xhi;v]
  px:x0+`long$(pw-1)*(v-xlo)%1e-9|xhi-xlo;
  .qvis.line[px;y0;px;y0+ph-1;.vis.GRID];
  s:.vis.fmtx[xt;xlo;xhi;v];
  w:.vis.textWidth[.vis.FONT_PROP;s];
  .vis.drawText[x0|(x0+pw-w)&px-w div 2;y0+ph+4;.vis.FONT_PROP;.qvis.gray;s];}

.vis.fmtnum:{ax:abs x:"f"$x;
  $[ax>=1e9;(.vis.r1 x%1e9),"B";ax>=1e6;(.vis.r1 x%1e6),"M";
    ax>=1e3;(.vis.r1 x%1e3),"K";.vis.r2 x]}
.vis.fmtb:{x:"f"$x;
  $[x>=1e9;(.vis.r1 x%1e9),"GB";x>=1e6;(.vis.r1 x%1e6),"MB";
    x>=1e3;(.vis.r1 x%1e3),"KB";(string"j"$x),"B"]}

/ table chunk -> list of columns of display strings
.vis.cells:{[t]
  {[c] 
    r: $[0h=type c; {$[10h=type x;x;.Q.s1 x]} each c; string c];
    $[(type r) in 10 -10h; enlist each r; r]
  } each value flip t}

/ pixel width per column from header + visible cell strings, 20-char cap
.vis.widths:{[hdrs;colz]
  $[.vis.FONT_PROP>=0;
    8+{max .vis.textWidth[.vis.FONT_PROP;] each x} each (enlist each hdrs),'{20 sublist' x} each colz;
    8+6*20&{max count each x} each (enlist each hdrs),'colz]}

/ wrap each line to w chars, preserving blank lines
.vis.wrap:{[w;lines] raze {[w;l] $[count l;(0N;w)#l;enlist l]}[w] each lines}

/ ---------------------------------------------------------------------------
/ Text view - scrollable lines; reused for function source and values
/ ---------------------------------------------------------------------------
.vis.openInEditor:{[fq]
  .vis.REPLB:.vis.srcLines fq;
  .vis.push .vis.replView[];}

.vis.txtView:{[nm;lines;fq] `name`draw`state!(nm;.vis.txtDraw;`off`lines`fq!(0;lines;fq))}

/ character-level syntax colorizer — works for both q and k code
/ returns a color list the same length as the input string
.vis.QKWS:`select`delete`update`from`where`by`exec`insert`upsert
.vis.charColors:{[s]
  n:count s;
  if[0=n; :()];
  colz:n#enlist .qvis.white;
  i:0;
  while[i<n;
    c:s i;
    $[c="\"";
      [j:i+1; while[(j<n) and not s[j]="\""; j+:$[s[j]="\\";2;1]];  / skip \" escapes
       colz[i+til (1+j-i)&n-i]:.qvis.magenta; i:j+1];
      c="`";
      [j:i+1; while[(j<n) and s[j] in "._",(.Q.a),(.Q.A),(.Q.n); j+:1];
       colz[i+til j-i]:.qvis.magenta; i:j];
      c in "{([;])}";
      [colz[i]:.qvis.gray; i+:1];
      c in "+-*%><~=@&#!_|?,^$'";
      [colz[i]:.qvis.cyan; i+:1];
      c="/";
      $[(i=0) or ((i>0) and s[i-1] in " \t");
        [colz[i+til n-i]:.qvis.gray; i:n];         / line comment — rest is gray
        [colz[i]:.qvis.cyan; i+:1]];               / division operator
      c="\\";
      $[(i=0) or ((i>0) and s[i-1] in " \t");
        [colz[i+til n-i]:.qvis.gray; i:n];         / system cmd — rest is gray
        [colz[i]:.qvis.cyan; i+:1]];               / adverb
      c in "0123456789";
      [j:i+1;                                / +- continue a number only after an exponent, so 1+2 isn't one green run
       while[(j<n) and (s[j] in "0123456789.eE") or (s[j] in "+-") and s[j-1] in "eE"; j+:1];
       colz[i+til j-i]:.qvis.green; i:j];
      c=":";
      [colz[i]:.qvis.yellow; i+:1];
      c in (.Q.a),(.Q.A),".";
      [j:i+1; while[(j<n) and s[j] in "._",(.Q.a),(.Q.A),(.Q.n); j+:1];
       w:`$s i+til j-i;
       if[w in .vis.QKWS; colz[i+til j-i]:.qvis.yellow];
       i:j];
      i+:1];                                 / default: advance
  ];
  colz}

.vis.qline:{[x0;y;s]
  if[0=count s; :(::)];
  colz:.vis.charColors s;
  ci:0;
  while[ci<count s;
    c:colz ci; j:ci;
    while[(j<count s) and colz[j]~c; j+:1];
    .vis.drawText[x0+.vis.textWidth[.vis.FONT_MONO; ci sublist s]; y; .vis.FONT_MONO; c; s ci+til j-ci];
    ci:j];}

.vis.txtDraw:{[ev]
  st:.vis.st[]; ls:st`lines; page:.vis.TROWS;
  off:.vis.scroll[ev;page;0|count[ls]-page;st`off]; .vis.put[`off;off];
  shown:page sublist off _ ls;
  .vis.qline[8]'[18+10*til count shown;shown];
  if[not (st`fq)~(::);
    .vis.drawText[8;.vis.H-35;.vis.FONT_PROP;.qvis.gray;(string count ls)," lines   click=edit   esc=back"];
    .vis.spot[8;.vis.H-38;120;14;{[fq;e] .vis.openInEditor fq}[st`fq]];
    if[`e in ev`new; .vis.openInEditor st`fq]];
  if[(st`fq)~(::);
    .vis.drawText[8;.vis.H-35;.vis.FONT_PROP;.qvis.gray;(string count ls)," lines  esc=back"]];}

.vis.srcLines:{[v]
  val:$[-11h=type v; @[get;v;{x}]; v];
  s:$[100h=type val; last value val; 10h=abs type val; val; .Q.s1 val];
  if[10h<>abs type s; s:.Q.s1 val];
  .vis.wrap[.vis.TXTC;"\n" vs s]}
.vis.valLines:{[fq] .vis.wrap[.vis.TXTC;"\n" vs -1_.Q.s get fq]}

/ ---------------------------------------------------------------------------
/ Table browser - lazy row fetch, so partitioned/splayed tables of any size
/ only ever read the visible window
/ ---------------------------------------------------------------------------
.vis.tab:{[t] .vis.open .vis.tabView[t;$[-11h=type t;t;`table]]}

.vis.tabView:{[t0;nm]
  v:$[-11h=type t0; get t0; t0];
  kc:keys v; if[count kc; v:0!v];
  mt:0!meta v;
  hdrs:{[c;tc;ik] (string c)," ",(enlist tc),$[ik;"*";""]}'[mt`c;mt`t;(mt`c) in kc];
  rf:$[-11h=type t0; (.vis.tabView;t0;nm); (::)];  / only named tables can re-get
  st:`t`n`nm`off`idx`srt`hdrs`cnames`c0`ck`ca`cc`refresh!
    (v;count v;nm;0;();(`;0b);hdrs;mt`c;0;(::);0;();rf);
  `name`draw`state!(nm;.vis.tabDraw;st)}

/ idx is a sort permutation (empty when unsorted); .Q.ind pages partitioned
/ tables, plain indexing covers in-memory and splayed
.vis.tabFetch:{[st;off;m]
  i:$[count st`idx; st[`idx] off+til m; off+til m];
  $[1b~.Q.qp st`t; .Q.ind[st`t;i]; st[`t] i]}

.vis.tabDraw:{[ev]
  st:.vis.st[]; n:st`n;
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  page:(ph-12) div 10;                      / rows that fit the box (38 at TBOX)
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  m:0|page&n-off;
  / cell cache: refetching + stringifying every frame is wasted work (and
  / disk reads on partitioned tables); rebuild on scroll/sort, and expire
  / after ~1s so live tables still refresh
  ck:(off;st`srt);
  fresh:(ck~st`ck) and 30>st`ca;
  .vis.put[`ca;$[fresh;1+st`ca;0]];
  colz:$[fresh; st`cc;
    [c:$[m>0; .vis.cells .vis.tabFetch[st;off;m]; count[st`hdrs]#enlist ()];
     .vis.put[`ck;ck]; .vis.put[`cc;c]; c]];
  / left/right page through columns that don't fit the box
  nc:count st`hdrs; c0:st`c0;
  if[`left in ev`new; c0:0|c0-1];
  if[`right in ev`new; c0:(0|nc-1)&c0+1];
  .vis.put[`c0;c0];
  ws:.vis.widths[st`hdrs;colz];
  cs:c0 _ til nc;
  xs:x0+sums 0,-1_ws cs;
  keep:where (xs+ws cs)<x0+pw;               / draw only columns that fit
  hv:.vis.hoverIx[ev`mx;ev`my;x0-4;y0+11;pw+8;10;m];
  if[hv>=0; .qvis.rect[x0-4;y0+11+10*hv;pw+8;10;.vis.HOVER]];
  .vis.tabCol[st;off;y0]'[xs keep;(ws cs)keep;(st[`hdrs]cs)keep;(st[`cnames]cs)keep;(colz cs)keep];
  {[x0;y0;pw;st;off;i] .vis.spot[x0-4;y0+11+10*i;pw+8;10;.vis.tabRow[st;off+i]]}
    [x0;y0;pw;st;off] each til m;
  s:.vis.tabFoot[st;off;m];
  if[(c0>0) or nc>count keep;
    s,:"  cols ",(string c0+1),"-",(string c0+count keep),"/",(string nc)," (left/right)"];
  .vis.drawText[x0;y0+ph;.vis.FONT_PROP;.qvis.gray;(pw div 6) sublist s];}  / clip to the box - a dash panel is narrower than the full window

/ click a row -> full record as "col: value" lines, untruncated
.vis.tabRow:{[st;r;e]
  d:first .vis.tabFetch[st;r;1];
  ls:{[d;k](string k),": ",.Q.s1 d k}[d] each key d;
  .vis.push .vis.txtView[`$"row ",string r;.vis.wrap[.vis.TXTC;ls];::];}

.vis.tabCol:{[st;off;y0;x0;w0;hdr;cn;cs]
  .vis.drawText[x0;y0;.vis.FONT_PROP;.qvis.yellow;hdr];
  .vis.spot[x0;y0-2;w0;11;.vis.tabSort cn];
  {[st;off;y0;cn;x0;w0;i;s]
    .vis.drawText[x0;y0+12+10*i;.vis.FONT_PROP;.qvis.white;20 sublist s];
    .vis.spotR[x0;y0+11+10*i;w0;10;.vis.cellMenu[st;cn;off+i]]}[st;off;y0;cn;x0;w0]
    '[til count cs;cs];}

/ right-click on a cell: copy / filter-by-value / inspect, plus plot for
/ numeric columns
.vis.cellMenu:{[st;cn;row;e]
  d:first .vis.tabFetch[st;row;1]; v:d cn;
  its:("copy value";"filter ",(string cn),"=",12 sublist .Q.s1 v;"inspect row");
  acts:({[v;e] .qvis.setclip .Q.s1 v}[v];.vis.cellFilter[st;cn;v];.vis.tabRow[st;row]);
  if[abs[type v] within 5 9h;
    its,:enlist "plot ",string cn; acts,:enlist .vis.colPlot[st;cn]];
  .vis.menu[its;acts];}

.vis.cellFilter:{[st;cn;v;e]
  cond:$[10h=type v; ({x~\:y};cn;v);
    0h>type v; (=;cn;$[-11h=type v;enlist v;v]);
    ()];                                    / nested cells: no clean where-clause
  .vis.RES:$[()~cond; "'filter: unsupported cell type";
    .vis.tabFilterC[st;enlist enlist cond;`$"/",(string cn),"=",12 sublist .Q.s1 v]];}

/ plot one column; shares the .vis.MAXSORT cap (it materialises the column)
.vis.colPlot:{[st;cn;e]
  $[.vis.MAXSORT<st`n;
    .vis.RES:"'plot: ",(.vis.fmtnum st`n)," rows > .vis.MAXSORT";
    .vis.push .vis.plotView[enlist string cn;enlist "f"$.vis.col[st`t;cn];
      enlist "f"$til st`n;" ";0f;"f"$0|-1+st`n]];}

/ sort = one iasc/idesc permutation kept in state; the table itself is never
/ copied, so the same path serves in-memory, splayed and partitioned tables
/ caps it - chunked external sort only if a db column ever outgrows RAM
.vis.MAXSORT:50000000;                      / max rows to sort/plot a column of
.vis.col:{[t;c] ?[t;();0b;(enlist c)!enlist c] c}
.vis.sortIdx:{[t;c;up] $[up;iasc;idesc] .vis.col[t;c]}
.vis.tabSort:{[c;e]
  st:.vis.st[];
  if[.vis.MAXSORT<st`n;
    .vis.RES:"'sort: ",(.vis.fmtnum st`n)," rows > .vis.MAXSORT (",
      (.vis.fmtnum .vis.MAXSORT),") - raise it to sort anyway"; :(::)];
  up:not (c;1b)~st`srt;
  .vis.put[`idx;.vis.sortIdx[st`t;c;up]];
  .vis.put[`srt;(c;up)];
  .vis.put[`off;0];}

.vis.tabFoot:{[st;off;m]
  s:"rows ",(.vis.fmtnum st`n),"  ",(string off+$[m>0;1;0]),"-",string off+m;
  if[not null first st`srt;
    s,:"  sort ",(string first st`srt),$[last st`srt;" asc";" desc"]];
  s,"  header=sorts   row=inspects   esc=back"}

/ ---------------------------------------------------------------------------
/ Namespace explorer
/ ---------------------------------------------------------------------------
.vis.ns:{[] .vis.open .vis.nsView `.}
.vis.nsView:{[path]
  `name`draw`state!(path;.vis.nsDraw;
    `path`off`rows`refresh!(path;0;.vis.nsList path;(.vis.nsView;path)))}

/ -22! serialized size is a cheap proxy, skipped for mapped values and
/ anything over .vis.SZMAX items (serialising is O(n) per refresh)
.vis.SZMAX:1000000;
.vis.nsList:{[path]
  fqs:$[path~`.;
    ((key `.) except 1#`),{`$".",string x} each (key `);
    {`$(string x),".",string y}[path] each (key path) except 1#`];
  if[not count fqs; :([]fq:0#`;kind:0#`;tp:0#0h;cnt:0#0N;sz:0#0N)];
  info:.vis.nsInfo each fqs;
  r:`fq xasc ([]fq:fqs;kind:info[;0];tp:info[;1];cnt:info[;2];sz:info[;3]);
  r iasc (`ns`table`dict`fn`var!til 5) r`kind}

.vis.nsInfo:{[fq]
  val:@[get;fq;{[e](::)}];
  tp:type val;
  isns:$[99h=tp; $[11h=type key val; null first key val; 0b]; 0b];
  kind:$[.Q.qt val;`table; isns;`ns; 99h=tp;`dict; tp>=100h;`fn; `var];
  cnt:$[kind=`fn;0N; kind=`ns;-1+count val; 0h>tp;1; @[count;val;0N]];
  mapped:$[kind=`table; any 01b~\:.Q.qp val; 0b];
  sz:$[mapped or cnt>.vis.SZMAX; 0N; @[{-22!x};val;0N]];
  (kind;tp;`long$cnt;`long$sz)}

.vis.nsDraw:{[ev]
  st:.vis.st[]; rows:st`rows; n:count rows; page:.vis.TROWS;
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  .vis.drawText[8;18;.vis.FONT_PROP;.qvis.yellow;"name"]; .vis.drawText[360;18;.vis.FONT_PROP;.qvis.yellow;"kind"];
  .vis.drawText[430;18;.vis.FONT_PROP;.qvis.yellow;"type"]; .vis.drawText[490;18;.vis.FONT_PROP;.qvis.yellow;"count"];
  .vis.drawText[570;18;.vis.FONT_PROP;.qvis.yellow;"size"];
  shown:page sublist off _ rows;
  hv:.vis.hoverIx[ev`mx;ev`my;4;29;630;10;count shown];
  if[hv>=0; .qvis.rect[4;29+10*hv;630;10;.vis.HOVER]];
  .vis.nsRow'[til count shown;shown];
  .vis.drawText[8;.vis.H-35;.vis.FONT_PROP;.qvis.gray;
    (string n)," entries   click=open   esc=back/quit"];}

.vis.nsRow:{[i;r]
  y:30+10*i;
  col:(`ns`table`dict`var`fn!(.qvis.yellow;.qvis.cyan;.qvis.magenta;.qvis.white;.qvis.green)) r`kind;
  fqstr: string r`fq;
  if[(type fqstr)=-10h; fqstr: enlist fqstr];
  .vis.drawText[8;y;.vis.FONT_PROP;col;56 sublist fqstr];
  .vis.drawText[360;y;.vis.FONT_PROP;.qvis.gray;string r`kind];
  .vis.drawText[430;y;.vis.FONT_PROP;.qvis.gray;string r`tp];
  if[not null r`cnt; .vis.drawText[490;y;.vis.FONT_PROP;.qvis.gray;.vis.fmtnum r`cnt]];
  if[not null r`sz; .vis.drawText[570;y;.vis.FONT_PROP;.qvis.gray;.vis.fmtb r`sz]];
  .vis.spot[4;y-1;630;10;.vis.nsAct[r`fq;r`kind]];
  .vis.spotR[4;y-1;630;10;.vis.nsMenu r];}

.vis.nsMenu:{[r;e]
  opts:("open";"copy name");
  acts:(.vis.nsAct[r`fq;r`kind];{[fq;e] .qvis.setclip string fq}[r`fq]);
  if[r[`kind] in `fn`var;
    opts,:enlist "open in editor";
    acts,:enlist {[fq;e] .vis.openInEditor fq}[r`fq]];
  .vis.menu[opts;acts];}

.vis.nsAct:{[fq;kind;e]
  $[kind=`ns; .vis.push .vis.nsView fq;
    kind=`table; .vis.push .vis.tabView[fq;fq];
    kind=`fn; .vis.push .vis.txtView[fq;.vis.srcLines fq;fq];
    .vis.push .vis.txtView[fq;.vis.valLines fq;fq]];}

/ ---------------------------------------------------------------------------
/ Plots
/ ---------------------------------------------------------------------------
/ downsample to <=2*pw points: min and max of each pixel bucket, so a single
/ spike in a million points still shows instead of falling between samples
/ downsample by real x position (not row index) into <=pw pixel-wide buckets:
/ each populated bucket keeps min and max y (so a spike still shows) at its
/ bucket's own x - which is already the right pixel column, no re-spacing
.vis.dsampxy:{[pw;xlo;xrg;xs;ser]
  n:count ser; if[n<=pw; :(xs;ser)];
  bi:`long$(pw-1)&0|floor (xs-xlo)*pw%xrg;
  g:group bi; bx:asc key g;
  mnmx:{(min x;max x)} each ser each g bx;
  bxs:xlo+xrg*bx%pw;
  (raze bxs,'bxs; raze mnmx)}

/ filter bad x/y, patch null y via fill, sort by x, downsample by x-bucket -
/ the pure pipeline behind .vis.plotline, split out so it's smoke-testable
/ without a window (unlike plotline itself, which calls .qvis.line)
.vis.plotPrep:{[pw;xlo;xrg;xs;ser]
  xs:"f"$xs; ser:"f"$ser; n:count ser; if[n<2; :(::)];
  ser:reverse fills reverse fills ser;      / patch interior/leading nulls
  ok:where not (.vis.bad xs) or .vis.bad ser;  / drop bad x, still-null/inf y -
                                             / where turns the mask into index
                                             / positions; indexing by the raw
                                             / boolean itself would use its 0/1
                                             / values as positions, not a filter
  xs:xs ok; ser:ser ok; n:count ser;
  if[n<2; :(::)];                           / all-null/bad series: nothing to draw
  ix:iasc xs; xs:xs ix; ser:ser ix;         / x need not arrive pre-sorted
  .vis.dsampxy[pw;xlo;xrg;xs;ser]}

/ scale a series into a box against explicit x/y ranges and draw it; points
/ are placed by their real x value (not row index), so unevenly spaced time
/ series and series of different lengths land at their true position instead
/ of all stretching to fill the same width.
/ box=(x0;y0;pw;ph), xrng=(xlo;xhi), yrng=(lo;hi) - bundled since q lambdas
/ cap out at 8 explicit params
.vis.FILLA:40;                              / area-under-line / bar fill alpha (0-255)
.vis.plotline:{[box;xrng;yrng;xs;ser;col]
  x0:box 0; y0:box 1; pw:box 2; ph:box 3; xlo:xrng 0; xhi:xrng 1; lo:yrng 0; hi:yrng 1;
  xrg:1e-9|xhi-xlo;
  xy:.vis.plotPrep[pw;xlo;xrg;xs;ser]; if[(::)~xy; :(::)];
  xs:xy 0; ser:xy 1;
  px:x0+`long$(pw-1)*(xs-xlo)%xrg;
  py:.vis.py[y0;ph;lo;1e-9|hi-lo;ser];
  base:y0+ph-1;                             / plot floor - the shaded area's baseline
  .qvis.polygon[px,(last px;first px);py,base,base;.qvis.fade[.vis.FILLA;col]];
  .qvis.line'[-1_px;-1_py;1_px;1_py;col];}

.vis.axes:{[x0;y0;pw;ph;lo;hi]
  .qvis.line[x0;y0;x0;y0+ph;.vis.BORD]; .qvis.line[x0;y0+ph;x0+pw;y0+ph;.vis.BORD];
  .vis.tick[x0;y0;pw;ph;lo;hi] each tks where (tks:.vis.nice[lo;hi;4]) within (lo;hi);}
.vis.tick:{[x0;y0;pw;ph;lo;hi;v]
  y:.vis.py[y0;ph;lo;1e-9|hi-lo;v];
  .qvis.line[x0+1;y;x0+pw;y;.vis.GRID];
  .vis.drawText[x0-.vis.YLGUT;y-3;.vis.FONT_PROP;.qvis.gray;8 sublist .vis.fmtnum v];}

.vis.plot:{[x]
  $[.Q.qt x; .vis.plotTbl x;
    0h=type x;
      .vis.open .vis.plotView[{"s",string x} each 1+til count x;"f"$'x;
        {"f"$til count x} each x;" ";0f;"f"$-1+max count each x];
    .vis.open .vis.plotView[enlist "y";enlist "f"$x;enlist "f"$til count x;
      " ";0f;"f"$-1+count x]]}

/ plot state from a table: numeric columns are series, the first temporal
/ column (if any) supplies both the x-axis range and each series' real x
/ position (so irregular time spacing renders correctly, not index-uniform)
.vis.plotState:{[t]
  if[count keys t; t:0!t]; mt:0!meta t;
  xi:first where (mt`t) in "pmdznuvt";
  yc:(mt`c) where (mt`t) in "hijfe";
  if[not count yc; '`$"no numeric columns"];
  xt:" "; xlo:0f; xhi:"f"$0|-1+count t; xc:"f"$til count t;
  / min/max, not first/last - the time column need not be sorted
  if[not null xi;
    xc:"f"$t (mt`c) xi; xt:(mt`t) xi;
    xcf:.vis.finite xc; xlo:$[count xcf;min xcf;0f]; xhi:$[count xcf;max xcf;1f]];
  `nms`ys`xss`xt`xlo`xhi!
    (string each yc;{[t;c]"f"$t c}[t] each yc;count[yc]#enlist xc;xt;xlo;xhi)}

.vis.plotTbl:{[t] .vis.open `name`draw`state!(`plot;.vis.plotDraw;.vis.plotState t)}

/ nms/ys = series names and vectors; xss = parallel x-value vectors (one per
/ series - real x placement, not row index); xt/xlo/xhi = x type char (" " =
/ ordinal index) and range, used only for the tick grid - see .vis.xticks
.vis.plotView:{[nms;ys;xss;xt;xlo;xhi]
  `name`draw`state!(`plot;.vis.plotDraw;`nms`ys`xss`xt`xlo`xhi!(nms;ys;xss;xt;xlo;xhi))}

.vis.plotDraw:{[ev]
  st:.vis.st[]; ys:st`ys; nms:st`nms; xss:st`xss;
  bx:.vis.boxOr[st;.vis.BOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  allv:.vis.finite raze ys;
  if[not count allv; .vis.drawText[x0;y0;.vis.FONT_PROP;.qvis.red;"no data"]; :(::)];
  lo:min allv; hi:max allv; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  .vis.xticks[x0;y0;pw;ph;st`xt;st`xlo;st`xhi];
  .vis.plotline[(x0;y0;pw;ph);(st`xlo;st`xhi);(lo;hi)]'
    [xss;ys;.vis.PAL til[count ys] mod count .vis.PAL];
  {[x0;pw;y0;i;nm;c] .vis.drawText[x0+pw-144;y0+10*i;.vis.FONT_PROP;c;16 sublist nm]}[x0;pw;y0]
    '[til count nms;nms;.vis.PAL til[count nms] mod count .vis.PAL];
  / crosshair + nearest-point readout per series while hovering the plot area
  mx:ev`mx; my:ev`my;
  if[(mx within (x0;x0+pw-1)) and my within (y0;y0+ph-1);
    .qvis.line[mx;y0;mx;y0+ph-1;.qvis.fade[80;.qvis.red]];
    .qvis.line[x0;my;x0+pw-1;my;.qvis.fade[80;.qvis.red]];
    xv:st[`xlo]+(st[`xhi]-st`xlo)*(mx-x0)%pw-1;
    tx:(x0+pw-90)&mx+6;
    .vis.drawText[tx;y0+2;.vis.FONT_PROP;.qvis.gray;.vis.fmtx[st`xt;st`xlo;st`xhi;xv]];
    {[tx;y0;xv;i;nm;xs;ser;c]
      if[count xs; j:.vis.nearest["f"$xs;xv];
        .vis.drawText[tx;y0+12+10*i;.vis.FONT_PROP;c;nm,": ",.vis.fmtnum ser j]]
      }[tx;y0;xv]'[til count nms;nms;xss;ys;.vis.PAL til[count nms] mod count .vis.PAL]];}

/ bin a numeric vector into `mn`rg`c (min, range, per-bin counts) - shared by
/ the standalone .vis.hist and the watch/dash `hist kind (.vis.histState)
.vis.histBin:{[x;bins]
  x:.vis.finite "f"$x;
  if[not count x; '`$"no data"];
  mn:min x; rg:1e-9|max[x]-mn;
  c:@[bins#0;`long$(bins-1)&floor bins*(x-mn)%rg;+;1];
  `mn`rg`c!(mn;rg;c)}

.vis.hist:{[x;bins] .vis.open `name`draw`state!(`hist;.vis.histDraw;.vis.histBin[x;bins])}

/ hist/bar as watch/dash kinds: state builder takes the fetched table and
/ picks columns automatically (first numeric column; first symbol/string
/ column as labels, for bar)
.vis.HISTBINS:40;
.vis.histState:{[t]
  if[count keys t; t:0!t]; mt:0!meta t;
  yc:first (mt`c) where (mt`t) in "hijfe";
  if[null yc; '`$"no numeric columns"];
  .vis.histBin["f"$t yc;.vis.HISTBINS]}

.vis.histDraw:{[ev]
  st:.vis.st[]; c:st`c; bins:count c;
  bx:.vis.boxOr[st;.vis.BOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  .vis.axes[x0;y0;pw;ph;0f;"f"$mx:1|max c];
  .vis.hbar[x0;y0;ph;1|pw div bins;mx]'[til bins;c];
  .vis.drawText[x0;y0+ph+4;.vis.FONT_PROP;.qvis.gray;.vis.fmtnum st`mn];
  s:.vis.fmtnum st[`mn]+st`rg;
  .vis.drawText[(x0+pw)-.vis.textWidth[.vis.FONT_PROP;s];y0+ph+4;.vis.FONT_PROP;.qvis.gray;s];}
.vis.hbar:{[x0;y0;ph;bw;mx;i;c]
  h:`long$(ph-2)*c%mx;
  .qvis.rect[x0+1+i*bw;(y0+ph-1)-h;1|bw-1;h;.qvis.fade[200;.qvis.cyan]];}

.vis.scatter:{[xx;yy]
  xt:.Q.t abs type xx;
  xx:"f"$xx; yy:"f"$yy;
  ok:where not (.vis.bad xx) or .vis.bad yy;
  xx:xx ok; yy:yy ok;
  if[not count xx; '`$"no data"];
  .vis.open `name`draw`state!(`scatter;.vis.scatDraw;`xx`yy`xt!(xx;yy;xt))}

.vis.scatDraw:{[ev]
  st:.vis.st[]; xx:st`xx; yy:st`yy; xt:st`xt;
  bx:.vis.boxOr[st;.vis.BOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  ylo:min yy; yhi:max yy; if[ylo=yhi; yhi:ylo+1f];
  xlo:min xx; xhi:max xx; if[xlo=xhi; xhi:xlo+1f];
  .vis.axes[x0;y0;pw;ph;ylo;yhi];
  .vis.xticks[x0;y0;pw;ph;xt;xlo;xhi];
  / translucent fill - overlapping points compound into a brighter, denser
  / patch instead of one flat opaque smear, so clusters read at a glance
  .qvis.rect'[x0+1+`long$(pw-4)*(xx-xlo)%xhi-xlo;
        (y0+ph-3)-`long$(ph-4)*(yy-ylo)%yhi-ylo;2;2;.qvis.fade[110;.qvis.cyan]];
  / crosshair + data-space readout while the mouse is over the plot area
  mx:ev`mx; my:ev`my;
  if[(mx within (x0;x0+pw-1)) and my within (y0;y0+ph-1);
    .qvis.line[mx;y0;mx;y0+ph-1;.qvis.fade[80;.qvis.red]];
    .qvis.line[x0;my;x0+pw-1;my;.qvis.fade[80;.qvis.red]];
    xv:xlo+(xhi-xlo)*(mx-x0)%pw-1; yv:ylo+(yhi-ylo)*((y0+ph-1)-my)%ph-1;
    s:(.vis.fmtx[xt;xlo;xhi;xv]),", ",.vis.fmtnum yv;
    w:.vis.textWidth[.vis.FONT_PROP;s];
    .vis.drawText[0|(x0+pw-w)&mx+6;(y0+2)|my-10;.vis.FONT_PROP;.qvis.gray;s]];}

/ ---------------------------------------------------------------------------
/ Candlestick - .vis.candle t where t has open/high/low/close columns; a
/ temporal column (if any) drives the x-axis ticks. More candles than fit
/ the width are bucketed OHLC-style (first/max/min/last) so shape survives.
/ ---------------------------------------------------------------------------
.vis.obucket:{[nb;o;h;l;c]
  if[nb>=n:count o; :(o;h;l;c)];
  g:value group floor (til n)*nb%n;
  (o first each g;max each h g;min each l g;c last each g)}

.vis.candleState:{[t]
  if[count keys t; t:0!t];
  if[not all `open`high`low`close in cols t; '`$"need open/high/low/close columns"];
  mt:0!meta t;
  xi:first where (mt`t) in "pmdznuvt";
  xt:" "; xlo:0f; xhi:"f"$0|-1+count t;
  if[not null xi;
    xc:.vis.finite "f"$t (mt`c) xi; xt:(mt`t) xi;
    xlo:$[count xc;min xc;0f]; xhi:$[count xc;max xc;1f]];
  `o`h`l`c`xt`xlo`xhi!("f"$t`open;"f"$t`high;"f"$t`low;"f"$t`close;xt;xlo;xhi)}

.vis.candle:{[t] .vis.open `name`draw`state!(`candle;.vis.candleDraw;.vis.candleState t)}

.vis.candleDraw:{[ev]
  st:.vis.st[];
  bx:.vis.boxOr[st;.vis.BOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  ohlc:.vis.obucket[pw div 5;st`o;st`h;st`l;st`c];
  n:count first ohlc;
  lo2:.vis.finite ohlc 2; hi2:.vis.finite ohlc 1;
  if[(0=n) or (not count lo2) or not count hi2;
    .vis.drawText[x0;y0;.vis.FONT_PROP;.qvis.red;"no data"]; :(::)];
  lo:min lo2; hi:max hi2; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  .vis.xticks[x0;y0;pw;ph;st`xt;st`xlo;st`xhi];
  py:.vis.py[y0;ph;lo;1e-9|hi-lo];
  .vis.candle1[x0;pw div n;py]'[til n;ohlc 0;ohlc 1;ohlc 2;ohlc 3];
  / crosshair + data-space readout while the mouse is over the plot area
  mx:ev`mx; my:ev`my;
  if[(mx within (x0;x0+pw-1)) and my within (y0;y0+ph-1);
    .qvis.line[mx;y0;mx;y0+ph-1;.qvis.fade[80;.qvis.red]];
    .qvis.line[x0;my;x0+pw-1;my;.qvis.fade[80;.qvis.red]];
    xv:st[`xlo]+(st[`xhi]-st`xlo)*(mx-x0)%pw-1;
    yv:lo+(hi-lo)*((y0+ph-1)-my)%ph-1;
    bw:pw div n;
    s:$[(bw>0) and (i:(mx-x0) div bw) within (0;n-1);
      (.vis.fmtx[st`xt;st`xlo;st`xhi;xv]),"  O:",(.vis.fmtnum ohlc[0]i)," H:",(.vis.fmtnum ohlc[1]i)," L:",(.vis.fmtnum ohlc[2]i)," C:",(.vis.fmtnum ohlc[3]i);
      (.vis.fmtx[st`xt;st`xlo;st`xhi;xv]),", ",.vis.fmtnum yv];
    w:.vis.textWidth[.vis.FONT_PROP;s];
    .vis.drawText[0|(x0+pw-w)&mx+6;(y0+2)|my-10;.vis.FONT_PROP;.qvis.gray;s]];}
.vis.candle1:{[x0;bw;py;i;o;h;l;c]
  col:$[c>=o;.qvis.green;.qvis.red];
  xm:x0+(i*bw)+bw div 2;
  .qvis.line[xm;py h;xm;py l;col];              / wick
  wb:1|25&bw-2; yt:py o|c;
  .qvis.rect[xm-wb div 2;yt;wb;1|1+(py o&c)-yt;col];}  / body

/ ---------------------------------------------------------------------------
/ Bar chart - .vis.bar[labels;values]; bars grow from a zero baseline so
/ negative values hang below it. Labels truncate to the bar width.
/ ---------------------------------------------------------------------------
.vis.bar:{[x;y]
  y:"f"$y; if[not count y; '`$"no data"];
  lbl:{$[10h=abs type x;(),x;string x]} each x;
  .vis.open `name`draw`state!(`bar;.vis.barDraw;`lbl`v!(lbl;y))}

.vis.barState:{[t]
  if[count keys t; t:0!t]; mt:0!meta t;
  yc:first (mt`c) where (mt`t) in "hijfe";
  if[null yc; '`$"no numeric columns"];
  li:first where (mt`t) in "sC";
  lbl:$[null li; string til count t;
    {$[10h=abs type x;(),x;string x]} each t (mt`c) li];
  `lbl`v!(lbl;"f"$t yc)}

.vis.barDraw:{[ev]
  st:.vis.st[]; v:st`v; n:count v;
  bx:.vis.boxOr[st;.vis.BOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  lo:min 0f,.vis.finite v; hi:max 0f,.vis.finite v; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  py:.vis.py[y0;ph;lo;1e-9|hi-lo];
  .vis.bar1[st;py;x0;1|pw div n;y0+ph]'[til n;v];}
.vis.bar1:{[st;py;x0;bw;yl;i;x]
  yv:py x; yz:py 0f;
  .qvis.rect[x0+1+i*bw;yv&yz;1|bw-2;1|1+abs yv-yz;.qvis.fade[200;$[x<0;.qvis.red;.qvis.cyan]]];
  s:(bw div 6) sublist st[`lbl] i;
  if[count s; .vis.drawText[x0+1+i*bw;yl+4;.vis.FONT_PROP;.qvis.gray;s]];}

/ ---------------------------------------------------------------------------
/ Dashboard - .vis.dash panels tiles several live views into one window.
/ panels is a list of (kind;src;cell) or (kind;src;cell;ms) tuples:
/   kind - one of .vis.WKIND (`plot`candle`tab`hist`bar)
/   src  - anything .vis.wfetch accepts: a table name, a nullary function
/          (called each refresh - a poor man's feed), or a table value
/   cell - (col;row;colspan;rowspan) on a grid sized to fit every panel
/   ms   - refresh interval in ms (default 1000)
/ Panels are display-only - click (or right-click) one to zoom into a full
/ live .vis.watchAs view of it, with all the usual interactivity (sort,
/ filter, command bar); esc returns to the dashboard grid. Example:
/   .vis.dash ((`plot;`sensors;0 0 2 1);
/     (`candle;{select from daily where sym=`AAPL};0 1 1 1);
/     (`tab;`trade;1 1 1 1;500))
/ only the top of the view stack ever redraws, so if one panel's src
/ advances a feed and others merely read the result, those readers go
/ static the instant you zoom into any panel but the driver - give every
/ panel that should look live its own src that advances things itself
/ (see examples/exampleDashboard.q)
/ ---------------------------------------------------------------------------
.vis.dash:{[panels] .vis.open .vis.dashView panels}

.vis.dashNorm:{[spec] {$[4=count x;x;x,1000]} each spec}  / default ms=1000

.vis.GUT:4; .vis.DTITLE:12;                  / panel gutter / title-strip height
.vis.dashArea:{[] (4;16;.vis.W-8;.vis.H-41)}  / content area below crumbs, above cmd bar

/ pixel `outer`box rect per panel from its (col;row;colspan;rowspan) cell -
/ outer is the bordered tile, box is what's left for the kind's own draw fn
/ after the title strip; pure, so testable without a window
.vis.dashBoxes:{[spec]
  panels:.vis.dashNorm spec; cells:panels[;2];
  ncols:max {x[0]+x[2]} each cells; nrows:max {x[1]+x[3]} each cells;
  ar:.vis.dashArea[]; x0:ar 0; y0:ar 1; aw:ar 2; ah:ar 3;
  cw:aw div ncols; ch:ah div nrows;
  {[x0;y0;cw;ch;cell]
    ox:x0+cell[0]*cw; oy:y0+cell[1]*ch; ow:cell[2]*cw-.vis.GUT; oh:cell[3]*ch-.vis.GUT;
    / box.x0 reserves .vis.YLGUT on its left so a chart's y-axis labels land
    / inside this panel's own tile instead of bleeding into its left neighbour
    `outer`box!((ox;oy;ow;oh);(ox+.vis.YLGUT;oy+.vis.DTITLE;ow-.vis.YLGUT-2;oh-.vis.DTITLE-4))
  }[x0;y0;cw;ch] each cells}

/ build (or rebuild) one panel's kind-state; errors are trapped and returned
/ as a symbol atom `$"'msg" instead of the usual dict, so a bad panel shows
/ red text instead of taking the whole dashboard down
.vis.dashBuild:{[k;src]
  @[{[a] .vis.WKIND[a 0][0] .vis.wfetch a 1};(k;src);{`$"'",x}]}

.vis.dashInit:{[k;src;ms;box;outer]
  vst:.vis.dashBuild[k;src];
  if[99h=type vst; vst[`box]:box];
  `kind`src`ms`lp`box`outer`vst!(k;src;ms;.z.P;box;outer;vst)}

/ per-panel refresh: rebuild the kind-state once ms has elapsed (same cadence
/ rule as .vis.watchDraw), otherwise pass the panel through unchanged
.vis.dashTick:{[pnl]
  if[(pnl`ms)>("j"$.z.P-pnl`lp)%1e6; :pnl];
  vst:.vis.dashBuild[pnl`kind;pnl`src];
  if[99h=type vst; vst[`box]:pnl`box];
  pnl[`vst]:vst; pnl[`lp]:.z.P; pnl}

/ draw one panel's border+title, then its kind's own draw fn pointed at the
/ panel's state via .vis.STO; click or right-click anywhere on the panel
/ zooms into a full live view of it (shadowing the kind's own hotspots, which
/ are registered first and so lose the "last wins" hit-test in .vis.hit)
.vis.dashPanelDraw:{[ev;pnl]
  ob:pnl`outer; ox:ob 0; oy:ob 1; ow:ob 2; oh:ob 3;
  if[(ev[`mx] within (ox;ox+ow-1)) and ev[`my] within (oy;oy+oh-1);
    .qvis.rect[ox;oy;ow;oh;.vis.HOVER]];   / tint the whole tile - hints it's clickable to zoom
  .qvis.line[ox;oy;ox+ow;oy;.vis.BORD]; .qvis.line[ox;oy+oh;ox+ow;oy+oh;.vis.BORD];
  .qvis.line[ox;oy;ox;oy+oh;.vis.BORD]; .qvis.line[ox+ow;oy;ox+ow;oy+oh;.vis.BORD];
  .vis.drawText[ox+3;oy+2;.vis.FONT_PROP;.qvis.gray;string pnl`kind];
  vst:pnl`vst;
  $[99h<>type vst;
    .vis.drawText[ox+3;oy+16;.vis.FONT_PROP;.qvis.red;(1|(ow-6) div 6) sublist string vst];
    [.vis.STO:vst;
     @[.vis.WKIND[pnl`kind][1];ev;{[e] -1"[qVis] dash panel error: ",e}];
     pnl[`vst]:.vis.STO; .vis.STO:(::)]];
  act:{[src;ms;k;e] .vis.push .vis.watchView[src;ms;k]}[pnl`src;pnl`ms;pnl`kind];
  .vis.spot[ox;oy;ow;oh;act]; .vis.spotR[ox;oy;ow;oh;act];
  pnl}

.vis.dashView:{[spec]
  panels:.vis.dashNorm spec; bx:.vis.dashBoxes spec;
  pnls:{[k;src;ms;b] .vis.dashInit[k;src;ms;b`box;b`outer]}
    '[panels[;0];panels[;1];panels[;3];bx];
  `name`draw`state!(`dash;.vis.dashDraw;`spec`pnls`refresh!(spec;pnls;(.vis.dashView;spec)))}

.vis.dashDraw:{[ev]
  pnls:(.vis.st[])`pnls;
  pev:ev; pev[`new]:0#`; pev[`held]:0#`; pev[`click]:0b; pev[`rclick]:0b;
  pev[`wheel]:0; pev[`text]:"";             / panels get mx/my only - no keys/clicks/wheel
  pnls:.vis.dashTick each pnls;
  pnls:.vis.dashPanelDraw[pev]'[pnls];
  .vis.put[`pnls;pnls];}

/ ---------------------------------------------------------------------------
/ Watch - live-updating views: .vis.watch[`trade;1000] replots the newest
/ .vis.WROWS rows every 1000ms; .vis.watchAs[t;ms;kind] picks the view -
/ `plot (default), `candle, or `tab (a follow-the-tail table browser).
/ t is a table name (re-fetched each cycle so appends show up) or a nullary
/ function returning a table (called each cycle - a poor man's feed).
/ ---------------------------------------------------------------------------
.vis.WROWS:10000;                           / tail rows fetched per refresh
.vis.wfetch:{[t]
  v:$[-11h=type t; get t; 100h<=type t; t[]; t];
  if[count keys v; v:0!v];                 / keyed result (e.g. select ... by sym) - row
                                             / position indexing below needs it unkeyed
  n:count v; i:(n-m)+til m:.vis.WROWS&n;
  $[1b~.Q.qp v; .Q.ind[v;i]; v i]}

/ `tab kind: browser state on the tail, scroll pinned to the newest rows -
/ a graphical tail -f
.vis.tailState:{[t]
  st:(.vis.tabView[t;`tail])`state;
  st[`off]:0|st[`n]-.vis.TROWS;
  st}

/ kind -> (state builder applied to the fetched tail; draw fn)
/ kind -> (state builder; draw fn) - shared by .vis.watch and .vis.dash
.vis.WKIND:`plot`candle`tab`hist`bar!(
  (.vis.plotState;.vis.plotDraw);
  (.vis.candleState;.vis.candleDraw);
  (.vis.tailState;.vis.tabDraw);
  (.vis.histState;.vis.histDraw);
  (.vis.barState;.vis.barDraw));

/ view dict for a live watch, without opening it - .vis.watchAs opens this;
/ a dashboard panel pushes the same thing when clicked to zoom in
.vis.watchView:{[t;ms;k]
  if[not k in key .vis.WKIND;
    '`$"watch: kind must be one of ",", " sv string key .vis.WKIND];
  `name`draw`state!(`$"watch-",string k;.vis.watchDraw;
    (.vis.WKIND[k][0] .vis.wfetch t),`wt`ms`lp`wk!(t;ms;.z.P;k))}

.vis.watch:{[t;ms] .vis.watchAs[t;ms;`plot]}
.vis.watchAs:{[t;ms;k] .vis.open .vis.watchView[t;ms;k]}

/ every frame: re-fetch + rebuild the kind's state once ms have elapsed,
/ then hand the frame to the kind's draw fn as if it were a plain view
.vis.watchDraw:{[ev]
  st:.vis.st[];
  if[(st`ms)<=(("j"$.z.P-st`lp)%1e6);
    st:st,.vis.WKIND[st`wk][0] .vis.wfetch st`wt; st[`lp]:.z.P;
    .vis.putAll st];
  .vis.WKIND[st`wk][1] ev;
  .vis.drawText[.vis.W-90;4;.vis.FONT_PROP;.qvis.gray;"watch ",(string st`ms),"ms"];}

/ ---------------------------------------------------------------------------
/ Partitioned-database overview
/ ---------------------------------------------------------------------------
.vis.db:{[] .vis.open .vis.dbView[]}
.vis.dbView:{[]
  part:`pf in key `.Q;
  ts:asc tables[];
  cs:{@[{count get x};x;0N]} each ts;
  pns:$[part; {$[x in .Q.pt; @[{.Q.cn get x};x;()]; ()]} each ts;
    count[ts]#enlist ()];
  hdr:$[part;
    "partitioned by ",(string .Q.pf),": ",(string count .Q.pv)," parts  ",
      (string first .Q.pv)," .. ",string last .Q.pv;
    "no partitioned db loaded - in-memory tables:"];
  `name`draw`state!(`db;.vis.dbDraw;
    `ts`cs`pns`hdr`off`refresh!(ts;cs;pns;hdr;0;(.vis.dbView;::)))}

.vis.dbDraw:{[ev]
  st:.vis.st[]; ts:st`ts; n:count ts;
  .vis.drawText[8;18;.vis.FONT_PROP;.qvis.gray;st`hdr];
  page:(.vis.H-84) div 12;
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  ix:off+til 0|page&n-off;
  mx:1|max 0,raze st[`pns] ix;
  .vis.dbRow[st;mx]'[til count ix;ix];
  .vis.drawText[8;.vis.H-35;.vis.FONT_PROP;.qvis.gray;"click a table to open   esc back"];}

.vis.dbRow:{[st;mx;i;j]
  y:32+12*i;
  t:st[`ts] j;
  .vis.drawText[8;y;.vis.FONT_PROP;.qvis.cyan;string t];
  c:st[`cs] j;
  .vis.drawText[150;y;.vis.FONT_PROP;.qvis.white;$[null c;"?";.vis.fmtnum c]];
  pn:st[`pns] j;
  if[count pn;
    bw:2|560 div count pn;
    nb:count[pn]&560 div bw;
    .vis.dbBar[y;bw;mx]'[til nb;nb sublist pn]];
  .vis.spot[4;y-1;200;11;{[tt;e] .vis.push .vis.tabView[tt;tt]}[t]];}
.vis.dbBar:{[y;bw;mx;i;c]
  h:1|`long$8*c%mx;
  .qvis.rect[220+i*bw;y+8-h;1|bw-1;h;.qvis.green];}

/ ---------------------------------------------------------------------------
/ Memory monitor
/ ---------------------------------------------------------------------------
.vis.mem:{[] .vis.open `name`draw`state!(`mem;.vis.memDraw;(1#`hist)!enlist 0#0j)}
.vis.memDraw:{[ev]
  w:.Q.w[];
  h:-300 sublist .vis.st[][`hist],w`used; .vis.put[`hist;h];
  mx:1|max w`used`heap`peak;
  {[w;mx;i;k]
    y:24+14*i;
    .vis.drawText[8;y;.vis.FONT_PROP;.qvis.gray;string k];
    .vis.drawText[60;y;.vis.FONT_PROP;.qvis.white;.vis.fmtb w k];
    .qvis.rect[130;y;600&`long$600*(w k)%mx;8;$[k=`used;.qvis.green;k=`heap;.qvis.cyan;.qvis.gray]];
  }[w;mx]'[til 5;`used`heap`peak`mmap`syms];
  .vis.drawText[8;110;.vis.FONT_PROP;.qvis.gray;"used history"];
  .vis.plotline[(8;122;.vis.W-20;.vis.H-172);(0f;"f"$1|max[count h]-1);
    (0f;"f"$1|max h);"f"$til count h;"f"$h;.qvis.green];
  .vis.drawText[8;.vis.H-35;.vis.FONT_PROP;.qvis.gray;"esc back"];}

/ ---------------------------------------------------------------------------
/ Filter - type /clause at the command bar. On a table view the clause is a
/ where-clause (/price>100) and matching rows open as a new stacked view -
/ esc clears the filter. On the namespace view it's a substring name match.
/ constraint when filtering a big partitioned table
/ ---------------------------------------------------------------------------
/ run where-conds (in parse-tree shape: enlist of a cond list) against the
/ view's table via eval, push the matches as a new table view; returns the
/ command bar's result line
.vis.tabFilterC:{[st;conds;nm]
  ft:.[{(0b;eval (?;x;y;0b;()))};(st`t;conds);{(1b;x)}];
  if[first ft; :"'filter: ",last ft];
  .vis.push .vis.tabView[last ft;nm];
  (.vis.fmtnum count last ft)," rows"}

.vis.tabFilter:{[st;cl]
  c:@[{(0b;(parse "select from t where ",x) 2)};cl;{(1b;x)}];
  $[first c; "'filter: ",last c; .vis.tabFilterC[st;last c;`$"/",cl]]}

.vis.nsFilterView:{[path;cl]
  v:.vis.nsView path;
  v[`state;`rows]:select from v[`state;`rows] where (string fq) like ("*",cl,"*");
  v[`name]:`$"/",cl;
  v[`state;`refresh]:(.vis.nsFilterView;path;cl);
  v}

.vis.filter:{[cl]
  if[not count .vis.STACK; :"'filter: no view"];
  st:(last .vis.STACK)`state;
  $[`t in key st; .vis.tabFilter[st;cl];
    `path in key st;
      [.vis.push .vis.nsFilterView[st`path;cl];
       (.vis.fmtnum count (last .vis.STACK)[`state;`rows])," entries"];
    "'filter: works on table and namespace views"]}

/ ---------------------------------------------------------------------------
/ Command bar - one-line q) prompt at the bottom of every view (the full
/ REPL editor has its own input and opts out via `capture). Enter evaluates;
/ \cmd runs a system command (\l db, \t, ...) and \\ exits q, console-style.
/ The result shows above the bar; the current view is then rebuilt from the
/ `refresh recipe in its state (a (constructor;args...) list applied with
/ value), so e.g. deleting a global shows up in .vis.ns immediately, and
/ view dicts keep uniform top-level keys (see cmdRefresh). Left/right/home/end
/ edit the bar only while it holds text; when empty they go to the view.
/ ---------------------------------------------------------------------------
.vis.CMD:""; .vis.CX:0;                     / bar text and cursor position
.vis.RES:""; .vis.CRC:0; .vis.CFC:0;        / last result, key-repeat + blink counters
.vis.CEK:`backspace`delete`left`right`home`end;

/ consume the bar's keys from the event dict and return the rest to the view
.vis.cmdIn:{[ev]
  cm:any .vis.CMDKS in ev`held;
  ins:$[cm or 10h<>type ev`text; ""; ev`text];
  if[cm and `v in ev`new; ins,:.qvis.clipboard[]];
  ins:(),raze {$[x="\t";"  ";x in "\n\r";" ";x]} each ins;
  if[count ins;
    .vis.CMD:(.vis.CX#.vis.CMD),ins,.vis.CX _ .vis.CMD;
    .vis.CX+:count ins];
  ks:ev[`new] inter .vis.CEK;
  .vis.CRC:$[any .vis.CEK in ev`held; 1+.vis.CRC; 0];
  if[.vis.CRC>10; ks,:ev[`held] inter .vis.CEK];
  if[0=count .vis.CMD; ks:ks inter `backspace`delete];  / empty bar: nav keys stay with the view
  .vis.cmdKey each ks;
  if[(`return in ev`new) and count trim .vis.CMD;
    s:trim .vis.CMD;
    .vis.CMD:""; .vis.CX:0;
    $[("/"=first s) and 1<count s;
      .vis.RES:.vis.filter 1_s;
      [.vis.RES:.vis.cmdRun s; .vis.cmdRefresh[]]]];
  ev[`new]:ev[`new] except ks,`return;
  ev}

.vis.cmdKey:{[k]
  n:count .vis.CMD;
  if[k=`left;  .vis.CX:0|.vis.CX-1];
  if[k=`right; .vis.CX:n&.vis.CX+1];
  if[k=`home;  .vis.CX:0];
  if[k=`end;   .vis.CX:n];
  if[(k=`backspace) and .vis.CX>0;
    .vis.CMD:.vis.edDel[.vis.CMD;.vis.CX-1]; .vis.CX-:1];
  if[(k=`delete) and .vis.CX<n;
    .vis.CMD:.vis.edDel[.vis.CMD;.vis.CX]];}

/ evaluate one line, console rules: \\ exits, \cmd -> system, else value.
/ a table result (bare "trade", "select from t where ...", etc.) opens in the
/ table browser instead of being squashed into an unreadable one-line string -
/ .vis.tab already handles symbols, in-memory/splayed/partitioned values and
/ keyed tables (unkeys them), so just hand the raw value to it
.vis.cmdRun:{[s]
  s:trim s;
  if[s~"\\\\"; .vis.close[]; exit 0];
  r:@[{(0b;$["\\"=first x; system 1_x; value x])};s;{(1b;x)}];
  $[first r; "'",last r;
    .Q.qt last r; [.vis.tab last r; ""];
    .vis.cmd1 last r]}

/ one-line display of a result; big collections are sampled so a stray
/ "select from bigtable" can't stall the frame loop building a giant string.
/ a bare partitioned-table result (e.g. typing "trade" with no where-clause)
/ can't be plain-sublisted - .Q.ind pages it the same way .vis.tabFetch does
.vis.cmd1:{[r]
  if[(::)~r; :""];
  big:(0<=type r) and 1000<count r;
  s:$[not big; r; 1b~.Q.qp r; .Q.ind[r;til 1000]; 1000 sublist r];
  (.vis.TXTC sublist .Q.s1 s),$[big;"..";""]}

/ rebuild the current view after a command so session changes show at once;
/ scroll position survives (draw clamps it if the data shrank). The recipe
/ lives in state, not the view dict: .vis.STACK is a list of conforming
/ dicts (i.e. a table), so every view must keep the same top-level keys
.vis.cmdRefresh:{[]
  if[not .vis.RUN; :(::)];
  if[not count .vis.STACK; :(::)];
  v:last .vis.STACK; st:v`state;
  if[not `refresh in key st; :(::)];
  nv:@[value;st`refresh;{[e](::)}];         / recipe may fail (e.g. table deleted) - keep old view
  if[99h<>type nv; :(::)];
  nv[`state;`off]:st`off;
  / table views also keep their column page and sort - the permutation is
  / recomputed on the refreshed data; a vanished column just drops the sort
  if[(`srt in key st) and `srt in key nv`state;
    nv[`state;`c0]:st`c0;
    if[not null first st`srt;
      idx:.[.vis.sortIdx;(nv[`state;`t];first st`srt;last st`srt);{[e]0#0}];
      if[count idx; nv[`state;`idx]:idx; nv[`state;`srt]:st`srt]]];
  .vis.STACK:(-1_.vis.STACK),enlist nv;}

.vis.cmdClick:{[ev]
  if[(ev`my)<.vis.H-13; :(::)];
  hoff:0|.vis.CX-(.vis.W-24) div .vis.MONOW;
  .vis.CX:count[.vis.CMD]&0|hoff+((ev`mx)-18) div .vis.MONOW;}

.vis.cmdDraw:{[]
  .vis.CFC+:1;
  .qvis.rect[0;.vis.H-25;.vis.W;25;.vis.BG];  / opaque strip so view rows don't bleed through
  if[count .vis.RES;
    .vis.drawText[8;.vis.H-23;.vis.FONT_PROP;$["'"=first .vis.RES;.qvis.red;.qvis.gray];.vis.RES]];
  .qvis.rect[0;.vis.H-13;.vis.W;13;.qvis.white];
  .vis.drawText[4;.vis.H-10;.vis.FONT_MONO;.qvis.black;"q)"];
  maxc:(.vis.W-24) div .vis.MONOW;
  hoff:0|.vis.CX-maxc;                      / h-scroll so the cursor stays visible
  .vis.drawText[18;.vis.H-10;.vis.FONT_MONO;.qvis.black;maxc sublist hoff _ .vis.CMD];
  if[12>.vis.CFC mod 20;
    .qvis.rect[18+.vis.textWidth[.vis.FONT_MONO; (.vis.CX-hoff) sublist (hoff _ .vis.CMD)];.vis.H-12;1;11;.qvis.black]];}

/ ---------------------------------------------------------------------------
/ REPL - multiline q editor (top pane) + result pane (bottom).
/ enter = newline, cmd/ctrl+enter = run, cmd/ctrl+v = paste, tab = 2 spaces,
/ shift+up/down = select whole lines, cmd/ctrl+a = select all, cmd+c/x copy/cut the
/ selected lines to the system clipboard, backspace/delete removes them,
/ arrows/home/end move, click positions the cursor, esc leaves the view.
/ Typed characters come from SDL text-input events (.qvis.poll's `text key),
/ so shift and keyboard layout are handled by the OS - scancodes can't
/ produce ` or {. The buffer persists in .vis.REPLB across open/close.
/ ---------------------------------------------------------------------------
.vis.EDR:26;                                / visible editor rows
.vis.EDK:`backspace`delete`left`right`up`down`home`end;  / repeatable keys
.vis.REPLB:enlist "";                       / persistent editor buffer
.vis.SCRATCHB:enlist "";                    / persistent scratch pad

.vis.repl:{[x]
  isScratch:(::)~x;
  if[not isScratch;
    t:type x;
    isf:$[t within (100;112); 1b;
          t in -11 -10h; [val:@[get;$[-10h=t;`$x;x];(::)]; (type val) within (100;112)];
          0b];
    if[not isf; '"repl: expected a function"];
    .vis.REPLB:.vis.srcLines x];
  if[isScratch;
    .vis.REPLB:.vis.SCRATCHB];
  .vis.open .vis.replView[isScratch]}
.vis.replView:{[isScratch]
  st:`lines`cy`cx`off`out`ooff`rc`fc`capture`sa`isScratch!
    (.vis.REPLB;-1+count .vis.REPLB;count last .vis.REPLB;0;();0;0;0;1b;-1;isScratch);
  `name`draw`state!(`repl;.vis.replDraw;st)}

/ pure editor ops on the state dict - lines/cy/cx are the buffer and cursor

/ insert txt (may contain \n) at the cursor; tabs become 2 spaces
.vis.edIns:{[st;txt]
  txt:(),raze {$[x="\t";"  ";x="\r";"";x]} each txt;
  if[not count txt; :st];
  segs:"\n" vs txt;
  ls:st`lines; cy:st`cy; cx:st`cx;
  pre:cx#ls cy; post:cx _ ls cy;
  $[1=count segs;
    [st[`lines]:@[ls;cy;:;pre,txt,post]; st[`cx]:cx+count txt];
    [st[`lines]:(cy#ls),(enlist pre,first segs),(1_-1_segs),
       (enlist last[segs],post),(cy+1)_ls;
     st[`cy]:cy+count[segs]-1; st[`cx]:count last segs]];
  st}

.vis.edDel:{[s;i] (i#s),(i+1)_s}
.vis.edKey:{[st;k]
  ls:st`lines; cy:st`cy; cx:st`cx; l:ls cy;
  if[k=`tab; :.vis.edIns[st;"  "]];
  if[k=`left;  $[cx>0; st[`cx]:cx-1; cy>0; [st[`cy]:cy-1; st[`cx]:count ls cy-1]; ::]];
  if[k=`right; $[cx<count l; st[`cx]:cx+1; cy<count[ls]-1; [st[`cy]:cy+1; st[`cx]:0]; ::]];
  if[k=`up;   $[cy>0; [st[`cy]:cy-1; st[`cx]:cx&count ls cy-1]; st[`cx]:0]];
  if[k=`down; $[cy<count[ls]-1; [st[`cy]:cy+1; st[`cx]:cx&count ls cy+1]; st[`cx]:count l]];
  if[k=`home; st[`cx]:0];
  if[k=`end;  st[`cx]:count l];
  if[k=`backspace;
    $[cx>0; [st[`lines]:@[ls;cy;.vis.edDel;cx-1]; st[`cx]:cx-1];
      cy>0; [st[`cx]:count ls cy-1;
             st[`lines]:((cy-1)#ls),(enlist (ls cy-1),l),(cy+1)_ls;
             st[`cy]:cy-1];
      ::]];
  if[k=`delete;
    $[cx<count l; st[`lines]:@[ls;cy;.vis.edDel;cx];
      cy<count[ls]-1; st[`lines]:(cy#ls),(enlist l,ls cy+1),(cy+2)_ls;
      ::]];
  st}

/ apply editing keys: new presses always fire; after ~a third of a second
/ held keys auto-repeat once per frame
.vis.edit:{[st;ev]
  ks:ev[`new] inter .vis.EDK;
  st[`rc]:$[any .vis.EDK in ev`held; 1+st`rc; 0];
  if[st[`rc]>10; ks,:ev[`held] inter .vis.EDK];
  .vis.edKey/[st;ks]}

/ line selection: sa is the anchor line (-1 = none); the selection is the
/ inclusive line range between sa and the cursor line cy
.vis.selRng:{[st] asc st`sa`cy}
.vis.selTxt:{[st] r:.vis.selRng st; "\n" sv st[`lines] r[0]+til 1+r[1]-r[0]}
.vis.selDel:{[st]
  r:.vis.selRng st;
  ls:(r[0]#st`lines),(1+r 1)_st`lines;
  if[not count ls; ls:enlist ""];
  st[`lines]:ls; st[`cy]:(count[ls]-1)&r 0; st[`cx]:0; st[`sa]:-1;
  st}

/ tab+up/down extends the selection, cmd/ctrl+a selects all, cmd+c/x
/ copy/cut the selected lines to the system clipboard, backspace/delete
/ removes them, plain movement drops the selection. A tab tapped without an
/ arrow still indents - the insert happens on release (`tp = tab pending).
/ Returns (state; consumed keys) - consumed keys are hidden from .vis.edit
/ so they don't also move the cursor or delete characters.
/ or cmd+a for everything
.vis.replSel:{[st;ev;cmd]
  eat:0#`;
  shiftH:any `left_shift`right_shift in ev`held;
  if[cmd and `a in ev`new;
    st[`sa]:0; st[`cy]:-1+count st`lines; st[`cx]:count last st`lines];
  if[`tab in ev`new;
    st[`sa]:-1; st:.vis.edIns[st;"  "]];
  if[shiftH;
    eat,:`up`down;
    mv:ev[`new] inter `up`down;
    if[count mv;
      if[0>st`sa; st[`sa]:st`cy];
      st:.vis.edKey/[st;mv]]];
  if[0<=st`sa;
    if[cmd and `c in ev`new; .qvis.setclip .vis.selTxt st];
    if[cmd and `x in ev`new; .qvis.setclip .vis.selTxt st; st:.vis.selDel st];
    if[any `backspace`delete in ev`new;
      st:.vis.selDel st; eat,:`backspace`delete]];
  if[(0<=st`sa) and not shiftH;               / plain movement drops the selection
    if[count (ev`new) inter `left`right`up`down`home`end; st[`sa]:-1]];
  (st;eat)}

/ group buffer lines into top-level statements: a statement starts at a
/ non-indented, non-blank line; indented/blank lines continue the previous
/ one (q script-file rules). value[] accepts \n inside an expression (e.g. a
/ multiline function body) but not between statements, so each statement is
/ evaluated on its own.
.vis.replStmts:{[lines]
  tops:where {(0<count x) and not first[x] in " \t"} each lines;
  if[not count tops; :()];
  {"\n" sv x} each tops cut lines}

/ run the buffer; returns display lines - the last statement's value, or
/ the error and offending statement
.vis.replRun:{[lines]
  stmts:.vis.replStmts lines;
  if[not count stmts; :enlist "(no code)"];
  r:(::); i:0;
  while[i<count stmts;
    r:@[{(0b;value x)};stmts i;{(1b;x)}];
    if[first r; :("'",last r;"  in: ",80 sublist first "\n" vs stmts i)];
    i+:1];
  $[(::)~r:last r; enlist "::"; "\n" vs -1_.Q.s r]}

.vis.replDraw:{[ev]
  st:.vis.st[];
  cmd:any .vis.CMDKS in ev`held;
  txt:ev`text; if[10h<>type txt; txt:""];
  se:.vis.replSel[st;ev;cmd]; st:first se;
  ev[`new]:ev[`new] except last se;         / selection consumed these keys
  ev[`held]:ev[`held] except last se;
  if[(not cmd) and count txt; st[`sa]:-1; st:.vis.edIns[st;txt]];
  if[cmd and `v in ev`new; st[`sa]:-1; st:.vis.edIns[st;.qvis.clipboard[]]];
  if[`return in ev`new;
    st[`sa]:-1;
    $[cmd;
      [st[`out]:.vis.wrap[.vis.TXTC] .vis.replRun st`lines; st[`ooff]:0];
      st:.vis.edIns[st;enlist "\n"]]];
  st:.vis.edit[st;ev];
  / editor scroll follows the cursor; wheel scrolls the pane under the mouse
  edh:18+10*.vis.EDR;
  st[`off]:0|$[st[`cy]<st`off; st`cy;
    st[`cy]>st[`off]+.vis.EDR-1; st[`cy]-.vis.EDR-1; st`off];
  outr:(.vis.H-16+edh+8) div 10;
  omx:0|count[st`out]-outr;
  if[0<>ev`wheel;
    $[ev[`my]<edh;
      st[`off]:0|(0|count[st`lines]-1)&(st`off)-3*ev`wheel;
      st[`ooff]:0|omx&(st`ooff)-3*ev`wheel]];
  if[`pagedown in ev`new; st[`ooff]:omx&(st`ooff)+outr];
  if[`pageup in ev`new; st[`ooff]:0|(st`ooff)-outr];
  if[ev`click;
    if[ev[`my] within (18;edh-1);
      st[`sa]:-1;
      st[`cy]:0|(count[st`lines]-1)&(st`off)+(ev[`my]-18) div 10;
      st[`cx]:count[st[`lines]st`cy]&0|(ev[`mx]-8) div .vis.MONOW]];
  st[`fc]:1+st`fc;
  .vis.REPLB::st`lines;
  if[1b~st`isScratch; .vis.SCRATCHB::st`lines];
  / executed code may itself have opened a view (.vis.tab etc.) and replaced
  / the stack - don't write repl state over it, just yield the frame
  if[$[count .vis.STACK; not `repl~(last .vis.STACK)`name; 1b]; :(::)];
  .vis.putAll st;
  / render: editor pane, blinking cursor, divider, output pane
  off:st`off; shown:.vis.EDR sublist off _ st`lines;
  maxc:(.vis.W-16) div .vis.MONOW;
  hoff:0|(st`cx)-maxc-1;                    / h-scroll so the cursor stays visible
  cyv:st[`cy]-off;
  if[cyv within (0;.vis.EDR-1); .qvis.rect[0;17+10*cyv;.vis.W;10;.vis.GRID]];
  if[0<=st`sa;                              / selected lines, over the cursor stripe
    sr:.vis.selRng st;
    {[y] if[y within (0;.vis.EDR-1); .qvis.rect[0;17+10*y;.vis.W;10;.vis.SELC]]}
      each (sr[0]+til 1+sr[1]-sr[0])-off];
  {[st;off;maxc;hoff;i;s]
    ho:$[(off+i)=st`cy; hoff; 0];
    .vis.qline[8;18+10*i;maxc sublist ho _ s]}[st;off;maxc;hoff]
    '[til count shown;shown];
  if[(cyv within (0;.vis.EDR-1)) and 12>(st`fc) mod 20;
    .qvis.rect[7+.vis.textWidth[.vis.FONT_MONO; ((st`cx)-hoff) sublist (hoff _ st[`lines] st`cy)];17+10*cyv;1;9;.qvis.white]];
  .qvis.line[0;edh+2;.vis.W;edh+2;.vis.BORD];
  oshown:outr sublist (st`ooff) _ st`out;
  {[y0;i;s] .vis.drawText[8;y0+10*i;.vis.FONT_MONO;
    $[(0<count s) and "'"=first s;.qvis.red;.qvis.white];s]}[edh+8]
    '[til count oshown;oshown];
  .vis.drawText[8;.vis.H-12;.vis.FONT_PROP;.qvis.gray;
    "cmd+enter=run   cmd+v=paste   tab=indent   shift+arrows/cmd+a=select   cmd+c/x=copy/cut   esc=back"];}