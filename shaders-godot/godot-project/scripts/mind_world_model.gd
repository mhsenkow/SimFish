extends RefCounted

# class_name intentionally omitted — callers preload this script as
# `const MindWorldModel = preload(...)`.

# SENTIENCE_THE_DARING_MIND §D/E — lite generative / forward model per fish.

const FishMindScience = preload("res://scripts/fish_mind_science.gd")

const STATE_DIM: int = 6


static func ensure_model(f: Fish) -> Dictionary:
	if f.get("_world_model") == null or not (f._world_model is Dictionary):
		f._world_model = {
			"weights": _default_weights(),
			"predicted": Vector3.ZERO,
			"error": 0.0,
			"variance": 0.35,
			"updates": 0,
		}
	return f._world_model


static func _default_weights() -> PackedFloat32Array:
	var w: PackedFloat32Array = PackedFloat32Array()
	w.resize(STATE_DIM)
	for i in STATE_DIM:
		w[i] = 0.15 + float(i) * 0.04
	return w


static func state_vector(f: Fish) -> PackedFloat32Array:
	var v: PackedFloat32Array = PackedFloat32Array()
	v.resize(STATE_DIM)
	v[0] = f.hunger
	v[1] = f.stress
	v[2] = f.curiosity_drive
	v[3] = clampf(f.speed / maxf(f.max_speed, 0.1), 0.0, 1.0)
	v[4] = f.familiarity
	v[5] = f.surprise
	return v


static func tick(f: Fish, _sim: Node, dt: float) -> void:
	var m: Dictionary = ensure_model(f)
	var s: PackedFloat32Array = state_vector(f)
	var w: PackedFloat32Array = m.get("weights", _default_weights())
	var pred_hunger: float = clampf(f.hunger - dt * 0.012 * (1.0 + w[0]), 0.0, 1.0)
	var pred_stress: float = clampf(f.stress - dt * 0.08 * w[1], 0.0, 1.0)
	m["predicted"] = Vector3(pred_hunger, pred_stress, f.curiosity_drive)
	var err: float = absf(f.hunger - pred_hunger) + absf(f.stress - pred_stress) * 0.7
	err += absf(f.surprise) * 0.35
	m["error"] = lerpf(float(m.get("error", 0.0)), err, clampf(dt * 4.0, 0.0, 1.0))
	var novelty: float = clampf(f.curiosity_drive * 0.6 + f.surprise * 0.4, 0.0, 1.0)
	m["variance"] = lerpf(float(m.get("variance", 0.35)), 0.15 + novelty * 0.55, dt * 0.5)
	m["updates"] = int(m.get("updates", 0)) + 1
	# Online nudge — cheap linear adaptation
	for i in STATE_DIM:
		w[i] = clampf(w[i] + (s[i] - 0.5) * dt * 0.02, 0.05, 0.85)
	m["weights"] = w
	f._world_model = m
	f._prediction_error = float(m.get("error", 0.0))


static func imagined_threat(f: Fish, heading: Vector3) -> float:
	var m: Dictionary = ensure_model(f)
	var open: float = 1.0 - f.stress * 0.4
	var err: float = float(m.get("error", 0.0))
	if heading.length_squared() < 0.01:
		return 0.0
	return clampf(open * 0.25 + err * 0.35, 0.0, 0.75)


static func counterfactual_regret(f: Fish, missed: bool) -> void:
	if not missed:
		return
	var m: Dictionary = ensure_model(f)
	m["error"] = clampf(float(m.get("error", 0.0)) + 0.12, 0.0, 1.0)
	f._world_model = m
	f.foraging_commitment = clampf(f.foraging_commitment + 0.08, 0.0, 1.0)


static func expected_free_energy_explore(f: Fish) -> float:
	var m: Dictionary = ensure_model(f)
	var info_gain: float = float(m.get("variance", 0.35))
	var goal: float = f.curiosity_drive * 0.6 + (1.0 - f.stress) * 0.2
	return clampf(info_gain * 0.55 + goal * 0.45, 0.0, 1.0)


static func curiosity_target_bias(f: Fish) -> Vector3:
	var m: Dictionary = ensure_model(f)
	if float(m.get("error", 0.0)) < 0.18:
		return Vector3.ZERO
	var cell: String = FishMindScience.novelty_cell_key(f)
	if f._hypotheses.has(cell):
		return Vector3.ZERO
	var cog: RandomNumberGenerator = MindRng.for_fish(f)
	return Vector3(cog.randf_range(-0.4, 0.4), 0.0, cog.randf_range(-0.4, 0.4)) \
			* float(m.get("error", 0.0))


static func precision_scale(f: Fish, label: String) -> float:
	var m: Dictionary = ensure_model(f)
	var clarity: float = 1.0 - float(m.get("variance", 0.35)) * 0.65
	if label == "threat" and f.stress > 0.5:
		clarity *= 0.82
	return clampf(clarity, 0.35, 1.0)


static func to_dict(f: Fish) -> Dictionary:
	var m: Dictionary = ensure_model(f).duplicate(true)
	if m.get("weights") is PackedFloat32Array:
		var warr: Array = []
		var pw: PackedFloat32Array = m["weights"] as PackedFloat32Array
		for i in pw.size():
			warr.append(pw[i])
		m["weights"] = warr
	var p: Variant = m.get("predicted")
	if p is Vector3:
		m["predicted"] = [(p as Vector3).x, (p as Vector3).y, (p as Vector3).z]
	return m


static func from_dict(f: Fish, d: Variant) -> void:
	if not d is Dictionary:
		return
	var m: Dictionary = (d as Dictionary).duplicate(true)
	if m.get("weights") is Array:
		var w: PackedFloat32Array = PackedFloat32Array()
		for v in m["weights"]:
			w.append(float(v))
		m["weights"] = w
	if m.get("predicted") is Array and (m["predicted"] as Array).size() >= 3:
		var a: Array = m["predicted"]
		m["predicted"] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	f._world_model = m
