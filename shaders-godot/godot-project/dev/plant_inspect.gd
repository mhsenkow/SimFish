extends Node

# Plant close-up harness (PlantSkeleton work). Builds the live World like
# dev/inspect.tscn, prints a plant census, then frames individual plants:
# the tallest stem-skeleton plants (side view, full height) and a rosette,
# plus a second shot of the first stem 1.5 s later to show chain sway.
#
# NB this builds a real World, which reads/writes TankSaves. Back up
# ~/Library/Application Support/Godot/app_userdata/walstad loom/tanks first.
#
#   -- out=/abs/dir/prefix_   settle=N

@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display

var _frame: int = 0
var _settle: int = 260
var _out_prefix: String = "res://plant_inspect_"
var _shots: Array = []   # [name, cam_pos, target, fov, wait_frames]
var _shot: int = 0
var _wait: int = 0


func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg != null:
		VoxelMat.apply_global_palette(cfg)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("settle="):
			_settle = maxi(30, int(a.split("=")[1]))
		if a.begins_with("out="):
			_out_prefix = a.substr(4)
		if a == "valli":
			_valli_only = true


# `-- valli`: skip the stem specimens and frame vallisneria instead (census of
# ribbon plants + a stand, a crown close-up and the surface canopy).
var _valli_only: bool = false


# Stem species are rare in the default roster, so the harness plants three
# identical stem specimens (same params before/after a change) to look at.
var _spawned: Array = []


func _spawn_stems() -> void:
	var w: Node = get_node("SubViewport/World")
	var pr: Node = w.get_node_or_null("Plants")
	if pr == null:
		return
	var water: float = float(w.get("WATER_HEIGHT"))
	var ramp: Array = [Color8(40, 72, 34), Color8(58, 98, 44), Color8(80, 128, 58),
		Color8(104, 156, 74), Color8(132, 182, 96), Color8(168, 206, 124)]
	var xs: Array = [-1.4, 0.0, 1.4]
	for i in 3:
		var p: Plant = load("res://scripts/plant.gd").new()
		pr.add_child(p)
		var x: float = float(xs[i])
		var z: float = 1.2
		var y: float = 0.0
		if w.has_method("column_surface_y"):
			y = float(w.call("column_surface_y", x, z))
		p.global_position = Vector3(x, y, z)
		p.water_surface_y = water
		p.init(90, {"leaf_form": "lance", "max_height": 90, "leaf_length": 3,
			"sway_amplitude": 0.16, "growth_rate": 0.18, "asymmetry_seed": 777 + i * 131,
			"ramp_override": ramp, "species_id": "harness_stem"})
		_spawned.append(p)
	# Exercise canopy / trim / light on the new code only (before-runs lack it).
	var a: Plant = _spawned[0]
	if a.has_method("_grow_trailing_internode"):
		a.set("_light_yaw_cache", PI * 0.5)
		for p2 in _spawned:
			if p2._at_surface_cap():
				p2._enter_canopy()
			for _k in 12:
				p2.call("_tick_skeleton_motion", 30.0)
		for _k in 5:
			a.call("_grow_trailing_internode")
		var b: Plant = _spawned[1]
		b.trim_for_aquascape(0.35, "top")
		for _k in 4:
			b._grow_one()
		var c: Plant = _spawned[2]
		for _k in 4:
			var bud: int = int(c.call("_maybe_release_axillary_bud", 0.0))
			if bud >= 0:
				c.call("_grow_axillary_shoot", c.ramp_override, bud)
	else:
		for p2 in _spawned:
			if p2._at_surface_cap():
				p2._enter_canopy()


