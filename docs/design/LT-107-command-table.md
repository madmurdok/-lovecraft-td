# LT-107: command table (LT-96 S11, first slice of LT-32)

Source: `docs/design/LT-96-extensibility-synthesis.md` §4 S11 and owner decision D10
("Раздельно: S3 сейчас, S11 в LT-32 (Recommended)"). Pure refactor: no rule, event, log or
UI text changes. Next user: LT-32 crew (`hire` by day, `deploy` a post at night).

## 1. Today

A player command lives in up to six places that must agree by hand:

| Place | What | File:line |
|---|---|---|
| can-check | `can_build`, `can_sell_tower`, `can_upgrade`, `can_set_target_priority`, `can_call_wave`, `can_buy_sanity`, `can_sell_relics`, `can_upgrade_lighthouse`, `can_buy_oil`, `can_fire_flare`; **none** for `debug_set_sanity`, `debug_end_night` (checks inline) | `sim/core/simulation.gd:155-458`, `sim/core/systems/*` |
| apply + log | 12 `_ctx.log_command([tick, name, args...])` sites, each inside its apply, after the can-check | `simulation.gd:189,222,290,359,385,419`; `light_system.gd:68,101,136`; `economy_system.gd:78`; `sanity_system.gd:70,84` |
| replay arg types | `const REPLAY_ARGS: Dictionary[String, Array]` (12 names) | `simulation.gd:468-483` |
| replay dispatch | `replay_command` name/type check, then a 12-arm `match`, plus an "unreachable" fallback | `simulation.gd:486-512`; `_replay_args_ok` `:515-526` |
| scene forwarder | one `GameCommands` method per command (sim call + `after.call()`) | `scenes/game_commands.gd:29-109` |
| refusal text | `CommandText.TEXT` keyed by `CommandResult` only, not by command | `ui/text/command_text.gd:9-35` |

Adding a crew command today = new names in REPLAY_ARGS and the match, a new forwarder, and a
test entry (`BAD_ENTRIES`), with nothing to tell when one is forgotten except a replay drift.

Cross-file answers (g-mesh does not index GDScript; all by grep, run in this worktree):
- Who reads `REPLAY_ARGS`: `grep -rn "REPLAY_ARGS" --include='*.gd' .` -> `simulation.gd:470,489,493,496,512`,
  `tests/sim_boundary_api_test.gd:516` (`Simulation.REPLAY_ARGS.keys()`), `tests/sim_boundary_test.gd:666`
  (a string literal inside a caps-scan fixture; unaffected).
- Every log/issue site: `grep -rn "log_command(" --include='*.gd' sim` -> the 12 sites above + the writer `sim_context.gd:43`.
- Callers of `replay_command`: `grep -rln "replay_command" --include='*.gd' tests` -> sandbox_sim_test, sim_systems_test,
  sim_boundary_test, golden_runs, sim_boundary_api_test (no production caller).
- UI callers: `grep -rn "commands\.\(build\|sell\|upgrade\|call_wave\|buy_\|fire_flare\|set_target\|skip_ahead\)" --include='*.gd' ui scenes`
  -> `ui/tower_picker.gd:324`, `ui/tower_panel.gd:324,328,332`, `ui/hud.gd:121,131,142,147`,
  `ui/lighthouse_panel.gd:43,47`, `scenes/game.gd:119`; `scenes/game.gd:61` calls `sim.debug_set_sanity` directly.
  ~70 more `_game.commands.<name>(...)` sites in tests.
- `CommandText` users: `grep -rn "CommandText\." --include='*.gd' ui scenes` -> tower_picker, tower_panel, lighthouse_panel.
- Guards: `grep -n "callv\|G4_FACADE\|command_log" tests/architecture_guard_test.gd` -> `command_log` writer pinned
  to `sim_context.gd` (:529, :732); no guard against `callv`.

## 2. Design

### 2.1 Entry shape

One const table on the facade, replacing `REPLAY_ARGS` (same key order, so `keys()` order is unchanged):

```gdscript
## LT-107: one entry per player command. Key = the command_log name. Insertion order = REPLAY_ARGS order.
const COMMANDS: Dictionary[String, Dictionary] = {
	"build": {"args": [TYPE_STRING, TYPE_VECTOR2I], "can": &"can_build", "apply": &"build_tower", "text": ""},
	"sell": {"args": [TYPE_INT], "can": &"can_sell_tower", "apply": &"sell_tower", "text": ""},
	... # 12 entries
}
```

| Field | Type | Meaning |
|---|---|---|
| key | `String` | the `command_log` name (`entry[1]`); unchanged strings |
| `args` | `Array[int]` (Variant.Type) | types of `entry[2..]`, = old REPLAY_ARGS value; STRING takes StringName, FLOAT takes INT |
| `can` | `StringName` | Simulation method, same params as `apply`, returns `CommandResult`, changes nothing |
| `apply` | `StringName` | Simulation method (the public command); checks `can` first, logs on OK |
| `text` | `String` | key into `CommandText.BY_COMMAND` (per-command refusal wording); `""` = only the shared table |

