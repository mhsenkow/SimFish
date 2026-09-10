extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(1, {"max_height": 6})
	p._growth_diag = {"limiting_factor": "light"}
	p._grow_one()
	if p.voxels[-1].growth_limit_code != 1:
		return _fail("stem handle missing compact limit code")
	var history: Array[Dictionary] = p.get_stem_growth_history()
	if history.size() != p.voxels.size() or String(history[-1].factor) != "light":
		return _fail("vertical history API failed")
	var saved: Dictionary = p.to_save_dict()
	if not saved.has("_stem_limit_history") \
			or (saved._stem_limit_history as Array).size() != p.voxels.size():
		return _fail("compact history did not save")
	for handle in p.voxels:
		if handle.get("growth_limit_code") == null:
			return _fail("history stored outside stem handle")
	print("SMOKE_PLANT_GROWTH_30_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
