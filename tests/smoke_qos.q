/ smoke.q - headless assertions on qOS window-manager logic.
/ Run from the repo root:  q tests/smoke.q -q
/ Loads qOS.q (and qVis/inspect.q underneath, binding qSDL.so) but never
/ opens a window - only list/geometry/eval logic is exercised.

system"l qOS.q"

ok:{[nm;c] $[c; -1"PASS ",nm; [-2"FAIL ",nm; exit 1]];}

/ .vis.open now spawns a qOS window instead of starting the inspector loop
.vis.open .vis.txtView[`t1;enlist "hello";::];
ok["open spawns a window"; 1=count .qos.WINS];
id1:.qos.WINS[0;`id];
ok["new window is focused"; id1~.qos.FOC];

/ drill-down pushes onto the owning window's own view stack
.qos.inWin[id1;{[e] .vis.push .vis.txtView[`t2;enlist "x";::]}];
ok["push stacks in-window"; 2=count .qos.WINS[0;`stack]];
ok["top view is the pushed one"; `t2~(last .qos.WINS[0;`stack])`name];

/ esc pops the stack, then closes the window at its root view
.qos.escWin id1; .qos.purge[];
ok["esc pops"; 1=count .qos.WINS[0;`stack]];
.qos.escWin id1; .qos.purge[];
ok["esc closes at root"; 0=count .qos.WINS];
ok["focus cleared"; null .qos.FOC];

/ z-order: topAt picks the topmost window under a point
a:.qos.spawnAt[.vis.txtView[`a;();::];10 10 300 200];
b:.qos.spawnAt[.vis.txtView[`b;();::];50 50 300 200];
ok["topAt overlap -> top window"; 1=.qos.topAt[60;60]];
ok["topAt uncovered area"; 0=.qos.topAt[15;15]];
ok["topAt miss"; null .qos.topAt[2000;2000]];
.qos.focus a;
ok["focus raises"; a~.qos.WINS[1;`id]];
ok["raised window wins topAt"; a~.qos.WINS[.qos.topAt[60;60];`id]];

/ minimised windows are skipped by hit-testing and focus falls back
.qos.minimise a; .qos.purge[];
ok["minimised skips topAt"; b~.qos.WINS[.qos.topAt[60;60];`id]];
ok["focus falls back"; b~.qos.FOC];
ok["focus restores minimised"; [.qos.focus a; not .qos.WINS[.qos.wix a;`min]]];

/ maximise round-trips geometry
g:.qos.WINS[.qos.wix b;`x`y`w`h];
.qos.maximise b; .qos.maximise b;
ok["maximise restores geometry"; g~.qos.WINS[.qos.wix b;`x`y`w`h]];

/ content box: text views get a slim margin, charts the y-label gutter
.qos.WINS:(); .qos.DEAD:0#0; .qos.FOC:0N;
.qos.spawnAt[.vis.txtView[`t;();::];(10;10;300;200)];
ok["cbox text view"; (18;28;286;156)~.qos.cbox .qos.WINS 0];
.qos.WINS:();
.qos.spawnAt[`name`draw`state!(`plot;::;()!());(10;10;300;200)];
ok["cbox chart view"; (64;28;240;156)~.qos.cbox .qos.WINS 0];

/ console eval
.qos.WINS:(); .qos.FOC:0N;
ok["conRun value"; (enlist enlist "2")~.qos.conRun "1+1"];
ok["conRun error"; "'"=first first .qos.conRun "xyzzy+1"];
ok["conRun empty"; ()~.qos.conRun "  "];
tdemo:([]a:1 2;b:`x`y);
.qos.conRun "tdemo";
ok["table result opens a browser window"; 1=count .qos.WINS];
ok["browser hosts a table view"; `t in key (last .qos.WINS[0;`stack])`state];

/ animation cadence: slowest \t that keeps visible views animated
.qos.WINS:(); .qos.DEAD:0#0; .qos.FOC:0N;
ok["cadence idle desktop = clock"; 1000=.qos.cadence[]];
cid:.qos.spawnAt[.qos.conView[];(0;0;300;200)];
ok["cadence console = blink"; 300=.qos.cadence[]];
.qos.minimise cid; .qos.purge[];
ok["cadence skips minimised"; 1000=.qos.cadence[]];
.qos.WINS:();
.qos.spawnAt[`name`draw`state!(`$"watch-plot";::;enlist[`ms]!enlist 200);(0;0;300;200)];
ok["cadence watch = half refresh"; 100=.qos.cadence[]];
.qos.spawnAt[`name`draw`state!(`mem;::;()!());(0;0;300;200)];
ok["cadence takes the minimum"; 100=.qos.cadence[]];
.qos.WINS:(); .qos.FOC:0N;

-1"smoke: all passed";
exit 0
