extends SceneTree

# Pins the articulated stem skeleton (PlantSkeleton) contract:
#   * growth adds internodes at the apex, one node per biomass unit;
#   * apical dominance holds buds until nutrients / a cut release them,
#     and a trimmed stem pushes side shoots from the nodes below the cut;
#   * the apex bends toward the light, bounded, and the grown stem bows;
#   * a stem that reaches the surface turns and trails along it;
#   * the skeleton survives a save round-trip, and pre-skeleton saves migrate;
#   * every sway parameter handed to the shader is bounded.

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_plant_skeleton")
	var host := Node3D.new()
	host.name = "PlantSkeletonHost"
	root.add_child(host)

	_check_apex_growth(t, host)
	_check_apical_dominance(t)
	_check_trim_side_shoots(t, host)
	_check_phototropism(t, host)
	_check_surface_trailing(t, host)
	_check_save_round_trip(t, host)
	_check_sway_bounds(t, host)
	_check_rosette_legacy(t, host)

	host.queue_free()
	await process_frame
	quit(t.finish())


func _make(host: Node3D, params: Dictionary, height: int = 1) -> Plant:
	var p: Plant = PlantScript.new()
	host.add_child(p)
	var merged: Dictionary = {"leaf_form": "lance", "max_height": 40,
		"asymmetry_seed": 4242, "sway_amplitude": 0.16}
	merged.merge(params, true)
	p.water_surface_y = 50.0
	p.init(height, merged)
	return p


func _check_apex_growth(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {})
	t.check(p.uses_stem_skeleton(), "lance stem plant uses the skeleton")
	t.equals(p.skeleton.node_count(), 1, "init(1) grows one internode")
	for _i in 7:
		p._grow_one()
	t.equals(p.skeleton.node_count(), 8, "each growth step adds one apex internode")
	t.equals(p.skeleton.node_count(), p.current_height, "nodes map 1:1 onto current_height")
	t.equals(p.biomass(), p.current_height, "biomass unchanged by the skeleton")
	var rising: bool = true
	for i in range(1, p.skeleton.node_count()):
		if p.skeleton.node_pos[i].y <= p.skeleton.node_pos[i - 1].y:
			rising = false
	t.check(rising, "internodes are added at the apex (node y strictly rising)")
	p.free()


func _check_apical_dominance(t: TestSupport.Suite) -> void:
	var sk := PlantSkeleton.new()
	for i in 20:
		sk.grow_internode(Vector3.UP, 0.27, 0.2, 0.2, 1.0, float(i) * 0.27, 0.0)
	t.equals(sk.pick_released_bud(1.0, 0.1, 0.8, 0.0), -1,
		"a lean, shaded apex keeps every bud dormant")
	var bud: int = sk.pick_released_bud(0.5, 1.0, 0.0, 0.0)
	t.check(bud >= 1 and bud <= sk.last_vertical_index() - 3,
		"rich nutrients release a bud outside the apex's dormancy zone (got %d)" % bud)
	t.check(sk.pick_released_bud(0.5, 1.0, 0.0, 0.99) == -1,
		"release is probabilistic, not every step")
	var removed: int = sk.truncate(sk.node_pos[14].y, 0)
	t.check(removed > 0 and not sk.apex_present, "a cut removes the apex")
	var cut_buds: PackedInt32Array = sk.release_buds_below_cut(2)
	t.equals(cut_buds.size(), 2, "pinching releases the two buds below the cut")
	t.check(cut_buds.size() == 0 or cut_buds[0] >= sk.last_vertical_index() - 3,
		"cut buds sit right under the cut")


func _check_trim_side_shoots(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {}, 14)
	var nodes_before: int = p.skeleton.node_count()
	p.trim_for_aquascape(0.4, "top")
	t.check(p.skeleton.node_count() < nodes_before,
		"trim removes nodes from the skeleton (%d -> %d)" % [nodes_before, p.skeleton.node_count()])
	t.check(not p.skeleton.apex_present, "trimmed stem has lost its apex")
	t.check(p._pending_axillary.size() >= 1, "trim queues axillary side shoots")
	var shoots_before: int = p.skeleton.side_shoot_nodes.size()
	var aux_before: int = p._aux_handles.size()
	var leaves_before: int = p._leaf_groups.size()
	p._grow_one()
	t.check(p.skeleton.side_shoot_nodes.size() >= maxi(shoots_before, 1),
		"side shoot recorded on the skeleton")
	t.check(p._aux_handles.size() > aux_before, "side shoot adds stem segments")
	t.check(p._leaf_groups.size() > leaves_before, "side shoot carries a new leaf")
	p.free()


