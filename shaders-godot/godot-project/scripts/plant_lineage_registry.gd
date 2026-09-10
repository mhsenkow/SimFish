# Naturalism #441 — lineage bookkeeping for plant populations.
# Tracks named strains, generation depth, and drift from species baseline
# so mutation is visible as family history, not just number noise.
extends RefCounted
class_name PlantLineageRegistry

var _by_id: Dictionary = {}  # lineage_id -> Dictionary
var _plant_lineage: Dictionary = {}  # plant instance_id -> lineage_id
var _established_plants: Dictionary = {}  # live instance_id -> true
const EVENT_HISTORY_CAP: int = 256
var _events: Array = []
var _event_seq: int = 0


static func lineage_id_for(g: Dictionary) -> String:
	var named: String = String(g.get("plant_name", "")).strip_edges()
	if named != "":
		return "name:%s" % named
	var parent: String = String(g.get("parent_lineage", "Founders")).strip_edges()
	var sid: String = String(g.get("species_id", "")).strip_edges()
	if sid != "":
		return "sp:%s|%s" % [sid, parent]
	return "anon:%s|g%d" % [parent, int(g.get("generation", 0))]


func register_genome(g: Dictionary, plant_instance_id: int = 0) -> String:
	var lid: String = lineage_id_for(g)
	if plant_instance_id != 0 and _plant_lineage.has(plant_instance_id):
		var registered_lid: String = String(_plant_lineage[plant_instance_id])
		if registered_lid == lid:
			return lid
		unregister_plant(plant_instance_id)
	var gen: int = int(g.get("generation", 0))
	var drift: float = PlantGenome.drift_distance(g)
	if not _by_id.has(lid):
		_by_id[lid] = {
			"id": lid,
			"display_name": String(g.get("plant_name", "")) if String(g.get("plant_name", "")) != "" \
				else String(g.get("parent_lineage", "Founders")),
			"species_id": String(g.get("species_id", "")),
			"founder_generation": gen,
			"max_generation": gen,
			"count": 0,
			"drift_max": drift,
			"drift_sum": 0.0,
			"named": String(g.get("plant_name", "")) != "",
			"germinations": 0,
			"establishments": 0,
			"extinctions": 0,
		}
	var e: Dictionary = _by_id[lid]
	e.count = int(e.count) + 1
	e.max_generation = maxi(int(e.max_generation), gen)
	e.drift_max = maxf(float(e.drift_max), drift)
	e.drift_sum = float(e.drift_sum) + drift
	if plant_instance_id != 0:
		_plant_lineage[plant_instance_id] = lid
	return lid


func unregister_plant(plant_instance_id: int) -> void:
	if not _plant_lineage.has(plant_instance_id):
		return
	var lid: String = String(_plant_lineage[plant_instance_id])
	_plant_lineage.erase(plant_instance_id)
	_established_plants.erase(plant_instance_id)
	if not _by_id.has(lid):
		return
	var e: Dictionary = _by_id[lid]
	e.count = maxi(0, int(e.count) - 1)
	if int(e.count) == 0:
		e.extinctions = int(e.get("extinctions", 0)) + 1
		_append_event("extinction", lid, "")


func record_germination(g: Dictionary, cell_key: String = "") -> String:
	var lid: String = lineage_id_for(g)
	_ensure_ledger_entry(lid, g)
	var e: Dictionary = _by_id[lid]
	e.germinations = int(e.get("germinations", 0)) + 1
	_append_event("germination", lid, cell_key)
	return lid


func record_establishment(plant_instance_id: int, cell_key: String = "") -> void:
	if not _plant_lineage.has(plant_instance_id):
		return
	if _established_plants.has(plant_instance_id):
		return
	var lid: String = String(_plant_lineage[plant_instance_id])
	var e: Dictionary = _by_id.get(lid, {})
	if e.is_empty():
		return
	_established_plants[plant_instance_id] = true
	e.establishments = int(e.get("establishments", 0)) + 1
	_append_event("establishment", lid, cell_key)


func event_history() -> Array:
	return _events.duplicate(true)


func _ensure_ledger_entry(lid: String, g: Dictionary) -> void:
	if _by_id.has(lid):
		return
	_by_id[lid] = {
		"id": lid,
		"display_name": String(g.get("plant_name",
			g.get("parent_lineage", "Founders"))),
		"species_id": String(g.get("species_id", "")),
		"founder_generation": int(g.get("generation", 0)),
		"max_generation": int(g.get("generation", 0)),
		"count": 0,
		"drift_max": 0.0,
		"drift_sum": 0.0,
		"named": String(g.get("plant_name", "")) != "",
		"germinations": 0,
		"establishments": 0,
		"extinctions": 0,
	}


func _append_event(kind: String, lid: String, cell_key: String) -> void:
	_event_seq += 1
	_events.append({
		"seq": _event_seq,
		"kind": kind,
		"lineage_id": lid,
		"cell": cell_key,
	})
	while _events.size() > EVENT_HISTORY_CAP:
		_events.pop_front()


func name_lineage(lid: String, strain_name: String) -> void:
	if not _by_id.has(lid):
		return
	var e: Dictionary = _by_id[lid]
	e.display_name = strain_name
	e.named = true


func get_entry(lid: String) -> Dictionary:
	return _by_id.get(lid, {})


func mean_drift(lid: String) -> float:
	if not _by_id.has(lid):
		return 0.0
	var e: Dictionary = _by_id[lid]
	var c: int = maxi(1, int(e.count))
	return float(e.drift_sum) / float(c)


func snapshot() -> Array:
	var out: Array = []
	for k in _by_id.keys():
		out.append((_by_id[k] as Dictionary).duplicate(true))
	return out


func to_save_dict() -> Dictionary:
	return {
		"by_id": _by_id.duplicate(true),
		"events": _events.duplicate(true),
		"event_seq": _event_seq,
		"schema_version": 2,
	}


func from_save_dict(d: Dictionary) -> void:
	_by_id.clear()
	# Keep live instance mappings when ambient state is restored after plants
	# have already registered during load; saved instance IDs are not stable.
	_events.clear()
	_event_seq = int(d.get("event_seq", 0))
	var src: Variant = d.get("by_id", {})
	if src is Dictionary:
		_by_id = (src as Dictionary).duplicate(true)
	var events_v: Variant = d.get("events", [])
	if events_v is Array:
		_events = (events_v as Array).slice(
			maxi(0, (events_v as Array).size() - EVENT_HISTORY_CAP))
