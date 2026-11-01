class_name SimBlast
extends RefCounted
## LT-47 (LT-46 P2): a thrown charge waiting for its fuse. Queued by Simulation._fire_towers,
## settled in slot 5b (Simulation._settle_blasts) at `detonate_tick`: every live enemy
## (fakes too; flyers only when not `ground_only`) within `radius` cells of `at` is hit.

var id: int  ## from SimState.next_blast_id
var tower: int  ## the throwing tower's id (it may be sold before the blast)
var source: String  ## the throwing tower's def id: kill credit and bleed source
var at: Vector2  ## blast centre in cell units (the predicted target position)
var throw_tick: int
var detonate_tick: int
var damage: float  ## per hit, before armor (lit, madness and crit already applied)
var radius: float  ## cells
var ground_only: bool
## The throwing level's effects (read-only): on-hit effects such as bleed come from here.
var effects: Dictionary = {}
