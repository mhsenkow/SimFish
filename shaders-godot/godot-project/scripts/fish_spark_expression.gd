extends RefCounted

# SENTIENCE_THE_SPARK §A — mind state → legible motion + shader expression.
# Grounded in real Fish / MindState fields only; never invents cognition.

const FishBinding = preload("res://scripts/fish_binding.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FishVolition = preload("res://scripts/fish_volition.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishConcepts = preload("res://scripts/fish_concepts.gd")
const MindSelfModel = preload("res://scripts/mind_self_model.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const SCHEMA_VERSION: int = 1


static func enabled() -> bool:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var st: SceneTree = ml as SceneTree
		if st.root != null:
			var cfg: Node = st.root.get_node_or_null("/root/TankConfig")
			if cfg != null and cfg.get("spark_expression_enabled") != null:
				return bool(cfg.spark_expression_enabled)
	return true


static func ensure(f: Fish) -> Dictionary:
	if f.get("_spark_state") == null or not (f._spark_state is Dictionary):
		f._spark_state = {
			"schema_version": SCHEMA_VERSION,
			"prev_ignited": false,
			"ignition_beat": 0.0,
			"pred_err_shimmer": 0.0,
			"veto_hitch": 0.0,
			"startle_flash": 0.0,
			"fragmented_off": 0.0,
		}
	return f._spark_state as Dictionary


static func gather_signals(f: Fish, ms, dt: float) -> Dictionary:
	var st: Dictionary = ensure(f)
	var sig: Dictionary = {
		"pred_err": float(f._prediction_error if f._prediction_error != null else 0.0),
		"ignited": bool(f._workspace_ignited),
		"ignition_edge": bool(f._workspace_ignited) and not bool(st.get("prev_ignited", false)),
		"stance": str(f._life_stance if f._life_stance != null else ""),
		"longing": float(f._longing_residue if f._longing_residue != null else 0.0),
		"confidence": 1.0,
		"effort": 0.0,
		"will_pool": 1.0,
		"intention_hold": "",
		"qualia_contrast": 0.0,
		"fragmented": false,
		"phi_proxy": 0.0,
		"present_width": 1.0,
		"gill_rhythm": 1.0,
		"fin_tension": 0.0,
		"fatigue": 0.0,
		"gut_fullness": 0.5,
		"valence": 0.0,
		"arousal": 0.0,
		"proto_scarcity": false,
		"proto_safety": false,
		"vitality": 1.0,
	}
	st["prev_ignited"] = bool(f._workspace_ignited)
	if ms != null and ms.self_model is Dictionary:
		sig["confidence"] = float((ms.self_model as Dictionary).get("confidence", 1.0))
	elif f.get("_mind_self_model") is Dictionary:
		sig["confidence"] = float((f._mind_self_model as Dictionary).get("confidence", 1.0))
	if FeltSelfLayer.layer_enabled():
		var vol: Dictionary = FishVolition.ensure(f)
		sig["effort"] = float(vol.get("effort", 0.0))
		sig["will_pool"] = float(vol.get("will_pool", 1.0))
		sig["intention_hold"] = str(vol.get("intention_hold", ""))
		var q: Dictionary = FishQualia.ensure(f)
		var objs: Dictionary = q.get("objects", {})
		if objs.has("contrast"):
			sig["qualia_contrast"] = float((objs["contrast"] as Dictionary).get("delta", 0.0))
		var bd: Dictionary = FishBinding.ensure(f)
		sig["fragmented"] = bool(bd.get("fragmented", false))
		sig["phi_proxy"] = float(bd.get("phi_proxy", 0.0))
		var fn: Dictionary = FishFeltNow.ensure(f)
		sig["present_width"] = float(fn.get("present_width", 1.0))
		var ps: Dictionary = FishProtoself.ensure(f)
		sig["gill_rhythm"] = float(ps.get("gill_rhythm", 1.0))
		sig["fin_tension"] = float(ps.get("fin_tension", 0.0))
		sig["fatigue"] = float(ps.get("fatigue", 0.0))
		sig["gut_fullness"] = float(ps.get("gut_fullness", 0.5))
		var proto_a: Array = FishConcepts.ensure(f).get("proto", [])
		sig["proto_scarcity"] = proto_a.has("scarcity")
		sig["proto_safety"] = proto_a.has("safety")
	sig["valence"] = FishCoreAffect.valence(f)
	sig["arousal"] = float(f.arousal if f.get("arousal") != null else 0.0)
	sig["vitality"] = clampf(1.0 - f.stress * 0.55 - f.hunger * 0.25, 0.15, 1.0)
	# Transient beats decay.
	if bool(st.get("ignition_edge", false)) or sig["ignition_edge"]:
		st["ignition_beat"] = 0.35
	st["ignition_beat"] = maxf(0.0, float(st.get("ignition_beat", 0.0)) - dt)
	var pe: float = sig["pred_err"]
	if pe > 0.32:
		st["pred_err_shimmer"] = clampf(pe, 0.0, 1.0)
	st["pred_err_shimmer"] = maxf(0.0, float(st.get("pred_err_shimmer", 0.0)) - dt * 2.5)
	if float(st.get("veto_hitch", 0.0)) > 0.0:
		st["veto_hitch"] = maxf(0.0, float(st["veto_hitch"]) - dt * 3.0)
	if sig["fragmented"]:
		st["fragmented_off"] = 0.45
	st["fragmented_off"] = maxf(0.0, float(st.get("fragmented_off", 0.0)) - dt)
	if f._startle_remaining > 0.05 and float(st.get("startle_flash", 0.0)) <= 0.0:
		st["startle_flash"] = 0.22
	st["startle_flash"] = maxf(0.0, float(st.get("startle_flash", 0.0)) - dt * 4.0)
	f._spark_state = st
	f._spark_signals = sig
	return sig


static func motion_modifiers(f: Fish, sig: Dictionary) -> Dictionary:
	if sig.is_empty():
		return {}
	var mods: Dictionary = {
		"wander_scale": 1.0,
		"turn_scale": 1.0,
		"speed_scale": 1.0,
		"tail_amp": 1.0,
		"fin_spread": 1.0,
		"spacing_bias": 1.0,
		"gaze_decouple": false,
		"stillness": 0.0,
		"listless": 0.0,
	}
	var conf: float = float(sig.get("confidence", 1.0))
	mods["turn_scale"] = lerpf(0.72, 1.12, conf)
	mods["wander_scale"] = lerpf(0.55, 1.05, conf)
	var stance: String = str(sig.get("stance", ""))
	match stance:
		"playful":
			mods["fin_spread"] = 1.18
			mods["tail_amp"] = 1.14
			mods["spacing_bias"] = 0.92
		"wary":
			mods["fin_spread"] = 0.82
			mods["tail_amp"] = 0.88
			mods["spacing_bias"] = 1.22
		"curious":
			mods["fin_spread"] = 1.08
			mods["wander_scale"] *= 1.12
		"trusting":
			mods["fin_spread"] = 1.05
			mods["speed_scale"] = 1.06
		"steadfast":
			mods["tail_amp"] = 0.96
	var longing: float = float(sig.get("longing", 0.0))
	if longing > 0.08:
		mods["speed_scale"] *= lerpf(1.0, 0.78, longing)
		mods["wander_scale"] *= lerpf(1.0, 0.65, longing)
	var effort: float = float(sig.get("effort", 0.0))
	var will_p: float = float(sig.get("will_pool", 1.0))
	mods["tail_amp"] *= lerpf(1.0, 1.22, effort)
	if will_p < 0.45:
		mods["speed_scale"] *= lerpf(0.92, 0.72, 1.0 - will_p)
	if str(sig.get("intention_hold", "")) != "":
		mods["wander_scale"] *= 0.42
	var fragmented_off: float = 0.0
	if f.get("_spark_state") is Dictionary:
		fragmented_off = float((f._spark_state as Dictionary).get("fragmented_off", 0.0))
	if fragmented_off > 0.05 or bool(sig.get("fragmented", false)):
		mods["gaze_decouple"] = false
		mods["stillness"] = maxf(mods["stillness"], fragmented_off)
	if bool(sig.get("proto_scarcity", false)):
		mods["wander_scale"] *= 0.75
		mods["spacing_bias"] *= 0.88
	if bool(sig.get("proto_safety", false)):
		mods["wander_scale"] *= 1.15
		mods["speed_scale"] *= 1.08
	var flat_affect: bool = absf(float(sig.get("valence", 0.0))) < 0.12 \
			and float(sig.get("arousal", 0.0)) < 0.18 and f.stress < 0.35
	if flat_affect and f.curiosity_drive < 0.2:
		mods["listless"] = 0.55
	if f._asleep:
		mods["fin_spread"] = minf(float(mods.get("fin_spread", 1.0)), 0.58)
		mods["tail_amp"] = minf(float(mods.get("tail_amp", 1.0)), 0.52)
		mods["speed_scale"] *= 0.72
		mods["stillness"] = maxf(float(mods.get("stillness", 0.0)), 0.35)
	var st: Dictionary = ensure(f)
	if float(st.get("ignition_beat", 0.0)) > 0.05:
		mods["stillness"] = maxf(mods["stillness"], float(st.get("ignition_beat", 0.0)))
		mods["gaze_decouple"] = true
	if float(st.get("veto_hitch", 0.0)) > 0.05:
		mods["speed_scale"] *= 0.35
		mods["turn_scale"] *= 1.65
	f._spark_motion = mods
	return mods


static func notify_veto(f: Fish) -> void:
	var st: Dictionary = ensure(f)
	st["veto_hitch"] = 0.55
	f._spark_state = st


static func apply_shaders(f: Fish, sig: Dictionary) -> void:
	if sig.is_empty() or f.get("_dying") == true:
		return
	var st: Dictionary = ensure(f)
	var pe_sh: float = float(st.get("pred_err_shimmer", 0.0))
	var qc: float = float(sig.get("qualia_contrast", 0.0))
	var vitality: float = float(sig.get("vitality", 1.0))
	var longing: float = float(sig.get("longing", 0.0))
	var fragmented_off: float = float(st.get("fragmented_off", 0.0))
	var irid: float = clampf(pe_sh * 0.85 + vitality * 0.15, 0.0, 1.0)
	if fragmented_off > 0.05:
		irid *= 0.25
	var vibrancy: float = 1.0 + qc * 0.35 - longing * 0.18
	if f._asleep:
		vibrancy *= 0.62
		irid *= 0.55
	Fish._walk_fauna_material_nodes(f, func(mi: Node, sm: ShaderMaterial) -> void:
		var mat_sm: ShaderMaterial = sm
		if not mi.has_meta("spark_owned") and not mi.has_meta("fauna_mat_owned"):
			if mat_sm.get_shader_parameter("irid_strength") != null \
					or mat_sm.get_shader_parameter("color_vibrancy") != null \
					or mat_sm.get_shader_parameter("belly_flash") != null \
					or mat_sm.get_shader_parameter("fin_translucency") != null:
				mi.material_override = mat_sm.duplicate() as ShaderMaterial
				mi.set_meta("fauna_mat_owned", true)
				mat_sm = mi.material_override as ShaderMaterial
		if mat_sm.get_shader_parameter("irid_strength") != null:
			var base_irid: float = 0.35
			if f.get("genome") is Dictionary:
				base_irid = clampf(float((f.genome as Dictionary).get("iridescence", 0.35)), 0.0, 1.0)
			mat_sm.set_shader_parameter("irid_strength", irid * base_irid)
		var mat_vibrancy: float = vibrancy
		if mat_sm.get_shader_parameter("color_vibrancy") != null:
			mat_sm.set_shader_parameter("color_vibrancy", clampf(mat_vibrancy, 0.55, 1.65))
		if mat_sm.get_shader_parameter("fin_translucency") != null:
			var fin_t: float = 0.0
			if f.maturity == 0:
				fin_t = clampf(0.62 + f.eye_size_factor * 0.12, 0.0, 0.92)
				mat_vibrancy = minf(mat_vibrancy, 0.88)
				mat_sm.set_shader_parameter("color_vibrancy", clampf(mat_vibrancy, 0.55, 1.65))
			var nicks: int = f._fin_nicks
			if nicks > 0:
				fin_t = maxf(fin_t, clampf(float(nicks) * 0.08, 0.0, 0.55))
				var wear: float = clampf(float(nicks) * 0.06, 0.0, 0.35)
				var cur_irid: float = float(mat_sm.get_shader_parameter("irid_strength"))
				mat_sm.set_shader_parameter("irid_strength", cur_irid * (1.0 - wear))
			mat_sm.set_shader_parameter("fin_translucency", fin_t))


static func tank_phi_coherence(fish_list: Array) -> float:
	if fish_list.is_empty() or not FeltSelfLayer.layer_enabled():
		return 0.5
	var sum: float = 0.0
	var n: int = 0
	for f in fish_list:
		if f is Fish and is_instance_valid(f) and f.get("_dying") != true:
			var bd: Dictionary = FishBinding.ensure(f)
			sum += float(bd.get("phi_proxy", 0.0))
			n += 1
	return sum / float(maxi(n, 1))


static func tick(f: Fish, ms, dt: float) -> void:
	if not enabled() or f == null or f.get("_dying") == true:
		return
	var sig: Dictionary = gather_signals(f, ms, dt)
	motion_modifiers(f, sig)
	apply_shaders(f, sig)
