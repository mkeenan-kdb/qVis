/ smoke.q - headless assertions on inspect.q's pure helpers.
/ Run from the repo root:  q tests/smoke.q -q
/ Loading inspect.q binds qSDL.so but never opens a window (q_init not called).

system "l inspect.q"

ok:{[nm;c] $[c; -1 "PASS ",nm; [-2 "FAIL ",nm; exit 1]];}

/ nice ticks
ok["nice basic";    .vis.nice[0;97;5]~0 20 40 60 80f];
ok["nice full";     .vis.nice[0;100;5]~0 20 40 60 80 100f];
ok["nice negative"; .vis.nice[-50;50;5]~-40 -20 0 20 40f];
ok["nice sub-1";    .vis.nice[0;0.97;5]~0 .2 .4 .6 .8];
ok["nice degenerate"; 1=count .vis.nice[3;3;4] where .vis.nice[3;3;4]=3f];

/ number / byte formatting
ok["fmtnum plain"; "12"~.vis.fmtnum 12];
ok["fmtnum K";     "1.23K"~.vis.fmtnum 1234];
ok["fmtnum M";     "1.5M"~.vis.fmtnum 1500000];
ok["fmtnum neg";   "-2K"~.vis.fmtnum -2000];
ok["fmtb GB";      "1.07GB"~.vis.fmtb 1073741824];
ok["fmtb B";       "512B"~.vis.fmtb 512];

/ cell rendering and column widths
t:([] a:1 2; b:`x`yy; c:("aa";"bb"); d:(1 2;3 4 5));
cl:.vis.cells t;
ok["cells long";   cl[0]~(enlist "1";enlist "2")];
ok["cells sym";    cl[1]~(enlist "x";"yy")];
ok["cells str";    cl[2]~("aa";"bb")];
ok["cells nested"; cl[3]~("1 2";"3 4 5")];
ok["widths";       20 128~.vis.widths[("ab";"cdef");
  (("x";"yy");("123456789012345678901234567";"z"))]];

/ wrap
ok["wrap split"; .vis.wrap[5;enlist "abcdefghij"]~("abcde";"fghij")];
ok["wrap blank"; .vis.wrap[5;("";"ab")]~("";"ab")];

