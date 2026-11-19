# LT-80: sim split 1 (B5): SimContext + LightSystem + SanitySystem

Scope: LT-65 block B5 (`docs/design/LT-65-architecture-review.md` §3.1, §4 G4a/G4b, §5 B5-B8,
§7 Q1). Base: `main` at `c3ad7ed` (0.6.0 bump); line numbers below are at that commit.
Design only. LT-81 (B6 Economy), LT-82 (B7 Combat + Ally) and LT-83 (B8 Spawn) are re-sliced
from §7 of this note.

Acceptance (unchanged from LT-65): golden output byte-identical (`tests/golden_replay_test.gd`
against `tests/fixtures/golden_digests.json`; `scripts/golden-regen.sh` must NOT be run), and
`tools/bot_runs.gd` wall time within 5 % of `main`.

## 1. Decisions in one paragraph

`Simulation` stays the only public API and the only place that orders the step slots. A new
`SimContext` owns the shared plumbing (state, config, RNG, the event buffer, the command log,
the day-only rule). `LightSystem` and `SanitySystem` take the beam/flare/oil and
sanity/cap/madness code verbatim **including their whole commands**: `can_*` checks, the
command body and its `command_log` entry (owner decision Q3, §8). The facade keeps the public
names as one-line forwarders, so `replay_command`, UI, bot and tests are unchanged. Gold is
reached through a seed `EconomySystem` that holds only `add_gold` (today's `_add_gold`,
verbatim) and grows into the full B6 system; Light and Sanity get it through their
constructors (Q2). The context never holds a system (no RefCounted cycles). B5 moves no
RNG draw.

## 2. SimContext

File: `sim/core/systems/sim_context.gd`, `class_name SimContext extends RefCounted`.

| Member | Kind | Notes |
|--------|------|-------|
| `state: SimState` | var, set once in `_init` | the same object as `Simulation.state`; never replaced |
| `config: GameConfig` | var, set once | the same object as `Simulation.config` |
| `events: Array[SimEvent]` | var | the one event buffer (invariant 3); `Simulation.drain_events` swaps it |
| `_rng: SimRng` | private var | built in `_init(config, run_seed)` from `run_seed`, as today |
| `rng(stream) -> RandomNumberGenerator` | func | `return _rng.stream(stream)` |
| `emit(type, id, data)` | func | `events.append(SimEvent.new(type, state.tick, id, data))`, the body of today's `_emit` |
| `log_command(entry: Array)` | func | `state.command_log.append(entry)`; the one writer of `command_log` (G4b), called at the exact spot of today's appends |
| `day_only() -> SimCommand.CommandResult` | func | today's `_day_only` (:1153-1158) verbatim; used by the facade (build, sell, upgrade, sell_relics) and by Light (lighthouse, oil) |

Ownership:
- **RNG.** Only `SimContext` creates the `SimRng`; systems draw through `ctx.rng(stream)` in the
  same call order as today. `Simulation.rng(stream)` forwards (tests and `golden_runs.gd`
  read `sim.rng(s).state`; `HallucinationSystem` draws through it).
- **Tick order.** Only `Simulation.step()` (no change in slot order or count). Systems expose
  one public method per slot; a system never calls another system's slot method.
- **Events.** `Simulation.events` becomes a read-only property
  (`var events: Array[SimEvent]: get: return _ctx.events`); `sim_boundary_api_test.gd:21`
  reads it. `drain_events()` does `var out := _ctx.events; _ctx.events = []; return out`.
  `Simulation._emit` keeps its signature and inlines `_ctx.events.append(SimEvent.new(...))`
  rather than calling `_ctx.emit`: it is the hottest call in the sim (SHOT and DAMAGE per
  hit) and the 5 % budget should not pay for a second call level.
- **Caching rule.** A system may keep `_ctx`, `_state := ctx.state` and `_config := ctx.config`
  as member vars (both objects live as long as the sim). It must **not** cache anything
  inside them: not `state.enemies` / `state.towers` (`_compact` replaces the arrays every
  tick), not `config.economy.flare` / `.oil` / `.beam` or `config.sanity.*` (tests set
  `sim.config.economy.flare = null` after construction, e.g. `flare_radial_test.gd:219`,
  and edit config sub-objects in about 10 suites). Reads stay exactly where they are today.
- **Lifetime.** `SimContext` holds no system. Systems hold `ctx` and the peers they call,
  injected through `_init` (a DAG: Light -> Economy, Sanity -> Economy in B5; §7). Nothing holds `Simulation`. So freeing a `Simulation` frees all of
  it; `bot_runs` builds hundreds of sims per process, a leak would show there.

`HallucinationSystem`, `WaveDirector` and `ScriptedSpawner` are unchanged: they keep calling
facade methods with the `Simulation` passed in (LT-65 §3.1 "Callers").

## 3. Systems

