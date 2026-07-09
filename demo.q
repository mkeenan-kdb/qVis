/ demo.q - guided tour of the .vis inspector on realistic demo data.
/ Run from the repo root:  q demo.q
/ (or from anywhere with QVIS=/path/to/qVis exported)
/ Builds:
/   trade      1M-row date-partitioned tick table in db/ (random-walk prices)
/   daily      250 days of OHLC bars per symbol
/   sensors    a day of 30s sensor readings (three overlapping series)
/   alltypes   small table with one column of every common q type
/   returns    20k normally-distributed floats
/   xs, ys     correlated pairs for the scatter plot
/   .stats     a small namespace to drill into with .vis.ns
/ then prints a numbered menu - type demo N at the q prompt to run one.
/ NOTE db/ is only built when absent: rm -rf db and rerun to regenerate.

/ ---------------------------------------------------------------------------
/ Data generators
/ ---------------------------------------------------------------------------
.demo.SYMS:`AAPL`MSFT`AMZN`GOOG`NFLX`TSLA;
.demo.S0:.demo.SYMS!192 415 178 165 987 242f;   / base prices

/ standard normals (Box-Muller) and a geometric random walk from s0
.demo.nrand:{(sqrt neg 2*log x?1f)*cos 2*acos[-1]*x?1f}
.demo.walk:{[s0;vol;n] s0*prds 1+vol*.demo.nrand n}

