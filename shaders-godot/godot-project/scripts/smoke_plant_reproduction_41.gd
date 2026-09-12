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
	TestSupport.check(failed, int(child.generation) == 5, "generation retained")
	TestSupport.check(failed, String(child.parent_lineage).contains("Copper")
		and String(child.parent_lineage).contains("Green"), "both lineages retained")
	TestSupport.check(failed, (child.parent_keys as Array).has("crypt:a")
		and (child.parent_keys as Array).has("crypt:b"), "both parent keys retained")
	TestSupport.check(failed, float(child.growth_rate) > 0.10
		and float(child.growth_rate) < 0.30, "offspring blends and mutates")
	var clone: Dictionary = PlantGenome.duplicate_mutate(a, 3)
	TestSupport.check(failed, int(clone.generation) == 3, "clonal fallback remains available")
	quit(TestSupport.report("smoke_plant_reproduction_41", failed))
