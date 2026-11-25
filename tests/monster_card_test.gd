class_name MonsterCardTest
extends GdUnitTestSuite
## LT-66 §5 / §9 (5, 6, 7, 17): the monster card. Its text comes from the snapshot record and
## its def only, so a real and a fake enemy of one kind read the same and a revealed fake
## differs by the title suffix alone (6); Speed and Armour show the current and the base
## value, Madness shows iff the record is madness-buffed (7); the card closes when its enemy
## dies, leaks or dissolves, or leaves the snapshot (5); its HP follows damage on stepped
## frames (17). The selection model writes `enemy_id` only through show_enemy. Expected
## strings are built from the record's own numbers and the card's own constants, so a
## swapped field (speed for base_speed) shows.

const DEF := "cultist"

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self)
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


## A live enemy of `def_id` at the start of its route, in a fresh snapshot.
func _enemy(def_id := DEF, fake := false) -> SimEnemy:
	var e := _game.sim.enemy_by_id(_game.sim.spawn_enemy(def_id, fake))
	GameFixture.sync(_game)
	return e


func _card() -> MonsterCard:
	return _game.monster_card


## Every label of the card (title, kind, each shown row's key and value) in order.
func _texts() -> Array:
	var c := _card()
	var out := [c.title_label.text, c.kind_label.text]
	for row: String in MonsterCard.ROWS:
		out.append([c.keys[row].visible, c.keys[row].text, c.values[row].visible,
			c.values[row].text])
	return out


# --- 6: real and fake read the same ----------------------------------------------------------

func test_a_real_and_a_fake_of_one_kind_show_identical_text_in_every_label() -> void:
	var real := _enemy(DEF, false)
	var fake := _enemy(DEF, true)
	assert_bool(_game.snapshot.enemy(real.id) != null and _game.snapshot.enemy(fake.id) != null) \
		.is_true()
	_card().open_for(real.id)
	var real_texts := _texts()
	_card().close()
	_card().open_for(fake.id)
	var fake_texts := _texts()
	assert_array(fake_texts).is_equal(real_texts)
	assert_dict(MonsterCard.card_text(_game.snapshot.enemy(fake.id))) \
		.is_equal(MonsterCard.card_text(_game.snapshot.enemy(real.id)))


func test_a_revealed_fake_differs_only_by_the_hallucination_suffix_in_the_title() -> void:
	var real := _enemy(DEF, false)
	var fake := _enemy(DEF, true)
	fake.revealed = true
	GameFixture.sync(_game)
	var a := MonsterCard.card_text(_game.snapshot.enemy(real.id))
	var b := MonsterCard.card_text(_game.snapshot.enemy(fake.id))
	assert_str(b["title"]).is_equal(a["title"] + MonsterCard.HALLUCINATION_SUFFIX)
	assert_str(a["title"]).is_equal(_config.enemies[DEF].name)
	a.erase("title")
	b.erase("title")
	assert_dict(b).is_equal(a)
	_card().open_for(fake.id)
	assert_str(_card().title_label.text).is_equal(
		_config.enemies[DEF].name + MonsterCard.HALLUCINATION_SUFFIX)


# --- 7: Speed / Armour / Madness lines ---------------------------------------------------------

func test_speed_and_armour_show_the_current_value_and_the_base_value() -> void:
	var e := _enemy()
	e.speed_mult = 0.5
	e.armor_bonus = 3.0
	GameFixture.sync(_game)
	var r := _game.snapshot.enemy(e.id)
	assert_float(r.speed).is_not_equal(r.base_speed)  # the two must be told apart
	assert_float(r.armor).is_not_equal(r.def.armor)
	var t := MonsterCard.card_text(r)
	var speed: String = t["Speed"]
	var armour: String = t["Armour"]
	assert_str(speed.get_slice("(base", 0)).contains(TowerText.num(snappedf(r.speed, 0.01)))
	assert_str(speed.get_slice("(base", 1)).contains(TowerText.num(snappedf(r.base_speed, 0.01)))
	assert_str(armour.get_slice("(base", 0)).contains(TowerText.num(r.armor))
	assert_str(armour.get_slice("(base", 1)).contains(TowerText.num(r.def.armor))
	assert_str(t["Speed"]).is_not_equal(
		MonsterCard.card_text(_game.snapshot.enemy(_enemy().id))["Speed"])


