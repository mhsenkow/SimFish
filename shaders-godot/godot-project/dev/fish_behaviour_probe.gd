# Fish behaviour probe — what a ten-second watch of the tank would show,
# as numbers.
#
#   Godot --headless --path . res://dev/fish_behaviour_probe.tscn
#
# WHY THIS EXISTS. "The fish look robotic" is not something a smoke can
# assert, and a still capture cannot show it: a frame of lockstep fish and a
# frame of living ones can be identical. What differs is the time series —
# whether fish of one species all speed up together, whether they sort
# themselves into the depth their species keeps, whether a guppy male ever
# actually displays, whether the shoal ever splits. This drives the real game
# (main.tscn, like dev/visual_capture.gd) and reports those, per species.
#
# It runs headless: the dummy renderer is fine because nothing here is
# visual, and the per-frame CPU cost it reports is then the sim's own.
#
# SAVE SAFETY. Same switch as visual_capture: TankConfig.capture_mode blocks
# SaveManager load/save. world.gd ALSO deletes the active slot's state.json
# when it is incompatible with the current preset (world.gd `_ready`,
# clear_active_state) and that path is not gated on capture_mode, so this
# probe refuses to run at all when the active slot holds a saved tank.
#
# Environment:
#   FISH_PROBE_SCENARIO   scenario id (default valli_jungle)
#   FISH_PROBE_STOCK      "species:count,..." top-up to at least these counts
#   FISH_PROBE_WARMUP_S   sim seconds before sampling (default 25)
#   FISH_PROBE_SAMPLE_S   sim seconds to sample (default 40)
#   FISH_PROBE_OUT        report path (default user://fish_behaviour_probe.txt)
#   FISH_PROBE_SPLIT      1 = also time frames with fish / sim processing off

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")

const SAMPLE_DT: float = 0.1
# Two fish closer than this belong to the same shoal for the cluster count.
const SHOAL_LINK: float = 1.35

var _main: Node = null
var _sim: Node = null
var _world: Node = null
var _warmup: float = 25.0
var _sample_len: float = 40.0
var _t_sim: float = 0.0
var _sample_acc: float = 0.0
var _topped_up: bool = false
var _stock: Dictionary = {}
var _out: String = "user://fish_behaviour_probe.txt"
# instance_id -> {species, speeds:[], fracs:[], yaws:[], display:int, flags}
var _track: Dictionary = {}
var _cluster_counts: Array = []
var _frame_ms: Array = []
var _last_tick_usec: int = 0
var _boot_frames: int = 0
# Adult male livebearers: samples, and how many were blocked by each gate of
# FishLifeBouts.livebearer_steer (stress, hunger, partner, burst, startle).
var _lb_gate: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var _o2_acc: float = 0.0
# FISH_PROBE_SPLIT=1: after sampling, 60 frames with every fish's _process
# off, then 60 with the sim node's processing off, so the report can say where
# a slow frame goes (fish per-frame motion vs the 10 Hz sim tick).
var _split: bool = false
var _split_phase: int = 0
var _split_frames: int = 0
var _split_ms: Array = [[], []]
var _o2_n: int = 0


func _ready() -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null and saves.has_method("has_state_for_active_slot") \
			and bool(saves.call("has_state_for_active_slot")):
		push_error("[fish_probe] active save slot holds a tank; refusing to run " \
			+ "(world.gd would clear it on a preset mismatch)")
		get_tree().quit(2)
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		push_error("[fish_probe] TankConfig autoload missing")
		get_tree().quit(1)
		return
	cfg.set("capture_mode", true)
	if cfg.has_method("reset_to_defaults"):
		cfg.reset_to_defaults()
	var id: String = _env("FISH_PROBE_SCENARIO", "valli_jungle")
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == id:
			ScenarioPickerScript.apply_scenario(sc, cfg)
	_warmup = _env("FISH_PROBE_WARMUP_S", "25").to_float()
	_sample_len = _env("FISH_PROBE_SAMPLE_S", "40").to_float()
	_out = _env("FISH_PROBE_OUT", _out)
	_split = _env("FISH_PROBE_SPLIT", "0") == "1"
	for part in _env("FISH_PROBE_STOCK", "").split(",", false):
		var kv: PackedStringArray = part.split(":")
		if kv.size() == 2:
			_stock[kv[0].strip_edges()] = kv[1].to_int()
	process_priority = 1000
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[fish_probe] scenario=", id, " warmup=", _warmup, " sample=", _sample_len)


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key).strip_edges()
	return fallback if v.is_empty() else v


