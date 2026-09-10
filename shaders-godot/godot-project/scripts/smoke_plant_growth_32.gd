extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(1, {
		"max_height": 8, "leaf_form": "column",
		"juvenile_leaf_form": "needle", "adult_leaf_form": "lance",
		"heteroblasty_node": 2, "emersed_leaf_form": "spade",
	})
	if p._heteroblasty_adult:
		return _fail("juvenile stage skipped")
	p._grow_one()
	p._grow_one()
	if not p._heteroblasty_adult or p.leaf_form != "column":
		return _fail("stable adult transition or base form failed")
	if p.emersed_leaf_form != "spade":
		return _fail("heteroblasty altered emergent form")
	var saved: Dictionary = p.to_save_dict()
	if String(saved.init_params.adult_leaf_form) != "lance":
		return _fail("heteroblasty did not save")
	var mutated: Dictionary = PlantGenome.mutate(saved.init_params, PlantGenome.REPRO_FRAGMENT)
	if int(mutated.heteroblasty_node) <= 0:
		return _fail("heteroblasty mutation lost transition")
	print("SMOKE_PLANT_GROWTH_32_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
