/ exampleDashboard.q - Streaming market-data dashboard built with .vis.dash.
/ Same idea as exampleDashboardRaw.q (a simulated multi-symbol trade feed),
/ built on inspect.q's dashboard tool instead of hand-rolled panels, layout
/ and input handling - about a tenth of the code.
/ Run from the repo root:  q examples/exampleDashboard.q
/ 2x2 grid:
/   top left     AAPL trade price
/   top right    a fresh random-walk OHLC candle series for AAPL
/   bottom left  total traded size by symbol
/   bottom right live tail of the raw multi-symbol trade feed
/ Panels are display-only - click (or right-click) one to zoom into a full
/ live view of it, with all the usual interactivity (sort, filter, command
/ bar); esc returns to the grid. Each panel calls .ex.feed[] itself (except
/ the candle, which regenerates its own independent random walk) so every
/ one keeps moving regardless of which panel you're looking at - a panel
/ that only *read* a table another panel's src advances would go static the
/ moment you zoom away from that driving panel, since only the top of the
/ view stack ever redraws.

$[count e:getenv`QVIS; system"l ",e,"/inspect.q"; system"l inspect.q"];

.ex.SYMS:`AAPL`MSFT`AMZN`GOOG`TSLA`NVDA;
.ex.LAST:.ex.SYMS!150 320 140 140 240 480f;      / latest price per symbol
.ex.TBL:([] time:`timestamp$(); sym:0#`; price:`float$(); size:`long$());

.ex.nrand:{(sqrt neg 2*log x?1f)*cos 2*acos[-1]*x?1f}  / standard normals (Box-Muller)

/ one burst of trades appended to a bounded rolling window; called each
/ refresh cycle by the plot panel below - a poor man's feed, same pattern as
/ .demo.feed in demo.q
.ex.feed:{[]
  n:30+rand 50; sm:n?.ex.SYMS;
  px:.ex.LAST[sm]*1f+.001*.ex.nrand n;
  @[`.ex.LAST;sm;:;px];
  .ex.TBL,:([] time:n#.z.p; sym:sm; price:px; size:1+n?100);
  .ex.TBL::-4000 sublist .ex.TBL;
  .ex.TBL}

/ a fresh random-walk OHLC session for one symbol, regenerated each refresh
.ex.day:{[s]
  n:390; c:.ex.LAST[s]*prds 1+.0004*.ex.nrand n; o:c*1+.0002*.ex.nrand n;
  ([] time:09:30:00.000+til n; open:o; high:(o|c)*1.001; low:(o&c)*.999; close:c)}

.vis.dash (
  (`plot;   {select time,price from .ex.feed[] where sym=`AAPL}; 0 0 1 1; 200);
  (`candle; {.ex.day `AAPL};                                     1 0 1 1; 5000);
  (`bar;    {select sum size by sym from .ex.feed[]};             0 1 1 1; 500);
  (`tab;    .ex.feed;                                             1 1 1 1; 200))
