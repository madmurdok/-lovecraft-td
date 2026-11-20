# LT-102: portability boundary, core (LT-96 S6)

Design slice S1. Source: `docs/design/LT-96-extensibility-synthesis.md` §4 "S6", §5 "Engine
portability", owner decision D8 "Минимум A + трасса, B по поводу (Recommended)".
Base: `780ea9e` (release-0.8.0). Line numbers below are at that commit; `sim/config.gd` changes
under LT-100 first, so S2 re-outlines it by symbol after the rebase.

Scope: IO and `JSON.parse` out of `sim/` (`GameConfig.from_dicts` + a loader outside `sim/`);
the 8 RNG draw sites call a `SimRng` API; `ENGINE_ALLOWLIST` loses `FileAccess`, `JSON`,
`RegEx`; a written float32/float64 contract; an engine-neutral trace next to the golden digests.
Out of scope: B's event payload schema, read-only snapshot, owned PCG32.

## 1. Decisions

### D-1. SimRng API: option A, the two Godot primitives per stream (Recommended)

```gdscript
# sim/core/sim_rng.gd
func randf(s: Stream) -> float                              # stream(s).randf(); one draw
func randi_range(s: Stream, from: int, to: int) -> int      # stream(s).randi_range(from, to)
func stream(s: Stream) -> RandomNumberGenerator             # kept: inspection only (seed, state)
```

`SimContext` forwards the two draws (`_ctx.randf(stream)`, `_ctx.randi_range(stream, a, b)`) and
exposes `sim_rng() -> SimRng` so `Simulation` can hand it to `HallucinationSystem.tick`.
`SimContext.rng(stream)` and `Simulation.rng(stream)` stay as inspection accessors: 20 test files
and `tests/golden_runs.gd:145` read `.state` / `.seed` or draw on fresh copies through them. A new
guard (§4) stops sim code from drawing through them.

| | A: `randf` / `randi_range` | B: `chance` / `pick` |
|---|---|---|
| Covers the 8 sites | all 8, one-to-one | 5 of 8; sites 2 (pack count, `randi_range(min, max)`), 3 (weighted loot, `randf() * total`) and 8 (3-way astray threshold) still need a raw primitive or 2 more helpers |
| Draw risk | none: each call is the same Godot call on the same generator | low but real: `chance(p)` must keep "no draw at p <= 0" in the caller, `pick(n)` must equal `randi_range(0, n - 1)` |
| Port value | the port implements exactly 2 Godot functions (`randf`, `randi_range`) and the call sites translate line by line | intent visible at the call site; the port still implements the same 2 primitives underneath |
| Cost | ~25 lines | ~40 lines + per-helper equivalence tests |

Benefit of A: mechanical, golden byte-identical by construction, smallest port surface.
Risk of A: call sites keep spelling the idiom (`randf() < chance`) instead of naming it; B's
helpers can be added on top later without touching the stream order.

### D-2. `GameConfig.from_dicts` and a loader outside `sim/`

```gdscript
# sim/config.gd
## Builds and validates a config from already-parsed file roots. Never returns a partial
## config (as load_from_dir did). `roots`: file name ("towers.json") -> parsed root, any
## Variant (a Dictionary to be valid); a file absent from `roots` was not read.
## `read_errors`: file name -> Array of [path, message] recorded while reading that file
## (not found, unreadable, bad JSON, duplicate keys); they lead that file's errors, so the
## per-file error order is the one load_from_dir produced. A required section with no root
## and no read error gets "<file>: missing". The config may keep references to
## sub-dictionaries of `roots` (e.g. pack traits): the caller hands them over.
static func from_dicts(roots: Dictionary, read_errors: Dictionary = {}) -> ConfigLoadResult
```

```gdscript
# io/config_loader.gd (new top-level dir, outside sim/ and outside the presentation scans)
class_name ConfigLoader
extends RefCounted
const DEFAULT_DIR := "res://data"                     # moved from GameConfig
static func load_dir(dir: String = DEFAULT_DIR) -> ConfigLoadResult   # reads, then from_dicts
static func find_duplicate_keys(text: String) -> Array[String]       # moved verbatim
static func _frame_path(stack: Array[Dictionary]) -> String          # moved verbatim
static func _read(dir: String, file: String, roots: Dictionary, read_errors: Dictionary) -> void
```

