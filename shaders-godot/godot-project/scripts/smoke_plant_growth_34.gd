extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var legacy: Plant = PlantScript.new()
	root.add_child(legacy)
	legacy.init(2, {"max_height": 10})
	if not is_equal_approx(legacy._species_growth_curve_multiplier(), 1.0):
		return _fail("legacy growth curve changed")
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(1, {
		"max_height": 10, "growth_curve_establishment": 0.3,
		"growth_curve_acceleration": 10.0, "growth_curve_plateau": 0.8,
	})
	var early: float = p._species_growth_curve_multiplier()
	p.current_height = 9
	var late: float = p._species_growth_curve_multiplier()
	if early >= late or late > 0.81:
		return _fail("bounded sigmoid curve failed")
	var g: Dictionary = PlantGenome.from_plant(p)
	if not is_equal_approx(float(g.growth_curve_acceleration), 10.0):
		return _fail("curve genome did not round-trip")
	print("SMOKE_PLANT_GROWTH_34_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
