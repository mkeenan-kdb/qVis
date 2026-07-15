/ qOS.q - a retro desktop environment for kdb+/q, built on qVis + inspect.q.
/ Opens one SDL window styled like an old OS: a teal desktop with icons, a
/ taskbar with a start menu and a clock, and movable/resizable windows that
/ host the .vis inspector views (table browser, namespace explorer, charts,
/ memory monitor, q console, multiline editor). Every .vis entry point
/ (.vis.plot, .vis.tab, .vis.ns, .vis.watchAs ...) opens a NEW window on the
/ desktop instead of taking over the screen, and drill-downs (clicking a
/ table row, "open in editor", filters) stack inside their own window -
/ esc goes back, and closes the window at its root view.
/ Run:            q qOS.q            (from this repo root, qVis checked out
/ Or load:        \l qOS.q           then .qos.start[]
/ Demo data:      q demo.q
/ How it reuses qVis: inspect.q's chart/table draw fns are already
/ box-relative (they honour a `box rect in view state - that is how .vis.dash
/ panels embed them) and access state via .vis.STO. qOS is a window manager
/ that points STO at each window's own view stack; only the draw fns that
/ hardcode fullscreen coordinates (txt/ns/db/mem/repl/watch footer) are
/ redefined below as box-relative versions. .vis.dash itself still assumes
/ the full screen - on qOS, windows ARE the dashboard, so it is not hosted.

/ ---------------------------------------------------------------------------
/ Load inspect.q (which loads qVis.q / qSDL.so)
/ ---------------------------------------------------------------------------
if[0=count getenv`QVIS; -1"qOS: QVIS must be set to the correct path (where qVis.q lives)"; exit 1];
if[not any`qVis.q~/:@[{key hsym`$getenv`QVIS};();enlist()];-1"qOS: QVIS must be set to the correct path (where qVis.q lives)"; exit 1];
if[(::)~@[get;`.vis.tabView;{[e](::)}]; system"l ",(getenv`QVIS),"/inspect.q"];

/ ---------------------------------------------------------------------------
/ Constants and state
/ ---------------------------------------------------------------------------
.qos.TB:26;                                  / taskbar height
.qos.TH:14;                                  / window title-bar height
.qos.MINW:220; .qos.MINH:140;                / minimum window size
.qos.DESK:32896i;                            / desktop teal      0x008080
.qos.FACE:12632256i;                         / chrome face gray  0xC0C0C0
.qos.LT:16777215i;                           / bevel highlight
.qos.DK:4210752i;                            / bevel shadow      0x404040
.qos.MD:8421504i;                            / mid gray          0x808080
.qos.TIT:128i;                               / active title blue 0x000080
.qos.TITI:8421504i;                          / inactive title gray
.qos.CHARTN:`plot`candle`hist`bar`scatter;   / views that need the y-label gutter

.qos.WINS:();                                / window list, z-order bottom->top
.qos.NID:0;                                  / window id counter
.qos.FOC:0N;                                 / focused window id
.qos.DEAD:0#0;                               / ids to purge after the frame
.qos.DRAG:(::);                              / active move/resize drag
.qos.SM:0b;                                  / start menu open?
.qos.CW:0N;                                  / window id owning the current .vis.push/pop context
.qos.MCW:0N;                                 / window id owning the open context menu
.qos.MHR:0 0;                                / context-menu hotspot range in .vis.HOT
.qos.WHEELW:0N;                              / window id under the mouse (wheel routing)
.qos.LCT:0Np; .qos.LCI:`;                    / last click time/target (icon double-click)
.qos.CASC:0;                                 / cascade counter for new windows
.qos.RUN:0b; .qos.OZTS:(::); .qos.OT:0;      / running flag, saved .z.ts and \t
.qos.TICK:0N;                                / current animation \t (0N = unset)
.qos.DEBUG:`debug in lower key .Q.opt .z.x;

/ ---------------------------------------------------------------------------
/ Window list helpers
/ ---------------------------------------------------------------------------
.qos.wix:{[id] $[count .qos.WINS; first where id=.qos.WINS[;`id]; 0N]}
.qos.wset:{[i;k;v] .[`.qos.WINS;(i;k);:;v];}

.qos.spawnAt:{[v;g]
  id:.qos.NID+:1;
  w:`id`x`y`w`h`min`mx`sg`stack`hr!
    (id;`long$g 0;`long$g 1;`long$g 2;`long$g 3;0b;0b;0 0 0 0;enlist v;0 0);
  .qos.WINS,:enlist w;
  .qos.FOC:id;
  id}

.qos.spawn:{[v]
  .qos.CASC:(.qos.CASC+1) mod 8;
  nw:.qos.MINW|`long$.55*.vis.W; wh:.qos.MINH|`long$.55*.vis.H-.qos.TB;
  .qos.spawnAt[v;(60+24*.qos.CASC;24+20*.qos.CASC;nw;wh)]}

.qos.focus:{[id]
  i:.qos.wix id; if[null i; :(::)];
  w:.qos.WINS i;
  .qos.WINS:(.qos.WINS (til count .qos.WINS) except i),enlist w;
  .qos.wset[-1+count .qos.WINS;`min;0b];     / focusing restores a minimised window
  .qos.FOC:id;}

.qos.closeWin:{[id]
  .qos.DEAD,:id;
  if[id~.qos.FOC; .qos.FOC:0N];}

.qos.purge:{[]
  if[count .qos.DEAD;
    if[count .qos.WINS; .qos.WINS:.qos.WINS where not .qos.WINS[;`id] in .qos.DEAD];
    .qos.DEAD:0#0];
  if[null .qos.FOC;
    c:$[count .qos.WINS; where not .qos.WINS[;`min]; 0#0];
    .qos.FOC:$[count c; .qos.WINS[last c;`id]; 0N]];}

.qos.minimise:{[id]
  i:.qos.wix id; if[null i; :(::)];
  .qos.wset[i;`min;1b];
  if[id~.qos.FOC; .qos.FOC:0N];}

.qos.maximise:{[id]
  i:.qos.wix id; if[null i; :(::)]; w:.qos.WINS i;
  $[1b~w`mx;
    .qos.wset[i]'[`x`y`w`h`mx;(w`sg),enlist 0b];
    [.qos.wset[i;`sg;(w`x;w`y;w`w;w`h)];
     .qos.wset[i]'[`x`y`w`h`mx;(4;4;.vis.W-8;(.vis.H-.qos.TB)-8;1b)]]];}

/ topmost non-minimised window (index into .qos.WINS) under a point, or 0N
.qos.topAt:{[mx;my]
  if[not count .qos.WINS; :0N];
  c:where not .qos.WINS[;`min];
  if[not count c; :0N];
  h:{[mx;my;i] w:.qos.WINS i;
    (mx within ((w`x);-1+(w`x)+w`w)) and my within ((w`y);-1+(w`y)+w`h)}[mx;my] each c;
  $[any h; last c where h; 0N]}

/ content box handed to the hosted view's draw fn: charts reserve the y-axis
/ label gutter (as .vis.dash panels do), everything else a slim margin
.qos.cbox:{[w]
  v:last w`stack;
  g:$[((v`name) in .qos.CHARTN) or (string v`name) like "watch-*"; .vis.YLGUT; 8];
  ((w`x)+g; (w`y)+.qos.TH+4; 0|(w`w)-g+6; 0|(w`h)-.qos.TH+30)}

/ ---------------------------------------------------------------------------
/ Route inspect.q's navigation into qOS windows: .vis.open spawns a window,
/ .vis.push/.vis.pop work on the stack of the window in context (.qos.CW).
/ Everything in inspect.q resolves these by name at call time, so tabRow
/ drill-downs, "open in editor", filters etc. all land in windows for free.
/ ---------------------------------------------------------------------------
.vis.open:{[v] .qos.spawn v;}
.vis.close:{[] .qos.stop[]}
.vis.push:{[v]
  i:$[null .qos.CW; 0N; .qos.wix .qos.CW];
  $[null i; .qos.spawn v; .[`.qos.WINS;(i;`stack);,;enlist v]];}
.vis.pop:{[]
  if[null .qos.CW; :(::)];
  i:.qos.wix .qos.CW; if[null i; :(::)];
  $[2>count .qos.WINS[i;`stack];
    .qos.closeWin .qos.CW;
    .[`.qos.WINS;(i;`stack);:;-1_.qos.WINS[i;`stack]]];}

/ run a unary action (a content hotspot / menu act) in a window's context:
/ point STO at its top view's state so .vis.st/.vis.put land there, and give
/ .vis.push/.vis.pop the window to stack into; write the state back after
.qos.inWin:{[id;a]
  i:.qos.wix id;
  if[null i; @[a;(::);{-1"[qOS] action error: ",x;}]; :(::)];
  k:count .qos.WINS[i;`stack];
  .qos.CW::id;
  .vis.STO::.qos.WINS[i;`stack;k-1;`state];
  @[a;(::);{-1"[qOS] action error: ",x;}];
  i2:.qos.wix id;
  if[(not null i2) and k<=count .qos.WINS[i2;`stack];
    .[`.qos.WINS;(i2;`stack;k-1;`state);:;.vis.STO]];
  .vis.STO::(::); .qos.CW::0N;}

/ hit-test last frame's hotspots restricted to one range (a window's own
/ rows, or the context menu's) - fixes click-through between stacked windows
.qos.hitRange:{[r;mx;my;rb]
  sub:.vis.HOT (r 0)+til 0|(r 1)-r 0;
  a:exec act from sub where rc=rb, mx>=x, mx<x+w, my>=y, my<y+h;
  $[count a; last a; ::]}

/ ---------------------------------------------------------------------------
/ Box-relative redefinitions of the inspect.q views that hardcode fullscreen
/ coordinates. Same names, same state keys - everything that constructs or
/ drills into them keeps working.
/ ---------------------------------------------------------------------------
/ text view (function source, values, row inspect)
.vis.txtDraw:{[ev]
  st:.vis.st[]; ls:st`lines;
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  page:1|(ph-14) div 10;
  off:.vis.scroll[ev;page;0|count[ls]-page;st`off]; .vis.put[`off;off];
  shown:page sublist off _ ls;
  maxc:1|pw div .vis.MONOW;
  .vis.qline[x0]'[y0+10*til count shown;maxc sublist' shown];
  s:(string count ls)," lines",$[(st`fq)~(::);"";"   e=edit"];
  .vis.drawText[x0;y0+ph+2;.vis.FONT_PROP;.qvis.gray;s];
  if[not (st`fq)~(::);
    if[`e in ev`new; .vis.openInEditor st`fq]];}

/ namespace explorer
.vis.nsDraw:{[ev]
  st:.vis.st[]; rows:st`rows; n:count rows;
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  page:1|(ph-24) div 10;
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  k0:x0+0|pw-280;
  .vis.drawText[x0;y0;.vis.FONT_PROP;.qvis.yellow;"name"];
  .vis.drawText[k0;y0;.vis.FONT_PROP;.qvis.yellow;"kind"];
  .vis.drawText[k0+70;y0;.vis.FONT_PROP;.qvis.yellow;"type"];
  .vis.drawText[k0+130;y0;.vis.FONT_PROP;.qvis.yellow;"count"];
  .vis.drawText[k0+200;y0;.vis.FONT_PROP;.qvis.yellow;"size"];
  shown:page sublist off _ rows;
  hv:.vis.hoverIx[ev`mx;ev`my;x0-4;y0+11;pw+8;10;count shown];
  if[hv>=0; .qvis.rect[x0-4;y0+11+10*hv;pw+8;10;.vis.HOVER]];
  .vis.nsRow[x0;y0;pw;k0]'[til count shown;shown];
  .vis.drawText[x0;y0+ph+2;.vis.FONT_PROP;.qvis.gray;(string n)," entries   click=open   rclick=menu"];}

.vis.nsRow:{[x0;y0;pw;k0;i;r]
  y:y0+12+10*i;
  col:(`ns`table`dict`var`fn!(.qvis.yellow;.qvis.cyan;.qvis.magenta;.qvis.white;.qvis.green)) r`kind;
  s:string r`fq; if[-10h=type s; s:enlist s];
  .vis.drawText[x0;y;.vis.FONT_PROP;col;(8|(0|pw-290) div 6) sublist s];
  .vis.drawText[k0;y;.vis.FONT_PROP;.qvis.gray;string r`kind];
  .vis.drawText[k0+70;y;.vis.FONT_PROP;.qvis.gray;string r`tp];
  if[not null r`cnt; .vis.drawText[k0+130;y;.vis.FONT_PROP;.qvis.gray;.vis.fmtnum r`cnt]];
  if[not null r`sz; .vis.drawText[k0+200;y;.vis.FONT_PROP;.qvis.gray;.vis.fmtb r`sz]];
  .vis.spot[x0-4;y-1;pw+8;10;.vis.nsAct[r`fq;r`kind]];
  .vis.spotR[x0-4;y-1;pw+8;10;.vis.nsMenu r];}

/ partitioned-database overview
.vis.dbDraw:{[ev]
  st:.vis.st[]; ts:st`ts; n:count ts;
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  .vis.drawText[x0;y0;.vis.FONT_PROP;.qvis.gray;(1|pw div 6) sublist st`hdr];
  page:1|(ph-28) div 12;
  off:.vis.scroll[ev;page;0|n-page;st`off]; .vis.put[`off;off];
  ix:off+til 0|page&n-off;
  mx:1|max 0,raze st[`pns] ix;
  .vis.dbRow[st;mx;x0;y0;pw]'[til count ix;ix];
  .vis.drawText[x0;y0+ph+2;.vis.FONT_PROP;.qvis.gray;"click a table to open"];}

.vis.dbRow:{[st;mx;x0;y0;pw;i;j]
  y:y0+14+12*i;
  t:st[`ts] j;
  .vis.drawText[x0;y;.vis.FONT_PROP;.qvis.cyan;20 sublist string t];
  c:st[`cs] j;
  .vis.drawText[x0+130;y;.vis.FONT_PROP;.qvis.white;$[null c;"?";.vis.fmtnum c]];
  pn:st[`pns] j;
  bw0:0|pw-210;
  if[(0<count pn) and bw0>10;
    bw:2|bw0 div count pn;
    nb:count[pn]&bw0 div bw;
    {[gx;y;bw;mx;i;c] h:1|`long$8*c%mx;
      .qvis.rect[gx+i*bw;y+8-h;1|bw-1;h;.qvis.green]}[x0+200;y;bw;mx]'[til nb;nb sublist pn]];
  .vis.spot[x0-4;y-1;190;11;{[tt;e] .vis.push .vis.tabView[tt;tt]}[t]];}

/ live memory monitor
.vis.memDraw:{[ev]
  st:.vis.st[]; w:.Q.w[];
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  h:-300 sublist st[`hist],w`used; .vis.put[`hist;h];
  mx:1|max w`used`heap`peak;
  {[x0;y0;pw;w;mx;i;k]
    y:y0+13*i;
    .vis.drawText[x0;y;.vis.FONT_PROP;.qvis.gray;string k];
    .vis.drawText[x0+40;y;.vis.FONT_PROP;.qvis.white;.vis.fmtb w k];
    bw:0|pw-110;
    .qvis.rect[x0+104;y+1;bw&`long$bw*(w k)%mx;8;
      $[k=`used;.qvis.green;k=`heap;.qvis.cyan;.qvis.gray]];
  }[x0;y0;pw;w;mx]'[til 5;`used`heap`peak`mmap`syms];
  gy:y0+78;
  .vis.drawText[x0;gy-8;.vis.FONT_PROP;.qvis.gray;"used history"];
  gh:ph-88;
  if[gh>12;
    .vis.plotline[(x0;gy+2;pw;gh);(0f;"f"$1|-1+count h);(0f;"f"$1|max h);
      "f"$til count h;"f"$h;.qvis.green]];}

/ watch: same as inspect.q's minus the screen-corner "watch Nms" footer
.vis.watchDraw:{[ev]
  st:.vis.st[];
  if[(st`ms)<=("j"$.z.P-st`lp)%1e6;
    st:st,.vis.WKIND[st`wk][0] .vis.wfetch st`wt; st[`lp]:.z.P;
    .vis.putAll st];
  .vis.WKIND[st`wk][1] ev;}

/ multiline editor/REPL - same state keys and behaviour, box-relative layout
.vis.replDraw:{[ev]
  st:.vis.st[];
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  edr:1|`long$(.6*ph-16)%10; edh:10*edr;      / editor pane rows / pixel height
  cmd:any .vis.CMDKS in ev`held;
  txt:ev`text; if[10h<>type txt; txt:""];
  se:.vis.replSel[st;ev;cmd]; st:first se;
  ev[`new]:ev[`new] except last se;
  ev[`held]:ev[`held] except last se;
  if[(not cmd) and count txt; st[`sa]:-1; st:.vis.edIns[st;txt]];
  if[cmd and `v in ev`new; st[`sa]:-1; st:.vis.edIns[st;.qvis.clipboard[]]];
  if[`return in ev`new;
    st[`sa]:-1;
    $[cmd;
      [st[`out]:.vis.wrap[1|(pw-4) div .vis.MONOW] .vis.replRun st`lines; st[`ooff]:0];
      st:.vis.edIns[st;enlist "\n"]]];
  st:.vis.edit[st;ev];
  st[`off]:0|$[st[`cy]<st`off; st`cy;
    st[`cy]>st[`off]+edr-1; st[`cy]-edr-1; st`off];
  outr:1|(ph-edh+18) div 10;
  omx:0|count[st`out]-outr;
  if[0<>ev`wheel;
    $[(ev`my)<y0+edh;
      st[`off]:0|(0|count[st`lines]-1)&(st`off)-3*ev`wheel;
      st[`ooff]:0|omx&(st`ooff)-3*ev`wheel]];
  if[`pagedown in ev`new; st[`ooff]:omx&(st`ooff)+outr];
  if[`pageup in ev`new; st[`ooff]:0|(st`ooff)-outr];
  if[ev`click;
    if[((ev`my) within (y0;y0+edh-1)) and (ev`mx) within (x0-4;x0+pw+4);
      st[`sa]:-1;
      st[`cy]:0|(count[st`lines]-1)&(st`off)+((ev`my)-y0) div 10;
      st[`cx]:count[st[`lines]st`cy]&0|((ev`mx)-x0) div .vis.MONOW]];
  .vis.REPLB::st`lines;
  if[1b~st`isScratch; .vis.SCRATCHB::st`lines];
  .vis.putAll st;
  off:st`off; shown:edr sublist off _ st`lines;
  maxc:1|(pw-4) div .vis.MONOW;
  hoff:0|(st`cx)-maxc-1;
  cyv:st[`cy]-off;
  if[cyv within (0;edr-1); .qvis.rect[x0-4;-1+y0+10*cyv;pw+8;10;.vis.GRID]];
  if[0<=st`sa;
    sr:.vis.selRng st;
    {[x0;y0;pw;edr;y] if[y within (0;edr-1); .qvis.rect[x0-4;-1+y0+10*y;pw+8;10;.vis.SELC]]}
      [x0;y0;pw;edr] each (sr[0]+til 1+sr[1]-sr[0])-off];
  {[st;off;maxc;hoff;x0;y0;i;s]
    ho:$[(off+i)=st`cy; hoff; 0];
    .vis.qline[x0;y0+10*i;maxc sublist ho _ s]}[st;off;maxc;hoff;x0;y0]
    '[til count shown;shown];
  if[(cyv within (0;edr-1)) and .qos.blink[];
    .qvis.rect[-1+x0+.vis.textWidth[.vis.FONT_MONO;((st`cx)-hoff) sublist hoff _ st[`lines] st`cy];
      -1+y0+10*cyv;1;9;.qvis.white]];
  .qvis.line[x0-4;y0+edh+2;x0+pw+4;y0+edh+2;.vis.BORD];
  oshown:outr sublist (st`ooff) _ st`out;
  {[x0;y1;i;s] .vis.drawText[x0;y1+10*i;.vis.FONT_MONO;
    $[(0<count s) and "'"=first s;.qvis.red;.qvis.white];s]}[x0;y0+edh+8]
    '[til count oshown;oshown];
  .vis.drawText[x0;y0+ph+2;.vis.FONT_PROP;.qvis.gray;
    (1|pw div 6) sublist "cmd+enter=run   tab=indent   shift+arrows=select   cmd+c/x/v"];}

/ ---------------------------------------------------------------------------
/ q Console - a terminal-style REPL app (one-line prompt, scrolling
/ transcript, shell-style history). Table results open in a browser window.
/ ---------------------------------------------------------------------------
.qos.conView:{[]
  st:`out`in`cx`off`h`hp`hd!(
    ("qOS q console - any q expression, enter runs it";
     "tables open in a browser window; \\cmd runs system commands";"");
    "";0;0;();0N;"");
  `name`draw`state!(`console;.qos.conDraw;st)}

.qos.conRun:{[s]
  s:trim s;
  if[not count s; :()];
  if[s~"\\\\"; .qos.stop[]; exit 0];
  r:@[{(0b;$["\\"=first x; system 1_x; value x])};s;{(1b;x)}];
  $[first r; enlist "'",last r;
    (::)~last r; ();
    .Q.qt last r; [.vis.tab last r; enlist "(opened in table browser)"];
    "\n" vs -1_.Q.s last r]}

.qos.conKey:{[st;k]
  n:count st`in;
  if[k=`left; st[`cx]:0|(st`cx)-1];
  if[k=`right; st[`cx]:n&(st`cx)+1];
  if[k=`home; st[`cx]:0];
  if[k=`end; st[`cx]:n];
  if[(k=`backspace) and (st`cx)>0;
    st[`in]:.vis.edDel[st`in;(st`cx)-1]; st[`cx]:(st`cx)-1];
  if[(k=`delete) and (st`cx)<n; st[`in]:.vis.edDel[st`in;st`cx]];
  st}

.qos.conHist:{[st;k]
  n:count st`h;
  if[n=0; :st];
  if[k=`up;
    if[null st`hp; st[`hd]:st`in; st[`hp]:n];
    st[`hp]:0|(st`hp)-1;
    st[`in]:st[`h] st`hp];
  if[(k=`down) and not null st`hp;
    st[`hp]:(st`hp)+1;
    st[`in]:$[(st`hp)>=n; st`hd; st[`h] st`hp];
    if[(st`hp)>=n; st[`hp]:0N]];
  st[`cx]:count st`in;
  st}

.qos.conDraw:{[ev]
  st:.vis.st[];
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  maxc:1|(pw-4) div .vis.MONOW;
  cmd:any .vis.CMDKS in ev`held;
  ins:$[cmd or 10h<>type ev`text; ""; ev`text];
  if[cmd and `v in ev`new; ins,:.qvis.clipboard[]];
  ins:(),raze {$[x="\t";"  ";x in "\n\r";" ";x]} each ins;
  if[count ins;
    st[`in]:((st`cx)#st`in),ins,(st`cx)_st`in;
    st[`cx]:(st`cx)+count ins; st[`hp]:0N];
  ks:(ev`new) inter .vis.CEK;
  .vis.CRC:$[any .vis.CEK in ev`held; 1+.vis.CRC; 0];
  if[.vis.CRC>10; ks,:(ev`held) inter .vis.CEK];
  st:.qos.conKey/[st;ks];
  st:.qos.conHist/[st;(ev`new) inter `up`down];
  if[(`return in ev`new) and count trim st`in;
    s:trim st`in;
    if[(0=count st`h) or not s~last st`h; st[`h]:st[`h],enlist s];
    st[`h]:-200 sublist st`h; st[`hp]:0N; st[`hd]:"";
    st[`in]:""; st[`cx]:0;
    o:.qos.conRun s;
    st[`out]:-500 sublist (st`out),(enlist "q) ",s),.vis.wrap[maxc;o];
    st[`off]:0];
  rows:1|(ph-18) div 10;
  omx:0|count[st`out]-rows;
  if[0<>ev`wheel; st[`off]:0|omx&(st`off)+3*ev`wheel];
  if[`pageup in ev`new; st[`off]:omx&(st`off)+rows];
  if[`pagedown in ev`new; st[`off]:0|(st`off)-rows];
  .vis.putAll st;
  shown:neg[rows] sublist (0|count[st`out]-st`off) sublist st`out;
  {[x0;y0;maxc;i;s]
    s:maxc sublist s;
    $[(3<=count s) and "q) "~3 sublist s; .vis.qline[x0;y0+10*i;s];
      .vis.drawText[x0;y0+10*i;.vis.FONT_MONO;
        $[(0<count s) and "'"=first s;.qvis.red;.qvis.white];s]]}[x0;y0;maxc]
    '[til count shown;shown];
  iy:y0+ph-8;
  .qvis.line[x0-4;iy-4;x0+pw+4;iy-4;.vis.BORD];
  .vis.drawText[x0;iy;.vis.FONT_MONO;.qvis.green;"q)"];
  ix:x0+.vis.textWidth[.vis.FONT_MONO;"q) "];
  imax:1|(pw-20) div .vis.MONOW;
  hoff:0|(st`cx)-imax;
  .vis.qline[ix;iy;imax sublist hoff _ st`in];
  if[.qos.blink[];
    .qvis.rect[ix+.vis.textWidth[.vis.FONT_MONO;((st`cx)-hoff) sublist hoff _ st`in];
      iy-1;1;10;.qvis.white]];}

.qos.about:{[]
  .qos.spawn .vis.txtView[`about;(
    "qOS 1.0 - a desktop for kdb+/q, built on qVis";
    "";
    "/ drag a title bar to move a window, the corner grip to resize";
    "/ title buttons: _ minimise   o maximise   x close";
    "/ esc goes back inside a window, and closes it at its root view";
    "/ double-click a desktop icon, or use the qOS start menu";
    "";
    "/ open the q Console and drive the session:";
    ".vis.plot sin 0.05*til 500";
    ".vis.tab `trade";
    ".vis.ns[]";
    ".vis.watchAs[`trade;1000;`candle]";
    "";
    "/ every .vis view opens as a desktop window; click rows to drill";
    "/ down, right-click cells and namespace entries for context menus";
    "");::]}

/ ---------------------------------------------------------------------------
/ Chrome drawing
/ ---------------------------------------------------------------------------
.qos.bevel:{[x;y;w;h;up]
  .qvis.rect[x;y;w;h;.qos.FACE];
  a:$[up;.qos.LT;.qos.DK]; b:$[up;.qos.DK;.qos.LT];
  .qvis.line[x;y;x+w-2;y;a]; .qvis.line[x;y;x;y+h-2;a];
  .qvis.line[x;y+h-1;x+w-1;y+h-1;b]; .qvis.line[x+w-1;y;x+w-1;y+h-1;b];}

.qos.btn:{[bx;by;g]
  .qos.bevel[bx;by;12;12;1b];
  .vis.drawText[bx+3;by+1;.vis.FONT_PROP;.qvis.black;g];}

.qos.drawWin:{[ev;i]
  w:.qos.WINS i;
  if[1b~w`min; :(::)];
  if[0=count w`stack; .qos.closeWin w`id; :(::)];
  x:w`x; y:w`y; nw:w`w; wh:w`h;
  foc:(w`id)~.qos.FOC;
  .qos.bevel[x-3;y-3;nw+6;wh+6;1b];
  .qvis.rect[x;y;nw;.qos.TH;$[foc;.qos.TIT;.qos.TITI]];
  ttl:" > " sv {string x`name} each w`stack;
  .vis.drawText[x+4;y+2;.vis.FONT_PROP;.qvis.white;(1|(nw-52) div 6) sublist ttl];
  bx0:x+nw-42;
  .qvis.rect[x;y+.qos.TH;nw;wh-.qos.TH;.vis.BG];
  .qos.btn[bx0;y+1;enlist "_"]; .qos.btn[bx0+14;y+1;enlist "o"]; .qos.btn[bx0+28;y+1;enlist "x"];
  v:last w`stack;
  st:v`state; st:st,enlist[`box]!enlist .qos.cbox w;
  .qos.CW::w`id;
  .vis.STO::st;
  k:count w`stack;
  pev:ev;
  if[not foc; pev[`new]:0#`; pev[`held]:0#`; pev[`text]:""; pev[`click]:0b; pev[`rclick]:0b];
  if[not (.qos.WHEELW)~w`id; pev[`wheel]:0];
  h0:count .vis.HOT;
  err:@[{x y; 0b}[v`draw];pev;{-1"[qOS] view error: ",x; 1b}];
  .qos.wset[i;`hr;(h0;count .vis.HOT)];
  if[k<=count .qos.WINS[i;`stack];
    .[`.qos.WINS;(i;`stack;k-1;`state);:;.vis.STO]];
  .vis.STO::(::); .qos.CW::0N;
  if[err; $[2>count .qos.WINS[i;`stack];
    .qos.closeWin w`id;
    .[`.qos.WINS;(i;`stack);:;-1_.qos.WINS[i;`stack]]]];
  {[gx;gy;d] .qvis.line[gx-d;gy;gx;gy-d;.qos.MD]}[x+nw-3;y+wh-3] each 3 6 9;}

/ ---------------------------------------------------------------------------
/ Desktop icons
/ ---------------------------------------------------------------------------
/ # black  W white  w silver  T gray  t dark gray  B blue  b navy  C cyan
/ Y yellow o orange G green   g dark green  R red  r dark red  ("." = transparent)
.qos.iconPalette: "#WwTtBbCYoGgRr"!(0i;16777215i;12632256i;8421504i;4210752i;
  255i;128i;65535i;16776960i;16744448i;65280i;32768i;16711680i;8388608i);

.qos.drawPixelArt:{[x;y;art;palette;scale]
  {[x;y;pal;s;j;row]
    {[x;y;pal;s;j;i;c]
      if[c in key pal; .qvis.rect[x+i*s;y+j*s;s;s;pal c]]
    }[x;y;pal;s;j]'[til count row;row]
  }[x;y;palette;scale]'[til count art;art];}

.qos.ICONS:([]
  nm:("q Console";"Editor";"Games";"Simulations";"Namespaces";"Tables";"Memory";"About");
  art:(
    (                             / terminal: navy titlebar, green prompt
      "................";
      ".tttttttttttttt.";
      ".tbbbbbbbbbbRRt.";
      ".tbbbbbbbbbbRRt.";
      ".tttttttttttttt.";
      ".t############t.";
      ".t#G##########t.";
      ".t##G#########t.";
      ".t###G########t.";
      ".t##G###GGG###t.";
      ".t#G##########t.";
      ".t############t.";
      ".tttttttttttttt.";
      "................";
      "................";
      "................"
    );
    (                             / notepad with a pencil across it
      "................";
      ".tttttttttt.....";
      ".tWWWWWWWWt.....";
      ".tWbbbbbbWt..rr.";
      ".tWWWWWWWWt.YY..";
      ".tWbbbbbbWtYY...";
      ".tWWWWWWWWYY....";
      ".tWbbbbbbYY.....";
      ".tWWWWWWYYt.....";
      ".tWWWWWooWt.....";
      ".tWWWW#WWWt.....";
      ".tWbbbbbbWt.....";
      ".tWWWWWWWWt.....";
      ".tttttttttt.....";
      "................";
      "................"
    );
    (                             / folder with a gamepad
      "................";
      "................";
      ".ooooo..........";
      ".oYYYoooooooooo.";
      ".oYYYYYYYYYYYYo.";
      ".oYYYYYYYYYYYYo.";
      ".oYYYYYYYYYYYYo.";
      ".oY##########Yo.";
      ".oY#WW##RR#GGYo.";
      ".oY#WW##RR#GGYo.";
      ".oY##########Yo.";
      ".oYYYYYYYYYYYYo.";
      ".oooooooooooooo.";
      "................";
      "................";
      "................"
    );
    (                             / folder with an atom
      "................";
      "................";
      ".ooooo..........";
      ".oYYYoooooooooo.";
      ".oYYYYYYYYYYYYo.";
      ".oYYYYCCCCYYYYo.";
      ".oYYCCYYYYCCYYo.";
      ".oYYCYYRRYYCYYo.";
      ".oYYCYYRRYYCYYo.";
      ".oYYCCYYYYCCYYo.";
      ".oYYYYCCCCYYYYo.";
      ".oYYYYYYYYYYYYo.";
      ".oooooooooooooo.";
      "................";
      "................";
      "................"
    );
    (                             / tree: root fanning out to children
      "................";
      "................";
      "......CCCC......";
      "......CCCC......";
      ".......WW.......";
      "...WWWWWWWWWW...";
      "...W...WW...W...";
      "..GGG.GGGG.GGG..";
      "..GGG.GGGG.GGG..";
      "..GGG.GGGG.GGG..";
      "................";
      "................";
      "................";
      "................";
      "................";
      "................"
    );
    (                             / spreadsheet: header row + grid
      "................";
      "................";
      ".BBBBBBBBBBBBBB.";
      ".BWWBBBWWBBBWWB.";
      ".WWWWtWWWWtWWWW.";
      ".WWWWtWWWWtWWWW.";
      ".tttttttttttttt.";
      ".WWWWtWWWWtWWWW.";
      ".WWWWtWWWWtWWWW.";
      ".tttttttttttttt.";
      ".WWWWtWWWWtWWWW.";
      ".WWWWtWWWWtWWWW.";
      ".tttttttttttttt.";
      "................";
      "................";
      "................"
    );
    (                             / RAM stick: chips, traces, gold pins
      "................";
      "................";
      "................";
      "................";
      "..gggggggggggg..";
      "..gg##g##g##gg..";
      "..gg##g##g##gg..";
      "..gggggggggggg..";
      "..gGgGgGgGgGgg..";
      "..gggggggggggg..";
      "..YYgYYgYYgYYg..";
      "................";
      "................";
      "................";
      "................";
      "................"
    );
    (                             / blue badge with a question mark
      "................";
      ".....BBBBB......";
      "...BBBBBBBBB....";
      "..BBBBBBBBBBB...";
      "..BBBWWWWBBBB...";
      "..BBWWBBWWBBB...";
      ".BBBBBBBWWBBBB..";
      ".BBBBBBWWBBBBB..";
      ".BBBBBWWBBBBBB..";
      "..BBBBWWBBBBB...";
      "..BBBBBBBBBBB...";
      "..BBBBWWBBBBB...";
      "...BBBBBBBBB....";
      ".....BBBBB......";
      "................";
      "................"
    )
  );
  act:({[e] .qos.spawn .qos.conView[]};{[e] .vis.repl[]};
       {[e] .qos.spawn .qos.folderView[`games;.qos.GAMES]};
       {[e] .qos.spawn .qos.folderView[`simulations;.qos.SIMS]};
       {[e] .vis.ns[]};{[e] .vis.db[]};{[e] .vis.mem[]};{[e] .qos.about[]}));

/ ---------------------------------------------------------------------------
/ Folders - windows of app launchers. The example apps own .z.ts and their
/ own SDL window, so they can't be hosted in a qOS window; each one launches
/ as a separate q process with its own window instead.
/ ---------------------------------------------------------------------------
.qos.GAMES:(
  ("Demon Arena";"apps/fps.q");
  ("Touchdown Run";"apps/football.q");
  ("Doom";"apps/exampleDoom.q"));

.qos.SIMS:(
  ("Game of Life";"apps/exampleLife.q");
  ("Boids";"apps/exampleBoids.q");
  ("Slime Mould";"apps/examplePhysarum.q");
  ("Fluid";"apps/exampleFluid.q");
  ("Falling Sand";"apps/exampleSand.q");
  ("N-Body";"apps/exampleNBody.q");
  ("Ripple";"apps/exampleRipple.q");
  ("Mandelbrot";"apps/exampleMandelbrot.q");
  ("Ray Tracer";"apps/exampleRay.q");
  ("Plasma";"apps/exampleAnimation.q");
  ("Bounce";"apps/exampleBounce.q");
  ("Order Book";"apps/exampleFinance.q");
  ("Text FX";"apps/exampleText.q"));

/ mini app window with a play button - one shared icon for folder items
.qos.FILEART:(
  "................";
  "................";
  "..tttttttttttt..";
  "..tbbbbbbbbbbt..";
  "..tttttttttttt..";
  "..t##########t..";
  "..t###G######t..";
  "..t###GG#####t..";
  "..t###GGG####t..";
  "..t###GG#####t..";
  "..t###G######t..";
  "..t##########t..";
  "..tttttttttttt..";
  "................";
  "................";
  "................");

/ malformed art renders garbage silently - fail loudly at load instead
if[not all raze {(16=count x),16=count each x} each
    .qos.ICONS[`art],enlist .qos.FILEART;
  '"qOS: icon art must be 16 rows of 16 chars"];

/ Open an app inside the qOS session: the script re-inits the shared SDL
/ window at its own resolution and installs its own .z.ts + timer; qOS's
/ frame loop is parked while it runs. esc (or the app's own quit path, which
/ ends with "\t 0") restores the desktop exactly as it was. Only one app
/ runs at a time - launching another replaces it. Paths are repo-root
/ relative: qOS runs from the repo root.
.qos.APPTS:(::);                             / hosted app's tick fn ((::) = none)

.qos.launch:{[p]
  if[not (::)~.qos.APPTS; .qos.appStop[]];
  -1 "[qOS] opening ",p," - esc returns to the desktop";
  zts:@[get;`.z.ts;{[e](::)}];
  .qvis.pollReset[];
  p:(getenv`QVIS),"/",p;
  ok:@[{system "l ",x; 1b};p;{-1 "[qOS] app load error: ",x; 0b}];
  $[ok and not zts~.z.ts;
    [.qos.APPTS:.z.ts; .z.ts:{.qos.appTick[]}];
    .qos.appStop[]];}                        / load failed / no loop - restore desktop

.qos.appTick:{[]
  if[`escape in .qvis.keyz[]; :.qos.appStop[]];
  @[.qos.APPTS;(::);{-1 "[qOS] app error: ",x; .qos.appStop[]}];
  if[(::)~.qos.APPTS; :(::)];                / the trap above already restored
  if[0=system "t"; .qos.appStop[]];}         / app quit its own loop (close button)

.qos.appStop:{[]
  .qos.APPTS:(::);
  .[.qvis.init;(.vis.W;.vis.H;.vis.SC);{[e]::}];  / back to desktop size (re-opens if the app shut the window)
  .vis.FONT_PROP:.qvis.loadsysfont[`prop;8]; / an app quitting via .qvis.shutdown drops fonts - reload
  .vis.FONT_MONO:.qvis.loadsysfont[`mono;8];
  if[.vis.FONT_MONO>=0; .vis.MONOW:first .qvis.textsize[.vis.FONT_MONO;"a"]];
  .qvis.pollReset[];
  .z.ts:.qos.FRAMETS;
  / an app quitting via .qvis.shutdown cleared the native callback - re-arm
  .qvis.seteventcb".qos.FRAMETS";
  .qos.TICK:0N; .qos.retime[];}

.qos.folderView:{[nm;items]
  `name`draw`state!(nm;.qos.folderDraw;enlist[`items]!enlist items)}

.qos.folderDraw:{[ev]
  st:.vis.st[];
  bx:.vis.boxOr[st;.vis.TBOX]; x0:bx 0; y0:bx 1; pw:bx 2; ph:bx 3;
  cw:78; ch:46; nc:1|pw div cw;
  {[x0;y0;cw;ch;nc;i;it]
    cx:x0+cw*i mod nc; cy:y0+ch*i div nc;
    .qos.drawPixelArt[cx+(cw-32) div 2;cy;.qos.FILEART;.qos.iconPalette;2];
    w:.vis.textWidth[.vis.FONT_PROP;first it];
    .vis.drawText[cx+0|(cw-w) div 2;cy+28;.vis.FONT_PROP;.qvis.white;
      (1|cw div 6) sublist first it];
    .vis.spot[cx;cy;cw;ch-2;{[p;e] .qos.launch p} last it];
  }[x0;y0;cw;ch;nc]'[til count st`items;st`items];
  .vis.drawText[x0;y0+ph+2;.vis.FONT_PROP;.qvis.gray;
    (1|pw div 6) sublist "click an app to open it   esc returns to the desktop"];}

.qos.drawIcons:{[]
  {[i;r]
    y:14+50*i;
    .qos.drawPixelArt[16;y;r`art;.qos.iconPalette;2];
    w:.vis.textWidth[.vis.FONT_PROP;r`nm];
    .vis.drawText[0|32-w div 2;y+34;.vis.FONT_PROP;.qvis.white;r`nm];
  }'[til count .qos.ICONS;.qos.ICONS];}

.qos.iconClick:{[mx;my]
  n:count .qos.ICONS;
  i:(my-14) div 50;
  hit:(mx within (12;52)) and (i>=0) and (i<n) and ((my-14) mod 50)<42;
  if[not hit; .qos.LCI:`; :(::)];
  tgt:`$"icon",string i;
  $[(tgt~.qos.LCI) and (.z.P-.qos.LCT)<0D00:00:00.4;
    [@[.qos.ICONS[i;`act];(::);{-1"[qOS] error: ",x;}]; .qos.LCI:`];
    [.qos.LCI:tgt; .qos.LCT:.z.P]];}

.qos.deskMenu:{[]
  .vis.menu[("open q Console";"open Editor";"games";"simulations";
             "namespaces";"memory monitor";"about qOS");
    ({[e] .qos.spawn .qos.conView[]};{[e] .vis.repl[]};
     {[e] .qos.spawn .qos.folderView[`games;.qos.GAMES]};
     {[e] .qos.spawn .qos.folderView[`simulations;.qos.SIMS]};
     {[e] .vis.ns[]};{[e] .vis.mem[]};{[e] .qos.about[]})];}

/ ---------------------------------------------------------------------------
/ Taskbar + start menu
/ ---------------------------------------------------------------------------
.qos.drawTaskbar:{[]
  y:.vis.H-.qos.TB;
  .qos.bevel[0;y;.vis.W;.qos.TB;1b];
  .qos.bevel[4;y+4;46;.qos.TB-8;not .qos.SM];
  .vis.drawText[13;y+8;.vis.FONT_PROP;.qvis.black;"qOS"];
  cw:56;
  .qos.bevel[.vis.W-cw+6;y+4;cw;.qos.TB-8;0b];
  .vis.drawText[.vis.W-cw;y+8;.vis.FONT_PROP;.qvis.black;8 sublist string .z.T];
  n:count .qos.WINS;
  if[n=0; :(::)];
  bw:30|140&((.vis.W-74+cw) div n)-4;
  ids:asc .qos.WINS[;`id];
  {[y;bw;ids;j]
    id:ids j; i:.qos.wix id; w:.qos.WINS i;
    bx:56+j*bw+4;
    foc:(id~.qos.FOC) and not w`min;
    .qos.bevel[bx;y+4;bw;.qos.TB-8;not foc];
    ttl:string (last w`stack)`name;
    .vis.drawText[bx+4;y+8;.vis.FONT_PROP;$[1b~w`min;.qos.MD;.qvis.black];
      (1|(bw-8) div 6) sublist ttl];
  }[y;bw;ids] each til n;}

.qos.tbClick:{[mx;my]
  y:.vis.H-.qos.TB;
  if[mx within (4;50); .qos.SM:not .qos.SM; :(::)];
  n:count .qos.WINS;
  if[n=0; :(::)];
  cw:56;
  bw:30|140&((.vis.W-74+cw) div n)-4;
  j:(mx-56) div bw+4;
  if[(mx>=56) and j within (0;n-1);
    ids:asc .qos.WINS[;`id]; id:ids j;
    w:.qos.WINS .qos.wix id;
    $[1b~w`min; .qos.focus id;
      id~.qos.FOC; .qos.minimise id;
      .qos.focus id]];}

.qos.SMIT:(
  ("q Console";{[e] .qos.spawn .qos.conView[]});
  ("Editor";{[e] .vis.repl[]});
  ("Games";{[e] .qos.spawn .qos.folderView[`games;.qos.GAMES]});
  ("Simulations";{[e] .qos.spawn .qos.folderView[`simulations;.qos.SIMS]});
  ("Namespace Explorer";{[e] .vis.ns[]});
  ("Tables / DB";{[e] .vis.db[]});
  ("Memory Monitor";{[e] .vis.mem[]});
  ("About qOS";{[e] .qos.about[]});
  ("Exit desktop";{[e] .qos.stop[]});
  ("Shut down q...";{[e] .qos.stop[]; exit 0}));

.qos.drawSM:{[mx;my]
  n:count .qos.SMIT; ih:16; w:160; h:8+ih*n;
  x0:4; y0:(.vis.H-.qos.TB)-h;
  .qvis.rect[x0+3;y0+3;w;h;.vis.SHADOW];
  .qos.bevel[x0;y0;w;h;1b];
  .qvis.rect[x0+3;y0+3;18;h-6;.qos.TIT];
  .vis.drawText[x0+6;y0+h-14;.vis.FONT_PROP;.qvis.white;"qOS"];
  {[x0;y0;ih;w;mx;my;i;it]
    y:y0+4+ih*i;
    hv:(mx within (x0;x0+w-1)) and my within (y;y+ih-1);
    if[hv; .qvis.rect[x0+23;y;w-26;ih;.qos.TIT]];
    .vis.drawText[x0+28;y+3;.vis.FONT_PROP;$[hv;.qvis.white;.qvis.black];first it];
  }[x0;y0;ih;w;mx;my]'[til n;.qos.SMIT];}

.qos.smClick:{[mx;my]
  n:count .qos.SMIT; ih:16; w:160; h:8+ih*n;
  x0:4; y0:(.vis.H-.qos.TB)-h;
  .qos.SM:0b;
  if[not (mx within (x0;x0+w-1)) and my within (y0;y0+h-1); :(::)];
  i:(my-y0+4) div ih;
  if[i within (0;n-1); @[(.qos.SMIT i)1;(::);{-1"[qOS] error: ",x;}]];}

/ ---------------------------------------------------------------------------
/ Input routing
/ ---------------------------------------------------------------------------
.qos.winClick:{[i;mx;my]
  w:.qos.WINS i; x:w`x; y:w`y; nw:w`w; wh:w`h; id:w`id;
  if[my within (y;y+.qos.TH-1);
    bx0:x+nw-42;
    if[mx>=bx0;
      j:(mx-bx0) div 14;
      $[j=0; .qos.minimise id; j=1; .qos.maximise id; .qos.closeWin id];
      :(::)];
    .qos.DRAG::`id`mode`dx`dy!(id;`move;mx-x;my-y);
    :(::)];
  if[(mx>x+nw-14) and my>y+wh-14;
    .qos.DRAG::`id`mode`dx`dy!(id;`size;(x+nw)-mx;(y+wh)-my);
    :(::)];
  a:.qos.hitRange[w`hr;mx;my;0b];
  if[not (::)~a; .qos.inWin[id;a]];}

.qos.click:{[ev]
  mx:ev`mx; my:ev`my;
  if[count .vis.MENU;
    a:.qos.hitRange[.qos.MHR;mx;my;0b];
    .vis.MENU:();
    if[not (::)~a;
      $[null .qos.MCW; @[a;(::);{-1"[qOS] error: ",x;}]; .qos.inWin[.qos.MCW;a]]];
    :(::)];
  if[.qos.SM; .qos.smClick[mx;my]; :(::)];
  if[my>=.vis.H-.qos.TB; .qos.tbClick[mx;my]; :(::)];
  t:.qos.topAt[mx;my];
  if[not null t;
    id:.qos.WINS[t;`id];
    .qos.focus id;
    .qos.winClick[.qos.wix id;mx;my];
    :(::)];
  .qos.iconClick[mx;my];}

.qos.rclick:{[ev]
  mx:ev`mx; my:ev`my;
  .vis.RCX:mx; .vis.RCY:my; .vis.MENU:(); .qos.SM:0b;
  if[my>=.vis.H-.qos.TB; :(::)];
  t:.qos.topAt[mx;my];
  $[not null t;
    [id:.qos.WINS[t;`id]; .qos.focus id; .qos.MCW:id;
     a:.qos.hitRange[.qos.WINS[.qos.wix id;`hr];mx;my;1b];
     if[not (::)~a; .qos.inWin[id;a]]];
    [.qos.MCW:0N; .qos.deskMenu[]]];}

.qos.dragStep:{[ev]
  if[(::)~.qos.DRAG; :(::)];
  if[not .qvis.PL; .qos.DRAG::(::); :(::)];
  d:.qos.DRAG; i:.qos.wix d`id;
  if[null i; .qos.DRAG::(::); :(::)];
  mx:ev`mx; my:ev`my;
  $[`move~d`mode;
    [.qos.wset[i;`x;(40-.qos.WINS[i;`w])|(.vis.W-40)&mx-d`dx];
     .qos.wset[i;`y;0|((.vis.H-.qos.TB)-10)&my-d`dy]];
    [.qos.wset[i;`w;.qos.MINW|(mx+d`dx)-.qos.WINS[i;`x]];
     .qos.wset[i;`h;.qos.MINH|(my+d`dy)-.qos.WINS[i;`y]]]];}

.qos.escWin:{[id]
  i:.qos.wix id; if[null i; :(::)];
  $[2>count .qos.WINS[i;`stack];
    .qos.closeWin id;
    .[`.qos.WINS;(i;`stack);:;-1_.qos.WINS[i;`stack]]];}

.qos.esc:{[]
  $[.qos.SM; .qos.SM:0b;
    count .vis.MENU; .vis.MENU:();
    not null .qos.FOC; .qos.escWin .qos.FOC;
    ::];}

/ ---------------------------------------------------------------------------
/ Frame loop - event-driven. The native layer applies .qos.FRAMETS the moment
/ SDL input/window events arrive (.qvis.seteventcb), so clicks, typing and
/ drags render immediately with no polling. .z.ts is only the animation
/ heartbeat: .qos.retime keeps \t at the slowest rate the visible views need
/ (1s taskbar clock when idle, cursor blink, watch/mem refresh) instead of a
/ fixed 30fps repaint.
/ ---------------------------------------------------------------------------
.qos.FRAMETS:{$[.qos.DEBUG;.qos.frame[];@[.qos.frame;(::);{-1"[qOS] frame error: ",x; .qos.stop[]}]]};

/ cursor blink phase from the wall clock (on 550ms of each second) - frames
/ only happen on events and animation ticks now, so a frame counter would
/ blink at whatever rate frames happen to fire
.qos.blink:{[] 550>(("j"$.z.P) mod 1000000000) div 1000000}

/ slowest \t that keeps everything visible animated; input never waits on
/ this - it arrives through the native event callback
.qos.cadence:{[]
  t:1000;                                    / taskbar clock shows seconds
  if[count .qos.WINS;
    tops:{[w] last w`stack} each .qos.WINS where not .qos.WINS[;`min];
    nms:{[v] v`name} each tops;
    if[any nms in `console`repl; t&:300];    / cursor blink
    if[`mem in nms; t&:250];                 / live memory monitor
    ws:tops where (string each nms) like "watch-*";
    / half the refresh interval so a fetch is never a full period late
    if[count ws; t&:33|min {[v] (v[`state]`ms) div 2} each ws]];
  `long$t}

.qos.retime:{[]
  t:.qos.cadence[];
  if[not t~.qos.TICK; .qos.TICK:t; system"t ",string t];}

.qos.frame:{[]
  if[not .qos.RUN; :(::)];
  / while a hosted app runs, its own .z.ts owns the session - an event wake
  / landing here would steal poll[]'s read-and-reset wheel/text from the app
  if[not (::)~.qos.APPTS; :(::)];
  ev:.qvis.poll[];
  if[ev`closed; .qos.stop[]; :(::)];
  .qos.dragStep ev;
  if[`escape in ev`new; .qos.esc[]];
  if[ev`click; .qos.click ev];
  if[ev`rclick; .qos.rclick ev];
  / a click above may have launched an app (its script drew its first frame);
  / don't paint the desktop over it - apps that only redraw on input (mandelbrot,
  / ray) would otherwise show a stale desktop and look like they never opened
  if[not (::)~.qos.APPTS; :(::)];
  if[not .qos.RUN; :(::)];
  .qos.purge[];
  .vis.HOT:0#.vis.HOT;
  .qvis.clear .qos.DESK;
  .qos.drawIcons[];
  .qos.WHEELW:$[null t:.qos.topAt[ev`mx;ev`my]; 0N; .qos.WINS[t;`id]];
  .qos.drawWin[ev] each til count .qos.WINS;
  .qos.purge[];
  .qos.drawTaskbar[];
  if[.qos.SM; .qos.drawSM[ev`mx;ev`my]];
  m0:count .vis.HOT;
  .vis.menuDraw[ev`mx;ev`my];
  .qos.MHR:(m0;count .vis.HOT);
  .qvis.present[];
  .qos.retime[];}

.qos.start:{[]
  if[.qos.RUN; :(::)];
  .[.qvis.init;(.vis.W;.vis.H;.vis.SC);{[e]::}];
  .vis.FONT_PROP:.qvis.loadsysfont[`prop;8];
  .vis.FONT_MONO:.qvis.loadsysfont[`mono;8];
  if[.vis.FONT_MONO>=0; .vis.MONOW:first .qvis.textsize[.vis.FONT_MONO;"a"]];
  .qos.OZTS:@[get;`.z.ts;{[e](::)}];
  .qos.OT:system"t";
  .qos.RUN:1b;
  .vis.HOT:0#.vis.HOT; .qvis.pollReset[];
  if[0=count .qos.WINS; .qos.about[]];
  .z.ts:.qos.FRAMETS;                        / animation heartbeat only
  .qvis.seteventcb".qos.FRAMETS";            / input renders via event wakes
  .qos.TICK:0N; .qos.retime[];
  .qos.frame[];                              / paint the desktop now, not a tick later
  -1"[qOS] desktop running - esc closes windows, .qos.stop[] exits the desktop";}

.qos.stop:{[]
  if[not .qos.RUN; :(::)];
  .qos.RUN:0b;
  @[.qvis.seteventcb;"";::];                 / stop event wakes before handing .z.ts back
  .qos.WINS:(); .qos.DEAD:0#0; .qos.DRAG:(::); .qos.SM:0b;
  .vis.MENU:(); .qos.FOC:0N; .qos.CW:0N; .qos.MCW:0N;
  system"t ",string .qos.OT;
  $[(::)~.qos.OZTS; @[system;"x .z.ts";::]; .z.ts:.qos.OZTS];
  .qvis.shutdown[];
  -1"[qOS] desktop closed - .qos.start[] to reopen";}

-1"[qOS] loaded - .qos.start[] opens the desktop";
if[(string .z.f) like "*qOS.q"; .qos.start[]];