Why names, not Callables: GDScript consts cannot hold bound Callables; `StringName` + `callv`
on `self` keeps the table a const that tests and UI can read without a Simulation instance.
`can`/`apply` stay Simulation methods (facade, guard G4); systems keep their own `can_*`/apply
bodies and their forwarders.

### 2.2 How each path uses it

- **Issue (new):** `Simulation.issue(name: String, args: Array) -> CommandResult`:
  `_check(name, args)` (UNKNOWN_COMMAND / BAD_ARGS, no side effect) then
  `callv(COMMANDS[name].apply, args)`. Bad input -> `push_error("Simulation.issue: ...")`.
- **Can (new):** `Simulation.can_issue(name, args)` -> same `_check`, then `callv(entry.can, args)`.
- **Apply + log:** unchanged. Each apply still calls its `can_*` first and logs at the same
  statement (see Q2). The table does not log.
- **Replay:** `replay_command(entry)` keeps its doc, its non-string-name check and both error
  strings verbatim (`"Simulation.replay_command: unknown entry %s"`, `"... bad args %s"`, tests
  pin them), then `return callv(COMMANDS[name].apply, entry.slice(2))`. The `match` and the
  "unreachable" line go. `_replay_args_ok(entry, types)` becomes `_args_ok(args, types)`.
- **Forwarder:** `GameCommands.issue(name, args)` = `sim.issue` + `after.call()`. The named
  forwarders stay (9 UI + ~70 test sites) as one-liners `return issue("build", [def_id, cell])`
  (Q4). `skip_ahead` and `buy_flare_oil` are UI composites, not table entries, and stay.
- **Text:** `CommandText.reason(r, cmd := "")`: `BY_COMMAND[COMMANDS[cmd].text][r]` if present,
  else `TEXT[r]`. `BY_COMMAND` is empty for the 12 existing commands, so every shown string is
  unchanged. LT-32 needs it: `deploy` refused with `NOT_NIGHT` should read "only at night",
  which the shared table (GENERIC) cannot say without changing `fire_flare` too (Q3).
- **Debug commands:** extract `can_debug_end_night()` (body of `simulation.gd:415-418`, same
  order) and `can_debug_set_sanity(_value: float)` (OUTCOME_REACHED else OK, from
  `sanity_system.gd:82-83`), so every entry has a `can` (Q5).

### 2.3 LT-32 recipe (the point of the slice)

A crew command = `can_hire`/`hire` in the crew system (logs its own entry) + two one-line
forwarders on Simulation (G4) + **one `COMMANDS` entry** + optional `BY_COMMAND` lines. Replay,
arg validation, `GameCommands.issue` and the completeness tests pick it up with no other edit;
the UI button calls `game.commands.issue("hire", [unit_id])`.

### 2.4 Byte-identical

- `command_log` entries: same names, same arg values and types (logging untouched; `typed`
  params still coerce, e.g. `debug_set_sanity(12)` logs `12.0` as today).
- Golden replays (`tests/golden_replay_test.gd`, `golden_trace_test.gd`, `golden_runs.gd`): no regen.
- `replay_command` results and error strings for every malformed entry
  (`sim_boundary_api_test.gd:446-570`); `REPLAY_ARGS` order == `COMMANDS` key order.
- Every `CommandText.reason(r)` and `panel_reason(r)` string; `CommandResult` values.
- `callv` coercion: `build_tower(entry[2], entry[3])` with Variant args and `callv` both go
  through the same typed-param conversion (StringName -> String, int -> float); pinned by
  `test_replay_command_accepts_string_name_for_string_and_int_for_float`.

## 3. Alternatives

| Option | Benefit | Risk |
|---|---|---|
| **A. Const table in `simulation.gd`, apply/log untouched (chosen)** | 1 sim file + small GameCommands/CommandText edits; no ordering change; LT-96 S11 variant A | facade grows ~15 lines; dispatch by method name (typo caught only by the arity test) |
| B. New `sim/core/sim_commands.gd` (`class_name SimCommands`) holding the table + `_check` | facade stays smaller; UI reads the table without naming Simulation | one more file; `apply` names still point at Simulation, so the table is split from what it names |
| C. Central logging in `issue` | 12 log sites -> 1 | direct calls (`sim.build_tower` in ~100 test sites, UI) must route through `issue` or stop logging; logged arg types change unless `convert()`ed (int vs float); log position moves relative to effects |
| D. Callables built in `_init` (`{"apply": build_tower}`) | no string dispatch | not const: tests/UI need an instance; per-sim allocation |
| E. Leave as is until LT-32 code | zero work now | each crew command touches 4 places; D10 already put S11 first in LT-32 |

## 4. Open questions for the owner

1. **Where the table lives.** (a) `const COMMANDS` in `simulation.gd` (Recommended: one place
   next to the methods it names; S11 variant A). (b) New `sim/core/sim_commands.gd`: smaller
   facade, one more file.
2. **Logging.** (a) Keep the 12 per-command `log_command` sites (Recommended: command_log
   byte-identical by construction). (b) Centralise in `issue` with `convert()`: one writer, but
   every direct-call site must change and arg typing must be re-proved by goldens.
