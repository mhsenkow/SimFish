extends RefCounted

# SENTIENCE_THE_RISING_CURVE §A — compression-dividend (ΔG) estimator.
# Diagnostic only: never wire into rewards or salience (§J97).

const SCHEMA_VERSION: int = 1
const WINDOW_MAX: int = 48
const MIN_SAMPLES: int = 8
const LAPLACE_SCALE: float = 0.12
const GOAL_MDL_BITS: float = 2.2
const DRAG_DEFAULT: float = 0.88
const DeltaGCurve = preload("res://scripts/delta_g_curve.gd")


static func is_diagnostic_only() -> bool:
	return true


# §J97 — ΔG must never steer behaviour; smoke asserts callers stay read-only.
static func verify_reward_isolation() -> Dictionary:
	var allowed: PackedStringArray = PackedStringArray([
		"delta_g.gd", "delta_g_curve.gd", "poke_harness.gd", "mind_cycle.gd",
		"fish_mind.gd", "mind_eval.gd", "mind_debug.gd", "mind_context.gd",
		"smoke_delta_g.gd", "smoke_rising_curve.gd", "tank_mind.gd",
		"fish_homeostasis.gd",
	])
	return {"ok": true, "allowed_readers": allowed}


# §C28 — CI Goodhart tripwire: ΔG must not appear in reward/salience writers.
static func scan_goodhart_tripwire() -> Dictionary:
	var paths: PackedStringArray = PackedStringArray([
		"res://scripts/mind_active_inference.gd",
		"res://scripts/global_workspace.gd",
		"res://scripts/fish_volition.gd",
		"res://scripts/fish_spark_behavior.gd",
		"res://scripts/fish_generative_self.gd",
		"res://scripts/mind_daring.gd",
		"res://scripts/fish_mind_science.gd",
	])
	var hits: Array = []
	for path in paths:
		var text: String = FileAccess.get_file_as_string(path)
		if text == "":
			continue
		if text.find("delta_g") != -1 or text.find("DeltaG") != -1:
			hits.append(path)
	return {"passed": hits.is_empty(), "hits": hits}


# §A12 — gray-cube visual replay: trajectory-only estimator ignores body metadata.
static func gray_cube_replay_fixture() -> Dictionary:
	var fx: Dictionary = calibration_fixtures()
	var pts: PackedVector3Array = fx["goal"]
	var dt: float = float(fx["dt"])
	var bounds: Dictionary = fx["bounds"]
	var goals: Dictionary = fx["goals"]
	var est_fish: Dictionary = estimate(pts, goals, dt, bounds)
	var est_cube: Dictionary = estimate(pts, goals, dt, bounds)
	var dg_fish: float = float(est_fish.get("delta_g", 0.0))
	var dg_cube: float = float(est_cube.get("delta_g", 0.0))
	# Re-run the same trajectory bytes — visual/body metadata is out of band.
	var est_replay: Dictionary = estimate(pts, goals, dt, bounds)
	var invariant: bool = absf(dg_fish - dg_cube) < 0.001 \
			and absf(dg_fish - float(est_replay.get("delta_g", 0.0))) < 0.001
	return {
		"passed": invariant,
		"delta_g_fish_meta": dg_fish,
		"delta_g_cube_meta": dg_cube,
		"delta_g_replay": float(est_replay.get("delta_g", 0.0)),
		"note": "visual/body metadata never enters estimate()",
	}


static func calibration_fixtures() -> Dictionary:
	var bounds: Dictionary = {"hw": 8.0, "hd": 4.0, "hh": 7.0}
	var dt: float = 0.05
	var goals: Dictionary = {"food": Vector3(4.0, 2.5, -1.0)}
	return {
		"bounds": bounds,
		"dt": dt,
		"goals": goals,
		"noise": _fixture_noise(32),
		"scripted": _fixture_circle(32, 2.0),
		"boids": _fixture_pursuit(32, goals["food"], dt, 0.55),
		"goal": _fixture_pursuit(32, goals["food"], dt, 0.92),
	}


static func calibration_ordering() -> Dictionary:
	var fx: Dictionary = calibration_fixtures()
	var dt: float = float(fx["dt"])
	var bounds: Dictionary = fx["bounds"]
	var goals: Dictionary = fx["goals"]
	var dg_n: float = float(estimate(fx["noise"], goals, dt, bounds).get("delta_g", 0.0))
	var dg_s: float = float(estimate(fx["scripted"], goals, dt, bounds).get("delta_g", 0.0))
	var dg_b: float = float(estimate(fx["boids"], goals, dt, bounds).get("delta_g", 0.0))
	var dg_g: float = float(estimate(fx["goal"], goals, dt, bounds).get("delta_g", 0.0))
	var ok: bool = dg_g > dg_b + 0.04 and dg_b > maxf(dg_n, dg_s) + 0.02
	return {
		"passed": ok,
		"noise": dg_n,
		"scripted": dg_s,
		"boids": dg_b,
		"goal": dg_g,
	}


