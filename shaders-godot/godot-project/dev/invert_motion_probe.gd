# Invertebrate motion probe (CREATURE_MOTION_700 #101 #102 #103) - how the
# crawlers move, as numbers, per creature type.
#
#   scripts/dev_run.sh --path shaders-godot/godot-project --headless res://dev/invert_motion_probe.tscn
#
# Drives the real game (main.tscn, like fish_behaviour_probe) and samples
# every shrimp, crab, lobster, mantis shrimp, glass snail, trumpet snail,
# bristle worm, wriggle worm and sea cucumber at 30 Hz of sim time:
#
#   speed / turn   p50 and p90 of travel speed and of the turn rate of the
#                  travel direction (0.5 s windows, while moving)
#   facing         dot(model forward, travel direction) while moving, and
#                  the share of windows above 0.9 (#103: snails, worms and
#                  cucumbers should face where they go). Model forward is -Z
#                  for crustaceans, worms and cucumbers, and +X under the
#                  Body node for glass snails (snail.gd MODEL_YAW). Shrimp
#                  also report the visual body (bank pivot): a crab's is
#                  meant to be ~0, it walks sideways.
#   stance / slip  legged crustaceans: stance ratio from the gait clock (legs
#                  in the planted part of the cycle) and kinematic stance
#                  (foot tip moving < 25% of body speed), and foot slip: how
#                  far a planted foot slides per stance, % of stride (#102,
#                  target <= 10%)
#   transitions    snails: surface changes (wall_normal turns > 17 deg),
#                  how long the visible body eases (snail.gd _blend_t), and
#                  the largest one-sample body rotation; shrimp: landings,
#                  take-offs and the touchdown settle; trumpet snails and
#                  bristle worms: emerge / bury changes and their durations.
#
# Environment:
#   INVERT_PROBE_SCENARIO   scenario id (default shrimp_sanctuary)
#   INVERT_PROBE_STOCK      top-up counts, default
#                           "caridean:4,crab:3,lobster:2,snail:4"
#   INVERT_PROBE_WARMUP_S   sim seconds before sampling (default 15)
#   INVERT_PROBE_SAMPLE_S   sim seconds to sample (default 30)
#   INVERT_PROBE_DAY_PHASE  pin the sim clock (0.25 midday, 0.8 night); unset
#                           leaves it running. Worms and trumpet snails only
#                           come out at night.
#   INVERT_PROBE_OUT        report path (default user://invert_motion_probe.txt)
#
# SAVE SAFETY: as fish_behaviour_probe - capture_mode on, and it refuses to
# run when the active slot holds a saved tank. Run it through dev_run.sh.
extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")
const SAMPLE_DT: float = 1.0 / 30.0
const WINDOW: int = 15                  # samples per facing / turn window (0.5 s)
const STANCE_FRACTION: float = 0.64     # shrimp.gd _tick_gait stance share of the cycle
const NORMAL_CHANGE: float = 0.3        # rad: a snail surface change
const REAL_FAUNA := "res://scripts/real_species_fauna.gd"

var _main: Node = null
var _sim: Node = null
var _world: Node = null
var _warmup: float = 15.0
var _sample_len: float = 30.0
var _t_sim: float = 0.0
var _acc: float = 0.0
var _topped_up: bool = false
var _stock: Dictionary = {}
var _out: String = "user://invert_motion_probe.txt"
var _boot_frames: int = 0
var _day_phase: float = -1.0
var _done: bool = false
# instance id -> track dictionary (see _new_track)
var _tracks: Dictionary = {}
var _leg_tips: Dictionary = {}


