
/ examplePhysarum.q - Physarum (slime mold) transport-network simulation,
/ fully vectorised. Tens of thousands of agents each sense the trail field
/ at three points ahead (left/front/right), steer toward the strongest
/ reading, step forward, and deposit trail where they land; the field then
/ diffuses (cross-shaped box blur out of four flat `rotate`s, as in
/ exampleSand.q) and decays. Emergent result: the agents carve glowing,
/ ever-reorganising vein networks like the real organism.
/ Everything is flat-vector work: sensing is three gathers of the W*H trail
/ field at toroidally-wrapped pixel indices, steering is a boolean vote,
/ deposition is one @[;;+;] scatter-add - no per-agent loops anywhere.
/ Left-click (hold) pours attractant the swarm converges on. Press p for
/ the parameter panel - sensor geometry and decay reshape the network
/ style live (wide angles: cells and membranes; long sensors: highways).

system "l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

W:960; H:720; SCALE:1;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

N: 60000;
SA: 0.5;                            / sensor angle offset (rad)
SD: 9f;                             / sensor distance ahead (px)
TA: 0.35;                           / turn per step (rad)
SS: 1.2;                            / step size (px)
DEP: 1f;                            / trail deposited per agent per step
DEC: 0.94;                          / field decay factor per step

/ toroidal flat-buffer index of float coordinates (q's mod is positive for
/ a positive divisor, so off-screen and negative positions wrap cleanly;
/ floor, not `long$, because `long$ rounds and 719.6 must not hit row 720)
tidx:{[x;y] ((floor y mod H)*W) + floor x mod W}

seed:{[]
    X:: W*N?1f; Y:: H*N?1f;
    TH:: 6.28318530718*N?1f;
    T:: (W*H)#0f; }

step:{[]
    / sense the trail at three points ahead
    la: TH-SA; ra: TH+SA;
    f: T tidx[X+SD*cos TH; Y+SD*sin TH];
    l: T tidx[X+SD*cos la; Y+SD*sin la];
    r: T tidx[X+SD*cos ra; Y+SD*sin ra];
    / steer toward the strongest side unless straight ahead already wins;
    / a little angular noise keeps the lanes organic rather than gridlocked
    TH:: TH + (0.2*(N?1f)-0.5) + TA*((r>l)-l>r)*not (f>=l)&f>=r;
    X:: (X+SS*cos TH) mod W;
    Y:: (Y+SS*sin TH) mod H;
    / deposit, then diffuse (cross box blur) and decay the whole field
    T:: @[T; tidx[X;Y]; +; DEP];
    T:: DEC*0.2*T+(1 rotate T)+(-1 rotate T)+(W rotate T)+neg[W] rotate T; }

/ attractant brush: disk of offsets poured into the trail field
BR:12; o: neg[BR]+til 1+2*BR;
bx: ((count o)*count o)#o; by: raze (count o)#/:o;
kp: where ((bx*bx)+by*by)<=BR*BR;
bx: bx kp; by: by kp;

/ --- parameter panel: p toggles, drag a knob to tune the sim live ----------
/ (global; min; max) - the knob writes straight to the named root global
PANEL:0b; DRAG:-1;
SLD: ((`SA;0.1;1.2);(`SD;2f;25f);(`TA;0.05;1f);(`SS;0.4;3f);(`DEC;0.8;0.99);(`DEP;0.2;3f));
PX:14; PY:36; TW:150; RH:16;

slider:{[ev;i]
    lbl: SLD[i;0]; mn: SLD[i;1]; mx: SLD[i;2];
    y: PY+RH*i;
    f: 0f|1f&((`float$value lbl)-mn)%mx-mn;
    .qvis.rect[PX; y+5; TW; 2; .qvis.gray];
    .qvis.rect[PX+(f*TW)-2; y; 5; 12; .qvis.white];
    .qvis.text[PX+TW+10; y+3; 1; .qvis.white;
        string[lbl]," ",string $[10f>v:`float$value lbl; 0.001*`long$v*1000; `long$v]];
    if[(ev`click)&((ev`my) within (y;y+13))&(ev`mx) within (PX-4;PX+TW+4); DRAG::i]; }

panelFrame:{[ev]
    if[`p in ev`new; PANEL::not PANEL];
    if[not PANEL; :(::)];
    .qvis.rect[PX-8; PY-12; TW+170; 30+RH*count SLD; .qvis.fade[190;1973790i]];
    slider[ev] each til count SLD;
    / drag: press on a row grabs the knob, releasing the button drops it
    / (.qvis.PL is the left-button level poll[] just recorded)
    if[not .qvis.PL; DRAG::-1];
    if[DRAG>=0; (SLD[DRAG;0]) set SLD[DRAG;1]+(SLD[DRAG;2]-SLD[DRAG;1])*0f|1f&((ev`mx)-PX)%TW];
    by2: PY+RH*count SLD;
    .qvis.rect[PX; by2+2; 44; 13; .qvis.fade[120;.qvis.gray]];
    .qvis.text[PX+7; by2+5; 1; .qvis.white; "RESET"];
    if[(ev`click)&((ev`my) within (by2+2;by2+15))&(ev`mx) within (PX;PX+44); seed[]]; }

.z.ts:{
    ev: .qvis.poll[];
    / pour attractant while the button is held anywhere off the panel
    op: PANEL and ((ev`mx) within (PX-8;PX+TW+161)) and (ev`my) within (PY-12;PY+17+RH*count SLD);
    if[.qvis.PL and (DRAG<0) and not op;
        T:: @[T; tidx[(ev`mx)+bx; (ev`my)+by]; +; 6f]];

    step[];

    / dark -> teal -> near-white glow, straight off the field intensity
    b: 1f & T*0.25;
    .qvis.setpixels (65536i*`int$b*90)+(256i*`int$b*225)+`int$30+b*225;
    if[not PANEL; .qvis.text[8; H-22; 2; .qvis.white; "Press p to open menu"]];
    panelFrame ev;
    .qvis.present[] }

seed[]
system "t 16"
