extends SceneTree

# World-level light drag invariants (bug A: "the light comes out different
# once you touch it"). Builds a real World once, then rebuilds only the
# fixture for each type and drives the same world API the drag uses.
#
#   - build == drag: re-applying the stored placement moves nothing
#   - a bar re-aims PARALLEL (it used to converge into one hot pool)
#   - dragging never leaks shafts or mote emitters
#   - every shaft points where its spot points
#   - a reload (rebuild from config) lands where the drag left it
#   - cancel restores the built rotations exactly
#   - the cone, colour and spot count are untouched by a drag

const R := preload("res://scripts/lighting_rig.gd")
const FIXTURES: Array[String] = ["bar", "gooseneck", "spotlight"]
const KEYS: Array[String] = ["light_fixture", "light_volumetric", "spot_offset_x",
	"spot_offset_z", "spot_aim_x", "spot_aim_z", "capture_mode"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := TestSupport.Suite.new("light_drag")
	var cfg: Node = root.get_node_or_null("/root/TankConfig")
	if cfg == null:
		t.check(false, "TankConfig autoload present")
		quit(t.finish())
		return
	var saved: Dictionary = {}
	for k in KEYS:
		saved[k] = cfg.get(k)
	cfg.set("capture_mode", true)  # never write the player's settings
	cfg.light_volumetric = true
	cfg.spot_offset_x = 0.0
	cfg.spot_offset_z = 0.0
	cfg.spot_aim_x = R.AIM_OFF
	cfg.spot_aim_z = R.AIM_OFF
	var w: Node3D = (load("res://scripts/world.gd") as Script).new() as Node3D
	w.name = "SmokeLightDragWorld"
	root.add_child(w)
	await process_frame
	await process_frame

	for fixture in FIXTURES:
		cfg.spot_offset_x = 0.0
		cfg.spot_offset_z = 0.0
		cfg.spot_aim_x = R.AIM_OFF
		cfg.spot_aim_z = R.AIM_OFF
		_rebuild(w, cfg, fixture)
		var spots: Array = w.get("_light_fixture_spots")
		t.check(spots.size() > 0, "%s: fixture has spots" % fixture)
		if spots.is_empty():
			continue
		var n: int = spots.size()
		var built_rot: Array = _rots(spots)
		var built_root: Vector3 = w.light_fixture_root_world()
		var cone: Array = _cone(spots)
		t.check(_beam_count(w) == n, "%s: one shaft per spot at build (%d)" % [fixture, _beam_count(w)])

		# build == drag: the drag's own setter with the stored values is a no-op.
		w.set_light_placement(0.0, 0.0, R.AIM_OFF, R.AIM_OFF)
		t.check(w.light_fixture_root_world().distance_to(built_root) < 0.001,
			"%s: build and drag agree on the head (moved %.3f)" % [
				fixture, w.light_fixture_root_world().distance_to(built_root)])
		t.check(_rots_equal(_rots(spots), built_rot),
			"%s: touching the lamp keeps the built beam direction" % fixture)
		# The handle sits on the fixture's centre (a bar's first spot is its end).
		var hw: Vector3 = w.light_fixture_head_world()
		t.check(Vector2(hw.x, hw.z).distance_to(Vector2(built_root.x, built_root.z)) < 0.01,
			"%s: the handle is drawn on the fixture's centre" % fixture)
		# With no aim, the aim ring still sits where the beam lands.
		t.check(w.light_aim_world().is_finite(),
			"%s: the aim ring is findable before any aim is set" % fixture)

		# Drag for a while: head moves, aim moves.
		for i in 40:
			var f: float = float(i) / 40.0
			w.set_light_placement(0.6 * sin(f * TAU), 0.4 * cos(f * TAU),
				0.3 * cos(f * TAU), -0.2 + 0.2 * sin(f * TAU))
		await process_frame
		t.check(_beam_count(w) == n and _motes_count(w) == n,
			"%s: 40 drag steps leave %d shafts / %d motes (want %d)" % [
				fixture, _beam_count(w), _motes_count(w), n])
		var fwd0: Vector3 = R.spot_forward(spots[0])
		var parallel: bool = true
		for s in spots:
			parallel = parallel and R.spot_forward(s).dot(fwd0) > 0.9999
		t.check(parallel, "%s: aimed spots stay parallel (no hot pool)" % fixture)
		t.check(_beams_follow(w), "%s: every shaft points where its spot points" % fixture)
		t.check(_cone(spots) == cone, "%s: cone angle, softness and reach untouched" % fixture)

		# Reload: rebuild from what the drag stored; it must land in the same place.
		var drag_root: Vector3 = w.light_fixture_root_world()
		var drag_fwd: Vector3 = R.spot_forward(spots[0])
		_rebuild(w, cfg, fixture)
		spots = w.get("_light_fixture_spots")
		t.check(w.light_fixture_root_world().distance_to(drag_root) < 0.001,
			"%s: reload puts the lamp where the drag left it" % fixture)
		t.check(R.spot_forward(spots[0]).dot(drag_fwd) > 0.9999,
			"%s: reload keeps the dragged beam direction" % fixture)

		# Cancel back to "no aim" restores the built rotation exactly.
		w.set_light_placement(0.0, 0.0, R.AIM_OFF, R.AIM_OFF)
		t.check(_rots_equal(_rots(spots), built_rot),
			"%s: cancelling to no aim restores the built beam" % fixture)
		t.check(w.light_fixture_root_world().distance_to(built_root) < 0.001,
			"%s: cancelling restores the head" % fixture)

	# The aim stays inside the glass whatever the cursor does.
	var far: Vector2 = w.light_aim_for(Vector3(1e4, 0.0, -1e4))
	var hw_: float = float(w.get("TANK_HALF_W"))
	var hd_: float = float(w.get("TANK_HALF_D"))
	var poly := PackedVector2Array()
	for c in w.call("_tank_footprint_corners"):
		poly.append(Vector2((c as Vector3).x, (c as Vector3).z))
	t.check(Geometry2D.is_point_in_polygon(Vector2(far.x * hw_, far.y * hd_), poly),
		"an aim dragged across the room is clamped inside the tank footprint")

	for k in KEYS:
		cfg.set(k, saved[k])
	w.queue_free()
	await process_frame
	quit(t.finish())


func _rebuild(w: Node3D, cfg: Node, fixture: String) -> void:
	cfg.light_fixture = fixture
	var r: Variant = w.get("_light_fixture_root")
	if r != null and is_instance_valid(r):
		(r as Node).free()
	(w.get("_light_fixture_spots") as Array).clear()
	w.call("_build_light_fixture")


func _rots(spots: Array) -> Array:
	var out: Array = []
	for s in spots:
		out.append((s as Node3D).basis)
	return out


func _rots_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not (a[i] as Basis).is_equal_approx(b[i] as Basis):
			return false
	return true


func _cone(spots: Array) -> Array:
	var out: Array = []
	for s in spots:
		var sp := s as SpotLight3D
		# Not light_color / energy: the daylight sync legitimately moves those per frame.
		out.append([snappedf(sp.spot_angle, 0.001),
			snappedf(sp.spot_attenuation, 0.001), sp.spot_range])
	return [spots.size(), out]


func _beams(w: Node3D) -> Array:
	var out: Array = []
	var r: Node = w.get("_light_fixture_root")
	for c in r.get_children():
		# By meta, not name: sibling shafts get auto-renamed "@MeshInstance3D@N",
		# which is exactly how the old name-matched cleanup leaked them.
		if c is MeshInstance3D and c.has_meta("beam_spot") \
				and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _beam_count(w: Node3D) -> int:
	return _beams(w).size()


func _motes_count(w: Node3D) -> int:
	var n: int = 0
	var r: Node = w.get("_light_fixture_root")
	for c in r.get_children():
		if c is GPUParticles3D and not c.is_queued_for_deletion():
			n += 1
	return n


func _beams_follow(w: Node3D) -> bool:
	for mi in _beams(w):
		var spot: Node3D = (mi as Node).get_meta("beam_spot", null)
		if spot == null:
			return false
		# beam_basis puts local -Y along the beam.
		var along: Vector3 = -(mi as Node3D).basis.y.normalized()
		if along.dot(R.spot_forward(spot)) < 0.999:
			return false
	return true
