#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CTL="$ROOT_DIR/build/cornerfixctl"

echo "Current status:"
"$CTL" --status

echo "Applying sharp preset globally"
"$CTL" --preset sharp

echo "Set Finder softer than the global default"
"$CTL" --app com.apple.finder --radius 8

echo "List configuration"
"$CTL" list
