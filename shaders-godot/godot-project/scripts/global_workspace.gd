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
const MindActiveInference = preload("res://scripts/mind_active_inference.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")
const MindSoulPass2 = preload("res://scripts/mind_soul_pass2.gd")
const MindSoulPass3 = preload("res://scripts/mind_soul_pass3.gd")
const _MindSimSnapScript = preload("res://scripts/mind_sim_snap.gd")
const _MindBidPoolScript = preload("res://scripts/mind_bid_pool.gd")
const _MindCompetitionScript = preload("res://scripts/mind_competition.gd")

const CAPACITY: int = 3
const IGNITION_THRESHOLD: float = 0.42
const COALITION_BONUS: float = 0.12
const _COMP_TOP_K: int = CAPACITY * 2  # PERFORMANCE_UNTHROTTLED #13

# PERFORMANCE_UNTHROTTLED #16 — hot label literals as StringName (no per-bid array alloc).
const _LN_FOOD: StringName = &"food"
const _LN_NOVELTY: StringName = &"novelty"
const _LN_MATE: StringName = &"mate"
const _LN_UNCERTAINTY: StringName = &"uncertainty"
const _LN_THREAT: StringName = &"threat"
const _LN_VIBRATION: StringName = &"vibration"
const _COAL_TAG_BITS: Dictionary = {
	"food": 1, "forage": 2, "threat": 4, "safety": 8, "mate": 16, "social": 32,
	"novelty": 64, "explore": 128, "memory": 256, "past": 512, "night": 1024,
	"rest": 2048, "dream": 4096, "player": 8192, "stress": 16384, "interoception": 32768,
	"prediction": 65536, "free_energy": 131072, "surprise": 262144, "sound": 524288,
	"lateral": 1048576, "keeper_message": 2097152, "vibration": 4194304,
}


static func _coal_mask(coalition: Array) -> int:
	var m: int = 0
	for c in coalition:
		var key: String = str(c)
		if _COAL_TAG_BITS.has(key):
			m |= int(_COAL_TAG_BITS[key])
	return m


static func _coalitions_overlap(a: Array, b: Array, mask_a: int, mask_b: int) -> bool:
	if mask_a != 0 and mask_b != 0:
		return (mask_a & mask_b) != 0
	for c in a:
		if b.has(c):
			return true
	return false

const _BID_EPS: float = 0.02  # PERFORMANCE_UNTHROTTLED #4
const SLOW_LANE_HZ: float = 3.0
const DIRTY_FEED: int = 1
const DIRTY_KEEPER: int = 2
const DIRTY_DAY: int = 4


# META #12 — bid-generator registry
# (territoriality, play, grief, a mod) registers a Callable(f, sim) -> Array[bid]
# instead of editing this kernel. Registered generators run on top of the built-in
# bids (additive — existing behaviour is unchanged), then go through the same
# precision/coalition pipeline. A bad generator can't crash the cycle.
static var _bid_generators: Array = []


static func register_bid_generator(cb: Callable) -> void:
	if cb.is_valid() and not _bid_generators.has(cb):
		_bid_generators.append(cb)


static func unregister_bid_generator(cb: Callable) -> void:
	_bid_generators.erase(cb)


static func clear_bid_generators() -> void:
	_bid_generators.clear()


# Run every registered generator and append its (validated) bids.
static func _append_registered(f, sim, bids: Array) -> void:
	for cb in _bid_generators:
		if not (cb is Callable) or not (cb as Callable).is_valid():
			continue
		var extra: Variant = (cb as Callable).call(f, sim)
		if not (extra is Array):
			continue
		for b in (extra as Array):
			if b is Dictionary and (b as Dictionary).has("label") \
					and float((b as Dictionary).get("salience", 0.0)) > 0.0:
				bids.append(b)


static func mark_bid_dirty(f, flag: int) -> void:
	if f == null:
		return
	f._bid_dirty = int(f.get("_bid_dirty") if f.get("_bid_dirty") != null else 0) | flag


static func _slow_lane_due(f) -> bool:
	if f.get("_bid_dirty") != null and int(f._bid_dirty) != 0:
		return true
	return bool(f.get("_bid_slow_due"))


static func _decay_cached_bids(cached: Array, dt: float) -> void:
	var k: float = maxf(0.0, 1.0 - dt * 0.35)
	for b in cached:
		if b is Dictionary:
			var d: Dictionary = b as Dictionary
			d["salience"] = float(d.get("salience", 0.0)) * k


