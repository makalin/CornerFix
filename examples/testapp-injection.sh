#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

echo "Building CornerFix and the unsigned test app"
make -C "$ROOT_DIR"

echo "Launching test app with injection"
"$ROOT_DIR/build/cornerfix-inject" --app "$ROOT_DIR/build/CornerFixTestApp.app"

echo "Next steps:"
echo "  ps aux | grep CornerFixTestApp"
echo "  vmmap <PID> | grep -i cornerfix"
echo "  $ROOT_DIR/build/cornerfixctl --radius 0"
echo "  $ROOT_DIR/build/cornerfixctl --radius 10"
