class_name WaveDirector
extends SimSpawner
## Wave flow from waves.json (GDD §4, §8; LT-5): BUILD (timer) -> WAVE n -> BUILD -> ...
## -> DONE after the last wave is cleared. Writes SimState.phase / wave_index /
## waves_total / build_ticks_left and emits BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED.
##
## Timing, all in ticks: the run starts in BUILD with build_ticks_left = build phase ticks.
## Each BUILD tick decrements it; the tick it reaches 0 starts the wave, and that same tick
## is wave tick 0. A wave called early (Simulation.call_wave, between ticks) makes the next
## tick wave tick 0. Spawn event k of a group fires on wave tick
## ticks(delay) + k * ticks(interval); events due on one tick fire in group order, then
## event order. A pack enemy expands into its pack inside Simulation.spawn_enemy.
##
## A wave is cleared when every group has fired all its events and no real enemy is alive
## (fakes do not count). Clearing pays award_wave_bonus(n) before the outcome check, so the
## last wave's bonus is paid in the same tick WON is set; the between-waves sanity regen
## (award_wave_sanity) follows the bonus the same way.

var _waves: WavesConfig
var _build_ticks: int
var _done := false
var _wave_tick := 0  ## wave tick the next spawn pass handles
var _fired: Array[int] = []  ## per group of the current wave: spawn events already fired


func _init(waves: WavesConfig) -> void:
	_waves = waves
	_build_ticks = SimTime.ticks(waves.build_phase_seconds)


## Starts the run in the build phase before wave 1 (tick 0).
func attach(sim: Simulation) -> void:
	sim.state.waves_total = _waves.waves.size()
	_begin_build(sim)


func tick(sim: Simulation) -> void:
	var s := sim.state
	if s.phase == SimState.Phase.BUILD:
		s.build_ticks_left -= 1
		if s.build_ticks_left > 0:
			return
		start_wave(sim, false)
	if s.phase == SimState.Phase.WAVE:
		_spawn_due(sim)


func end_tick(sim: Simulation) -> void:
	var s := sim.state
	if s.phase != SimState.Phase.WAVE or s.lighthouse_hp == 0:
		return  # a wave that ends with the lighthouse is not survived: no bonus
	if not _all_fired(s):
		return
	for e in s.enemies:
		if not e.is_fake:
			return
	_clear_wave(sim)


## LT-12 §2: in a wave whose groups are not all fired, one entry per unfired spawn event
## (`count - fired` copies of the group's enemy id, group order); otherwise empty, so no
## fake spawns in BUILD/DONE or after the wave's last real spawn (owner decision Q2).
func fake_candidates(sim: Simulation) -> Array[String]:
	var out: Array[String] = []
	var s := sim.state
	if s.phase != SimState.Phase.WAVE or _all_fired(s):
		return out
	var groups := _current_wave(s).groups
	for gi in groups.size():
		for _k in groups[gi].count - _fired[gi]:
			out.append(groups[gi].enemy_id)
	return out


## True once the last wave is cleared.
func is_exhausted() -> bool:
	return _done


## Ends the build phase and starts the next wave. `early` = called by the player
## (Simulation.call_wave), which then spawns from the next tick on; otherwise the timer
## ran out and the caller spawns in this same tick. Only valid in BUILD.
func start_wave(sim: Simulation, early: bool) -> void:
	var s := sim.state
	if s.phase != SimState.Phase.BUILD:
		return
	var ticks_left := s.build_ticks_left
	s.phase = SimState.Phase.WAVE
	s.wave_index += 1
	s.build_ticks_left = 0
	_wave_tick = 0
	_fired.clear()
	_fired.resize(_current_wave(s).groups.size())
	_fired.fill(0)
	sim.emit_event(SimEvent.Type.WAVE_STARTED, 0,
		{"wave": s.wave_index, "early": early, "ticks_left": ticks_left})


func _begin_build(sim: Simulation) -> void:
	var s := sim.state
	s.phase = SimState.Phase.BUILD
	s.build_ticks_left = _build_ticks
	sim.emit_event(SimEvent.Type.BUILD_STARTED, 0,
		{"next_wave": s.wave_index + 1, "ticks": _build_ticks})


func _spawn_due(sim: Simulation) -> void:
	var groups := _current_wave(sim.state).groups
	for gi in groups.size():
		var g := groups[gi]
		var delay := SimTime.ticks(g.delay)
		var interval := SimTime.ticks(g.interval)
		while _fired[gi] < g.count and delay + _fired[gi] * interval <= _wave_tick:
			_fired[gi] += 1
			sim.spawn_enemy(g.enemy_id)
	_wave_tick += 1


func _all_fired(s: SimState) -> bool:
	var groups := _current_wave(s).groups
	for gi in groups.size():
		if _fired[gi] < groups[gi].count:
			return false
	return true


func _clear_wave(sim: Simulation) -> void:
	var s := sim.state
	var n := s.wave_index
	sim.dissolve_fakes("wave_end")  # LT-12 §5: before the bonus, so BUILD starts with none
	var bonus := sim.award_wave_bonus(n)
	sim.award_wave_sanity()  # LT-10: regen.between_waves, also for the last wave
	sim.emit_event(SimEvent.Type.WAVE_CLEARED, 0, {"wave": n, "bonus": bonus})
	if n < s.waves_total:
		_begin_build(sim)
	else:
		s.phase = SimState.Phase.DONE
		_done = true


func _current_wave(s: SimState) -> WavesConfig.Wave:
	return _waves.waves[s.wave_index - 1]