static func _collect_fast_bids(f, _sim, dl: float, use_efe: bool, bids: Array) -> void:
	if f.spooked > 0.38 or f._startle_remaining > 0.0:
		if f._startle_remaining > 0.0 or f.spooked > 0.42 or f.stress > 0.38:
			var thr_s: float = f.spooked + 0.45
			if use_efe:
				thr_s = MindActiveInference.efe_salience(f, "threat")
			bids.append(_bid(f,"threat", thr_s, ["threat", "safety"], use_efe))
	if f._cached_glance_strength > 0.22:
		bids.append(_bid(f,"player", f._cached_glance_strength + f.familiarity * 0.15,
				["player", "social"]))
	if f.get("_player_watched") == true and f._cached_glance_strength > 0.12:
		bids.append(_bid(f,"being_watched", f._cached_glance_strength * 0.85 + 0.12,
				["player", "social"]))
	var sigb: Dictionary = FishSignals.collect_signal_bid(f)
	if not sigb.is_empty() and float(sigb.get("salience", 0.0)) > 0.05:
		bids.append(sigb)
	if MindAblation.enabled(MindAblation.THEORY_OF_MIND):
		var pb: Dictionary = FishMindScience.collect_predict_bid(f)
		if not pb.is_empty():
			bids.append(pb)
	var kb: Dictionary = KeeperInput.collect_keeper_bid(f)
	if not kb.is_empty():
		bids.append(kb)
		mark_bid_dirty(f, DIRTY_KEEPER)
	var gb: Dictionary = KeeperInput.collect_gaze_bid(f)
	if not gb.is_empty():
		bids.append(gb)
	var cb: Dictionary = KeeperInput.collect_cursor_bid(f)
	if not cb.is_empty():
		bids.append(cb)
	if KeeperInput.mic_enabled() and KeeperInput.mic_rms > 0.05:
		bids.append(_bid(f,"keeper_message", KeeperInput.mic_arousal_bump(), ["keeper_message", "player"]))
	if dl < 0.32:
		var vib: float = f.spooked * 0.35 + f.arousal * 0.25
		if f._startle_remaining > 0.0:
			vib += 0.35
		if vib > 0.22 and (f.spooked > 0.28 or f._startle_remaining > 0.0):
			bids.append(_bid(f,"vibration", vib + 0.2, ["sound", "lateral"]))


