# LT-32: crew, hire by day, deploy defence posts at night (design note)

Status: approved with edits (owner review 2026-11-22: Q1, Q2, Q5-Q8, T1 as recommended; Q3
revised, Q4 kept without a post-to-tower path; see §11). One new decision is open: Q3b (posts
and `tower_lift`). Branch `feat/LT-32-crew` off `release-0.11.0` (`6bff0be`). Line numbers
below are from that commit.

Owner idea (verbatim): "Мне кажется что продажа только днем, и возможно имеет смысл закупать не
башни а юнитов. Ну типа - закупили 10 гарпунщиков, на каждую башню положено по 2 человека, 4х
разместили ( сделали 2 башни ) а 6 придержали до ночи. Если есть нужда - ставим еще 3 гарпунные
башни (или даже не башни а пункты обороны, которые бьют хуже чем башни, а в башни они
автоматически апгрейдятся днем/или вариант что днем они снова возвращаются в резерв )".

Source sketch and its 8 open questions: `LT-27-day-night-relics.md` §7. Seams this note builds
on: LT-99 dawn hook (`Simulation.on_dawn`, `simulation.gd:588-595`), LT-100 config registry
(`config.gd:100-115`, optional-block rule in the header), LT-105 modifier channel
(`LT-105-tower-modifiers.md`; posts are ordinary readers and receive light/trait writes, they
need no writer of their own, §2.4), LT-107 command table (`COMMANDS`, `simulation.gd:487-504`;
`CommandText.BY_COMMAND`, `command_text.gd:39-41`).

**In one paragraph.** By day money hires **crew** into a **reserve**. A crewed tower kind
(the four mundane shooters) needs `per_tower` crew of its own kind; building it takes crew from
the reserve first and hires the missing ones on the spot, so with an empty reserve a build costs
exactly today's `cost`. At night a player can **deploy** `post.crew` (2) reserve men of any kind
as a **reserve post**: not a tower but a temporary group of plain riflemen on a free buildable
cell, with its own stats in `crew.json` (`post`), its own look (figures, no tower plate), free
of money, no upgrades, never in the tower picker's build list. At **dawn** every post is
removed and its men return to the reserve; there is no post-to-tower path. Selling a tower returns its crew to the reserve and refunds 70 % of the money spent on
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
  searchlight is not a shooter crew. Data allows adding any tower later (one row).
  Risk: the occult strategies get no night agency from crew; the mundane/occult asymmetry grows
  (mundane gains posts). Follow-up idea: occult "scholars" whose post costs sanity.
- (b) Every tower has crew, occult crews are scholars/cultists. Benefit: uniform. Risk: occult
  posts need their own rules (banish or summon posts? sanity reserve of a free post?); doubles
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

### Q3. What a post is, its stats, where it stands (revised after owner review)

Owner (2026-11-22, verbatim): "Резервисты - это по сути не башня, а просто временный пост, он не
должен выглядеть как башня, по умолчанию это просто стрелки". Reading: a post is a temporary
group of reserve men; whatever crew kind they are hired as, by default they fight as plain
riflemen ("просто стрелки"). "По умолчанию" leaves room for later per-kind posts (e.g.
harpooners throwing harpoons) and for upgrades from lighthouse rooms (§10), both out of scope.

