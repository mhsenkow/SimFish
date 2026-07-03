extends RefCounted

# SENTIENCE_THE_RISING_CURVE §C — ΔG_robust developmental log per fish.

const SCHEMA_VERSION: int = 1
const MAX_SAMPLES: int = 96
const FLAT_SLOPE_EPS: float = 0.00008


static func ensure(f: Fish) -> Dictionary:
	if not f._delta_g_curve.has("samples"):
		f._delta_g_curve = {
			"schema_version": SCHEMA_VERSION,
			"samples": [],
			"milestones": [],
			"last_robust": 0.0,
			"last_delta_g": 0.0,
			"last_goal": "",
			"gen_gap": 0.0,
		}
	return f._delta_g_curve as Dictionary


static func record_estimate(f: Fish, est: Dictionary, robustness: float = -1.0) -> void:
	var c: Dictionary = ensure(f)
	c["last_delta_g"] = float(est.get("delta_g", 0.0))
	c["last_goal"] = str(est.get("goal", ""))
	if robustness >= 0.0:
		record_robustness(f, robustness, float(est.get("delta_g", 0.0)))
	else:
		f._delta_g_curve = c


static func record_generalization_gap(f: Fish, gap: float) -> void:
	var c: Dictionary = ensure(f)
	c["gen_gap"] = gap
	f._delta_g_curve = c


static func record_robustness(f: Fish, robust: float, delta_g: float) -> void:
	var c: Dictionary = ensure(f)
	var samples: Array = c.get("samples", [])
	samples.append({
		"age": float(f.age if f.get("age") != null else 0.0),
		"tick": Engine.get_physics_frames(),
		"robust": clampf(robust, 0.0, 2.0),
		"delta_g": delta_g,
	})
	while samples.size() > MAX_SAMPLES:
		samples.pop_front()
	c["samples"] = samples
	c["last_robust"] = robust
	_try_milestone(f, c, robust)
	f._delta_g_curve = c


static func slope(f: Fish) -> float:
	var samples: Array = ensure(f).get("samples", [])
	if samples.size() < 2:
		return 0.0
	var a0: Dictionary = samples[0]
	var a1: Dictionary = samples[-1]
	var dt_age: float = float(a1.get("age", 0.0)) - float(a0.get("age", 0.0))
	if dt_age < 1.0:
		return 0.0
	return (float(a1.get("robust", 0.0)) - float(a0.get("robust", 0.0))) / dt_age


static func tank_aggregate(fish_list: Array) -> Dictionary:
	var vals: Array = []
	for item in fish_list:
		if item == null or not is_instance_valid(item) or not item is Fish:
			continue
		vals.append(float(ensure(item as Fish).get("last_robust", 0.0)))
	if vals.is_empty():
		return {"mean_robust": 0.0, "count": 0}
	var sum: float = 0.0
	for v in vals:
		sum += float(v)
	return {"mean_robust": sum / float(vals.size()), "count": vals.size()}


static func summary_for(f: Fish) -> Dictionary:
	var c: Dictionary = ensure(f)
	return {
		"delta_g": float(c.get("last_delta_g", 0.0)),
		"goal": str(c.get("last_goal", "")),
		"robust": float(c.get("last_robust", 0.0)),
		"slope": slope(f),
		"flat": is_flat(f),
		"gen_gap": float(c.get("gen_gap", 0.0)),
		"milestones": (c.get("milestones", []) as Array).size(),
	}


static func is_flat(f: Fish) -> bool:
	var samples: Array = ensure(f).get("samples", [])
	if samples.size() < 5:
		return false
	return absf(slope(f)) < FLAT_SLOPE_EPS


static func biography_line(f: Fish) -> String:
	var s: Dictionary = summary_for(f)
	if float(s.get("robust", 0.0)) < 0.05 and float(s.get("delta_g", 0.0)) < 0.05:
		return ""
	if bool(s.get("flat", false)):
		return "goal-structure flat — not thriving"
	if float(s.get("slope", 0.0)) > 0.0002:
		return "goals growing sturdier (robust %.0f%%)" % (float(s.get("robust", 0.0)) * 100.0)
	if str(s.get("goal", "")) != "":
		return "moving like it wants %s" % str(s.get("goal", "")).replace("_", " ")
	return ""


static func to_dict(f: Fish) -> Dictionary:
	return ensure(f).duplicate(true)


static func from_dict(f: Fish, d: Variant) -> void:
	if d is Dictionary and not (d as Dictionary).is_empty():
		f._delta_g_curve = (d as Dictionary).duplicate(true)
		ensure(f)


static func _try_milestone(f: Fish, c: Dictionary, robust: float) -> void:
	var milestones: Array = c.get("milestones", [])
	for band in [0.55, 0.72, 0.85]:
		if robust < band:
			continue
		var tag: String = "robust_%.0f" % (band * 100.0)
		var seen: bool = false
		for m in milestones:
			if m is Dictionary and str((m as Dictionary).get("tag", "")) == tag:
				seen = true
				break
		if seen:
			continue
		milestones.append({"tag": tag, "age": float(f.age), "robust": robust})
	c["milestones"] = milestones
