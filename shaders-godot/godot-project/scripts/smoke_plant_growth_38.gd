extends SceneTree

func _initialize() -> void:
	var a: Dictionary = ProceduralPlantSpecies.sample(380038)
	var b: Dictionary = ProceduralPlantSpecies.sample(380038)
	if a != b:
		return _fail("fixed-seed sampler is not deterministic")
	if not ProceduralPlantSpecies._valid(a):
		return _fail("sampler returned invalid genome")
	if not String(a.parent_lineage).begins_with("Procedural"):
		return _fail("real species anchor provenance missing")
	for i in 32:
		var g: Dictionary = ProceduralPlantSpecies.sample(380100 + i)
		if not ProceduralPlantSpecies._valid(g):
			return _fail("constraint rejection failed")
	print("SMOKE_PLANT_GROWTH_38_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
