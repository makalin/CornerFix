#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CTL="$ROOT_DIR/build/cornerfixctl"

echo "Resetting all settings"
"$CTL" reset

echo "Broadcasting reload"
"$CTL" reload

echo "Status after reset"
"$CTL" --status
