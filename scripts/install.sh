#!/bin/sh
set -eu

PREFIX=${PREFIX:-/usr/local}
LIB_DIR=${LIB_DIR:-$PREFIX/lib/cornerfix}
BIN_DIR=${BIN_DIR:-$PREFIX/bin}
SHARE_DIR=${SHARE_DIR:-$PREFIX/share/cornerfix}

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

mkdir -p "$LIB_DIR" "$BIN_DIR" "$SHARE_DIR/examples"
install -m 755 "$ROOT_DIR/build/libcornerfix.dylib" "$LIB_DIR/libcornerfix.dylib"
install -m 755 "$ROOT_DIR/build/cornerfixctl" "$BIN_DIR/cornerfixctl"
install -m 755 "$ROOT_DIR/build/cornerfix-inject" "$BIN_DIR/cornerfix-inject"
install -m 644 "$ROOT_DIR/libcornerfix.dylib.blacklist" "$SHARE_DIR/libcornerfix.dylib.blacklist"
install -m 644 "$ROOT_DIR/README.md" "$SHARE_DIR/README.md"
install -m 644 "$ROOT_DIR/CLI.md" "$SHARE_DIR/CLI.md"
install -m 644 "$ROOT_DIR/LOADER.md" "$SHARE_DIR/LOADER.md"
install -m 644 "$ROOT_DIR/COMPATIBILITY.md" "$SHARE_DIR/COMPATIBILITY.md"
install -m 644 "$ROOT_DIR/TESTING.md" "$SHARE_DIR/TESTING.md"
install -m 755 "$ROOT_DIR/examples/basic-workflow.sh" "$SHARE_DIR/examples/basic-workflow.sh"
install -m 755 "$ROOT_DIR/examples/ammonia-style-usage.sh" "$SHARE_DIR/examples/ammonia-style-usage.sh"
install -m 755 "$ROOT_DIR/examples/per-app-overrides.sh" "$SHARE_DIR/examples/per-app-overrides.sh"
install -m 755 "$ROOT_DIR/examples/reset-and-reload.sh" "$SHARE_DIR/examples/reset-and-reload.sh"
install -m 755 "$ROOT_DIR/examples/testapp-injection.sh" "$SHARE_DIR/examples/testapp-injection.sh"

printf 'Installed:\n'
printf '  %s\n' "$LIB_DIR/libcornerfix.dylib" "$BIN_DIR/cornerfixctl" "$BIN_DIR/cornerfix-inject" "$SHARE_DIR/libcornerfix.dylib.blacklist" "$SHARE_DIR/TESTING.md"
