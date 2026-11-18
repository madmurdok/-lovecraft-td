class_name MuteArgTest
extends GdUnitTestSuite
## LT-87: `-- --mute` mutes the Master bus; a run without it leaves the bus unmuted.

var _master := 0


func before_test() -> void:
	_master = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(_master, false)


func after_test() -> void:
	AudioServer.set_bus_mute(_master, false)


func test_mute_arg_mutes_the_master_bus() -> void:
	assert_bool(Game.apply_mute_arg(PackedStringArray(["--seed=3", "--mute"]))).is_true()
	assert_bool(AudioServer.is_bus_mute(_master)).is_true()


func test_no_mute_arg_leaves_the_bus_unmuted() -> void:
	assert_bool(Game.apply_mute_arg(PackedStringArray(["--sandbox", "--sanity=0"]))).is_false()
	assert_bool(AudioServer.is_bus_mute(_master)).is_false()
