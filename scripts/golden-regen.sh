#!/usr/bin/env bash
# LT-73: rewrites tests/fixtures/golden_digests.json from the golden runs (tools/golden/regen.gd)
# on the frozen config in tests/fixtures/golden_data/, and (LT-102) the engine-neutral trace in
# tests/fixtures/golden_trace/ (manifest.json for every run, full .jsonl text for
# GoldenRuns.TRACE_FULL_RUNS). Only for an approved behaviour change: see tests/fixtures/README.md.
#
# Env: GODOT  Godot binary, default /Applications/Godot.app/Contents/MacOS/Godot.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."
if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found: $GODOT (set \$GODOT)" >&2
  exit 2
fi
# A stale class cache gives parse errors (see scripts/test.sh); re-import when a script is newer.
cache=.godot/global_script_class_cache.cfg
if [ ! -f "$cache" ] || [ -n "$(find . \( -path ./.godot -o -path ./.git \) -prune -o -name '*.gd' \
    -newer "$cache" -print -quit)" ]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
log="$(mktemp)"
"$GODOT" --headless --path . -s res://tools/golden/regen.gd 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR:" "$log"; then
  echo "golden-regen: SCRIPT ERROR in the log; the digests file may be wrong" >&2
  code=3
fi
rm -f "$log"
exit $code