All are `RefCounted`, in `sim/core/systems/`, built once in `Simulation._init` after the
context, in this order: `_ctx = SimContext.new(config, run_seed)`,
`_economy = EconomySystem.new(_ctx)`, `_sanity = SanitySystem.new(_ctx, _economy)`,
`_light = LightSystem.new(_ctx, _economy)`. Construction writes state but emits nothing and
draws nothing, so the order changes no output; sanity before light keeps today's `_init`
order (sanity fields, then oil, then `_start_beam`).

Command shape: each moved command is moved **whole and verbatim** (outcome check, `can_*`,
writes, log, emits, gold) with three mechanical substitutions only:
`state.command_log.append(x)` -> `_ctx.log_command(x)`, `_day_only()` -> `_ctx.day_only()`,
`_add_gold(...)` -> `_economy.add_gold(...)`. The facade keeps the public name:
`func upgrade_lighthouse() -> SimCommand.CommandResult: return _light.upgrade_lighthouse()`.
Systems return `SimCommand.CommandResult` values: the enum moves to its own file first
(§5 step 0, owner decision Q5), so systems never name `Simulation`.

### 3.0 EconomySystem seed (`economy_system.gd`), owns `gold` from B5 on

The temporary gold access before B6. One public method, `add_gold(delta: int, reason: String,
id: int)`, the body of `_add_gold` (:1069-1074) verbatim (`state.gold += delta`, then
`ctx.emit(GOLD_CHANGED, id, {delta, gold, reason})`). The facade's own gold writers (build
:292, sell :325, upgrade :394, sell_relics :822, award_wave_bonus :909) call
`_economy.add_gold` at the same spot; `_add_gold` is deleted. Gold reads (`state.gold <
cost` in `can_*`) stay plain reads; G4b only counts writes.

Why this keeps golden byte-identical: the GOLD_CHANGED emit is the same expression appended
to the same buffer at the same point of each command, and no RNG is involved. Why it is
legal under G4a: no `Simulation` object, only public calls (`_economy.add_gold`,
`_ctx.emit`). Rejected alternatives: a `Callable` to the facade's `_add_gold` (holds the
Simulation object id, against the spirit of "a system never holds Simulation", and needs a
swap in B6); a `ctx.add_gold` (puts a rule into the plumbing and also needs a swap in B6).

### 3.1 LightSystem (`light_system.gd`), owns `lighthouse_level`, `beam_*`, `prev_beam_*`, `flare_*`, `oil`, `t.lit`, `t.shadowed`, `e.lit`

Public (no leading underscore), each moved verbatim from the named function:

| Method | From (`simulation.gd`) | Called by |
|--------|------------------------|-----------|
| `_init(ctx)` | `_init` :81-83 (oil start, `_start_beam`) | facade `_init` |
| `update_beam()` | `_update_beam` :1330-1358 | `step` slot 2 (first) |
| `apply_flare_slow()` | `_apply_flare_slow` :1542-1549 | `step` slot 2 |
| `count_down_flare()` | `_count_down_flare` :1552-1557 | `step` slot 2 (last) |
| `beam_on() -> bool` | `_beam_on` :1262-1263 | internal (`can_fire_flare`, `beam_directions`) |
| `flaring() -> bool` | `_flaring` :1267-1268 | internal; `flare_burn` |
| `beam_count()`, `lighthouse_upgrade_cost()` | :579-591 | facade forwards (ui, tools, tests) |
| `flare_seconds()`, `flare_burn()`, `oil_cap()`, `flare_cost_oil()`, `oil_for_flare()` | :1273-1316 (`_flare_ticks` becomes private `_flare_ticks`) | facade forwards |
| `light_at(p, skip_id)` | :1381-1394 | facade forwards (bot_runs, tests) |
| `is_lit(px, py)` | `_is_lit` :1515-1516 | facade `_is_lit` forwarder (tests, §8 Q1) |
| `power_mult(t)`, `interval_mult(t)` | `_power_mult` :1442-1446, `_interval_mult` :1449-1453 | facade `_apply_auras` :1598, `_fire_towers` :1700/:1776, `_cast_banish` :1797, `_summon` :1843 |
| `beam_directions(alpha)` | :695-710 | facade forwards (scenes/lighting.gd, tests) |
| `can_upgrade_lighthouse()`, `upgrade_lighthouse()` | :594-624 whole | facade forwarders (ui, bot, replay) |
| `can_buy_oil()`, `buy_oil()` | :627-656 whole | facade forwarders |
| `can_fire_flare()`, `fire_flare()` | :659-692 whole | facade forwarders |

Private, verbatim: `_add_oil` (:1078-1083, only the commands call it), `_flare_ticks`, `_lit_now`, `_light_flags`, `_casters`, `_in_cast`,
`_cast_count`, `_start_beam`, `_turn_beam`, `_beam_dirs`, static `_dirs_of`, `_lit_by`,
consts `LIT_FLAG`, `SHADOWED_FLAG` (:46-47).

