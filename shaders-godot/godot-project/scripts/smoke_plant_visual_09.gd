extends SceneTree

class LightStub extends Node:
	func daylight() -> float:
		return 1.0

func _initialize() -> void:
	var failed: Array[String] = []
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var plant := Plant.new()
	plant.red_potential = 0.9
	host.add_child(plant)
	var batch := VoxelBatch.new(plant, StandardMaterial3D.new(), 2, true)
	var handle := batch.add(Transform3D.IDENTITY, Color.GREEN)
	handle.set_custom_data(Color(0.4, 0.2, 0.0, 1.0))
	plant._leaf_groups = [[handle]]
	plant._register_leaf_age(0.0)
	var light := LightStub.new()
	plant._tick_leaf_light_dose(45.0, light)
	light.free()
	TestSupport.check(failed, handle.custom_data.b > 0.9, "bright mature leaf accumulates dose")
	var saved := plant._leaf_light_doses_snapshot()
	plant._leaf_states[0].light_dose = 0.0
	plant._restore_leaf_light_doses(saved)
	TestSupport.check(failed, float(plant._leaf_states[0].light_dose) > 0.9,
		"bounded dose round-trips save data")
	var source := FileAccess.get_file_as_string("res://shaders/foliage_mm.gdshader")
	TestSupport.check(failed, source.contains("red_potential * v_light_dose"),
		"shader combines dose with species red potential")
	host.queue_free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_09_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)
