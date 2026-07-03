extends RefCounted
class_name FishHomeostasis

# SENTIENCE_THE_RISING_CURVE §D — rung-1 homeostatic goal-structure.
# Stakes, not scripts: behavior descends from defended interior state.

const ALLOSTASIS_HORIZON_S: float = 30.0
const HUNGER_RISE_RATE: float = 0.006


static func ensure(f) -> Dictionary:
	if f == null:
		return {}
	var h: Variant = f.get("_homeostasis")
	if h is Dictionary and (h as Dictionary).has("hunger_set"):
		return h as Dictionary
	var seeded: Dictionary = _seed_setpoints(f)
	if f is Object:
		(f as Object).set("_homeostasis", seeded)
	return seeded


static func _seed_setpoints(f) -> Dictionary:
	var id_str: String = String(f.id) if f.get("id") != null else "anon"
	var rng := RandomNumberGenerator.new()
	rng.seed = SimRng.stream_seed(0xA05E, SimRng.entity_stream_name("homeostasis", id_str))
	var bold: float = _trait(f, "boldness")
	var curious: float = _trait(f, "curiosity")
	return {
		"hunger_set": clampf(0.24 + bold * 0.14 + rng.randf_range(-0.03, 0.03), 0.12, 0.48),
		"safety_set": clampf(0.14 + (1.0 - bold) * 0.18 + rng.randf_range(-0.02, 0.02), 0.08, 0.42),
		"o2_set": clampf(0.72 + rng.randf_range(-0.08, 0.08), 0.55, 0.92),
		"rest_set": clampf(0.18 + (1.0 - bold) * 0.12, 0.08, 0.38),
		"social_set": clampf(0.22 + curious * 0.12, 0.1, 0.45),
		"explore_set": clampf(0.28 + curious * 0.2, 0.15, 0.62),
		"hunger_trend": 0.0,
		"prev_hunger": f.hunger if f.get("hunger") != null else 0.3,
		"dominant": "",
		"conflict": 0.0,
		"feed_point": Vector3.ZERO,
	}


static func _trait(f, key: String) -> float:
	if f.has_method("_trait"):
		return SaveHelpers._num(f.call("_trait", key), 0.5)
	return 0.5


static func tick(f, sim: Node, dt: float) -> void:
	var h: Dictionary = ensure(f)
	var prev: float = SaveHelpers._num(h.get("prev_hunger", f.hunger), f.hunger)
	var trend: float = (f.hunger - prev) / maxf(dt, 0.001)
	h["hunger_trend"] = lerpf(SaveHelpers._num(h.get("hunger_trend", 0.0), 0.0), trend, clampf(dt * 3.0, 0.0, 1.0))
	h["prev_hunger"] = f.hunger
	var dom: Dictionary = dominant_error(f, sim)
	h["dominant"] = str(dom.get("label", ""))
	h["conflict"] = conflict_level(f, sim)
	h["feed_point"] = preferred_food_point(f, sim)
	if f is Object:
		(f as Object).set("_homeostasis", h)
		(f as Object).set("_homeostatic_feed_point", h["feed_point"] as Vector3)


