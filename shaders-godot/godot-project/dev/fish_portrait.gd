# Fish portrait — the shipped render, with a species lineup held in front of
# the lens.
#
# WHY THIS EXISTS. The fauna look is judged at the size a player actually sees
# it: 15-30 render pixels long inside a planted tank, under the real palette,
# post chain and lighting. dev/visual_capture.tscn gives that frame but not the
# fish in it — the stocked fish swim wherever the brain sends them, and at the
# default angles a guppy is a few pixels somewhere behind a leaf. This harness
# is visual_capture.gd plus one thing: at the moment the harness arms, it
# spawns one adult male and one adult female of each named species and pins
# them in a row facing +X, broadside to the camera, in open water.
#
# The lineup fish are NOT registered with the sim: the brain never ticks them,
# so they hold station and show the hover pose (pectoral sculling, breathing,
# tail idle) instead of swimming off. _process still runs the whole visual
# pipeline — pivots, custom data, colour ticks.
#
#   FISH_PORTRAIT_SPECIES   comma list of SPECIES_LIBRARY keys
#                           (default guppy,glassdart)
#   FISH_PORTRAIT_SPACING   world units between columns (default 1.5)
#   FISH_PORTRAIT_YAW       lineup heading in radians (default 0 = facing +X)
#
# Every VISUAL_CAPTURE_* override still applies; pair it with a close
# VISUAL_CAPTURE_CAM, e.g. "0.0,-0.02,4.5,0.62". Like visual_capture it sets
# capture_mode, so no save slot is read or written.

extends "res://dev/visual_capture.gd"

var _lineup: Array = []
var _spawned: bool = false


func _process(dt: float) -> void:
	if not _spawned and _frame >= _settle - 2 and _main != null:
		_spawned = true
		_spawn_lineup()
	super._process(dt)
	_pin_lineup()


func _spawn_lineup() -> void:
	var world: Variant = _main.get("world")
	var sim: Variant = _main.get("_sim")
	if not (world is Node3D):
		push_warning("[fish_portrait] no world")
		return
	var root: Node = (world as Node).get("fauna_root")
	if root == null:
		root = world
	var cfg := get_node_or_null("/root/TankConfig")
	var keys: PackedStringArray = _env("FISH_PORTRAIT_SPECIES", "guppy,glassdart").split(",", false)
	var spacing: float = _env("FISH_PORTRAIT_SPACING", "1.5").to_float()
	var floor_y: float = float((world as Node).get("SUBSTRATE_DEPTH"))
	var surface_y: float = float((world as Node).get("WATER_HEIGHT"))
	var mid_y: float = lerpf(floor_y, surface_y, 0.62)
	var n: int = keys.size()
	for i in n:
		var key: String = keys[i].strip_edges()
		var lib: Dictionary = cfg.SPECIES_LIBRARY if cfg != null else {}
		var entry: Dictionary = lib.get(key, {})
		if entry.is_empty():
			push_warning("[fish_portrait] unknown species " + key)
			continue
		for sex in 2:
			var g: Dictionary = (entry.get("genome", {}) as Dictionary).duplicate(true)
			g["sex"] = sex
			g["id"] = "portrait_%s_%d" % [key, sex]
			var f := Fish.new()
			f.age = float(g.get("max_age_s", 240.0)) * 0.45
			root.add_child(f)
			var x: float = (float(i) - float(n - 1) * 0.5) * spacing
			var y: float = mid_y + (0.45 if sex == 0 else -0.45)
			f.global_position = Vector3(x, y, 0.0)
			if sim is Node:
				f.sim = sim
			f.init_genome(g)
			_lineup.append({"fish": f, "pos": f.global_position})
	print("[fish_portrait] lineup=", _lineup.size())


func _pin_lineup() -> void:
	var yaw: float = _env("FISH_PORTRAIT_YAW", "0").to_float()
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))
	for e in _lineup:
		var f: Variant = e["fish"]
		if f == null or not is_instance_valid(f):
			continue
		var fn: Node3D = f
		fn.global_position = e["pos"]
		fn.look_at(fn.global_position + fwd, Vector3.UP)
		fn.set("velocity", Vector3.ZERO)
		fn.set("target_velocity", Vector3.ZERO)
