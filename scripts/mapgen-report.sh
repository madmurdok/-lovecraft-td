#!/usr/bin/env bash
# LT-130 S22: P1 map generator report (tools/mapgen/mapgen_report.gd): per-map lines and a
# summary of accepted maps, reject rates, rejects by reason and ms per map.
#
# Usage: scripts/mapgen-report.sh [--preset small|large] [--seeds N] [--from S] [--params f.json]
#        [--maps] [--out report.json]      (defaults: large, 1000 seeds from 1)
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
uptime
log="$(mktemp)"
set +e
/usr/bin/time -p "$GODOT" --headless --path . -s res://tools/mapgen/mapgen_report.gd -- "$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e
if grep -q "SCRIPT ERROR:" "$log"; then
  echo "mapgen-report: SCRIPT ERROR in the log; the numbers may be wrong" >&2
  code=3
fi
rm -f "$log"
exit $code