static func _collect_slow_bids(f, _sim, dl: float, use_efe: bool) -> Array:
	var slow: Array = []
	if f.hunger > 0.45:
		var food_s: float = f.hunger + 0.1
		if use_efe:
			food_s = MindActiveInference.efe_salience(f, "food")
		slow.append(_bid(f,"food", food_s, ["food", "forage"], use_efe))
	if (f.get("has_mate") == true) or (f.get("partner") != null and is_instance_valid(f.get("partner"))):
		var mate_s: float = 0.52
		if use_efe:
			mate_s = MindActiveInference.efe_salience(f, "mate")
		slow.append(_bid(f,"mate", mate_s, ["mate", "social"], use_efe))
	if use_efe:
		var ep_s: float = MindActiveInference.epistemic_bid_salience(f)
		if ep_s > 0.05:
			slow.append(_bid(f,"free_energy", ep_s,
					["free_energy", "explore", "novelty", "prediction"], true))
	else:
		if f.curiosity_drive > 0.4:
			slow.append(_bid(f,"novelty", f.curiosity_drive * 0.75, ["novelty", "explore"]))
		var pred_err: float = 0.0
		if f.get("_prediction_error") != null:
			pred_err = float(f._prediction_error)
		elif f.get("_world_model") is Dictionary:
			pred_err = float((f._world_model as Dictionary).get("error", 0.0))
		if pred_err > 0.28:
			slow.append(_bid(f,"uncertainty", pred_err * 0.82, ["novelty", "explore", "prediction"]))
		if (f.is_guardian or f.fish_name != "" or f.familiarity > 0.4) and f.stress < 0.6 \
				and MindAblation.enabled(MindAblation.WORLD_MODEL):
			var efe: float = MindWorldModel.expected_free_energy_explore(f)
			if efe > 0.45:
				slow.append(_bid(f,"free_energy", efe * 0.7, ["free_energy", "explore", "novelty"]))
	if f.surprise > 0.35:
		slow.append(_bid(f,"surprise", f.surprise * 0.9, ["surprise"]))
	if f.stress > 0.55:
		var int_s: float = f.stress * 0.6
		if use_efe:
			int_s = MindActiveInference.efe_salience(f, "interoception")
		slow.append(_bid(f,"interoception", int_s, ["stress", "interoception"], use_efe))
	var boids_n: int = int(f.get("_boids_neighbor_count") if f.get("_boids_neighbor_count") != null else 0)
	if boids_n >= 3 and (f.swim_pattern == "school" or f.swim_pattern == "shoal"):
		var school_s: float = clampf(float(boids_n) / 8.0, 0.12, 0.55) * (1.0 - f.stress * 0.25)
		slow.append(_bid(f, "school", school_s, ["social", "school"]))
	if f.get("_episodic_retrieval_hint") is Dictionary:
		var hint: Dictionary = f._episodic_retrieval_hint
		var hs: float = float(hint.get("salience", 0.0))
		if hs > 0.25:
			slow.append(_bid(f,"memory", hs, ["memory", str(hint.get("kind", "past"))]))
	var schb: Dictionary = EpisodicMemory.collect_schema_bid(f)
	if not schb.is_empty() and float(schb.get("salience", 0.0)) > 0.05:
		slow.append(schb)
	if dl < 0.32 and f.stress < 0.4 and f.vigilance < 0.45:
		var nq_s: float = 0.38
		if use_efe:
			nq_s = MindActiveInference.efe_salience(f, "night_quiet")
		slow.append(_bid(f,"night_quiet", nq_s, ["night", "rest"], use_efe))
	if FishBinding.layer_enabled():
		slow.append(FishProtoself.baseline_bid(f))
		for ob in FishProtoself.organ_bids(f):
			slow.append(ob)
		var sab: Dictionary = MindSoul.self_attend_bid(f)
		if not sab.is_empty():
			slow.append(sab)
		var prob: Dictionary = MindSoulPass2.prospective_bid(f)
		if not prob.is_empty():
			slow.append(prob)
		var sab2: Dictionary = MindSoulPass2.shared_attention_bid(f, _sim)
		if not sab2.is_empty():
			slow.append(sab2)
		var tomf: Dictionary = MindSoulPass2.tom_follow_food_bid(f)
		if not tomf.is_empty():
			slow.append(tomf)
		for eb in MindSoulPass3.collect_extra_bids(f, _sim):
			slow.append(eb)
	return slow


static func collect_bids(f, _sim) -> Array:
	MindSoul.apply_hebbian_mods(f)
	var bids: Array = []
	var dl: float = MindSimSnap.daylight_of(_sim)
	var use_efe: bool = MindActiveInference.enabled_for(f, _sim)
	# Sleeping fish: rest/dream dominate; don't stack threat loops in the dark.
	if f._asleep:
		var depth: float = float(f.get("_sleep_depth") if f.get("_sleep_depth") != null else 0.0)
		var rest_s: float = 0.58 + depth * 0.32
		if use_efe:
			rest_s = MindActiveInference.efe_salience(f, "rest")
		bids.append(_bid(f,"rest", rest_s, ["rest", "night"]))
		if f._dreaming:
			bids.append(_bid(f,"dream", 0.48 + depth * 0.22, ["dream", "night", "memory"]))
		if f.get("_dream_wisp") != null and str(f._dream_wisp) != "":
			bids.append(_bid(f,"memory", 0.4, ["memory", "dream"]))
		if f._cached_glance_strength > 0.35:
			bids.append(_bid(f,"player", f._cached_glance_strength * 0.5, ["player", "social"]))
		_append_registered(f, _sim, bids)
		_apply_precision_and_mods(f, bids, _sim)
		return bids
	_collect_fast_bids(f, _sim, dl, use_efe, bids)
	if f.get("_bid_last_daylight") != null and absf(float(f._bid_last_daylight) - dl) > 0.08:
		mark_bid_dirty(f, DIRTY_DAY)
	f._bid_last_daylight = dl
	var slow_cache: Variant = f.get("_bid_slow_cache")
	if _slow_lane_due(f) or not (slow_cache is Array) or (slow_cache as Array).is_empty():
		f._bid_slow_cache = _collect_slow_bids(f, _sim, dl, use_efe)
		f._bid_slow_accum = 0.0
		f._bid_dirty = 0
		f._bid_slow_due = false
	elif f.get("_bid_slow_cache") is Array:
		_decay_cached_bids(f._bid_slow_cache as Array, 1.0 / maxf(SLOW_LANE_HZ, 1.0))
	for sb in (f._bid_slow_cache if f.get("_bid_slow_cache") is Array else []):
		bids.append(sb)
	_append_registered(f, _sim, bids)
	_apply_precision_and_mods(f, bids, _sim)
	return bids


