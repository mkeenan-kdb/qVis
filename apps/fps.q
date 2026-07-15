/ fps.q - DEMON ARENA: first-person shooter on the qVis engine.
/ Heightmap raycaster: textured floor + roof (per-pixel floor-casting via
/ setpixels), variable-height cells rendered voxel-style so the map has
/ real climbable stairs and a raised platform, pixel-art demon sprites.
//
/ Run from repo root (or export QVIS=/path/to/qVis):
/   q apps/fps.q
/ Headless self-check (no window):
/   q apps/fps.q -smoke -q
//
/ Keys (click window to focus):
/   w/s/up/down walk   a/d strafe   q/e/left/right turn
/   space or click fire   r restart   esc quit

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

/ --------------------------------------------------------------------------
/ Constants
/ --------------------------------------------------------------------------
W:320; H:200; SCALE:4; HW:W div 2; HH:H div 2;
DT:0.045; PI:acos -1;
MSPD:0.2; TSPD:0.13;                   / player move / turn per frame
ESPD:1.0;                              / demon speed, cells/sec
K:1.1*H;                               / projection: screen y = HH+(K%t)*(EZ-z)

/ Rays: one per column across a ~60 degree FOV (same core as exampleDoom.q)
FOC:(W%2)%tan 0.5236;
ANGOFF:atan ((`float$til W)-W%2)%FOC;
STEP:0.04; NSTEP:400;
DSTEPS:STEP*1f+til NSTEP;
TM:cos[ANGOFF]*\:DSTEPS;               / perpendicular distance per (col;step)
KTM:K%TM;

/ Map cells are heights: . floor, 1-4 stairs (0.15 each), # full wall (2.0).
/ Centre platform (0.6) reached by the stair run on row 7.
MAP:(
  "################";
  "#......##......#";
  "#..##......##..#";
  "#..##..##..##..#";
  "#..............#";
  "#.....4444.....#";
  "#.....4444.....#";
  "#.12344444.....#";
  "#.....4444.....#";
  "#.....4444.....#";
  "#..............#";
  "#......##......#";
  "#..##......##..#";
  "#..##..##..##..#";
  "#......##......#";
  "################")
MAPW:count first MAP;
HFLAT:raze ("#1234."!2 0.15 0.3 0.45 0.6 0f) each MAP;
hAt:{[x;y]HFLAT (MAPW*15&0|floor y)+15&0|floor x}

KM:`w`a`s`d`q`e`up`down`left`right!"wasdqewsqe"

/ --------------------------------------------------------------------------
/ Demon sprite - 12x14 pixel art, drawn as scaled rects per opaque pixel
/ --------------------------------------------------------------------------
SPR:(
  "..w......w..";
  ".ww......ww.";
  ".rrrrrrrrrr.";
  ".ryyrrrryyr.";
  ".rrrrrrrrrr.";
  "..rwwrwwr...";
  "...rrrrrr...";
  "drrrrrrrrrrd";
  "dr..rrrr..rd";
  "d...rrrr...d";
  "....rrrr....";
  "....r..r....";
  "...rr..rr...";
  "...dd..dd...")
ach:raze SPR; mm:where ach<>".";
SPRC:(raze (count SPR)#enlist til 12) mm;
SPRR:(raze 12#'til count SPR) mm;
SPRCH:ach mm;
PAL:"rdyw"!((190 40 35f);(110 20 20f);(255 220 40f);(235 230 220f));

/ --------------------------------------------------------------------------
/ Raycast - one march serves wall depths, platform depths and the heightmap
/ --------------------------------------------------------------------------
castAll:{
  ra:PA+ANGOFF;
  idx:(MAPW*15&0|floor PY+sin[ra]*\:DSTEPS)+15&0|floor PX+cos[ra]*\:DSTEPS;
  HM::HFLAT idx;                                 / height per (col;step)
  WD::(STEP*1f+sum each mins each HM<1.5)*cos ANGOFF;   / full walls
  SD::(STEP*1f+sum each mins each HM<0.55)*cos ANGOFF; } / platform-or-wall

/ --------------------------------------------------------------------------
/ Game state
/ --------------------------------------------------------------------------
reset:{
  PX::2.5; PY::2.5; PA::0.785; EZ::0.5; T::0f;
  HP::100f; GCOOL::0f; MUZZ::0f; FLASH::0f; HIT::0f; ATK::0f; ST::`play;
  ENE::([]x:13.5 2.5 13.5 2.5 12.5 8.5; y:2.5 13.5 13.5 8.5 7.5 12.5;
        hp:6#3; fl:6#0f);
  castAll[]; }

/ Movement with axis-split collision; a cell is enterable when the height
/ rise is one stair step or less, so stairs work and falls are always allowed
mv:{[ch]
  nx:PX; ny:PY;
  $[ch="w"; [nx+:MSPD*cos PA; ny+:MSPD*sin PA];
    ch="s"; [nx-:MSPD*cos PA; ny-:MSPD*sin PA];
    ch="a"; [nx+:MSPD*sin PA; ny-:MSPD*cos PA];
    ch="d"; [nx-:MSPD*sin PA; ny+:MSPD*cos PA];
    ch="q"; PA-:TSPD;
    ch="e"; PA+:TSPD;
    ::];
  cur:hAt[PX;PY];
  if[0.21>hAt[nx;PY]-cur; PX::nx];
  if[0.21>hAt[PX;ny]-cur; PY::ny]; }

/ Hitscan down the view axis: nearest live demon within a 0.3-wide corridor,
/ not behind a wall, and not a floor demon hidden behind the platform
doShoot:{[pl]
  if[GCOOL>0; :()];
  if[not (pl`click) or `space in pl`held; :()];
  GCOOL::0.35; MUZZ::0.12;
  ca:cos PA; sa:sin PA;
  dx:ENE[`x]-PX; dy:ENE[`y]-PY;
  fx:(dx*ca)+dy*sa; sx:(dy*ca)-dx*sa;
  ehv:hAt'[ENE`x;ENE`y];
  ok:(ENE[`hp]>0) and (fx>0.2) and (abs[sx]<0.3) and (fx<WD HW) and (fx<0.3+SD HW) or ehv>=0.5;
  w:where ok;
  if[0=count w; :()];
  i:w first iasc fx w;
  .[`ENE;(i;`hp);-;1];
  .[`ENE;(i;`fl);:;0.15];
  HIT::0.15; }

