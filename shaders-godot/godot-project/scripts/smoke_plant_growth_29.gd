extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var host := Node3D.new()
	root.add_child(host)
	var legacy: Plant = PlantScript.new()
	host.add_child(legacy)
	legacy.init(1, {"max_height": 8, "asymmetry_seed": 1})
	var old_y: float = legacy.voxels[0].local_pos.y
	legacy._light_avg = 0.05
	legacy._grow_one()
	if not is_equal_approx(legacy._internode_extension_y, 0.0):
		return _fail("legacy genome changed spacing")
	if not is_equal_approx(legacy.voxels[0].local_pos.y, old_y):
		return _fail("existing tissue moved")
	var p: Plant = PlantScript.new()
	host.add_child(p)
	p.init(1, {"max_height": 8, "asymmetry_seed": 2, "etiolation_sensitivity": 1.0})
	var fixed_y: float = p.voxels[0].local_pos.y
	p._light_avg = 0.05
	p._grow_one()
	if p._internode_extension_y <= 0.0 or not is_equal_approx(p.voxels[0].local_pos.y, fixed_y):
		return _fail("future-only etiolation failed")
	var saved: Dictionary = p.to_save_dict()
	if not saved.init_params.has("etiolation_sensitivity"):
		return _fail("trait not saved")
	print("SMOKE_PLANT_GROWTH_29_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
