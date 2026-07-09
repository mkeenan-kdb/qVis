#! /bin/bash
set -e
cmake -S cpp -B build
cmake --build build
# rm first: cp over an existing file reuses the vnode and macOS then kills
# q with SIGKILL (Code Signature Invalid) when it maps the stale signature
rm -f qSDL.so
cp build/qSDL.so .

