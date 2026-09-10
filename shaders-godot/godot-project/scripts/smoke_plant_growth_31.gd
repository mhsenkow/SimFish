extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(1, {"vascular_transport_rate": 0.2, "nutrient_demand": 0.05})
	p._root_reserve = 0.3
	p._shoot_reserve = 0.1
	var before: float = p._root_reserve + p._shoot_reserve
	p._tick_resource_transport(0.5)
	var after: float = p._root_reserve + p._shoot_reserve
	if not is_equal_approx(before, after):
		return _fail("transport did not conserve resources")
	if p._root_reserve < 0.0 or p._shoot_reserve > Plant.RESOURCE_RESERVOIR_CAP:
		return _fail("reservoir bounds violated")
	if float(PlantGenome.enrich({}).vascular_transport_rate) != 0.0:
		return _fail("legacy transport path not preserved")
	var g: Dictionary = PlantGenome.from_plant(p)
	if not is_equal_approx(float(g.vascular_transport_rate), 0.2):
		return _fail("transport trait did not round-trip")
	print("SMOKE_PLANT_GROWTH_31_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
