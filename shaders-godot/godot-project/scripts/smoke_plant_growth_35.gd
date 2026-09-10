extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(8, {
		"max_height": 16, "reiteration_loss_threshold": 0.3,
		"reiteration_capacity": 1, "asymmetry_seed": 35,
	})
	p.nibble(4)
	if p._reiteration_pending_node < 0 or p._reiterations_used != 1:
		return _fail("substantial loss did not schedule reiteration")
	p.nibble(1)
	if p._reiterations_used != 1:
		return _fail("damage episode reiterated twice")
	p._grow_one()
	if p._reiteration_pending_node >= 0:
		return _fail("reiteration did not grow from surviving node")
	if int(PlantGenome.enrich({}).reiteration_capacity) != 0:
		return _fail("legacy genomes enabled reiteration")
	print("SMOKE_PLANT_GROWTH_35_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
