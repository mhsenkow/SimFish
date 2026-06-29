extends RefCounted

# CONSCIOUSNESS_ENGINEERING §B — Global Workspace Theory in code.

const FishMind = preload("res://scripts/fish_mind.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const MindLexicon = preload("res://scripts/mind_lexicon.gd")
const MindWorldModel = preload("res://scripts/mind_world_model.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const FishFeltNow = preload("res://scripts/fish_felt_now.gd")
const FishQualia = preload("res://scripts/fish_qualia.gd")
const FeltSelfLayer = preload("res://scripts/felt_self_layer.gd")

const CAPACITY: int = 3
const IGNITION_THRESHOLD: float = 0.42
const COALITION_BONUS: float = 0.12


static func collect_bids(f: Fish, _sim: Node) -> Array:
	var bids: Array = []
	var dl: float = 1.0
	if _sim != null and _sim.has_method("daylight"):
		dl = float(_sim.daylight())
	# Sleeping fish: rest/dream dominate; don't stack threat loops in the dark.
	if f._asleep:
		var depth: float = float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0)
		bids.append(_bid("rest", 0.58 + depth * 0.32, ["rest", "night"]))
		if f._dreaming:
			bids.append(_bid("dream", 0.48 + depth * 0.22, ["dream", "night", "memory"]))
		if f.get("_dream_wisp") != null and str(f._dream_wisp) != "":
			bids.append(_bid("memory", 0.4, ["memory", "dream"]))
		if f._cached_glance_strength > 0.35:
			bids.append(_bid("player", f._cached_glance_strength * 0.5, ["player", "social"]))
		_apply_precision_and_mods(f, bids, _sim)
		return bids
	if f.spooked > 0.38 or f._startle_remaining > 0.0:
		if f._startle_remaining > 0.0 or f.spooked > 0.42 or f.stress > 0.38:
			bids.append(_bid("threat", f.spooked + 0.45, ["threat", "safety"]))
	if f.hunger > 0.45:
		bids.append(_bid("food", f.hunger + 0.1, ["food", "forage"]))
	if f._cached_glance_strength > 0.22:
		bids.append(_bid("player", f._cached_glance_strength + f.familiarity * 0.15,
				["player", "social"]))
	if f.partner != null and is_instance_valid(f.partner):
		bids.append(_bid("mate", 0.52, ["mate", "social"]))
	if f.curiosity_drive > 0.4:
		bids.append(_bid("novelty", f.curiosity_drive * 0.75, ["novelty", "explore"]))
	if f.surprise > 0.35:
		bids.append(_bid("surprise", f.surprise * 0.9, ["surprise"]))
	# META #2 — prediction error as salience (orient toward the unexpected).
	var pred_err: float = 0.0
	if f.get("_prediction_error") != null:
		pred_err = float(f._prediction_error)
	elif f.get("_world_model") is Dictionary:
		pred_err = float((f._world_model as Dictionary).get("error", 0.0))
	if pred_err > 0.28:
		bids.append(_bid("uncertainty", pred_err * 0.82, ["novelty", "explore", "prediction"]))
	if f.stress > 0.55:
		bids.append(_bid("interoception", f.stress * 0.6, ["stress", "interoception"]))
	# Retrieved episodic boost
	if f.get("_episodic_retrieval_hint") is Dictionary:
		var hint: Dictionary = f._episodic_retrieval_hint
		var hs: float = float(hint.get("salience", 0.0))
		if hs > 0.25:
			bids.append(_bid("memory", hs, ["memory", str(hint.get("kind", "past"))]))
	# DARING §A — keeper as percept
	var kb: Dictionary = KeeperInput.collect_keeper_bid(f)
	if not kb.is_empty():
		bids.append(kb)
	var gb: Dictionary = KeeperInput.collect_gaze_bid(f)
	if not gb.is_empty():
		bids.append(gb)
	var cb: Dictionary = KeeperInput.collect_cursor_bid(f)
	if not cb.is_empty():
		bids.append(cb)
	if KeeperInput.mic_enabled() and KeeperInput.mic_rms > 0.05:
		bids.append(_bid("keeper_message", KeeperInput.mic_arousal_bump(), ["keeper_message", "player"]))
	if dl < 0.32:
		var vib: float = f.spooked * 0.35 + f.arousal * 0.25
		if f._startle_remaining > 0.0:
			vib += 0.35
		# Calm night: heater hum only when actually wary, not idle arousal.
		if vib > 0.22 and (f.spooked > 0.28 or f._startle_remaining > 0.0):
			bids.append(_bid("vibration", vib + 0.2, ["sound", "lateral"]))
		elif f.stress < 0.4 and f.vigilance < 0.45:
			bids.append(_bid("night_quiet", 0.38, ["night", "rest"]))
	if FishBinding.layer_enabled():
		bids.append(FishProtoself.baseline_bid(f))
		for ob in FishProtoself.organ_bids(f):
			bids.append(ob)
	_apply_precision_and_mods(f, bids, _sim)
	return bids


static func _apply_precision_and_mods(f: Fish, bids: Array, sim: Node = null) -> void:
	var mods: Dictionary = {}
	if f.get("_bid_salience_mods") is Dictionary:
		mods = f._bid_salience_mods as Dictionary
	var keeper_text: String = ""
	if f.get("_keeper_pending") is Dictionary:
		keeper_text = str((f._keeper_pending as Dictionary).get("keeper_text", ""))
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	for b in bids:
		var label: String = str(b.get("label", ""))
		var sal: float = float(b.get("salience", 0.0))
		sal *= MindWorldModel.precision_scale(f, label)
		if dl < 0.3 and label in ["novelty", "food"]:
			sal *= lerpf(0.55, 1.0, dl / 0.3)
		if dl < 0.3 and label == "vibration":
			sal *= lerpf(1.0, 1.45, 1.0 - dl / 0.3)
		if mods.has(label):
			sal += clampf(float(mods[label]), -0.2, 0.25)
		if label == "food" and keeper_text != "":
			sal += MindLexicon.food_bid_boost(f, keeper_text)
		if FishBinding.layer_enabled():
			var phi: float = FishBinding.integration_score(f)
			if phi < 0.38 and label in ["food", "novelty", "mate", "uncertainty"]:
				sal *= lerpf(0.5, 1.0, phi / 0.38)
			if bool(FishBinding.ensure(f).get("fragmented", false)) and label == "threat":
				sal *= 1.22
		b["salience"] = maxf(0.0, sal)


static func _bid(label: String, salience: float, coalition: Array) -> Dictionary:
	return {"label": label, "salience": salience, "coalition": coalition}


static func run_competition(bids: Array) -> Dictionary:
	var sorted: Array = bids.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0)))
	var winners: Array = []
	var top_s: float = 0.0
	for b in sorted:
		var s: float = float(b.get("salience", 0.0))
		if winners.is_empty():
			winners.append(b)
			top_s = s
		elif winners.size() < CAPACITY and s >= IGNITION_THRESHOLD * 0.65:
			# Coalition: related labels merge salience
			var coal: Array = b.get("coalition", [])
			var merged: bool = false
			for w in winners:
				var wc: Array = w.get("coalition", [])
				for c in coal:
					if wc.has(c):
						w["salience"] = float(w.get("salience", 0.0)) + s * COALITION_BONUS
						merged = true
						break
				if merged:
					break
			if not merged:
				winners.append(b)
		if winners.size() >= CAPACITY:
			break
	var ignited: bool = top_s >= IGNITION_THRESHOLD
	return {"contents": winners, "ignited": ignited, "top_salience": top_s}