func _ready() -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null and saves.has_method("has_state_for_active_slot") \
			and bool(saves.call("has_state_for_active_slot")):
		push_error("[invert_probe] active save slot holds a tank; refusing to run " \
			+ "(world.gd would clear it on a preset mismatch)")
		get_tree().quit(2)
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		push_error("[invert_probe] TankConfig autoload missing")
		get_tree().quit(1)
		return
	cfg.set("capture_mode", true)
	if cfg.has_method("reset_to_defaults"):
		cfg.reset_to_defaults()
	var id: String = _env("INVERT_PROBE_SCENARIO", "shrimp_sanctuary")
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == id:
			ScenarioPickerScript.apply_scenario(sc, cfg)
	_warmup = _env("INVERT_PROBE_WARMUP_S", "15").to_float()
	_sample_len = _env("INVERT_PROBE_SAMPLE_S", "30").to_float()
	_out = _env("INVERT_PROBE_OUT", _out)
	var dp: String = _env("INVERT_PROBE_DAY_PHASE", "")
	if not dp.is_empty():
		_day_phase = clampf(dp.to_float(), 0.0, 1.0)
	for part in _env("INVERT_PROBE_STOCK", "caridean:4,crab:3,lobster:2,snail:4").split(",", false):
		var kv: PackedStringArray = part.split(":")
		if kv.size() == 2:
			_stock[kv[0].strip_edges()] = kv[1].to_int()
	process_priority = 1000
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[invert_probe] scenario=", id, " warmup=", _warmup, " sample=", _sample_len,
		" day_phase=", str(_day_phase) if _day_phase >= 0.0 else "running")


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key).strip_edges()
	return fallback if v.is_empty() else v


func _process(dt: float) -> void:
	if _main == null or _done:
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
		if _boot_frames > 3000:
			push_error("[invert_probe] no sim after boot")
			get_tree().quit(1)
		return
	if _day_phase >= 0.0 and _sim.get("day_phase") != null:
		_sim.set("day_phase", _day_phase)
	if not _topped_up:
		if _world == null or _boot_frames < 30:
			return
		_topped_up = true
		_top_up()
		return
	var ts: float = float(_sim.get("time_scale"))
	var sdt: float = dt * (ts if ts > 0.0 else 1.0)
	_t_sim += sdt
	if _t_sim < _warmup:
		return
	_acc += sdt
	if _acc >= SAMPLE_DT:
		_acc = fmod(_acc, SAMPLE_DT)
		_sample()
	if _t_sim >= _warmup + _sample_len:
		_done = true
		_finish()


# ---- Stocking --------------------------------------------------------------

func _counts() -> Dictionary:
	var have: Dictionary = {}
	for c in _creatures():
		var k: String = String(c[1])
		have[k] = int(have.get(k, 0)) + 1
	return have


func _top_up() -> void:
	if _stock.is_empty() or _world == null:
		return
	var have: Dictionary = _counts()
	var real: Dictionary = (load(REAL_FAUNA) as Script).call("by_id")
	var genome_for: Dictionary = {"caridean": "cherry_shrimp", "crab": "fiddler_crab",
		"lobster": "crayfish", "mantis": "mantis_shrimp"}
	var hw: float = float(_world.get("TANK_HALF_W")) if _world.get("TANK_HALF_W") != null else 6.0
	var hd: float = float(_world.get("TANK_HALF_D")) if _world.get("TANK_HALF_D") != null else 3.0
	for kind in _stock.keys():
		var need: int = int(_stock[kind]) - int(have.get(kind, 0))
		for i in maxi(need, 0):
			var x: float = randf_range(-hw * 0.6, hw * 0.6)
			var z: float = randf_range(-hd * 0.6, hd * 0.6)
			var pos: Vector3 = _world.call("spawn_position_on_floor", x, z, 0.1) \
				if _world.has_method("spawn_position_on_floor") else Vector3(x, 1.7, z)
			if genome_for.has(kind) and _world.has_method("_spawn_shrimp_at"):
				var g: Dictionary = {}
				var ent: Variant = real.get(genome_for[kind], {})
				if ent is Dictionary:
					g = ((ent as Dictionary).get("genome", {}) as Dictionary).duplicate(true)
				g["body_shape"] = kind
				_world.call("_spawn_shrimp_at", g, pos)
			elif kind == "snail" and _world.has_method("_spawn_snail_at"):
				_world.call("_spawn_snail_at", {"shell_shape": "turbo"}, pos)
			else:
				push_warning("[invert_probe] cannot stock " + String(kind))
				break
	print("[invert_probe] stock before top-up ", have, " -> after ", _counts())