func _check_phototropism(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {})
	# Lamp to +X; desire leans that way.
	p._tropism = Vector3(0.6, 0.8, 0.0).normalized()
	p._light_yaw_cache = PI * 0.5
	for _i in 14:
		p._grow_one()
	var apex: Vector3 = p.skeleton.apex_pos()
	t.check(apex.x > 0.05, "apex bends toward the light (x=%.3f)" % apex.x)
	var reach: float = p._plant_lateral_reach() * 1.3
	t.check(Vector2(apex.x, apex.z).length() <= reach + 0.05,
		"phototropic lean stays inside the lateral reach budget")
	var max_tilt: float = 0.0
	for i in range(1, p.skeleton.node_count()):
		var d: Vector3 = p.skeleton.node_dir[i]
		max_tilt = maxf(max_tilt, atan2(Vector2(d.x, d.z).length(), d.y))
	t.check(max_tilt <= PlantSkeleton.MAX_TILT_SHADE + 0.01,
		"internode tilt bounded (%.3f rad)" % max_tilt)
	# The grown stem slowly bows toward the lamp.
	for _i in 400:
		p._tick_skeleton_motion(0.45)
	var h: float = p._get_stem_top()
	t.check(p.skeleton.rest_bend.x > 0.0, "rest bend points at the lamp")
	t.check(p.skeleton.rest_bend.length() <= minf(h * PlantSkeleton.REST_BEND_HEIGHT_FRAC,
		PlantSkeleton.REST_BEND_MAX) + 1e-4, "rest bend bounded by stem height")
	var bend_1: float = p.skeleton.rest_bend.length()
	var sk := PlantSkeleton.new()
	sk.step_bend(Vector2(1.0, 0.0), 0.45, 10.0)
	t.check(sk.rest_bend.length() < 0.05, "the bow is slow (one step moves %.4f)" % sk.rest_bend.length())
	t.check(bend_1 > 0.0, "bow accumulates over minutes")
	p.free()


func _check_surface_trailing(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {"max_height": 40})
	p.water_surface_y = p.global_position.y + 3.0
	var guard: int = 0
	while p._grow_one() and guard < 60:
		guard += 1
	t.check(p._at_surface_cap(), "stem grew up to the surface")
	p._enter_canopy()
	var h_before: int = p.current_height
	for _i in 3:
		p._grow_trailing_internode()
	t.equals(p.skeleton.trail_count(), 3, "three trailing internodes along the surface")
	var surface_local: float = p.water_surface_y - p.global_position.y
	var along_surface: bool = true
	for i in p.skeleton.node_count():
		if p.skeleton.node_flags[i] & PlantSkeleton.FLAG_TRAIL:
			if absf(p.skeleton.node_pos[i].y - surface_local) > Plant.VOXEL_SIZE * 0.6:
				along_surface = false
	t.check(along_surface, "trailing nodes lie just under the waterline")
	var lv: int = p.skeleton.last_vertical_index()
	var base := Vector2(p.skeleton.node_pos[lv].x, p.skeleton.node_pos[lv].z)
	var tip := Vector2(p.skeleton.apex_pos().x, p.skeleton.apex_pos().z)
	t.check(base.distance_to(tip) > Plant.VOXEL_SIZE * 1.2,
		"trail runs horizontally away from the stem (%.3f)" % base.distance_to(tip))
	t.equals(p.biomass(), h_before + 3, "trailing tissue counts toward biomass")
	p.free()