Stays in the facade: `tower_mults` (a `TowerRules` query), `static in_cast_radius` (:1435,
external callers in `tests/light_shadow_test.gd`, and the G1 denylist names it).

`upgrade_lighthouse` after the move (statement order exactly as today):
```
func upgrade_lighthouse() -> SimCommand.CommandResult:
	var result := can_upgrade_lighthouse()
	if result != SimCommand.CommandResult.OK:
		return result
	var cost := lighthouse_upgrade_cost()
	_state.lighthouse_level += 1
	_ctx.log_command([_state.tick, "upgrade_lighthouse"])
	_ctx.emit(SimEvent.Type.LIGHTHOUSE_UPGRADED, 0, {"level": _state.lighthouse_level,
		"beams": beam_count(), "cost": cost})
	_economy.add_gold(-cost, "lighthouse", 0)
	return SimCommand.CommandResult.OK
```

### 3.2 SanitySystem (`sanity_system.gd`), owns `sanity`, `sanity_cap`, `sanity_state`

| Method | From | Called by |
|--------|------|-----------|
| `_init(ctx)` | `_init` :78-80 (cap, start, initial state, no event) | facade `_init` |
| `add(delta, reason, id) -> float` | `_add_sanity` :1092-1110 | facade `_on_enemy_killed` :1147, internal (buyout, debug, restore, regen), facade `_add_sanity` forwarder (tests, Q1) |
| `horror_drain()` | `_horror_drain` :1115-1134 | `step` slot 6 |
| `apply_madness_buff()` | `_apply_madness_buff` :1622-1633 (+ private `_madness_buff_blocked` :1638-1639) | `step` slot 2 |
| `change_reserve(t, delta, reason)` | `_change_reserve` :862-877 | facade `build_tower` :293, `sell_tower` :326, `upgrade_tower` :395 |
| `reserve_drives_mad(delta) -> bool` | `_reserve_drives_mad` :426-428 | facade `would_drive_mad_build` :407, `would_drive_mad_upgrade` :421 |
| `restore_target()`, `reserve_of(t)`, `reserve_delta(...)`, `sanity_state_for(s)`, `threshold()` | :841, :846, :852, :925-934, :2348 | facade forwards (external callers, §5) |
| `buyout_applies()`, `can_buy_sanity()`, `buy_sanity()` | :502-541 whole (gold via `_economy.add_gold`) | facade forwarders |
| `debug_set_sanity(value)` | :545-551 whole | facade forwarder |
| `auto_restore_sanity() -> float` | :831-837 whole | facade forwarder (wave_director) |
| `award_wave_sanity() -> float` | :916-920 whole | facade forwarder (wave_director) |

Const `MADNESS_EXIT_REASONS` (:40) moves (no caller outside `simulation.gd`).
Stays in the facade: `would_drive_mad_build` / `would_drive_mad_upgrade` (tower queries:
they read `config.towers`, `tower_by_id`, `upgrade_target`; they call
`_sanity.reserve_drives_mad`). `buy_sanity` keeps its order: log, `_economy.add_gold(-cost,
"buyout", 0)`, then `add(restore_target() - _state.sanity, "buyout", 0)`.

`SanitySystem` reads `e.lit` (`_madness_buff_blocked`) but never calls `LightSystem`: the
order "beam first, then madness buff" is the slot order in `step()`, not a call.

### 3.3 The step after B5

```
state.tick += 1; reset_modifiers
_light.update_beam()            # was _update_beam
_apply_auras()                  # facade until B7
_sanity.apply_madness_buff()    # was _apply_madness_buff
_light.apply_flare_slow()       # was _apply_flare_slow
_tick_statuses(); _tick_allies()
_light.count_down_flare()       # was _count_down_flare
_move(); _move_allies(); _leak(); _fire_towers(); _ally_combat(); _settle_blasts()
_sanity.horror_drain()          # was _horror_drain
_settle_tokens(); ... unchanged
```

### 3.4 Cross-system order and the determinism invariants (LT-65 §3.1)

Kill path in B5 (unchanged code, new targets): `apply_damage` -> `_on_enemy_killed` (facade)
-> `_drop_token(e)` (facade, B6 moves it) -> `_sanity.add(regen_mundane_kill, "mundane_kill",
e.id)`. From B7 the same sequence is `combat` -> `economy.on_enemy_killed(e)` ->
`sanity.on_kill(e, source)`, one plain call each, in that order.

