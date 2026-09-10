extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(6, {"max_height": 12, "auxin_dominance": 0.9, "asymmetry_seed": 28})
	if p.auxin_at_node(5) <= p.auxin_at_node(1):
		return _fail("auxin does not decay from apex")
	var rebuilds: int = p._auxin_rebuild_count
	p._compute_growth_rate(1.0, 1.0, null)
	if p._auxin_rebuild_count != rebuilds:
		return _fail("auxin rebuilt without architecture change")
	p.nibble(1)
	if p._pending_trim_nodes.is_empty() or p.auxin_at_node(1) != 0.0:
		return _fail("apex loss did not release lateral buds")
	var e: Dictionary = PlantGenome.enrich({})
	if float(e.auxin_dominance) != 0.0:
		return _fail("legacy default changed")
	print("SMOKE_PLANT_GROWTH_28_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