static func bids_digest(bids: Array) -> int:
	var h: int = 0
	for b in bids:
		if not (b is Dictionary):
			continue
		var d: Dictionary = b as Dictionary
		h = (h * 31 + hash(str(d.get("label", "")))) & 0x7fffffff
		h = (h * 31 + int(snappedf(float(d.get("salience", 0.0)), _BID_EPS) * 100.0)) & 0x7fffffff
	return h


static func competition_digest(result: Dictionary) -> int:
	var h: int = 1 if bool(result.get("ignited", false)) else 0
	for w in result.get("contents", []):
		if not (w is Dictionary):
			continue
		var d: Dictionary = w as Dictionary
		h = (h * 31 + hash(str(d.get("label", "")))) & 0x7fffffff
		h = (h * 31 + int(snappedf(float(d.get("salience", 0.0)), _BID_EPS) * 100.0)) & 0x7fffffff
	return h


static func resolve_competition(f, bids: Array) -> Dictionary:
	if f != null:
		var cached_dig: Variant = f.get("_ws_bids_digest")
		if cached_dig != null and int(cached_dig) == bids_digest(bids) \
				and f.get("_ws_competition_cache") is Dictionary:
			return f._ws_competition_cache as Dictionary
	var result: Dictionary = run_competition(bids)
	if f != null:
		f.set("_ws_bids_digest", bids_digest(bids))
		f.set("_ws_competition_cache", result)
	return result


static func broadcast_if_changed(f, result: Dictionary, ms) -> void:
	_broadcast_ms(result, ms)
	var dig: int = competition_digest(result)
	if f != null:
		var prev_dig: Variant = f.get("_ws_broadcast_digest")
		if prev_dig != null and int(prev_dig) == dig:
			return
		f.set("_ws_broadcast_digest", dig)
	_broadcast_fish(f, result, ms)


static func broadcast(f, result: Dictionary, ms) -> void:
	_broadcast_ms(result, ms)
	_broadcast_fish(f, result, ms)


static func _broadcast_ms(result: Dictionary, ms) -> void:
	var contents: Array = result.get("contents", [])
	ms.workspace = contents
	if contents.is_empty():
		ms.attention_focus = ""
		ms.workspace_ignited = false
		return
	ms.workspace_ignited = bool(result.get("ignited", false))
	ms.attention_focus = str((contents[0] as Dictionary).get("label", ""))


static func _broadcast_fish(f, result: Dictionary, ms) -> void:
	# MindState is the AUTHORITY for the workspace triplet (workspace / focus /
	# ignition); commit_workspace_to() mirrors it onto the fish fields the rest of
	# tick() still reads. (#14/#15 / 0E.)
	var contents: Array = result.get("contents", [])
	if contents.is_empty():
		ms.commit_workspace_to(f)
		f._behavior_ws_bias = Vector3.ZERO
		return
	var primary: Dictionary = contents[0]
	f._last_winning_affordance = str(primary.get("affordance", ""))
	ms.commit_workspace_to(f)
	MindSoul.after_workspace_commit(f, ms, null)
	if contents.size() >= 2:
		blend_behavior_bias(f, contents)
	else:
		_apply_behavior_bias(f, ms.attention_focus, float(primary.get("salience", 0.0)))


static func cache_cycle_bias_targets(f) -> void:
	if f == null:
		return
	var feed: Vector3 = Vector3.ZERO
	if f.get("_homeostatic_feed_point") is Vector3:
		feed = f._homeostatic_feed_point as Vector3
	var mate_pos: Vector3 = Vector3.ZERO
	var partner: Variant = f.get("partner")
	if partner != null and f.get("has_mate") == true and partner is Node3D \
			and is_instance_valid(partner as Node3D):
		mate_pos = (partner as Node3D).position
	f._cycle_bias_cache = {
		"glance": f._cached_glance_point if f.get("_cached_glance_point") is Vector3 else Vector3.ZERO,
		"feed": feed,
		"mate_pos": mate_pos,
	}


