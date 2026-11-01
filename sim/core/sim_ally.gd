class_name SimAlly
extends RefCounted
## LT-52 (LT-46 P10): an allied unit on the board, e.g. a Summoning Circle ghoul. Spawned by
## Simulation.spawn_ally; ticked in slot 2 (expiry, hold), slot 3 (Simulation._move_allies:
## chase, contact) and slot 5 (Simulation._ally_combat: trade damage); removed in slot 8 once
## `gone`. Free position in cell units (not on a route). Not tied to a tower kind, so
## later allies (LT-32 crew) reuse it with `tower` 0.

var id: int  ## shared entity id counter (SimState.next_id)
var tower: int  ## the summoning tower's id; 0 = none (it may be sold: then the unit is gone)
var source: String  ## kill credit passed to apply_damage (the tower def id)
var home: Vector2  ## leash centre, cell units (the spot it was summoned at)
var leash: float  ## cells: engages only enemies whose position is within this of `home`
var pos: Vector2  ## cell units
var prev_pos: Vector2  ## pos before this tick's move (render interpolation)
var hp: float
var max_hp: float
var dps: float  ## damage per second dealt to the held enemy, before armor
var speed: float  ## cells per second
var flying: bool  ## engages flyers too; a ground unit (false) engages ground enemies only
var summon_tick: int
var expires_tick: int  ## gone at the start of this tick (slot 2); 0 = no lifetime
## The enemy it holds (in contact, <= Simulation.ALLY_CONTACT cells): -1 = none. One unit
## holds at most one enemy and an enemy is held by at most one unit.
var held_id := -1
var target_id := -1  ## the enemy it chases this tick (render); -1 = none (heading home)
var gone := false  ## killed, expired or dismissed this tick; removed in slot 8


func is_live() -> bool:
	return not gone
