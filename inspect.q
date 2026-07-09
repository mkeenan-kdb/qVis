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
/   .vis.watchAs[t;ms;k] live view of kind k: `plot, `candle or `tab
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
.vis.W:850; .vis.H:450; .vis.SC:2;
.vis.TROWS:38;                              / visible rows in table/text views
.vis.TXTC:130;                              / wrap width (chars) in text views
.vis.BG:658448i; .vis.GRID:2105376i; .vis.BORD:2764856i;
.vis.SELC:2046556i;                         / selected-line highlight (muted blue)
.vis.CMDKS:`left_gui`right_gui`left_ctrl`right_ctrl`left_command`right_command`left_meta`right_meta`left_windows`right_windows;
.vis.PAL:(.qvis.cyan;.qvis.green;.qvis.yellow;.qvis.magenta;.qvis.red;.qvis.white); /our palette 

.vis.STACK:();                              / view stack (drill-down)
.vis.HOT:([] x:0#0; y:0#0; w:0#0; h:0#0; rc:0#0b; act:());  / this frame's hotspots
.vis.OZTS:(::); .vis.OT:0;                  / saved .z.ts and \t
.vis.RUN:0b;
.vis.DEBUG:0b;

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
.vis.st:{[] (last .vis.STACK)`state}
.vis.put:{[k;v] .[`.vis.STACK;(-1+count .vis.STACK;`state;k);:;v];}
.vis.putAll:{[st] .[`.vis.STACK;(-1+count .vis.STACK;`state);:;st];}

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
.vis.menuDraw:{[]
  if[not count .vis.MENU; :(::)];
  m:.vis.MENU; its:m`items;
  w:14+6*max count each its; h:4+12*count its;
  x0:0|(.vis.W-w)&m`x; y0:0|(.vis.H-25-h)&m`y;  / keep clear of the command bar
  .qvis.rect[x0;y0;w;h;.vis.BG];
  .qvis.line[x0;y0;x0+w;y0;.vis.BORD]; .qvis.line[x0;y0+h;x0+w;y0+h;.vis.BORD];
  .qvis.line[x0;y0;x0;y0+h;.vis.BORD]; .qvis.line[x0+w;y0;x0+w;y0+h;.vis.BORD];
  .vis.menuItem[x0;y0;w]'[til count its;its;m`acts];}
.vis.menuItem:{[x0;y0;w;i;s;a]
  y:y0+3+12*i;
  .qvis.text[x0+7;y;1;.qvis.white;s];
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
  .vis.menuDraw[];
  .qvis.present[];}

