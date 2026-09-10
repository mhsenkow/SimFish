extends SceneTree

# PLANT_SYSTEMS_50 #20 — calm mature plants coarsen work without losing elapsed
# time, and explicit biological/environmental dirtiness wakes them immediately.

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var substrate := SubstrateGrid.new()
	substrate.init(4.0, 2.0, 1.0)
	var host := Node3D.new()
	root.add_child(host)
	host.add_child(substrate)
	var plant: Plant = PlantScript.new()
	host.add_child(plant)
	plant.init(1, {"leaf_form": "column", "max_height": 1,
		"uses_flowering": false})
	plant.life_phase = Plant.LifePhase.VEGETATIVE
	plant.health = 1.0
	plant._health_smooth = 1.0

	var settle_steps: int = 0
	while not plant._static_sleeping and settle_steps < 20:
		plant.tick_sleep_aware(0.5, substrate)
		settle_steps += 1
	_assert(failed, plant._static_sleeping, "stable mature plant enters sleep")
	var age_before: float = plant.plant_age_s
	for i in 3:
		plant.tick_sleep_aware(0.2, substrate)
	_assert(failed, is_equal_approx(plant.plant_age_s, age_before),
		"sub-coarse sleeping ticks skip full state work")
	_assert(failed, is_equal_approx(plant._static_sleep_accum_s, 0.6),
		"sleeping dt accumulates exactly")

	plant.current_height = 0
	plant.wake_plant("growth")
	plant.tick_sleep_aware(0.1, substrate)
	_assert(failed, not plant._static_sleeping, "growth dirtiness wakes plant")
	_assert(failed, is_equal_approx(plant.plant_age_s, age_before + 0.7),
		"wake integrates all accumulated dt exactly once")

	plant.free()
	host.free()
	await process_frame
	if failed.is_empty():
		print("[smoke] plant_static_sleep OK accumulated=0.600 wake_dt=0.700")
		quit(0)
	else:
		for message in failed:
			push_error("[smoke] FAIL: %s" % message)
		quit(1)


func _assert(failed: Array[String], condition: bool, label: String) -> void:
	if not condition:
		failed.append(label)
