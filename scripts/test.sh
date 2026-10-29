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

# No -d: under the debugger a script parse error still exits 0.
log="$(mktemp)"
"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests --ignoreHeadlessMode "$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
# gdUnit4 exits 0 when it finds no tests (e.g. every test script failed to parse).
if [ "$code" -eq 0 ] && grep -q "No test cases found" "$log"; then
  echo "No test cases found: treating as failure" >&2
  code=1
fi
rm -f "$log"
echo "gdUnit4 exit code: $code"
exit $code