func _process(dt: float) -> void:
	if _main == null:
		return
	_boot_frames += 1
	if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
		_main.call("_on_focus_in")
	_main.set("_hud_idle_seconds", 0.0)
	if _sim == null:
		var s: Variant = _main.get("_sim")
		if s is Node:
			_sim = s
		var w: Variant = _main.get("world")
		if w is Node:
			_world = w
		return
	var fish: Array = _sim.get("fish") as Array
	if fish == null or fish.is_empty():
		if _boot_frames > 3000:
			push_error("[fish_probe] no fish after boot")
			get_tree().quit(1)
		return
	if not _topped_up:
		_topped_up = true
		_top_up(fish)
		return
	var ts: float = float(_sim.get("time_scale"))
	var sdt: float = dt * (ts if ts > 0.0 else 1.0)
	_t_sim += sdt
	if _t_sim < _warmup:
		return
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec > 0:
		_frame_ms.append(float(now - _last_tick_usec) / 1000.0)
	_last_tick_usec = now
	_sample_acc += sdt
	if _sample_acc >= SAMPLE_DT:
		_sample_acc -= SAMPLE_DT
		_sample(fish)
	if _t_sim >= _warmup + _sample_len:
		if _split and _split_phase < 3:
			_split_step(fish, now)
			return
		_finish(fish)


func _split_step(fish: Array, now: int) -> void:
	if _split_phase == 0:
		_split_phase = 1
		for f in fish:
			if is_instance_valid(f):
				f.set_process(false)
		return
	(_split_ms[_split_phase - 1] as Array).append(_frame_ms.back())
	_frame_ms.pop_back()
	_split_frames += 1
	if _split_frames < 60:
		return
	_split_frames = 0
	if _split_phase == 1:
		for f in fish:
			if is_instance_valid(f):
				f.set_process(true)
		_sim.set_process(false)
		_sim.set_physics_process(false)
		_split_phase = 2
	else:
		_sim.set_process(true)
		_sim.set_physics_process(true)
		_split_phase = 3
	_last_tick_usec = now


func _top_up(fish: Array) -> void:
	if _stock.is_empty() or _world == null or not _world.has_method("_spawn_fish_at"):
		return
	var have: Dictionary = {}
	for f in fish:
		if is_instance_valid(f):
			have[String(f.species)] = int(have.get(String(f.species), 0)) + 1
	var tc: Script = load("res://scripts/tank_config.gd")
	var lib: Dictionary = tc.get("SPECIES_LIBRARY") if tc != null else {}
	for sp in _stock.keys():
		var entry: Dictionary = lib.get(sp, {})
		if entry.is_empty():
			push_warning("[fish_probe] unknown species " + String(sp))
			continue
		var need: int = int(_stock[sp]) - int(have.get(sp, 0))
		for i in maxi(need, 0):
			var g: Dictionary = (entry.get("genome", {}) as Dictionary).duplicate(true)
			g["sex"] = i % 2
			_world.call("_spawn_fish_at", g, _world.call("_sample_fish_spawn_pos", g))
	print("[fish_probe] topped up to ", _stock)


func _column() -> Vector2:
	# Holistic #081: same water-column ends as FishDepthBands / World.
	var floor_y: float = 1.6
	var surf: float = 6.5
	if _world != null:
		if _world.get("SUBSTRATE_DEPTH") != null:
			floor_y = float(_world.SUBSTRATE_DEPTH)
		elif _sim != null and _sim.get("substrate_top_y") != null:
			floor_y = float(_sim.substrate_top_y)
		if _world.get("WATER_HEIGHT") != null:
			surf = float(_world.WATER_HEIGHT)
	elif _sim != null and _sim.get("substrate_top_y") != null:
		floor_y = float(_sim.substrate_top_y)
	return Vector2(floor_y, maxf(surf, floor_y + 0.5))


