
/ exampleNBody.q - N-body gravity simulation, fully vectorised. Pairwise
/ O(N^2) force matrices cap out around ~1,200 bodies, so gravity is instead
/ solved on a coarse grid (a particle-mesh scheme): bodies are binned into
/ CS-px cells with the same scatter-add idiom as exampleFluid.q's spatial
/ hash, each occupied cell is reduced to its total mass and centre of mass,
/ and every body then feels every *cell* through one N x C matrix product
/ (mmu, BLAS-backed). C is a few hundred where N is tens of thousands, so
/ the frame cost is O(N) and 10-20k bodies stay realtime. Gravity is
/ long-range, so unlike the fluid's short-range kernels distant sources
/ can't be dropped - they can only be lumped, which is exactly what the
/ cell COM does. Softened gravity (EPS2) hides the grid granularity and
/ keeps close encounters from producing singular forces.
/ Masses are heavy-tailed: most bodies are ~0.5-mass stars, a few percent
/ are 3-4.5-mass giants that render as larger disks and pull harder.
/ Bodies are stamped into a flat ARGB pixel buffer (ragged per-body disk
/ offsets, no loops) and pushed with one .qvis.setpixels call.
/ Controls: arrows pan, r/f (or wheel) zoom in/out, left-drag pans,
/ c recentres, p opens a slider panel to tune G/CENTRAL/DT/EPS2/N live.

system "l qVis.q"

W:1280; H:900; SCALE:1;
.qvis.init[W; H; SCALE]

system "S ",string `int$.z.t

CX: W%2f; CY: H%2f;
R: 360f;                            / initial disk radius

G: 0.08;
CENTRAL: 8500f;                     / compact central mass: simple disk-galaxy potential
DT: 0.30;
EPS2: 200f;                         / softening length^2 - also blurs the force grid's cell edges
NNEXT: 6000f;                       / body count applied by the next RESET (slider-driven)

/ far-field force grid: CS-px cells; bodies that wander off-canvas are
/ clamped into the border cells (their true positions still feed the COM,
/ so their pull stays roughly right)
CS: 64f;
NCX: `int$ceiling W%CS; NCY: `int$ceiling H%CS;

/ acceleration of every body: bin into cells, reduce each occupied cell to
/ (mass; COM), then one N x C softened-gravity matrix product per axis.
/ A body's own cell includes itself; EPS2 keeps that self-bias negligible.
/ (exampleFluid.q style) if close-encounter scattering ever matters
accel:{[]
    cid: (`long$0|(NCX-1)&floor X%CS) + NCX*`long$0|(NCY-1)&floor Y%CS;
    mc: @[(NCX*NCY)#0f; cid; +; M];
    u: where mc>0f; w: mc u;
    gx: (@[(NCX*NCY)#0f; cid; +; M*X] u)%w;
    gy: (@[(NCX*NCY)#0f; cid; +; M*Y] u)%w;
    dx: X -\: gx; dy: Y -\: gy;
    d2: EPS2 + (dx*dx)+dy*dy;
    invd3: 1f % d2*sqrt d2;
    ax: neg G * (dx*invd3) mmu w;
    ay: neg G * (dy*invd3) mmu w;
    rx: X-CX; ry: Y-CY; rc2: EPS2+(rx*rx)+ry*ry;
    rc3: rc2*sqrt rc2;
    (ax-G*CENTRAL*rx%rc3; ay-G*CENTRAL*ry%rc3) }

/ per-size-class stamp offsets into the flat buffer: point / plus / r=2 disk
o: `int$-2+til 5;
gx2: raze 5#enlist o; gy2: raze 5#'o;
k2: where ((gx2*gx2)+gy2*gy2)<=5;
OFF: (enlist 0i; 0 -1 1 0 0i; gx2 k2) + W*(enlist 0i; 0 0 0 -1 1i; gy2 k2);