# [node, type] for every invertebrate the probe understands.
func _creatures() -> Array:
	var out: Array = []
	if _sim == null:
		return out
	var shrimp_v: Variant = _sim.get("shrimp")
	if shrimp_v is Array:
		for s in shrimp_v as Array:
			if is_instance_valid(s) and s is Shrimp:
				out.append([s, String((s as Shrimp).body_shape)])
	var sroot: Variant = _sim.get("snails_root")
	if sroot is Node:
		for n in (sroot as Node).get_children():
			if n is TrumpetSnail:
				out.append([n, "trumpet"])
			elif n.get("_eye_stalks") != null or n.get("shell_shape") != null:
				out.append([n, "snail"])
	if _world != null:
		var wr: Variant = _world.get("wriggle_root")
		if wr is Node:
			for n in (wr as Node).get_children():
				if n is BristleWorm:
					out.append([n, "bristle_worm"])
				elif n is WriggleWorm:
					out.append([n, "wriggle_worm"])
		var fr: Variant = _world.get("fauna_root")
		if fr is Node:
			for n in (fr as Node).get_children():
				if n is SeaCucumber:
					out.append([n, "sea_cucumber"])
	return out


# ---- Sampling --------------------------------------------------------------

func _new_track(kind: String) -> Dictionary:
	# Plain Arrays while sampling: a packed array read out of a Dictionary is
	# a copy, so appends to it would be lost. _packed() converts for the report.
	return {"kind": kind, "pos": [], "fwd": [], "vis": [], "nrm": [], "basis": [],
		"state": [], "aux": [], "legs": {}, "stride": 0.0}


func _sample() -> void:
	for pair in _creatures():
		var c: Node3D = pair[0]
		if c.get("_dying") == true or c.is_queued_for_deletion():
			continue
		var key: int = c.get_instance_id()
		var trk: Dictionary = _tracks.get(key, {})
		if trk.is_empty():
			trk = _new_track(String(pair[1]))
			_tracks[key] = trk
		var gx: Transform3D = c.global_transform
		(trk["pos"] as Array).append(c.global_position)
		var fwd: Vector3 = -gx.basis.z.normalized()
		var vis: Vector3 = fwd
		var nrm: Vector3 = Vector3.UP
		var state: float = 0.0
		var aux: float = 0.0
		var body_basis: Basis = gx.basis.orthonormalized()
		match String(trk["kind"]):
			"snail":
				var body: Variant = c.get("_body")
				var bb: Basis = (body as Node3D).global_transform.basis if body is Node3D else gx.basis
				body_basis = bb.orthonormalized()
				fwd = bb.x.normalized()
				vis = fwd
				var wn: Variant = c.get("wall_normal")
				nrm = (wn as Vector3).normalized() if wn is Vector3 else Vector3.UP
				state = float(c.get("_blend_t")) if c.get("_blend_t") != null else -1.0
			"trumpet":
				# A vertical shell: no facing axis to score.
				fwd = Vector3.ZERO
				vis = fwd
				state = 1.0 if bool(c.get("_is_emerged")) else 0.0
				aux = c.position.y
			"bristle_worm":
				state = float(c.get("_emerged_t")) if c.get("_emerged_t") != null else 0.0
			"caridean", "crab", "lobster", "mantis":
				var s: Shrimp = c
				var bp: Node3D = s._bank_pivot
				if bp != null:
					vis = -bp.global_transform.basis.z.normalized()
				var grounded: bool = s.global_position.y <= s.substrate_top_y + s._ground_band()
				state = 1.0 if grounded else 0.0
				aux = s._land_settle_t
				_sample_legs(s, trk, grounded)
		(trk["fwd"] as Array).append(fwd)
		(trk["vis"] as Array).append(vis)
		(trk["nrm"] as Array).append(nrm)
		(trk["basis"] as Array).append(body_basis)
		(trk["state"] as Array).append(state)
		(trk["aux"] as Array).append(aux)


