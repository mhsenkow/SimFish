extends RefCounted

# class_name intentionally omitted — callers preload this script as
# `const MindWorldModel = preload(...)`.

# SENTIENCE_THE_DARING_MIND §D/E — lite generative / forward model per fish.

const FishMindScience = preload("res://scripts/fish_mind_science.gd")

const STATE_DIM: int = 6
# 1B / META #3 — GRU-lite (Minimal Gated Unit) recurrent world model. The MGU has
# a single forget gate (half a GRU's params) — a recognized lite variant. It gives
# the model TEMPORAL MEMORY the memoryless linear predictor lacked, so prediction
# error reflects "is this surprising given the recent trajectory", not just the
# instant. Seeded per-fish from the id (deterministic), persisted, and folded into
# `variance` (info gain) by a small centered nudge so it sharpens active inference
# (1A) without destabilising the behaviour-driving error/variance ranges.
const GRU_HIDDEN: int = 8
const GRU_OUT: int = 3   # predicts next [hunger, stress, curiosity]


static func ensure_model(f: Fish) -> Dictionary:
	if f.get("_world_model") == null or not (f._world_model is Dictionary):
		f._world_model = {
			"weights": _default_weights(),
			"predicted": Vector3.ZERO,
			"error": 0.0,
			"variance": 0.35,
			"updates": 0,
		}
	var m: Dictionary = f._world_model
	# Migration: a save may carry a malformed/empty linear weight vector — backfill
	# so the linear tick can't read out of bounds.
	if not (m.get("weights") is PackedFloat32Array) \
			or (m["weights"] as PackedFloat32Array).size() < STATE_DIM:
		m["weights"] = _default_weights()
	# Migration: old saves have the linear dict but no GRU — add it lazily.
	if not m.has("h"):
		m["gw"] = _gru_init(f)
		m["h"] = _zeros(GRU_HIDDEN)
		m["gru_pred"] = _zeros(GRU_OUT)
		m["gru_error"] = 0.0
		f._world_model = m
	return m


static func _default_weights() -> PackedFloat32Array:
	var w: PackedFloat32Array = PackedFloat32Array()
	w.resize(STATE_DIM)
	for i in STATE_DIM:
		w[i] = 0.15 + float(i) * 0.04
	return w


# --- GRU-lite (MGU) primitives -------------------------------------------------

static func _zeros(n: int) -> PackedFloat32Array:
	var a: PackedFloat32Array = PackedFloat32Array()
	a.resize(n)
	return a


# Seeded weight init, deterministic from the fish id (same id → same model, so a
# replay reproduces the fish's mind). Small uniform weights keep the cell stable.
static func _gru_init(f: Fish) -> Dictionary:
	var id_str: String = String(f.id) if f.get("id") != null else "anon"
	var rng := RandomNumberGenerator.new()
	rng.seed = SimRng.stream_seed(0x5EED, SimRng.entity_stream_name("world_model_gru", id_str))
	return {
		"Wf": _rand_mat(rng, GRU_HIDDEN * STATE_DIM), "Uf": _rand_mat(rng, GRU_HIDDEN * GRU_HIDDEN),
		"bf": _zeros(GRU_HIDDEN),
		"Wh": _rand_mat(rng, GRU_HIDDEN * STATE_DIM), "Uh": _rand_mat(rng, GRU_HIDDEN * GRU_HIDDEN),
		"bh": _zeros(GRU_HIDDEN),
		"Wo": _rand_mat(rng, GRU_OUT * GRU_HIDDEN), "bo": _zeros(GRU_OUT),
	}


static func _rand_mat(rng: RandomNumberGenerator, n: int) -> PackedFloat32Array:
	var a: PackedFloat32Array = PackedFloat32Array()
	a.resize(n)
	for i in n:
		a[i] = rng.randf_range(-0.4, 0.4)
	return a