| Invariant | How B5 keeps it |
|-----------|-----------------|
| 1 slot order only in `step()` | §3.3: one system call per moved slot; G4a forbids systems from naming `Simulation` |
| 2 RNG via `SimRng` streams only | no moved function draws; `SimContext` is the only `SimRng.new`; G4a forbids `SimRng.new` / `RandomNumberGenerator.new` under `systems/` |
| 3 one event buffer, no reordered emits | `ctx.events` is the buffer; facade `_emit` and `ctx.emit` append to it; each moved function's emit sequence is unchanged; G4a forbids `SimEvent.new` outside `sim_context.gd` in `systems/` |
| 4 iteration over `state` arrays in id order | loops moved verbatim; caching rule (§2) forbids holding a stale array |
| 5 float expressions verbatim | moved by cut and paste; no helper extraction, no regrouping (e.g. `e.def.horror_drain * SimTime.DT`, `_turn_beam`'s rotation, `restore_target() - state.sanity`) |
| 6 `command_log` / `REPLAY_ARGS` unchanged | same entries appended at the same statement through `ctx.log_command`; `REPLAY_ARGS` and `replay_command`'s `match` call the facade names, which forward |

Command sequences that now cross systems (each line is one statement today and stays one,
in this order):
- `upgrade_lighthouse`: Light level, log, `LIGHTHOUSE_UPGRADED`, Economy `GOLD_CHANGED`.
- `buy_oil`: log, Light `OIL_CHANGED`, Economy `GOLD_CHANGED`.
- `buy_sanity`: log, Economy `GOLD_CHANGED`, Sanity `SANITY_CHANGED` (+ `SANITY_STATE_CHANGED`).
- `build_tower` / `upgrade_tower` / `sell_tower` (facade): log, `_economy.add_gold`, then
  `_sanity.change_reserve`, as today.

## 4. Guards (new tests in `tests/architecture_guard_test.gd`)

Both reuse `SimBoundaryTest._code_lines` (comments and strings blanked), `_gd_files`, `_find`,
`_write_patterns`, `_mutators`. Each lands with this block and has controls in §6.

**G4a, systems are internal.** For every file under `res://sim/core/systems/`:
1. no `\bSimulation\b`, no exception (the result enum lives in `SimCommand`, §5 step 0);
2. no access to another object's private member: `\b(?!self\b)\w+\._\w+` (for example
   `_ctx._rng`, `sim._emit`); `self._x` is allowed;
3. no `\b(SimRng|RandomNumberGenerator)\.new\(`;
4. `\bSimEvent\.new\(` only in `sim_context.gd`.

And across `res://sim`, `res://scenes`, `res://ui`, `res://tools`: `\b(SimContext|\w+System)\.new\(`
for the classes declared in `systems/` appears only in `sim/core/simulation.gd`.
(`HallucinationSystem` lives in `sim/core/`, not `systems/`, so it is outside the list; it is
built with `new()` in `simulation.gd` anyway.) Each check gets a near-miss self-test on a
synthetic snippet, as G1-G11 do.

**G4b, one writer per state field.** For every `var` of `sim/core/sim_state.gd` (parsed, not
hard-coded), the set of files under `res://sim` that write it equals a pinned `OWNERS` map.
A write is a match of `_write_patterns(head, _mutators())` where `head` is `\b_?state` or
`\bctx\.state` (bare member access inside sim) or an alias `_state_writes` already resolves
(`var s := sim.state` in `wave_director.gd`); the field is the first `.name` after the head.
Entity fields (`t.lit`, `e.speed_mult`, `e.hp`) are out of scope: `speed_mult` has three
writers by design (auras, madness buff, flare slow). Pinned after B5:

| Owner file | Fields |
|-----------|--------|
| `systems/light_system.gd` | `lighthouse_level`, `beam_dx`, `beam_dy`, `prev_beam_dx`, `prev_beam_dy`, `beam_sign`, `flare_ticks_left`, `flare_cooldown_ticks`, `oil` |
| `systems/sanity_system.gd` | `sanity`, `sanity_cap`, `sanity_state` |
| `systems/economy_system.gd` | `gold` |
| `systems/sim_context.gd` | `command_log` |
| `core/wave_director.gd` | `phase`, `wave_index`, `waves_total`, `build_ticks_left` |
| `core/wave_director.gd` + `core/simulation.gd` | `night_luck` (call_wave sets it, dawn resets it) |
| `core/simulation.gd` | every other field (`tick`, `outcome`, `lighthouse_hp`, `map`, `enemies`, `next_id`, `relics`, `relic_tokens`, `next_token_id`, `blasts`, `next_blast_id`, `allies`, `towers`, `tower_at`) |

B6-B8 edit only this table. Before writing the map, the tests slice prints the scanner's
actual result on `main` and pins that (rule "compute, never write from memory"); a field
with an unexpected writer is a finding, not something to pin silently.

Also update `sim_boundary_test.gd:750` (`test_the_scans_cover_the_expected_files`): it pins
`_change_reserve` and `_reserve_drives_mad` as private members of `Simulation`; after B5 pin
members that stay (`_spawner`, `_pack_queue`, `_emit`, `_add_sanity` (Q1)).
`SIM_DIR` scans (engine types, forbidden tokens, G3, G10, G11 trig-free) pick up the new
files automatically: the moved code uses `sqrt` only (allowed), no trig, no `+ 0.5`.