func _leg_tip_local(leg: Node3D, v: float) -> Vector3:
	var id: int = leg.get_instance_id()
	if _leg_tips.has(id):
		return _leg_tips[id]
	var box: AABB = MotionDebugOverlay.pivot_local_aabb(leg)
	var tip := Vector3(0.0, -v * 0.43, 0.0)
	if box.size != Vector3.ZERO:
		var c: Vector3 = box.get_center()
		tip = Vector3(c.x, box.position.y, c.z)
	_leg_tips[id] = tip
	return tip


func _sample_legs(s: Shrimp, trk: Dictionary, grounded: bool) -> void:
	var g: Dictionary = s._gait_profile()
	trk["stride"] = 1.0 / maxf(float(g.get("steps_per_unit", 8.0)), 0.1)
	var legs: Dictionary = trk["legs"]
	for entry in s._leg_pivots:
		var node: Variant = (entry as Dictionary).get("node")
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var leg: Node3D = node
		var lid: int = leg.get_instance_id()
		if not legs.has(lid):
			legs[lid] = {"tip": [], "planted": []}
		var tip: Vector3 = leg.global_transform * _leg_tip_local(leg, s.adult_voxel_scale)
		var cycle: float = fposmod(s._gait_phase + float((entry as Dictionary).get("phase", 0.0)), TAU) / TAU
		((legs[lid] as Dictionary)["tip"] as Array).append(tip)
		((legs[lid] as Dictionary)["planted"] as Array).append(grounded and cycle < STANCE_FRACTION)


# ---- Report ----------------------------------------------------------------

static func _flat(v: Vector3, n: Vector3) -> Vector3:
	return v - n * v.dot(n)


func _finish() -> void:
	var lines := PackedStringArray()
	var scenario_id: String = _env("INVERT_PROBE_SCENARIO", "shrimp_sanctuary")
	lines.append("invert_motion_probe  scenario=%s  warmup=%.0fs  sampled=%.0fs  sample_hz=%.0f  day_phase=%s  build=%s" % [
		scenario_id, _warmup, _sample_len, 1.0 / SAMPLE_DT,
		"%.2f" % _day_phase if _day_phase >= 0.0 else "running",
		String(ProjectSettings.get_setting("application/config/version", ""))])
	var by_kind: Dictionary = {}
	for key in _tracks.keys():
		var trk: Dictionary = _tracks[key]
		var k: String = String(trk["kind"])
		if not by_kind.has(k):
			by_kind[k] = []
		(by_kind[k] as Array).append(trk)
	lines.append("%-13s %3s %6s %15s %15s %6s %17s %6s" % ["type", "n", "moving",
		"speed p50/p90", "turn p50/p90", "facing", "(>0.9) visual", "min"])
	var detail := PackedStringArray()
	for k in by_kind.keys():
		var trs: Array = by_kind[k]
		var speeds := PackedFloat32Array()
		var turns := PackedFloat32Array()
		var facing := PackedFloat32Array()
		var vis_facing := PackedFloat32Array()
		var samples: int = 0
		var moving: int = 0
		var move_min: float = 0.004 if k in ["snail", "trumpet", "bristle_worm", "wriggle_worm", "sea_cucumber"] else 0.03
		for trk in trs:
			var pos := PackedVector3Array(trk["pos"])
			var fwd := PackedVector3Array(trk["fwd"])
			var vis := PackedVector3Array(trk["vis"])
			var nrm := PackedVector3Array(trk["nrm"])
			samples += pos.size()
			var prev_dir := Vector3.ZERO
			var w: int = WINDOW
			var i: int = w
			while i < pos.size():
				var n: Vector3 = nrm[i]
				var d: Vector3 = pos[i] - pos[i - w]
				d = _flat(d, n) if k == "snail" else Vector3(d.x, 0.0, d.z)
				var spd: float = d.length() / (float(w) * SAMPLE_DT)
				speeds.append(spd)
				if spd >= move_min:
					moving += w
					var dir: Vector3 = d.normalized()
					var fw: Vector3 = _flat(fwd[i], n) if k == "snail" else Vector3(fwd[i].x, 0.0, fwd[i].z)
					var fv: Vector3 = Vector3(vis[i].x, 0.0, vis[i].z)
					if fw.length_squared() > 1e-8:
						facing.append(fw.normalized().dot(dir))
					if fv.length_squared() > 1e-8:
						vis_facing.append(fv.normalized().dot(dir))
					if prev_dir != Vector3.ZERO:
						turns.append(prev_dir.angle_to(dir) / (float(w) * SAMPLE_DT))
					prev_dir = dir
				else:
					prev_dir = Vector3.ZERO
				i += w
		var ps: Dictionary = MotionMetrics.percentiles(speeds, [50, 90])
		var pt: Dictionary = MotionMetrics.percentiles(turns, [50, 90])
		var good: int = 0
		for fv2 in facing:
			if fv2 > 0.9:
				good += 1
		var vis_s: String = "-"
		if k in ["caridean", "crab", "lobster", "mantis"] and not vis_facing.is_empty():
			vis_s = "%.2f" % MotionMetrics.mean(vis_facing)
		lines.append("%-13s %3d %5.0f%% %7.3f/%7.3f %7.2f/%7.2f %6s %8s %8s %6.2f" % [
			k, trs.size(), 100.0 * float(moving) / maxf(float(samples), 1.0),
			ps[50], ps[90], pt[50], pt[90],
			"%.2f" % MotionMetrics.mean(facing) if not facing.is_empty() else "-",
			"%.0f%%" % (100.0 * float(good) / float(facing.size())) if not facing.is_empty() else "-",
			vis_s, float(samples) * SAMPLE_DT / 60.0])
		match k:
			"caridean", "crab", "lobster", "mantis":
				detail.append_array(_legged_report(k, trs))
			"snail":
				detail.append_array(_snail_report(trs))
			"trumpet", "bristle_worm":
				detail.append_array(_emerge_report(k, trs))
	if by_kind.is_empty():
		lines.append("(no invertebrates sampled)")
	lines.append("targets  facing > 0.9 once moving (#103; crab visual ~0 by design); foot slip <= 10% of stride (#102)")
	lines.append_array(detail)
	var text: String = "\n".join(lines) + "\n"
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print(text)
	print("[invert_probe] wrote ", ProjectSettings.globalize_path(_out))
	set_process(false)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)