func test_the_madness_row_shows_iff_the_record_is_madness_buffed() -> void:
	var e := _enemy()
	_card().open_for(e.id)
	assert_bool(_card().keys["Madness"].visible).is_false()
	assert_bool(_card().values["Madness"].visible).is_false()
	assert_bool(MonsterCard.card_text(_game.snapshot.enemy(e.id)).has("Madness")).is_false()
	e.madness_buffed = true
	GameFixture.sync(_game)
	_card().on_stepped()
	assert_bool(_card().keys["Madness"].visible).is_true()
	assert_bool(_card().values["Madness"].visible).is_true()
	assert_str(_card().values["Madness"].text).is_equal(MonsterCard.MADNESS_TEXT)
	e.madness_buffed = false
	GameFixture.sync(_game)
	_card().on_stepped()
	assert_bool(_card().values["Madness"].visible).is_false()


func test_ground_and_flying_follow_the_def_for_every_enemy() -> void:
	for id: String in _config.enemies:
		var e := _enemy(id)
		var kind: String = MonsterCard.card_text(_game.snapshot.enemy(e.id))["kind"]
		assert_bool(kind.begins_with("Flying")).override_failure_message(id) \
			.is_equal(_config.enemies[id].flying)


# --- 5: the card closes with its enemy ---------------------------------------------------------

func test_the_card_closes_on_died_leaked_and_dissolved_for_its_own_id_only() -> void:
	for type: SimEvent.Type in [SimEvent.Type.DIED, SimEvent.Type.LEAKED,
			SimEvent.Type.FAKE_DISSOLVED]:
		var e := _enemy()
		var other := _enemy()
		_card().open_for(e.id)
		_card().on_event(SimEvent.new(type, 0, other.id, {}))
		assert_bool(_card().visible).override_failure_message("other id, type %d" % type).is_true()
		_card().on_event(SimEvent.new(type, 0, e.id, {}))
		assert_bool(_card().visible).override_failure_message("own id, type %d" % type).is_false()
		assert_int(_card().enemy_id).is_equal(0)
		assert_int(_game.selection.enemy_id).is_equal(0)


func test_the_card_closes_when_its_enemy_leaves_the_snapshot() -> void:
	var e := _enemy()
	_card().open_for(e.id)
	assert_bool(_card().visible).is_true()
	_game.sim.apply_damage(e.id, 1.0e9, "test", true)
	GameFixture.sync(_game)
	assert_object(_game.snapshot.enemy(e.id)).is_null()
	_card().on_stepped()
	assert_bool(_card().visible).is_false()


func test_opening_for_an_id_not_in_the_snapshot_does_nothing() -> void:
	_card().open_for(987654)
	assert_bool(_card().visible).is_false()
	assert_int(_game.selection.enemy_id).is_equal(0)


# --- 17: HP follows damage on stepped frames --------------------------------------------------

func test_hp_follows_damage_on_a_stepped_frame_and_an_unchanged_card_does_not_rebuild() -> void:
	var e := _enemy()
	_card().open_for(e.id)
	var rebuilt := _card().rebuild_count
	var before: String = _card().values["HP"].text
	_card().on_stepped()
	assert_int(_card().rebuild_count).is_equal(rebuilt)  # same key: no rebuild
	assert_int(e.id).is_equal(_card().enemy_id)
	# one tick of the clock: Game.advance steps the sim, rebuilds the snapshot, then the card
	_game.sim.apply_damage(e.id, 2.0, "test", true)
	_game.advance(1.0 / SimTime.TICK_RATE * 1.5)
	var r := _game.snapshot.enemy(e.id)
	assert_object(r).is_not_null()
	assert_float(r.hp).is_less(r.max_hp)
	assert_str(_card().values["HP"].text).is_not_equal(before)
	assert_str(_card().values["HP"].text).is_equal(MonsterCard.card_text(r)["HP"])
	assert_int(_card().rebuild_count).is_greater(rebuilt)


# --- selection ----------------------------------------------------------------------------------

func test_the_selection_enemy_is_written_only_by_show_enemy_and_reset_by_clear_and_show_cell() -> void:
	var s := SelectionModel.new()
	assert_int(s.enemy_id).is_equal(0)
	s.show_enemy(5)
	assert_int(s.enemy_id).is_equal(5)
	s.set_ring(2.0, "")  # ring, letter and cast keep the enemy
	s.set_preview(2.0, "R", "")
	s.set_cell(Vector2i(1, 1))
	assert_int(s.enemy_id).is_equal(5)
	s.show_cell(Vector2i(2, 2))
	assert_int(s.enemy_id).is_equal(0)
	s.show_enemy(6)
	s.clear()
	assert_int(s.enemy_id).is_equal(0)
	var e := _enemy()
	_card().open_for(e.id)
	assert_int(_game.selection.enemy_id).is_equal(e.id)
	_card().close()
	assert_int(_game.selection.enemy_id).is_equal(0)