## 5. Edit map for LT-80

### Step 0 (lands first, own commit): move `CommandResult` to `SimCommand`

Mechanical, no behaviour change, no diagnosis needed. Owner decision Q5.

New file `sim/core/command_result.gd`:
```
class_name SimCommand
extends RefCounted
## LT-80 (Q5): the result of a player command, moved out of Simulation so sim systems can
## return it without naming Simulation (G4a).

<cut here verbatim: simulation.gd :7-37, the two `##` doc lines and the whole
 `enum CommandResult { ... }` block, every value and comment in the same order>
```
The enum keeps its name `CommandResult`, so values never shift and two scans keep working
unchanged: `tests/command_text_test.gd:8` (`MAP_ENTRY` matches `CommandResult\.X:` inside
`SimCommand.CommandResult.X:`) and `tests/sim_boundary_test.gd:752` (`_own_types` still finds
the enum `CommandResult` under `sim/`).

Recipe (run from the worktree root, in this order):
```
# 1. the list (47 files: every file except simulation.gd that names it)
grep -rlE --include='*.gd' 'Simulation\.CommandResult\b' . | grep -v '^\./\.godot/'
# 2. simulation.gd: delete lines 7-37 (after copying them into the new file), then
perl -pi -e 's/(?<![\w.])CommandResult\b/SimCommand.CommandResult/g' sim/core/simulation.gd
# 3. every other file
grep -rlE --include='*.gd' 'Simulation\.CommandResult\b' . | grep -v '^\./\.godot/' \
  | xargs perl -pi -e 's/\bSimulation\.CommandResult\b/SimCommand.CommandResult/g'
