# LT-101: bot strategies as data (S5)

Scope: block S5 of `docs/design/LT-96-extensibility-synthesis.md` (§4, Tier 1); no owner decision
D1..D11 touches S5. Base: `release-0.8.0` at `780ea9e`, worktree branch
`refactor/LT-101-bot-strategies-data`. Line numbers below are at `780ea9e`.

Goal: the bot's per-strategy choices (build order, L3 branch picks, cap floor, flags) become rows
in one data file read by one interpreter; the arms with real control flow stay code as named
policies. Acceptance: bot RUN lines identical on 20 seeds; golden digests unchanged; a new
tower enters the balance lab (`tools/balance/`) by a data edit only.

## 1. What exists today

| Piece | Where | Per strategy? |
|---|---|---|
| Strategy list `STRATEGIES` (10 names, order = play order, `light` last) | `tools/bot_runs.gd:76-77` | list |
| Strategy descriptions (doc comment) | `tools/bot_runs.gd:16-38` | yes |
| Build orders: `match strat` in `order()` | `tools/bot/bot_strategies.gd:46-72` | yes |
| `MIXED_ORDER`, `LIGHT_ORDER` | `bot_strategies.gd:15-18` | yes |
| `BRANCH_PICK` (strategy -> tower -> `a`/`b`) | `bot_strategies.gd:22-33` | yes |
| `CAP_FLOOR` (`occult` 30, `mixed` 60), `cap_allows()` | `bot_strategies.gd:13, 77-80` | yes |
| `OCCULT_MAX_RIFLEMEN` (3), occult fallback in `order()` | `bot_strategies.gd:14, 60-66` | occult |
| `buy_sanity()` for occult/mixed | `bot_strategies.gd:87-88` | flag |
| mixed "skip a blocked occult item" | `bot_strategies.gd:113-116` | mixed |
| occult "blocked, out of riflemen: upgrade else save" | `bot_strategies.gd:117-123` | occult |
| `BUILD_FIRST` 5, `FLARE_MIN_LIVE` 4, oil top-up, lighthouse rule, `next_upgrade`, `night_flare` | `bot_strategies.gd:11, 19, 95-111, 137-195` | shared by all |
| Placement scoring, `CAST_WEIGHT` | `tools/bot/bot_placement.gd` | shared by all |
| Run cap `MAX_TICKS := 30 * 60 * 30` | `tools/bot_runs.gd:85`, loop `:198` | shared |

Readers of the strategy tables (grep, see §12):

- `STRATEGIES`: `tools/bot_runs.gd:93, 128-132` (CLI); `tools/balance/balance.py:48-54` (regex on
  the `.gd` source, used at `:370`); `tests/golden_runs.gd:179-180` (`get_script_constant_map()`);
  `tests/bot_upgrade_test.gd:71-73` (`_strategy_names`, used at `:996`) and `:926`;
  `tools/balance/tests/test_balance.py:199-212`; `tools/balance/README.md:25`.
- `BRANCH_PICK`: `bot_strategies.gd:173`; `tests/bot_upgrade_test.gd:249, 721, 852, 1005`.
- `CAP_FLOOR`: `bot_strategies.gd:78-80`; `tests/bot_upgrade_test.gd:297`.
- `MIXED_ORDER`: `bot_strategies.gd:68`; `tests/bot_upgrade_test.gd:485`.
- `LIGHT_ORDER`: `bot_strategies.gd:70` only.
- `OCCULT_MAX_RIFLEMEN`: `bot_strategies.gd:65`; `tests/bot_upgrade_test.gd:441`.
- `order()` direct calls: `tests/bot_upgrade_test.gd:198, 212, 226, 442-449, 726, 806` (with
  `sim = null`, strategy `mundane`), `856, 1000`.
- `MAX_TICKS`: `tools/bot_runs.gd:198`; `tests/golden_runs.gd:18, 166, 169` (source-text cut).