3. **Text key.** (a) `text` -> `CommandText.BY_COMMAND` overrides, empty for existing commands
   (Recommended: no visible change, LT-32 gets "only at night"). (b) No `text` field until LT-32
   adds it. (c) Wire existing buttons' labels into the table (labels are formatted at runtime,
   e.g. "Sell relics (+%s)"; churn, visible-text risk).
4. **Named forwarders in `GameCommands`.** (a) Keep them as one-liners over `issue`
   (Recommended: 0 UI/test call-site edits, one code path). (b) Keep bodies as today and only add
   `issue` (two paths can drift). (c) Remove them and move ~80 call sites to `issue` (big diff).
5. **Debug commands' `can`.** (a) Extract `can_debug_end_night` / `can_debug_set_sanity`
   (Recommended: every entry uniform). (b) Make `can` optional (`&""` = always OK): fewer new
   functions, a special case in `can_issue`.

## 5. EDIT MAP (code slice)

Change:
- `sim/core/simulation.gd:468-483` `REPLAY_ARGS` -> `COMMANDS` (12 entries, same order).
- `sim/core/simulation.gd:486-512` `replay_command`: keep checks/messages, replace `match` with `callv`.
- `sim/core/simulation.gd:515-526` `_replay_args_ok` -> `_args_ok(args, types)`; add `_check`,
  `issue`, `can_issue` next to it.
- `sim/core/simulation.gd:407-427` `debug_end_night`: body's two checks -> `can_debug_end_night()`.
- `sim/core/simulation.gd:403-404` add forwarder `can_debug_set_sanity`;
  `sim/core/systems/sanity_system.gd:76-87` split its OUTCOME check into `can_debug_set_sanity`.
- `scenes/game_commands.gd:29-109` add `issue(name, args)`; named forwarders -> `issue(...)` (Q4).
- `ui/text/command_text.gd:9-57` add `BY_COMMAND := {}` and `reason(r, cmd := "")` fallback.
- `tests/sim_boundary_api_test.gd:512-517` `Simulation.REPLAY_ARGS.keys()` -> `Simulation.COMMANDS.keys()`.

Read for context (do not change):
- `sim/core/systems/sim_context.gd:41-44` (`log_command`, the one writer).
- `sim/core/command_result.gd` (UNKNOWN_COMMAND, BAD_ARGS).
- `tests/sim_boundary_api_test.gd:274-330, 446-570` (replay helpers, BAD_ENTRIES, error strings).
- `tests/golden_runs.gd:355-385`, `tests/sim_boundary_test.gd:960-970, 1020-1055` (frame-pattern replays).
- `tests/architecture_guard_test.gd:500-540, 600-640` (G4 facade, command_log writer).

## 6. Behaviours for the tests slice (each with a control)

1. **Golden unchanged:** golden replay/trace suites pass without regen (control: swap two entries'
   `apply` names, e.g. `buy_oil`/`fire_flare` -> fails).
2. **Completeness:** `COMMANDS.keys()` == the set of names any `log_command` writes (scan the 12
   sites' literals) and == `BAD_ENTRIES.keys()` (control: drop the `debug_end_night` entry).
3. **Entry well-formed:** for each entry, `can` and `apply` exist on Simulation (`has_method`) and
   both accept exactly `args.size()` args (method list, defaults allowed) (control: misspell one `can`).
4. **can/apply agree:** for each entry on a state where it is refused, `apply` returns the same
   result as `can`, and digest/log/events are unchanged; where `can` is OK, `apply` is OK (control:
   make `can_debug_end_night` return OK by day).
5. **issue == direct call:** `sim.issue(name, args)` vs the named method on a twin: same result,
   digest and last log entry, for all 12 (control: `issue` skips `_check` -> bad args script error).
6. **issue/can_issue refuse bad input:** unknown name -> UNKNOWN_COMMAND, wrong arity/type -> BAD_ARGS,
   push_error, nothing changes (control: return OK from `_check`).
7. **replay_command unchanged:** existing `sim_boundary_api_test` replay tests incl. error strings
   and StringName/int coercion (control: drop the STRING_NAME allowance in `_args_ok`).
8. **No per-name dispatch:** guard that `replay_command`, `issue`, `can_issue` bodies contain no
   `match` and no command-name literal (control: re-add one `match` arm).
9. **GameCommands.issue:** returns the sim result and calls `after` exactly once, OK or refused
   (control: skip `after.call()` on refusal).
10. **Text fallback:** `reason(r, cmd)` == `reason(r)` for every result and every existing command;
    a planted `BY_COMMAND` override wins only for its command (control: ignore `cmd`).

## 7. Owner decisions (2026-11-21)

1. Where the table lives: "const в simulation.gd (Recommended)".
2. Logging: "Оставить 12 мест (Recommended)".
3. Text key: "BY_COMMAND, пустой сейчас (Recommended)".
4. Named forwarders: "Однострочники через issue (Recommended)".
5. Debug commands' `can`: "Выделить can_debug_* (Recommended)".
