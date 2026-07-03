class_name MindPromptSkeleton
extends RefCounted

# PERFORMANCE_UNTHROTTLED #56 — prompt skeleton rebuilt only on bio/roster change.

static var _cache: Dictionary = {}  # fish_id -> {sig, skeleton}


static func reset_for_test() -> void:
	_cache.clear()


static func _signature(f: Fish, sim: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(f.species))
	parts.append(str(f.fish_name))
	parts.append(str(f.personality_tag if f.get("personality_tag") != null else ""))
	parts.append(str(int(f.maturity if f.get("maturity") != null else 0)))
	if sim != null and sim.get("fish") != null:
		parts.append(str(sim.fish.size()))
	return "|".join(parts)


static func skeleton_for(f: Fish, sim: Node) -> Dictionary:
	if f == null:
		return {}
	var fid: String = str(f.id)
	var sig: String = _signature(f, sim)
	if fid != "" and _cache.has(fid):
		var row: Dictionary = _cache[fid] as Dictionary
		if String(row.get("sig", "")) == sig:
			return row.get("skeleton", {}) as Dictionary
	var sk: Dictionary = {
		"species": str(f.species),
		"name": str(f.fish_name if f.fish_name != "" else f.species),
		"personality": str(f.personality_tag if f.get("personality_tag") != null else ""),
		"roster_n": sim.fish.size() if sim != null and sim.get("fish") != null else 0,
	}
	if fid != "":
		_cache[fid] = {"sig": sig, "skeleton": sk}
	return sk


static func invalidate(f: Fish) -> void:
	if f == null:
		return
	var fid: String = str(f.id)
	if fid != "":
		_cache.erase(fid)