func _sample(fish: Array) -> void:
	var col: Vector2 = _column()
	var live: Array = []
	const _DepthBands = preload("res://scripts/fish_depth_bands.gd")
	for f in fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		live.append(f)
		var key: int = f.get_instance_id()
		var trk: Dictionary = _track.get(key, {})
		if trk.is_empty():
			trk = {"species": String(f.species), "sex": int(f.sex),
				"mat": int(f.maturity), "speeds": [], "fracs": [], "yaws": [],
				"display": 0, "court": 0, "peck": 0, "cruise": 0, "dbout": 0, "follow": 0, "hung": 0.0, "strs": 0.0, "dspd": 0.0, "max_speed": float(f.max_speed)}
			_track[key] = trk
		var v: Vector3 = f.velocity
		(trk["speeds"] as Array).append(v.length())
		(trk["fracs"] as Array).append(_DepthBands.frac_from_y(f.global_position.y, col.x, col.y))
		(trk["yaws"] as Array).append(atan2(f.heading.x, -f.heading.z))
		if bool(f.get("_courtship_flare")):
			trk["court"] = int(trk["court"]) + 1
		var disp: Variant = f.get("_lb_display_t")
		if disp != null and float(disp) > 0.0:
			trk["display"] = int(trk["display"]) + 1
		# Diagnostics: how often the fish is free to bout at all, and why not.
		if int(f.current_mode) == 0:
			trk["cruise"] = int(trk["cruise"]) + 1
		if f.get("_bout_kind") != null and int(f.get("_bout_kind")) == 2:
			trk["dbout"] = int(trk["dbout"]) + 1
		if f.get("_lb_target") != null:
			trk["follow"] = int(trk["follow"]) + 1
		trk["hung"] = float(trk["hung"]) + float(f.hunger)
		trk["strs"] = float(trk["strs"]) + float(f.stress)
		if f.get("_bout_kind") != null and int(f.get("_bout_kind")) == 2:
			trk["dspd"] = float(trk["dspd"]) + v.length() / maxf(float(f.max_speed), 0.1)
		if bool(f.get("is_livebearer")) and int(f.sex) == 0 and int(f.maturity) == 2:
			_lb_gate[0] += 1
			if float(f.stress) >= 0.75: _lb_gate[1] += 1
			if float(f.hunger) >= 0.6: _lb_gate[2] += 1
			if f.partner != null: _lb_gate[3] += 1
			if float(f.burst_remaining) > 0.0: _lb_gate[4] += 1
			if float(f.get("_startle_remaining")) > 0.0: _lb_gate[5] += 1
		var peck: Variant = f.get("_peck_t")
		if peck != null and float(peck) > 0.0:
			trk["peck"] = int(trk["peck"]) + 1
	_cluster_counts.append(_clusters(live))
	if _sim != null and _sim.get("dissolved_o2") != null:
		_o2_acc += float(_sim.get("dissolved_o2"))
		_o2_n += 1


# Single-linkage shoal count per species, summed. A tank where every species
# is one blob that never splits reads 1 per species forever.
func _clusters(live: Array) -> Dictionary:
	var by_sp: Dictionary = {}
	for f in live:
		var sp: String = String(f.species)
		if not by_sp.has(sp):
			by_sp[sp] = []
		(by_sp[sp] as Array).append(f.global_position)
	var out: Dictionary = {}
	var l2: float = SHOAL_LINK * SHOAL_LINK
	for sp in by_sp.keys():
		var pts: Array = by_sp[sp]
		var n: int = pts.size()
		var parent: PackedInt32Array = PackedInt32Array()
		parent.resize(n)
		for i in n:
			parent[i] = i
		for i in n:
			for j in range(i + 1, n):
				if (pts[i] as Vector3).distance_squared_to(pts[j]) < l2:
					var a: int = _root(parent, i)
					var b: int = _root(parent, j)
					if a != b:
						parent[a] = b
		var roots: Dictionary = {}
		for i in n:
			roots[_root(parent, i)] = true
		out[sp] = roots.size()
	return out


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


