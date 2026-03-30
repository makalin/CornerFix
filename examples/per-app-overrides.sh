#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CTL="$ROOT_DIR/build/cornerfixctl"

"$CTL" --app com.apple.Safari on
"$CTL" --app com.apple.Safari --radius 0

"$CTL" --app com.apple.dt.Xcode on
"$CTL" --app com.apple.dt.Xcode --radius 4

"$CTL" list