func _legged_report(k: String, trs: Array) -> PackedStringArray:
	var leg_samples: int = 0
	var planted_n: int = 0
	var kin_planted: int = 0
	var slips := PackedFloat32Array()
	var landings: int = 0
	var takeoffs: int = 0
	var settle := PackedFloat32Array()
	for trk in trs:
		var pos := PackedVector3Array(trk["pos"])
		var state := PackedFloat32Array(trk["state"])
		var aux := PackedFloat32Array(trk["aux"])
		var stride: float = float(trk["stride"])
		for i in range(1, state.size()):
			if state[i] > 0.5 and state[i - 1] < 0.5:
				landings += 1
				# The touchdown settle starts within a few samples of the
				# grounded flip; time how long it runs.
				var j0: int = i
				while j0 < mini(i + 10, aux.size()) and aux[j0] <= 0.0:
					j0 += 1
				var j: int = j0
				while j < aux.size() and aux[j] > 0.0:
					j += 1
				if j > j0:
					settle.append(float(j - j0) * SAMPLE_DT)
			elif state[i] < 0.5 and state[i - 1] > 0.5:
				takeoffs += 1
		var legs: Dictionary = trk["legs"]
		for lid in legs:
			var tips := PackedVector3Array((legs[lid] as Dictionary)["tip"])
			var planted: Array = (legs[lid] as Dictionary)["planted"]
			var n: int = mini(tips.size(), pos.size())
			# Stance runs while the body walks.
			var run_tips := PackedVector3Array()
			var run_flags: Array = []
			for i in range(1, n):
				var body_v: Vector3 = pos[i] - pos[i - 1]
				body_v.y = 0.0
				var body_spd: float = body_v.length() / SAMPLE_DT
				if body_spd < 0.03 or state[i] < 0.5:
					continue
				leg_samples += 1
				var tip_v: Vector3 = tips[i] - tips[i - 1]
				tip_v.y = 0.0
				if bool(planted[i]):
					planted_n += 1
				if tip_v.length() / SAMPLE_DT < body_spd * 0.25:
					kin_planted += 1
				var stance: bool = bool(planted[i]) and bool(planted[i - 1])
				if stance:
					if run_tips.is_empty():
						run_tips.append(tips[i - 1])
						run_flags.append(true)
					run_tips.append(tips[i])
					run_flags.append(true)
				elif run_tips.size() >= 3:
					slips.append(MotionMetrics.foot_slip(run_tips, run_flags, stride))
					run_tips = PackedVector3Array()
					run_flags = []
				else:
					run_tips = PackedVector3Array()
					run_flags = []
	var out := PackedStringArray()
	var ps: Dictionary = MotionMetrics.percentiles(slips, [50, 90])
	out.append("   %-10s legs: stance (gait clock) %4.0f%%  kinematic stance %4.0f%%  foot slip per stance p50 %4.1f%% p90 %4.1f%% of stride (n=%d)  landings %d (settle %.2f s, n=%d)  take-offs %d" % [
		k, 100.0 * float(planted_n) / maxf(float(leg_samples), 1.0),
		100.0 * float(kin_planted) / maxf(float(leg_samples), 1.0),
		100.0 * float(ps[50]), 100.0 * float(ps[90]), slips.size(), landings,
		MotionMetrics.mean(settle), settle.size(), takeoffs])
	return out