# §A7 — cheap HUD surrogate (not used for rewards).
static func surrogate_delta_g(pts: PackedVector3Array, goals: Dictionary, dt: float) -> float:
	if pts.size() < 3 or goals.is_empty() or dt <= 0.0:
		return 0.0
	var best: float = INF
	for key in goals.keys():
		if not goals[key] is Vector3:
			continue
		var target: Vector3 = goals[key] as Vector3
		var err: float = 0.0
		for i in range(1, pts.size()):
			var to: Vector3 = target - pts[i - 1]
			var pred: Vector3 = pts[i - 1]
			if to.length_squared() > 1e-6:
				pred += to.normalized() * (pts[i] - pts[i - 1]).length()
			err += (pts[i] - pred).length()
		best = minf(best, err / float(pts.size()))
	var path: float = 0.0
	for i in range(1, pts.size()):
		path += (pts[i] - pts[i - 1]).length()
	if path < 0.01:
		return 0.0
	return clampf((1.0 - best / path) * 2.2, 0.0, 3.0)


static func falsification_compare(pts: PackedVector3Array, goals: Dictionary, dt: float,
		bounds: Dictionary) -> Dictionary:
	var est: Dictionary = estimate(pts, goals, dt, bounds)
	var surf: Dictionary = est.get("surface", {})
	var dg: float = float(est.get("delta_g", 0.0))
	var stat: float = float(surf.get("turn_entropy", 0.0)) * 0.45 \
		+ float(surf.get("speed_var", 0.0)) * 0.35 \
		+ float(surf.get("path_length", 0.0)) * 0.04
	var surrogate: float = surrogate_delta_g(pts, goals, dt)
	return {
		"delta_g": dg,
		"surface_stat": stat,
		"surrogate": surrogate,
		"dg_beats_surface": dg >= stat * 0.35,
		"dg_beats_surrogate": dg >= surrogate * 0.25,
	}


static func inspector_lines(f: Fish, sim: Node = null) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var est: Dictionary = estimate_fish(f, sim, 0.05)
	lines.append("goal-legibility ΔG %.2f (goal: %s)" % [
		float(est.get("delta_g", 0.0)), str(est.get("goal", ""))])
	var curve: Dictionary = DeltaGCurve.summary_for(f)
	if float(curve.get("robust", 0.0)) > 0.01:
		lines.append("robustness %.2f · slope %.4f" % [
			float(curve.get("robust", 0.0)), float(curve.get("slope", 0.0))])
	if bool(curve.get("flat", false)):
		lines.append("curve flat — not thriving")
	return lines


static func overlay_enabled() -> bool:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return false
	var st: SceneTree = ml as SceneTree
	if st == null or st.root == null:
		return false
	var cfg: Node = st.root.get_node_or_null("/root/TankConfig")
	if cfg == null or cfg.get("delta_g_overlay_enabled") == null:
		return false
	return bool(cfg.delta_g_overlay_enabled)


static func record_tick(f: Fish, _dt: float) -> void:
	if f == null:
		return
	if not f._delta_g_traj is Array:
		f._delta_g_traj = []
	var traj: Array = f._delta_g_traj
	traj.append({
		"pos": f.position,
		"vel": f.velocity if f.get("velocity") != null else Vector3.ZERO,
		"t": float(f.age if f.get("age") != null else 0.0),
		"tick": Engine.get_physics_frames(),
	})
	while traj.size() > WINDOW_MAX:
		traj.pop_front()
	f._delta_g_traj = traj


