# Lovecraft TD

Godot 4 tower defense (2D, GDScript). Design: `docs/GDD.md`.

## Versions

- Godot 4.7.2.stable (standard build, not .NET): `brew install --cask godot`
  (binary: `/Applications/Godot.app/Contents/MacOS/Godot`)
- gdUnit4 6.2.2 (vendored in `addons/gdUnit4/`)
- Renderer: Compatibility (`gl_compatibility`), required for web export

## Export templates (needed for web export)

Download `Godot_v4.7.2-stable_export_templates.tpz` from
https://github.com/godotengine/godot/releases/tag/4.7.2-stable, unzip it, and copy
the contents of `templates/` to
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
(it must contain `web_*.zip`).

## Tests

```
scripts/test.sh
```

Runs the whole gdUnit4 suite (`res://tests`) headless; exits non-zero on any failure.
Binary from `$GODOT` (default `/Applications/Godot.app/Contents/MacOS/Godot`).
Does the first-time import automatically when `.godot/` is missing.
Reports go to `reports/` (git-ignored).

## Web build

Prerequisite: export templates 4.7.2 (see above).

```
scripts/export-web.sh          # exports to build/web/ (git-ignored), prints path and size
scripts/serve-web.py [port]    # serves build/web, default port 8060
```

Open http://localhost:8060/ in Chrome or Safari. Stop the server with Ctrl+C.
`$GODOT` overrides the Godot binary.

Known limits:
- Single-threaded export (`thread_support=false`), so no special hosting is needed;
  the server still sends COOP/COEP headers, harmless here.
- Needs WebGL2; the first load is slow (~38 MB, wasm compile), 20-30 s under load.
- Must be served over HTTP; `file://` does not work.
