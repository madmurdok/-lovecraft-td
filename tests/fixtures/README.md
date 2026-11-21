# Test fixtures

## Golden replay (LT-73, B0 / guard G5 of docs/design/LT-65-architecture-review.md)

- `golden_data/`: a frozen copy of `data/` (every JSON file `GameConfig` loads), taken at
  0.5.0. Balance tuning edits `data/` and never touches the golden test. Do not edit
  `golden_data/` to follow `data/`.
- `golden_digests.json`: per-run digests of the golden runs (`tests/golden_runs.gd`): every
  drained event (type, tick, id, data with sorted keys, floats as their exact bits) hashed as a
  whole and per 900-tick bucket, the event count, and a hash of the final state. Runs: every
  `tools/bot_runs.gd` strategy x the seeds in `GoldenRuns.SEEDS`, the `SimNoTreeLoop` game and
  the LT-34 frame-driven `Game` run (its command log replayed on a bare sim).
- `tests/golden_replay_test.gd` recomputes the digests and compares; a failure names the run,
  the first differing tick window and the final-state summary.

### Regenerating `golden_digests.json`

```
scripts/golden-regen.sh
```

Only when the sim's behaviour changes on purpose and the owner approved that change (a new
mechanic, a rule change, a new event field), or when `golden_data/` itself is deliberately
replaced. Commit the regenerated file in the same commit as the change and say why in the
message. Never during a refactor (the refactor plan's steps must keep the golden test green
without regenerating), and never edit the file by hand.

## Golden trace (LT-102, `docs/design/LT-102-portability-core.md` §5)

- `golden_trace/manifest.json`: for every golden run, the line count and sha256 of its
  engine-neutral trace; `golden_trace/<run>.jsonl` (`/` -> `_`): the full text of the runs in
  `GoldenRuns.TRACE_FULL_RUNS` (`no_tree_loop/5`, `frame_path/1234`).
- Format: JSON Lines, LF, keys sorted. A header `{"data_dir", "format": "lovecraft-td-trace",
  "run", "version": 1}`, one `{"data", "id", "tick", "type"}` line per drained event in drain
  order (`type` is the `SimEvent.Type` name), and a `{"final": {...}}` line (the
  `SimNoTreeLoop.digest` scalars plus the 7 `SimRng` stream states as decimal strings of
  Godot's signed int64). Values are plain JSON (`GoldenRuns.neutral`): Vector2 / Vector2i ->
  `[x, y]`, floats as shortest round-trip binary64, ints within 2^53.
- Comparison rule for a port: compare parsed values (numbers as binary64), not text; Godot
  writes `1.0` for a float and `1` for an int, a port need not.
- `tests/golden_replay_test.gd` recomputes the trace in the same pass as the digests and
  compares; a full-text difference names the first differing line.
- Regenerate it only together with the digests, with `scripts/golden-regen.sh` (it rewrites
  both and deletes stale `.jsonl` files); never edit it by hand.

## Probe trait (LT-106)

- `probe_trait.gd` (`ProbeTrait`): a test-only enemy trait that records every hook call.
  `tests/trait_hooks_test.gd` injects it into `TraitCatalog` where a line in `_rows()` would
  put it, so it doubles as the "one file + one catalog line" proof for a new trait.

## Look variants (LT-104, `docs/design/LT-104-look-catalog.md` §2.3)

- `looks/variant_looks.json`: a `data/looks.json` that reuses built-in looks with no code
  (variants of tracer, dynamite, summon, banish and enemy; a built-in `tracer` on the coast
  battery, whose branch b falls back to `shell`). Read with `TextLoader.read_json` and injected
  with `LookCatalog.use` by `tests/look_render_test.gd` and `tests/look_catalog_test.gd`; it
  is never copied over `data/looks.json`. Edit it with the tests that pin its values.
