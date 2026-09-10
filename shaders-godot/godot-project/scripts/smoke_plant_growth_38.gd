extends SceneTree

const CreatorScript := preload("res://scripts/creature_creator.gd")

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
	# Production proof: the normal-game Designer Plant randomizer delegates to
	# the bounded sampler rather than recreating unconstrained trait rolls.
	var creator = CreatorScript.new()
	creator._randomize_plant(380038)
	var generated: Dictionary = creator._genome.duplicate(true)
	creator._randomize_plant(380038)
	if generated != creator._genome:
		return _fail("production designer caller is not deterministic when seeded")
	if not String(generated.get("parent_lineage", "")).begins_with("Procedural"):
		return _fail("production designer caller did not invoke anchored sampler")
	if generated.has("ramp_override") or not generated.has("_ramp_base"):
		return _fail("production designer caller did not adapt sampled ramp")
	creator.free()
	print("SMOKE_PLANT_GROWTH_38_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