Every build order is a cycle: `X if i % 3 == 2 else "rifleman"` is the cycle
`[rifleman, rifleman, X]`; madness (`_` arm) is `[necronomicon_reader, elder_sign]`; occult is a
one-item prefix `[rifleman]` then the cycle `[elder_sign, necronomicon_reader]` indexed by
`i - 1` (`i % 2 == 1` -> elder_sign for `i >= 1`).

## 2. Decision: JSON file, not a const table

**Recommendation: `tools/bot/strategies.json`**, loaded by a new `tools/bot/strategy_table.gd`.

| | JSON `tools/bot/strategies.json` (recommended) | const Dictionary in `bot_strategies.gd` |
|---|---|---|
| Lab entry by data edit | yes: `balance.py` reads it with `json.load`, no regex on GDScript | the "data edit" is a `.gd` edit; `balance.py` must regex a nested dict literal (fragile) |
| Lab variants can vary strategies later | cheap (same deep-merge patcher, §10 Q1) | no |
| Readers in GDScript | via the loader (`StrategyTable.default()`) | `get_script_constant_map()`, as today |
| Type safety | needs a validator; JSON numbers parse as float (cast `fallback_max` to int) | compile-time |
| Failure mode | bad file -> loader errors, bot quits 1 before any run | parse error of the script |
| Files | +2 (json, loader) | 0 |

