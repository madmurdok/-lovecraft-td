#!/usr/bin/env bash
# Exports the "Web" preset to build/web/ (index.html + wasm + pck).
# Godot binary: $GODOT, default /Applications/Godot.app/Contents/MacOS/Godot.
set -euo pipefail
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

rm -rf build/web
mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html

if [ ! -s build/web/index.html ] || [ ! -s build/web/index.wasm ]; then
  echo "Export failed: build/web/index.html or index.wasm missing" >&2
  exit 1
fi
echo "Output: $(pwd)/build/web"
echo "Size:   $(du -sh build/web | cut -f1)"