func _census() -> void:
	var w: Node = get_node("SubViewport/World")
	var water: float = float(w.get("WATER_HEIGHT"))
	var pr: Node = w.get_node_or_null("Plants")
	var stems: Array = []
	var rosettes: Array = []
	var counts: Dictionary = {}
	var nodes_total: int = 0
	var trails: int = 0
	var shoots: int = 0
	if pr != null:
		print("[plant_inspect] Plants children=%d" % pr.get_child_count())
		for c in pr.get_children():
			if not c is Plant:
				counts[c.get_class()] = int(counts.get(c.get_class(), 0)) + 1
				continue
			var p: Plant = c
			var is_stem: bool = _is_stem(p)
			var key: String = "%s/%s%s" % [p._save_kind(), p.leaf_form, "*" if is_stem else ""]
			counts[key] = int(counts.get(key, 0)) + 1
			if is_stem:
				stems.append(p)
				var sk: Variant = p.get("skeleton")
				if sk != null:
					nodes_total += int(sk.node_count())
					trails += int(sk.trail_count())
					shoots += int(sk.side_shoot_nodes.size())
			elif p.leaf_form in ["paddle", "spade", "lobed"]:
				rosettes.append(p)
	print("[plant_inspect] water=%.2f census=%s" % [water, str(counts)])
	print("[plant_inspect] stem skeletons=%d nodes=%d trailing=%d side_shoots=%d" % [
		stems.size(), nodes_total, trails, shoots])
	stems.sort_custom(func(a: Plant, b: Plant) -> bool: return a.current_height > b.current_height)
	for i in mini(stems.size(), 6):
		var p: Plant = stems[i]
		var sk: Variant = p.get("skeleton")
		var extra: String = "" if sk == null else " nodes=%d trail=%d shoots=%s bend=%s apex=%s" % [
			int(sk.node_count()), int(sk.trail_count()), str(sk.side_shoot_nodes),
			str(sk.rest_bend), str(sk.apex_pos())]
		print("[plant_inspect]  stem %d %s h=%d/%d phase=%d%s" % [
			i, p.leaf_form, p.current_height, p.max_height, p.life_phase, extra])
	for i in _spawned.size():
		_frame_plant(_spawned[i], "harness_stem%d" % i)
	if not _spawned.is_empty():
		var p0: Plant = _spawned[0]
		var sk0: Variant = p0.get("skeleton")
		if sk0 != null:
			print("[plant_inspect]  harness stem0 nodes=%d trail=%d bend=%s" % [
				int(sk0.node_count()), int(sk0.trail_count()), str(sk0.rest_bend)])
		var top: float = p0.top_world_y()
		var mid := Vector3(p0.global_position.x, lerpf(p0.global_position.y, top, 0.8), p0.global_position.z)
		_shots.append(["stem0_crown", mid + Vector3(1.5, 0.6, 4.0), mid, 40.0, 1])
		_shots.append(["stem0_crown_t+1.5s", mid + Vector3(1.5, 0.6, 4.0), mid, 40.0, 90])
	if not rosettes.is_empty():
		_frame_plant(rosettes[0], "rosette")
		var r: Plant = rosettes[0]
		var rc := r.global_position + Vector3(0.0, 0.6, 0.0)
		_shots.append(["rosette_close", rc + Vector3(1.2, 1.4, 2.6), rc, 45.0, 1])
	if pr != null:
		for c in pr.get_children():
			if c is Plant and (c as Plant).leaf_form == "ribbon":
				var rb: Plant = c
				var mid := rb.global_position + Vector3(0.0, 4.0, 0.0)
				_shots.append(["ribbon", mid + Vector3(2.0, 0.5, 7.0), mid, 50.0, 1])
				_shots.append(["ribbon_t+1.5s", mid + Vector3(2.0, 0.5, 7.0), mid, 50.0, 90])
				break


func _is_stem(p: Plant) -> bool:
	if p.has_method("uses_stem_skeleton"):
		return bool(p.call("uses_stem_skeleton"))
	return p._save_kind() == "plant" and not p.is_epiphyte and not p.is_carpet \
		and (p.whorled_leaves or p.leaf_form in ["lance", "pinnate", "fingered", "downy",
			"oval", "cordate", "column"])


