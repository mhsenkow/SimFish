class_name MindKernel
extends RefCounted

# PERFORMANCE_UNTHROTTLED #49/#50 — packed numeric kernels + GDScript twin + optional native.

const _MindBidSoAScript = preload("res://scripts/mind_bid_soa.gd")
const _MindCompetitionScript = preload("res://scripts/mind_competition.gd")
const EpisodicMemory = preload("res://scripts/episodic_memory.gd")

const CAPACITY: int = 3
const IGNITION_THRESHOLD: float = 0.42
const COALITION_BONUS: float = 0.12
const TOP_K: int = 6

static var _native_checked: bool = false
static var _native_ok: bool = false
static var _native: RefCounted = null


static func reset_for_test() -> void:
	_native_checked = false
	_native_ok = false
	_native = null


static func native_available() -> bool:
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("MindKernelNative"):
			_native = ClassDB.instantiate("MindKernelNative")
			_native_ok = _native != null
	return _native_ok


static func backend_name() -> String:
	return "native" if native_available() else "gdscript"


static func competition(bids: Array) -> Dictionary:
	if bids.is_empty():
		return {"contents": [], "ignited": false, "top_salience": 0.0}
	var soa = _MindBidSoAScript.new()
	soa.load_from_bids(bids)
	if native_available() and _native.has_method("competition"):
		var packed: Dictionary = _native.competition(
				soa.saliences, soa.coal_masks, soa.labels)
		return _unpack_competition(packed, soa)
	return _competition_gdscript(soa)


static func _unpack_competition(packed: Dictionary, soa) -> Dictionary:
	var winners: Array = []
	var idxs: Variant = packed.get("indices", [])
	if idxs is PackedInt32Array:
		for i in idxs:
			winners.append(soa.source_at(int(i)).duplicate(false))
	elif idxs is Array:
		for i in idxs:
			winners.append(soa.source_at(int(i)).duplicate(false))
	return {
		"contents": winners,
		"ignited": bool(packed.get("ignited", false)),
		"top_salience": float(packed.get("top_salience", 0.0)),
	}


static func _competition_gdscript(soa) -> Dictionary:
	var sorted: Array = []
	for i in soa.count:
		_MindCompetitionScript.insert_top_bid(sorted, soa.source_at(i))
	return _MindCompetitionScript.from_sorted(sorted)


static func dot_top_k(query: PackedFloat32Array, entries: Array, k: int = 3) -> Array:
	if native_available() and _native.has_method("dot_top_k"):
		return _native.dot_top_k(query, entries, k)
	return _dot_top_k_gdscript(query, entries, k)


static func _dot_top_k_gdscript(query: PackedFloat32Array, entries: Array, k: int) -> Array:
	var best: Array = []
	for e in entries:
		if not (e is Dictionary):
			continue
		var vec: Variant = e.get("vec", null)
		if vec is not PackedFloat32Array:
			continue
		var sim: float = EpisodicMemory.similarity(query, vec as PackedFloat32Array)
		sim *= float(e.get("weight", 0.5))
		var insert_at: int = best.size()
		for i in best.size():
			if sim > float(best[i].get("score", 0.0)):
				insert_at = i
				break
		if best.size() < k:
			best.insert(insert_at, {"entry": e, "score": sim})
		elif insert_at < k:
			best.insert(insert_at, {"entry": e, "score": sim})
			best.remove_at(k)
	var out: Array = []
	for hit in best:
		out.append(hit)
	return out


static func boot_self_test() -> bool:
	var bids: Array = [
		{"label": "food", "salience": 0.72, "coalition": ["food"], "coal_mask": 1},
		{"label": "threat", "salience": 0.68, "coalition": ["threat"], "coal_mask": 4},
		{"label": "novelty", "salience": 0.55, "coalition": ["novelty"], "coal_mask": 64},
	]
	var soa_gd = _MindBidSoAScript.new()
	soa_gd.load_from_bids(bids)
	var gd: Dictionary = _competition_gdscript(soa_gd)
	var routed: Dictionary = competition(bids)
	if bool(gd.get("ignited")) != bool(routed.get("ignited")):
		return false
	if absf(float(gd.get("top_salience", 0.0)) - float(routed.get("top_salience", 0.0))) > 0.0001:
		return false
	var gw: Array = gd.get("contents", [])
	var rw: Array = routed.get("contents", [])
	if gw.size() != rw.size():
		return false
	for i in gw.size():
		if str((gw[i] as Dictionary).get("label", "")) != str((rw[i] as Dictionary).get("label", "")):
			return false
	return load("res://scripts/global_workspace.gd").run_competition_smoke_parity()