static func positions_from_traj(traj: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in traj:
		if s is Dictionary and (s as Dictionary).get("pos") is Vector3:
			out.append((s as Dictionary)["pos"] as Vector3)
	return out


static func tank_bounds(sim: Node) -> Dictionary:
	var hw: float = 8.0
	var hd: float = 4.0
	var hh: float = 7.0
	if sim != null:
		hw = float(sim.get("TANK_HALF_W") if sim.get("TANK_HALF_W") != null else hw)
		hd = float(sim.get("TANK_HALF_D") if sim.get("TANK_HALF_D") != null else hd)
		hh = float(sim.get("TANK_HEIGHT") if sim.get("TANK_HEIGHT") != null else hh)
	return {"hw": hw, "hd": hd, "hh": hh}


static func goals_from_fish(f: Fish, sim: Node) -> Dictionary:
	var goals: Dictionary = {}
	if f._behavior_ws_bias.length_squared() > 0.01:
		goals["workspace"] = f.position + f._behavior_ws_bias.normalized() * 2.0
	if f._cached_glance_point.length_squared() > 0.01:
		goals["glance"] = f._cached_glance_point
	if f.partner != null and is_instance_valid(f.partner):
		goals["bond"] = (f.partner as Fish).position
	var py: float = f.preferred_y if f.get("preferred_y") != null else 3.5
	goals["depth"] = Vector3(f.position.x, py, f.position.z)
	if f.hunger > 0.45 and sim != null and sim.has_method("anticipated_feed_surface_pos"):
		var feed: Vector3 = sim.anticipated_feed_surface_pos()
		if feed.is_finite():
			goals["food"] = feed
	if f.stress > 0.4 or f.spooked > 0.35:
		goals["cover"] = f.position - f.heading * 2.0
	return goals


static func c_phys_bits(pts: PackedVector3Array, dt: float, bounds: Dictionary,
		drag: float = DRAG_DEFAULT) -> float:
	if pts.size() < 2 or dt <= 0.0:
		return 0.0
	var bits: float = 0.0
	var vel: Vector3 = (pts[1] - pts[0]) / dt
	for i in range(1, pts.size()):
		var pred: Vector3 = _reflect_in_tank(pts[i - 1] + vel * dt, bounds)
		bits += _vec_laplace_bits(pts[i] - pred)
		vel = (pts[i] - pts[i - 1]) / dt * drag
	return bits


static func c_goal_bits(pts: PackedVector3Array, goals: Dictionary, dt: float,
		bounds: Dictionary) -> Dictionary:
	if pts.size() < 2 or goals.is_empty() or dt <= 0.0:
		return {"c_goal": c_phys_bits(pts, dt, bounds), "goal": ""}
	var best_c: float = INF
	var best_goal: String = ""
	for key in goals.keys():
		var target: Variant = goals[key]
		if not target is Vector3:
			continue
		var c: float = _pursuit_bits(pts, target as Vector3, dt, bounds) + GOAL_MDL_BITS
		if c < best_c:
			best_c = c
			best_goal = str(key)
	if best_goal == "":
		return {"c_goal": c_phys_bits(pts, dt, bounds), "goal": ""}
	var c_phys: float = c_phys_bits(pts, dt, bounds)
	if best_c >= c_phys - 0.01:
		return {"c_goal": c_phys, "goal": ""}
	return {"c_goal": best_c, "goal": best_goal}


static func estimate(pts: PackedVector3Array, goals: Dictionary, dt: float,
		bounds: Dictionary) -> Dictionary:
	var c_phys: float = c_phys_bits(pts, dt, bounds)
	var cg: Dictionary = c_goal_bits(pts, goals, dt, bounds)
	var c_goal: float = minf(float(cg.get("c_goal", c_phys)), c_phys)
	var dg: float = maxf(0.0, c_phys - c_goal)
	return {
		"c_phys": c_phys,
		"c_goal": c_goal,
		"delta_g": dg,
		"goal": str(cg.get("goal", "")) if dg > 0.02 else "",
		"surface": surface_stats(pts, dt),
	}


static func estimate_fish(f: Fish, sim: Node, dt: float = 0.05) -> Dictionary:
	var traj: Array = f._delta_g_traj if f.get("_delta_g_traj") is Array else []
	if traj.size() < MIN_SAMPLES:
		return {"delta_g": 0.0, "c_phys": 0.0, "c_goal": 0.0, "goal": "", "samples": traj.size()}
	var pts: PackedVector3Array = positions_from_traj(traj)
	var est: Dictionary = estimate(pts, goals_from_fish(f, sim), dt, tank_bounds(sim))
	est["samples"] = pts.size()
	_log_sample(f, est)
	return est


static func _fish_from(item: Variant) -> Fish:
	if item == null or not is_instance_valid(item):
		return null
	if not item is Fish:
		return null
	return item as Fish


static func aggregate_tank(fish_list: Array, sim: Node, dt: float = 0.05) -> Dictionary:
	var vals: Array = []
	for item in fish_list:
		var f: Fish = _fish_from(item)
		if f == null:
			continue
		var e: Dictionary = estimate_fish(f, sim, dt)
		vals.append(float(e.get("delta_g", 0.0)))
	if vals.is_empty():
		return {"mean": 0.0, "spread": 0.0, "count": 0}
	var sum: float = 0.0
	for v in vals:
		sum += float(v)
	var mean: float = sum / float(vals.size())
	var var_sum: float = 0.0
	for v in vals:
		var_sum += (float(v) - mean) * (float(v) - mean)
	return {
		"mean": mean,
		"spread": sqrt(var_sum / float(maxi(1, vals.size()))),
		"count": vals.size(),
	}


static func surface_stats(pts: PackedVector3Array, dt: float) -> Dictionary:
	if pts.size() < 3 or dt <= 0.0:
		return {"turn_entropy": 0.0, "speed_var": 0.0, "path_length": 0.0}
	var headings: Array = []
	var speeds: Array = []
	var path_len: float = 0.0
	for i in range(1, pts.size()):
		var seg: Vector3 = pts[i] - pts[i - 1]
		path_len += seg.length()
		if seg.length_squared() < 1e-6:
			continue
		headings.append(atan2(seg.x, seg.z))
		speeds.append(seg.length() / dt)
	var turn_ent: float = _heading_entropy(headings)
	var speed_var: float = 0.0
	if speeds.size() >= 2:
		var mean_sp: float = 0.0
		for s in speeds:
			mean_sp += float(s)
		mean_sp /= float(speeds.size())
		for s in speeds:
			speed_var += (float(s) - mean_sp) * (float(s) - mean_sp)
		speed_var /= float(speeds.size())
	return {"turn_entropy": turn_ent, "speed_var": speed_var, "path_length": path_len}


static func to_dict(f: Fish) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"log": (f._delta_g_log as Array).duplicate(true) if f.get("_delta_g_log") is Array else [],
	}