func _frame_plant(p: Plant, label: String) -> void:
	var base: Vector3 = p.global_position
	var top: float = p.top_world_y()
	var h: float = maxf(top - base.y, 1.0)
	var target := Vector3(base.x, base.y + h * 0.5, base.z)
	var dist: float = clampf(h * 1.1, 3.0, 30.0)
	_shots.append([label, target + Vector3(dist * 0.25, h * 0.08, dist), target, 50.0, 1])


func _aim(s: Array) -> void:
	var cam: Camera3D = $SubViewport/World/Camera3D
	cam.position = s[1]
	cam.look_at(s[2], Vector3.UP)
	cam.fov = float(s[3])
	cam.make_current()


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == _settle - 30:
		if _valli_only:
			_spawn_valli()
		else:
			_spawn_stems()
	if _frame < _settle:
		return
	if _frame == _settle:
		if _valli_only:
			_valli_census()
		else:
			_census()
		if _shots.is_empty():
			print("[plant_inspect] no plants to frame")
			get_tree().quit(0)
			return
		_aim(_shots[0])
		_wait = int(_shots[0][4]) + 5
		return
	_wait -= 1
	if _wait > 0:
		return
	var img: Image = sub_viewport.get_texture().get_image()
	img.save_png("%s%s.png" % [_out_prefix, _shots[_shot][0]])
	print("[plant_inspect] saved %s" % _shots[_shot][0])
	_shot += 1
	if _shot >= _shots.size():
		print("[plant_inspect] done")
		get_tree().quit(0)
		return
	_aim(_shots[_shot])
	_wait = int(_shots[_shot][4]) + 5


func _valli_census() -> void:
	var w: Node = get_node("SubViewport/World")
	var water: float = float(w.get("WATER_HEIGHT"))
	var pr: Node = w.get_node_or_null("Plants")
	var ribbons: Array = []
	if pr != null:
		for c in pr.get_children():
			if c is Plant and (c as Plant).leaf_form == "ribbon":
				ribbons.append(c)
	print("[plant_inspect] water=%.2f ribbon plants=%d" % [water, ribbons.size()])
	for i in mini(ribbons.size(), 8):
		var p: Plant = ribbons[i]
		print("[plant_inspect]  valli %d pos=%s h=%d/%d leaves=%d stem_vox=%d top=%.2f phase=%d bio=%d" % [
			i, str(p.global_position.snapped(Vector3.ONE * 0.01)), p.current_height,
			p.max_height, p._leaf_groups.size(), p.voxels.size(), p.top_world_y(),
			p.life_phase, p.biomass()])
	if pr != null:
		for c in pr.get_children():
			if c is Plant and (c as Plant).top_world_y() > water - 1.5:
				var q: Plant = c
				print("[plant_inspect]  tall %s kind=%s form=%s sp=%s pos=%s h=%d/%d leaves=%d vox=%d" % [
					q.name, q._save_kind(), q.leaf_form, q.species_id,
					str(q.global_position.snapped(Vector3.ONE * 0.01)), q.current_height,
					q.max_height, q._leaf_groups.size(), q.voxels.size()])
	_probe_rods(w, water)
	for sp in _spawned:
		var q: Plant = sp
		print("[plant_inspect]  specimen h=%d/%d leaves=%d handles=%d top=%.2f" % [
			q.current_height, q.max_height, q._leaf_groups.size(),
			q._foliage_batch._count if q._foliage_batch != null else 0, q.top_world_y()])
	if _spawned.size() == 2:
		var s0: Plant = _spawned[0]
		var s1: Plant = _spawned[1]
		var hh: float = water - s0.global_position.y
		var m0 := s0.global_position + Vector3(0.6, hh * 0.5, 0.0)
		_shots.append(["spec_full", m0 + Vector3(0.0, 0.0, hh * 1.05), m0, 55.0, 1])
		_shots.append(["spec_full_t+1.5s", m0 + Vector3(0.0, 0.0, hh * 1.05), m0, 55.0, 90])
		var c0 := s0.global_position + Vector3(0.0, 1.2, 0.0)
		_shots.append(["spec_crown", c0 + Vector3(0.6, 0.3, 3.4), c0, 45.0, 1])
		var t0 := Vector3(s0.global_position.x, water - 0.5, s0.global_position.z)
		_shots.append(["spec_surface", t0 + Vector3(1.0, -2.2, 3.6), t0 + Vector3(0.0, 0.2, -0.5), 60.0, 1])
		var c1 := s1.global_position + Vector3(0.0, 1.4, 0.0)
		_shots.append(["spec_young", c1 + Vector3(0.4, 0.4, 4.2), c1, 45.0, 1])
	if ribbons.is_empty():
		return
	# The ribbon nearest the front-centre gets the close-ups.
	ribbons.sort_custom(func(pa: Plant, pb: Plant) -> bool:
		return absf(pa.global_position.x) + absf(pa.global_position.z - 1.0) \
			< absf(pb.global_position.x) + absf(pb.global_position.z - 1.0))
	var r: Plant = ribbons[0]
	var b: Vector3 = r.global_position
	var h: float = maxf(water - b.y, 2.0)
	var mid := b + Vector3(0.0, h * 0.5, 0.0)
	_shots.append(["valli_stand", mid + Vector3(1.0, 0.0, h * 1.25), mid, 55.0, 1])
	_shots.append(["valli_stand_t+1.5s", mid + Vector3(1.0, 0.0, h * 1.25), mid, 55.0, 90])
	var crown := b + Vector3(0.0, 0.9, 0.0)
	_shots.append(["valli_crown", crown + Vector3(0.8, 0.5, 3.2), crown, 45.0, 1])
	var top := Vector3(b.x, water - 0.4, b.z)
	_shots.append(["valli_surface", top + Vector3(2.5, -1.6, 4.5), top, 55.0, 1])
	_shots.append(["valli_wide", Vector3(0.0, water * 0.55, 16.0), Vector3(0.0, water * 0.5, 0.0), 60.0, 1])


