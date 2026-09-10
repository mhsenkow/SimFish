extends SceneTree

const CanopyDensityBuilder := preload("res://scripts/canopy_density.gd")

func _initialize() -> void:
	var failed: Array[String] = []
	var plant := Plant.new()
	root.add_child(plant)
	plant.current_height = 12
	await process_frame
	var image: Image = CanopyDensityBuilder.build([plant], 7.5, 3.5)
	_assert(failed, image.get_width() == 16 and image.get_height() == 8,
		"canopy input stays low resolution")
	var occupied: bool = false
	for y in image.get_height():
		for x in image.get_width():
			occupied = occupied or image.get_pixel(x, y).r > 0.0
	_assert(failed, occupied, "living crown contributes density")
	var source := FileAccess.get_file_as_string("res://scripts/world.gd")
	var builder := FileAccess.get_file_as_string("res://scripts/canopy_density.gd")
	_assert(failed, builder.contains("PLANT_CAP: int = 128"),
		"canopy scan is capped")
	_assert(failed, source.contains("_canopy_density_next_ms = now_ms + 3000"),
		"input updates coarsely")
	_assert(failed, source.contains("shader_perf_tier() < 2"),
		"lowest tier disables canopy attenuation")
	plant.queue_free()
	if failed.is_empty(): print("SMOKE_PLANT_VISUAL_11_OK"); quit(0); return
	for message in failed: push_error(message)
	quit(1)

func _assert(failed: Array[String], condition: bool, message: String) -> void:
	if not condition: failed.append(message)
