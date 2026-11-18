extends SceneTree
## LT-73: regenerates tests/fixtures/golden_digests.json, the digests the golden replay test
## (tests/golden_replay_test.gd) compares against. Run through scripts/golden-regen.sh, only
## for an approved behaviour change (see tests/fixtures/README.md). Never edit the file by hand.


func _initialize() -> void:
	_main()


func _main() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame  # root is in the tree only once the main loop runs (the frame run needs it)
	var runs: Dictionary = await GoldenRuns.compute_all(root, true)
	var names := runs.keys()
	names.sort()
	var ordered := {}
	for n in names:
		ordered[n] = runs[n]
	var doc := {
		"_generated_by": "scripts/golden-regen.sh (tools/golden/regen.gd); do not edit by hand",
		"data_dir": GoldenRuns.GOLDEN_DATA,
		"bucket_ticks": GoldenRuns.BUCKET_TICKS,
		"runs": ordered,
	}
	var path := ProjectSettings.globalize_path(GoldenRuns.PINNED)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", path, ": ", FileAccess.get_open_error())
		quit(1)
		return
	f.store_string(JSON.stringify(doc, "  ", false) + "\n")
	f.close()
	print("golden: wrote %d runs to %s in %d ms" % [runs.size(), path, Time.get_ticks_msec() - t0])
	quit(0)
