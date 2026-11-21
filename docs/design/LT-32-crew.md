# LT-32: crew, hire by day, deploy defence posts at night (design note)

Status: proposal, owner decisions pending (§1, Q1-Q8 and T1) · branch `feat/LT-32-crew` off
`release-0.11.0` (`6bff0be`). Line numbers below are from that commit.

Owner idea (verbatim): "Мне кажется что продажа только днем, и возможно имеет смысл закупать не
башни а юнитов. Ну типа - закупили 10 гарпунщиков, на каждую башню положено по 2 человека, 4х
разместили ( сделали 2 башни ) а 6 придержали до ночи. Если есть нужда - ставим еще 3 гарпунные
башни (или даже не башни а пункты обороны, которые бьют хуже чем башни, а в башни они
автоматически апгрейдятся днем/или вариант что днем они снова возвращаются в резерв )".

Source sketch and its 8 open questions: `LT-27-day-night-relics.md` §7. Seams this note builds
on: LT-99 dawn hook (`Simulation.on_dawn`, `simulation.gd:588-595`), LT-100 config registry
(`config.gd:100-115`, optional-block rule in the header), LT-105 modifier channel
(`LT-105-tower-modifiers.md`, writer slot "[LT-32 crew posts]" in `Simulation.step`,
`simulation.gd:83-86`), LT-107 command table (`COMMANDS`, `simulation.gd:487-504`;
`CommandText.BY_COMMAND`, `command_text.gd:39-41`).

**In one paragraph.** By day money hires **crew** into a **reserve**. A crewed tower kind
(the four mundane shooters) needs `per_tower` crew of its own kind; building it takes crew from
the reserve first and hires the missing ones on the spot, so with an empty reserve a build costs
exactly today's `cost`. At night a player can **deploy** reserve crew as a **post**: the same
tower def at L1 on a free buildable cell, free of money, firing at `post.power_mult` (0.6) via
the LT-105 channel, no upgrades. At **dawn** every post is struck and its crew returns to the
reserve. Selling a tower returns its crew to the reserve and refunds 70 % of the money spent on
frame and upgrades. All crew config is one optional file, `data/crew.json`; absent (golden data,
test copies) means crew off and byte-identical behaviour.

## 1. The eight LT-27 §7 questions

Each: options, the recommended one first, its benefit and risk.

### Q1. Crew per tower kind; do occult towers need crew?

- **(a) Recommended: one crew kind per crewed tower def, keyed by the tower id; v1 crews the
  four mundane shooters (rifleman 2, harpooner 2, dynamite_crew 2 "Sappers", coast_battery 3
  "Gunners"); occult towers and the searchlight need no crew.** Benefit: exactly the owner's
  example (harpooners staff harpoon towers); occult towers already pay with the sanity reserve
  (LT-23), so a second cost axis is not stacked on them; the searchlight is a light caster, a
  "searchlight post" at 60 % power means nothing. Data allows adding any tower later (one row).
  Risk: the occult strategies get no night agency from crew; the mundane/occult asymmetry grows
  (mundane gains posts). Follow-up idea: occult "scholars" whose post costs sanity.
- (b) Every tower has crew, occult crews are scholars/cultists. Benefit: uniform. Risk: occult
  posts need their own rules (banish/summon at 60 %? sanity reserve of a free post?); doubles
  the design and tests.
- (c) One generic crew ("hands") for every tower. Benefit: simplest reserve. Risk: loses the
  owner's "10 harpooners" flavour; a reserve of hands deploys any post, no plan-ahead choice.

### Q2. Hire price vs. today's tower cost

- **(a) Recommended: `cost` in towers.json stays the price of a ready L1 tower; crew.json gives
  `per_tower` and `hire`; the frame price is derived, `frame = cost - per_tower * hire`
  (cross-check: >= 0).** v1 numbers: rifleman 50 = 10 + 2x20; harpooner 70 = 20 + 2x25;
  dynamite_crew 90 = 30 + 2x30; coast_battery 120 = 30 + 3x30. Upgrades keep their
  `upgrade_cost` and need no extra crew. Benefit: a build with an empty reserve costs exactly
  today's money (one `GOLD_CHANGED "build"`), so bots, the picker's numbers, most tests and
  every balance result so far carry over; one number cannot drift from the sum of two.
  Risk: crew is ~70-80 % of the price, so selling (Q6) loses little; tuning the split is a lab
  parameter (§8).
