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

## Web export

```
mkdir -p build/web
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Web" build/web/index.html
```

Serve `build/web/` over HTTP to play (e.g. `python3 -m http.server -d build/web`).