func _check_save_round_trip(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {}, 10)
	p._tropism = Vector3(0.3, 0.9, 0.3).normalized()
	for _i in 6:
		p._grow_one()
	p.skeleton.rest_bend = Vector2(0.12, -0.05)
	p.skeleton.release_bud_at(4)
	var d: Dictionary = p.to_save_dict()
	t.has_keys(d, ["skeleton"], "save carries the skeleton")
	var p2: Plant = PlantScript.new()
	host.add_child(p2)
	p2.apply_save_dict(d)
	t.equals(p2.skeleton.vertical_count(), p.skeleton.vertical_count(), "node count survives reload")
	var max_err: float = 0.0
	for i in mini(p.skeleton.node_count(), p2.skeleton.node_count()):
		max_err = maxf(max_err, p.skeleton.node_pos[i].distance_to(p2.skeleton.node_pos[i]))
	t.check(max_err < 0.01, "reloaded stem keeps its grown curve (max err %.4f)" % max_err)
	t.check(p2.skeleton.rest_bend.distance_to(p.skeleton.rest_bend) < 0.002, "rest bend survives reload")
	t.check(p2.skeleton.side_shoot_nodes.has(4), "saved side shoot regrows on load")
	t.check(not p2.skeleton.has_replay(), "replay data released after load")
	# Migration: a pre-skeleton save has no key and must still load a chain.
	var legacy: Dictionary = d.duplicate(true)
	legacy.erase("skeleton")
	legacy.erase("_internode_extension_y")
	var p3: Plant = PlantScript.new()
	host.add_child(p3)
	p3.apply_save_dict(legacy)
	t.equals(p3.skeleton.node_count(), p3.current_height, "legacy save migrates to a fresh chain")
	t.equals(p3.biomass(), int(d["current_height"]), "legacy biomass preserved")
	var round2: Dictionary = p3.to_save_dict()
	t.check((round2["skeleton"] as Dictionary).has("pos"), "migrated plant saves a skeleton next time")
	p.free()
	p2.free()
	p3.free()


func _check_sway_bounds(t: TestSupport.Suite, host: Node3D) -> void:
	var ok: bool = true
	for h in [0.0, 0.5, 4.0, 15.0, 200.0]:
		for s in [-1.0, 0.0, 0.5, 1.0, 3.0]:
			for f in [Vector3.ZERO, Vector3(0.05, 0.0, 0.02), Vector3(0.4, 0.0, -0.3), Vector3(9.0, 3.0, 9.0)]:
				var c: Dictionary = PlantSkeleton.chain_sway(h, s, f, 0.2)
				var lean: Vector2 = c["flow_lean"]
				if lean.length() > minf(h * PlantSkeleton.FLOW_LEAN_HEIGHT_FRAC,
						PlantSkeleton.FLOW_LEAN_MAX) + 1e-4:
					ok = false
				if float(c["amp_scale"]) < 0.25 or float(c["amp_scale"]) > 1.3:
					ok = false
				if float(c["speed_scale"]) < 0.6 or float(c["speed_scale"]) > 1.2:
					ok = false
				if float(c["lag"]) < 1.2 or float(c["lag"]) > 3.4:
					ok = false
	t.check(ok, "chain_sway parameters bounded across height/stiffness/flow")
	var p: Plant = _make(host, {}, 20)
	p._brush_bend = Vector2(0.55, 0.0)
	p.skeleton.rest_bend = Vector2(5.0, 5.0)
	p._flow_lean = Vector2(3.0, 0.0)
	p._push_chain_bend()
	var h_top: float = p._get_stem_top()
	t.check(p._chain_bend_pushed.length() <= minf(h_top * 0.16, 2.0) + 1e-4,
		"pushed chain bend clamped (%.3f)" % p._chain_bend_pushed.length())
	p._apply_sway_personality()
	var mat: ShaderMaterial = p._foliage_mat if p._foliage_mat != null else p._stem_mat
	if t.check(mat != null, "stem plant has a chain material"):
		var amp: float = float(mat.get_shader_parameter("chain_sway_amp"))
		t.in_range(amp, 0.0, 0.45, "shader chain sway amplitude bounded")
		t.in_range(float(mat.get_shader_parameter("chain_lag")), 1.2, 3.4, "chain lag bounded")
	p.free()


func _check_rosette_legacy(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, {"leaf_form": "paddle"}, 4)
	t.check(not p.uses_stem_skeleton(), "rosettes keep the legacy path")
	t.equals(p.skeleton.node_count(), 0, "rosette grows no skeleton nodes")
	t.check((p.to_save_dict()["skeleton"] as Dictionary).is_empty(), "rosette saves an empty skeleton")
	t.check(p._rosette_runner_form(), "crypt/sword rosettes spread by runners")
	# Leaf plasticity: shade leaves larger, sun leaves smaller.
	p._light_avg = 0.95
	p._shade_mult = 1.0
	var sun: float = p._shade_size_mult()
	p._light_avg = 0.08
	var shade: float = p._shade_size_mult()
	t.check(sun < 1.0 and shade > 1.1, "leaf size answers light (sun %.2f, shade %.2f)" % [sun, shade])
	t.check(p._shade_thin_mult() < 1.0, "shade leaves bake thinner")
	p.free()