# 4. checks: both must print nothing
grep -rn --include='*.gd' 'Simulation\.CommandResult' . | grep -v '^\./\.godot/'
grep -n 'SimCommand\.SimCommand' -r --include='*.gd' .
```
Step 2 also rewrites the word in `simulation.gd` comments (e.g. :254, :267); that is fine.
Bare `CommandResult` left elsewhere after step 3 is only in comments/strings and the two
scans above (`tests/command_text_test.gd:7,8,23,85`, `tests/sim_boundary_test.gd:752`); leave
them. Local aliases (`const R := Simulation.CommandResult` / `R2` in 12 test files,
`var R := ...` in `madness_test.gd:478`) become `SimCommand.CommandResult` through step 3.

Counts at `c3ad7ed` (from `grep -rn --include='*.gd' CommandResult`): 285 lines in 48 files,
`sim/core/simulation.gd` 108, `ui/text/command_text.gd` 32, `scenes/game_commands.gd` 17,
`tests/stats_panel_test.gd` 12, `tests/ui_event_refresh_test.gd` 11, `ui/tower_picker.gd` 9,
`tests/sanity_reserve_test.gd` 9, `tests/side_panel_test.gd` 9, the rest 1-6 each (`tools/bot_runs.gd`,
`ui/hud.gd`, `ui/tower_panel.gd`, `ui/lighthouse_panel.gd`, 35 more test files).

**No compat alias (every site rewritten), recommended because:** a `const CommandResult =
SimCommand.CommandResult` on `Simulation` would cover value uses (`.OK`, `.keys()`) but not
the many type hints (`-> Simulation.CommandResult`, `Array[Simulation.CommandResult]` in
`command_text.gd:39`), since a const is not a type in GDScript; a half-alias would leave two
spellings and invite `Simulation.CommandResult` back into `systems/`, which G4a now bans with
no exception. The full sweep is one perl line and the step 4 grep proves it complete.

Proof for step 0: `scripts/test.sh` on `golden_replay_test`, `command_text_test`,
`sim_boundary_test`, `sim_boundary_api_test`, `ui_event_refresh_test`, `gold_test` (parse
errors show in any of them; the class cache is re-imported by `scripts/test.sh`). Commit the
new `.uid`. Golden unchanged by construction (no sim code path changes). Dry-run of the recipe on a
scratch copy of `c3ad7ed`: 0 `Simulation.CommandResult` left, 0 doubled prefixes, 279
`SimCommand.CommandResult` sites (285 minus the enum declaration and the 5 bare test lines).

### Steps 1+ (the split)

New files (plus the `.uid` Godot generates on import; commit them):
- `sim/core/systems/sim_context.gd` (~55 lines: plumbing + `log_command` + `day_only`)
- `sim/core/systems/economy_system.gd` (~20 lines: `add_gold` only)
- `sim/core/systems/light_system.gd` (~440 lines incl. the lighthouse/oil/flare commands)
- `sim/core/systems/sanity_system.gd` (~270 lines incl. buyout/debug/restore/regen)

`sim/core/simulation.gd` (at `c3ad7ed`):

| Lines | Change |
|-------|--------|
| :40, :46-47 | consts move to Sanity / Light |
| :49-51, :57 | `events` becomes a getter property over `_ctx.events`; `_rng` replaced by `_ctx`, `_economy`, `_sanity`, `_light` |
| :69-84 `_init` | build `_ctx`, `_economy`, `_sanity`, `_light`; keep `state.map`, `lighthouse_hp`, `relics`, `_ground_route` here; gold, sanity and oil/beam starts move (note below) |
| :94-95 `rng` | forward to `_ctx.rng` |
| :111, :113, :114, :119, :136 | slot calls per §3.3 |
| :267, :305, :367, :793 | `_day_only()` -> `_ctx.day_only()` |
| :290, :323, :391, :467, :493, :565, :812 | `state.command_log.append(x)` -> `_ctx.log_command(x)` |
| :292, :325, :394, :822, :909 | `_add_gold(...)` -> `_economy.add_gold(...)` |
| :293, :319, :326, :387, :395, :407, :421 | `reserve_of` / `_change_reserve` / `reserve_delta` / `_reserve_drives_mad` -> `_sanity.*` |
| :426-428 | delete (moved) |
| :502-551 | `buyout_applies`, `can_buy_sanity`, `buy_sanity`, `debug_set_sanity` move whole to Sanity; one-line forwarders remain |
| :579-692 | `beam_count`, `lighthouse_upgrade_cost`, `can_upgrade_lighthouse`, `upgrade_lighthouse`, `can_buy_oil`, `buy_oil`, `can_fire_flare`, `fire_flare` move whole to Light; forwarders remain |
| :695-710 | `beam_directions` moves; forwarder |
| :831-877 | `auto_restore_sanity`, `restore_target`, `reserve_of`, `reserve_delta` move; forwarders; `_change_reserve` deleted |
| :916-934 | `award_wave_sanity`, `sanity_state_for` move; forwarders |
| :1051-1064 | `drain_events` swaps `_ctx.events`; `emit_event` unchanged; `_emit` appends to `_ctx.events` |
| :1069-1074 | `_add_gold` moves to `economy_system.gd` as `add_gold`; deleted here |
| :1078-1083 | `_add_oil` moves to Light (private) |
| :1092-1134 | `_add_sanity` -> one-line forwarder (Q1); `_horror_drain` moves |
| :1147 | `_sanity.add(...)` |
| :1153-1158 | `_day_only` moves to `SimContext.day_only` |
| :1262-1569 | moved to Light, except `in_cast_radius` (:1435) which stays; `_is_lit` -> forwarder (Q1); `flare_seconds`, `flare_burn`, `oil_cap`, `flare_cost_oil`, `oil_for_flare`, `light_at` -> forwarders |
| :1598, :1700, :1776, :1797, :1843 | `_power_mult` / `_interval_mult` -> `_light.*` |
| :1622-1639 | moved to Sanity |
| :2348-2349 | `threshold` forwards (:2356 `_roll_miss` calls `_sanity.threshold()`) |

Start values: `state.gold = config.economy.starting_gold` (:76) is a write of `gold`, so it
moves into `EconomySystem._init` (G4b `gold` -> `economy_system.gd` only). The same holds for
the sanity (:78-80) and oil/beam (:81-83) starts, already listed.

Expected size: `simulation.gd` 2407 -> about 1800 lines.

Tests to edit: `tests/sim_boundary_test.gd:750` (§4); `tests/architecture_guard_test.gd`
(G4a, G4b). No other test changes (Q1 keeps the two forwarders).

Read for context (implementer): `step` :99-160, `replay_command` :734-757, `_on_enemy_killed`
:1141-1149, `_apply_auras` :1572-1620, `build_tower` :275-297, `sell_tower` :313-329,
`upgrade_tower` :381-400, `SimBoundaryTest._code_lines` / `_write_patterns` / `_state_writes`.

### Callers relied on (found with `grep -rn --include=*.gd '\b<name>\b'` over the worktree, excluding `.godot/`; g-mesh does not index GDScript)

| Facade member | Callers outside `simulation.gd` |
|---------------|---------------------------------|
| `beam_count` | scenes/lighting.gd, ui/lighthouse_panel.gd, tests (beam, lighthouse_ui, ui_event_refresh) |
| `flare_seconds` | scenes/lighting.gd, ui/hud.gd, ui/lighthouse_panel.gd, 5 test files |
| `flare_burn` | scenes/lighting.gd, tests (sim_rule_queries, ui_event_refresh) |
| `oil_cap`, `flare_cost_oil`, `oil_for_flare` | ui/hud.gd, ui/lighthouse_panel.gd, scenes/game_commands.gd, tools/bot_runs.gd, tests |
| `light_at` | tools/bot_runs.gd (6), tests/sim_rule_queries_test.gd (22) |
| `beam_directions` | scenes/lighting.gd, tests (beam, lighthouse_ui, lighting) |
| `lighthouse_upgrade_cost` | ui/lighthouse_panel.gd, tools/bot_runs.gd, tests/beam_test.gd |
| `sanity_state_for` | 24 test files |
| `threshold` | sim/core/hallucination_system.gd, scenes/sanity_fx.gd, ui/hud.gd, ui/sanity_bar.gd, 11 test files |
| `would_drive_mad_*`, `buyout_applies` | ui/tower_picker.gd, ui/tower_panel.gd, ui/hud.gd, tests |
| `auto_restore_sanity`, `award_wave_sanity` | sim/core/wave_director.gd, tests |
| `reserve_of`, `reserve_delta`, `restore_target` | tools/bot_runs.gd, tests |
| `rng(stream)` | sim/core/hallucination_system.gd, tests/golden_runs.gd, 12 test files |
| `upgrade_lighthouse`, `buy_oil`, `fire_flare`, `buy_sanity`, `debug_set_sanity` and their `can_*` | `replay_command` (:734-757 `match`), ui/scenes via `scenes/game_commands.gd`, tools/bot_runs.gd, tests |
| `CommandResult` | 48 files, 285 lines: the step 0 sweep (§5) |
| `events` (property) | tests/sim_boundary_api_test.gd:21 |
| `_add_sanity` (private) | tests: lt62_fps, sanity_feedback, sanity_fx_screen, ui_polish, window_scale |
| `_is_lit` (private) | tests: beam_test.gd:61, flare_radial_test.gd:51 |
| `_add_oil`, `_horror_drain`, `_update_beam`, `_turn_beam`, `_power_mult`, `_interval_mult`, `_dirs_of`, `LIT_FLAG`, `MADNESS_EXIT_REASONS` | none (comments only) |

## 6. What tests must confirm (tests slice) and controls

Behaviours:
1. Golden digests unchanged (`golden_replay_test`), no regen.
2. Existing suites green: `beam_test`, `flare_radial_test`, `light_shadow_test`,
   `lighthouse_ui_test`, `sim_rule_queries_test`, `sanity_test`, `sanity_reserve_test`,
   `madness_test`, `madness_buff_test`, `sim_boundary_test`, `sim_boundary_api_test`,
   `sim_determinism_test`, `architecture_guard_test`.
3. G4a and G4b pass on the tree, and each has near-miss self-tests (a snippet that must hit,
   one that must not).
4. A freed `Simulation` frees its systems: `var w := weakref(sim._light)` (and `_sanity`,
   `_ctx`), drop the last `sim` reference, `w.get_ref() == null`. Pins "no cycles" before
   B6-B8 add peers.
5. Facade forwarding of the buffer: events emitted by a system and by the facade in one tick
   come out of one `drain_events()` in emit order, and a second drain is empty.
6. Each moved command keeps its result order and its side effects: for `upgrade_lighthouse`,
   `buy_oil`, `fire_flare`, `buy_sanity`, `debug_set_sanity` the tests slice lists the suite
   that pins (a) the first failing reason of its `can_*` (NOT_BUILD_PHASE at night for
   lighthouse and oil included), (b) the event sequence incl. GOLD_CHANGED, (c) the
   `command_log` entry and a `replay_command` of it. A gap is filled with a new test.

Verify slice (not tests): `bot_runs` wall time, `main` vs branch, same command, 3 runs each,
median, `uptime` and `/usr/bin/time -p` user/sys recorded:
`$GODOT --headless --path . -s res://tools/bot_runs.gd -- --seeds=10 --out=<scratch>`.