- **(a) Recommended: identity and stats of its own, carried by a `SimTower` record.**
  - *Identity:* `SimTower.post = true` with a synthetic `TowerDef` id `"post"` (name "Reserve
    post", kind `mundane`, one level, no branches) built by `CrewConfig` from `crew.json`
    `post`. It is **not** in `config.towers`, so the tower picker's build list, stats table,
    roster snapshot, bot cycles and LT-43 cards never show it. Own look (§4): two or three
    rifleman figures, no plate, no tower glyph. Not upgradeable, not sellable (new result
    `NOT_A_TOWER`, checked right after `NO_SUCH_TOWER` in `can_upgrade` / `can_sell_tower`; it
    is also what keeps `upgrade_target` from indexing a missing `levels[1]`).
  - *Stats (own data entry):* `post.crew` 2 men of one crew kind (any kind; the deploy command
    names it), `range` 2.5, `damage` 6, `fire_interval` 0.8, no effects. Rifleman L1 for
    comparison (`data/towers.json`): range 3, damage 10, interval 0.8, so a post is ~60 % of a
    rifleman tower's DPS at a shorter reach. Optional per-kind `post` override in a crew row is
    allowed by the parser but not shipped.
  - *Placement:* any free buildable cell (`can_build`'s map rules: buildable, not occupied).
    No money. Night only.
  - *Why a `SimTower` record, not a new entity:* it is still the simplest sim carrier: combat
    (`fire_towers`, targeting, misses, target priority), light (`update_beam` sets `lit` /
    `shadowed` and writes the LT-105 channel), `tower_at` occupancy and the build-cell checks
    all work unchanged. Identity and look are kept separate by `t.post` and the `"post"` def.
  - *LT-105:* a post is an ordinary channel **reader**. It gets the light writer's values like
    any mundane shooter (lit: x0.8 interval, no miss; shadowed: x1.25 interval, +0.1 miss) and
    any LT-106 trait writes. Crew adds **no writer**: the weakness is in the post's own stats,
    so the "[LT-32 crew posts]" writer slot in `Simulation.step` stays empty and the panel's
    "modified" mark (LT-105 owner Q3) is not raised by crew.
  - Benefit: matches the owner's words (not a tower, looks different, plain shooters), stats
    are tuned directly in data, no new combat path. Risk: a `SimTower` that is "not a tower"
    must be filtered wherever code means a real tower (sell, upgrade, panel upgrade rows, bot
    `towers_final`, `build_first` counts in the bot); the slice lists every `state.towers`
    reader (must-confirm in §9).
- (b) A separate entity `SimPost` in `state.posts` with its own fire loop. Benefit: no "not a
  tower" filters. Risk: a second shooter path through combat, light, targeting, occupancy and
  render; roughly doubles S2.
- (c) The L1 tower of the crew's kind x 0.6 through the channel (the first draft). Rejected by
  the owner's review: it is a tower in all but power and looks like one.

**Q3b (new owner decision). Posts and the night-gaunt's `tower_lift` (LT-117).**

- **(a) Recommended: posts are immune to `tower_lift`** (LT-117 skips `t.post` when picking a
  target). Benefit: thematic (a gaunt lifts a structure; a post is men on the ground), keeps
  posts and their men in place, LT-117 needs one filter and no crew rule. Risk: from wave 6
  posts are the one gaunt-proof defence; if that is too strong, the lab sees it in HP left.
- (b) Lifted like towers: the post and its men are dropped `drop_cells` away and disabled
  `disable_seconds`, men stay with the post. Benefit: one rule for every shooter. Risk: lifting
  men looks odd; same cost to LT-117 as a tower.

### Q4. Dawn rule (owner: kept; no post-to-tower path)

- **Decided: at dawn every post is removed and its men return to the reserve (`on_dawn`,
  last action).** No post ever becomes a tower and there is no "fortify" button: posts and
  towers are different things (Q3). Benefit: deterministic, no unrequested spending, no post
  ever exists by day, simplest bot. Risk: none new; by day the reserve men can staff new
  towers (a build takes reserve crew of its kind first, Q2), which is the only bridge.
- Rejected: (b) auto-convert a post into a tower at dawn; (c) posts stay all day with a
  "Fortify" button. Both assume a post is a weak tower, which Q3 no longer holds.

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
  "post": { "name": "Reserve post", "crew": 2, "range": 2.5, "damage": 6, "fire_interval": 0.8 },
  "crews": {
    "rifleman":      { "name": "Riflemen",   "per_tower": 2, "hire": 20 },
    "harpooner":     { "name": "Harpooners", "per_tower": 2, "hire": 25 },
    "dynamite_crew": { "name": "Sappers",    "per_tower": 2, "hire": 30 },
    "coast_battery": { "name": "Gunners",    "per_tower": 3, "hire": 30 }
  }
}
```

- `CrewConfig` (new `sim/defs/crew_config.gd`): `enabled: bool`, `post_crew` (int >= 1),
  `post_def: TowerDef` (synthetic, id `"post"`, kind `mundane`, `cost` 0, `levels = [L]`, no
  branches; `L` parsed by `TowerDef.Level.parse` from `range` / `damage` / `fire_interval`, so
  the level's own checks apply), `crews: Dictionary[String, CrewKind]` (`name`, `per_tower` int
  >= 1, `hire` int >= 0, optional per-kind `post` override with the same keys: parsed, not
  shipped). Unknown keys rejected as in other parsers. `post_def` is **not** added to
  `config.towers`.
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
- `SimTower.crew := 0` (men on board), `SimTower.crew_kind := ""` (set for a post: whose men
  stand there), `SimTower.post := false` (a reserve post, Q3: not a tower; filtered wherever
  code means a real tower). `spent` keeps meaning money
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
| `can_deploy(kind, cell)` | OUTCOME_REACHED, NO_CREW (off / not a crew kind), NOT_BUILDABLE, OCCUPIED, RESERVE_SHORT (reserve of `kind` < `post.crew`), NOT_NIGHT (phase != WAVE, last) |
| `deploy(kind, cell)` | new SimTower record (next id, `def = post_def` or the kind's override, L1, `post = true`, `crew_kind = kind`, `crew = post.crew`, `spent = 0`); `towers` / `tower_at`; log `[tick, "deploy", kind, cell]`; POST_DEPLOYED `{kind, cell, crew}`; CREW_CHANGED reason "deploy" |
| `release(t, reason)` | reserve of `t.crew_kind` (posts) or `t.def.id` (towers) += t.crew, CREW_CHANGED; used by sell and dawn |
| `on_dawn()` | posts in id order: erase from `towers` / `tower_at`, POST_REMOVED `{kind, cell, reason: "dawn"}`, `release(t, "dawn")` |

- **Build** (`Simulation.build_tower`, `simulation.gd:175-195`): `can_build` swaps
  `state.gold < def.cost` for `state.gold < build_price(def_id)` (same position, same reason
  order); apply pays `build_price` with one `GOLD_CHANGED "build"` and sets `t.spent = frame`
  for a crewed def (`def.cost` otherwise): the auto-hired crew money buys crew, not the tower.
  TOWER_BUILT `cost` = money paid (today's value with an empty reserve). Then
  `take_for_build(t)`.
- **Sell** (`sell_tower`, `simulation.gd:212-228`): after TOWER_SOLD, `release(t, "sell")`.
  `sell_refund` (`economy_system.gd:106-107`) is unchanged: `spent` already excludes crew.
- **Posts and other commands:** `can_sell_tower` (`simulation.gd:199-206`) and `can_upgrade`
  (`:253-275`) return `NOT_A_TOWER` for a post, right after `NO_SUCH_TOWER` (a post exists
  only at night, so a player meets it only through replay/debug; the check also keeps
  `upgrade_target` from indexing the post def's missing `levels[1]`). `set_target_priority` on
  a post is allowed (plain shooters pick targets). The sanity reserve of a post is 0 (mundane).
- **New `CommandResult` values**, appended after `OIL_FULL` (values never shift):
  `NO_CREW` (crew off or the kind has no crew), `RESERVE_SHORT` (reserve of the kind below
  `post.crew`), `NOT_A_TOWER` (sell / upgrade on a post).
- **New `SimEvent.Type` values**, appended last: `CREW_CHANGED`, id 0, `{kind, reserve, delta,
  reason: "hire" | "build" | "sell" | "deploy" | "dawn"}`; `POST_DEPLOYED`, id = the post,
  `{kind, cell, crew}`; `POST_REMOVED`, id = the post, `{kind, cell, reason: "dawn"}`. Posts do
  not emit TOWER_BUILT / TOWER_SOLD (they are not towers). Digests use the type *name*
  (`golden_runs.gd:134`), so appending changes nothing existing.
- **No RNG draw anywhere** (no new stream; Q5a).

### 2.4 Phase hooks and step order

- Dawn: `Simulation.on_dawn` gains one last line `_crew.on_dawn()` after
  `auto_restore_sanity()` (LT-99: "a new dawn action is one line here"). Events land before
  WAVE_CLEARED, as all dawn actions do. Off -> no-op.
- Dusk: nothing. Deploy is gated by phase (`WAVE`), not by a dusk action.
- Step: no change. Posts carry their weakness in their own stats, so crew adds no LT-105
  writer; the "[LT-32 crew posts]" mention in the slot-2 comment (`simulation.gd:83-86`) is
  removed. Posts read the channel like towers (light first, then LT-106 traits).
- `debug_end_night` reaches `on_dawn` through the director, so posts return there too.

### 2.5 Facade

One-line forwarders on Simulation (guard G4): `crew_need`, `build_price`, `can_hire`, `hire`,
`can_deploy`, `deploy`, `crew_reserve() -> Dictionary`, `post_def(kind) -> TowerDef`.
Constructed after `_economy` in `_init` (`simulation.gd:34-56`); crew does not reach combat.

## 3. Commands (LT-107 table)

Appended after `debug_end_night` in `COMMANDS` (`simulation.gd:487-504`), so the old key order
is a prefix:

```gdscript
	"hire": {"args": [TYPE_STRING], "can": &"can_hire", "apply": &"hire", "text": "hire"},
	"deploy": {"args": [TYPE_STRING, TYPE_VECTOR2I], "can": &"can_deploy", "apply": &"deploy",
		"text": "deploy"},
```

`CommandText` (`command_text.gd`):

- `TEXT` gains `NO_CREW: "no crew for this"`, `RESERVE_SHORT: "not enough crew"`,
  `NOT_A_TOWER: "a post, not a tower"`.
- `BY_COMMAND = {"deploy": {NOT_NIGHT: "only at night", OCCUPIED: "cell occupied"}, "hire":
  {NOT_BUILD_PHASE: "hire by day"}}`. (`OCCUPIED` repeats TEXT; drop it if the slice prefers
  only real overrides.)
- `GameCommands` (`scenes/game_commands.gd`): `hire(kind)` and `deploy(kind, cell)` one-liners
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
  the tower rows stay as today ("only by day") and a **post section** is added above them: one
  row per crew kind, "Post: 2 Harpooners (4 in reserve)", enabled when `can_deploy(kind, cell)`
  is OK; pressing calls `game.commands.deploy(kind, cell)`. Every row shows the same post stats
  (plain riflemen) in the hover card. Title "Deploy a reserve post" or the shared refusal
  ("Not enough crew"). `REFRESH_ON` (`:32-33`) gains CREW_CHANGED, POST_DEPLOYED, POST_REMOVED
  and the phase events.
- **Post view** (`ui/tower_panel.gd` `_rebuild` :163-214, or a short `PostPanel` if the panel's
  tower assumptions get in the way; the slice decides by the size of the `if t.post` branch):
  title "Reserve post", "2 Harpooners, fighting as riflemen", the stats row of `post_def`, the
  target priority row, "Returns to the reserve at dawn". No upgrade or sell rows.
- **Board** (`scenes/board/entity_layer.gd` `_draw_tower` :147-178 dispatches to a new
  `_draw_post`): two or three small rifleman figures (dots with a musket stroke) in the
  mundane attack colour, no plate, no glyph, no tower border; shots use the rifleman's
  attack visual. `scenes/board/look_catalog.gd` keys tower looks by def id and derives a
  default from the level's mode, so def `"post"` gets the plain shooter shot look with no
  entry; an entry is added only if the playtest wants a distinct shot.
- **End screen:** none.

## 5. Bots (`tools/bot_runs.gd`, LT-101 strategies data)

- `tools/bot/strategies.json` tunables: `crew_reserve` (extra crew to hold by day, default 0)
  and `post_min_live` (default 4). Both **optional** in `StrategyTable._read_tunables`
  (`strategy_table.gd:113-128`; today every key is required), so existing strategy-table test
  texts stay valid.
- `BotStrategies.act` (`bot_strategies.gd:53-105`):
  - night branch (`:55-57`): after `night_flare(sim)`, `night_posts(sim)`: when live enemies >=
    `post_min_live`, for each crew kind in crew.json order while its reserve >= `post.crew`,
    deploy at `Placement.best_cell(cfg, sim, "rifleman", score_cache)` (a post fights as a
    rifleman, so the rifleman's cell score is the right one; `best_cell` reads `cfg.towers[id]`,
    so it gets the rifleman id, not `"post"`) until refused.
  - day: builds as today (auto-hire inside `build_tower`; same money as crew off). After the
    build loop breaks, `hire_reserve(sim, strat)`: hire the **cheapest** crew kind (posts are
    the same whoever stands there; today rifleman, $20) while total reserve < `crew_reserve`
    and `hire` is OK.
  - `build_first` counts (`sim.state.towers.size()`) are taken by day, when no post exists, so
    they need no filter; the slice still counts real towers only (`not t.post`) for clarity.
- With `crew_reserve = 0` the reserve stays empty (bots never sell), no post is ever deployed,
  and every RUN line equals the crew-off run: the control for §8 and a cheap test.
- `bot_runs.gd` `_play` (:166-306): RUN gains `"crew_hired"`, `"crew_gold"` (from
  `GOLD_CHANGED reason "hire"`), `"posts"` (POST_DEPLOYED count) and `"post_shots"` (SHOT from
  a post). `towers_final` skips posts (a run lost at night would list them otherwise). Header comment documents
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

- **Real towers:** crew belongs to the `SimTower`. `t.crew` travels with a lifted tower
  unchanged; lifting neither releases nor kills crew. A lifted tower keeps its id; LT-117 moves
  it by updating `t.cell`, `t.pos` and `tower_at` (today `pos` is "set once when built",
  `sim_tower.gd:15`; LT-117 owns that change). LT-117 does not remove towers; if it ever does,
  it must call `CrewSystem.release(t, reason)` through the facade (crew back to the reserve,
  no money) and add the reason to CREW_CHANGED.
- **Posts (Q3b, owner decision a):** `tower_lift` never targets a post: LT-117's target choice
  (`TowerLiftTrait.near_tower`) skips `t.post`. Posts are not structures (Q3), so nothing is lifted, moved or disabled.
  If the owner picks Q3b (b) instead: a lifted post moves and is disabled like a tower, its
  `crew` / `crew_kind` stay with it, and at dawn it is removed and returns its men as any post.
- Other tower-targeting traits (LT-106 `tower_harass`) see posts as shooters (they write the
  channel; a post reads it) unless their own task says otherwise.

## 8. Lab plan (`tools/balance/`, CLAUDE.local.md rules)

20 seeds per arm, all strategies; report losses/20, "Where runs end" (mean wave reached) and
"Lighthouse HP left" (mean/median), plus mean `posts` and `crew_gold` from RUN lines.

1. **Control pair:** `lt32_crew_off` (`crew.json enabled: false`) vs `baseline` (crew on,
   `crew_reserve` 0). Expected: identical RUN lines. If they differ, stop: crew on is leaking
   into play without posts.
2. **Does night agency matter?** `crew_reserve`: baseline 0 vs arms 2 and 4, then double/halve
   from the first arm that moves the metric (2 -> 1 / 4). Read: wave reached and HP left rise
   with posts deployed > 0 (an arm with `posts` = 0 measured nothing).
3. **Post strength** (own stats, §2.1), with the reserve arm from step 2: `post.damage` 6 ->
   x2 12 / ÷2 3; then `post.range` 2.5 -> x2 5 / ÷2 1.25 (1.25 reaches only path-adjacent
   cells; still meaningful, so plain double/halve). Bisect toward the owner's feel target
   ("weaker than towers", noticeable) in 2-3 steps. `post.crew` 2 -> 1 / 4 only if hire money
   looks wrong next to the effect (it scales the price of a post).
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
| `sim/defs/crew_config.gd` | new | `CrewConfig`, `CrewKind`, `parse`, synthetic `post_def` via `TowerDef.Level.parse` (`tower_def.gd:220-299`) |
| `sim/config.gd` | consts :16-21, `_sections` :100-110, `_cross_checks` :114-115 | `CREW_FILE`, row `[CREW_FILE, _parse_crew, false]` last, `_check_crew`, `var crew`, `crew_on()` |
| `data/crew.json` | new | §2.1 |
| `sim/core/sim_state.gd` | vars :22-41 | `crew` reserve |
| `sim/core/sim_tower.gd` | vars :12-51 | `crew`, `crew_kind`, `post` |
| `sim/core/command_result.gd` | enum end :35 | `NO_CREW`, `RESERVE_SHORT`, `NOT_A_TOWER` |
| `sim/core/sim_event.gd` | enum `Type` end | `CREW_CHANGED`, `POST_DEPLOYED`, `POST_REMOVED` with doc comments |
| `sim/core/systems/crew_system.gd` | new | §2.3 |
| `sim/core/simulation.gd` | `_init` :34-56 | construct `_crew` |
| same | `step` comment :83-86 | drop "[LT-32 crew posts]" (no crew writer) |
| same | `can_build` :155-168, `build_tower` :175-195 | `build_price`, `t.spent = frame`, `take_for_build` |
| same | `can_sell_tower` :199-206, `can_upgrade` :253-275 | `NOT_A_TOWER` after `NO_SUCH_TOWER` |
| same | `sell_tower` :212-228 | `_crew.release(t, "sell")` |
| same | `on_dawn` :588-595 | `_crew.on_dawn()` last |
| same | `COMMANDS` :487-504 + forwarders | `hire`, `deploy` (§3) |
| `scenes/game_commands.gd` | after `fire_flare` :97-98 | `hire`, `deploy` one-liners |
| `ui/text/command_text.gd` | `TEXT` :9-35, `BY_COMMAND` :39-41 | §3 |

Read for context: `SimContext.day_only` / `log_command` / `next_id` (`sim_context.gd:43-60`),
`EconomySystem.add_gold` (`economy_system.gd:29-33`), `upgrade_branches` / `upgrade_target`
(`simulation.gd:231-246`, why the post needs `NOT_A_TOWER`), `GameConfig.from_dicts` (`config.gd:45-84`),
`EconomyConfig._parse_flare` (`economy_config.gd:267-286`, optional-block parse pattern).

Must-confirm in S2 (a `SimTower` that is not a tower): list every reader of `state.towers`
(`grep -rn "state.towers\|\.towers:" sim ui scenes tools`) and mark each as "shooter" (posts
included: combat, light, targeting, occupancy, render) or "real tower" (filter `not t.post`:
sell, upgrade, sanity reserve sums, bot `towers_final`, stats/upgrade UI). Report the list in
the slice result.

### S3 UI

| file | function (lines) | change |
|---|---|---|
| `ui/hud.gd` | `_ready` :78-202, `_rebuild` :234-251 | `CrewButton`, `_refresh_crew`, CREW_CHANGED mask |
| `ui/crew_panel.gd` | new | rows + hire buttons |
| `ui/side_panel.gd` | `_ready` :69-116, `_update_idle` :167+ | add `CrewPanel` view |
| `ui/tower_picker.gd` | `REFRESH_ON` :32-33, `refresh` :250-300, `_on_tower_pressed` :323-326 | build price; night post section (one row per crew kind) |
| `ui/tower_panel.gd` | `_rebuild` :163-214 | post view (or new `ui/post_panel.gd`) |
| `scenes/board/entity_layer.gd` | `_draw_tower` :147-178 | dispatch to new `_draw_post` (figures, no plate) |

Read: `LighthousePanel` (`ui/lighthouse_panel.gd`, 164 lines) as the panel template;
`TowerText.cost_text`.

### S4 bots

| file | function (lines) | change |
|---|---|---|
| `tools/bot/strategy_table.gd` | `TUNABLE_KEYS` :14, `_read_tunables` :113-128 | optional `crew_reserve`, `post_min_live` |
| `tools/bot/strategies.json` | `tunables` | the two keys |
| `tools/bot/bot_strategies.gd` | `act` :53-105 | `night_posts`, `hire_reserve` |
| `tools/bot_runs.gd` | header :1-67, `_play` :166-306 | RUN keys `crew_hired`, `crew_gold`, `posts`, `post_shots`; `towers_final` skips posts |
| `tools/balance/README.md` | variants | the crew-off variant note |

Read: `night_flare` (`bot_strategies.gd:125-138`), `Placement.best_cell` (`bot_placement.gd:13-48`).

### Behaviours the tests slice pins (each with a control)

1. Crew off (no crew.json): golden replay/trace byte-identical (control: make `build_price`
   ignore `crew_on()` with a crewed config copy -> crew-on test fails; golden itself is the
   no-regen check).
2. Build with empty reserve pays `def.cost` in one GOLD_CHANGED, no CREW_CHANGED; with reserve
   N pays `frame + max(0, need-N) * hire` (control: always charge `def.cost`).
3. `hire`: day only, money, reserve +1, logged, replays (control: drop `day_only`).
4. `deploy(kind, cell)`: night only, reserve of `kind` -`post.crew`, no money, POST_DEPLOYED,
   no TOWER_BUILT (control: allow by day).
5. A post fires with `post` stats whatever the crew kind (harpooner post shot = `post.damage`,
   no pierce), and the light writer still applies to it; `"post"` is not in `config.towers`
   (control: give the post the crew kind's tower def).
6. Dawn removes every post and returns its men before WAVE_CLEARED; sell / upgrade on a post
   return `NOT_A_TOWER` (controls: drop the `on_dawn` line; drop the `NOT_A_TOWER` check ->
   upgrade script error / sell at night still refused, so pin it through `can_upgrade`).
7. Sell returns crew and refunds 70 % of frame + upgrades (control: refund from `def.cost`).
8. Bot with `crew_reserve = 0`: RUN lines equal crew off on 3 seeds (control: default 2).

## 10. Slicing

The work fits three code slices plus tests, verify, measure and playtest; no task split is
needed. Slices and their one exit criterion:

| slice | phase | exit criterion |
|---|---|---|
| S1 | design | this note approved by the owner (Q1-Q8, T1; revised Q3/Q4 and Q3b) |
| S2 | implement: sim + data + commands (§9 S2) | `hire`/`deploy` replay through `COMMANDS` and golden replay passes without regen |
| S3 | implement: UI (§9 S3) | a game window (`-- --mute`) shows hire by day and a post (figures, not a tower) deployed at night that is gone at dawn (screenshot pair) |
| S4 | implement: bots (§9 S4) | `crew_reserve = 0` RUN lines equal crew-off RUN lines on 3 seeds; `crew_reserve = 2` deploys posts |
| S5 | tests | behaviours 1-8 pinned, each control fails when reverted |
| S6 | verify | targeted suites + controls in a throwaway worktree, findings reported |
| S7 | measure | lab steps 1-3 (§8) table delivered to the owner |
| S8 | owner playtest | owner verdict recorded |

Follow-up backlog candidates (not in LT-32):

- **Day as an untimed planning and build phase** (owner, 2026-11-22): no day timer; night
  starts only by "Light the lamp". Touches LT-27 §1.2 early-night luck (it is computed from
  seconds left), the bots' `call_wave` and the lab's tick cap.
- **Lighthouse rooms for the reserve/crew** (owner, 2026-11-22): rooms built in the lighthouse
  that house the reserve and carry reserve upgrades (training rooms, an alchemist's workshop,
  etc.). Natural home for per-kind post stats (the parser already accepts a per-kind `post`
  override) and post upgrades.
- Crew losses / desertion (Q5 b/c); occult crew ("scholars") (Q1 b); upkeep wage (Q7 b);
  barricades deployed from the reserve (LT-18).

## 11. Owner decisions (2026-11-22)

- Q1, Q2, Q5, Q6, Q7, Q8, T1: as recommended.
- Q3: revised. Owner, verbatim: "Резервисты - это по сути не башня, а просто временный пост, он
  не должен выглядеть как башня, по умолчанию это просто стрелки, потом есть следующие идеи:
  сделать день как фазу планирования и строительства без таймера времени. Для
  резервистов/экипажа будем строить в маяке отдельные помещения, возможно там будут апгрейды
  для резервистов, типа тренировочных комнат, или мастерских алхимика и тп". Applied in Q3 (a).
- Q4: dawn removal and return to the reserve kept; no post-to-tower path.
- Q3b: (a), posts are immune to `tower_lift` (§7).
