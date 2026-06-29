extends RefCounted

# CONSCIOUSNESS_ENGINEERING §B — Global Workspace Theory in code.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishMindScience = preload("res://scripts/fish_mind_science.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")
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
	# 1A / META #1 — active inference: expected free energy as a DRIVE (not just a
	# reaction to surprise). High EFE = the generative model expects information gain
	# from exploring, so the fish acts to reduce uncertainty (Friston's free-energy
	# principle). Conservative rollout: named/familiar/guardian fish first. Gated off
	# when stressed — allostasis / dark-room guard: a scared fish doesn't go sightseeing.
	if (f.is_guardian or f.fish_name != "" or f.familiarity > 0.4) and f.stress < 0.6 \
			and MindAblation.enabled(MindAblation.WORLD_MODEL):
		var efe: float = MindWorldModel.expected_free_energy_explore(f)
		if efe > 0.45:
			bids.append(_bid("free_energy", efe * 0.7, ["free_energy", "explore", "novelty"]))
	if f.stress > 0.55:
		bids.append(_bid("interoception", f.stress * 0.6, ["stress", "interoception"]))
	# Retrieved episodic boost
	if f.get("_episodic_retrieval_hint") is Dictionary:
		var hint: Dictionary = f._episodic_retrieval_hint
		var hs: float = float(hint.get("salience", 0.0))
		if hs > 0.25:
			bids.append(_bid("memory", hs, ["memory", str(hint.get("kind", "past"))]))
	# 1D / META #5 — a heard inter-fish signal enters the workspace (intersubjectivity).
	var sigb: Dictionary = FishSignals.collect_signal_bid(f)
	if not sigb.is_empty() and float(sigb.get("salience", 0.0)) > 0.05:
		bids.append(sigb)
	# META #4 — predictive theory-of-mind: anticipate a learned charger before contact.
	if MindAblation.enabled(MindAblation.THEORY_OF_MIND):
		var pb: Dictionary = FishMindScience.collect_predict_bid(f)
		if not pb.is_empty():
			bids.append(pb)
	# META #8 — caution from a sleep-distilled semantic schema (learned bad region).
	var schb: Dictionary = EpisodicMemory.collect_schema_bid(f)
	if not schb.is_empty() and float(schb.get("salience", 0.0)) > 0.05:
		bids.append(schb)
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
	# MindState is the AUTHORITY for the workspace triplet (workspace / focus /
	# ignition); commit_workspace_to() mirrors it onto the fish fields the rest of
	# tick() still reads. (#14/#15 / 0E.) This also fixes a latent revert: broadcast
	# used to set ms.workspace but NOT ms.attention_focus, so MindChannel.commit's
	# apply_to_fish reverted attention_focus to its stale cycle-start value while the
	# workspace persisted — now the whole triplet moves together.
	var contents: Array = result.get("contents", [])
	ms.workspace = contents.duplicate(true)
	if contents.is_empty():
		ms.attention_focus = ""
		ms.workspace_ignited = false
		ms.commit_workspace_to(f)
		f._behavior_ws_bias = Vector3.ZERO
		return
	ms.workspace_ignited = bool(result.get("ignited", false))
	var primary: Dictionary = contents[0]
	ms.attention_focus = str(primary.get("label", ""))
	ms.commit_workspace_to(f)
	# META #9 — co-ignition (>1 winner) blends a single skirt vector from all
	# goals; a lone winner keeps the original single-goal bias.
	if contents.size() >= 2:
		blend_behavior_bias(f, contents)
	else:
		_apply_behavior_bias(f, ms.attention_focus, float(primary.get("salience", 0.0)))


static func _apply_behavior_bias(f: Fish, focus: String, salience: float) -> void:
	f._behavior_ws_bias = _bias_for(f, focus, salience)


# META #9 — the per-goal steering bias for one focus. Pure: returns the vector and
# writes nothing, so blend_behavior_bias() can sum it across co-ignited contents.
static func _bias_for(f: Fish, focus: String, salience: float) -> Vector3:
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
		"free_energy":
			# 1A — steer toward the high-uncertainty cell the world model wants to
			# resolve (epistemic foraging); fall back to a gentle forward probe.
			var t: Vector3 = MindWorldModel.curiosity_target_bias(f)
			bias = t * (0.6 + mag) if t.length_squared() > 1e-6 else f.heading * mag * 0.5
		_:
			bias = f.heading * mag * 0.3
	return bias


# META #9 — multi-goal motor blending. When the Global Workspace holds more than
# one winner (e.g. food AND threat both ignited), synthesize ONE motor vector from
# all of them — salience-weighted, primary leading — so the fish skirts toward food
# while leaning off the threat instead of the DDM flip-flopping between them frame
# to frame. A single winner reduces exactly to _bias_for (behavior preserved).
static func blend_behavior_bias(f: Fish, contents: Array) -> void:
	var blended: Vector3 = Vector3.ZERO
	var total_w: float = 0.0
	for i in contents.size():
		var c: Dictionary = contents[i]
		var sal: float = float(c.get("salience", 0.0))
		# Primary keeps full weight; secondaries fold in at 0.6 so the focus still
		# leads but a co-active threat/opportunity still bends the path.
		var w: float = maxf(sal, 0.001) * (1.0 if i == 0 else 0.6)
		blended += _bias_for(f, str(c.get("label", "")), sal) * w
		total_w += w
	if total_w > 0.0001:
		blended /= total_w
	f._behavior_ws_bias = blended


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