/ (re)seed the disk at the slider's body count; called at load and by RESET
seed:{[]
    N:: `int$NNEXT;
    rad: R*sqrt N?1f;                / uniform-disk sampling
    ang: 6.28318530718*N?1f;
    X:: CX+rad*cos ang; Y:: CY+rad*sin ang;
    / heavy-tailed mass spectrum: u^6 piles most bodies near 0.5 and leaves
    / a few percent of 2.5-4.5 giants; RC is the render size class
    M:: 0.5f+4f*(N?1f) xexp 6;
    RC:: (M>2.5f)+M>4f;
    / colour once per body from its mass: heavier reads warmer/brighter
    frac: (M-min M) % 1e-9|(max M)-min M;
    COL:: (65536i*`int$150+105*frac) + (256i*`int$110+105*frac) + `int$170+70*frac;
    / near-circular orbits in the combined central+disk potential, with a
    / small dispersion folded into the launch angle
    vcirc: sqrt G*(CENTRAL+(sum M)*(rad*rad)%R*R)%1f|rad;
    disp: 0.12f*(N?1f)-0.5f;
    VX:: vcirc*neg sin ang+disp; VY:: vcirc*cos ang+reverse disp;
    A:: accel[]; }

/ Camera controls affect only the rendered view, never the physics.
ZOOM:1f; CAMX:CX; CAMY:CY;
PANDRAG:0b; PMX:0; PMY:0;           / left-drag pan state + last mouse pos

/ --- parameter panel: p toggles, drag a knob to tune the sim live ----------
/ (global; min; max) - the knob writes straight to the named root global
PANEL:0b; DRAG:-1;
SLD: ((`G;0.005;0.4);(`CENTRAL;0f;12000f);(`DT;0.05;0.9);(`EPS2;25f;4000f);(`NNEXT;500f;20000f));
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
    by: PY+RH*count SLD;
    .qvis.rect[PX; by+2; 44; 13; .qvis.fade[120;.qvis.gray]];
    .qvis.text[PX+7; by+5; 1; .qvis.white; "RESET"];
    if[(ev`click)&((ev`my) within (by+2;by+15))&(ev`mx) within (PX;PX+44); seed[]]; }

.z.ts:{
    ev: .qvis.poll[];
    if[((ev`wheel)>0)|`r in ev`held; ZOOM::0.30f|3f&1.08f*ZOOM];
    if[((ev`wheel)<0)|`f in ev`held; ZOOM::0.30f|3f&ZOOM%1.08f];
    pan: 18f%ZOOM;
    if[`up    in ev`held; CAMY::CAMY-pan];
    if[`down  in ev`held; CAMY::CAMY+pan];
    if[`left  in ev`held; CAMX::CAMX-pan];
    if[`right in ev`held; CAMX::CAMX+pan];
    if[`c in ev`new; ZOOM::1f; CAMX::CX; CAMY::CY];

    / drag-to-pan: a press anywhere off the panel grabs the world, which
    / then follows the cursor 1:1 (divide by ZOOM to convert screen px to
    / world px) until the button is released
    op: PANEL and ((ev`mx) within (PX-8;PX+TW+161)) and (ev`my) within (PY-12;PY+17+RH*count SLD);
    if[(ev`click) and not op; PANDRAG::1b];
    if[not .qvis.PL; PANDRAG::0b];
    if[PANDRAG; CAMX::CAMX-((ev`mx)-PMX)%ZOOM; CAMY::CAMY-((ev`my)-PMY)%ZOOM];
    PMX::ev`mx; PMY::ev`my;

    / kick-drift-kick (leapfrog): time reversible, conserves orbital energy
    / far better than forward Euler. A carries last frame's closing kick
    / acceleration forward, so it's one grid force eval per frame, not two.
    VX::VX+0.5f*DT*A 0; VY::VY+0.5f*DT*A 1;
    X::X+DT*VX; Y::Y+DT*VY;
    A::accel[];
    VX::VX+0.5f*DT*A 0; VY::VY+0.5f*DT*A 1;

    / stamp every body's size-class disk in one ragged scatter: per-body
    / base index + that class's offset list, razed flat. Later (heavier
    / rows drawn last only by input order) duplicates simply overwrite.
    buf: (W*H)#.qvis.black;
    sx: CX+ZOOM*(X-CAMX); sy: CY+ZOOM*(Y-CAMY);
    ix: `long$sx; iy: `long$sy;
    b: where (ix within 2,W-3) & iy within 2,H-3;   / margin covers the r=2 stamp
    if[count b;
        offs: OFF RC b;
        buf: @[buf; raze ((W*iy b)+ix b)+offs; :; raze (count each offs)#'COL b]];
    .qvis.setpixels buf;
    .qvis.circle[`int$CX+ZOOM*(CX-CAMX);`int$CY+ZOOM*(CY-CAMY);4;.qvis.white];
    if[not PANEL; .qvis.text[8; H-22; 2; .qvis.white; "Press p to open menu"]];
    panelFrame ev;
    .qvis.present[] }

seed[]
system "t 25"