/ scroll clamping (fixture event with nothing pressed)
ev:`new`held`click`mx`my`wheel`back`close!(0#`;0#`;0b;0;0;0;0b;0b);
ok["scroll clamp hi"; 50=.vis.scroll[ev;10;50;60]];
ok["scroll clamp lo"; 0=.vis.scroll[ev;10;50;-5]];
ok["scroll wheel";    4=.vis.scroll[@[ev;`wheel;:;2];10;50;10]];
ok["scroll end";      50=.vis.scroll[@[ev;`new;:;enlist `end];10;50;0]];

/ arrows move on press, auto-repeat after ~1/3s, accelerate on a long hold
.vis.SRC:0;
ok["scroll press";   11=.vis.scroll[@[ev;`new`held;:;(enlist `down;enlist `down)];10;50;10]];
ok["scroll no rpt";  11=.vis.scroll[@[ev;`held;:;enlist `down];10;50;11]];
.vis.SRC:20;
ok["scroll repeat";  12=.vis.scroll[@[ev;`held;:;enlist `down];10;50;11]];
.vis.SRC:100;
ok["scroll accel";   36=.vis.scroll[@[ev;`held;:;enlist `down];10;50;11]];
.vis.SRC:0;

/ namespace listing over a fixture namespace
.smoketest.a:til 5;
.smoketest.f:{x+1};
.smoketest.t:([] x:1 2);
r:.vis.nsList `.smoketest;
ok["nsList count"; 3=count r];
ok["nsList table"; `table=first exec kind from r where fq=`.smoketest.t];
ok["nsList fn";    `fn=first exec kind from r where fq=`.smoketest.f];
ok["nsList var";   `var=first exec kind from r where fq=`.smoketest.a];
ok["nsList cnt";   2=first exec cnt from r where fq=`.smoketest.t];
ok["nsList root has ns"; `ns in exec kind from .vis.nsList `.];

/ table view construction (no window needed)
v:.vis.tabView[([] a:til 10; b:10?`3);`t];
ok["tabView rows";   10=v[`state;`n]];
ok["tabView unsorted"; 0=count v[`state;`idx]];
ok["tabView hdrs";   "a j"~first v[`state;`hdrs]];

/ index-based sort: the table is never copied, only a permutation is kept
.vis.STACK:enlist .vis.tabView[([] a:3 1 2; b:`x`y`z);`t];
.vis.tabSort[`a;::];
ok["sort asc";  1 2 3~(.vis.tabFetch[.vis.st[];0;3])`a];
ok["sort asc b"; `y`z`x~(.vis.tabFetch[.vis.st[];0;3])`b];
.vis.tabSort[`a;::];
ok["sort desc"; 3 2 1~(.vis.tabFetch[.vis.st[];0;3])`a];
ok["sort page"; 2 1~(.vis.tabFetch[.vis.st[];1;2])`a];

/ row drill-down pushes a text view of the full record (uses the sort order)
.vis.tabRow[.vis.st[];0;::];
ok["tabRow name";  (`$"row 0")~(last .vis.STACK)`name];
ok["tabRow lines"; ("a: 3";"b: `x")~(last .vis.STACK)[`state;`lines]];
.vis.STACK:();
ok["tabView c0"; 0=(.vis.tabView[([] a:1 2);`t])[`state;`c0]];

/ function source extraction
ok["srcLines"; "{x+1}"~first .vis.srcLines `.smoketest.f];

/ syntax colorizer: operators break number runs; escaped quotes stay strings
ok["color plus"; (.qvis.green;.qvis.cyan;.qvis.green)~.vis.charColors "1+2"];
ok["color exp";  all .qvis.green=.vis.charColors "1e+5"];
ok["color esc";  all .qvis.magenta=.vis.charColors "\"a\\\"b\""];

/ min/max downsampling preserves spikes
spike:@[1000#0f;500;:;99f];
ok["dsamp spike"; 99f in .vis.dsamp[100;spike]];
ok["dsamp len";   200=count .vis.dsamp[100;spike]];
ok["dsamp short"; (til 5)~.vis.dsamp[10;til 5]];

/ repl editor ops (pure state-dict transforms, no window needed)
est:`lines`cy`cx`off`out`ooff`rc`fc`capture!(enlist "";0;0;0;();0;0;0;1b);
e1:.vis.edIns[est;"ab"];
ok["edIns text";   (enlist "ab")~e1`lines];
ok["edIns cursor"; 2=e1`cx];
e2:.vis.edIns[e1;enlist "\n"];
ok["edIns split";  ("ab";"")~e2`lines];
ok["edIns cy";     (1;0)~e2`cy`cx];
e3:.vis.edIns[e2;"x:1\ny:2"];
ok["edIns paste";  ("ab";"x:1";"y:2")~e3`lines];
ok["edIns tab";    (enlist "  ")~(.vis.edIns[est;enlist "\t"])`lines];
e4:.vis.edKey[e3;`backspace];                     / delete "2" at end
ok["edKey bsp";    ("ab";"x:1";"y:")~e4`lines];
e5:.vis.edKey[@[e3;`cx;:;0];`backspace];          / join line up
ok["edKey join";   ("ab";"x:1y:2")~e5`lines];
ok["edKey joincx"; 3=e5`cx];
e6:.vis.edKey/[e3;`up`up`up`down];                / clamp then move
ok["edKey arrows"; 1=e6`cy];
ok["edKey home";   0=(.vis.edKey[e3;`home])`cx];

/ repl line selection: sa anchors the range, shift+arrows extend (.vis.replSel)
e3s:e3,(enlist `sa)!enlist 1;                           / lines ("ab";"x:1";"y:2"), cy 2
ok["selTxt";      "x:1\ny:2"~.vis.selTxt e3s];
s1:.vis.selDel e3s;
ok["selDel";      (enlist "ab")~s1`lines];
ok["selDel cur";  (0;0;-1)~s1`cy`cx`sa];
ok["selDel all";  (enlist "")~(.vis.selDel @[e3s;`sa;:;0])`lines];
sev:`new`held`click`mx`my`wheel`text!(0#`;0#`;0b;0;0;0;"");
r:.vis.replSel[e3,(enlist `sa)!enlist -1;@[sev;`new`held;:;(enlist `up;enlist `left_shift)];0b];
ok["sel anchor";  2=(first r)`sa];                / anchored at the old cursor line
ok["sel move";    1=(first r)`cy];
ok["sel eats";    `up`down~last r];               / .vis.edit must not also move
r2:.vis.replSel[e3,(enlist `sa)!enlist -1;@[sev;`new;:;enlist `a];1b];
ok["sel all";     (0;2)~(first r2)`sa`cy];
r3:.vis.replSel[e3,(enlist `sa)!enlist -1;@[sev;`new;:;enlist `tab];0b];
ok["tab indent";  "y:2  "~(first r3)[`lines]2];   / inserted at the cursor (end of line)
r4:.vis.replSel[e3s;@[sev;`new;:;enlist `backspace];0b];
ok["sel bsp";     ((enlist "ab");`backspace`delete)~((first r4)`lines;last r4)];
r5:.vis.replSel[e3s;@[sev;`new;:;enlist `down];0b];
ok["sel drop";    -1=(first r5)`sa];              / plain movement clears it

/ repl statement grouping: indented/blank lines continue the previous stmt
ok["stmts flat";   ("a:1";"b:2")~.vis.replStmts ("a:1";"b:2")];
ok["stmts cont";   (enlist "f:{[x]\n  x+1}")~.vis.replStmts ("f:{[x]";"  x+1}")];
ok["stmts blank";  2=count .vis.replStmts ("a:1";"";"b:2")];
ok["stmts empty";  0=count .vis.replStmts enlist ""];

/ repl evaluation
ok["run value";    (enlist "42")~.vis.replRun enlist "6*7"];
ok["run seq";      (enlist "43")~.vis.replRun ("sm_x:42";"sm_x+1")];
ok["run fn";       (enlist "42")~.vis.replRun ("sm_f:{[x]";"  x+41}";"sm_f 1")];
ok["run err";      "'"=first first .vis.replRun enlist "1+`a"];
ok["run comment";  (enlist enlist "3")~.vis.replRun ("/ adds";"1+2")];
ok["run empty";    (enlist "(no code)")~.vis.replRun ()];

/ command bar: evaluation, system commands, big-result guard
ok["cmd value";  "42"~.vis.cmdRun "6*7"];
ok["cmd err";    "'type"~.vis.cmdRun "1+`a"];
ok["cmd null";   ""~.vis.cmdRun " ::  "];
ok["cmd sys";    ""~.vis.cmdRun "\\t 0"];         / system cmd routed through \
ok["cmd sys r";  "0i"~.vis.cmdRun "\\t"];
ok["cmd big";    ".."~-2#.vis.cmdRun "til 5000"];
ok["cmd big len"; (2+.vis.TXTC)>=count .vis.cmdRun "til 5000"];

/ command bar: single-line editing on the .vis.CMD/.vis.CX globals
.vis.CMD:"abc"; .vis.CX:3;
.vis.cmdKey `backspace;
ok["cmdKey bsp";  ("ab";2)~(.vis.CMD;.vis.CX)];
.vis.cmdKey `home; .vis.cmdKey `delete;
ok["cmdKey del";  (enlist "b";0)~(.vis.CMD;.vis.CX)];
.vis.cmdKey `end;
ok["cmdKey end";  1=.vis.CX];
.vis.CMD:""; .vis.CX:0;

/ command bar: full input path - typing then enter evaluates into .vis.RES
cev:`new`held`click`mx`my`wheel`text!(0#`;0#`;0b;0;0;0;"1+1");
cev:.vis.cmdIn cev;
ok["cmdIn type";  "1+1"~.vis.CMD];
cev[`new]:enlist `return; cev[`text]:"";
cev:.vis.cmdIn cev;
ok["cmdIn run";   (enlist "2")~.vis.RES];
ok["cmdIn clear"; ""~.vis.CMD];
ok["cmdIn eaten"; not `return in cev`new];

/ view refresh recipes rebuild from live session state
.vis.RUN:1b;                                / pretend the loop is on (no window needed)
.vis.STACK:enlist .vis.nsView `.smoketest;
ok["refresh has recipe"; `refresh in key (last .vis.STACK)`state];
delete a from `.smoketest;
.vis.cmdRefresh[];
ok["refresh drops deleted"; not `.smoketest.a in exec fq from (last .vis.STACK)[`state;`rows]];
.vis.RUN:0b; .vis.STACK:();
ok["tab refresh named"; 0h=type (.vis.tabView[`.smoketest.t;`t])[`state;`refresh]];
ok["tab refresh anon";  (::)~(.vis.tabView[([] a:1 2);`t])[`state;`refresh]];

/ view dicts must keep uniform top-level keys: q collapses a list of
/ conforming dicts into a table, so pushing a view with an extra key onto
/ .vis.STACK threw 'mismatch (.vis.tab trade then .vis.tab `trade)
.vis.STACK:enlist .vis.tabView[([] a:1 2);`t];
.vis.push .vis.tabView[`.smoketest.t;`t];
.vis.push .vis.nsView `.smoketest;
ok["stack mixed views"; 3=count .vis.STACK];
.vis.STACK:();

/ capture check must not index the state dict (missing-key lookup on a state
/ holding a partitioned table threw 'par); needs the repo's dummy db loaded
if[count pt:$[`pt in key `.Q;.Q.pt;0#`];
  .vis.STACK:enlist .vis.tabView[first pt;first pt];
  ok["cap parted"; not .vis.cap[]];
  .vis.STACK:()];

/ x-axis ticks: temporal types snap to round time steps, others fall back
ok["nicex time";   .vis.nicex["t";0f;3600000f;5]~900000f*til 5];
ok["nicex plain";  .vis.nicex[" ";0f;97f;5]~.vis.nice[0;97;5]];
ok["fmtx time";    "00:15:00"~.vis.fmtx["t";0f;3600000f;900000f]];
ok["fmtx date";    "2000.02.20"~.vis.fmtx["d";0f;100f;50f]];
ok["fmtx p intraday"; "00:30:00"~.vis.fmtx["p";0f;3.6e12;1.8e12]];
ok["fmtx p days";  "2000.01.03"~.vis.fmtx["p";0f;1e15;172800000000000f]];
ok["fmtx plain";   "1.5K"~.vis.fmtx[" ";0f;1e4;1500f]];

/ plot state extraction: numeric cols are series, temporal col sets x range
pst:.vis.plotState ([] time:09:30:00.000+1000*til 10; price:10f+til 10; s:10#`a);
ok["plotState ys"; (enlist "price")~pst`nms];
ok["plotState xt"; "t"=pst`xt];
ok["plotState xr"; (34200000f;34209000f)~pst`xlo`xhi];

/ candle OHLC bucketing preserves shape (first/max/min/last per bucket)
cb:.vis.obucket[2;1 2 3 4f;5 6 7 8f;0 1 2 3f;1.5 2.5 3.5 4.5f];
ok["obucket";      (1 3f;6 8f;0 2f;2.5 4.5f)~cb];
ok["obucket pass"; (1 2f;3 4f;0 1f;5 6f)~.vis.obucket[10;1 2f;3 4f;0 1f;5 6f]];

/ watch tail fetch honours .vis.WROWS and accepts name / lambda / value
ow:.vis.WROWS; .vis.WROWS:5;
ok["wfetch tail";  (95+til 5)~(.vis.wfetch ([] a:til 100))`a];
ok["wfetch name";  .smoketest.t~.vis.wfetch `.smoketest.t];
ok["wfetch fn";    ([] a:1 2)~.vis.wfetch {([] a:1 2)}];
.vis.WROWS:ow;

/ watch view kinds: candle state extraction and the tail-pinned table state
cs:.vis.candleState ([] open:1 2f; high:3 4f; low:0 1f; close:2 3f);
ok["candleState";     (1 2f;3 4f;0 1f;2 3f)~cs`o`h`l`c];
ok["candleState ord"; " "=cs`xt];
ok["candleState time"; "t"=(.vis.candleState ([] time:09:00:00.000 09:00:01.000;
  open:1 2f; high:3 4f; low:0 1f; close:2 3f))`xt];
tls:.vis.tailState ([] a:til 100);
ok["tailState off";   (100-.vis.TROWS)=tls`off];
ok["tailState n";     100=tls`n];
ok["wkind";           `plot`candle`tab~key .vis.WKIND];

/ /filter: where-clause pushes a filtered table view, bad clauses report
fv:.vis.tabView[([] a:1 2 3; s:`x`y`x);`t];
.vis.STACK:enlist fv;
ok["filter res";   "2 rows"~.vis.tabFilter[fv`state;"a>1"]];
ok["filter push";  2=count .vis.STACK];
ok["filter rows";  2 3~(last .vis.STACK)[`state;`t]`a];
ok["filter err";   "'"=first .vis.tabFilter[fv`state;"a>)("]];
.vis.STACK:enlist fv;
.vis.cellFilter[fv`state;`s;`x;::];
ok["cellFilter";   1 3~(last .vis.STACK)[`state;`t]`a];
.vis.STACK:enlist .vis.nsView `.smoketest;
.vis.filter "f";
ok["filter ns";    (enlist `.smoketest.f)~exec fq from (last .vis.STACK)[`state;`rows]];
.vis.STACK:();

/ sort cap: over .vis.MAXSORT rows the header click refuses instead of OOM
.vis.STACK:enlist .vis.tabView[([] a:3 1 2);`t];
om:.vis.MAXSORT; .vis.MAXSORT:2;
.vis.tabSort[`a;::];
ok["sort guard";     0=count .vis.st[]`idx];
ok["sort guard msg"; "'"=first .vis.RES];
.vis.MAXSORT:om; .vis.STACK:(); .vis.RES:"";

/ cmdRefresh carries sort (recomputed on fresh data) and column page
.vis.RUN:1b;
.vis.STACK:enlist .vis.tabView[`.smoketest.t;`t];
.vis.tabSort[`x;::]; .vis.tabSort[`x;::];         / second click: descending
.vis.cmdRefresh[];
ok["refresh keeps sort"; (`x;0b)~.vis.st[]`srt];
ok["refresh keeps idx";  1 0~.vis.st[]`idx];
.vis.RUN:0b; .vis.STACK:();

/ hotspots are per-button; right-click spots feed the context menu
.vis.HOT:0#.vis.HOT;
.vis.spot[0;0;10;10;{[e] .smoketest.hit::`left}];
.vis.spotR[0;0;10;10;{[e] .smoketest.hit::`right}];
.vis.hit[5;5;0b]; ok["hit left";  `left~.smoketest.hit];
.vis.hit[5;5;1b]; ok["hit right"; `right~.smoketest.hit];
.vis.HOT:0#.vis.HOT;

/ context menu construction: numeric cells offer plot, others don't
.vis.STACK:enlist .vis.tabView[([] a:1 2; s:`x`y);`t];
.vis.cellMenu[.vis.st[];`a;1;::];
ok["cellMenu num"; 4=count .vis.MENU`items];
.vis.cellMenu[.vis.st[];`s;0;::];
ok["cellMenu sym"; 3=count .vis.MENU`items];
.vis.MENU:(); .vis.STACK:();

-1 "all smoke tests passed";
exit 0
