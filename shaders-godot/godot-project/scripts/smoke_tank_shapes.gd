extends SceneTree

const SHAPES: Array[String] = ["box", "cube", "hex", "triangle", "cylinder", "sphere"]


func _initialize() -> void:
	await process_frame
	var cfg := get_root().get_node_or_null("TankConfig")
	if cfg == null:
		push_error("[smoke] TankConfig autoload missing")
		quit(1)
		return
	var world_script: Script = load("res://scripts/world.gd")
	var failed: Array[String] = []
	for shape in SHAPES:
		cfg.tank_shape = shape
		var w: Node3D = world_script.new() as Node3D
		w.name = "SmokeWorld_" + shape
		root.add_child(w)
		await process_frame
		await process_frame
		if w.get("terrain_grid") == null:
			failed.append("%s: terrain_grid null" % shape)
		elif w.get_child_count() < 2:
			failed.append("%s: too few children (%d)" % [shape, w.get_child_count()])
		if w.has_method("_surface_floater_capacity"):
			var cap: int = int(w.call("_surface_floater_capacity"))
			if cap < 4:
				failed.append("%s: floater cap too low (%d)" % [shape, cap])
			elif shape in ["box", "cube", "hex", "triangle"]:
				# Triangle/hex footprints are smaller — scale the floor with shape multiplier.
				var min_cap: int = maxi(
					8, int(round(40.0 * WorldFloaterManager.shape_capacity_multiplier(shape))))
				if cap < min_cap:
					failed.append("%s: floater cap suspiciously low (%d < %d)" % [shape, cap, min_cap])
			else:
				print_verbose("[smoke] %s floater cap=%d mult=%.2f" % [
					shape, cap, WorldFloaterManager.shape_capacity_multiplier(shape),
				])
		w.queue_free()
		await process_frame
	if failed.is_empty():
		print("[smoke] all tank shapes OK: ", ", ".join(SHAPES))
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)