Benefit: one source for the bot, the lab and the golden harness; a non-programmer edit; the lab
stops parsing GDScript. Risk: a loader plus validator (~100 lines) and a test suite for it; a
float/int slip in the interpreter could change an order index (pinned by the order-equivalence
test, §8 #2). Not `data/`: it is not game config; `GameConfig.load_from_dir` and the golden
fixture `tests/fixtures/golden_data/` stay untouched, and one strategies file serves both
`data/` and the golden config.

Top level is `{"strategies": [row, ...]}`: an array, so play order (and `light` last) is
explicit and does not depend on dictionary key order.

## 3. Row schema

| Field | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `name` | string | yes | | strategy name (RUN `"strategy"`, `--strategies=`, golden key `bot/<name>/<seed>`); unique |
| `about` | string | no | `""` | one-line description (replaces `bot_runs.gd:16-38`) |
| `prefix` | array of tower ids | no | `[]` | builds `0 .. prefix.size()-1`, played once |
| `cycle` | non-empty array of tower ids | yes | | build `i >= prefix.size()` is `cycle[(i - prefix.size()) % cycle.size()]` |
| `branches` | object tower id -> `"a"`/`"b"` | no | `{}` | L3 branch picks (was `BRANCH_PICK[name]`); a tower not listed stays at L2; `--branch=` still wins |
| `cap_floor` | number | no | absent = no cap guard | lowest `sanity_cap` an occult build or upgrade may leave (was `CAP_FLOOR`) |
| `on_blocked` | `"skip"` or `"fallback"` | iff `cap_floor` | | named policy for a blocked occult build (§5) |
| `fallback` | tower id | iff `on_blocked == "fallback"` | | tower built instead of a blocked cycle item |
| `fallback_max` | integer >= 0 | iff `on_blocked == "fallback"` | | per run, while `built[fallback] < fallback_max` (was `OCCULT_MAX_RIFLEMEN`) |
| `buy_sanity` | bool | no | `false` | call `sim.buy_sanity()` on every `act()` (was `strat in [occult, mixed]`) |

Validation (loader, error strings name the row index and field; all errors collected):

1. File parses as a JSON object with exactly the key `strategies`, an array of objects.
2. No duplicate JSON key anywhere (reuse `GameConfig.find_duplicate_keys(text)`, `sim/config.gd:164`).
3. Each row: no unknown key; `name` a non-empty string, unique; types as in the table.
4. `branches` values in `["a", "b"]`; `fallback_max` an integral number >= 0 (stored as `int`).
5. `cap_floor` present <-> `on_blocked` present; `fallback`/`fallback_max` present <->
   `on_blocked == "fallback"`.
6. Against a `GameConfig` (`check_towers(cfg)`, run by the harness after the config loads):
   every tower id in `prefix`, `cycle`, `branches`, `fallback` exists in `cfg.towers`;
   `fallback` is not `kind == "occult"`; a `"skip"` row's `cycle` has at least one non-occult
   item (else the skip loop in `act()` never ends).

Rows are normalized on load (every key present, defaults filled, `cap_floor` float or `null`,
`fallback_max` int) and made read-only (`make_read_only()` on each row and its nested arrays and
dictionaries), so a test or `branch_override` cannot mutate the shared table.

### The current strategies (the whole file the code slice writes)

```json
{
  "strategies": [
    {"name": "mundane", "about": "rifleman, rifleman, harpooner repeated; never builds occult",
     "cycle": ["rifleman", "rifleman", "harpooner"],
     "branches": {"rifleman": "a", "harpooner": "a"}},
    {"name": "occult",
     "about": "rifleman, then elder_sign / necronomicon_reader alternating; cap guard 30, a blocked item becomes a rifleman (3 per run), then upgrade-or-save; buys sanity",
     "prefix": ["rifleman"],
     "cycle": ["elder_sign", "necronomicon_reader"],
     "branches": {"rifleman": "a", "elder_sign": "a", "necronomicon_reader": "a"},
     "cap_floor": 30, "on_blocked": "fallback", "fallback": "rifleman", "fallback_max": 3,
     "buy_sanity": true},
    {"name": "mixed",
     "about": "rifleman, rifleman, elder_sign, rifleman, harpooner, necronomicon_reader repeated; cap guard 60, a blocked occult item is skipped; buys sanity",
     "cycle": ["rifleman", "rifleman", "elder_sign", "rifleman", "harpooner", "necronomicon_reader"],
     "branches": {"rifleman": "a", "harpooner": "a", "elder_sign": "a", "necronomicon_reader": "a"},
     "cap_floor": 60, "on_blocked": "skip", "buy_sanity": true},
    {"name": "madness", "about": "necronomicon_reader / elder_sign alternating, no guard, never buys sanity: builds past cap 0",
     "cycle": ["necronomicon_reader", "elder_sign"],
     "branches": {"elder_sign": "b", "necronomicon_reader": "b"}},
    {"name": "demolition", "about": "mundane with the Dynamite crew in the harpooner's slot (LT-47)",
     "cycle": ["rifleman", "rifleman", "dynamite_crew"],
     "branches": {"rifleman": "a", "dynamite_crew": "a"}},
    {"name": "battery", "about": "the same with the Coast battery (LT-48)",
     "cycle": ["rifleman", "rifleman", "coast_battery"],
     "branches": {"rifleman": "a", "coast_battery": "a"}},
    {"name": "resonator", "about": "the same with the Tillinghast Resonator (LT-50); no cap guard",
     "cycle": ["rifleman", "rifleman", "resonator"],
     "branches": {"rifleman": "a", "resonator": "a"}},
    {"name": "gate", "about": "the same with the Silver Key Gate (LT-51); no cap guard",
     "cycle": ["rifleman", "rifleman", "silver_key"],
     "branches": {"rifleman": "a", "silver_key": "a"}},
    {"name": "circle", "about": "the same with the Summoning Circle (LT-52); no cap guard",
     "cycle": ["rifleman", "rifleman", "summoning_circle"],
     "branches": {"rifleman": "a", "summoning_circle": "a"}},
    {"name": "light", "about": "builds the Searchlight third (LT-70 §6)",
     "cycle": ["rifleman", "rifleman", "searchlight", "harpooner", "rifleman"],
     "branches": {"rifleman": "a", "harpooner": "a", "searchlight": "b"}}
  ]
}
```

Fully worked conversions (old code -> row), checked index by index:

- **mundane** `order`: `"harpooner" if i % 3 == 2 else "rifleman"` -> `cycle[i % 3]` with
  `cycle = [rifleman, rifleman, harpooner]`: i=0 R, 1 R, 2 H, 3 R, 4 R, 5 H. Same. `BRANCH_PICK`
  row copied. No `CAP_FLOOR`, no `buy_sanity`. demolition/battery/resonator/gate/circle are the
  same shape with their tower in slot 2.
- **occult** `order`: i=0 -> rifleman (= `prefix[0]`); i>=1 -> `elder_sign` if `i % 2 == 1` else
  `necronomicon_reader` = `cycle[(i - 1) % 2]` with `cycle = [elder_sign, necronomicon_reader]`:
  i=1 ES, 2 NR, 3 ES, 4 NR. Same. Guard on the cycle item `d` (always occult):
  `cap_allows(sim, "occult", d.levels[0].sanity_reserve)` with floor 30; blocked -> `"rifleman"`
  if `built["rifleman"] < 3` else `""` = `fallback` / `fallback_max`. `buy_sanity: true`.
- **mixed** `order`: `MIXED_ORDER[i % 6]` = `cycle`. The act-time skip of a blocked occult item =
  `on_blocked: "skip"`, floor 60. `buy_sanity: true`.
- **madness** (`_` arm): `"necronomicon_reader" if i % 2 == 0 else "elder_sign"` = cycle of 2.
- **light**: `LIGHT_ORDER[i % 5]` = `cycle`.

## 4. The interpreter

New `tools/bot/strategy_table.gd` (`extends RefCounted`, no `class_name`, preloaded like
`bot_placement.gd`):

```gdscript
const DEFAULT_PATH := "res://tools/bot/strategies.json"
var names: Array[String] = []   ## play order
var rows := {}                  ## name -> normalized read-only row
var errors: Array[String] = []
static func parse_text(text: String) -> StrategyTable   # validation 1-5
static func load_file(path := DEFAULT_PATH) -> StrategyTable
static func default() -> StrategyTable   # static var cache; load_file() once; asserts no errors
func check_towers(cfg: GameConfig) -> Array[String]   # validation 6
func row(name: String) -> Dictionary     # {} for an unknown name
```

`tools/bot/bot_strategies.gd` keeps its public API and signatures (`order`, `cap_allows`, `act`,
`lighthouse_next`, `bot_oil_target`, `night_flare`, `next_upgrade`) so the harness and most tests
do not change. New field `var table: StrategyTable = StrategyTable.default()` (a test may assign a
table from `parse_text`). Removed consts: `CAP_FLOOR`, `OCCULT_MAX_RIFLEMEN`, `MIXED_ORDER`,
`LIGHT_ORDER`, `BRANCH_PICK`. Kept consts: `FLARE_MIN_LIVE`, `BUILD_FIRST` (shared tunables, §10 Q2).

```gdscript
func order(strat, i, sim, built) -> String:
	var r := table.row(strat)
	assert(not r.is_empty(), "unknown strategy " + strat)
	if i < r.prefix.size():
		return r.prefix[i]
	var id: String = r.cycle[(i - r.prefix.size()) % r.cycle.size()]
	if r.on_blocked == "fallback" and cfg.towers[id].kind == "occult" \
			and not cap_allows(sim, strat, cfg.towers[id].levels[0].sanity_reserve):
		return r.fallback if built.get(r.fallback, 0) < r.fallback_max else ""
	return id

func cap_allows(sim, strat, delta) -> bool:
	var floor = table.row(strat).get("cap_floor")   # unknown strategy or null: no guard
	if floor == null or delta <= 0.0:
		return true
	return sim.state.sanity_cap - delta >= floor
```

`act()`: line 87 becomes `if table.row(strat).buy_sanity:`; line 113 becomes
`if table.row(strat).on_blocked == "skip" and cfg.towers[id].kind == "occult" and not cap_allows(...)`;
the `id == ""` arm (117-123) is unchanged (only a `"fallback"` row returns `""`).
`next_upgrade()` line 173: `var picks: Dictionary = table.row(strat).get("branches", {}).duplicate()`.

Notes on equivalence:
- `order("mundane", 5, null, {})` (`bot_upgrade_test.gd:806`) must not touch `sim`: the occult
  check short-circuits on `on_blocked != "fallback"`.
- The fallback guard applies to cycle items only (prefix items are returned before it), as the
  old `i == 0` arm. The skip guard in `act()` applies to whatever `order()` returns, as today.
- The old `kind == "occult"` filter is kept for both; for the fallback row it is new but moot
  (both cycle items are occult in `data/` and `golden_data/`).
- An unknown strategy name now asserts in `order()` (was: the madness arm). The harness only
  plays names from the table, so no run changes.

`tools/bot_runs.gd`:
- `_init`: after the config loads, `var table := StrategyTable.default()`; print `table.errors`
  and `table.check_towers(_cfg)` and `quit(1)` on any; `--strategies=` is checked against
  `table.names` and keeps table order (`table.names.filter(...)`). The arg parse (126-137) needs
  the names before the config loads: load the table first (no cfg needed), run `check_towers`
  after `_cfg` is set. Keep the existing message text `unknown strategy in --strategies:`.
- `const STRATEGIES` (76-77) removed; `var _strategies: Array = []` filled from the table.
- `_policy()` (303-314): unchanged (the policy uses `StrategyTable.default()`).

## 5. Named code policies (stay code) and why they cannot be rows

| Policy | Where | Why not a row |
|---|---|---|
| `on_blocked: "skip"` (mixed) | `act()` 113-116 | changes the order index inside the purchase loop (`idx += 1; continue`): control flow, not a value |
| `on_blocked: "fallback"` (occult) | `order()` fallback arm + `act()` 117-123 | three-way outcome (fallback tower / save / upgrade even below `BUILD_FIRST`) that reads per-run `built` counts and calls `next_upgrade`; only its tower and count are row params |
| cap guard `cap_allows` | 77-80 | a formula over live `sim.state.sanity_cap`; the floor is the row param `cap_floor` |
| wide-then-deep upgrade pick `next_upgrade` | 172-195 | cheapest-first over towers with ties, `has_pending`, override merge: shared by all strategies, no per-strategy variance today |
| lighthouse rule `lighthouse_next`, oil top-up, `night_flare` | 95-105, 137-165 | shared; read sim state; tunables `BUILD_FIRST`, `FLARE_MIN_LIVE` |
| placement `Placement.best_cell`, `cast_term` | `bot_placement.gd` | scoring over the grid and light; shared |

A new strategy that needs a new blocked-item behaviour adds a value to `on_blocked` (code); one
that only reorders or picks branches is a row.

## 6. `tests/golden_runs.gd` reader

- `strategies()` (179-180):
  `return (preload("res://tools/bot/strategy_table.gd").default().names as Array)`.
  Golden keys stay `bot/<name>/1000` in the same order, so `golden_digests.json` is unchanged.
- `make_bot()` (163-177): drop `BOT_MAX_TICKS` (18) and its source-text cut (166, 169); after
  `script.new()`, `if max_ticks > 0: bot.set("_max_ticks", max_ticks)`. The `_init` rename
  stays.

## 7. `MAX_TICKS` decision: derive from `waves.json`

Replace `const MAX_TICKS := 30 * 60 * 30` with `const TICKS_PER_WAVE := 6 * 60 * 30` and
`var _max_ticks := 0  ## 0: TICKS_PER_WAVE x the config's wave count`; the loop at 198 reads
`_tick_cap()` = `_max_ticks if _max_ticks > 0 else TICKS_PER_WAVE * _cfg.waves.waves.size()`.

- `data/waves.json` and `tests/fixtures/golden_data/waves.json` both have 5 waves -> 54000 ticks
  = the old cap exactly: RUN lines and golden digests unchanged. Balance patches cannot change
  the wave count (they only change existing values).
- Benefit: LT-72 (10 waves) is a data-only edit (P3 -1); golden loses a source-text cut.
- Risk: "6 minutes per wave" is an assumption; a 10-wave run caps at 60 min. Only runs that
  reach the cap (outcome `timeout`) are affected. Reversible: one const.

## 8. Behaviours tests must pin

1. Table names equal, in order, `["mundane", "occult", "mixed", "madness", "demolition",
   "battery", "resonator", "gate", "circle", "light"]` (literal in the test).
2. Order equivalence: for every strategy, `order(strat, i, sim, {})` for `i in 0..11` (sim with a
   cap the guard allows) equals a literal of the pre-refactor sequence (derived from the old
   `match` in §3). Replaces nothing; the per-strategy order tests stay.
3. Occult fallback: blocked -> `fallback` while `built < fallback_max`, then `""`
   (existing `:437`, reading `fallback_max` from the row instead of `OCCULT_MAX_RIFLEMEN`).
4. Mixed skip (existing `:483`, `cycle` from the row instead of `MIXED_ORDER`).
5. Cap floors 30/60 and no guard elsewhere (existing `:295`, `:416`; `:297` asserts the rows'
   `cap_floor`).
6. `buy_sanity` called only for rows with the flag (new: a counting Simulation subclass, like
   `CountingSim` at `:775`, one `act()` per strategy, by day and by night).
7. Loader rejects, each with its message: unknown key, duplicate name, duplicate JSON key,
   empty/absent `cycle`, branch not `a`/`b`, `cap_floor` without `on_blocked` and the reverse,
   `fallback` fields on a `skip` row, non-integral `fallback_max`; `check_towers`: unknown tower
   id, occult `fallback`, all-occult `skip` cycle.
8. The table is read-only and `next_upgrade` with a `branch_override` leaves it unchanged
   (existing `:235-250` adapted).
9. Data-only entry: a table from `parse_text` with one extra row (e.g. `probe`, cycle
   `[rifleman, harpooner]`) plays that order in `order()` and is accepted by `--strategies=probe`
   (harness copy from `_run_main` with the table injected), no code edit.
10. Harness: `--strategies=` keeps table order and rejects an unknown name (existing `:915-950`;
    `:926` reads `StrategyTable.default().names`).
11. Run cap: `_tick_cap()` is 54000 on `data/` and on `golden_data/`; `_max_ticks > 0` wins.
12. `balance.py`: `bot_strategies()` returns the JSON names in order (temp-file test with the
    path mocked; real-file test keeps `mundane` in, no duplicates).
13. Golden: `tests/golden_replay_test.gd` passes with `golden_digests.json` untouched.

Suggested controls (verify slice picks 6-8): revert the `prefix` handling (occult order test
fails); use `i % cycle.size()` without the prefix offset; drop `buy_sanity` row check (call for
all); drop the skip arm's kind check -> all-occult validation; drop `make_read_only`; drop the
`check_towers` unknown-id rule; set `TICKS_PER_WAVE` to `5 * 60 * 30` (cap test fails); return
`sorted(names)` in `balance.py` (its order test fails).

## 9. Checking "RUN lines identical on 20 seeds"

Reference = `780ea9e` in a throwaway worktree; both sides through `balance.py baseline` (the
branch side also exercises the new JSON reader). One background script, scratch work dirs
outside both repos:

```sh
S=<scratchpad>/lt101-run
REF=/Users/Valentin_Taiurskii/Projects/ClaudeProjects/lovecraft-td-wt-lt101-ref
NEW=/Users/Valentin_Taiurskii/Projects/ClaudeProjects/lovecraft-td-wt-lt101
git -C "$NEW" worktree add --detach "$REF" 780ea9e
for W in "$REF" "$NEW"; do "$GODOT" --headless --import --path "$W" >/dev/null 2>&1 || true; done
uptime > "$S.summary"
(cd "$REF" && /usr/bin/time -p python3 tools/balance/balance.py baseline --seeds=20 --jobs=4 --work="$S/ref") \
  > "$S/ref.out" 2>&1
(cd "$NEW" && /usr/bin/time -p python3 tools/balance/balance.py baseline --seeds=20 --jobs=4 --work="$S/new") \
  > "$S/new.out" 2>&1
for s in mundane occult mixed madness demolition battery resonator gate circle light; do
  a=$(grep -c '^RUN ' "$S/ref/logs/baseline.$s.log"); b=$(grep -c '^RUN ' "$S/new/logs/baseline.$s.log")
  if diff <(grep '^RUN ' "$S/ref/logs/baseline.$s.log") <(grep '^RUN ' "$S/new/logs/baseline.$s.log") >/dev/null
  then echo "SAME $s $a/$b"; else echo "DIFF $s $a/$b"; fi
done >> "$S.summary"
# flag paths the baseline does not reach (branch override, upgrades off), 5 seeds, both sides
for W in REF NEW; do d=${!W}
  "$GODOT" --headless --path "$d" -s res://tools/bot_runs.gd -- --seeds=5 --branch=rifleman:b \
    | grep '^RUN ' > "$S/$W.branch"
  "$GODOT" --headless --path "$d" -s res://tools/bot_runs.gd -- --seeds=5 --upgrades=0 \
    | grep '^RUN ' > "$S/$W.noup"
done
for k in branch noup; do
  if cmp -s "$S/REF.$k" "$S/NEW.$k"; then echo "SAME $k $(wc -l < "$S/NEW.$k")"; else echo "DIFF $k"; fi
done >> "$S.summary"
uptime >> "$S.summary"
```

Pass: 10 `SAME <s> 20/20` lines plus `SAME branch 50`, `SAME noup 50` (10 strategies x 5 seeds). RUN lines carry no wall time (`ticks` is sim ticks), so they compare byte
for byte. Then remove the reference worktree (`git worktree remove`). Golden:
`scripts/test.sh tests/golden_replay_test.gd`.

## 10. Owner questions

**Q1. Lab variants vary strategies?** S5's benefit line says "lab variants can vary strategies";
the acceptance does not require it.
- *Follow-up task, not in LT-101 (Recommended)*: benefit: LT-101 stays S/M and RUN-identical;
  risk: varying a build order in the lab needs a JSON edit by hand until then.
- *In LT-101*: variant key `"bot"` deep-merged into a copy of `strategies.json` by the existing
  patcher, passed as a new bot flag `--bot-strategies=<path>` (reserved for the runner).
  Benefit: an A/B of a build order without touching the repo; risk: +~40 lines and tests in
  `balance.py`, a new CLI flag, more for the verify slice.

**Q2. Shared tunables `BUILD_FIRST`, `FLARE_MIN_LIVE` into the JSON (top-level `"tunables"`)?**
- *Keep as consts (Recommended)*: benefit: ~10 test sites unchanged, smaller diff; risk: tuning
  them stays a `.gd` edit.
- *Move to JSON*: benefit: all bot tunables in one file, lab-variant ready with Q1; risk: more
  test edits, no current need.

### Owner decisions (2026-11-20)

- Design: "Утверждаю (Recommended)".
- Q1: "Отдельной задачей (Recommended)": lab variants varying strategies is a follow-up task, not LT-101.
- Q2: "Перенести в JSON": `BUILD_FIRST` and `FLARE_MIN_LIVE` move to a top-level `"tunables"` object in
  `tools/bot/strategies.json`, read by `strategy_table.gd`; the ~10 test sites that use the consts
  read the loaded values instead. This overrides the "Kept consts" line in §4 and the §5 table.

## 11. EDIT MAP for the code slice

Change:

| File | Lines (at `780ea9e`) | Change |
|---|---|---|
| `tools/bot/strategies.json` | new | §3 file |
| `tools/bot/strategy_table.gd` | new | §4 loader + validation 1-6 |
| `tools/bot/bot_strategies.gd` | 1-5 header; 12-33 consts; 43-72 `order`; 75-80 `cap_allows`; 86-88, 113-116 in `act`; 168-173 `next_upgrade` | §4; preload the table; field `table` |
| `tools/bot_runs.gd` | 8-38 header (strategy list -> "see tools/bot/strategies.json", `BRANCH_PICK` -> `branches`), 42-48, 76-81, 85, 92-93, 126-143 `_init`, 198 loop, 297-299 (stale orphan comment: delete) | §4, §7 |
| `tests/golden_runs.gd` | 9 (doc), 18, 163-177 `make_bot`, 179-180 `strategies` | §6 |
| `tests/bot_upgrade_test.gd` | 71-73, 249, 297, 441, 485, 721, 852, 926, 1005 | read rows instead of removed consts; add §8 #1, #2, #6, #8, #9, #11 |
| `tests/strategy_table_test.gd` | new | §8 #7 |
| `tools/balance/balance.py` | 31-32 (add `STRATEGIES_FILE`), 48-54 `bot_strategies` (`json.load`, `[r["name"] for r in ...["strategies"]]`) | §2 |
| `tools/balance/tests/test_balance.py` | 197-212 `BotStrategiesTest` | mock `STRATEGIES_FILE`, JSON fixture |
| `tools/balance/README.md` | 25, 68-69, Tests section; new "Add a strategy" section (append a row; the lab picks it up) | docs |

Read for context (do not change): `tools/bot/bot_placement.gd` (whole, 73 lines);
`sim/config.gd:136-164` (`_read_json`, `find_duplicate_keys`); `sim/defs/waves_config.gd:7-8`;
`tests/bot_upgrade_test.gd:37-70` (`_bot`, `_strat`), `:775-800` (`CountingSim`), `:860-912`
(`_run_main`); `tools/balance/balance.py:145-163, 180-200` (materialize, run_job).

Not changed: `data/`, `tests/fixtures/` (digests and golden data), `tools/golden/regen.gd`,
`tests/sim_rule_queries_test.gd` (only renames `_init`), `tests/sim_boundary_test.gd:748` (a file
list).

## 12. Must confirm (code slice)

1. `JSON.parse_string` returns numbers as float in Godot 4.7: cast `fallback_max` to `int`;
   `cap_floor` float compare as before (`30.0`).
2. `static var` cache works in a `RefCounted` script loaded by `preload` from both a SceneTree
   script and gdUnit (precedent: `scenes/lighting.gd:48`, `scenes/whisper_audio.gd:18`).
3. `make_read_only()` is shallow: apply it to nested arrays/dicts too; `.duplicate()` of a
   read-only dict is writable (needed by `next_upgrade`'s merge).
4. `GameConfig.find_duplicate_keys` is static and callable from `tools/` (no instance state).
5. Mundane towers have no `sanity_reserve` (checked: `data/` and `golden_data/` towers.json, all 5
   mundane ids none), so the `kind == "occult"` filters are behaviour-neutral.
6. `golden_data/towers.json` holds every tower id in the table (checked: same 10 ids as `data/`).
7. No runtime code outside `tools/`, `tests/` reads the bot (web export ships `tools/`; the JSON
   ships too, harmless).

Grep provenance for §1 readers (g-mesh has no GDScript plugin):
`grep -rn "bot_strategies\|BotStrategies\|STRATEGIES\|bot_runs\|bot_placement\|BotPlacement" . --exclude-dir=.git --exclude-dir=.godot`;
`grep -n "func \|const \|STRATEG\|BRANCH_PICK\|CAP_FLOOR\|MIXED_ORDER\|LIGHT_ORDER\|OCCULT_MAX\|BUILD_FIRST\|FLARE_MIN\|\.order(\|cap_allows" tests/bot_upgrade_test.gd`;
`grep -n "func \|const \|STRATEG\|MAX_TICKS" tests/golden_runs.gd`;
`grep -n "MAX_TICKS" tools/bot_runs.gd`.
