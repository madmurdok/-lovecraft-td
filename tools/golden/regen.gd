extends SceneTree
## LT-73: regenerates tests/fixtures/golden_digests.json, the digests the golden replay test
## (tests/golden_replay_test.gd) compares against, and (LT-102) tests/fixtures/golden_trace/:
## the trace manifest of every run and the full text of GoldenRuns.TRACE_FULL_RUNS. Run
## through scripts/golden-regen.sh, only for an approved behaviour change (see
## tests/fixtures/README.md). Never edit these files by hand.


func _initialize() -> void:
	_main()


func _main() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame  # root is in the tree only once the main loop runs (the frame run needs it)
	var runs: Dictionary = await GoldenRuns.compute_all(root, true)
	var names := runs.keys()
	names.sort()
	var ordered := {}
	var traces := {}
	for n in names:
		# The trace goes to its own files: golden_digests.json keeps its LT-73 shape.
		traces[n] = runs[n]["trace"]
		runs[n].erase("trace")
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
	if not _write_trace(traces):
		quit(1)
		return
	print("golden: wrote %d runs to %s in %d ms" % [runs.size(), path, Time.get_ticks_msec() - t0])
	quit(0)


## Rewrites GoldenRuns.TRACE_DIR: drops every old .jsonl, writes the full-text runs and the
## manifest (keys sorted). Prints each run's trace size, pinned or not.
func _write_trace(traces: Dictionary) -> bool:
	var dir := ProjectSettings.globalize_path(GoldenRuns.TRACE_DIR)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("cannot create ", dir)
		return false
	for old in DirAccess.get_files_at(dir):
		if old.ends_with(".jsonl") and DirAccess.remove_absolute(dir.path_join(old)) != OK:
			printerr("cannot remove ", dir.path_join(old))
			return false
	var manifest_runs := {}
	var total := 0
	var pinned := 0
	for n: String in traces:
		var t: Dictionary = traces[n]
		var file: Variant = null
		total += int(t["bytes"])
		if t["text"] != null:
			file = GoldenRuns.trace_file_name(n)
			if not _write(dir.path_join(file), t["text"]):
				return false
			pinned += int(t["bytes"])
		manifest_runs[n] = {"file": file, "lines": t["lines"], "sha256": t["sha256"]}
		print("golden trace %s: %d lines, %d bytes%s" % [n, t["lines"], t["bytes"],
			" (full text)" if file != null else ""])
	var manifest := {
		"_generated_by": "scripts/golden-regen.sh (tools/golden/regen.gd); do not edit by hand",
		"format": GoldenRuns.TRACE_FORMAT,
		"version": GoldenRuns.TRACE_VERSION,
		"runs": manifest_runs,
	}
	if not _write(dir.path_join(GoldenRuns.TRACE_MANIFEST),
			JSON.stringify(manifest, "  ", true) + "\n"):
		return false
	print("golden trace: %d bytes of full text pinned; all %d runs as text: %d bytes" % [
		pinned, traces.size(), total])
	return true


func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", path, ": ", FileAccess.get_open_error())
		return false
	f.store_string(text)
	f.close()
	return true
