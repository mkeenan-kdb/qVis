
/ exampleText.q - demo of the text[] primitive plus the blink[]/marqueeX[]
/ animation utilities from qVis.q.
/ text[x; y; scale; color; str] - see qVis.q for the supported character set.

system "l qVis.q"

W:400; H:200; SCALE:2;
.qvis.init[W; H; SCALE]

/ Static labels
.qvis.text[10; 10;  2; .qvis.white;   "HELLO, QVIS!"]
.qvis.text[10; 110; 1; .qvis.yellow;  "SMALL: THE QUICK BROWN FOX 123"]
.qvis.text[10; 130; 1; .qvis.magenta; "SYMBOLS: HI, THERE! - OK? YES."]

/ Flashing label - drawn only while blink[] is on
flashStr: "BIG TEXT"; flashScale: 4i; flashY: 50i;

/ Scrolling marquee along the bottom
marqueeStr: "...NOW SCROLLING ACROSS THE SCREEN..."; marqueeScale: 1i; marqueeY: 160i;
marqueeW: .qvis.textWidth[marqueeScale; marqueeStr];

lastT: .z.p
t: 0f

.z.ts:{
    now: .z.p;
    t+: 1e-9 * `float$ now-lastT;
    lastT:: now;

    .qvis.clear[.qvis.black];
    if[.qvis.blink[0.8; t]; .qvis.text[10; flashY; flashScale; .qvis.cyan; flashStr]];
    .qvis.text[.qvis.marqueeX[80f; W; marqueeW; t]; marqueeY; marqueeScale; .qvis.green; marqueeStr];
    .qvis.present[]
    }

/ Start at ~60 fps
system "t 16"