static func _label_name(label: String) -> StringName:
	return StringName(label)


static func _phi_sensitive_label(ln: StringName) -> bool:
	return ln == _LN_FOOD or ln == _LN_NOVELTY or ln == _LN_MATE or ln == _LN_UNCERTAINTY


static func _apply_precision_and_mods(f, bids: Array, sim = null) -> void:
	var mods: Dictionary = {}
	var base_mods: Variant = f.get("_bid_salience_mods")
	var soul_mods: Dictionary = MindSoulPass3.salience_mods(f) if MindSoulPass3.enabled() else {}
	if base_mods is Dictionary and not (base_mods as Dictionary).is_empty():
		mods = (base_mods as Dictionary).duplicate(true)
	elif not soul_mods.is_empty():
		mods = {}
	for k in soul_mods.keys():
		mods[k] = float(mods.get(k, 0.0)) + float(soul_mods[k])
	var keeper_text: String = ""
	if f.get("_keeper_pending") is Dictionary:
		keeper_text = str((f._keeper_pending as Dictionary).get("keeper_text", ""))
	var dl: float = MindSimSnap.daylight_of(sim)
	# PERFORMANCE_UNTHROTTLED #17 — per-fish invariants once, not per bid.
	var night_food_scale: float = 1.0
	var night_vib_scale: float = 1.0
	if dl < 0.3:
		night_food_scale = lerpf(0.55, 1.0, dl / 0.3)
		night_vib_scale = lerpf(1.0, 1.45, 1.0 - dl / 0.3)
	var phi: float = 1.0
	var fragmented: bool = false
	if FishBinding.layer_enabled():
		phi = FishBinding.integration_score(f)
		fragmented = bool(FishBinding.ensure(f).get("fragmented", false))
	for b in bids:
		var label: String = str(b.get("label", ""))
		var ln: StringName = _label_name(label)
		if not MindSoulPass2.markov_permits(f, label):
			b["salience"] = 0.0
			continue
		var sal: float = float(b.get("salience", 0.0))
		sal *= MindWorldModel.precision_scale(f, label)
		sal *= MindSoulPass2.sense_precision_scale(f, label)
		sal *= MindSoulPass2.mood_congruence_scale(f, label)
		sal += MindSoulPass2.pavlov_bid_boost(f, label)
		if dl < 0.3:
			if ln == _LN_NOVELTY or ln == _LN_FOOD:
				sal *= night_food_scale
			elif ln == _LN_VIBRATION:
				sal *= night_vib_scale
		if mods.has(label):
			sal += clampf(float(mods[label]), -0.2, 0.25)
		if ln == _LN_FOOD and keeper_text != "":
			sal += MindLexicon.food_bid_boost(f, keeper_text)
		if FishBinding.layer_enabled():
			if phi < 0.38 and _phi_sensitive_label(ln):
				sal *= lerpf(0.5, 1.0, phi / 0.38)
			if fragmented and ln == _LN_THREAT:
				sal *= 1.22
		b["salience"] = maxf(0.0, sal)


static func _bid(f, label: String, salience: float, coalition: Array,
		efe_sourced: bool = false) -> Dictionary:
	var mask: int = _coal_mask(coalition)
	if f != null:
		return _MindBidPoolScript.take(f, label, salience, coalition, mask, efe_sourced)
	return {"label": label, "salience": salience, "coalition": coalition,
			"coal_mask": mask, "efe_sourced": efe_sourced}


static func _insert_top_bid(top: Array, b: Dictionary) -> void:
	_MindCompetitionScript.insert_top_bid(top, b)


static func _competition_from_sorted(sorted: Array) -> Dictionary:
	return _MindCompetitionScript.from_sorted(sorted)


static var _kernel_script: GDScript = null


static func _kernel() -> GDScript:
	if _kernel_script == null:
		_kernel_script = load("res://scripts/mind_kernel.gd") as GDScript
	return _kernel_script


static func run_competition(bids: Array) -> Dictionary:
	if bids.is_empty():
		return {"contents": [], "ignited": false, "top_salience": 0.0}
	var kernel: GDScript = _kernel()
	if kernel != null:
		return kernel.competition(bids)
	return _MindCompetitionScript.run(bids)


