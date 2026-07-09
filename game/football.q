/ football.q - TOUCHDOWN RUN: 3D arcade football on the qVis engine.
/ You auto-run downfield; dodge the defenders and reach the endzone.
/ Get tackled and ragdoll physics fling you into space.
//
/ Run from repo root (or export QVIS=/path/to/qVis):
/   q game/football.q
/ Headless self-check (no window):
/   q game/football.q -smoke -q
//
/ Keys (click window to focus): a/d or left/right dodge, r restart, esc quit.

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

/ --------------------------------------------------------------------------
/ Constants
/ --------------------------------------------------------------------------
W:480; H:300; SCALE:3; HW:W%2; HH:H%2;
F:HW%tan 0.5236;                       / ~60 degree FOV
PITCH:0.22; SP:sin PITCH; CP:cos PITCH;
HZ:`long$HH-F*SP%CP;                   / horizon row of the ground plane
DT:0.033; PI:acos -1;
FW:15f;                                / half field width
GOAL:100f; EZ:110f;                    / goal line / back of endzone

GRASS:3050286i; DCOL:14692400i; PCOL:.qvis.white; EZB:2245802i;
STARS:(60?W;60?HZ);

/ Stick figure: foot L/R, hip, shoulder, head, hand L/R
BONES:(0 2;1 2;2 3;3 4;3 5;3 6);
RBONES:BONES,(0 1;5 6;2 4);            / extra braces so the ragdoll keeps shape

/ --------------------------------------------------------------------------
/ Camera + projection (camera looks straight down +y, pitched down)
/ --------------------------------------------------------------------------
dep:{[p]((p[1]-CY)*CP)-(p[2]-CZ)*SP}
proj:{[xs;ys;zs]d:((ys-CY)*CP)-(zs-CZ)*SP;(HW+F*(xs-CX)%d;HH-F*(((ys-CY)*SP)+(zs-CZ)*CP)%d;d)}
proj1:{[p]p2:proj . 3 1#p; p2[;0]}

/ line3[a;b;col] - 3D line with near-plane clipping (depth is linear in the
/ world segment, so lerp the behind-camera endpoint onto depth 0.3)
line3:{[a;b;col]
  da:dep a; db:dep b;
  if[(da<0.3)and db<0.3; :()];
  if[da<0.3; a:b+(a-b)*(db-0.3)%db-da];
  if[db<0.3; b:a+(b-a)*(da-0.3)%da-db];
  pa:proj1 a; pb:proj1 b;
  .qvis.line[pa 0;pa 1;pb 0;pb 1;col]; }

/ --------------------------------------------------------------------------
/ Figures
/ --------------------------------------------------------------------------
/ joints[x;y;ph] - 7x3 joint positions for a runner at (x;y), leg phase ph
joints:{[x;y;ph]
  sl:sin ph; sr:sin ph+PI;
  ((x-0.18; y+0.35*sl; 0.15*0|sl);
   (x+0.18; y+0.35*sr; 0.15*0|sr);
   (x; y; 0.95);
   (x; y+0.08; 1.55);
   (x; y+0.12; 1.78);
   (x-0.35; y+0.3*sr; 1.1);
   (x+0.35; y+0.3*sl; 1.1))}

drawFig:{[J;col]
  pr:proj . flip J;
  if[any 0.25>=pr 2; :()];
  sx:pr 0; sy:pr 1;
  {[sx;sy;col;b].qvis.line[sx b 0;sy b 0;sx b 1;sy b 1;col]}[sx;sy;col] each BONES;
  .qvis.circle[sx 4;sy 4;1|`long$50%pr[2;4];col]; }

/ --------------------------------------------------------------------------
/ Ragdoll - Verlet particles on the figure's joints, stick constraints
/ --------------------------------------------------------------------------
mkRag:{
  J:joints[PX;PY;PH];
  RESTS::{[J;b]d:J[b 0]-J b 1; sqrt sum d*d}[J] each RBONES;
  v:((7;3)#neg[3f]+21?6f)+\:(VX;3f;26f);   / launch up + per-particle spin
  RAG::`p`o!(J;J-DT*v); }

solveC:{[P;b;r]
  a:P b 0; c:P b 1; d:c-a; l:sqrt sum d*d;
  if[l>1e-9; k:0.5*(l-r)%l; P[b 0]:a+k*d; P[b 1]:c-k*d];
  P}

ragStep:{
  P:RAG`p;
  N:(P+0.995*P-RAG`o)+\:DT*DT*0 0 -2f;     /weak gravity = space fling
  N:4 {solveC/[x;RBONES;RESTS]}/ N;
  RAG::`p`o!(N;P); }

/ --------------------------------------------------------------------------
/ Game state
/ --------------------------------------------------------------------------
reset:{
  PX::0f; PY::0f; PH::0f; VX::0f; ST::`run;
  CX::0f; CY::-9f; CZ::3.2;
  DEF::([]x:neg[12f]+24*8?1f; y:(25f+9*til 8)+8?4f; ph:8?2*PI); }

tackled:{0.81>min ((PX-DEF`x)*PX-DEF`x)+(PY-DEF`y)*PY-DEF`y}

stepDef:{
  dx:PX-DEF`x; dy:(PY+2f)-DEF`y;
  d:1e-6|sqrt (dx*dx)+dy*dy;
  update x:x+DT*5.8*dx%d, y:y+DT*5.8*dy%d, ph:ph+DT*18 from `DEF; }

