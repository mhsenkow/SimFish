extends SceneTree

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	root.add_child(plant)
	await process_frame
	plant.current_height = 20
	plant.water_surface_y = 6.5
	plant.global_position = Vector3(2.0, 0.0, -1.0)
	var crown := plant.canopy_shadow_sphere()
	TestSupport.check(failed, crown.w >= 0.22 and crown.w <= 1.25,
		"plant crown radius is bounded")
	TestSupport.check(failed, crown.y > plant.global_position.y and crown.y <= plant.water_surface_y,
		"crown center tracks living canopy")
	var source := FileAccess.get_file_as_string("res://scripts/world.gd")
	TestSupport.check(failed, source.contains("_PLANT_BLOB_SHADOW_SLOTS: int = 8"),
		"plant shadow budget is capped")
	TestSupport.check(failed, source.contains("proximity / biomass_gain"),
		"selection prioritizes nearby high-biomass crowns")
	plant.queue_free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_07_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)