/ breadcrumb trail; clicking a crumb pops back to that view
.vis.crumbs:{[]
  nms:{string x`name} each .vis.STACK;
  ws:{6*count x} each nms;
  xs:4+sums 0,-1_ws+12;
  .vis.crumb[count nms]'[til count nms;nms;xs;ws];}
.vis.crumb:{[n;i;nm;x0;wd]
  .qvis.text[x0;4;1;$[i=n-1;.qvis.white;.qvis.gray];nm];
  if[i<n-1; .qvis.text[x0+wd+3;4;1;.qvis.gray;">"]];
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
  .qvis.text[0|(x0+pw-6*count s)&px-3*count s;y0+ph+4;1;.qvis.gray;s];}

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
.vis.widths:{[hdrs;colz] 8+6*20&{max count each x} each (enlist each hdrs),'colz}

/ wrap each line to w chars, preserving blank lines
.vis.wrap:{[w;lines] raze {[w;l] $[count l;(0N;w)#l;enlist l]}[w] each lines}

/ ---------------------------------------------------------------------------
/ Text view - scrollable lines; reused for function source and values
/ ---------------------------------------------------------------------------
.vis.txtView:{[nm;lines] `name`draw`state!(nm;.vis.txtDraw;`off`lines!(0;lines))}

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

/ draw one syntax-colored line of q at (x0;y): group consecutive same-color
/ runs and draw each as one text call
.vis.qline:{[x0;y;s]
  if[0=count s; :(::)];
  colz:.vis.charColors s;
  ci:0;
  while[ci<count s;
    c:colz ci; j:ci;
    while[(j<count s) and colz[j]~c; j+:1];
    .qvis.text[x0+6*ci; y; 1; c; s ci+til j-ci];
    ci:j];}

.vis.txtDraw:{[ev]
  st:.vis.st[]; ls:st`lines; page:.vis.TROWS;
  off:.vis.scroll[ev;page;0|count[ls]-page;st`off]; .vis.put[`off;off];
  shown:page sublist off _ ls;
  .vis.qline[8]'[18+10*til count shown;shown];
  .qvis.text[8;.vis.H-35;1;.qvis.gray;(string count ls)," lines  esc back"];}

.vis.srcLines:{[fq]
  v:get fq;
  s:$[100h=type v; last value v; .Q.s1 v];
  if[10h<>abs type s; s:.Q.s1 v];
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
  st:.vis.st[]; n:st`n; page:.vis.TROWS;
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
  / left/right page through columns that don't fit the window
  nc:count st`hdrs; c0:st`c0;
  if[`left in ev`new; c0:0|c0-1];
  if[`right in ev`new; c0:(0|nc-1)&c0+1];
  .vis.put[`c0;c0];
  ws:.vis.widths[st`hdrs;colz];
  cs:c0 _ til nc;
  xs:8+sums 0,-1_ws cs;
  keep:where (xs+ws cs)<.vis.W;             / draw only columns that fit
  .vis.tabCol[st;off]'[xs keep;(ws cs)keep;(st[`hdrs]cs)keep;(st[`cnames]cs)keep;(colz cs)keep];
  {[st;off;i] .vis.spot[4;29+10*i;.vis.W-8;10;.vis.tabRow[st;off+i]]}[st;off] each til m;
  s:.vis.tabFoot[st;off;m];
  if[(c0>0) or nc>count keep;
    s,:"  cols ",(string c0+1),"-",(string c0+count keep),"/",(string nc)," (left/right)"];
  .qvis.text[8;.vis.H-35;1;.qvis.gray;s];}

/ click a row -> full record as "col: value" lines, untruncated
.vis.tabRow:{[st;r;e]
  d:first .vis.tabFetch[st;r;1];
  ls:{[d;k](string k),": ",.Q.s1 d k}[d] each key d;
  .vis.push .vis.txtView[`$"row ",string r;.vis.wrap[.vis.TXTC;ls]];}

.vis.tabCol:{[st;off;x0;w0;hdr;cn;cs]
  .qvis.text[x0;18;1;.qvis.yellow;hdr];
  .vis.spot[x0;16;w0;11;.vis.tabSort cn];
  {[st;off;cn;x0;w0;i;s]
    .qvis.text[x0;30+10*i;1;.qvis.white;20 sublist s];
    .vis.spotR[x0;29+10*i;w0;10;.vis.cellMenu[st;cn;off+i]]}[st;off;cn;x0;w0]
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
      " ";0f;"f"$0|-1+st`n]];}

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
  s,"  header sorts  row inspects  esc back"}

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
  .qvis.text[8;18;1;.qvis.yellow;"name"]; .qvis.text[360;18;1;.qvis.yellow;"kind"];
  .qvis.text[430;18;1;.qvis.yellow;"type"]; .qvis.text[490;18;1;.qvis.yellow;"count"];
  .qvis.text[570;18;1;.qvis.yellow;"size"];
  shown:page sublist off _ rows;
  .vis.nsRow'[til count shown;shown];
  .qvis.text[8;.vis.H-35;1;.qvis.gray;
    (string n)," entries  click to open  esc back"];}

.vis.nsRow:{[i;r]
  y:30+10*i;
  col:(`ns`table`dict`var`fn!(.qvis.yellow;.qvis.cyan;.qvis.magenta;.qvis.white;.qvis.green)) r`kind;
  fqstr: string r`fq;
  if[(type fqstr)=-10h; fqstr: enlist fqstr];
  .qvis.text[8;y;1;col;56 sublist fqstr];
  .qvis.text[360;y;1;.qvis.gray;string r`kind];
  .qvis.text[430;y;1;.qvis.gray;string r`tp];
  if[not null r`cnt; .qvis.text[490;y;1;.qvis.gray;.vis.fmtnum r`cnt]];
  if[not null r`sz; .qvis.text[570;y;1;.qvis.gray;.vis.fmtb r`sz]];
  .vis.spot[4;y-1;630;10;.vis.nsAct[r`fq;r`kind]];
  .vis.spotR[4;y-1;630;10;.vis.nsMenu r];}

.vis.nsMenu:{[r;e]
  .vis.menu[("open";"copy name");
    (.vis.nsAct[r`fq;r`kind];{[fq;e] .qvis.setclip string fq}[r`fq])];}