stepRun:{[ks]
  tgt:9f*(any `d`right in ks)-any `a`left in ks;
  VX::(0.75*VX)+0.25*tgt;
  PX::(0.5-FW)|(FW-0.5)&PX+DT*VX;
  PY+::DT*6.5; PH+::DT*20;
  stepDef[];
  if[PY>=GOAL; ST::`td];
  if[tackled[]; ST::`dead; mkRag[]]; }

/ --------------------------------------------------------------------------
/ Rendering
/ --------------------------------------------------------------------------
setCam:{
  $[ST=`dead;
    [c:avg RAG`p;
     CX::CX+0.1*(c 0)-CX;
     CY::CY+0.08*((c 1)-16)-CY;
     CZ::CZ+0.08*(c 2)-CZ];
    [CX::CX+0.25*PX-CX; CY::PY-9f; CZ::3.2]]; }

skyC:{[k]((`int$k*135)*65536i)+((`int$k*206)*256i)+`int$k*235}
ctext:{[y;s;c;str].qvis.text[HW-.qvis.textWidth[s;str]%2;y;s;c;str]}

drawField:{
  {line3[(neg FW;x;0f);(FW;x;0f);EZB]} each GOAL+0.5+til 10;
  {line3[(neg FW;x;0f);(FW;x;0f);$[x=GOAL;.qvis.yellow;.qvis.white]]} each `float$10*til 11;
  line3[(neg FW;0f;0f);(neg FW;EZ;0f);.qvis.white];
  line3[(FW;0f;0f);(FW;EZ;0f);.qvis.white];
  line3[(neg FW;EZ;0f);(FW;EZ;0f);.qvis.white]; }

drawP:{$[ST=`dead; drawFig[RAG`p;PCOL]; drawFig[joints[PX;PY;PH];PCOL]]}

draw:{
  setCam[];
  k:$[ST=`dead; 0f|1-(avg RAG[`p][;2])%80; 1f];   / sky fades to space
  .qvis.rect[0;0;W;HZ;skyC k];
  if[k<0.6; .qvis.pixel[;;.qvis.white]'[STARS 0;STARS 1]];
  .qvis.rect[0;HZ;W;H-HZ;GRASS];
  drawField[];
  DRWN::0b;                                        / painter: far to near
  {[i]r:DEF i;
    if[(not DRWN)and PY>r`y; drawP[]; DRWN::1b];
    drawFig[joints[r`x;r`y;r`ph];DCOL]} each idesc DEF`y;
  if[not DRWN; drawP[]];
  .qvis.text[8;8;1;.qvis.white;"YARDS TO GO: ",string 0|`long$GOAL-PY];
  if[ST=`dead; ctext[40;2;.qvis.red;"TACKLED INTO SPACE!"]; ctext[62;1;.qvis.white;"PRESS R TO RUN IT BACK"]];
  if[ST=`td; ctext[40;3;.qvis.yellow;"TOUCHDOWN!"]; ctext[74;1;.qvis.white;"PRESS R TO PLAY AGAIN"]];
  .qvis.present[]; }

/ --------------------------------------------------------------------------
/ Main loop
/ --------------------------------------------------------------------------
tick:{
  pl:.qvis.poll[];
  if[(pl`closed)or`escape in pl`held; system"t 0"; .qvis.shutdown[]; :()];
  if[`r in pl`new; reset[]];
  $[ST=`run; stepRun pl`held; ST=`dead; ragStep[]; ::];
  draw[]; }

/ --------------------------------------------------------------------------
/ Headless self-check: q game/football.q -smoke -q
/ --------------------------------------------------------------------------
runTests:{
  chk:{if[not x;'y]};
  CX::0f; CY::0f; CZ::2f;
  p:proj[0f;20f;2f];
  chk[HW=p 0; "proj: dead-ahead point must be screen-centred"];
  chk[19>abs 20-dep(0f;20f;2f); "dep: depth roughly forward distance"];
  PX::0f; PY::30f; PH::1f; VX::0f;
  mkRag[];
  do[20; ragStep[]];
  lens:{[J;b]d:J[b 0]-J b 1; sqrt sum d*d}[RAG`p] each RBONES;
  chk[all 0.2>abs lens-RESTS; "ragdoll: bone lengths must survive 20 steps"];
  chk[10<RAG[`p][4;2]-1.78; "ragdoll: head must be flung well upward"];   / ~26u/s * 0.66s
  DEF::([]x:enlist 0f; y:enlist 30f; ph:enlist 0f);
  chk[tackled[]; "tackle: contact detected"];
  DEF::update y:50f from DEF;
  chk[not tackled[]; "tackle: no false positive at range"];
  -1 "smoke ok";
  exit 0}

$[any .z.x like "*smoke*";
  runTests[];
  [.qvis.init[W;H;SCALE]; reset[]; .z.ts:{tick[]}; system "t 33"; draw[]]]
