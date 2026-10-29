#!/usr/bin/env bash
# Runs the whole gdUnit4 suite headless. Exits non-zero if any test fails.
# Godot binary: $GODOT, default /Applications/Godot.app/Contents/MacOS/Godot.
set -uo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."

if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found: $GODOT (set \$GODOT)" >&2
  exit 2
fi

if [ ! -d .godot ]; then
  echo "First run: importing project..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

"$GODOT" --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests --ignoreHeadlessMode "$@"
code=$?
echo "gdUnit4 exit code: $code"
exit $code
