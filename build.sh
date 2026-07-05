#! /bin/bash
cmake -S . -B build
cmake --build build
cp build/qSDL.so .
