
/ exampleText.q - demo of the text[] primitive: draws strings at different
/ sizes so you can "type" labels/HUD text onto the canvas.
/ text[x; y; scale; color; str] - see qVis.q for the supported character set.

system "l qVis.q"

W:400; H:200; SCALE:2;
init[W; H; SCALE]

clear[black]
text[10; 10;  2; white;   "HELLO, QVIS!"]
text[10; 50;  4; cyan;    "BIG TEXT"]
text[10; 110; 1; yellow;  "SMALL: THE QUICK BROWN FOX 123"]
text[10; 130; 1; magenta; "SYMBOLS: HI, THERE! - OK? YES."]
present[]

system "sleep 5"
shutdown[]
