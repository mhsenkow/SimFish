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
	TestSupport.check(failed, is_equal_approx(float(untouched.palatability), 0.65),
		"no grazing leaves inheritance unchanged")
	var selected: Dictionary = PlantGenome.apply_grazing_selection(base, 1.0)
	TestSupport.check(failed, is_equal_approx(float(selected.palatability), 0.53),
		"palatability shift is bounded")
	TestSupport.check(failed, is_equal_approx(float(selected.leaf_thickness), 0.6),
		"defense shift is bounded")
	TestSupport.check(failed, is_equal_approx(float(selected.growth_rate), 0.16),
		"defense has explicit growth cost")
	TestSupport.check(failed, is_equal_approx(float(selected.nutrient_demand), 0.105),
		"defense has explicit resource cost")
	var clamped: Dictionary = PlantGenome.apply_grazing_selection(base, 20.0)
	TestSupport.check(failed, is_equal_approx(float(clamped.palatability), 0.53),
		"pressure cannot exceed one-generation bound")
	quit(TestSupport.report("smoke_plant_reproduction_49", failed))
