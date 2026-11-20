# Balance lab

Bots play the game on patched copies of `data/` and report, per balance variant and bot
strategy, how many runs they won and lost. Use it to try a balance idea without editing
`data/`: write a variant, run it next to `baseline`, compare the rows.

The goal set by the owner (LT-56): bots lose at least 10 of 20 runs. The table marks each
strategy that meets the target.

## Run

```sh
python3 tools/balance/balance.py baseline oil_price_1          # these variants, 20 seeds
python3 tools/balance/balance.py all --seeds=5                  # every variant, 5 seeds
python3 tools/balance/balance.py baseline --strategies=mundane,occult --jobs=4
python3 tools/balance/balance.py --list                         # variants and descriptions
python3 tools/balance/balance.py all --check                    # validate patches, run nothing
```

Options:

| option | default | meaning |
|---|---|---|
| `--seeds=N` | 20 | runs per strategy (seeds 1000 .. 1000+N-1, as in `tools/bot_runs.gd`) |
| `--strategies=a,b` | all | strategies to play; the list is read from `tools/bot/strategies.json` (row order) |
| `--jobs=N` | 3 | Godot processes at a time (one process = one variant x one strategy) |
| `--target=F` | 0.5 | a strategy meets the target when it loses at least `ceil(F * seeds)` runs |
| `--out=FILE` | `<work>/report.md` | where to write the markdown table (it is also printed) |
| `--work=DIR` | new temp dir | patched data dirs and logs; must be outside the repo |
| `--check` | | validate and write the patched data, run nothing |

Requires only `python3` and Godot (`$GODOT`, else `godot` on `PATH`, else
`/Applications/Godot.app`). In a fresh checkout or worktree run `godot --headless --import --path .`
once first: without `.godot/` the bot fails to parse (`Could not find type "GameConfig"`) and every
job reports 0 RUN lines. A Godot process still running after 120 + 60 x seeds seconds is killed
and its job fails (`timeout after N s`). Exit code 0 ok, 1 a Godot run failed (its `.err` log is named),
2 a bad variant, patch or option (nothing is run).

20 seeds x 6 strategies is about 8-15 minutes of CPU per variant (LT-30 S13: 499-996 s real per
5-strategy arm, three at a time). Start small (`--seeds=2`) to check a variant runs at all.

## Add a variant

Create `tools/balance/variants/<name>.json`:

```json
{
  "description": "one line: what changes and why",
  "patch": {
    "economy.json": { "lighthouse": { "oil": { "price": 1 } } },
    "towers.json": { "towers": { "rifleman": { "levels": { "0": { "damage": 30 } } } } },
    "waves.json": { "waves": { "*": { "groups": { "0": { "count": 10 } } } } }
  },
  "flags": ["--flare=0"]
}
```

All three keys are optional (`baseline.json` has only a description).

- `patch` maps a file in `data/` to an object that is deep-merged into it. An object merges
  key by key; any other value (number, string, bool, a whole array) replaces the old value.
- Array items are addressed by an object whose keys are:
  - an index: `"0"`, `"2"`, `"-1"` (last item);
  - `"*"`: every item;
  - `"field=value"`: every item whose `field` equals `value` (e.g. `"type=deep_one"`).
- A patch only changes values that exist. A key or index that is not in `data/`, a missing
  data file, or a value of another type (a string where a number was) is an error that names
  the variant, the file and the path, and nothing is run.
- `flags` are passed to `tools/bot_runs.gd` (see its header): `--flare=0`, `--lighthouse=0`,
  `--upgrades=0`, `--branch=rifleman:b`. `--seeds`, `--data`, `--out` and `--strategies` belong
  to the runner and are refused.
- The patched data still goes through the game's config validation; a value it rejects fails
  that variant's runs with `config errors: ...` in the `.err` log.

Shipped examples reproduce LT-30 S13 arms: `baseline` (A), `beam_off` (B), `flare_off` (D),
`oil_price_1` (F), `lighthouse_half_cost` (H).

## Read the table

```
| variant | mundane | occult | ... | met | s/run | user/real |
| baseline | 10/10 **yes** | 13/7 no | ... | 3/6 | 7.9 | 0.95 |
```

- A cell is `wins/losses` out of `--seeds`, then **yes** when the strategy meets the target
  (loses at least `ceil(target * seeds)`), else `no`. `(k t/o)` counts runs that hit the bot's
  cap of 6 simulated minutes per wave (30 for 5 waves; neither won nor lost).
- LT-68 two-part target: with the flare on, a strategy meets the target when it loses at least
  `ceil(target * seeds)` runs AND survives waves 1..3 (the first half of the waves) in at least
  `ceil(0.75 * seeds)` runs (15 of 20); the cell then carries `eN`, the runs that survived them.
  Flare-off variants (`--flare=0`) are judged on the losses part only; runs without
  `waves_survived` too.
- `met`: strategies meeting the target out of those played.
- `s/run`: mean real seconds per bot run in this row. `user/real`: CPU seconds per wall second;
  near 1 the runs were CPU-bound, far below 1 they were waiting (load, disk).
- The header records the commit (`(dirty)` when `sim/`, `tools/` or `data/` has uncommitted
  changes), seeds, target, and `uptime` at start and end: compare timings only between reports
  taken under similar load.
- A second table, "Where runs end" (LT-68), shows per strategy the losses in wave 1..N joined
  by `.` (e.g. `0.0.3.12.5`: 3 runs lost in wave 3, 12 in wave 4, 5 in wave 5), then the mean
  waves survived in brackets. `all losses by wave` sums the row; `early ok` is the share of all
  runs in the row that survived the first half of the waves (waves 1..3 of 5).
- Per-run detail (all RUN fields: flares, lighthouse level, gold, sanity, ...) is in
  `<work>/logs/<variant>.<strategy>.log`, one `RUN {json}` line per run.

Wins vary with seeds (loot is random): 2 seeds tell whether a variant runs, not whether it is
balanced. Compare variants at 20 seeds.

## Add a strategy

The bot's strategies are rows of `tools/bot/strategies.json` (LT-101), played in row order.
To add one, append a row; no code changes, and the lab picks it up (`--strategies=<name>` or
all):

```json
{"name": "probe", "about": "rifleman, harpooner repeated",
 "cycle": ["rifleman", "harpooner"], "branches": {"rifleman": "a", "harpooner": "a"}}
```

Fields: `prefix` (built once, first), `cycle` (then repeated), `branches` (tower -> L3 branch
`a`/`b`; a tower not listed stays at L2), `cap_floor` with `on_blocked` (`"skip"`, or
`"fallback"` with `fallback` and `fallback_max`), `buy_sanity`. The shared `tunables`
(`build_first`, `flare_min_live`) sit at the top of the file. The schema and the validation
rules are in `docs/design/LT-101-bot-strategies-data.md` §3; a bad file stops the bot before
any run (exit 1). Adding a row adds a strategy to the golden replay too
(`tests/golden_runs.gd`), so regenerate the golden digests (`tools/golden/regen.gd`).

## Tests

```sh
python3 -m unittest discover -s tools/balance/tests -v   # balance.py, no Godot (stdlib only)
scripts/test.sh tests/bot_upgrade_test.gd                 # the bot's --strategies= flag (gdUnit)
scripts/test.sh tests/strategy_table_test.gd              # tools/bot/strategies.json loader, interpreter, run cap (gdUnit)
```