`_read` is today's `GameConfig._read_json` (config.gd:136-158) with its outcomes redirected:
not found / cannot read / invalid JSON -> a read error, no root; parsed -> `roots[file] = data`,
then, only when `data` is a Dictionary (as today), each duplicate key -> a read error
`[dup_path, "duplicate key"]`. "root must be an object" moves into `from_dicts` (a port that
feeds dictionaries needs that check too); it ran before the duplicate scan and returned early,
and the "only scan a Dictionary root" rule keeps that outcome. Messages stay byte-identical,
including `"file not found (%s)" % full` (the loader knows the path).

Who calls the loader: every current `GameConfig.load_from_dir` caller, 64 sites in 49 files
(`grep -rn "GameConfig.load_from_dir" --include="*.gd" tests scenes tools`), all with one role
(load a config directory): `scenes/main.gd:26`, `tools/bot_runs.gd:137` (2 calls), 
`tests/config_test_base.gd:58`, `tests/sim_test_base.gd:19`, `tests/sim_no_tree_loop.gd:15`,
`tests/golden_runs.gd:81` and 43 other test files. `GameConfig.load_from_dir` is deleted, not
kept as a forwarder: a forwarder in `sim/` would name `ConfigLoader`, which the boundary test
rejects. The two doc comments that name it (`sim/config_load_result.gd:3`,
`sim/defs/enemy_def.gd:15`) are reworded. `tests/config_duplicate_keys_test.gd` calls
`ConfigLoader.find_duplicate_keys`.

Why `io/`: `tools/` is a presentation dir in the boundary scans and holds dev tools; `scenes/`
is for nodes. The export filter only excludes `tests/*` and `addons/gdUnit4/*`, so `io/`
ships to Web.

**Composition with LT-100 (assumed shape, from LT-96 S4: "load sections from a
`[file, parser, required]` list; cross-checks after all sections").** `from_dicts` is that
loop with the source swapped: where LT-100 calls `_read_json(dir, r)` for a section,
`from_dicts` replays `read_errors[file]` into `r` and takes `roots.get(file)`. An optional
section (required = false) with no root and no read error is "off", no error. The loader gets
the file list from the same table through one accessor, `GameConfig.section_files() -> Array`
of `[file, required]`; it never keeps a second hard-coded file list. The loader reads an
optional section's file only when it exists, a required one always. If LT-100 lands another
shape, S2 keeps these two rules (one table, from_dicts = the table loop) and adapts names. Cross
check placement and error order are LT-100's; S2 preserves whatever LT-100 pins.

### D-3. `RegEx` out of `ConfigReader`

`ConfigReader._id_regex` (config_reader.gd:14) becomes a character loop: first char `a`-`z`,
the rest `a`-`z`, `0`-`9`, `_`, non-empty. `ID_PATTERN` stays as the text of the error message.
Probe on Godot 4.7.2: the PCRE pattern `^[a-z][a-z0-9_]*$` accepts `"abc\n"` (`$` matches before
a final newline); the loop rejects it. This is a deliberate, stricter acceptance change for a
case no data file has; pinned by a test (§5 B8).

### D-4. Trace: JSON Lines from the golden runs' recorder

Generated in the same pass as the digests (no extra run time), written by `golden-regen.sh`,
checked by `golden_replay_test`. `tests/fixtures/golden_digests.json` stays byte-identical:
the trace is separate files. Coverage is owner question Q1; the recommended default below.

## 2. The 8 draw sites

From `grep -rn "randf\|randi\|rng" sim/` (and `.rng(` in `sim/core/simulation.gd:60`,
`sim_context.gd:20`, the accessors).

| # | Site | Stream | Today | After (A) |
|---|---|---|---|---|
| 1 | `sim/core/hallucination_system.gd:42` | SANITY | `sim.rng(S).randi_range(0, n - 1)` | `rng.randi_range(S, 0, n - 1)` (`rng: SimRng` new `tick` param) |
| 2 | `sim/core/systems/spawn_system.gd:54` | SPAWN or SANITY | `_ctx.rng(stream).randi_range(min, max)` | `_ctx.randi_range(stream, min, max)` |
| 3 | `sim/core/systems/economy_system.gd:142` | LOOT or GHOST_LOOT | `_ctx.rng(stream).randf() * total` | `_ctx.randf(stream) * total` |
| 4 | `sim/core/systems/combat_system.gd:262` | MADNESS | `pool[_ctx.rng(M).randi_range(0, n - 1)]` | `pool[_ctx.randi_range(M, 0, n - 1)]` |
| 5 | `sim/core/systems/combat_system.gd:358-360` | MADNESS | `var stream := _ctx.rng(M)` then `stream.randi_range(0, n - 1)` in a loop | the local goes; `_ctx.randi_range(M, 0, pool.size() - 1)` in the loop |
| 6 | `sim/core/systems/combat_system.gd:686` (`_roll_miss`) | COMBAT | `randf() < chance` | `_ctx.randf(C) < chance` |
| 7 | `sim/core/systems/combat_system.gd:693` (`_roll_crit`) | CRIT | `randf() < chance` | `_ctx.randf(CRIT) < chance` |
| 8 | `sim/core/systems/combat_system.gd:699` (`_roll_astray`) | MADNESS | `var r := ...randf()` | `var r := _ctx.randf(M)` |

No other draw in `sim/`: `SIM_FORBIDDEN_CODE` already bans the global `randf(` family, and
`RandomNumberGenerator` appears only in `sim_rng.gd`, `sim_context.gd:20`, `simulation.gd:60`.
Every "no draw" guard stays in the caller (`chance <= 0` returns before the draw, sites 6-7).

## 3. Allowlist diff (`tests/sim_boundary_test.gd:23-27`)

```diff
 const ENGINE_ALLOWLIST := [
-	"Array", "Callable", "Dictionary", "FileAccess", "JSON", "PackedByteArray", "PackedInt64Array",
-	"PackedStringArray", "PackedVector2Array", "RandomNumberGenerator", "Rect2",
-	"RefCounted", "RegEx", "String", "Variant", "Vector2", "Vector2i",
+	"Array", "Callable", "Dictionary", "PackedByteArray", "PackedInt64Array",
+	"PackedStringArray", "PackedVector2Array", "RandomNumberGenerator", "Rect2",
+	"RefCounted", "String", "Variant", "Vector2", "Vector2i",
 ]
```

The comment above it gains: "LT-102: FileAccess, JSON, RegEx dropped (IO lives in
io/config_loader.gd)". `test_the_engine_allowlist_is_not_stale` forces the drop once the code
moves (a stale entry fails it), and the two "names only allowlisted types" tests then reject any
return of these names. `JSON` in comments is blanked by the scanner and does not count.
`FileAccess`, `OK`, `error_string` leave `sim/` with `_read_json`.

