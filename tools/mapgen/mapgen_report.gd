extends SceneTree
## LT-130 §5: the P1 map generator report. Run through scripts/mapgen-report.sh. Args after `--`:
##   --preset small|large  (default small: 24x16, 1-3 entries; large: 32x18, 1-4 entries)
##   --seeds N (default 1000)  --from S (default 1)  --params f.json (MapGenParams.from_dict
##   overrides on the preset)  --maps (one line per map)  --out report.json
## Reject rates: attempt-level = rejected attempts / all attempts; seed-level = seeds that hit the
## attempt cap (no map) / seeds. Time per map = one generate() call, retries included.

const DEFAULT_SEEDS := 1000
const PASS_REJECT_PCT := 30.0
const PASS_P95_MS := 200.0


func _initialize() -> void:
	quit(_main())


func _main() -> int:
	var args := OS.get_cmdline_user_args()
	var preset := _opt(args, "--preset", "large")
	var seeds := int(_opt(args, "--seeds", str(DEFAULT_SEEDS)))
	var first := int(_opt(args, "--from", "1"))
	var params_file := _opt(args, "--params", "")
	var out_file := _opt(args, "--out", "")
	var per_map := args.has("--maps")
	var p: MapGenParams
	match preset:
		"small":
			p = MapGenParams.p1_small()
		"large":
			p = MapGenParams.p1_large()
		_:
			printerr("unknown --preset \"%s\" (small|large)" % preset)
			return 2
	if seeds < 1:
		printerr("--seeds must be >= 1")
		return 2
	if params_file != "":
		var loaded := load_params(params_file, p)
		if loaded.is_empty():
			return 2
		p = loaded[0]
	print("mapgen-report: preset=%s %s %dx%d entries %d-%d seeds %d..%d attempt_cap=%d%s" % [
		preset, p.grid_kind, p.width, p.height, p.entries_min, p.entries_max, first,
		first + seeds - 1, p.attempt_cap, " params=" + params_file if params_file != "" else ""])
	var ms: Array[float] = []
	var accepted := 0
	var capped := 0
	var attempts_total := 0
	var rejected_total := 0
	var first_pass := 0
	var hist := {}
	var slow_seed := first
	var slow_ms := -1.0
	var lines: Array[String] = []
	for s in range(first, first + seeds):
		var t0 := Time.get_ticks_usec()
		var res := MapGenerator.generate(s, p)
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		ms.append(dt)
		if dt > slow_ms:
			slow_ms = dt
			slow_seed = s
		attempts_total += res.attempts
		rejected_total += res.rejects.size()
		if res.map != null:
			accepted += 1
			if res.attempts == 1:
				first_pass += 1
		else:
			capped += 1
		for r in res.rejects:
			for code in r:
				hist[code] = int(hist.get(code, 0)) + 1
		var line := map_line(s, res)
		lines.append(line)
		if per_map:
			print(line)
	ms.sort()
	var mean := 0.0
	for v in ms:
		mean += v
	mean /= ms.size()
	var p95: float = ms[mini(ms.size() - 1, int(ceil(0.95 * ms.size())) - 1)]
	var reject_pct := 100.0 * rejected_total / maxi(1, attempts_total)
	var seed_pct := 100.0 * capped / seeds
	print("--- summary (preset %s)" % preset)
	print("seeds: %d  accepted: %d  cap failures: %d" % [seeds, accepted, capped])
	print("reject rate, attempt-level (rejected attempts / all attempts): %.1f%% (%d / %d)" % [
		reject_pct, rejected_total, attempts_total])
	print("reject rate, seed-level (seeds with no map / seeds): %.1f%%" % seed_pct)
	print("first-attempt pass rate: %.1f%%" % (100.0 * first_pass / seeds))
	var codes := PackedStringArray()
	for code in MapGenerator.REASON_ORDER:
		if hist.has(code):
			codes.append("%s x%d" % [code, hist[code]])
	print("rejects by reason (an attempt counts under each code it failed): %s" % (
		", ".join(codes) if not codes.is_empty() else "none"))
	print("ms per map: mean %.1f  p95 %.1f  max %.1f (seed %d)" % [mean, p95, slow_ms, slow_seed])
	var ok := reject_pct < PASS_REJECT_PCT and p95 < PASS_P95_MS and capped == 0
	print("bar (reject < %.0f%%, p95 < %.0f ms, no cap failure): %s" % [
		PASS_REJECT_PCT, PASS_P95_MS, "PASS" if ok else "FAIL"])
	if out_file != "":
		var doc := {
			"preset": preset, "params": p.to_dict(), "from": first, "seeds": seeds,
			"accepted": accepted, "cap_failures": capped,
			"reject_rate_attempt_pct": reject_pct, "reject_rate_seed_pct": seed_pct,
			"first_attempt_pass_pct": 100.0 * first_pass / seeds, "rejects_by_reason": hist,
			"ms_mean": mean, "ms_p95": p95, "ms_max": slow_ms, "maps": lines,
		}
		var f := FileAccess.open(out_file, FileAccess.WRITE)
		if f == null:
			printerr("cannot write ", out_file, ": ", FileAccess.get_open_error())
			return 1
		f.store_string(JSON.stringify(doc, "  ", false) + "\n")
		f.close()
	return 0


## `seed attempts digest[0:12] len=[..] chokes=[..] blind=[..] share=.. detours=[..] rejected=[..]`
## (rejected: reason codes of every rejected attempt before the accepted one, "|"-joined).
static func map_line(s: int, res: MapGenerator.GenResult) -> String:
	var rej := PackedStringArray()
	for r in res.rejects:
		rej.append("|".join(r))
	var head := "seed %d attempts %d " % [s, res.attempts]
	if res.map == null:
		return head + "NO MAP rejected=[%s] %s" % [", ".join(rej), res.error]
	var rep := res.report
	var chokes: Array[int] = []
	for c in rep.chokepoints:
		chokes.append(c.size())
	var det := PackedStringArray()
	for d: Array in rep.detour_deltas:
		var best := ChokepointMetric.SKIPPED
		var cut := 0
		for v: int in d:
			cut += 1 if v == ChokepointMetric.CUT else 0
			best = maxi(best, v)
		det.append("best %s cut %d" % [str(best) if best >= 0 else "none", cut])
	return head + "%s len=%s chokes=%s blind=%s share=%d detours=[%s] rejected=[%s]" % [
		res.map.digest().substr(0, 12), rep.lengths, chokes, rep.max_blind,
		rep.shared_share_pct, ", ".join(det), ", ".join(rej)]


## Loads `path` over `base`; [] (after printing why) when it cannot be read or is invalid.
static func load_params(path: String, base: MapGenParams) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		printerr("cannot read --params file ", path)
		return []
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary):
		printerr("--params file is not a JSON object: ", path)
		return []
	var r := MapGenParams.from_dict(d, base)
	if r["params"] == null:
		printerr("--params errors: ", "; ".join(r["errors"]))
		return []
	return [r["params"]]


static func _opt(args: PackedStringArray, key: String, fallback: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback
