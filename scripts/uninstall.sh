#!/bin/sh
set -eu

PREFIX=${PREFIX:-/usr/local}
LIB_DIR=${LIB_DIR:-$PREFIX/lib/cornerfix}
BIN_DIR=${BIN_DIR:-$PREFIX/bin}
SHARE_DIR=${SHARE_DIR:-$PREFIX/share/cornerfix}

rm -f "$LIB_DIR/libcornerfix.dylib"
rm -f "$BIN_DIR/cornerfixctl"
rm -f "$BIN_DIR/cornerfix-inject"
rm -f "$SHARE_DIR/libcornerfix.dylib.blacklist"
rm -f "$SHARE_DIR/README.md" "$SHARE_DIR/CLI.md" "$SHARE_DIR/LOADER.md" "$SHARE_DIR/COMPATIBILITY.md" "$SHARE_DIR/TESTING.md"
rm -f "$SHARE_DIR/examples/basic-workflow.sh" "$SHARE_DIR/examples/ammonia-style-usage.sh" "$SHARE_DIR/examples/per-app-overrides.sh" "$SHARE_DIR/examples/reset-and-reload.sh" "$SHARE_DIR/examples/testapp-injection.sh"
rmdir "$SHARE_DIR/examples" 2>/dev/null || true
rmdir "$SHARE_DIR" 2>/dev/null || true
rmdir "$LIB_DIR" 2>/dev/null || true

printf 'Removed CornerFix files from %s\n' "$PREFIX"