.vis.nsAct:{[fq;kind;e]
  $[kind=`ns; .vis.push .vis.nsView fq;
    kind=`table; .vis.push .vis.tabView[fq;fq];
    kind=`fn; .vis.push .vis.txtView[fq;.vis.srcLines fq];
    .vis.push .vis.txtView[fq;.vis.valLines fq]];}

/ ---------------------------------------------------------------------------
/ Plots
/ ---------------------------------------------------------------------------
/ downsample to <=2*pw points: min and max of each pixel bucket, so a single
/ spike in a million points still shows instead of falling between samples
.vis.dsamp:{[pw;ser]
  n:count ser; if[n<=pw; :ser];
  raze {(min x;max x)} each ser value group floor (til n)*pw%n}

/ scale a series into a box against an explicit lo..hi range and draw it
.vis.plotline:{[x0;y0;pw;ph;ser;lo;hi;col]
  ser:"f"$ser; n:count ser; if[n<2; :(::)];
  ser:reverse fills reverse fills ser;      / patch interior/leading nulls
  if[any null ser; :(::)];                  / all-null series: nothing to draw
  ser:.vis.dsamp[pw;ser]; n:count ser;
  rg:1e-9|hi-lo;
  xs:x0+`long$(pw-1)*(til n)%n-1;
  ys:(y0+ph-1)-`long$(ph-1)*(ser-lo)%rg;
  .qvis.line'[-1_xs;-1_ys;1_xs;1_ys;col];}

.vis.axes:{[x0;y0;pw;ph;lo;hi]
  .qvis.line[x0;y0;x0;y0+ph;.vis.BORD]; .qvis.line[x0;y0+ph;x0+pw;y0+ph;.vis.BORD];
  .vis.tick[x0;y0;pw;ph;lo;hi] each tks where (tks:.vis.nice[lo;hi;4]) within (lo;hi);}
.vis.tick:{[x0;y0;pw;ph;lo;hi;v]
  y:(y0+ph-1)-`long$(ph-1)*(v-lo)%1e-9|hi-lo;
  .qvis.line[x0+1;y;x0+pw;y;.vis.GRID];
  .qvis.text[2;y-3;1;.qvis.gray;8 sublist .vis.fmtnum v];}

.vis.plot:{[x]
  $[.Q.qt x; .vis.plotTbl x;
    0h=type x;
      .vis.open .vis.plotView[{"s",string x} each 1+til count x;"f"$'x;
        " ";0f;"f"$-1+max count each x];
    .vis.open .vis.plotView[enlist "y";enlist "f"$x;" ";0f;"f"$-1+count x]]}

/ plot state from a table: numeric columns are series, the first temporal
/ column (if any) supplies the x-axis range and tick format
.vis.plotState:{[t]
  if[count keys t; t:0!t]; mt:0!meta t;
  xi:first where (mt`t) in "pmdznuvt";
  yc:(mt`c) where (mt`t) in "hijfe";
  if[not count yc; '`$"no numeric columns"];
  xt:" "; xlo:0f; xhi:"f"$0|-1+count t;
  / min/max, not first/last - the time column need not be sorted
  if[not null xi; xc:t (mt`c) xi; xt:(mt`t) xi; xlo:"f"$min xc; xhi:"f"$max xc];
  `nms`ys`xt`xlo`xhi!(string each yc;{[t;c]"f"$t c}[t] each yc;xt;xlo;xhi)}

.vis.plotTbl:{[t] .vis.open `name`draw`state!(`plot;.vis.plotDraw;.vis.plotState t)}

/ nms/ys = series names and vectors; xt/xlo/xhi = x type char (" " = ordinal
/ index) and range, used only for the tick grid - see .vis.xticks
.vis.plotView:{[nms;ys;xt;xlo;xhi]
  `name`draw`state!(`plot;.vis.plotDraw;`nms`ys`xt`xlo`xhi!(nms;ys;xt;xlo;xhi))}

.vis.plotDraw:{[ev]
  st:.vis.st[]; ys:st`ys; nms:st`nms;
  x0:56; y0:24; pw:.vis.W-72; ph:.vis.H-60;
  allv:raze ys; allv:allv where not null allv;
  if[not count allv; .qvis.text[x0;y0;1;.qvis.red;"no data"]; :(::)];
  lo:min allv; hi:max allv; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  .vis.xticks[x0;y0;pw;ph;st`xt;st`xlo;st`xhi];
  .vis.plotline[x0;y0;pw;ph;;lo;hi;]'[ys;.vis.PAL til[count ys] mod count .vis.PAL];
  {[i;nm;c] .qvis.text[.vis.W-160;24+10*i;1;c;16 sublist nm]}
    '[til count nms;nms;.vis.PAL til[count nms] mod count .vis.PAL];}

.vis.hist:{[x;bins]
  x:"f"$x; x:x where not null x;
  if[not count x; '`$"no data"];
  mn:min x; rg:1e-9|max[x]-mn;
  c:@[bins#0;`long$(bins-1)&floor bins*(x-mn)%rg;+;1];
  .vis.open `name`draw`state!(`hist;.vis.histDraw;`mn`rg`c!(mn;rg;c))}

.vis.histDraw:{[ev]
  st:.vis.st[]; c:st`c; bins:count c;
  x0:56; y0:24; pw:.vis.W-72; ph:.vis.H-60;
  .vis.axes[x0;y0;pw;ph;0f;"f"$mx:1|max c];
  .vis.hbar[x0;y0;ph;1|pw div bins;mx]'[til bins;c];
  .qvis.text[x0;y0+ph+4;1;.qvis.gray;.vis.fmtnum st`mn];
  s:.vis.fmtnum st[`mn]+st`rg;
  .qvis.text[(x0+pw)-6*count s;y0+ph+4;1;.qvis.gray;s];}
.vis.hbar:{[x0;y0;ph;bw;mx;i;c]
  h:`long$(ph-2)*c%mx;
  .qvis.rect[x0+1+i*bw;(y0+ph-1)-h;1|bw-1;h;.qvis.cyan];}

.vis.scatter:{[xx;yy]
  xx:"f"$xx; yy:"f"$yy;
  ok:where not (null xx) or null yy;
  xx:xx ok; yy:yy ok;
  if[not count xx; '`$"no data"];
  .vis.open `name`draw`state!(`scatter;.vis.scatDraw;`xx`yy!(xx;yy))}

.vis.scatDraw:{[ev]
  st:.vis.st[]; xx:st`xx; yy:st`yy;
  x0:56; y0:24; pw:.vis.W-72; ph:.vis.H-60;
  ylo:min yy; yhi:max yy; if[ylo=yhi; yhi:ylo+1f];
  xlo:min xx; xhi:max xx; if[xlo=xhi; xhi:xlo+1f];
  .vis.axes[x0;y0;pw;ph;ylo;yhi];
  .vis.xticks[x0;y0;pw;ph;" ";xlo;xhi];
  .qvis.rect'[x0+1+`long$(pw-4)*(xx-xlo)%xhi-xlo;
        (y0+ph-3)-`long$(ph-4)*(yy-ylo)%yhi-ylo;2;2;.qvis.cyan];
  / crosshair + data-space readout while the mouse is over the plot area
  mx:ev`mx; my:ev`my;
  if[(mx within (x0;x0+pw-1)) and my within (y0;y0+ph-1);
    .qvis.line[mx;y0;mx;y0+ph-1;.vis.BORD];
    .qvis.line[x0;my;x0+pw-1;my;.vis.BORD];
    xv:xlo+(xhi-xlo)*(mx-x0)%pw-1; yv:ylo+(yhi-ylo)*((y0+ph-1)-my)%ph-1;
    s:(.vis.fmtnum xv),", ",.vis.fmtnum yv;
    .qvis.text[0|(x0+pw-6*count s)&mx+6;(y0+2)|my-10;1;.qvis.gray;s]];}

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
  if[not null xi; xc:t (mt`c) xi; xt:(mt`t) xi; xlo:"f"$min xc; xhi:"f"$max xc];
  `o`h`l`c`xt`xlo`xhi!("f"$t`open;"f"$t`high;"f"$t`low;"f"$t`close;xt;xlo;xhi)}

.vis.candle:{[t] .vis.open `name`draw`state!(`candle;.vis.candleDraw;.vis.candleState t)}

.vis.candleDraw:{[ev]
  st:.vis.st[];
  x0:56; y0:24; pw:.vis.W-72; ph:.vis.H-60;
  ohlc:.vis.obucket[pw div 5;st`o;st`h;st`l;st`c];
  n:count first ohlc;
  if[0=n; .qvis.text[x0;y0;1;.qvis.red;"no data"]; :(::)];
  lo:min ohlc 2; hi:max ohlc 1; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  .vis.xticks[x0;y0;pw;ph;st`xt;st`xlo;st`xhi];
  py:{[y0;ph;lo;rg;v] (y0+ph-1)-`long$(ph-1)*(v-lo)%rg}[y0;ph;lo;1e-9|hi-lo];
  .vis.candle1[x0;pw div n;py]'[til n;ohlc 0;ohlc 1;ohlc 2;ohlc 3];}
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

.vis.barDraw:{[ev]
  st:.vis.st[]; v:st`v; n:count v;
  x0:56; y0:24; pw:.vis.W-72; ph:.vis.H-60;
  lo:min 0f,v; hi:max 0f,v; if[lo=hi; hi:lo+1f];
  .vis.axes[x0;y0;pw;ph;lo;hi];
  py:{[y0;ph;lo;rg;x] (y0+ph-1)-`long$(ph-1)*(x-lo)%rg}[y0;ph;lo;1e-9|hi-lo];
  .vis.bar1[st;py;x0;1|pw div n;y0+ph]'[til n;v];}
.vis.bar1:{[st;py;x0;bw;yl;i;x]
  yv:py x; yz:py 0f;
  .qvis.rect[x0+1+i*bw;yv&yz;1|bw-2;1|1+abs yv-yz;$[x<0;.qvis.red;.qvis.cyan]];
  s:(bw div 6) sublist st[`lbl] i;
  if[count s; .qvis.text[x0+1+i*bw;yl+4;1;.qvis.gray;s]];}

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
  n:count v; i:(n-m)+til m:.vis.WROWS&n;
  $[1b~.Q.qp v; .Q.ind[v;i]; v i]}

/ `tab kind: browser state on the tail, scroll pinned to the newest rows -
/ a graphical tail -f
.vis.tailState:{[t]
  st:(.vis.tabView[t;`tail])`state;
  st[`off]:0|st[`n]-.vis.TROWS;
  st}

/ kind -> (state builder applied to the fetched tail; draw fn)
.vis.WKIND:`plot`candle`tab!(
  (.vis.plotState;.vis.plotDraw);
  (.vis.candleState;.vis.candleDraw);
  (.vis.tailState;.vis.tabDraw));

.vis.watch:{[t;ms] .vis.watchAs[t;ms;`plot]}
.vis.watchAs:{[t;ms;k]
  if[not k in key .vis.WKIND;
    '`$"watch: kind must be one of ",", " sv string key .vis.WKIND];
  .vis.open `name`draw`state!(`$"watch-",string k;.vis.watchDraw;
    (.vis.WKIND[k][0] .vis.wfetch t),`wt`ms`lp`wk!(t;ms;.z.P;k))}

/ every frame: re-fetch + rebuild the kind's state once ms have elapsed,
/ then hand the frame to the kind's draw fn as if it were a plain view
.vis.watchDraw:{[ev]
  st:.vis.st[];
  if[(st`ms)<=(("j"$.z.P-st`lp)%1e6);
    st:st,.vis.WKIND[st`wk][0] .vis.wfetch st`wt; st[`lp]:.z.P;
    .vis.putAll st];
  .vis.WKIND[st`wk][1] ev;
  .qvis.text[.vis.W-90;4;1;.qvis.gray;"watch ",(string st`ms),"ms"];}

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
  .qvis.text[8;18;1;.qvis.gray;st`hdr];
  page:(.vis.H-84) div 12;
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  ix:off+til 0|page&n-off;
  mx:1|max 0,raze st[`pns] ix;
  .vis.dbRow[st;mx]'[til count ix;ix];
  .qvis.text[8;.vis.H-35;1;.qvis.gray;"click a table to open  esc back"];}

.vis.dbRow:{[st;mx;i;j]
  y:32+12*i;
  t:st[`ts] j;
  .qvis.text[8;y;1;.qvis.cyan;string t];
  c:st[`cs] j;
  .qvis.text[150;y;1;.qvis.white;$[null c;"?";.vis.fmtnum c]];
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
    .qvis.text[8;y;1;.qvis.gray;string k];
    .qvis.text[60;y;1;.qvis.white;.vis.fmtb w k];
    .qvis.rect[130;y;600&`long$600*(w k)%mx;8;$[k=`used;.qvis.green;k=`heap;.qvis.cyan;.qvis.gray]];
  }[w;mx]'[til 5;`used`heap`peak`mmap`syms];
  .qvis.text[8;110;1;.qvis.gray;"used history"];
  .vis.plotline[8;122;.vis.W-20;.vis.H-172;"f"$h;0f;"f"$1|max h;.qvis.green];
  .qvis.text[8;.vis.H-35;1;.qvis.gray;"esc back"];}

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

/ evaluate one line, console rules: \\ exits, \cmd -> system, else value
.vis.cmdRun:{[s]
  s:trim s;
  if[s~"\\\\"; .vis.close[]; exit 0];
  r:@[{(0b;$["\\"=first x; system 1_x; value x])};s;{(1b;x)}];
  $[first r; "'",last r; .vis.cmd1 last r]}

/ one-line display of a result; big collections are sampled so a stray
/ "select from bigtable" can't stall the frame loop building a giant string
.vis.cmd1:{[r]
  if[(::)~r; :""];
  big:(0<=type r) and 1000<count r;
  (.vis.TXTC sublist .Q.s1 $[big; 1000 sublist r; r]),$[big;"..";""]}

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
  hoff:0|.vis.CX-(.vis.W-24) div 6;
  .vis.CX:count[.vis.CMD]&0|hoff+((ev`mx)-18) div 6;}

.vis.cmdDraw:{[]
  .vis.CFC+:1;
  .qvis.rect[0;.vis.H-25;.vis.W;25;.vis.BG];  / opaque strip so view rows don't bleed through
  if[count .vis.RES;
    .qvis.text[8;.vis.H-23;1;$["'"=first .vis.RES;.qvis.red;.qvis.gray];.vis.RES]];
  .qvis.rect[0;.vis.H-13;.vis.W;13;.qvis.white];
  .qvis.text[4;.vis.H-10;1;.qvis.black;"q)"];
  maxc:(.vis.W-24) div 6;
  hoff:0|.vis.CX-maxc;                      / h-scroll so the cursor stays visible
  .qvis.text[18;.vis.H-10;1;.qvis.black;maxc sublist hoff _ .vis.CMD];
  if[12>.vis.CFC mod 20;
    .qvis.rect[18+6*.vis.CX-hoff;.vis.H-12;1;11;.qvis.black]];}

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

.vis.repl:{[] .vis.open .vis.replView[]}
.vis.replView:{[]
  st:`lines`cy`cx`off`out`ooff`rc`fc`capture`sa!
    (.vis.REPLB;-1+count .vis.REPLB;count last .vis.REPLB;0;();0;0;0;1b;-1);
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
      st[`cx]:count[st[`lines]st`cy]&0|(ev[`mx]-8) div 6]];
  st[`fc]:1+st`fc;
  .vis.REPLB::st`lines;
  / executed code may itself have opened a view (.vis.tab etc.) and replaced
  / the stack - don't write repl state over it, just yield the frame
  if[$[count .vis.STACK; not `repl~(last .vis.STACK)`name; 1b]; :(::)];
  .vis.putAll st;
  / render: editor pane, blinking cursor, divider, output pane
  off:st`off; shown:.vis.EDR sublist off _ st`lines;
  maxc:(.vis.W-16) div 6;
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
    .qvis.rect[7+6*(st`cx)-hoff;17+10*cyv;1;9;.qvis.white]];
  .qvis.line[0;edh+2;.vis.W;edh+2;.vis.BORD];
  oshown:outr sublist (st`ooff) _ st`out;
  {[y0;i;s] .qvis.text[8;y0+10*i;1;
    $[(0<count s) and "'"=first s;.qvis.red;.qvis.white];s]}[edh+8]
    '[til count oshown;oshown];
  .qvis.text[8;.vis.H-12;1;.qvis.gray;
    "cmd+enter run  cmd+v paste  tab indent  shift+arrows/cmd+a select  cmd+c/x copy/cut  esc back"];}