class_name SaveRepair
extends RefCounted

# SYSTEMIC #6 — validate + repair save dicts before load_state (never crash on corrupt minds).

const MAX_FISH: int = 512
const MAX_PLANTS: int = 1024


static func sanitize(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		push_warning("[SaveRepair] root is not a dict — starting fresh tank")
		return {}
	var out: Dictionary = (d as Dictionary).duplicate(true)
	out["version"] = clampi(int(out.get("version", 0)), 0, 999)
	out["sim"] = _repair_sim(out.get("sim", {}))
	out["fish"] = _repair_entity_array(out.get("fish", []), MAX_FISH)
	out["plants"] = _repair_entity_array(out.get("plants", []), MAX_PLANTS)
	out["fish_eggs"] = _repair_entity_array(out.get("fish_eggs", []), 256)
	out["shrimp"] = _repair_entity_array(out.get("shrimp", []), 256)
	out["snails"] = _repair_entity_array(out.get("snails", []), 128)
	if out.has("discovered_species") and not (out["discovered_species"] is Array):
		out.erase("discovered_species")
	if out.has("aquascape") and not (out["aquascape"] is Array):
		out.erase("aquascape")
	if out.has("terrain") and not (out["terrain"] is Dictionary):
		out.erase("terrain")
	return out


static func _repair_sim(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var sim: Dictionary = (raw as Dictionary).duplicate(true)
	if sim.has("day_phase"):
		sim["day_phase"] = clampf(SaveHelpers._num(sim["day_phase"], 0.0), 0.0, 1.0)
	if sim.has("dissolved_o2"):
		sim["dissolved_o2"] = clampf(SaveHelpers._num(sim["dissolved_o2"], 0.0), 0.0, 1.0)
	if sim.has("stability"):
		sim["stability"] = clampf(SaveHelpers._num(sim["stability"], 0.0), 0.0, 1.0)
	if sim.has("tank_age_s"):
		sim["tank_age_s"] = maxf(0.0, SaveHelpers._num(sim["tank_age_s"], 0.0))
	if sim.has("elapsed_runtime_s"):
		sim["elapsed_runtime_s"] = maxf(0.0, SaveHelpers._num(sim["elapsed_runtime_s"], 0.0))
	if sim.has("time_scale"):
		sim["time_scale"] = clampf(SaveHelpers._num(sim["time_scale"], 1.0), 0.0, 64.0)
	if sim.has("tank_mind") and not (sim["tank_mind"] is Dictionary):
		sim.erase("tank_mind")
	if sim.has("guardian_arc") and not (sim["guardian_arc"] is Dictionary):
		sim.erase("guardian_arc")
	if sim.has("voice_caches") and not (sim["voice_caches"] is Dictionary):
		sim.erase("voice_caches")
	return sim


static func _repair_entity_array(raw: Variant, cap: int) -> Array:
	if not (raw is Array):
		return []
	var out: Array = []
	for entry in raw:
		if entry is Dictionary:
			out.append((entry as Dictionary).duplicate(true))
		if out.size() >= cap:
			push_warning("[SaveRepair] truncated entity array to %d entries" % cap)
			break
	return out