static func broadcast(f: Fish, result: Dictionary, ms) -> void:
	var contents: Array = result.get("contents", [])
	ms.workspace = contents.duplicate(true)
	ms.workspace_ignited = bool(result.get("ignited", false))
	f._mind_workspace = contents.duplicate(true)
	if contents.is_empty():
		f.attention_focus = ""
		f._behavior_ws_bias = Vector3.ZERO
		f._workspace_ignited = false
		return
	var primary: Dictionary = contents[0]
	f.attention_focus = str(primary.get("label", ""))
	f._workspace_ignited = ms.workspace_ignited
	_apply_behavior_bias(f, str(f.attention_focus), float(primary.get("salience", 0.0)))


static func _apply_behavior_bias(f: Fish, focus: String, salience: float) -> void:
	var bias: Vector3 = Vector3.ZERO
	var mag: float = clampf(salience, 0.0, 1.0) * 0.35
	match focus:
		"player":
			if f._cached_glance_point.length_squared() > 0.01:
				bias = (f._cached_glance_point - f.position).normalized() * mag
		"keeper_message":
			if f._cached_glance_point.length_squared() > 0.01:
				bias = (f._cached_glance_point - f.position).normalized() * mag * (0.5 + f.familiarity * 0.5)
		"being_watched":
			if f._cached_glance_point.length_squared() > 0.01:
				var toward: Vector3 = (f._cached_glance_point - f.position).normalized()
				if f._trait("boldness") > 0.52 and f.familiarity > 0.35:
					bias = toward * mag
				else:
					bias = -toward * mag * 0.65
		"food":
			bias = Vector3(0.0, mag * 0.6, 0.0)
		"threat":
			bias = -f.heading * mag
		"night_quiet", "rest", "dream":
			bias = Vector3.ZERO
		"mate":
			if f.partner != null and is_instance_valid(f.partner):
				bias = (f.partner.position - f.position).normalized() * mag
		"memory":
			if f.get("_episodic_retrieval_hint") is Dictionary:
				var pos: Variant = (f._episodic_retrieval_hint as Dictionary).get("pos", null)
				if pos is Vector3 and (pos as Vector3).is_finite():
					bias = ((pos as Vector3) - f.position).normalized() * mag * 0.7
		_:
			bias = f.heading * mag * 0.3
	f._behavior_ws_bias = bias


static func encode_from_workspace(f: Fish, ms) -> void:
	if not ms.workspace_ignited or ms.workspace.is_empty():
		return
	var primary: Dictionary = ms.workspace[0]
	var label: String = str(primary.get("label", "moment"))
	if not f.try_mark_workspace_encode(label):
		return
	var text: String = ""
	if FeltSelfLayer.layer_enabled():
		text = FishFeltNow.encode_moment_text(f)
		if text == "":
			text = FishQualia.report_line(f)
	if text == "":
		text = f.workspace_thought_for(label)
	FishMind.record_salient(f, label, text, float(primary.get("salience", 0.5)), f.position)
