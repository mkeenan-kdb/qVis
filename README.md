# qVis

A pixel-buffer drawing library for [kdb+/q](https://kx.com), backed by SDL3.
It gives q a `qSDL.so` shared library exposing an immediate-mode canvas
(`pixel`, `line`, `rect`, `circle`, `text`) plus a fast `setpixels` path for
pushing a whole computed frame (e.g. a plasma effect) in one call. SDL runs
on the main thread; a background pipe-timer keeps the window's event loop
pumping without blocking the q REPL.

## Dependencies

- [kdb+/q](https://kx.com/kdb-personal-edition-download/) (KXVER 3)
- [SDL3](https://github.com/libsdl-org/SDL) — e.g. `brew install sdl3`
- CMake 3.20+
- A C++20 compiler

## Build

```sh
cmake -S . -B build
cmake --build build
cp build/qSDL.so .
```

`qVis.q` loads the library from `./qSDL`, so `qSDL.so` needs to be in the
directory you launch `q` from (the `cp` above puts it alongside the `.q`
files).

## Run

```sh
q qVis.q
```

This just defines the API (`init`, `clear`, `pixel`, `line`, `rect`,
`circle`, `text`, `present`, `setpixels`, `shutdown`) — call them yourself
from the q session, e.g.:

```q
init[320; 240; 2]
clear[black]
circle[160; 120; 80; red]
present[]
shutdown[]
```

Or run one of the bundled examples, each of which loads `qVis.q` itself:

```sh
q exampleBounce.q     # bouncing ball, immediate-mode primitives
q exampleAnimation.q  # full-frame plasma effect via setpixels
q exampleRipple.q     # water-ripple interference pattern
q exampleText.q       # bitmap font demo
```

## Files

- `qSDL.cpp` / `k.h` — the C++ side: SDL window/renderer management and
  drawing primitives, exposed to q via the kdb+ C API.
- `qVis.q` — q wrapper that loads `qSDL.so` and defines the friendly API.
- `example*.q` — standalone demos.
