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
#   FISH_PROBE_MOTION_N   fish per species given 30 Hz pose tracks (default 4)
#   FISH_PROBE_MAX_FPS    Engine.max_fps (HOLISTIC #099; 0 = uncapped)
#   FISH_PROBE_TIME_SCALE sim.time_scale after boot (default leave alone)
#   FISH_PROBE_FIXED_SEED force sim.tank_seed for paired matrix runs
#
# Motion quality (CREATURE_MOTION_700 #85-#89 #92 #100 #119), appended after
# the behaviour table: up to FISH_PROBE_MOTION_N fish per species get 30 Hz
# pose tracks (root, head and tail tips, every pivot channel), resampled to an
# even grid and scored with MotionMetrics - jerk, heading kinks, arc breaks,
# head/body -> tail phase lag, tail-beat Hz, Strouhal, pectoral twin
# correlation, neighbour pose correlation and snaps - plus p10/p50/p90 of
# speed, turn rate and bout length from the 10 Hz samples.

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")

const SAMPLE_DT: float = 0.1
# Two fish closer than this belong to the same shoal for the cluster count.
const SHOAL_LINK: float = 1.35
# Motion tracks (#100): pose sampling step, and the thresholds the counts use.
const MOTION_DT: float = 1.0 / 30.0
const SNAP_ROT: float = 0.9          # rad in one 1/30 s step on a pivot channel
const SNAP_POS: float = 0.25         # units in one step of the root, outside bursts
const KINK_SLACK: float = 1.3        # x max_turn_rate before a yaw step is a kink
const MOTION_CHANNELS: PackedStringArray = ["head_ry", "body_ry", "tail_ry", "dorsal_rx",
	"pec_l_rz", "pec_r_rz", "bank_rx", "bank_ry", "bank_rz"]

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
var _motion_n: int = 4
var _motion_acc: float = 0.0
var _motion_t: float = 0.0
# instance_id -> {species, max_turn, len, t, pos, yaw, lat, speed, exempt, ch:{}}
var _motion: Dictionary = {}
var _motion_count: Dictionary = {}
var _fps_knobs_applied: bool = false
var _path_len_total: float = 0.0
var _path_prev: Dictionary = {}  # instance_id -> Vector3
var _tank_age_start: float = -1.0


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
	_motion_n = maxi(0, _env("FISH_PROBE_MOTION_N", "4").to_int())
	var max_fps_s: String = _env("FISH_PROBE_MAX_FPS", "")
	if not max_fps_s.is_empty():
		Engine.max_fps = maxi(0, max_fps_s.to_int())
	for part in _env("FISH_PROBE_STOCK", "").split(",", false):
		var kv: PackedStringArray = part.split(":")
		if kv.size() == 2:
			_stock[kv[0].strip_edges()] = kv[1].to_int()
	process_priority = 1000
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[fish_probe] scenario=", id, " warmup=", _warmup, " sample=", _sample_len,
		" max_fps=", Engine.max_fps)


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
	# HOLISTIC #099 — apply paired-run knobs once sim exists.
	if not _fps_knobs_applied:
		_fps_knobs_applied = true
		var ts_env: String = _env("FISH_PROBE_TIME_SCALE", "")
		if not ts_env.is_empty() and _sim.get("time_scale") != null:
			_sim.set("time_scale", maxf(0.25, ts_env.to_float()))
		var seed_env: String = _env("FISH_PROBE_FIXED_SEED", "")
		if not seed_env.is_empty() and _sim.get("tank_seed") != null:
			_sim.set("tank_seed", seed_env.to_int())
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
	_motion_t += sdt
	_motion_acc += sdt
	if _motion_acc >= MOTION_DT and _t_sim < _warmup + _sample_len:
		_motion_acc = fmod(_motion_acc, MOTION_DT)
		_sample_motion(fish)
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
		_sim.set_physics_process(false)
		_sim.set_physics_process(false)
		_split_phase = 2
	else:
		_sim.set_physics_process(true)
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
				"display": 0, "court": 0, "peck": 0, "cruise": 0, "dbout": 0, "follow": 0, "hung": 0.0, "strs": 0.0, "dspd": 0.0, "max_speed": float(f.max_speed),
				"flow_n": 0, "flow_up": 0, "flow_acc": 0.0, "flow_rel": 0.0, "bk": []}
			_track[key] = trk
		var v: Vector3 = f.velocity
		(trk["speeds"] as Array).append(v.length())
		(trk["fracs"] as Array).append(_DepthBands.frac_from_y(f.global_position.y, col.x, col.y))
		(trk["yaws"] as Array).append(atan2(f.heading.x, -f.heading.z))
		var bk_v: Variant = f.get("_bout_kind")
		(trk["bk"] as Array).append(int(bk_v) if bk_v != null else 0)
		# HOLISTIC #099 — horizontal path length for FPS/time-scale matrices.
		var prev_p: Variant = _path_prev.get(key, null)
		var pos_xz: Vector3 = Vector3(f.global_position.x, 0.0, f.global_position.z)
		if prev_p is Vector3:
			_path_len_total += pos_xz.distance_to(prev_p as Vector3)
		_path_prev[key] = pos_xz
		if _tank_age_start < 0.0 and _sim.get("tank_age_s") != null:
			_tank_age_start = float(_sim.get("tank_age_s"))
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
		# Water current: how much of it reaches this fish, and whether a fish
		# in real current is facing into it (rheotaxis).
		if _world != null and _world.has_method("sample_flow"):
			var fv: Vector3 = _world.sample_flow(f.global_position)
			var fl: float = fv.length()
			trk["flow_acc"] = float(trk["flow_acc"]) + fl
			if fl > 0.06:
				trk["flow_n"] = int(trk["flow_n"]) + 1
				var hd: Vector3 = f.heading
				if hd.length_squared() > 1e-6 and hd.normalized().dot(fv / fl) < -0.5:
					trk["flow_up"] = int(trk["flow_up"]) + 1
	_cluster_counts.append(_clusters(live))
	if _sim != null and _sim.get("dissolved_o2") != null:
		_o2_acc += float(_sim.get("dissolved_o2"))
		_o2_n += 1