New guard in the same suite, `test_sim_draws_only_through_the_sim_rng_api`: on code lines of
every `sim/` file except the homes (`sim/core/sim_rng.gd`, `sim/core/systems/sim_context.gd`,
`sim/core/simulation.gd`), no match of `\.(?:rng|stream)\s*\(` and no `RandomNumberGenerator`.
Planted probes: must hit `_ctx.rng(SimRng.Stream.A).randf()`, `var g := _ctx.rng(s)`,
`sim.rng(s).randi_range(0, 1)`, `_rng.stream(s)`; must miss `_ctx.randf(SimRng.Stream.A)`,
`rng.randi_range(s, 0, 1)`, `# _ctx.rng(s)`, `"sim.rng("`.

## 4. Float contract (text for the `sim/core/sim_time.gd` header)

S2 pastes this below the existing header lines; `sim_rng.gd` gets a one-line pointer to it.
Each item was probed on Godot 4.7.2 (2026-11-20, `scratchpad/probe*.gd`), see §6.

```
## Numeric contract (LT-102; what a port must reproduce bit for bit):
##  - `float` is IEEE 754 binary64; every scalar computation in sim/ is binary64.
##  - `int` is int64. Path progress is integer distance units (UNITS_PER_CELL per cell), so
##    movement is exact; floats meet it only through roundi.
##  - Vector2 / PackedVector2Array components are binary32 (no double-precision build).
##    Storing rounds to nearest-even binary32; reading widens exactly. Positions (towers,
##    enemies via SimRoute, allies, blasts, tokens) are binary32 storage.
##  - Vector2 methods compute in binary32: SimRoute.position_at and AllySystem.ally_position
##    use Vector2.lerp (weight rounded to binary32). Rule and distance checks widen the
##    components first (`float(p.x) - c.x`) and compute in binary64 (LightRules,
##    GridTopology.distance, AllySystem._dist2, CombatSystem._line_*). The beam direction is
##    two binary64 scalars on purpose (SimState.beam_dx/dy).
##  - sqrt is the only non-trivial math (correctly rounded); no trig (guard G11).
##  - roundi rounds halves away from zero (2.5 -> 3, -2.5 -> -3); floori / floorf as usual.
##  - RNG (SimRng): one Godot PCG32 RandomNumberGenerator per stream, seed
##    run_seed * 16 + stream. randf() is a binary32 value widened to binary64;
##    randi_range(a, a) returns a and draws nothing.
##  - Config numbers arrive as JSON binary64; int fields are exact up to 2^53 (ConfigReader).
```