/ Demons chase with the same climb rule as the player - they take the stairs
stepEne:{
  update fl:0f|fl-DT from `ENE;
  {[i]
    e:ENE i;
    dx:PX-e`x; dy:PY-e`y; d:sqrt (dx*dx)+dy*dy;
    $[d<1.1;
      [ATK::ATK-DT; if[ATK<0; HP::HP-9; FLASH::0.3; ATK::0.8]];
      [nx:e[`x]+DT*ESPD*dx%d; ny:e[`y]+DT*ESPD*dy%d;
       cur:hAt[e`x;e`y];
       if[0.21>hAt[nx;e`y]-cur; .[`ENE;(i;`x);:;nx]];
       if[0.21>hAt[ENE[i;`x];ny]-cur; .[`ENE;(i;`y);:;ny]]]];
    } each exec i from ENE where hp>0;
  if[HP<=0; HP::0f; ST::`dead];
  if[not any ENE[`hp]>0; ST::`win]; }

/ --------------------------------------------------------------------------
/ Rendering
/ --------------------------------------------------------------------------
/ Background: per-pixel floor-cast checkerboard floor + hell-tile roof,
/ blasted as one full frame via setpixels (walls draw over it)
bgBuf:{
  dirx:cos[PA+ANGOFF]%cos ANGOFF; diry:sin[PA+ANGOFF]%cos ANGOFF;
  tf:(K*EZ)%0.5+til HH;                          / floor distance per row
  fx:PX+tf*\:dirx; fy:PY+tf*\:diry;
  cf:(floor[fx]+floor fy) mod 2;
  brf:1f%1f+0.12*tf;
  fA:((`int$brf*100)*65536i)+((`int$brf*95)*256i)+`int$brf*88;
  fB:((`int$brf*65)*65536i)+((`int$brf*62)*256i)+`int$brf*58;
  tr:(K*2f-EZ)%(HH-0.5)-til HH;                  / roof (z=2) distance per row
  rx:PX+tr*\:dirx; ry:PY+tr*\:diry;
  cr:(floor[2*rx]+floor 2*ry) mod 2;
  brr:1f%1f+0.12*tr;
  rA:((`int$brr*80)*65536i)+((`int$brr*34)*256i)+`int$brr*30;
  rB:((`int$brr*52)*65536i)+((`int$brr*22)*256i)+`int$brr*20;
  `int$raze (rB+cr*rA-rB),fB+cf*fA-fB }

/ Voxel-style column renderer: march near-to-far keeping a per-column screen
/ cursor; every sample whose top beats the cursor paints a segment. Handles
/ full walls, stair fronts and stair tops in one pass.
segCalc:{
  ym:H&0|`long$HH+KTM*EZ-HM;
  pm:mins each ym;
  priorm:H,'-1_'pm;
  vis:(HM>0.01)&ym<priorm;
  wv:where each vis;
  cxs:raze {count[y]#x}'[til W;wv];
  tops:raze ym@'wv;
  hts:raze (priorm@'wv)-ym@'wv;
  tv:raze TM@'wv; hv:raze HM@'wv;
  br:1f%1f+0.16*tv;
  wood:hv<0.9;                                   / stairs wood, walls stone
  r:`int$br*?[wood;185f;150f];
  g:`int$br*?[wood;120f;125f];
  b:`int$br*?[wood;72f;108f];
  (cxs;tops;hts;(r*65536i)+(g*256i)+b)}

drawWalls:{s:segCalc[]; {[x;y;h;c].qvis.rect[x;y;1;h;c]}'[s 0;s 1;s 2;s 3];}

drawEne:{[i]
  e:ENE i;
  ca:cos PA; sa:sin PA;
  dx:e[`x]-PX; dy:e[`y]-PY;
  fx:(dx*ca)+dy*sa;
  if[fx<0.35; :()];
  sx:(dy*ca)-dx*sa;
  c:HW+FOC*sx%fx;
  if[(c<neg 30) or c>W+30; :()];
  ci:0|(W-1)&`long$c;
  if[fx>0.3+WD ci; :()];
  eh:hAt[e`x;e`y];
  if[(fx>0.3+SD ci) and eh<0.5; :()];            / floor demon behind platform
  wh:(4*H)&K%fx;
  bot:HH+wh*EZ-eh;
  if[e[`hp]<=0;                                  / corpse splat
    .qvis.circle[c;bot-0.02*wh;1|`long$0.14*wh;5246992i]; :()];
  ph:0.9*wh; s:ph%14;
  y0:(bot-ph)+0.02*ph*sin (8*T)+i;               / idle bob, offset per demon
  x0:c-6*s;
  br:1f%1f+0.15*fx;
  cd:$[e[`fl]>0; "rdyw"!4#.qvis.white;
    "rdyw"!{[br;ch]v:PAL ch; sh:$[ch="y";1f;br]; / eyes glow, no shading
      ((`int$sh*v 0)*65536i)+((`int$sh*v 1)*256i)+`int$sh*v 2}[br] each "rdyw"];
  sz:1|ceiling s;
  {[x;y;z;c2].qvis.rect[x;y;z;z;c2]}'[x0+s*SPRC;y0+s*SPRR;count[SPRC]#sz;cd SPRCH]; }

ctext:{[y;s;c;str].qvis.text[HW-.qvis.textWidth[s;str]%2;y;s;c;str]}

drawHud:{
  .qvis.line[HW-4;HH;HW+4;HH;.qvis.white];
  .qvis.line[HW;HH-4;HW;HH+4;.qvis.white];
  if[HIT>0;                                      / hitmarker: X around crosshair
    .qvis.line[HW-8;HH-8;HW-3;HH-3;.qvis.red];
    .qvis.line[HW+3;HH+3;HW+8;HH+8;.qvis.red];
    .qvis.line[HW+3;HH-3;HW+8;HH-8;.qvis.red];
    .qvis.line[HW-8;HH+8;HW-3;HH+3;.qvis.red]];
  .qvis.rect[HW-6;H-28;12;28;4210752i];          / gun barrel
  .qvis.rect[HW-14;H-12;28;12;5395026i];         / gun body
  if[MUZZ>0; .qvis.circle[HW;H-32;6;.qvis.yellow]];
  if[FLASH>0;                                    / damage: red screen border
    .qvis.rect[0;0;W;4;.qvis.red]; .qvis.rect[0;H-4;W;4;.qvis.red];
    .qvis.rect[0;0;4;H;.qvis.red]; .qvis.rect[W-4;0;4;H;.qvis.red]];
  .qvis.rect[8;H-14;104;8;2105376i];
  .qvis.rect[10;H-12;`long$HP;4;$[HP>30;.qvis.green;.qvis.red]];
  .qvis.text[8;6;1;.qvis.white;"DEMONS LEFT: ",string sum ENE[`hp]>0];
  if[ST=`dead; ctext[70;2;.qvis.red;"YOU DIED"]; ctext[92;1;.qvis.white;"PRESS R TO RESPAWN"]];
  if[ST=`win; ctext[70;2;.qvis.yellow;"AREA CLEARED!"]; ctext[92;1;.qvis.white;"PRESS R TO PLAY AGAIN"]]; }

draw:{
  .qvis.setpixels bgBuf[];
  drawWalls[];
  d2:((ENE[`x]-PX)*ENE[`x]-PX)+(ENE[`y]-PY)*ENE[`y]-PY;
  drawEne each idesc d2;                         / painter: far to near
  drawHud[];
  .qvis.present[]; }

/ --------------------------------------------------------------------------
/ Main loop
/ --------------------------------------------------------------------------
tick:{
  pl:.qvis.poll[];
  if[(pl`closed) or `escape in pl`held; system"t 0"; .qvis.shutdown[]; :()];
  if[`r in pl`new; reset[]];
  GCOOL::GCOOL-DT; MUZZ::0f|MUZZ-DT; FLASH::0f|FLASH-DT; HIT::0f|HIT-DT;
  T::T+DT;
  if[ST=`play;
    castAll[];
    mv each KM (pl`held) inter key KM;
    EZ::EZ+0.25*(0.5+hAt[PX;PY])-EZ;             / eye height eases up stairs
    doShoot pl;
    stepEne[]];
  draw[]; }

/ --------------------------------------------------------------------------
/ Headless self-check: q apps/fps.q -smoke -q
/ --------------------------------------------------------------------------
runTests:{
  chk:{if[not x;'y]};
  dm:{[t]min sqrt ((t[`x]-PX)*t[`x]-PX)+(t[`y]-PY)*t[`y]-PY};
  reset[];
  chk[W=count WD; "cast: one distance per column"];
  chk[all WD>0; "cast: distances positive"];
  chk[all WD<1+STEP*NSTEP; "cast: every ray hits a wall"];
  chk[(W;NSTEP)~count each (HM;first HM); "cast: heightmap is col x step"];
  chk[(W*H)=count bgBuf[]; "bg: one pixel per screen cell"];
  s:segCalc[];
  chk[1=count distinct count each s; "segs: aligned vectors"];
  chk[all s[2]>0; "segs: positive heights"];
  chk[all (s[1]>=0) and s[1]<=H; "segs: tops on screen"];
  PA::0f; WD::W#10f; SD::W#10f; GCOOL::0f;
  ENE::([]x:enlist PX+3; y:enlist PY; hp:enlist 3; fl:enlist 0f);
  doShoot `click`held!(1b;0#`);
  chk[2=first ENE`hp; "shoot: direct hit lands"];
  chk[HIT>0; "shoot: hitmarker triggers on hit"];
  GCOOL::0f; HIT::0f; ENE::update y:PY+2 from ENE;
  doShoot `click`held!(1b;0#`);
  chk[2=first ENE`hp; "shoot: off-axis shot misses"];
  GCOOL::0f; ENE::update y:PY from ENE; WD::W#1f;
  doShoot `click`held!(1b;0#`);
  chk[2=first ENE`hp; "shoot: wall blocks the bullet"];
  PX::1.5; PY::7.5; PA::0f;                      / stair run heads east
  do[25; mv"w"];
  chk[PX>6f; "stairs: player climbs the stair run"];
  chk[0.55<hAt[PX;PY]; "stairs: player ends on the platform"];
  PX::6.5; PY::4.5; PA::PI%2;                    / platform ledge from the north
  do[10; mv"w"];
  chk[PY<5f; "stairs: cannot climb the 0.6 ledge directly"];
  reset[];
  d0:dm ENE;
  do[60; stepEne[]];
  chk[all 0.9>hAt'[ENE`x;ENE`y]; "ai: demons stay out of walls"];
  chk[d0>dm ENE; "ai: demons close in"];
  ENE::([]x:enlist PX+0.5; y:enlist PY; hp:enlist 3; fl:enlist 0f);
  ATK::0f; h0:HP;
  stepEne[];
  chk[HP<h0; "ai: adjacent demon bites"];
  PX::1.3; PY::2.5; PA::PI;
  do[30; mv"w"];
  chk[PX>=1f; "move: border wall collision holds"];
  t:system"t:10 (castAll[];bgBuf[];segCalc[])";
  -1 "render calc: ",string[0.1*t]," ms/frame (budget 45)";
  -1 "smoke ok";
  exit 0}

$[any .z.x like "*smoke*";
  runTests[];
  [.qvis.init[W;H;SCALE]; reset[]; .z.ts:{tick[]}; system "t 45"; draw[]]]