# Arrow map of the current: a front-to-back average side view (x across, y
# up) and a top view at mid-depth (x across, z toward the viewer). Arrow
# = direction, case = speed (lower < 0.05 u/s <= UPPER), '#' = solid.
func _flow_map(ff: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var d: Vector3i = ff.grid_dims()
	var wc: WaterCurrent = ff.solver()
	var arrows := ["e", "n", "w", "s"]
	out.append("flow map: side view (rows = height, top row = surface)")
	for y in range(d.y - 1, -1, -1):
		var row := ""
		for x in d.x:
			var acc := Vector3.ZERO
			var solid_n: int = 0
			for z in d.z:
				if wc.is_solid_cell(x, y, z):
					solid_n += 1
					continue
				acc += ff.sample(ff.cell_center(x, y, z))
			if solid_n == d.z:
				row += "#"
				continue
			acc /= float(d.z - solid_n)
			row += _arrow(Vector2(acc.x, acc.y), arrows)
		out.append("  " + row)
	var ym: int = int(d.y / 2.0)
	out.append("flow map: top view at mid-depth (rows = back to front)")
	for z in d.z:
		var row2 := ""
		for x in d.x:
			if wc.is_solid_cell(x, ym, z):
				row2 += "#"
				continue
			var v: Vector3 = ff.sample(ff.cell_center(x, ym, z))
			row2 += _arrow(Vector2(v.x, -v.z), arrows)
		out.append("  " + row2)
	return out


func _arrow(v: Vector2, arrows: Array) -> String:
	var l: float = v.length()
	if l < 0.012:
		return "."
	var a: float = fposmod(atan2(v.y, v.x), TAU)
	var k: int = int(round(a / (PI * 0.5))) % 4
	var ch: String = arrows[k]
	return ch.to_upper() if l >= 0.05 else ch


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
	lines.append("samples_per_track_hz=%.1f  sample_dt=%.2f  build=%s  max_fps=%d" % [
		1.0 / SAMPLE_DT, SAMPLE_DT,
		String(ProjectSettings.get_setting("application/config/version", "")),
		Engine.max_fps])
	var fm: Array = _frame_ms
	lines.append("frame_ms  mean %.2f  p50 %.2f  p95 %.2f  p99 %.2f  n=%d" % [
		_mean(fm), _pct(fm, 0.5), _pct(fm, 0.95), _pct(fm, 0.99), fm.size()])
	# HOLISTIC #099 — locomotion integrity across frame caps / time scales.
	var age_end: float = float(_sim.get("tank_age_s")) if _sim != null and _sim.get("tank_age_s") != null else -1.0
	var age_delta: float = age_end - _tank_age_start if _tank_age_start >= 0.0 and age_end >= 0.0 else -1.0
	lines.append("holistic_099  path_len_xz=%.2f  tank_age_delta=%.2f  sample_sim_s=%.2f  tolerated: dart%%±8pp path±12%% age_delta≈sample" % [
		_path_len_total, age_delta, _sample_len])
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
		var fl_n: int = 0
		var fl_up: int = 0
		var fl_acc: float = 0.0
		for ftr in trs:
			fl_n += int(ftr.get("flow_n", 0))
			fl_up += int(ftr.get("flow_up", 0))
			fl_acc += float(ftr.get("flow_acc", 0.0))
		lines.append("   flow  mean current at fish %4.3f u/s  in-current %4.1f%%  facing upstream when in current %4.1f%%" % [
			fl_acc / denom, 100.0 * float(fl_n) / denom,
			100.0 * float(fl_up) / maxf(float(fl_n), 1.0)])
	lines.append("adult-male livebearer samples %d  blocked: stress %d  hunger %d  partner %d  burst %d  startle %d   mean O2 %.2f" % [
		_lb_gate[0], _lb_gate[1], _lb_gate[2], _lb_gate[3], _lb_gate[4], _lb_gate[5],
		_o2_acc / maxf(float(_o2_n), 1.0)])
	if _world != null and _world.get("_flow_field") != null:
		var ff: Variant = _world.get("_flow_field")
		var wc: WaterCurrent = ff.solver()
		var st: Dictionary = wc.stats()
		lines.append("water current  grid %dx%dx%d cell %.2f  max %.2f mean %.3f u/s  step %.2f ms (worker)  resid_div %.3f" % [
			wc.nx, wc.ny, wc.nz, wc.cell, float(st["max"]), float(st["mean"]),
			wc.last_step_ms, wc.residual_divergence()])
	if _world != null and _world.get("plants_root") != null:
		var forms: Dictionary = {}
		var heights: Dictionary = {}
		for pl in (_world.get("plants_root") as Node).get_children():
			if pl is Plant:
				var k: String = String((pl as Plant).leaf_form)
				forms[k] = int(forms.get(k, 0)) + 1
				heights[k] = int(heights.get(k, 0)) + int((pl as Plant).current_height)
		var parts := PackedStringArray()
		for k in forms:
			parts.append("%s %d (mean h %.1f)" % [k, int(forms[k]),
				float(heights[k]) / maxf(float(forms[k]), 1.0)])
		lines.append("plants  " + ", ".join(parts))
	# Small life: what makes a tank read as inhabited at a glance.
	if _world != null and _sim != null:
		var snail_kinds: Dictionary = {}
		var snail_sizes: Array = []
		var sroot: Variant = _sim.get("snails_root")
		if sroot is Node:
			for sn in (sroot as Node).get_children():
				var shp: Variant = sn.get("shell_shape")
				if shp != null:
					snail_kinds[String(shp)] = int(snail_kinds.get(String(shp), 0)) + 1
					snail_sizes.append(float((sn as Node3D).scale.x))
		var fry_n: int = 0
		for fsh in fish:
			if is_instance_valid(fsh) and int(fsh.get("maturity")) == 0:
				fry_n += 1
		var shrimp_v: Variant = _sim.get("shrimp")
		var eggs_v: Variant = _sim.get("eggs")
		var mf: int = int(_world.call("live_microfauna_count")) if _world.has_method("live_microfauna_count") else -1
		lines.append("small life  snails %s (scale p10/p50/p90 %.2f/%.2f/%.2f)  shrimp %d  fry %d  eggs %d  microfauna %d" % [
			JSON.stringify(snail_kinds), _pct(snail_sizes, 0.1), _pct(snail_sizes, 0.5), _pct(snail_sizes, 0.9),
			(shrimp_v as Array).size() if shrimp_v is Array else -1, fry_n,
			(eggs_v as Array).size() if eggs_v is Array else -1, mf])
	if _env("FISH_PROBE_FLOW_MAP", "0") == "1" and _world != null \
			and _world.get("_flow_field") != null:
		lines.append_array(_flow_map(_world.get("_flow_field")))
	if _split:
		lines.append("split frame_ms  fish _process off: %.2f   sim off (fish on): %.2f" % [
			_mean(_split_ms[0]), _mean(_split_ms[1])])
	lines.append_array(_motion_report())
	lines.append_array(_distribution_report())
	var text: String = "\n".join(lines) + "\n"
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print(text)
	print("[fish_probe] wrote ", ProjectSettings.globalize_path(_out))
	set_process(false)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


# ---- Motion quality (#85-#89 #92 #100 #119) --------------------------------

func _sample_motion(fish: Array) -> void:
	if _motion_n <= 0:
		return
	for f in fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var key: int = f.get_instance_id()
		var trk: Dictionary = _motion.get(key, {})
		if trk.is_empty():
			var sp: String = String(f.species)
			if int(_motion_count.get(sp, 0)) >= _motion_n:
				continue
			_motion_count[sp] = int(_motion_count.get(sp, 0)) + 1
			var ch: Dictionary = {}
			for c in MOTION_CHANNELS:
				ch[c] = []
			trk = {"species": sp, "max_turn": float(f.max_turn_rate),
				"max_speed": float(f.max_speed),
				"len": float(f.adult_voxel_scale) * 5.5 * float(f.body_elongation) * maxf(f.scale.x, 0.1),
				"t": [], "pos": [], "yaw": [], "lat": [], "speed": [], "exempt": [], "ch": ch}
			_motion[key] = trk
		var n3: Node3D = f
		var pos: Vector3 = n3.global_position
		(trk["t"] as Array).append(_motion_t)
		(trk["pos"] as Array).append(pos)
		(trk["yaw"] as Array).append(atan2(f.heading.x, -f.heading.z))
		var right: Vector3 = n3.global_transform.basis.x.normalized()
		(trk["lat"] as Array).append((MotionDebugOverlay.tail_tip_world(n3) - pos).dot(right))
		(trk["speed"] as Array).append(float(f.speed))
		var ex: bool = float(f.burst_remaining) > 0.0 or float(f.get("_startle_remaining")) > 0.0
		(trk["exempt"] as Array).append(1 if ex else 0)
		var ch2: Dictionary = trk["ch"]
		_push_rot(ch2, "head_ry", f.get("_head_pivot"), 1)
		_push_rot(ch2, "body_ry", f.get("_body_mid_pivot"), 1)
		_push_rot(ch2, "tail_ry", f.get("_tail_pivot"), 1)
		_push_rot(ch2, "dorsal_rx", f.get("_dorsal_pivot"), 0)
		_push_rot(ch2, "pec_l_rz", f.get("_pec_left_pivot"), 2)
		_push_rot(ch2, "pec_r_rz", f.get("_pec_right_pivot"), 2)
		_push_rot(ch2, "bank_rx", f.get("_bank_pivot"), 0)
		_push_rot(ch2, "bank_ry", f.get("_bank_pivot"), 1)
		_push_rot(ch2, "bank_rz", f.get("_bank_pivot"), 2)


static func _push_rot(ch: Dictionary, key: String, pivot: Variant, axis: int) -> void:
	var v: float = 0.0
	if pivot is Node3D and is_instance_valid(pivot):
		v = (pivot as Node3D).rotation[axis]
	(ch[key] as Array).append(v)


# Linear resample of (t, v) onto the absolute grid k*MOTION_DT. Returns
# [first grid index, values], so tracks that started at different times align.
static func _grid(t: PackedFloat32Array, v: PackedFloat32Array, angular: bool = false) -> Array:
	var out := PackedFloat32Array()
	var n: int = mini(t.size(), v.size())
	if n < 2:
		return [0, out]
	var src: PackedFloat32Array = v
	if angular:
		src = v.duplicate()
		for i in range(1, n):
			src[i] = src[i - 1] + wrapf(v[i] - v[i - 1], -PI, PI)
	var k0: int = int(ceil(t[0] / MOTION_DT))
	var k1: int = int(floor(t[n - 1] / MOTION_DT))
	var j: int = 0
	for k in range(k0, k1 + 1):
		var tk: float = float(k) * MOTION_DT
		while j < n - 2 and t[j + 1] < tk:
			j += 1
		var span: float = maxf(t[j + 1] - t[j], 1e-6)
		var a: float = clampf((tk - t[j]) / span, 0.0, 1.0)
		out.append(lerpf(src[j], src[j + 1], a))
	return [k0, out]


static func _grid3(t: PackedFloat32Array, v: PackedVector3Array) -> PackedVector3Array:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for p in v:
		xs.append(p.x)
		ys.append(p.y)
		zs.append(p.z)
	var gx: PackedFloat32Array = _grid(t, xs)[1]
	var gy: PackedFloat32Array = _grid(t, ys)[1]
	var gz: PackedFloat32Array = _grid(t, zs)[1]
	var out := PackedVector3Array()
	for i in gx.size():
		out.append(Vector3(gx[i], gy[i], gz[i]))
	return out


static func _std(v: PackedFloat32Array) -> float:
	if v.size() < 2:
		return 0.0
	var m: float = MotionMetrics.mean(v)
	var acc: float = 0.0
	for x in v:
		acc += (x - m) * (x - m)
	return sqrt(acc / float(v.size()))


# Grid index -> exempt flag (burst / startle) from the bracketing raw samples.
static func _exempt_grid(t: PackedFloat32Array, ex: PackedByteArray, k0: int, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	var j: int = 0
	for i in n:
		var tk: float = float(k0 + i) * MOTION_DT
		while j < t.size() - 1 and t[j + 1] <= tk:
			j += 1
		var e: bool = (j < ex.size() and ex[j] != 0) or (j + 1 < ex.size() and ex[j + 1] != 0)
		out[i] = 1 if e else 0
	return out


func _score_track(trk: Dictionary) -> Dictionary:
	# Tracks are plain Arrays while sampling (a packed array read out of a
	# Dictionary is a copy, so appending to it would be lost); pack them here.
	var t := PackedFloat32Array(trk["t"])
	var yg: Array = _grid(t, PackedFloat32Array(trk["yaw"]), true)
	var k0: int = int(yg[0])
	var yaw: PackedFloat32Array = yg[1]
	var n: int = yaw.size()
	if n < 16:
		return {}
	var pos: PackedVector3Array = _grid3(t, PackedVector3Array(trk["pos"]))
	var spd: PackedFloat32Array = _grid(t, PackedFloat32Array(trk["speed"]))[1]
	var lat: PackedFloat32Array = _grid(t, PackedFloat32Array(trk["lat"]))[1]
	var ch: Dictionary = {}
	for c in MOTION_CHANNELS:
		ch[c] = _grid(t, PackedFloat32Array((trk["ch"] as Dictionary)[c]))[1]
	var exempt: PackedByteArray = _exempt_grid(t, PackedByteArray(trk["exempt"]), k0, n)
	var exempt_idx := PackedInt32Array()
	for i in n:
		if exempt[i] != 0:
			exempt_idx.append(i)
	var minutes: float = maxf(float(n) * MOTION_DT / 60.0, 1e-3)
	var out: Dictionary = {"k0": k0, "minutes": minutes, "tail": ch["tail_ry"]}
	var j: Dictionary = MotionMetrics.jerk(pos, MOTION_DT)
	out["jerk_mean"] = float(j["mean"])
	out["jerk_p95"] = float(j["p95"])
	out["kinks"] = MotionMetrics.heading_kinks(yaw, MOTION_DT, float(trk["max_turn"]) * KINK_SLACK, exempt_idx)
	var step_len: float = maxf(MotionDebugOverlay.CURVATURE_MIN_STEP, float(trk["len"]) * 0.05)
	out["breaks"] = MotionMetrics.curvature_breaks(MotionDebugOverlay.decimate(pos, step_len),
		MotionDebugOverlay.CURVATURE_BREAK)
	var tail: PackedFloat32Array = ch["tail_ry"]
	var hz: float = MotionMetrics.dominant_hz(tail, MOTION_DT)
	out["hz"] = hz
	out["lag_ht"] = MotionMetrics.phase_lag(ch["head_ry"], tail, MOTION_DT, hz) \
		if _std(ch["head_ry"]) > 1e-3 and _std(tail) > 1e-3 and hz > 0.0 else NAN
	out["lag_bt"] = MotionMetrics.phase_lag(ch["body_ry"], tail, MOTION_DT, hz) \
		if _std(ch["body_ry"]) > 1e-3 and _std(tail) > 1e-3 and hz > 0.0 else NAN
	# Strouhal at cruise: outside bursts, moving at least 15% of max speed.
	var cruise_lat := PackedFloat32Array()
	var cruise_spd := PackedFloat32Array()
	var ms: float = float(trk["max_speed"])
	for i in n:
		if exempt[i] == 0 and spd[i] > ms * 0.15:
			cruise_lat.append(lat[i])
			cruise_spd.append(spd[i])
	out["st"] = NAN
	if cruise_lat.size() >= 30:
		var pc: Dictionary = MotionMetrics.percentiles(cruise_lat, [5, 95])
		out["st"] = MotionMetrics.strouhal(hz, float(pc[95]) - float(pc[5]), MotionMetrics.mean(cruise_spd))
	# Twin: right pectoral against the mirrored left.
	var neg_l := PackedFloat32Array()
	for v in (ch["pec_l_rz"] as PackedFloat32Array):
		neg_l.append(-v)
	out["pec_twin"] = MotionMetrics.correlation(ch["pec_r_rz"], neg_l) \
		if _std(ch["pec_r_rz"]) > 1e-4 and _std(neg_l) > 1e-4 else NAN
	var snaps: int = 0
	for c in MOTION_CHANNELS:
		snaps += MotionMetrics.snaps(ch[c], SNAP_ROT, true)
	for i in range(1, pos.size()):
		if exempt[i] == 0 and pos[i].distance_to(pos[i - 1]) > SNAP_POS:
			snaps += 1
	out["snaps"] = snaps
	return out


static func _nan_mean(vals: Array) -> float:
	var acc: float = 0.0
	var k: int = 0
	for v in vals:
		if is_nan(float(v)):
			continue
		acc += float(v)
		k += 1
	return acc / float(k) if k > 0 else NAN


static func _circ_mean(vals: Array) -> float:
	var c: float = 0.0
	var s: float = 0.0
	var k: int = 0
	for v in vals:
		if is_nan(float(v)):
			continue
		c += cos(float(v))
		s += sin(float(v))
		k += 1
	return fposmod(atan2(s, c), TAU) if k > 0 else NAN


static func _fmt(v: float, pattern: String, width: int) -> String:
	if is_nan(v):
		return "-".lpad(width)
	return (pattern % v).lpad(width)


func _motion_report() -> PackedStringArray:
	var out := PackedStringArray()
	if _motion.is_empty():
		return out
	out.append("motion quality (CREATURE_MOTION_700 #85-#89 #92 #100)  30 Hz pose tracks, up to %d fish/species; lag in units of pi (tail behind head/body), counts per fish-minute" % _motion_n)
	out.append("%-18s %2s %16s %7s %7s %10s %5s %5s %5s %6s %6s %6s" % [
		"species", "n", "jerk mean/p95", "kinks", "arcbrk", "lag h/b", "tailHz", "St",
		"pecTw", "nbrCor", "snaps", "min"])
	var by_sp: Dictionary = {}
	for key in _motion.keys():
		var trk: Dictionary = _motion[key]
		var sc: Dictionary = _score_track(trk)
		if sc.is_empty():
			continue
		var sp: String = String(trk["species"])
		if not by_sp.has(sp):
			by_sp[sp] = []
		(by_sp[sp] as Array).append(sc)
	for sp in by_sp.keys():
		var scs: Array = by_sp[sp]
		var f_jm: Array = []
		var f_jp: Array = []
		var f_hz: Array = []
		var f_st: Array = []
		var f_tw: Array = []
		var f_lh: Array = []
		var f_lb: Array = []
		var kinks: int = 0
		var breaks: int = 0
		var snaps: int = 0
		var minutes: float = 0.0
		for sc in scs:
			f_jm.append(sc["jerk_mean"])
			f_jp.append(sc["jerk_p95"])
			f_hz.append(sc["hz"])
			f_st.append(sc["st"])
			f_tw.append(sc["pec_twin"])
			f_lh.append(sc["lag_ht"])
			f_lb.append(sc["lag_bt"])
			kinks += int(sc["kinks"])
			breaks += int(sc["breaks"])
			snaps += int(sc["snaps"])
			minutes += float(sc["minutes"])
		# Neighbour pose correlation: tail yaw of tracked pairs, on the shared grid.
		var nbr: Array = []
		for i in scs.size():
			for jj in range(i + 1, scs.size()):
				nbr.append(_aligned_corr(scs[i], scs[jj]))
		var lag_h: float = _circ_mean(f_lh)
		var lag_b: float = _circ_mean(f_lb)
		var lag_s: String = "%s/%s" % [_fmt(lag_h / PI, "%.2f", 4).strip_edges(), _fmt(lag_b / PI, "%.2f", 4).strip_edges()]
		out.append("%-18s %2d %7.1f/%8.1f %7.1f %7.1f %10s %5s %5s %5s %6s %6.1f %6.2f" % [
			sp, scs.size(), _nan_mean(f_jm), _nan_mean(f_jp),
			float(kinks) / minutes, float(breaks) / minutes, lag_s,
			_fmt(_nan_mean(f_hz), "%.2f", 5).strip_edges(), _fmt(_nan_mean(f_st), "%.2f", 5).strip_edges(),
			_fmt(_nan_mean(f_tw), "%.2f", 5).strip_edges(), _fmt(_nan_mean(nbr), "%.2f", 6).strip_edges(),
			float(snaps) / minutes, minutes])
	out.append("   targets  St 0.2-0.4 at cruise (#88); lag: travelling wave = monotonic, standing = 0 or 1 (#87); pecTw/nbrCor well below 1 (#89); kinks/arcbrk/snaps near 0 outside bursts (#86 #83 #92)")
	return out


static func _aligned_corr(a: Dictionary, b: Dictionary) -> float:
	var ta: PackedFloat32Array = a["tail"]
	var tb: PackedFloat32Array = b["tail"]
	var ka: int = int(a["k0"])
	var kb: int = int(b["k0"])
	var start: int = maxi(ka, kb)
	var stop: int = mini(ka + ta.size(), kb + tb.size())
	if stop - start < 30:
		return NAN
	return MotionMetrics.correlation(ta.slice(start - ka, stop - ka), tb.slice(start - kb, stop - kb))


# #119: the spread, not just the mean. Speed and turn rate from the 10 Hz
# samples; bout lengths are runs of one _bout_kind, first and last run of
# each track dropped (they are cut off by the sampling window).
func _distribution_report() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("distributions (#119)  p10/p50/p90 from %.0f Hz samples" % (1.0 / SAMPLE_DT))
	out.append("%-18s %20s %20s %22s" % ["species", "speed u/s", "turn rad/s", "bout s (n)"])
	var by_sp: Dictionary = {}
	for key in _track.keys():
		var trk: Dictionary = _track[key]
		var sp: String = String(trk["species"])
		if not by_sp.has(sp):
			by_sp[sp] = {"speed": [], "turn": [], "bout": []}
		var acc: Dictionary = by_sp[sp]
		for v in trk["speeds"]:
			(acc["speed"] as Array).append(float(v))
		var yaws: Array = trk["yaws"]
		for i in range(1, yaws.size()):
			(acc["turn"] as Array).append(absf(wrapf(float(yaws[i]) - float(yaws[i - 1]), -PI, PI)) / SAMPLE_DT)
		var bk: Array = trk.get("bk", [])
		var runs := PackedFloat32Array()
		var run: int = 0
		for i in bk.size():
			run += 1
			if i == bk.size() - 1 or int(bk[i + 1]) != int(bk[i]):
				runs.append(float(run) * SAMPLE_DT)
				run = 0
		for i in range(1, runs.size() - 1):
			(acc["bout"] as Array).append(runs[i])
	for sp in by_sp.keys():
		var acc2: Dictionary = by_sp[sp]
		var ps: Dictionary = MotionMetrics.percentiles(PackedFloat32Array(acc2["speed"]))
		var pt: Dictionary = MotionMetrics.percentiles(PackedFloat32Array(acc2["turn"]))
		var pb: Dictionary = MotionMetrics.percentiles(PackedFloat32Array(acc2["bout"]))
		out.append("%-18s   %5.2f/%5.2f/%5.2f   %5.2f/%5.2f/%5.2f   %5.1f/%5.1f/%5.1f (%3d)" % [
			sp, ps[10], ps[50], ps[90], pt[10], pt[50], pt[90], pb[10], pb[50], pb[90],
			(acc2["bout"] as Array).size()])
	return out