## 5. Trace format

**Files** (Q1 default): `tests/fixtures/golden_trace/manifest.json` for every golden run, plus
full text `tests/fixtures/golden_trace/<run>.jsonl` (run name with `/` -> `_`) for the runs in
`GoldenRuns.TRACE_FULL_RUNS := ["no_tree_loop/5", "frame_path/1234"]` (470 and 100 events).
All 12 runs total 16 409 events, estimated 1.5-2.5 MB as text; S3 measures the real size and
reports it before committing.

**Lines** (one JSON object per line, LF, keys sorted, written by
`JSON.stringify(neutral(v), "", true, true)`):

```
{"data_dir":"res://tests/fixtures/golden_data","format":"lovecraft-td-trace","run":"no_tree_loop/5","version":1}
{"data":{...},"id":12,"tick":30,"type":"SPAWNED"}
...
{"final":{"command_log":6,"gold":10,"lighthouse_hp":0,"next_id":64,"outcome":2,"rng":["<int64>",...],"sanity":85.0,"tick":8073,"towers":5,"wave":3}}
```

- Header: run name, format, version, data dir. Events: one per drained event, in drain order;
  `type` is the `SimEvent.Type` key name. Final: the `SimNoTreeLoop.digest` scalars plus the 7
  stream states (decimal strings of Godot's signed int64 `state`, in `SimRng.Stream` order).
- `neutral(v)`: float -> JSON number, shortest round-trip binary64 (`full_precision = true`;
  probe: `0.1 + 0.2` -> `0.30000000000000004`, parses back equal); int -> number (asserted
  `|v| <= 2^53`, else the run fails); bool, null as JSON; String / StringName -> string;
  Vector2 -> `[x, y]` (binary32 widened); Vector2i -> `[x, y]`; Array and Packed*Array -> array;
  Dictionary -> object, String keys only (asserted); NaN / INF -> assertion failure (events
  must not carry them). Without `neutral`, `JSON.stringify` writes a Vector2 as the string
  `"(0.1, 2.0)"` (probe), which is Godot text.
- Comparison rule for a port: compare parsed values (numbers as binary64), not text. Godot
  writes `1.0` and `1` for float and int; a port need not.
- Manifest: `{"_generated_by": ..., "format": "lovecraft-td-trace", "version": 1, "runs":
  {"<run>": {"lines": n, "sha256": "<hex of the UTF-8 text incl. header and final>",
  "file": "<run>.jsonl" | null}}}`, keys sorted.

**Producing it.** `GoldenRuns.Recorder` gets a run name (`Recorder.new(name)`; its 3 callers
`bot_run`, `no_tree_run`, `frame_run` gain a `run_name` param, only `compute_all` calls them)
and a second `HashingContext` over trace lines; it keeps the text only for `TRACE_FULL_RUNS`.
`result()` appends the final line and adds `"trace": {"lines", "sha256", "text"}` to the run.

**Writing it.** `tools/golden/regen.gd` pops `"trace"` from every run before writing
`golden_digests.json` (so that file stays byte-identical), deletes `*.jsonl` in
`golden_trace/`, writes the manifest and the full-text files. `scripts/golden-regen.sh` keeps its
logic; its header comment names both outputs. `tests/fixtures/README.md` gets a "Golden trace"
section (format, comparison rule, regenerate together with the digests, never by hand).

**Checking it.** In `test_golden_runs_match_the_pinned_digests` (one `compute_all`, no extra run
time): after the digest diff, for every run compare `lines` and `sha256` with the manifest,
and for full-text runs compare the file text with the computed text, naming the first differing
line number and both lines. A new fast test, `test_trace_lines_are_engine_neutral`, plays
`no_tree_run` only and checks every line parses as a JSON object, no string value looks like
Godot vector text (`^\(.*, .*\)$`), each float parses back equal, and `rng` holds strings.

## 6. Edit map

### S2: IO out, SimRng, allowlist (starts after LT-100 merges; re-outline `config.gd` first)

Change:
- `sim/config.gd`: `load_from_dir` (25-93) -> `from_dicts(roots, read_errors)` per D-2, root type
  check moved in from `_read_json`; delete `_read_json` (136-158), `find_duplicate_keys`
  (164-201), `_frame_path` (204-213), `DEFAULT_DIR` (6); add `section_files()` if LT-100 did not
  expose its table; header comment (3) says "built from parsed JSON roots".
- `io/config_loader.gd` (new, + `.uid` from the import): `load_dir`, `_read`,
  `find_duplicate_keys`, `_frame_path`.
- `sim/config_reader.gd`: drop `_id_regex` (14); `check_id` (66-70) uses a char loop (D-3).
- `sim/core/sim_rng.gd`: add `randf`, `randi_range` (after `stream`, 23-24); header gets the
  pointer to the contract.
- `sim/core/systems/sim_context.gd`: add `randf`, `randi_range`, `sim_rng` next to `rng` (20-21);
  `rng`'s doc says "inspection only; draws go through randf / randi_range".
- `sim/core/simulation.gd`: `rng` (60-61) doc as above; line 110 passes `_ctx.sim_rng()` to
  `_hallucinations.tick`.
- `sim/core/hallucination_system.gd`: `tick` (24-45) gains `rng: SimRng`, site 1.
- `sim/core/systems/spawn_system.gd:54`, `economy_system.gd:142`,
  `combat_system.gd:262, 358-360, 686, 693, 699`: sites 2-8.
- `sim/core/sim_time.gd`: header contract (§4).
- `tests/sim_boundary_test.gd`: `ENGINE_ALLOWLIST` (21-27), new draw guard after
  `test_sim_uses_no_forbidden_tokens` (794-807).
- Caller sweep `GameConfig.load_from_dir(` -> `ConfigLoader.load_dir(` (64 sites, 49 files, §D-2);
  `tests/config_duplicate_keys_test.gd:6-10` (`_dups`); comments in
  `sim/config_load_result.gd:3`, `sim/defs/enemy_def.gd:15`.
- New tests (B2-B4, B7-B8): extend `tests/config_reject_test.gd` and add
  `tests/config_from_dicts_test.gd`, `tests/sim_rng_test.gd` (or extend `sim_determinism_test`).

Read for context: `tests/config_test_base.gd` `load_edited` (55-60), `has_error` (73-80);
`tests/config_reject_test.gd` 25-52 and `test_errors_from_all_files_are_collected_in_file_order`
(513-528); `tests/sim_boundary_test.gd` `_find` (137), `_code_lines` (128),
`test_the_engine_allowlist_is_not_stale` (769-781); `tests/architecture_guard_test.gd`
`test_g4a_systems_are_internal` (573-600: `_ctx.rng(...)` is a pinned must-miss there; keep it
valid); `tests/sim_no_tree_loop.gd` `digest` (48-52).

### S3: trace (after S2)

Change:
- `tests/golden_runs.gd`: `Recorder` (44-77), `bot_run` (184-188), `no_tree_run` (191-196),
  `frame_run` (199-246, its `Recorder.new` at 230), `compute_all` (267-286); new consts
  `TRACE_DIR := "res://tests/fixtures/golden_trace"`, `TRACE_FULL_RUNS`; new statics `neutral`,
  `trace_event_line`, `trace_header`, `trace_final`, `trace_file_name`.
- `tools/golden/regen.gd` `_main` (11-36).
- `tests/golden_replay_test.gd`: `test_golden_runs_match_the_pinned_digests` (17-31), new
  `test_trace_lines_are_engine_neutral`.
- `scripts/golden-regen.sh` header (1-6); `tests/fixtures/README.md`.
- New fixtures: `tests/fixtures/golden_trace/manifest.json` + full-text `.jsonl` files, from
  `scripts/golden-regen.sh` only; `git diff tests/fixtures/golden_digests.json` must be empty.

Read for context: `GoldenRuns.canon` (97-133), `state_text` (135-161), `diff` (289-),
`SimEvent` fields (`sim/core/sim_event.gd:27-33`).

## 7. Behaviours tests must pin

S2:
- B1 Golden digests unchanged without regeneration (existing `golden_replay_test`).
- B2 `from_dicts` on roots parsed in memory equals `ConfigLoader.load_dir` on the same files
  (same `SimNoTreeLoop` digest on both configs).
- B3 Per-file error order survives the split: read errors lead their file's errors, files in
  table order (existing order test; new: a duplicate key and a parse error in one file, the
  duplicate first).
- B4 `from_dicts`: non-dict root -> "root must be an object"; required section absent with no
  read error -> "missing"; optional section absent -> no error, block off.
- B5 Allowlist without `FileAccess`, `JSON`, `RegEx` (existing names + not-stale tests).
- B6 Draw guard: planted probes hit and miss as in §3.
- B7 `SimRng.randf` / `randi_range` equal a fresh generator with the same seed;
  `randi_range(s, a, a)` leaves the stream state unchanged.
- B8 ID check: `a_1` accepted; `Bad-Id`, `1tower`, `é`, `""`, `"abc\n"` rejected.

S3:
- B9 Recomputed trace equals the pinned manifest (lines, sha256) and full-text files.
- B10 Trace lines are engine-neutral (§5 "Checking it").
- B11 Regenerating leaves `golden_digests.json` byte-identical (verify step).

Controls (one per behaviour, 7): re-add a `FileAccess` call in `sim/config.gd` (B5);
revert site 6 to `_ctx.rng(C).randf()` (B6); in `from_dicts` replay read errors after parsing
(B3); accept a trailing newline in the id loop (B8); make `randi_range(s, a, a)` draw (B7);
stringify without `full_precision` (B9); skip `neutral` for Vector2 (B10).

## 8. Must confirm

1. LT-100's merged shape of `sim/config.gd` (table name, parser signature, cross-check placement,
   pinned error order); adapt D-2 names, keep its two rules.