- (b) Independent `frame` and `hire` numbers, `cost` dropped for crewed towers. Benefit: free
  tuning. Risk: every build price changes at once, every test and bot table with it; two
  numbers per tower to keep coherent.
- (c) Crew hired only through the reserve (build refused without crew in reserve). Benefit: the
  reserve is always explicit. Risk: two clicks per build; bots and every build test change.

### Q3. Post stats; where can a post stand?

- **(a) Recommended: a post is a `SimTower` of the same def at L1 with `post = true`; a crew
  pass writes `add_modifiers(post.power_mult, post.interval_mult, 0.0)` on every post each
  tick (LT-105 writer slot, after traits, posts in tower-id order). Defaults: power 0.6,
  interval 1.0; same range, targeting and target priority as the L1 tower; no upgrades, no
  sanity reserve. It stands on any cell `can_build` accepts (buildable, free). Free of money.**
  Benefit: zero new combat code: damage, bleed, pierce, blasts all come from the L1 level and
  the channel already composes with light (light writes first, then crew, LT-105 D4); the
  panel shows the channel's numbers (LT-105 D7, owner Q3 "modified" wording). Risk: the
  channel has no range field, so a post cannot be shorter-ranged without a sixth channel field;
  a lit post (x0.8 interval, no miss) is close to a dark tower.
- (b) A post is a separate entity (`SimPost`) with its own stats block in crew.json. Benefit:
  any stat (range, targeting). Risk: a second shooter path through combat, targeting, look and
  panel code; much larger.
- (c) LT-105 §3's original sketch: a post is a buff aura on nearby towers. Benefit: no new
  shooter. Risk: not what the owner described (posts "бьют хуже чем башни", i.e. they shoot).

### Q4. Dawn rule

- **(a) Recommended: at dawn every post is struck and its crew returns to the reserve
  (`on_dawn`, last action).** By day the reserve then builds towers for frame money only (Q2),
  so "convert the post" is one picker click on the same cell. Benefit: deterministic, no
  unrequested spending, no post ever exists by day (so sell/upgrade never meet a post and need
  no new refusal), simplest bot. Risk: the player re-clicks each post he wants to keep; a
  "fortify all posts" button can come later.
- (b) Auto-convert at dawn: a post becomes a tower if money covers its frame (in tower-id
  order), else returns. Benefit: the owner's first variant, no clicks. Risk: spends money the
  player may want for something else; order-dependent when money runs out; dawn money comes
  from the wage paid in the same `on_dawn`, so the order inside `on_dawn` becomes a rule.
- (c) Posts stay all day with a "Fortify ($frame)" button. Benefit: player chooses per post.
  Risk: posts by day must be refused by sell/upgrade (new results), and a standing free post at
  60 % may beat building frames for long runs.

### Q5. Can crew die or desert?

- **(a) Recommended: no losses in v1.** Benefit: the reserve is a pure resource, easy to read
  and to balance; nothing new draws RNG (golden RNG streams untouched). Risk: hiring is a sunk
  cost with no attrition; the reserve only grows. Follow-up task candidates: posts lose crew
  when a leak passes them; madness makes crew desert.
- (b) Posts lose one crew member when an enemy touches them. Risk: posts need HP/contact rules.
- (c) In MADNESS a share of the reserve deserts at dawn. Risk: new RNG draw or a rounding rule;
  stacks a second penalty on the madness strategy.

### Q6. Selling a tower

- **(a) Recommended: the crew returns to the reserve; refund = `roundi(spent * sell_refund_ratio)`
  where `spent` counts money for frame + upgrades only (auto-hired crew money is not in it).**
  Benefit: "units, not towers": moving a tower costs ~70 % of the frame, not of the crew; the
  reserve grows by day for the night. Risk: relocation becomes cheap (rifleman: today sell
  loses $15, now $3 of frame); the live-data tests that pin a refund change (§6).
