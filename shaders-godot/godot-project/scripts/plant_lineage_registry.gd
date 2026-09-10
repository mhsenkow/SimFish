# Naturalism #441 — lineage bookkeeping for plant populations.
# Tracks named strains, generation depth, and drift from species baseline
# so mutation is visible as family history, not just number noise.
extends RefCounted
class_name PlantLineageRegistry

var _by_id: Dictionary = {}  # lineage_id -> Dictionary
var _plant_lineage: Dictionary = {}  # plant instance_id -> lineage_id


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
	if not _by_id.has(lid):
		return
	var e: Dictionary = _by_id[lid]
	e.count = maxi(0, int(e.count) - 1)


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
	return {"by_id": _by_id.duplicate(true)}


func from_save_dict(d: Dictionary) -> void:
	_by_id.clear()
	_plant_lineage.clear()
	var src: Variant = d.get("by_id", {})
	if src is Dictionary:
		_by_id = (src as Dictionary).duplicate(true)
