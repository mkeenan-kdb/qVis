// minimalExample.q - the smallest useful qVis demo: a string bouncing
// around the window like a screensaver (the old DVD-logo screensaver).
// Read this top to bottom if you're new to qVis - it touches every
// fundamental piece:
//   1. loading the library and opening a window      (.qvis.init)
//   2. loading a font and drawing text with it       (.qvis.loadsysfont / .qvis.drawtext)
//   3. the per-frame callback that makes it move     (.z.ts)
//   4. the timer that drives that callback           (system "t ...")
//
// Run it with:  q apps/minimalExample.q

// Load qVis.q. QVIS env var should point at this repo (see qVis.q's header);
// if you're running q from the repo root this also works unqualified.
system"l ",$[count e:getenv`QVIS; e,"/qVis.q"; "qVis.q"]

// Open a window. Real pixels are windowWidth x windowHeight; windowScale is
// an integer zoom factor applied on top, so the actual OS window is
// (windowWidth*windowScale) x (windowHeight*windowScale).
windowWidth:400; windowHeight:200; windowScale:2;
.qvis.init[windowWidth; windowHeight; windowScale]

// Load a system font at a fixed point size and draw with it via drawtext[]
// (as opposed to the small built-in 5x7 bitmap font used by .qvis.text[]).
// fontSize is in points, same units .qvis.textsize[] measures in - keep it
// named rather than inlined so it's obvious the two must move together.
fontSize: 48i;
font: .qvis.loadsysfont[`prop; fontSize];

// --- state -------------------------------------------------------------
// Everything the animation needs to remember between frames lives in plain
// global variables, updated in place with `::` inside the callback below.
label: "DVD";

// textsize[] would return the font's full line height (ascent+descent+
// leading), which is taller than the glyphs actually drawn - "DVD" has no
// descenders, so that box leaves dead space below the letters and the text
// would visibly stop short of the bottom edge before bouncing. textinkbox[]
// instead measures the tight bounding box of the pixels actually inked, so
// the bounce below lines up with what's really on screen.
inkBox:  .qvis.textinkbox[font; label];   // (offsetX; offsetY; width; height)
inkOffX: inkBox 0; inkOffY: inkBox 1;
inkW:    inkBox 2; inkH:    inkBox 3;

posX: 20f; posY: 20f;             // text starts at the top-left of the window (floats: sub-pixel motion)
velX: 70f; velY: 48f;            // velocity in pixels/second

lastTime: .z.p;                   // timestamp of the previous frame (nanoseconds)

// --- the animation loop --------------------------------------------------
// .z.ts is the q system callback: once a timer is running (see "t 16" below),
// q calls .z.ts on every timer tick. Everything that needs to happen each
// frame goes here.
.z.ts:{[]
    now: .z.p;
    dt:  1e-9 * `float$ now - lastTime;    // seconds elapsed since last frame
    lastTime:: now;

    // move the text by velocity * elapsed time, so speed is independent
    // of how often the timer actually fires
    posX+: velX * dt;
    posY+: velY * dt;

    // bounce: check the inked edges (posX/posY + the ink offset), not the
    // raw drawtext anchor, and clamp so the ink - not the anchor - lands
    // exactly on the wall before flipping the velocity component that was
    // carrying it that way.
    //
    // NOTE: q has no operator precedence - it evaluates strictly right to
    // left, and that applies within a single operator too: `400-95-3` is
    // `400-(95-3)` = 308, not the conventional (400-95)-3 = 302. So the far
    // edge clamps below use `windowWidth-(inkW+inkOffX)` rather than the
    // more natural-looking `windowWidth-inkW-inkOffX` (which would silently
    // clamp 2*inkOffX too far right/down, still overlapping the true edge
    // and freezing that axis as the bounce re-triggers every frame).
    // Separately, `posX+inkOffX<=0` would parse as `posX+(inkOffX<=0)` (a
    // number, not a boolean), which is why the comparisons are parenthesised
    // too - if[] requires an actual boolean condition.
    if[(posX+inkOffX)<=0;                 posX::neg inkOffX;                    velX::abs velX];
    if[(posX+inkOffX+inkW)>=windowWidth;  posX::windowWidth-(inkW+inkOffX);     velX::neg abs velX];
    if[(posY+inkOffY)<=0;                 posY::neg inkOffY;                    velY::abs velY];
    if[(posY+inkOffY+inkH)>=windowHeight; posY::windowHeight-(inkH+inkOffY);    velY::neg abs velY];

    // every frame: wipe the back buffer, draw the text at its new spot,
    // then present it to the visible window
    .qvis.clear[.qvis.black];
    .qvis.drawtext[posX; posY; font; .qvis.yellow; label];
    .qvis.present[]
    }

// Start a background timer that fires every 16ms (~60 frames/second).
// This is what actually invokes .z.ts above, repeatedly, without blocking
// the q console - you can still type commands while the window animates.
system "t 16"