2. Caller count of `GameConfig.load_from_dir` after LT-100 merges (64 sites / 49 files at
   `780ea9e`), each a "load a config directory" caller before the sweep.
3. Which defs keep references into the parsed dictionaries (`EnemyDef.traits["pack"]` read at
   `spawn_system.gd:53`); `from_dicts` doc says the caller hands them over.
4. Every event `data` has String keys and finite floats (B10 asserts it; if not, the trace
   needs an encoding, decide in S3).
5. Real trace size from S3 before choosing Q1's final coverage.
6. `.uid` files for `io/config_loader.gd` and new test files are generated and committed.
7. Confirmed by probe on Godot 4.7.2.stable (no action): `JSON.stringify(v, "", true, true)`
   gives shortest round-trip floats; `JSON.stringify(Vector2)` gives `"(0.1, 2.0)"`;
   `randi_range(3, 3)` draws nothing; 10 000 `randf()` values are all binary32; `Vector2.lerp`
   result is binary32 (`0.29999998211861` vs binary64 `0.3`); `roundi(2.5) = 3`,
   `roundi(-2.5) = -3`; `RegEx("^[a-z][a-z0-9_]*$")` accepts `"abc\n"`.

## 9. Owner questions

**Q1. Trace coverage**
- **Full text for the 2 short runs + sha256 manifest for all 12 (Recommended).** Benefit: small
  diff on regen (~60-80 KB of text); every run still pinned; a port gets a readable oracle and
  can regenerate the rest from Godot at the same commit. Risk: a mismatch on a bot run shows
  only "sha differs" until someone regenerates its text locally.
- Full text for all 12 runs. Benefit: complete oracle in the repo. Risk: ~2 MB of text, rewritten
  on every approved behaviour change.
- Short runs only, no manifest. Benefit: smallest. Risk: bot runs (late waves, madness, relics)
  not covered by the trace.

**Q2. SimRng API shape** (LT-96 S6 left A vs B open; D8 did not pick)
- **A: `randf` / `randi_range` per stream (Recommended).** Benefit: one-to-one with today's
  calls, no draw risk, 2-function port surface. Risk: call sites keep the idiom, no named intent.
- B: `chance` / `pick` helpers. Benefit: intent named at the call site. Risk: covers 5 of 8 sites,
  still needs the primitives; each helper needs an equivalence test.

### Owner decisions (2026-11-20)

- Design: "Утверждаю (Recommended)".
- Q1 trace coverage: "2 коротких полностью + sha всех 12 (Recommended)".
- Q2 SimRng API: "A: randf / randi_range (Recommended)".