# out[r] = b[r] + sum_c W[r*cols + c] * x[c]
static func _matvec(w: PackedFloat32Array, rows: int, cols: int,
		x: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(rows)
	for r in rows:
		var s: float = b[r]
		var base: int = r * cols
		for c in cols:
			s += w[base + c] * x[c]
		out[r] = s
	return out


# One MGU step: f = σ(Wf·x + Uf·h); h~ = tanh(Wh·x + Uh·(f⊙h)); h' = (1-f)⊙h + f⊙h~.
# Mutates m["h"] and returns the readout prediction (GRU_OUT) plus the mean gate.
static func _gru_step(m: Dictionary, x: PackedFloat32Array) -> Dictionary:
	var gw: Dictionary = m["gw"]
	var h: PackedFloat32Array = m["h"]
	var fx: PackedFloat32Array = _matvec(gw["Wf"], GRU_HIDDEN, STATE_DIM, x, gw["bf"])
	var fh: PackedFloat32Array = _matvec(gw["Uf"], GRU_HIDDEN, GRU_HIDDEN, h, _zeros(GRU_HIDDEN))
	var gate: PackedFloat32Array = _zeros(GRU_HIDDEN)
	var fh_x_h: PackedFloat32Array = _zeros(GRU_HIDDEN)
	var gate_sum: float = 0.0
	for i in GRU_HIDDEN:
		gate[i] = 1.0 / (1.0 + exp(-(fx[i] + fh[i])))
		gate_sum += gate[i]
		fh_x_h[i] = gate[i] * h[i]
	var cx: PackedFloat32Array = _matvec(gw["Wh"], GRU_HIDDEN, STATE_DIM, x, gw["bh"])
	var ch: PackedFloat32Array = _matvec(gw["Uh"], GRU_HIDDEN, GRU_HIDDEN, fh_x_h, _zeros(GRU_HIDDEN))
	var h_new: PackedFloat32Array = _zeros(GRU_HIDDEN)
	for i in GRU_HIDDEN:
		var cand: float = tanh(cx[i] + ch[i])
		h_new[i] = (1.0 - gate[i]) * h[i] + gate[i] * cand
	m["h"] = h_new
	var raw: PackedFloat32Array = _matvec(gw["Wo"], GRU_OUT, GRU_HIDDEN, h_new, gw["bo"])
	var pred: PackedFloat32Array = _zeros(GRU_OUT)
	for o in GRU_OUT:
		pred[o] = 1.0 / (1.0 + exp(-raw[o]))   # sigmoid → [0,1], matches state scale
	return {"pred": pred, "gate_mean": gate_sum / float(GRU_HIDDEN)}


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
	# 1B — recurrent GRU-lite pass: score LAST tick's prediction against the state
	# we actually landed in (predictive-processing error WITH temporal context),
	# then roll the hidden state forward and predict the next state.
	var gp: PackedFloat32Array = m.get("gru_pred", _zeros(GRU_OUT))
	var gerr: float = (absf(gp[0] - s[0]) + absf(gp[1] - s[1]) + absf(gp[2] - s[2])) / 3.0
	m["gru_error"] = lerpf(float(m.get("gru_error", 0.0)), gerr, clampf(dt * 3.0, 0.0, 1.0))
	var step: Dictionary = _gru_step(m, s)
	m["gru_pred"] = step["pred"]
	# Fold a small CENTERED nudge into variance (info gain): when the recurrent
	# model is more surprised than the linear baseline, exploration gets more
	# epistemic value (sharpens active inference, 1A); less surprised → calmer.
	# Bounded so the behaviour-driving variance range stays sane.
	m["variance"] = clampf(float(m["variance"]) + (float(m["gru_error"]) - float(m["error"])) * 0.1,
			0.1, 0.95)
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


static func _pack_to_arr(v: Variant) -> Array:
	var out: Array = []
	if v is PackedFloat32Array:
		for x in (v as PackedFloat32Array):
			out.append(x)
	return out


static func _arr_to_pack(v: Variant) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if v is Array:
		for x in (v as Array):
			out.append(float(x))
	return out


static func to_dict(f: Fish) -> Dictionary:
	var m: Dictionary = ensure_model(f).duplicate(true)
	if m.get("weights") is PackedFloat32Array:
		m["weights"] = _pack_to_arr(m["weights"])
	var p: Variant = m.get("predicted")
	if p is Vector3:
		m["predicted"] = [(p as Vector3).x, (p as Vector3).y, (p as Vector3).z]
	# 1B — serialize GRU state (hidden + weight matrices + last prediction).
	if m.get("h") is PackedFloat32Array:
		m["h"] = _pack_to_arr(m["h"])
	if m.get("gru_pred") is PackedFloat32Array:
		m["gru_pred"] = _pack_to_arr(m["gru_pred"])
	if m.get("gw") is Dictionary:
		var gw: Dictionary = (m["gw"] as Dictionary).duplicate(true)
		for k in gw.keys():
			gw[k] = _pack_to_arr(gw[k])
		m["gw"] = gw
	return m


static func from_dict(f: Fish, d: Variant) -> void:
	if not d is Dictionary:
		return
	var m: Dictionary = (d as Dictionary).duplicate(true)
	if m.get("weights") is Array:
		m["weights"] = _arr_to_pack(m["weights"])
	if m.get("predicted") is Array and (m["predicted"] as Array).size() >= 3:
		var a: Array = m["predicted"]
		m["predicted"] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	# 1B — restore GRU state (or drop it so ensure_model re-seeds: old saves).
	if m.get("h") is Array:
		m["h"] = _arr_to_pack(m["h"])
	if m.get("gru_pred") is Array:
		m["gru_pred"] = _arr_to_pack(m["gru_pred"])
	if m.get("gw") is Dictionary:
		var gw: Dictionary = (m["gw"] as Dictionary).duplicate(true)
		for k in gw.keys():
			gw[k] = _arr_to_pack(gw[k])
		m["gw"] = gw
	f._world_model = m
	ensure_model(f)   # backfill any missing GRU fields for forward-compat
