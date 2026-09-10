extends SceneTree

const BranchScript := preload("res://scripts/branch_plant.gd")

func _initialize() -> void:
	await process_frame
	var p: BranchPlant = BranchScript.new()
	root.add_child(p)
	p.init(0, {"max_height": 12, "crown_fill": 1.0, "asymmetry_seed": 33})
	if p._attraction_points.is_empty() or p._attraction_points.size() > BranchPlant.MAX_ATTRACTION_POINTS:
		return _fail("attraction point bounds failed")
	var first: Vector3 = p._attraction_points[0]
	var q: BranchPlant = BranchScript.new()
	root.add_child(q)
	q.init(0, {"max_height": 12, "crown_fill": 1.0, "asymmetry_seed": 33})
	if not first.is_equal_approx(q._attraction_points[0]):
		return _fail("crown points are not deterministic")
	if not PlantGenome.from_plant(p).has("crown_fill"):
		return _fail("crown trait did not round-trip")
	print("SMOKE_PLANT_GROWTH_33_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