static func _pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var s: Array = arr.duplicate()
	s.sort()
	return float(s[clampi(int(q * float(s.size() - 1)), 0, s.size() - 1)])


static func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var t: float = 0.0
	for x in arr:
		t += float(x)
	return t / float(arr.size())


static func _corr(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n < 8:
		return 0.0
	var ma: float = 0.0
	var mb: float = 0.0
	for i in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab: float = 0.0
	var saa: float = 0.0
	var sbb: float = 0.0
	for i in n:
		var da: float = float(a[i]) - ma
		var db: float = float(b[i]) - mb
		sab += da * db
		saa += da * da
		sbb += db * db
	if saa < 1e-9 or sbb < 1e-9:
		return 0.0
	return sab / sqrt(saa * sbb)


func _finish(fish: Array) -> void:
	var lines := PackedStringArray()
	var cfg := get_node_or_null("/root/TankConfig")
	var scenario_id: String = _env("FISH_PROBE_SCENARIO", "valli_jungle")
	var seed_v: int = 0
	var time_scale: float = 1.0
	if _sim != null:
		if _sim.get("tank_seed") != null:
			seed_v = int(_sim.get("tank_seed"))
		if _sim.get("time_scale") != null:
			time_scale = float(_sim.get("time_scale"))
	var tier: String = String(cfg.get("device_tier")) if cfg != null else ""
	var pop: Dictionary = {}
	for fsh in fish:
		if fsh == null or not is_instance_valid(fsh):
			continue
		var sp: String = String(fsh.get("species")) if fsh.get("species") != null else "?"
		pop[sp] = int(pop.get(sp, 0)) + 1
	# HOLISTIC #005 — reproducible header: seed, population, time scale, tier, scenario.
	lines.append("fish_behaviour_probe  scenario=%s  seed=%d  time_scale=%.2f  tier=%s  fish=%d  warmup=%.0fs  sampled=%.0fs" % [
		scenario_id, seed_v, time_scale, tier if tier != "" else "default",
		fish.size(), _warmup, _sample_len])
	lines.append("population  %s" % JSON.stringify(pop))
	lines.append("samples_per_track_hz=%.1f  sample_dt=%.2f  build=%s" % [
		1.0 / SAMPLE_DT, SAMPLE_DT,
		String(ProjectSettings.get_setting("application/config/version", ""))])
	var fm: Array = _frame_ms
	lines.append("frame_ms  mean %.2f  p50 %.2f  p95 %.2f  p99 %.2f  n=%d" % [
		_mean(fm), _pct(fm, 0.5), _pct(fm, 0.95), _pct(fm, 0.99), fm.size()])
	var by_sp: Dictionary = {}
	for key in _track.keys():
		var trk: Dictionary = _track[key]
		var sp: String = String(trk["species"])
		if not by_sp.has(sp):
			by_sp[sp] = []
		(by_sp[sp] as Array).append(trk)
	lines.append("%-18s %3s  %-17s %-22s %6s %6s %6s %6s %6s %6s %5s %5s" % [
		"species", "n", "depth p10/50/90", "speed mean/cv", "hover", "dart",
		"turn/s", "lock", "shoals", "disp%", "crt%", "peck%"])
	for sp in by_sp.keys():
		var trs: Array = by_sp[sp]
		var fracs: Array = []
		var speeds: Array = []
		var hover: int = 0
		var dart: int = 0
		var turn_acc: float = 0.0
		var turn_n: int = 0
		var disp: int = 0
		var court: int = 0
		var peck: int = 0
		var samples: int = 0
		var d_cruise: int = 0
		var d_dbout: int = 0
		var d_follow: int = 0
		var d_hung: float = 0.0
		var d_strs: float = 0.0
		var d_dspd: float = 0.0
		for trk in trs:
			var ms: float = maxf(float(trk["max_speed"]), 0.1)
			fracs.append_array(trk["fracs"])
			var sps: Array = trk["speeds"]
			speeds.append_array(sps)
			samples += sps.size()
			for s in sps:
				if float(s) < ms * 0.12:
					hover += 1
				elif float(s) > ms * 0.85:
					dart += 1
			var yaws: Array = trk["yaws"]
			for i in range(1, yaws.size()):
				turn_acc += absf(wrapf(float(yaws[i]) - float(yaws[i - 1]), -PI, PI)) / SAMPLE_DT
				turn_n += 1
			disp += int(trk["display"])
			court += int(trk["court"])
			peck += int(trk["peck"])
			d_cruise += int(trk["cruise"])
			d_dbout += int(trk["dbout"])
			d_follow += int(trk["follow"])
			d_hung += float(trk["hung"])
			d_strs += float(trk["strs"])
			d_dspd += float(trk["dspd"])
		var sp_mean: float = _mean(speeds)
		var var_acc: float = 0.0
		for s in speeds:
			var_acc += (float(s) - sp_mean) * (float(s) - sp_mean)
		var cv: float = sqrt(var_acc / maxf(float(speeds.size()), 1.0)) / maxf(sp_mean, 1e-4)
		# Lockstep: mean pairwise correlation of the speed series. Robotic
		# schools speed up and slow down together (~0.5+); living ones don't.
		var lock_acc: float = 0.0
		var lock_n: int = 0
		for i in trs.size():
			for j in range(i + 1, mini(trs.size(), i + 6)):
				lock_acc += _corr(trs[i]["speeds"], trs[j]["speeds"])
				lock_n += 1
		var shoal_ns: Array = []
		for cc in _cluster_counts:
			shoal_ns.append(int((cc as Dictionary).get(sp, 0)))
		var sh_mean: float = _mean(shoal_ns)
		var sh_var: float = 0.0
		for c in shoal_ns:
			sh_var += (float(c) - sh_mean) * (float(c) - sh_mean)
		sh_var = sqrt(sh_var / maxf(float(shoal_ns.size()), 1.0))
		var denom: float = maxf(float(samples), 1.0)
		lines.append("%-18s %3d  %4.2f/%4.2f/%4.2f    %5.2f / %4.2f          %5.1f%% %5.1f%% %6.2f %6.2f %4.1f±%3.1f %5.1f %5.1f %5.1f" % [
			sp, trs.size(), _pct(fracs, 0.1), _pct(fracs, 0.5), _pct(fracs, 0.9),
			sp_mean, cv, 100.0 * hover / denom, 100.0 * dart / denom,
			turn_acc / maxf(float(turn_n), 1.0), lock_acc / maxf(float(lock_n), 1.0),
			sh_mean, sh_var, 100.0 * disp / denom, 100.0 * court / denom,
			100.0 * peck / denom])
		lines.append("   diag  cruise-mode %4.1f%%  dart-bout %4.1f%%  pursuing %4.1f%%  hunger %4.2f  stress %4.2f  dart-speed %4.2f of max" % [
			100.0 * d_cruise / denom, 100.0 * d_dbout / denom, 100.0 * d_follow / denom,
			d_hung / denom, d_strs / denom, d_dspd / maxf(float(d_dbout), 1.0)])
	lines.append("adult-male livebearer samples %d  blocked: stress %d  hunger %d  partner %d  burst %d  startle %d   mean O2 %.2f" % [
		_lb_gate[0], _lb_gate[1], _lb_gate[2], _lb_gate[3], _lb_gate[4], _lb_gate[5],
		_o2_acc / maxf(float(_o2_n), 1.0)])
	if _split:
		lines.append("split frame_ms  fish _process off: %.2f   sim off (fish on): %.2f" % [
			_mean(_split_ms[0]), _mean(_split_ms[1])])
	var text: String = "\n".join(lines) + "\n"
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print(text)
	print("[fish_probe] wrote ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)