static func _run_competition_sorted_legacy(bids: Array) -> Dictionary:
	var sorted: Array = bids.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("salience", 0.0)) > float(b.get("salience", 0.0)))
	return _competition_from_sorted(sorted)


static func run_competition_smoke_parity() -> bool:
	var base: Array = [
		_bid(null, "food", 0.72, ["food", "forage"]),
		_bid(null, "threat", 0.68, ["threat", "safety"]),
		_bid(null, "novelty", 0.55, ["novelty", "explore"]),
		_bid(null, "mate", 0.44, ["mate", "social"]),
		_bid(null, "player", 0.31, ["player", "social"]),
		_bid(null, "memory", 0.22, ["memory", "past"]),
		_bid(null, "rest", 0.12, ["rest", "night"]),
		_bid(null, "surprise", 0.08, ["surprise"]),
	]
	var fixture_fast: Array = []
	var fixture_slow: Array = []
	for b in base:
		fixture_fast.append((b as Dictionary).duplicate(true))
		fixture_slow.append((b as Dictionary).duplicate(true))
	var fast: Dictionary = run_competition(fixture_fast)
	var slow: Dictionary = _run_competition_sorted_legacy(fixture_slow)
	if bool(fast.get("ignited")) != bool(slow.get("ignited")):
		return false
	if absf(float(fast.get("top_salience", 0.0)) - float(slow.get("top_salience", 0.0))) > 0.0001:
		return false
	var fw: Array = fast.get("contents", [])
	var sw: Array = slow.get("contents", [])
	if fw.size() != sw.size():
		return false
	for i in fw.size():
		if str((fw[i] as Dictionary).get("label", "")) != str((sw[i] as Dictionary).get("label", "")):
			return false
		if absf(float((fw[i] as Dictionary).get("salience", 0.0))
				- float((sw[i] as Dictionary).get("salience", 0.0))) > 0.0001:
			return false
	return true


static func _apply_behavior_bias(f, focus: String, salience: float) -> void:
	f._behavior_ws_bias = _bias_for(f, focus, salience)


# META #9 — the per-goal steering bias for one focus. Pure: returns the vector and
# writes nothing, so blend_behavior_bias() can sum it across co-ignited contents.
static func _bias_for(f, focus: String, salience: float) -> Vector3:
	var bias: Vector3 = Vector3.ZERO
	var mag: float = clampf(salience, 0.0, 1.0) * 0.35
	var cache: Dictionary = f._cycle_bias_cache if f.get("_cycle_bias_cache") is Dictionary else {}
	var glance_pt: Vector3 = cache.get("glance", f._cached_glance_point) if not cache.is_empty() \
			else f._cached_glance_point
	var feed_pt: Vector3 = cache.get("feed", Vector3.ZERO) if not cache.is_empty() else Vector3.ZERO
	var mate_pos: Vector3 = cache.get("mate_pos", Vector3.ZERO) if not cache.is_empty() else Vector3.ZERO
	match focus:
		"player":
			if glance_pt.length_squared() > 0.01:
				bias = (glance_pt - f.position).normalized() * mag
		"keeper_message":
			if glance_pt.length_squared() > 0.01:
				bias = (glance_pt - f.position).normalized() * mag * (0.5 + f.familiarity * 0.5)
		"being_watched":
			if glance_pt.length_squared() > 0.01:
				var toward: Vector3 = (glance_pt - f.position).normalized()
				if f._trait("boldness") > 0.52 and f.familiarity > 0.35:
					bias = toward * mag
				else:
					bias = -toward * mag * 0.65
		"food":
			if feed_pt.length_squared() > 0.01:
				bias = (feed_pt - f.position).normalized() * mag
			else:
				bias = Vector3(0.0, mag * 0.6, 0.0)
		"threat":
			bias = -f.heading * mag
		"night_quiet", "rest", "dream":
			bias = Vector3.ZERO
		"mate":
			if mate_pos.length_squared() > 0.01:
				bias = (mate_pos - f.position).normalized() * mag
			elif f.get("has_mate") == true and f.get("partner") != null and is_instance_valid(f.get("partner")):
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
static func blend_behavior_bias(f, contents: Array) -> void:
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


static func encode_from_workspace(f, ms) -> void:
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