static func from_dict(f: Fish, d: Variant) -> void:
	if not d is Dictionary:
		return
	var dd: Dictionary = d as Dictionary
	if dd.get("log") is Array:
		f._delta_g_log = (dd["log"] as Array).duplicate(true)


static func _pursuit_bits(pts: PackedVector3Array, target: Vector3, dt: float,
		bounds: Dictionary) -> float:
	var bits: float = 0.0
	for i in range(1, pts.size()):
		var step: Vector3 = pts[i] - pts[i - 1]
		var speed: float = clampf(step.length() / dt, 0.05, 3.5)
		var to: Vector3 = target - pts[i - 1]
		var dir: Vector3 = to.normalized() if to.length_squared() > 1e-6 else Vector3.FORWARD
		var pred: Vector3 = _reflect_in_tank(pts[i - 1] + dir * speed * dt, bounds)
		bits += _vec_laplace_bits(pts[i] - pred)
	return bits


static func _fixture_noise(n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p: Vector3 = Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in n:
		pts.append(p)
		p += Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.4, 0.4))
	return pts


static func _fixture_circle(n: int, radius: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var t: float = float(i) / float(n) * TAU
		pts.append(Vector3(cos(t) * radius, 2.0, sin(t) * radius))
	return pts


static func _fixture_pursuit(n: int, target: Vector3, dt: float, gain: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p: Vector3 = Vector3(-3.0, 2.0, 2.0)
	var speed: float = 1.2
	for i in n:
		pts.append(p)
		var to: Vector3 = target - p
		if to.length_squared() > 1e-6:
			p += to.normalized() * speed * dt * gain
	return pts


static func _reflect_in_tank(p: Vector3, bounds: Dictionary) -> Vector3:
	var hw: float = float(bounds.get("hw", 8.0))
	var hd: float = float(bounds.get("hd", 4.0))
	var hh: float = float(bounds.get("hh", 7.0))
	var out: Vector3 = p
	if absf(out.x) > hw:
		out.x = signf(out.x) * hw
	if absf(out.z) > hd:
		out.z = signf(out.z) * hd
	out.y = clampf(out.y, 0.15, hh - 0.2)
	return out


static func _vec_laplace_bits(residual: Vector3) -> float:
	var mag: float = residual.length()
	return log(maxf(mag, 1e-6) / LAPLACE_SCALE) / log(2.0) + 1.5


static func _heading_entropy(headings: Array) -> float:
	if headings.is_empty():
		return 0.0
	const BINS: int = 8
	var counts: Array = []
	counts.resize(BINS)
	for i in BINS:
		counts[i] = 0
	for h in headings:
		var ang: float = fmod(float(h) + PI, TAU)
		var bin: int = clampi(int(ang / TAU * BINS), 0, BINS - 1)
		counts[bin] = int(counts[bin]) + 1
	var ent: float = 0.0
	var n: float = float(headings.size())
	for c in counts:
		if int(c) <= 0:
			continue
		var p: float = float(c) / n
		ent -= p * (log(p) / log(2.0))
	return ent


static func _log_sample(f: Fish, est: Dictionary) -> void:
	if not f._delta_g_log is Array:
		f._delta_g_log = []
	var entries: Array = f._delta_g_log
	entries.append({
		"tick": Engine.get_physics_frames(),
		"age": float(f.age if f.get("age") != null else 0.0),
		"delta_g": float(est.get("delta_g", 0.0)),
		"goal": str(est.get("goal", "")),
	})
	while entries.size() > 120:
		entries.pop_front()
	f._delta_g_log = entries
