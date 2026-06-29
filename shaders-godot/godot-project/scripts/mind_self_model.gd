extends RefCounted

# CONSCIOUSNESS_ENGINEERING §G — self-model & higher-order representation.

const FishMind = preload("res://scripts/fish_mind.gd")
const FishProtoself = preload("res://scripts/fish_protoself.gd")
const FishCoreAffect = preload("res://scripts/fish_core_affect.gd")
const FishBinding = preload("res://scripts/fish_binding.gd")


static func build(f: Fish, workspace: Array) -> Dictionary:
	var attending: String = ""
	if not workspace.is_empty():
		attending = str((workspace[0] as Dictionary).get("label", ""))
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
	return out


static func tick_higher_order(f: Fish, self_model: Dictionary, _dt: float) -> PackedStringArray:
	var meta: PackedStringArray = PackedStringArray()
	if f.stress > 0.65 and float(self_model.get("confidence", 1.0)) < 0.4:
		meta.append("I keep failing here")
	if f._asleep and f._dreaming and float(self_model.get("confidence", 0.0)) > 0.42:
		if MindRng.for_fish(f).randf() < 0.003:
			meta.append("this might be sleep")
	if f.spooked > 0.5 and f.vigilance > 0.6:
		meta.append("I've been scared a long time")
	if f.mood > 0.35 and f.arousal < 0.35:
		meta.append("I'm content")
	# Self-prediction (#65)
	if f.hunger > 0.55 and f.hunger < 0.75:
		meta.append("I'll be hungry soon")
	if f.surprise > 0.4:
		meta.append("something surprised me")
	return meta


static func update_self_summary(f: Fish, reflection_line: String) -> void:
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


static func tick_trait_change_notice(f: Fish, _dt: float) -> void:
	if f.get("_last_boldness") == null:
		f._last_boldness = f._trait("boldness")
		return
	var old_b: float = float(f._last_boldness)
	var new_b: float = f._trait("boldness")
	if absf(new_b - old_b) > 0.08:
		FishMind.record_salient(f, "self", "I've grown %s" % ("braver" if new_b > old_b else "warier"),
				0.45, f.position)
	f._last_boldness = new_b


static func tag_agency(f: Fish, kind: String, self_caused: bool) -> void:
	if f.memory.is_empty():
		return
	var last: Dictionary = f.memory[-1]
	last["agency"] = "self" if self_caused else "world"
	last["kind"] = kind