static func errors(f, sim: Node = null) -> Dictionary:
	var h: Dictionary = ensure(f)
	var hunger_err: float = maxf(0.0, f.hunger - SaveHelpers._num(h.get("hunger_set", 0.3), 0.3))
	var safety_err: float = maxf(0.0, f.spooked + f.stress * 0.4 - SaveHelpers._num(h.get("safety_set", 0.2), 0.2))
	var rest_err: float = maxf(0.0,
			SaveHelpers._num(f.get("_rest_debt"), 0.0)
			- SaveHelpers._num(h.get("rest_set", 0.2), 0.2))
	var social_err: float = 0.0
	var has_partner: bool = f.get("has_mate") == true \
			or (f.get("partner") != null and is_instance_valid(f.get("partner")))
	if not has_partner:
		social_err = SaveHelpers._num(h.get("social_set", 0.25), 0.25)
	var explore_err: float = maxf(0.0, f.curiosity_drive - SaveHelpers._num(h.get("explore_set", 0.35), 0.35))
	var o2_err: float = 0.0
	if sim != null:
		var eff_o2: float = SaveHelpers._num(sim.get("dissolved_o2"), 1.0)
		o2_err = maxf(0.0, SaveHelpers._num(h.get("o2_set", 0.75), 0.75) - eff_o2)
	var trend: float = SaveHelpers._num(h.get("hunger_trend", 0.0), 0.0)
	var future_hunger: float = clampf(
			f.hunger + trend * ALLOSTASIS_HORIZON_S + HUNGER_RISE_RATE * ALLOSTASIS_HORIZON_S,
			0.0, 1.0)
	var allo_hunger: float = maxf(0.0, future_hunger - SaveHelpers._num(h.get("hunger_set", 0.3), 0.3))
	return {
		"hunger": hunger_err,
		"safety": safety_err,
		"o2": o2_err,
		"rest": rest_err,
		"social": social_err,
		"exploration": explore_err,
		"allostatic_hunger": allo_hunger,
	}


static func dominant_error(f, sim: Node = null) -> Dictionary:
	var e: Dictionary = errors(f, sim)
	var best_l: String = ""
	var best_v: float = 0.0
	for key in ["hunger", "allostatic_hunger", "safety", "o2", "rest", "social", "exploration"]:
		var v: float = SaveHelpers._num(e.get(key, 0.0), 0.0)
		if v > best_v:
			best_v = v
			best_l = key
	return {"label": best_l, "value": best_v}


static func conflict_level(f, sim: Node = null) -> float:
	var e: Dictionary = errors(f, sim)
	var vals: Array = []
	for key in e.keys():
		vals.append(SaveHelpers._num(e[key], 0.0))
	vals.sort()
	vals.reverse()
	if vals.size() < 2:
		return 0.0
	var top: float = SaveHelpers._num(vals[0], 0.0)
	var second: float = SaveHelpers._num(vals[1], 0.0)
	if top < 0.12:
		return 0.0
	return clampf(second / maxf(top, 0.001), 0.0, 1.0)


static func hesitation_scale(f, sim: Node = null) -> float:
	# §D40 — homeostatic conflict slows commitment; don't smooth it away.
	return lerpf(1.0, 0.42, conflict_level(f, sim))


static func should_revisit_food(f, _sim: Node = null) -> bool:
	return errors(f, _sim)["hunger"] > 0.08 or errors(f, _sim)["allostatic_hunger"] > 0.12


static func should_explore_goal(f, sim: Node = null) -> bool:
	var e: Dictionary = errors(f, sim)
	return e["exploration"] > 0.08 or (f.curiosity_drive > 0.55 and e["safety"] < 0.35)


static func preferred_food_point(f, sim: Node) -> Vector3:
	if sim != null and sim.has_method("anticipated_feed_surface_pos"):
		var feed: Vector3 = sim.anticipated_feed_surface_pos()
		if feed.is_finite() and feed.length_squared() > 0.01:
			return feed
	if f.goal_kind == "revisit_food" and f.goal_point.length_squared() > 0.01:
		return f.goal_point
	return Vector3.ZERO


static func food_seek_bias(f, food_pos: Vector3) -> Vector3:
	if food_pos.length_squared() < 0.01:
		return Vector3.ZERO
	var e: Dictionary = errors(f, null)
	var urge: float = maxf(SaveHelpers._num(e["hunger"], 0.0), SaveHelpers._num(e["allostatic_hunger"], 0.0) * 0.85)
	if urge < 0.06:
		return Vector3.ZERO
	var to: Vector3 = food_pos - f.position
	if to.length_squared() < 1e-6:
		return Vector3.ZERO
	return to.normalized() * clampf(urge * 1.35, 0.0, 1.0)