func _snail_report(trs: Array) -> PackedStringArray:
	var changes: int = 0
	var blends := PackedFloat32Array()
	var max_rot: float = 0.0
	var max_rot_blend: float = 0.0
	for trk in trs:
		var nrm := PackedVector3Array(trk["nrm"])
		var state := PackedFloat32Array(trk["state"])
		var bases: Array = trk["basis"]
		for i in range(1, nrm.size()):
			var b0: Basis = bases[i - 1]
			var b1: Basis = bases[i]
			var rot: float = rad_to_deg((b0.inverse() * b1).get_rotation_quaternion().get_angle())
			max_rot = maxf(max_rot, rot)
			if state[i] >= 0.0:
				max_rot_blend = maxf(max_rot_blend, rot)
			if nrm[i].angle_to(nrm[i - 1]) > NORMAL_CHANGE:
				changes += 1
				var j: int = i
				while j < state.size() and state[j] >= 0.0:
					j += 1
				blends.append(float(j - i) * SAMPLE_DT)
	var out := PackedStringArray()
	out.append("   snail      surface changes %d  body ease %.2f s mean (max %.2f s)  max body rotation %.1f deg/sample (%.1f during eases)" % [
		changes, MotionMetrics.mean(blends),
		float(MotionMetrics.percentiles(blends, [100])[100]), max_rot, max_rot_blend])
	return out


func _emerge_report(k: String, trs: Array) -> PackedStringArray:
	var flips: int = 0
	var durs := PackedFloat32Array()
	for trk in trs:
		var state := PackedFloat32Array(trk["state"])
		var aux := PackedFloat32Array(trk["aux"])
		for i in range(1, state.size()):
			if k == "trumpet":
				if state[i] != state[i - 1]:
					flips += 1
					# Until the shell stops moving (< 5 mm/s).
					var j: int = i + 1
					while j < aux.size() and absf(aux[j] - aux[j - 1]) / SAMPLE_DT > 0.005:
						j += 1
					durs.append(float(j - i) * SAMPLE_DT)
			elif (state[i] >= 0.5) != (state[i - 1] >= 0.5):
				flips += 1
				# 10% -> 90% of the emerge ramp, around this crossing.
				var lo: int = i
				while lo > 0 and absf(state[lo] - (0.0 if state[i] >= 0.5 else 1.0)) > 0.1:
					lo -= 1
				var hi: int = i
				while hi < state.size() - 1 and absf(state[hi] - (1.0 if state[i] >= 0.5 else 0.0)) > 0.1:
					hi += 1
				durs.append(float(hi - lo) * SAMPLE_DT)
	var out := PackedStringArray()
	out.append("   %-10s emerge/bury changes %d  duration mean %.2f s" % [k, flips, MotionMetrics.mean(durs)])
	return out
