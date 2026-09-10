extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	seed(41041)
	var a := PlantGenome.enrich({
		"species_id": "crypt.test", "plant_name": "Copper",
		"generation": 2, "growth_rate": 0.12, "palatability": 0.2,
		"parent_keys": ["crypt:a"],
	})
	var b := PlantGenome.enrich({
		"species_id": "crypt.test", "plant_name": "Green",
		"generation": 4, "growth_rate": 0.28, "palatability": 0.8,
		"parent_keys": ["crypt:b"],
	})
	var child: Dictionary = PlantGenome.outcross(a, b, 5)
	_assert(failed, int(child.generation) == 5, "generation retained")
	_assert(failed, String(child.parent_lineage).contains("Copper")
		and String(child.parent_lineage).contains("Green"), "both lineages retained")
	_assert(failed, (child.parent_keys as Array).has("crypt:a")
		and (child.parent_keys as Array).has("crypt:b"), "both parent keys retained")
	_assert(failed, float(child.growth_rate) > 0.10
		and float(child.growth_rate) < 0.30, "offspring blends and mutates")
	var clone: Dictionary = PlantGenome.duplicate_mutate(a, 3)
	_assert(failed, int(clone.generation) == 3, "clonal fallback remains available")
	if failed.is_empty():
		print("[smoke_plant_reproduction_41] PASS")
		quit(0)
	else:
		for message in failed:
			push_error("[smoke_plant_reproduction_41] " + message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
