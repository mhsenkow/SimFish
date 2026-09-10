extends SceneTree


func _init() -> void:
	var failed: Array[String] = []
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(2.0, 2.0, 1.0)
	var p := Vector3.ZERO
	grid.add_family_allelochemical_at(p, "family:a", 0.5)
	grid.add_family_allelochemical_at(p, "family:b", 0.2)
	var competitor: float = grid.get_allelopathy_pressure_at(p, "family:c", 0.0)
	var kin: float = grid.get_allelopathy_pressure_at(p, "family:a", 0.0)
	_assert(failed, kin < competitor, "emitters and close kin resist own family")
	_assert(failed, grid.get_allelochemical_at(p) <= SubstrateGrid.ALLELO_MAX,
		"scalar compatibility remains bounded")
	for i in 10:
		grid.add_family_allelochemical_at(p, "family:%d" % i, 0.02)
	_assert(failed, grid.get_allelopathy_mix_at(p).size() <= 4,
		"family count capped per cell")
	var before_decay: float = grid.get_allelochemical_at(p)
	grid.tick_channels(5.0)
	_assert(failed, grid.get_allelochemical_at(p) < before_decay,
		"family mixture decays")

	var saved: Dictionary = grid.to_save_dict()
	var restored := SubstrateGrid.new()
	root.add_child(restored)
	restored.init(2.0, 2.0, 1.0)
	restored.apply_save_dict(saved)
	_assert(failed, restored.get_allelopathy_mix_at(p).size() > 0,
		"family mixture roundtrip")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("allelopathy_families")
	var migrated := SubstrateGrid.new()
	root.add_child(migrated)
	migrated.init(2.0, 2.0, 1.0)
	migrated.apply_save_dict(legacy)
	_assert(failed, migrated.get_allelopathy_mix_at(p).has("legacy:anonymous"),
		"scalar allelopathy migrates anonymously")

	var emitter: Dictionary = PlantGenome.enrich({
		"species_id": "stem.a",
		"allelopathy_strength": 0.4,
	})
	_assert(failed, String(emitter.allelopathy_family) == "family:stem.a",
		"legacy emitter derives stable family")
	_assert(failed, float(emitter.allelopathy_resistance) >= 0.85,
		"emitter derives heritable kin resistance")
	var child: Dictionary = PlantGenome.duplicate_mutate(emitter, 2)
	_assert(failed, String(child.allelopathy_family) == String(emitter.allelopathy_family),
		"family is inherited")
	_assert(failed, float(child.allelopathy_resistance) >= 0.0 \
		and float(child.allelopathy_resistance) <= 1.0, "resistance stays bounded")

	if failed.is_empty():
		print("[smoke_plant_family_allelopathy] PASS")
		quit(0)
	else:
		for msg in failed:
			push_error("[smoke_plant_family_allelopathy] " + msg)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