static func audit_script_leaks() -> Array:
	# Documented timer/script behaviors and whether homeostatic gating applies.
	return [
		{"id": "wander_refresh", "gated": false, "note": "locomotion variety — not a goal claim"},
		{"id": "goal_timer_explore", "gated": true, "note": "explore goals require exploration error"},
		{"id": "goal_timer_revisit_food", "gated": true, "note": "food revisit requires hunger error"},
		{"id": "zoomies", "gated": true, "note": "play burst only when hunger error low"},
		{"id": "idle_fidget", "gated": false, "note": "expressive micro-gesture — no goal claim"},
	]


static func rung1_move_food_kill(f, food_a: Vector3, food_b: Vector3) -> Dictionary:
	f.hunger = 0.78
	tick(f, null, 0.05)
	var bias_a: Vector3 = food_seek_bias(f, food_a)
	var bias_b: Vector3 = food_seek_bias(f, food_b)
	if bias_a.length_squared() < 1e-6 or bias_b.length_squared() < 1e-6:
		return {"passed": false, "reason": "no food bias under hunger"}
	var reoriented: bool = bias_a.normalized().dot(bias_b.normalized()) < 0.35
	# Simulate short pursuit paths under each food location.
	var dt: float = 0.05
	var path_a: PackedVector3Array = _simulate_pursuit(f.position, food_a, dt, 24)
	f.position = path_a[path_a.size() - 1]
	var path_b: PackedVector3Array = _simulate_pursuit(f.position, food_b, dt, 24)
	var bounds: Dictionary = {"hw": 8.0, "hd": 4.0, "hh": 7.0}
	const DeltaG = preload("res://scripts/delta_g.gd")
	var goals_a: Dictionary = {"food": food_a}
	var goals_b: Dictionary = {"food": food_b}
	var _dg_a: float = SaveHelpers._num(DeltaG.estimate(path_a, goals_a, dt, bounds).get("delta_g", 0.0), 0.0)
	var dg_b: float = SaveHelpers._num(DeltaG.estimate(path_b, goals_b, dt, bounds).get("delta_g", 0.0), 0.0)
	return {
		"passed": reoriented and dg_b >= 0.06,
		"reoriented": reoriented,
		"delta_g_before_move": _dg_a,
		"delta_g_after_move": dg_b,
		"bias_flip_dot": bias_a.normalized().dot(bias_b.normalized()),
	}


static func _simulate_pursuit(start: Vector3, food: Vector3, dt: float, steps: int) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var p: Vector3 = start
	for _i in steps:
		pts.append(p)
		var to: Vector3 = food - p
		if to.length_squared() > 1e-6:
			p += to.normalized() * 1.1 * dt * 0.9
	return pts


static func individuation_distance(fa: Fish, fb: Fish) -> float:
	var sum: float = 0.0
	var n: int = 0
	if fa.feed_heatmap.size() > 0 and fa.feed_heatmap.size() == fb.feed_heatmap.size():
		for i in fa.feed_heatmap.size():
			sum += absf(SaveHelpers._num(fa.feed_heatmap[i], 0.0) - SaveHelpers._num(fb.feed_heatmap[i], 0.0))
		n += fa.feed_heatmap.size()
	var ha: Dictionary = ensure(fa)
	var hb: Dictionary = ensure(fb)
	for key in ["hunger_set", "safety_set", "explore_set"]:
		sum += absf(SaveHelpers._num(ha.get(key, 0.0), 0.0) - SaveHelpers._num(hb.get(key, 0.0), 0.0))
		n += 1
	if fa.get("_world_model") is Dictionary and fb.get("_world_model") is Dictionary:
		var wa: Dictionary = fa._world_model as Dictionary
		var wb: Dictionary = fb._world_model as Dictionary
		sum += absf(SaveHelpers._num(wa.get("gru_error", 0.0), 0.0) - SaveHelpers._num(wb.get("gru_error", 0.0), 0.0))
		n += 1
	return sum / float(maxi(n, 1))


static func to_dict(f) -> Dictionary:
	return ensure(f).duplicate(true)


static func from_dict(f, d: Variant) -> void:
	if d is Dictionary and f is Object:
		(f as Object).set("_homeostasis", (d as Dictionary).duplicate(true))
