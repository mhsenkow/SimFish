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
		w.queue_free()
		await process_frame
	if failed.is_empty():
		print("[smoke] all tank shapes OK: ", ", ".join(SHAPES))
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] " + f)
		quit(1)