- (b) Crew is dismissed, refund 70 % of everything (today's numbers). Benefit: no refund change
  anywhere. Risk: crew becomes a pure price split, the reserve never grows from sales.
- (c) Crew to reserve and refund 70 % of everything. Risk: selling becomes a profit generator
  (crew worth 100 % plus 70 % of it in money).

### Q7. Upkeep

- **(a) Recommended: one-time hire, no wage.** Benefit: no dawn drain to balance; LT-27's dawn
  wage stays income only. Risk: no cost to hoarding crew. An optional `wage` key can be added
  later (absent = 0, optional-block rule).
- (b) Each crew member costs `wage` at dawn. Risk: a second economy loop, bots must budget it.

### Q8. UI and the bots' deployment policy

- **(a) Recommended:** reuse panels (§4): the tower picker turns into the post picker at night;
  hiring lives in a small crew panel in the side panel (like the lighthouse panel) opened from a
  HUD crew line. Bots (§5): two optional tunables `crew_reserve` (extra hires by day, default
  0) and `post_min_live` (deploy everything in the reserve at night when at least that many
  live enemies are on the map). Benefit: no new screen; with `crew_reserve = 0` the bots play
  exactly as with crew off (a built-in control). Risk: the post picker shares its rows with the
  build picker; the bot never "saves" crew for later nights.
- (b) A dedicated crew bar under the HUD with drag-and-drop deploy. Risk: new input path, UI
  tests, out of grey-box scope.

### T1 (extra). Which configs run with crew on

- **(a) Recommended: `data/crew.json` ships with `"enabled": true`; frozen golden data and the
  test copies (`ConfigTestBase.FILES`, 6 files, `config_test_base.gd:6-7`) have no crew.json,
  so they run crew off; `SimTestBase.real_config()` stays live (crew on).** Benefit: no golden
  regen; `tsim()`/`make_config()` suites unchanged; crew-on is exercised by the real-config,
  scene and UI suites and the new crew suites. Risk: the few live-data suites that pin a sell
  refund change (§6); test copies never see crew unless a crew suite adds the file.
- (b) Crew shipped off (`"enabled": false`) until the owner's playtest. Benefit: zero test
  churn now. Risk: the playtest build needs a data flip and a second test pass.

## 2. Sim model

### 2.1 Data: `data/crew.json` (new optional file)

```json
{
  "enabled": true,
  "post": { "power_mult": 0.6, "interval_mult": 1.0 },
  "crews": {
    "rifleman":      { "name": "Riflemen",   "per_tower": 2, "hire": 20 },
    "harpooner":     { "name": "Harpooners", "per_tower": 2, "hire": 25 },
    "dynamite_crew": { "name": "Sappers",    "per_tower": 2, "hire": 30 },
    "coast_battery": { "name": "Gunners",    "per_tower": 3, "hire": 30 }
  }
}
```

- `CrewConfig` (new `sim/defs/crew_config.gd`): `enabled: bool`, `post_power_mult` (0 < x <= 1),
  `post_interval_mult` (>= 1), `crews: Dictionary[String, CrewKind]` (`name`, `per_tower` int
  >= 1, `hire` int >= 0). Unknown keys rejected as in other parsers.
- Registry (LT-100): one row `[CREW_FILE, _parse_crew, false]` appended **last** in
  `_sections()` (`config.gd:100-110`), so existing files keep their error order
  (`config_reject_test`). Absent file or `enabled: false` -> `GameConfig.crew == null` /
  `crew_on() == false`.
- Cross-check `_check_crew` appended to `_cross_checks()` (`config.gd:114-115`): every crew key
  is a tower id; `frame = cost - per_tower * hire >= 0`. With `enabled: false` the block is still
  validated (the lab's off arm stays a valid config).
- Lab switch: a balance variant patches `"crew.json": {"enabled": false}` (patches change only
  existing values, README "Add a variant"), which is why `enabled` exists despite the
  optional-file rule.

### 2.2 State

- `SimState.crew: Dictionary[String, int]` reserve per crew kind (empty when off).
- `SimTower.crew := 0` (crew on board), `SimTower.post := false`. `spent` keeps meaning money
  for this tower (frame + upgrades), the refund base. The golden `state_text`
  (`golden_runs.gd:262-288`) prints named tower fields only, so new fields do not touch it.

### 2.3 `CrewSystem` (new `sim/core/systems/crew_system.gd`, LT-80 system pattern)

Holds `_ctx`, `_state`, `_config`, `_economy`. Every method returns at once when crew is off.

| method | rule |
|---|---|
| `crew_need(def_id) -> int` | `per_tower` of a crewed def, else 0 (also when off) |
| `build_price(def_id) -> int` | `def.cost` when not crewed; else `frame + max(0, need - reserve) * hire` |
| `take_for_build(t)` | reserve -= min(reserve, need); `t.crew = need`; CREW_CHANGED only if the reserve changed |
| `can_hire(kind)` | OUTCOME_REACHED, NO_CREW (off / not a crew kind), NOT_ENOUGH_GOLD, NOT_BUILD_PHASE (`_ctx.day_only()`, last) |
| `hire(kind)` | reserve += 1; log `[tick, "hire", kind]`; CREW_CHANGED `{kind, reserve, delta: 1, reason: "hire"}`; `add_gold(-hire, "hire", 0)` |
| `can_deploy(def_id, cell)` | OUTCOME_REACHED, UNKNOWN_TOWER, NO_CREW, NOT_BUILDABLE, OCCUPIED, RESERVE_SHORT, NOT_NIGHT (phase != WAVE, last) |
| `deploy(def_id, cell)` | new SimTower (next id, L1, `post = true`, `spent = 0`, `crew = need`); log `[tick, "deploy", def_id, cell]`; TOWER_BUILT `{def, cell, cost: 0, post: true}`; CREW_CHANGED reason "deploy" |
| `release(t, reason)` | reserve += t.crew, CREW_CHANGED; used by sell, dawn and (contract §7) a destroyed tower |
| `write_post_mods()` | slot 2: for t in towers (id order) if t.post: `t.add_modifiers(post_power, post_interval, 0.0)` |
| `on_dawn()` | posts in id order: erase from `towers` / `tower_at`, dismiss their allies (none for v1 kinds), TOWER_SOLD `{def, cell, refund: 0, post: true}`, `release(t, "dawn")` |

- **Build** (`Simulation.build_tower`, `simulation.gd:175-195`): `can_build` swaps
  `state.gold < def.cost` for `state.gold < build_price(def_id)` (same position, same reason
  order); apply pays `build_price` with one `GOLD_CHANGED "build"` and sets `t.spent = frame`
  for a crewed def (`def.cost` otherwise): the auto-hired crew money buys crew, not the tower.
  TOWER_BUILT `cost` = money paid (today's value with an empty reserve). Then
  `take_for_build(t)`.
- **Sell** (`sell_tower`, `simulation.gd:212-228`): after TOWER_SOLD, `release(t, "sell")`.
  `sell_refund` (`economy_system.gd:106-107`) is unchanged: `spent` already excludes crew.
- **Posts and other commands:** a post never exists by day (Q4a), and sell, upgrade, lighthouse
  are day only, so no new refusal is needed for them. `set_target_priority` on a post is
  allowed (it is a tower). `would_drive_mad_build` is unaffected (crewed defs have no reserve).
- **New `CommandResult` values**, appended after `OIL_FULL` (values never shift):
  `NO_CREW` (crew off or the def has no crew), `RESERVE_SHORT` (fewer than `per_tower` in the
  reserve).
- **New `SimEvent.Type` value**, appended last: `CREW_CHANGED`, id 0, `{kind, reserve, delta,
  reason: "hire" | "build" | "sell" | "deploy" | "dawn" | "lost"}`. Digests use the type
  *name* (`golden_runs.gd:134`), so appending changes nothing existing.
- **No RNG draw anywhere** (no new stream; Q5a).

### 2.4 Phase hooks and step order

- Dawn: `Simulation.on_dawn` gains one last line `_crew.on_dawn()` after
  `auto_restore_sanity()` (LT-99: "a new dawn action is one line here"). Events land before
  WAVE_CLEARED, as all dawn actions do. Off -> no-op.
- Dusk: nothing. Deploy is gated by phase (`WAVE`), not by a dusk action.
- Step slot 2 (`simulation.gd:83-96`): `_crew.write_post_mods()` right after
  `_traits.near_tower()`, before `_combat.apply_auras()`; the slot comment already names it
  ("[LT-32 crew posts]"). LT-105 D4 order: light, traits, crew.
- `debug_end_night` reaches `on_dawn` through the director, so posts return there too.

### 2.5 Facade

One-line forwarders on Simulation (guard G4): `crew_need`, `build_price`, `can_hire`, `hire`,
`can_deploy`, `deploy`, `crew_reserve() -> Dictionary`. Constructed after `_economy` in
`_init` (`simulation.gd:34-56`), before `_combat` is not needed (crew does not reach combat).

## 3. Commands (LT-107 table)

Appended after `debug_end_night` in `COMMANDS` (`simulation.gd:487-504`), so the old key order
is a prefix:

```gdscript
	"hire": {"args": [TYPE_STRING], "can": &"can_hire", "apply": &"hire", "text": "hire"},
	"deploy": {"args": [TYPE_STRING, TYPE_VECTOR2I], "can": &"can_deploy", "apply": &"deploy",
		"text": "deploy"},
```

`CommandText` (`command_text.gd`):

- `TEXT` gains `NO_CREW: "no crew for this"`, `RESERVE_SHORT: "not enough crew"`.
- `BY_COMMAND = {"deploy": {NOT_NIGHT: "only at night", OCCUPIED: "cell occupied"}, "hire":
  {NOT_BUILD_PHASE: "hire by day"}}`. (`OCCUPIED` repeats TEXT; drop it if the slice prefers
  only real overrides.)
- `GameCommands` (`scenes/game_commands.gd`): `hire(kind)` and `deploy(def_id, cell)` one-liners
  over `issue` (LT-107 Q4).
- `tests/sim_boundary_api_test.gd` `BAD_ENTRIES` (`:475`) gains both names (LT-107 completeness
  test forces it).

## 4. UI (grey-box, minimal)

- **HUD** (`ui/hud.gd`, `_ready` :78-202, new `_refresh_crew` next to `_refresh_relics`
  :258-264): a `CrewButton` "Crew: 6" (reserve total; tooltip per kind "Harpooners 4 in reserve,
  2 on duty"), hidden when crew is off; refreshed on CREW_CHANGED. Pressing it opens the crew
  panel.
- **Crew panel** (new `ui/crew_panel.gd`, a sibling view in `SidePanel._ready` :69-116, the
  `LighthousePanel` pattern): one row per crew kind: name, `reserve / on duty`, `Hire ($25)`
  button -> `game.commands.hire(kind)`; disabled with `CommandText.reason(r, "hire")`.
- **Picker by day** (`ui/tower_picker.gd` `refresh` :250-300): the cost cell and tooltip show
  `game.sim.build_price(id)` instead of `def.cost`; a tooltip line "uses N Harpooners from the
  reserve" when the reserve covers some crew.
- **Picker at night** (same `refresh`, `_on_tower_pressed` :323-326): in `WAVE` with crew on,
  crewed rows check `can_deploy(id, cell)` and read "Post: <name> (2 crew)"; pressing deploys;
  the title reads "Deploy a post" (or the shared refusal, e.g. "Not enough crew"); uncrewed rows
  stay "only by day". The picker already refreshes on TOWER_BUILT/TOWER_SOLD (`:32-33`); add
  CREW_CHANGED and the phase events to `REFRESH_ON`.
- **Tower panel** (`ui/tower_panel.gd` `_rebuild` :163-214): a post shows "Post: returns to the
  reserve at dawn" instead of the upgrade rows; sell is refused at night anyway. Numbers come
  from the channel (LT-105 D7), so the 60 % shows with the generic "modified" mark.
- **Board** (`scenes/board/entity_layer.gd` `_draw_tower` :147-178): a post draws its plate at
  reduced alpha with a dashed border (look only; no new look catalog entry needed).
- **End screen:** none.

## 5. Bots (`tools/bot_runs.gd`, LT-101 strategies data)

- `tools/bot/strategies.json` tunables: `crew_reserve` (extra crew to hold by day, default 0)
  and `post_min_live` (default 4). Both **optional** in `StrategyTable._read_tunables`
  (`strategy_table.gd:113-128`; today every key is required), so existing strategy-table test
  texts stay valid.
- `BotStrategies.act` (`bot_strategies.gd:53-105`):
  - night branch (`:55-57`): after `night_flare(sim)`, `night_posts(sim)`: when live enemies >=
    `post_min_live`, for each crew kind in the row's build order with reserve >= per_tower,
    deploy at `Placement.best_cell(cfg, sim, id, score_cache)` until refused.
  - day: builds as today (auto-hire inside `build_tower`; same money as crew off). After the
    build loop breaks, `hire_reserve(sim, strat)`: hire the row's first crewed cycle tower's
    crew while total reserve < `crew_reserve` and `hire` is OK.
- With `crew_reserve = 0` the reserve stays empty (bots never sell), no post is ever deployed,
  and every RUN line equals the crew-off run: the control for §8 and a cheap test.
- `bot_runs.gd` `_play` (:166-306): RUN gains `"crew_hired"`, `"crew_gold"` (from
  `GOLD_CHANGED reason "hire"`), `"posts"` (TOWER_BUILT with `post`). Header comment documents
  the tunables. No new CLI flag (tunables are patched through the lab's `bot` key, LT-112).
- `tools/balance/balance.py`: no change needed for the tables; optionally print mean `posts`.

## 6. Save / replay / golden impact

- **No save system exists** (no `user://` or save code in `sim/`, `scenes/`, `ui/`, `io/`).
  Replays are `command_log`: `hire` and `deploy` entries replay through `COMMANDS` like the
  others.
- **Golden replay and trace: unchanged, no regen.** `tests/fixtures/golden_data/` has no
  crew.json -> crew off; every crew branch is a no-op; no new event, RNG draw or command is
  emitted; new enum values are appended; new tunables are unused with crew off. No new
  strategy row is added (a row would add golden runs; README "Add a strategy").
- **Test copies (`make_config`, `tsim`, `load_edited`)**: crew off (crew.json not in
  `ConfigTestBase.FILES`). Unchanged.
- **Live-data suites (crew on)**: build money identical (empty reserve). Changes expected only
  where a suite **sells** a crewed tower on live data and pins the refund or the gold after it,
  or pins the picker's cost text: candidates by grep `refund` in tests (9 files:
  `config_reject`, `lighthouse_config`, `occult_tower`, `config_valid`, `side_panel`,
  `scene_game`, `sim_economy`, `gold`, `upgrade`; most use `tsim` copies and stay green). The
  tests slice measures the actual set by one targeted run and updates the expected values.
- **Pinned lists that grow:** `config_registry_test` / `config_from_dicts_test` (registry rows,
  `config_from_dicts_test.gd:95,103`, `config_registry_test.gd:19,154`), `architecture_guard_test`
  (`:429` event type list), `ui_event_refresh_test` (`CommandResult.keys()`), LT-107 completeness
  tests, `roster_snapshot_test` if it snapshots data files.

## 7. Contract for LT-117 (night_gaunt `tower_lift`)

- Crew belongs to the `SimTower`: `t.crew` and `t.post` travel with a lifted tower unchanged;
  lifting neither releases nor kills crew. A lifted post stays a post (its crew writer keeps
  writing 0.6 while LT-117's `disabled` is set; `disabled` ORs, LT-105 D4).
- A lifted tower keeps its id; LT-117 moves it by updating `t.cell`, `t.pos` and `tower_at`
  (today `pos` is "set once when built", `sim_tower.gd:15`; LT-117 owns that change).
- If LT-117 ever removes a tower (no free cell to drop on), it calls `CrewSystem.release(t,
  "lost")` through the facade (crew back to the reserve, no money). Recommended for LT-117: no
  removal; drop on the nearest free buildable cell, or stay in place.
- At dawn a post struck while lifted returns its crew as any post.

## 8. Lab plan (`tools/balance/`, CLAUDE.local.md rules)

20 seeds per arm, all strategies; report losses/20, "Where runs end" (mean wave reached) and
"Lighthouse HP left" (mean/median), plus mean `posts` and `crew_gold` from RUN lines.

1. **Control pair:** `lt32_crew_off` (`crew.json enabled: false`) vs `baseline` (crew on,
   `crew_reserve` 0). Expected: identical RUN lines. If they differ, stop: crew on is leaking
   into play without posts.
2. **Does night agency matter?** `crew_reserve`: baseline 0 vs arms 2 and 4, then double/halve
   from the first arm that moves the metric (2 -> 1 / 4). Read: wave reached and HP left rise
   with posts deployed > 0 (an arm with `posts` = 0 measured nothing).
3. **Post strength** (threshold parameter, 0 < x <= 1): with the reserve arm from step 2, vary
   the remainder `1 - power_mult` = 0.4: halve -> 0.2 (power 0.8), double -> 0.8 (power 0.2).
   Bisect toward the owner's feel target ("weaker than towers", noticeable) in 2-3 steps.
4. **Crew share of the price** (`hire`, frame derived): x2 is invalid for most towers (frame <
   0), so halve the crew share (hire / 2: frame doubles) and take the max valid share (frame
   0). Effect is on selling and the cost of extra reserve only; skip if step 2 shows no effect.
5. `post_min_live`: 4 -> 2 / 8, only if posts deploy too late or too early by HP-lost-per-wave.
6. Sanity table next to the runs: post DPS per hire-dollar vs tower DPS per dollar from
   `data/towers.json` + crew.json (not a model, a check).

The lab proposes; the owner picks shipped numbers after a playtest.

## 9. Edit map

Cross-file facts used (GDScript is not indexed by g-mesh; all by grep in this worktree):
`grep -rn "on_dawn"` -> only `simulation.gd:588` and `wave_director.gd:143`;
`grep -rn "TOWER_BUILT\|TOWER_SOLD" ui scenes` -> `tower_picker.gd:32-33`, `tower_panel.gd:17,30`;
`grep -rln "load_dir" scenes tools` -> `scenes/main.gd:27`, `tools/bot_runs.gd:140`;
`grep -rn "section_files\|_sections()" tests` -> the registry tests above;
`grep -n FILES tests/config_test_base.gd` -> the 6-file copy list (crew off in copies);
`grep -rln "refund" tests` -> the 9 files in §6; `SimEvent.Type.keys()` users ->
`golden_runs.gd:134,240`, `golden_trace_test.gd:84`, `architecture_guard_test.gd:429`,
`lt62_fps_test.gd:337`.

### S2 sim + data + commands

| file | function (lines) | change |
|---|---|---|
| `sim/defs/crew_config.gd` | new | `CrewConfig`, `CrewKind`, `parse` |
| `sim/config.gd` | consts :16-21, `_sections` :100-110, `_cross_checks` :114-115 | `CREW_FILE`, row `[CREW_FILE, _parse_crew, false]` last, `_check_crew`, `var crew`, `crew_on()` |
| `data/crew.json` | new | §2.1 |
| `sim/core/sim_state.gd` | vars :22-41 | `crew` reserve |
| `sim/core/sim_tower.gd` | vars :12-51 | `crew`, `post` |
| `sim/core/command_result.gd` | enum end :35 | `NO_CREW`, `RESERVE_SHORT` |
| `sim/core/sim_event.gd` | enum `Type` end | `CREW_CHANGED` with doc comment |
| `sim/core/systems/crew_system.gd` | new | §2.3 |
| `sim/core/simulation.gd` | `_init` :34-56 | construct `_crew` |
| same | `step` :72-138 | `_crew.write_post_mods()` after `_traits.near_tower()` |
| same | `can_build` :155-168, `build_tower` :175-195 | `build_price`, `t.spent = frame`, `take_for_build` |
| same | `sell_tower` :212-228 | `_crew.release(t, "sell")` |
| same | `on_dawn` :588-595 | `_crew.on_dawn()` last |
| same | `COMMANDS` :487-504 + forwarders | `hire`, `deploy` (§3) |
| `scenes/game_commands.gd` | after `fire_flare` :97-98 | `hire`, `deploy` one-liners |
| `ui/text/command_text.gd` | `TEXT` :9-35, `BY_COMMAND` :39-41 | §3 |

Read for context: `SimContext.day_only` / `log_command` / `next_id` (`sim_context.gd:43-60`),
`EconomySystem.add_gold` (`economy_system.gd:29-33`), `SimTower.add_modifiers` (`sim_tower.gd:73-82`),
`AllySystem.dismiss_allies`, `GameConfig.from_dicts` (`config.gd:45-84`),
`EconomyConfig._parse_flare` (`economy_config.gd:267-286`, optional-block parse pattern).

### S3 UI

| file | function (lines) | change |
|---|---|---|
| `ui/hud.gd` | `_ready` :78-202, `_rebuild` :234-251 | `CrewButton`, `_refresh_crew`, CREW_CHANGED mask |
| `ui/crew_panel.gd` | new | rows + hire buttons |
| `ui/side_panel.gd` | `_ready` :69-116, `_update_idle` :167+ | add `CrewPanel` view |
| `ui/tower_picker.gd` | `REFRESH_ON` :32-33, `refresh` :250-300, `_on_tower_pressed` :323-326 | build price; night post rows |
| `ui/tower_panel.gd` | `_rebuild` :163-214 | post line instead of upgrades |
| `scenes/board/entity_layer.gd` | `_draw_tower` :147-178 | post look |

Read: `LighthousePanel` (`ui/lighthouse_panel.gd`, 164 lines) as the panel template;
`TowerText.cost_text`.

### S4 bots

| file | function (lines) | change |
|---|---|---|
| `tools/bot/strategy_table.gd` | `TUNABLE_KEYS` :14, `_read_tunables` :113-128 | optional `crew_reserve`, `post_min_live` |
| `tools/bot/strategies.json` | `tunables` | the two keys |
| `tools/bot/bot_strategies.gd` | `act` :53-105 | `night_posts`, `hire_reserve` |
| `tools/bot_runs.gd` | header :1-67, `_play` :166-306 | RUN keys `crew_hired`, `crew_gold`, `posts` |
| `tools/balance/README.md` | variants | the crew-off variant note |

Read: `night_flare` (`bot_strategies.gd:125-138`), `Placement.best_cell` (`bot_placement.gd:13-48`).

### Behaviours the tests slice pins (each with a control)

1. Crew off (no crew.json): golden replay/trace byte-identical (control: make `build_price`
   ignore `crew_on()` with a crewed config copy -> crew-on test fails; golden itself is the
   no-regen check).
2. Build with empty reserve pays `def.cost` in one GOLD_CHANGED, no CREW_CHANGED; with reserve
   N pays `frame + max(0, need-N) * hire` (control: always charge `def.cost`).
3. `hire`: day only, money, reserve +1, logged, replays (control: drop `day_only`).
4. `deploy`: night only, reserve -need, no money, post at L1, TOWER_BUILT `post: true`
   (control: allow by day).
5. Post damage = L1 damage x `post.power_mult` through the channel, composed after light
   (control: skip `write_post_mods`).
6. Dawn strikes every post and returns its crew before WAVE_CLEARED (control: drop the
   `on_dawn` line).
7. Sell returns crew and refunds 70 % of frame + upgrades (control: refund from `def.cost`).
8. Bot with `crew_reserve = 0`: RUN lines equal crew off on 3 seeds (control: default 2).

## 10. Slicing

The work fits three code slices plus tests, verify, measure and playtest; no task split is
needed. Slices and their one exit criterion:

| slice | phase | exit criterion |
|---|---|---|
| S1 | design | this note approved by the owner (Q1-Q8, T1) |
| S2 | implement: sim + data + commands (§9 S2) | `hire`/`deploy` replay through `COMMANDS` and golden replay passes without regen |
| S3 | implement: UI (§9 S3) | a game window (`-- --mute`) shows hire by day and a post deployed at night that is gone at dawn (screenshot pair) |
| S4 | implement: bots (§9 S4) | `crew_reserve = 0` RUN lines equal crew-off RUN lines on 3 seeds; `crew_reserve = 2` deploys posts |
| S5 | tests | behaviours 1-8 pinned, each control fails when reverted |
| S6 | verify | targeted suites + controls in a throwaway worktree, findings reported |
| S7 | measure | lab steps 1-3 (§8) table delivered to the owner |
| S8 | owner playtest | owner verdict recorded |

Follow-up backlog candidates (not in LT-32): crew losses / desertion (Q5 b/c); occult crew
("scholars") and posts for occult towers (Q1 b); "Fortify all posts" day button (Q4); upkeep
wage (Q7 b); barricades deployed from the reserve (LT-18).
