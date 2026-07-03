extends RefCounted

# CONSCIOUSNESS_ENGINEERING §G — self-model & higher-order representation.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")
const MindSoul = preload("res://scripts/mind_soul.gd")


static func build(f, workspace: Array) -> Dictionary:
	var attending: String = ""
	if not workspace.is_empty():
		attending = str((workspace[0] as Dictionary).get("label", ""))
	# PERFORMANCE_UNTHROTTLED #21 — reuse when source fields unchanged.
	var cache_key: String = "%s|%s|%.2f|%.2f|%.2f|%.2f" % [
		attending, f.current_intention, f.stress, f.mood, f.hunger, f.surprise,
	]
	var cached: Variant = f.get("_self_model_cache")
	var cached_key: Variant = f.get("_self_model_key")
	if cached is Dictionary \
			and str(cached_key if cached_key != null else "") == cache_key:
		return (cached as Dictionary).duplicate(true)
	var out: Dictionary = {
		"feel": FishMind.emotional_state(f),
		"attending_to": attending,
		"intention": f.current_intention,
		"wants": FishMind.dominant_wants(f),
		"confidence": clampf(1.0 - f.stress * 0.5 - f.vigilance * 0.3, 0.0, 1.0),
		"agency": "self" if f.speed > 0.05 else "drifting",
		"self_summary": str(f.get("_self_summary") if f.get("_self_summary") != null else ""),
	}
	if FishBinding.layer_enabled():
		var pb: Dictionary = FishProtoself.ensure(f)
		out["body"] = {
			"gills": snappedf(float(pb.get("gill_rhythm", 0.0)), 0.01),
			"gut": snappedf(float(pb.get("gut_fullness", 0.0)), 0.01),
			"fins": snappedf(float(pb.get("fin_tension", 0.0)), 0.01),
			"comfort": snappedf(float(pb.get("comfort", 0.0)), 0.01),
		}
		out["core_valence"] = snappedf(FishCoreAffect.valence(f), 0.01)
		out["felt_texture"] = FishCoreAffect.texture(f)
		out["binding"] = snappedf(FishBinding.integration_score(f), 0.01)
		if MindSoul.enabled():
			var soul: Dictionary = MindSoul.ensure(f)
			out["self_pred_error"] = snappedf(float(soul.get("self_pred_error", 0.0)), 0.01)
			out["confidence_volatility"] = snappedf(float(soul.get("confidence_volatility", 0.0)), 0.01)
			out["second_order_doubt"] = float(soul.get("confidence_volatility", 0.0)) > 0.22 \
					and float(out["confidence"]) < 0.55
	f.set("_self_model_key", cache_key)
	f.set("_self_model_cache", out.duplicate(true))
	return out


const META_RING_SIZE: int = 8


static func _meta_ring_ensure(f) -> Array:
	if f.get("_meta_ring") == null or not (f._meta_ring is Array):
		f._meta_ring = []
		f._meta_ring_head = 0
	return f._meta_ring as Array


static func meta_push(f, line: String) -> void:
	if line.strip_edges() == "":
		return
	var ring: Array = _meta_ring_ensure(f)
	var head: int = int(f.get("_meta_ring_head") if f.get("_meta_ring_head") != null else 0)
	if ring.size() < META_RING_SIZE:
		ring.append(line)
	else:
		ring[head % META_RING_SIZE] = line
		f._meta_ring_head = head + 1


static func meta_to_array(f) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if f.get("_meta_ring") == null or not (f._meta_ring is Array):
		return out
	for s in f._meta_ring as Array:
		var t: String = str(s)
		if t != "":
			out.append(t)
	return out


static func tick_higher_order(f, self_model: Dictionary, _dt: float) -> PackedStringArray:
	var ring: Array = _meta_ring_ensure(f)
	ring.clear()
	f._meta_ring_head = 0
	if f.stress > 0.65 and float(self_model.get("confidence", 1.0)) < 0.4:
		meta_push(f, "I keep failing here")
	if f._asleep and f._dreaming and float(self_model.get("confidence", 0.0)) > 0.42:
		if MindRng.for_fish(f).randf() < 0.003:
			meta_push(f, "this might be sleep")
	if f.spooked > 0.5 and f.vigilance > 0.6:
		meta_push(f, "I've been scared a long time")
	if f.mood > 0.35 and f.arousal < 0.35:
		meta_push(f, "I'm content")
	if f.hunger > 0.55 and f.hunger < 0.75:
		meta_push(f, "I'll be hungry soon")
	if f.surprise > 0.4:
		meta_push(f, "something surprised me")
	return meta_to_array(f)


static func update_self_summary(f: Fish, reflection_line: String, sim: Node = null) -> void:
	if reflection_line.strip_edges() == "":
		return
	var prev: String = str(f.get("_self_summary") if f.get("_self_summary") != null else "")
	var nm: String = f.fish_name if f.fish_name != "" else "I"
	var frag: String = reflection_line.strip_edges().trim_suffix(".")
	if frag == "":
		return
	if prev.contains(frag):
		return
	if prev == "":
		f._self_summary = "%s — %s" % [nm, reflection_line.strip_edges().trim_suffix(".")]
	else:
		f._self_summary = prev.substr(0, mini(prev.length(), 120)) + " · " + reflection_line.strip_edges().trim_suffix(".")
	try_rare_summary_voice(f, sim, frag)


# SENTIENCE_THE_SPARK #13 — one-shot narrator line at a real self-model milestone.
static func try_rare_summary_voice(f: Fish, sim: Node, fragment: String) -> void:
	if f == null or fragment.strip_edges() == "":
		return
	if f.fish_name == "" and not f.is_guardian and f.familiarity < 0.45:
		return
	var cd: float = f._self_summary_voice_cd
	if cd > 0.0:
		return
	if MindRng.for_fish(f).randf() > 0.38:
		return
	f._self_summary_voice_cd = 90.0
	var nm: String = f.fish_name if f.fish_name != "" else "I"
	var line: String = "%s — %s." % [nm, fragment.strip_edges()]
	f._current_thought = line
	f._thought_stream = line
	f._thought_stream_age = 0.0
	FishMind.record_salient(f, "self", fragment, 0.42, f.position)
	if sim != null and sim.has_method("append_fish_journal_entry"):
		sim.append_fish_journal_entry(f, line, PackedStringArray(["self_summary", "milestone"]))


static func tick_self_summary_voice_cd(f: Fish, dt: float) -> void:
	f._self_summary_voice_cd = maxf(0.0, f._self_summary_voice_cd - dt)


static func tick_trait_change_notice(f: Fish, sim: Node, _dt: float) -> void:
	if f._last_boldness < 0.0:
		f._last_boldness = f._trait("boldness")
		return
	var old_b: float = f._last_boldness
	var new_b: float = f._trait("boldness")
	if absf(new_b - old_b) > 0.08:
		var note: String = "braver now" if new_b > old_b else "warier now"
		update_self_summary(f, note, sim)
		FishMind.record_salient(f, "self", "I've grown %s" % ("braver" if new_b > old_b else "warier"),
				0.45, f.position)
	f._last_boldness = new_b


static func tag_agency(f: Fish, kind: String, self_caused: bool) -> void:
	if f.memory.is_empty():
		return
	var last: Dictionary = f.memory[-1]
	last["agency"] = "self" if self_caused else "world"
	last["kind"] = kind