Candidate controls (each reverts code, never a test; 8):

| # | Revert in the throwaway worktree | Must fail |
|---|----------------------------------|-----------|
| C1 | `SanitySystem.add`: emit `SANITY_STATE_CHANGED` before `SANITY_CHANGED` | `golden_replay_test` |
| C2 | `LightSystem.buy_oil`: `_economy.add_gold` before `_add_oil` | `golden_replay_test` if the golden bots buy oil, else the behaviour-6 suite for `buy_oil`; the dry-run decides |
| C3 | `SimContext.day_only` always returns OK | the behaviour-6 suite pinning NOT_BUILD_PHASE for `buy_oil` / `upgrade_lighthouse` |
| C4 | `LightSystem` caches `var _flare := config.economy.flare` in `_init` and reads it in `flaring()` | `flare_radial_test` (:219 sets the flare to null) |
| C5 | add `var _sim: Simulation` to `light_system.gd` | G4a |
| C6 | `LightSystem.upgrade_lighthouse` writes `_state.gold -= cost` and emits GOLD_CHANGED itself instead of `_economy.add_gold` | G4b (`gold` gains a second writer) |
| C7 | `SanitySystem._init` stores itself in the context: `_ctx.set_meta("sanity", self)` (a cycle) | behaviour 4 (weakref test) |
| C8 | `drain_events` returns `_ctx.events` without swapping | behaviour 5, `sim_determinism_test` |

