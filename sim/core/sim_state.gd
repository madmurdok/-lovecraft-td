class_name SimState
extends RefCounted
## Everything the simulation knows; scenes read it directly, read-only (design note LT-4 §1.4).

enum Outcome {NONE, WON, LOST}
## Wave flow (LT-5). NONE = no WaveDirector attached (tests with ScriptedSpawner);
## DONE = the last wave was cleared (the win follows in the same tick).
enum Phase {NONE, BUILD, WAVE, DONE}
## Sanity thresholds, sanest first (GDD §5.3; sanity.json `thresholds`). Derived from
## `sanity` by Simulation.sanity_state_for; MADNESS only at exactly 0 (LT-10).
enum SanityState {LUCID, WHISPERS, FRAYING, MADNESS}

var tick := 0  ## completed steps; the first step() runs tick 1
var outcome := Outcome.NONE  ## once not NONE, step() is a no-op
var lighthouse_hp := 0
var map: MapDef
var enemies: Array[SimEnemy] = []  ## id order
var next_id := 1  ## shared by every entity; never reused
var command_log: Array = []  ## [tick, command...] entries (LT-5/LT-6 add commands)
## Money (shown as "$", LT-27 §2; the name stays `gold`): from economy.starting_gold; never
## negative.
var gold := 0
## LT-27 §1.3: relic kind -> count in the stash (every economy kind, config order). Changes
## only when a real token arrives (or at dawn) and on sell_relics.
var relics: Dictionary[String, int] = {}
## LT-27 §1.3: tokens in flight, id order; real and ghost tokens alike.
var relic_tokens: Array[RelicToken] = []
var next_token_id := 1  ## relic token ids; separate from next_id, never reused
## LT-47 (LT-46 P2): charges in flight (thrown, fuse burning), throw order = id order.
var blasts: Array[SimBlast] = []
var next_blast_id := 1  ## blast ids; separate from next_id, never reused
## LT-52 (LT-46 P10): allied units, id order (ids from next_id); gone ones are dropped in
## slot 8.
var allies: Array[SimAlly] = []
var night_luck := 1.0  ## LT-27 §1.2: set by call_wave, reset to 1.0 at dawn
var towers: Array[SimTower] = []  ## id order
var tower_at: Dictionary[Vector2i, int] = {}  ## occupied cell -> tower id
var phase := Phase.NONE
var wave_index := 0  ## 1-based number of the current or last started wave; 0 before wave 1
var waves_total := 0  ## number of waves in waves.json (0 without a WaveDirector)
var build_ticks_left := 0  ## ticks until the next wave starts by itself; 0 outside BUILD
var sanity := 0.0  ## global pool, 0..sanity_cap; from sanity.start (LT-10)
## LT-23 §1: sanity.max minus the sanity_reserve of every standing tower, floored at 0.
## Changes only in build/upgrade/sell; sanity never rises above it.
var sanity_cap := 0.0
var sanity_state := SanityState.LUCID  ## derived from `sanity`; changes emit SANITY_STATE_CHANGED
## LT-30 (LT-26 §1.1, §1.2): lighthouse level, 0 = L1 (index into economy.beam.levels).
var lighthouse_level := 0
## Base beam direction, a unit vector as two 64-bit floats (Vector2 is 32-bit); starts
## pointing left ("sweep": at sweep_edges[0], Simulation._start_beam). Beam i is it rotated
## by i x 360° / beam count (Simulation.beam_count).
var beam_dx := -1.0
var beam_dy := 0.0
## The base direction before this tick's turn (render interpolation, like prev_distance).
var prev_beam_dx := -1.0
var prev_beam_dy := 0.0
var beam_sign := 1.0  ## "sweep" pattern: +1 / -1, the current swing direction
## LT-30 §1.1: ticks the current flare still burns (0 = none) and ticks until the next
## flare may be fired; both count down in slot 2.
var flare_ticks_left := 0
var flare_cooldown_ticks := 0
## LT-30 §1.2: lamp oil in stock, 0..economy.oil.cap; 0 without an `oil` block.
var oil := 0
