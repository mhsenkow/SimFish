extends SceneTree

const BranchScript := preload("res://scripts/branch_plant.gd")

func _initialize() -> void:
	await process_frame
	var legacy: BranchPlant = BranchScript.new()
	root.add_child(legacy)
	legacy.init(0, {"max_height": 8, "ls_depth": 1})
	if legacy.ls_axiom != "":
		return _fail("legacy fallback disabled")
	var p: BranchPlant = BranchScript.new()
	root.add_child(p)
	p.init(0, {
		"max_height": 20, "ls_axiom": "F", "ls_rule_f": "F[+F]-Fjunk",
		"ls_depth": 4, "asymmetry_seed": 27,
	})
	if p._ls_program.length() > BranchPlant.LS_MAX_SYMBOLS or p._ls_program.contains("j"):
		return _fail("symbol budget/sanitizer failed")
	for _i in 200:
		p._grow_one()
	if p._ls_voxels > BranchPlant.LS_MAX_VOXELS or p._ls_stack.size() > BranchPlant.LS_MAX_STACK:
		return _fail("interpreter bounds failed")
	var saved: Dictionary = p.to_save_dict()
	if String(saved.ls_axiom) != "F":
		return _fail("grammar did not save")
	print("SMOKE_PLANT_GROWTH_27_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
