extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var grid := SubstrateGrid.new()
	grid.init(4.0, 4.0, 1.0)
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(0, {"root_foraging": 1.0})
	p._world_pos = Vector3.ZERO
	var fallback: float = p._nutrient_seeking_root_angle(grid)
	grid.add_at(Vector3(grid.cell_size, 0.0, 0.0), 0.5)
	var seeking: float = p._nutrient_seeking_root_angle(grid)
	if absf(angle_difference(seeking, 0.0)) >= absf(angle_difference(fallback, 0.0)):
		return _fail("root did not steer toward richer east cell")
	p.root_foraging = 0.0
	if not is_equal_approx(p._nutrient_seeking_root_angle(grid), fallback):
		return _fail("golden-angle fallback changed")
	if not PlantGenome.from_plant(p).has("root_foraging"):
		return _fail("root trait did not round-trip")
	print("SMOKE_PLANT_GROWTH_36_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