Run all controls in one throwaway worktree, one after another (revert, run only the named
suite with `scripts/test.sh`, `git checkout -- .`); dry-run the fail check on C1 first.

## 7. Outline for B6-B8 (re-slice LT-81..LT-83 from this)

Same pattern every time: move verbatim, whole commands (`can_*` included) go to their
system, the facade keeps a one-line forwarder per public name, one call per slot, peers by
constructor, G4b `OWNERS` rows move, golden byte-identical, `bot_runs` within 5 %.

- **B6 / LT-81 EconomySystem** (`economy_system.gd` grows from the B5 seed to ~250 lines).
  The temporary gold access needs no replacement: Light and Sanity already hold `_economy`
  and call `add_gold`, and the facade already calls `_economy.add_gold`; B6 only adds to the
  file. Moves: `relics` / `relic_tokens` / `next_token_id` writes (and the `relics` start,
  :74-75), `_drop_token`, `_settle_tokens` (slot 6b), `settle_all_tokens`, `_vanish_token`,
  `_add_relics`, `_roll_drop` (draws on the stream it is given: same call order),
  `_ghost_tokens`, `relic_price`, `relics_value`, `can_sell_relics` + `sell_relics` whole,
  `sell_refund`, `award_wave_bonus` whole, `early_night_luck` (reads `_spawner is
  WaveDirector`: pass "has a wave director" from the facade or keep it a facade query; LT-81
  design decides). No new peer. `_on_enemy_killed` stays in the facade and calls
  `_economy.drop_token(e)` then `_sanity.add(...)`. G4b rows: `relics`, `relic_tokens`,
  `next_token_id` -> `economy_system.gd`. Risk: `_roll_drop` RNG order; `_ghost_tokens` is a
  `Dictionary` (check it is only looked up, never iterated for output).
- **B7 / LT-82 CombatSystem + AllySystem** (~750 + ~200). Combat owns `e.hp/status/dead`,
  `t.cooldown_ticks/burst_index/locked_id`, `blasts`, `next_blast_id`; peers injected:
  `light` (power/interval mult), `sanity` (threshold, kill regen), `economy` (drop on kill).
  `_on_enemy_killed` becomes `combat._on_kill` -> `economy.on_enemy_killed(e)` ->
  `sanity.on_kill(e, source)`. Ally owns `allies`. **Cycle to resolve in LT-82 design:**
  `_summon` (Combat) spawns allies, `_ally_combat` (Ally) calls `apply_damage` (Combat).
  Recommended: Ally takes Combat as a constructor peer; Combat reaches `ally.spawn` through a
  `Callable` set by the facade (a Callable stores the object id, not a strong ref), and the
  weakref test (§6 behaviour 4) proves no cycle. Alternative: `_summon`'s spawn moves into
  AllySystem and Combat gets a peer Ally, while ally damage goes through a facade-provided
  Callable. `_apply_auras` goes to Combat. `_roll_miss/_roll_crit/_roll_astray` move with
  their callers, draws in the same order.
- **B8 / LT-83 SpawnSystem** (~200). Owns `enemies` (append, compact), `next_id` (shared
  with towers/allies: decide one writer, e.g. a `ctx.next_id()` allocator, a G4b row
  change), `_pack_queue`. Public: `spawn_enemy`, `release_pack_members(fakes)`, `move()`,
  `push_back(e, cells)` (Combat peer), `leak()`, `compact()`, `dissolve_fakes`. The facade is
  then ~600 lines and G4b `OWNERS` has no "every other field" row left except true facade
  fields (`tick`, `outcome`, `command_log`, `towers`, `tower_at`).

## 8. Decisions (owner, 2026-11-19)

Quoted verbatim (option labels chosen in the form):

- Q1 test-only private members: "Оставить форвардеры (Recommended)". The facade keeps
  one-line `_add_sanity` and `_is_lit` forwarders; B8 revisits them.
- Q2 how systems reach each other: "Через конструктор (Recommended)". Peers are injected one
  way through `_init`; `SimContext` holds no system.
- Q3 where command bodies live: "Системы владеют командами целиком". Systems own whole
  commands, `can_*` included, per the LT-65 §3.1 table (not the recommended option). This
  note was reworked for it: §1, §2 (`log_command`, `day_only`), §3.0 EconomySystem seed for
  gold, §3.1-§3.2, §3.4, §5, §6, §7.
- Q4 G4b scope: "Все поля SimState сразу (Recommended)". Every `SimState` field is pinned in
  B5.

- Q5 where `CommandResult` lives (raised by Q3): "Вынести enum в свой файл" (not the
  recommended option). The enum moves to `sim/core/command_result.gd` (`SimCommand`) as
  step 0 (§5), every caller is rewritten, G4a bans `Simulation` in `systems/` with no
  exception.
- Note: "Утверждаю (Recommended)". The note is approved with Q1-Q5 as above.
