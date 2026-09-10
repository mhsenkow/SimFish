extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var base := PlantGenome.enrich({
		"palatability": 0.65,
		"leaf_thickness": 0.5,
		"growth_rate": 0.2,
		"nutrient_demand": 0.08,
	})
	var untouched: Dictionary = PlantGenome.apply_grazing_selection(base, 0.0)
	_assert(failed, is_equal_approx(float(untouched.palatability), 0.65),
		"no grazing leaves inheritance unchanged")
	var selected: Dictionary = PlantGenome.apply_grazing_selection(base, 1.0)
	_assert(failed, is_equal_approx(float(selected.palatability), 0.53),
		"palatability shift is bounded")
	_assert(failed, is_equal_approx(float(selected.leaf_thickness), 0.6),
		"defense shift is bounded")
	_assert(failed, is_equal_approx(float(selected.growth_rate), 0.16),
		"defense has explicit growth cost")
	_assert(failed, is_equal_approx(float(selected.nutrient_demand), 0.105),
		"defense has explicit resource cost")
	var clamped: Dictionary = PlantGenome.apply_grazing_selection(base, 20.0)
	_assert(failed, is_equal_approx(float(clamped.palatability), 0.53),
		"pressure cannot exceed one-generation bound")
	if failed.is_empty():
		print("[smoke_plant_reproduction_49] PASS")
		quit(0)
	else:
		for message in failed:
			push_error("[smoke_plant_reproduction_49] " + message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
