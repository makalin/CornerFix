#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cat <<EOF
Ammonia-style example

1. Build:
   make

2. Install:
   make install PREFIX=/usr/local

3. Point your loader at:
   /usr/local/lib/cornerfix/libcornerfix.dylib

4. Use the controller:
   /usr/local/bin/cornerfixctl --preset sharp
   /usr/local/bin/cornerfixctl --app com.apple.Safari --radius 4
   /usr/local/bin/cornerfixctl doctor

Reference docs:
  $ROOT_DIR/LOADER.md
EOF