func _probe_rods(n: Node, water: float) -> void:
	if n is VisualInstance3D and (n as Node3D).is_visible_in_tree():
		var vi: VisualInstance3D = n
		var bb: AABB = vi.global_transform * vi.get_aabb()
		if bb.size.y > water * 0.4 and maxf(bb.size.x, bb.size.z) < 1.2:
			print("[plant_inspect]  rod %s (%s) parent=%s aabb=%s" % [
				vi.get_path(), vi.get_class(), vi.get_parent().name, str(bb)])
	for c in n.get_children():
		_probe_rods(c, water)


# Two isolated specimens in open water at the front: a mature crown that has
# reached the surface and a young one, so blade shape reads without the bed.
func _spawn_valli() -> void:
	var w: Node = get_node("SubViewport/World")
	var pr: Node = w.get_node_or_null("Plants")
	if pr == null:
		return
	var water: float = float(w.get("WATER_HEIGHT"))
	var ramp: Array = [Color8(16, 38, 20), Color8(29, 59, 34), Color8(44, 90, 48),
		Color8(62, 127, 64), Color8(87, 162, 83), Color8(121, 192, 105)]
	var spots: Array = [Vector2(-1.2, 3.6), Vector2(2.2, 3.9)]
	for i in 2:
		var p: Plant = load("res://scripts/plant.gd").new()
		pr.add_child(p)
		var x: float = spots[i].x
		var z: float = spots[i].y
		var y: float = 0.0
		if w.has_method("column_surface_y"):
			y = float(w.call("column_surface_y", x, z))
		p.global_position = Vector3(x, y, z)
		p.water_surface_y = water
		var reach: int = PlantEstablish.surface_reach_voxels(y, water, 0.32)
		var mature: int = PlantEstablish.surface_height(y, water, 0.32, 18, 14)
		p.init(reach + 1 if i == 0 else 12, {"leaf_form": "ribbon", "max_height": mature,
			"leaf_length": 8, "sway_amplitude": 0.22, "growth_rate": 0.18,
			"asymmetry_seed": 4242 + i * 17, "ramp_override": ramp,
			"surface_pooling": true, "max_roots": 4})
		_spawned.append(p)