/ one partition of ticks: per-sym intraday walks; raze leaves the rows
/ grouped by sym (time-ascending within each), as `p#sym requires
.demo.dayTab:{[dt]
  raze {[s]
    m:15000+rand 5000;
    ([] sym:m#s; time:asc 09:30:00.000+m?23400000;
        price:.demo.walk[.demo.S0 s;.0005;m]; size:100*1+m?100)
    } each .demo.SYMS}

.demo.wrDay:{[dt]
  t:update `p#sym from .Q.en[`:db] .demo.dayTab dt;
  (.Q.dd[`:db;(dt;`trade;`)]) set t;}

/ build the partitioned db only when db/ is absent, before inspect.q
/ auto-loads it (that load chdirs into db/, so build first from the root)
if[not `db in key `:.;
  -1"[demo] building db/trade (10 partitions of random-walk ticks)...";
  .demo.wrDay each .z.D-1+til 10];

$[count e:getenv`QVIS; system"l ",e,"/inspect.q"; system"l inspect.q"];

/ in-memory demo data
.demo.DTS:.z.D-reverse 1+til 250;
.demo.ohlc:{[s]
  n:count .demo.DTS;
  c:.demo.walk[.demo.S0 s;.015;n];
  o:c*1+.004*.demo.nrand n;
  ([] date:.demo.DTS; sym:n#s; open:o;
      high:(o|c)*1+abs .004*.demo.nrand n; low:(o&c)*1-abs .004*.demo.nrand n;
      close:c; volume:`long$1e6*1+abs .demo.nrand n)}
daily:raze .demo.ohlc each .demo.SYMS;

m:2880;                                       / one day at 30s intervals
sensors:([] time:00:00:00.000+30000*til m;
  temp:20+(3*sin .004*til m)+.2*.demo.nrand m;
  pressure:101+(2*cos .002*til m)+.15*.demo.nrand m;
  vibration:abs (sin .05*til m)+.3*.demo.nrand m);
`:db/sensors set sensors;

returns:.demo.nrand 20000;
xs:.demo.nrand 2000; ys:(.7*xs)+.3*.demo.nrand 2000;

m:100000;
alltypes:([]
  b:m?01b; g:m?0Ng; x:`byte$m?256; h:m?32767h; i:m?1000i; j:m?100000j;
  e:m?100e; f:m?1000f; c:m?.Q.a; s:m?.demo.SYMS;
  p:.z.P+m?1000000000000j; d:.z.D-m?365; t:m?24:00:00.000; str:string m?1000);
`:db/alltypes/ set .Q.en[`:db;alltypes];
delete m from `.;

/ a namespace worth drilling into with .vis.ns
.stats.mean:{avg x};
.stats.stdev:{sqrt var x};
.stats.zscore:{(x-avg x)%dev x};
.stats.ols:{[x;y](cov[x;y]%var x;avg[y]-avg[x]*cov[x;y]%var x)};
.stats.cfg:`window`alpha!(20;.05);
.stats.pi:acos -1;

/ synthetic live feed for the watch demos: each call appends one random-walk
/ OHLC bar (bounded rolling window) and returns the table. .vis.watchAs
/ calls it once per refresh cycle - no separate timer needed.
.demo.LIVE:([] time:`timespan$(); open:`float$(); high:`float$();
  low:`float$(); close:`float$());
.demo.feed:{[]
  o:$[count .demo.LIVE; last .demo.LIVE`close; 100f];
  c:o+-0.5+rand 1f;
  .demo.LIVE::-240 sublist .demo.LIVE upsert (.z.N;o;(o|c)+rand .2;(o&c)-rand .2;c);
  .demo.LIVE}

\l db
/ ---------------------------------------------------------------------------
/ Menu
/ ---------------------------------------------------------------------------
.demo.LIST:([]
  name:("intraday price walk (partitioned query)";
        "multi-series line plot, one per symbol";
        "table plot with a time axis";
        "histogram - normal returns";
        "scatter - correlated pairs";
        "table browser - 1M-row partitioned trade table";
        "table browser - every q column type";
        "partitioned-database overview";
        "namespace explorer (drill into .stats)";
        "live memory monitor";
        "multiline q editor/REPL";
        "OHLC candlestick - AAPL daily bars";
        "bar chart - total volume by symbol";
        "live watch - tail of trade, 1s refresh";
        "LIVE candlestick - synthetic random-walk feed";
        "LIVE table tail - a graphical tail -f");
  code:(".vis.plot select time, price from trade where date=max date, sym=`AAPL";
        ".vis.plot flip exec close by sym from daily";
        ".vis.plot sensors";
        ".vis.hist[returns;60]";
        ".vis.scatter[xs;ys]";
        ".vis.tab `trade";
        ".vis.tab alltypes";
        ".vis.db[]";
        ".vis.ns[]";
        ".vis.mem[]";
        ".vis.repl[]";
        ".vis.candle select from daily where sym=`AAPL";
        "{.vis.bar[key x;value x]} exec sum volume by sym from daily";
        ".vis.watch[`trade;1000]";
        ".vis.watchAs[.demo.feed;250;`candle]";
        ".vis.watchAs[.demo.feed;250;`tab]"));

.demo.menu:{[]
  -1"\nqVis inspector demo - type demo N to run one:\n";
  {[i;r] -1"  demo ",(2$string i),"  ",(50$r`name),"  ",r`code;}'
    [1+til count .demo.LIST;.demo.LIST];
  -1"\nIn the window: every view has a q) command bar at the bottom - type any";
  -1"q code there and hit enter (try deleting a global while in .vis.ns, or";
  -1"opening a plot from inside a table). \\l, \\t etc. work console-style.";
  -1"Click drills down, esc goes back, the close button quits.\n";}

demo:{[i]
  if[(::)~i; :.demo.menu[]];
  if[not i within (1;count .demo.LIST); :-1"demo: pick 1-",string count .demo.LIST];
  r:.demo.LIST i-1;
  -1"q) ",r`code;
  res:@[value;r`code;{-1"demo error: ",x;}];
  if[not any (::)~/:enlist res; show res];}

if[not `trade in tables[];
  -1"[demo] db/ holds the old dummy data (no trade table) - partitioned demos";
  -1"[demo] will fail. rm -rf db and rerun q demo.q to rebuild it."];
.demo.menu[]
