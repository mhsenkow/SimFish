# AquariumVisuals — lightweight coordinator for the 50-item visual polish pass.
# Attached as a child of World; ticked from world._process at 10 Hz for cosmetics.

extends Node3D
class_name AquariumVisuals

const TICK_INTERVAL: float = 0.1
const SLIME_CAP: int = 96
const SPARKLE_CAP: int = 12
const FLOATER_SHADOW_CAP: int = 64

var _world: Node3D
var _sim: Node
var _cfg: Node
var _accum: float = 0.0
var _glass_mat: ShaderMaterial
var _glass_root: Node3D
var _glass_walls: Array[MeshInstance3D] = []
var _compaction: Dictionary = {}
var _slime_marks: Array[MeshInstance3D] = []
var _mineral_streaks: Array[MeshInstance3D] = []
var _floater_shadows: Array[MeshInstance3D] = []

var _haze_particles: GPUParticles3D
var _debris_particles: GPUParticles3D
var _rain_particles: GPUParticles3D
var _condensation_particles: GPUParticles3D
var _current_ribbons: GPUParticles3D
var _gas_escape_particles: GPUParticles3D
var _filter_cavitation_t: float = 0.0
var _gas_escape_t: float = 0.0
var _rain_t: float = 0.0
var _sparkle_t: float = 0.0
var _screenshot_boost_t: float = 0.0
var _seasonal_hue: float = 0.0
var _active_ripples: int = 0
const MAX_RIPPLES: int = 24


func setup(world: Node3D, sim: Node) -> void:
	_world = world
	_sim = sim
	_cfg = get_node_or_null("/root/TankConfig")
	_seasonal_hue = _compute_seasonal_hue()
	_build_ambient_emitters()
	_build_waterline_tick()


func _build_waterline_tick() -> void:
	if _world == null:
		return
	# Full-width tick only makes sense on rectilinear tanks; on a cylinder the
	# bar would span the bounding box and poke through the glass into the void.
	var shape: String = String(_world.TANK_SHAPE)
	if shape == "cylinder" or shape == "sphere":
		return
	var mi := MeshInstance3D.new()
	mi.name = "WaterlineTick"
	var hw: float = float(_world.TANK_HALF_W) - 0.4
	mi.mesh = VoxelMat.get_box(Vector3(hw * 2.0, 0.04, 0.04))
	mi.material_override = VoxelMat.make(Color8(170, 210, 230))
	mi.position = Vector3(0.0, float(_world.WATER_HEIGHT), float(_world.TANK_HALF_D) - 0.03)
	_world.add_child(mi)


func register_glass(root: Node3D, mat: ShaderMaterial) -> void:
	_glass_root = root
	_glass_mat = mat
	_glass_walls.clear()
	_collect_glass_meshes(root)
	_add_glass_rim_bevels(root)


func tick(dt: float, ambient_due: bool) -> void:
	if not ambient_due or _world == null:
		if _screenshot_boost_t > 0.0:
			_screenshot_boost_t = maxf(0.0, _screenshot_boost_t - dt)
		return
	_accum += dt
	if _accum < TICK_INTERVAL:
		return
	_accum = 0.0
	var sdt: float = dt
	if _sim != null:
		sdt = dt * float(_sim.time_scale)
	_update_glass_cosmetics(sdt)
	_update_bubble_tints()
	_maybe_gas_escape(sdt)
	_maybe_filter_cavitation(sdt)
	_maybe_rain_on_glass(sdt)
	_maybe_glass_sparkle(sdt)
	_update_god_ray_occlusion()
	_cleanup_slime()
	_sync_floater_shadows()
	if _screenshot_boost_t > 0.0:
		_screenshot_boost_t = maxf(0.0, _screenshot_boost_t - dt)


func begin_screenshot_boost(duration: float = 3.0) -> void:
	_screenshot_boost_t = duration
	if _world.get("_water_material_ref") != null:
		var wm: ShaderMaterial = _world._water_material_ref
		wm.set_shader_parameter("wave_amplitude", 0.042)
		wm.set_shader_parameter("wave2_amplitude", 0.022)
		wm.set_shader_parameter("caustic_intensity", 0.85)
		wm.set_shader_parameter("depth_fog", 0.55)


func screenshot_boost_active() -> bool:
	return _screenshot_boost_t > 0.0


func seasonal_palette_shift() -> float:
	return _seasonal_hue


func record_compaction(x: float, z: float, amount: float = 0.02) -> void:
	var key: Vector2i = Vector2i(int(floor(x * 2.0)), int(floor(z * 2.0)))
	_compaction[key] = clampf(float(_compaction.get(key, 0.0)) + amount, 0.0, 1.0)
	if _world != null and _world.has_method("tint_substrate_cell"):
		_world.tint_substrate_cell(x, z, Color(0.72, 0.68, 0.58), float(_compaction[key]) * 0.48)


func spawn_splash_crown(pos: Vector3) -> void:
	if _world == null:
		return
	var root := Node3D.new()
	root.position = Vector3(pos.x, _world.WATER_HEIGHT - 0.03, pos.z)
	_world.add_child(root)
	for i in 5:
		var ang: float = float(i) / 5.0 * TAU
		var drop := MeshInstance3D.new()
		drop.mesh = VoxelMat.get_box(Vector3(0.08, 0.12, 0.08))
		drop.material_override = VoxelMat.make(Color8(210, 235, 245))
		drop.position = Vector3(cos(ang) * 0.12, 0.08, sin(ang) * 0.12)
		root.add_child(drop)
		var tw := create_tween()
		tw.tween_property(drop, "position", drop.position + Vector3(
			cos(ang) * 0.35, 0.55, sin(ang) * 0.35), 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(drop, "scale", Vector3(0.2, 0.2, 0.2), 0.35)
	spawn_burst_ripple_proxy(pos)
	get_tree().create_timer(0.45).timeout.connect(root.queue_free)


func spawn_pop_spray(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 4
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.position = Vector3(pos.x, _world.WATER_HEIGHT - 0.02, pos.z)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0, -1.2, 0)
	pm.spread = 35.0
	pm.scale_min = 0.15
	pm.scale_max = 0.35
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.025
	bm.height = 0.05
	bm.radial_segments = 4
	bm.rings = 2
	bm.material = VoxelMat.make_bubble(Color(0.9, 0.97, 1.0, 0.35))
	p.draw_pass_1 = bm
	_world.add_child(p)
	p.emitting = true
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)


func _release_slime_mark(mi: MeshInstance3D) -> void:
	_slime_marks.erase(mi)
	if is_instance_valid(mi):
		mi.queue_free()


func _pop_slime_mark() -> void:
	while not _slime_marks.is_empty():
		var old = _slime_marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()
			return


func spawn_snail_slime(pos: Vector3, wall_n: Vector3) -> void:
	if _slime_marks.size() >= SLIME_CAP:
		_pop_slime_mark()
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(0.06, 0.02, 0.06))
	# Duplicate the cached material so a fade tween on this mark doesn't
	# alpha-down every other slime mark sharing the cache entry. Then
	# tween the mark from its full alpha down to zero over the lifetime
	# so the trail visibly *recedes* behind the snail instead of all
	# marks popping out simultaneously at the end of the 14s window.
	var base_mat: ShaderMaterial = VoxelMat.make(Color(0.72, 0.82, 0.78, 0.35))
	var mat: ShaderMaterial = base_mat.duplicate()
	mi.material_override = mat
	mi.position = pos + wall_n * 0.02
	if _glass_root != null:
		_glass_root.add_child(mi)
	else:
		_world.add_child(mi)
	_slime_marks.append(mi)
	# Hold full alpha for the first ~30% of the mark's life, then fade
	# linearly to zero over the remaining 70%. The fifo will pop the
	# oldest if SLIME_CAP is hit before the tween completes anyway.
	const LIFETIME: float = 14.0
	var tw := create_tween()
	tw.tween_interval(LIFETIME * 0.30)
	var start_col: Color = VoxelMat.read_albedo(mat, Color(0.72, 0.82, 0.78, 0.35))
	var end_col: Color = Color(start_col.r, start_col.g, start_col.b, 0.0)
	tw.tween_property(mat, "shader_parameter/albedo", end_col, LIFETIME * 0.70)
	# Use a lambda so the MeshInstance3D is never passed as a typed argument
	# after it may have been freed — .bind(mi) causes a type-coercion error
	# in emit_signalp when the object is no longer valid.
	get_tree().create_timer(LIFETIME).timeout.connect(func() -> void:
		if is_instance_valid(mi):
			_release_slime_mark(mi))


func spawn_snail_bubble(pos: Vector3) -> void:
	if randf() > 0.35:
		return
	var p := GPUParticles3D.new()
	p.amount = 1
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.28
	pm.gravity = Vector3(0, 0.6, 0)
	pm.spread = 8.0
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.02
	bm.height = 0.04
	bm.radial_segments = 4
	bm.rings = 2
	bm.material = VoxelMat.make_bubble()
	p.draw_pass_1 = bm
	_world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func spawn_predation_flash(pos: Vector3) -> void:
	# A short-lived bright burst at the bite site. Reads as the visceral
	# "kill landed" beat — distinct from the steady waste-spawning that
	# happens after. Just an expanding warm-white sphere with a fade
	# tween; cheap enough we never cap the spawn rate (predation events
	# are sparse to begin with, throttled by sim food chains).
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sm.radial_segments = 6
	sm.rings = 4
	# Translucent additive-feel material — high luma so the bloom path
	# in palette_quantize lifts it toward warm white at any time of day.
	# Duplicating so the tween doesn't bleed into other call sites
	# sharing the cached material.
	var mat: ShaderMaterial = VoxelMat.make_translucent(Color(1.0, 0.85, 0.55, 0.85)).duplicate()
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	_world.add_child(mi)
	const FLASH_DURATION: float = 0.28
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.6, FLASH_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/albedo",
		Color(1.0, 0.85, 0.55, 0.0), FLASH_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func spawn_burst_ripple_proxy(pos: Vector3) -> void:
	if _active_ripples >= MAX_RIPPLES:
		return
	_active_ripples += 1
	if _world.has_method("spawn_burst_ripple"):
		_world.spawn_burst_ripple(pos)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		_active_ripples = maxi(0, _active_ripples - 1))


func sync_aquatic_uniforms(intensity: float, light_color: Color, water_y: float,
		day_offset: float, shimmer: float) -> void:
	var boost: float = 1.0 + (0.35 if screenshot_boost_active() else 0.0)
	VoxelMat.update_aquatic_uniforms(
		intensity * boost, light_color, water_y, day_offset, shimmer * boost)


func sync_foliage_uniforms(canopy_shade: float, water_y: float, daylight: float) -> void:
	VoxelMat.update_foliage_uniforms(canopy_shade, water_y, daylight)


func _build_ambient_emitters() -> void:
	if _world == null:
		return
	var wh: float = float(_world.WATER_HEIGHT)
	var sd: float = float(_world.SUBSTRATE_DEPTH)
	var col_h: float = maxf(0.5, wh - sd)
	var hw: float = float(_world.TANK_HALF_W) - 0.6
	var hd: float = float(_world.TANK_HALF_D) - 0.6

	_haze_particles = _make_box_emitter("EvaporationHaze", 6, 3.5,
		Vector3(0, wh - 0.02, 0), Vector3(hw, 0.04, hd),
		Vector3(0, 0.08, 0), 0.0, 0.05, Color(0.85, 0.92, 0.98, 0.08))
	_debris_particles = _make_box_emitter("SurfaceDebris", 8, 5.0,
		Vector3(0, wh - 0.08, 0), Vector3(hw, 0.06, hd),
		Vector3(0, 0, 0), 0.02, 0.06, Color(0.78, 0.82, 0.72, 0.25))
	_rain_particles = _make_rain_emitter()
	_condensation_particles = _make_condensation_emitter()
	_gas_escape_particles = _make_gas_emitter(col_h)
	_current_ribbons = _make_current_ribbons(wh, hw, hd)


func _make_box_emitter(n: String, amount: int, life: float, pos: Vector3, ext: Vector3,
		dir: Vector3, vmin: float, vmax: float, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = life
	p.preprocess = life * 0.5
	p.local_coords = false
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.ZERO
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3.ZERO
	pm.spread = 12.0
	if _world.has_method("configure_meniscus_emission"):
		_world.configure_meniscus_emission(pm, ext.y)
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = ext
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.06)
	bm.material = VoxelMat.make(col)
	p.draw_pass_1 = bm
	_world.add_child(p)
	return p


func _make_rain_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RainOnGlass"
	p.amount = 1
	p.emitting = false
	p.lifetime = 0.8
	p.local_coords = false
	p.position = Vector3(0, float(_world.TANK_HEIGHT) * 0.55, float(_world.TANK_HALF_D) + 0.2)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0.2)
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -2.0, 0)
	pm.spread = 4.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(_world.TANK_HALF_W), 0.5, 0.05)
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.18, 0.02)
	bm.material = VoxelMat.make(Color(0.65, 0.75, 0.88, 0.35))
	p.draw_pass_1 = bm
	_world.add_child(p)
	return p


func _make_condensation_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Condensation"
	p.amount = 10
	p.lifetime = 12.0
	p.preprocess = 6.0
	p.local_coords = false
	p.position = Vector3(0, float(_world.WATER_HEIGHT) * 0.7, float(_world.TANK_HALF_D) - 0.05)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.05, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.02
	pm.gravity = Vector3.ZERO
	pm.spread = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(_world.TANK_HALF_W) - 0.5, 1.2, 0.02)
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.018
	bm.height = 0.036
	bm.radial_segments = 4
	bm.rings = 2
	bm.material = VoxelMat.make(Color(0.82, 0.9, 0.96, 0.3))
	p.draw_pass_1 = bm
	_world.add_child(p)
	return p


func _make_gas_emitter(col_h: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "GasEscape"
	p.amount = 3
	p.lifetime = 2.5
	p.preprocess = 1.0
	p.local_coords = false
	p.position = Vector3(0, float(_world.SUBSTRATE_DEPTH) + col_h * 0.02 + 0.15, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0, 0.35, 0)
	pm.spread = 18.0
	if _world.has_method("configure_meniscus_emission"):
		_world.configure_meniscus_emission(pm, col_h * 0.015 + 0.05)
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(
			float(_world.TANK_HALF_W) * 0.6, 0.05, float(_world.TANK_HALF_D) * 0.6)
	p.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.025
	bm.height = 0.05
	bm.material = VoxelMat.make_bubble(Color(0.7, 0.82, 0.75, 0.25))
	p.draw_pass_1 = bm
	p.emitting = false
	_world.add_child(p)
	return p


func _make_current_ribbons(wh: float, hw: float, hd: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "CurrentRibbons"
	p.amount = 6
	p.lifetime = 2.8
	p.preprocess = 1.0
	p.local_coords = false
	var x_frac: float = 0.0
	if _cfg != null:
		x_frac = float(_cfg.aeration_x_frac)
	var ax: float = x_frac * (hw - 0.5)
	p.position = Vector3(ax, wh * 0.55, -hd * 0.4)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.1, 0.0, 1.0)
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.65
	pm.gravity = Vector3(0, 0, 0)
	pm.spread = 6.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.08, col_height_safe(wh), 0.08)
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.25, 0.55)
	bm.material = VoxelMat.make(Color(0.55, 0.72, 0.82, 0.12))
	p.draw_pass_1 = bm
	_world.add_child(p)
	return p


func col_height_safe(wh: float) -> float:
	return maxf(0.5, wh - float(_world.SUBSTRATE_DEPTH)) * 0.35


func _update_glass_cosmetics(sdt: float) -> void:
	if _glass_mat == null:
		return
	var bloom: float = 0.0
	var bio: float = 0.0
	if _world.get("biofilm_progress") != null:
		bio = float(_world.biofilm_progress)
	if _sim != null:
		bloom = float(_sim.get("bloom_intensity"))
	_glass_mat.set_shader_parameter("biofilm", clampf(bio * 0.85 + bloom * 0.25, 0.0, 0.7))
	var humidity: float = clampf(float(_world.get("tannins")) if _world.get("tannins") != null else 0.0, 0.0, 1.0)
	_glass_mat.set_shader_parameter("condensation", humidity * 0.55)
	if randf() < sdt * 0.002 and _glass_walls.size() > 0:
		_add_mineral_streak()


func _update_bubble_tints() -> void:
	var o2: float = 0.7
	var bloom: float = 0.0
	if _sim != null:
		o2 = float(_sim.get("dissolved_o2"))
		bloom = float(_sim.get("bloom_intensity"))
	var mat := VoxelMat.get_bubble_material()
	mat.set_shader_parameter("o2_tint", clampf((o2 - 0.5) / 0.7, 0.0, 1.0))
	var alpha: float = clampf(0.42 - bloom * 0.12, 0.22, 0.55)
	mat.set_shader_parameter("bubble_color", Color(
		lerpf(0.82, 0.68, bloom * 0.4),
		lerpf(0.92, 0.78, bloom * 0.3),
		lerpf(0.96, 0.82, bloom * 0.2),
		alpha))


func _maybe_gas_escape(sdt: float) -> void:
	_gas_escape_t -= sdt
	if _gas_escape_t > 0.0 or _gas_escape_particles == null:
		return
	if randf() > 0.004:
		return
	_gas_escape_t = randf_range(8.0, 22.0)
	_gas_escape_particles.emitting = true
	_gas_escape_particles.restart()
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(_gas_escape_particles):
			_gas_escape_particles.emitting = false)


func _maybe_filter_cavitation(sdt: float) -> void:
	if _sim == null or String(_sim.get("aeration_fixture")) != "filter":
		return
	_filter_cavitation_t -= sdt
	if _filter_cavitation_t > 0.0:
		return
	var flow: float = float(_sim.get("aeration_flow_rate"))
	if flow < 0.25 or randf() > 0.003 * flow:
		return
	_filter_cavitation_t = randf_range(4.0, 10.0)
	var intake: Vector3 = _sim.get("filter_intake_pos")
	if intake != Vector3.ZERO:
		spawn_snail_bubble(intake + Vector3(0, 0.12, 0))


func _maybe_rain_on_glass(sdt: float) -> void:
	if _rain_particles == null:
		return
	_rain_t -= sdt
	if _rain_t > 0.0:
		return
	if randf() > 0.0008:
		return
	_rain_t = randf_range(15.0, 40.0)
	_rain_particles.amount = 12
	_rain_particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(_rain_particles):
			_rain_particles.emitting = false
			_rain_particles.amount = 1)


func _maybe_glass_sparkle(sdt: float) -> void:
	if _glass_mat == null or _sim == null:
		return
	_sparkle_t -= sdt
	var dl: float = _sim.daylight() if _sim.has_method("daylight") else 1.0
	if dl < 0.35:
		_glass_mat.set_shader_parameter("sparkle", 0.0)
		return
	if _sparkle_t <= 0.0 and randf() < 0.02:
		_sparkle_t = 0.15
	_glass_mat.set_shader_parameter("sparkle", 1.0 if _sparkle_t > 0.0 else 0.0)


func _update_god_ray_occlusion() -> void:
	if _world.get("_god_ray_materials") == null:
		return
	var mats: Array = _world._god_ray_materials
	var occ: float = 0.0
	if _sim != null:
		occ = clampf(float(_sim.total_plant_biomass) / 400.0, 0.0, 0.55)
	for m in mats:
		if is_instance_valid(m):
			m.set_shader_parameter("occlusion", occ)


func _collect_glass_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_glass_walls.append(c)
		_collect_glass_meshes(c)


func _add_glass_rim_bevels(root: Node3D) -> void:
	if _world == null:
		return
	var th: float = float(_world.TANK_HEIGHT)
	var corners: Array = _world._tank_footprint_corners() if _world.has_method("_tank_footprint_corners") else []
	for c in corners:
		var p: Vector3 = c as Vector3
		var rim := MeshInstance3D.new()
		rim.mesh = VoxelMat.get_box(Vector3(0.14, 0.08, 0.14))
		rim.material_override = VoxelMat.make(Color8(200, 230, 245))
		rim.position = Vector3(p.x, th - 0.04, p.z)
		root.add_child(rim)


func _add_mineral_streak() -> void:
	if _glass_walls.is_empty() or _world == null or _glass_root == null:
		return
	var wall: MeshInstance3D = _glass_walls[randi() % _glass_walls.size()]
	var streak := MeshInstance3D.new()
	streak.mesh = VoxelMat.get_box(Vector3(0.04, randf_range(0.25, 0.65), 0.04))
	streak.material_override = VoxelMat.make(Color8(225, 230, 235))
	var gp: Vector3 = wall.global_position
	var wh: float = float(_world.WATER_HEIGHT)
	# Add to the tree FIRST so the global_position setter doesn't bail out
	# with the "!is_inside_tree()" warning (the setter needs a parent
	# transform to derive the local position).
	_glass_root.add_child(streak)
	streak.global_position = Vector3(
		gp.x + randf_range(-0.1, 0.1),
		randf_range(wh - 0.45, wh - 0.05),
		gp.z + randf_range(-0.1, 0.1))
	_mineral_streaks.append(streak)
	if _mineral_streaks.size() > 28:
		var old = _mineral_streaks.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _cleanup_slime() -> void:
	var i: int = _slime_marks.size() - 1
	while i >= 0:
		if not is_instance_valid(_slime_marks[i]):
			_slime_marks.remove_at(i)
		i -= 1
	while _slime_marks.size() > SLIME_CAP:
		_pop_slime_mark()


func sync_floater_shadows(floaters: Array, substrate_y: float) -> void:
	if _world == null:
		return
	var live: int = 0
	for f in floaters:
		if is_instance_valid(f):
			live += 1
	while _floater_shadows.size() > mini(live, FLOATER_SHADOW_CAP):
		var old = _floater_shadows.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	var idx: int = 0
	for f in floaters:
		if not is_instance_valid(f):
			continue
		if idx >= FLOATER_SHADOW_CAP:
			break
		var fn: Node3D = f as Node3D
		var mi: MeshInstance3D
		if idx < _floater_shadows.size() and is_instance_valid(_floater_shadows[idx]):
			mi = _floater_shadows[idx]
		else:
			mi = _make_floater_shadow()
			if idx < _floater_shadows.size():
				_floater_shadows[idx] = mi
			else:
				_floater_shadows.append(mi)
		mi.global_position = Vector3(fn.position.x, substrate_y + 0.03, fn.position.z)
		var shade: float = clampf(0.55 + fn.position.y * 0.02, 0.45, 0.75)
		mi.scale = Vector3(shade, 1.0, shade)
		idx += 1


func _sync_floater_shadows() -> void:
	if _world == null or _world.get("_floaters") == null:
		return
	sync_floater_shadows(_world._floaters, float(_world.SUBSTRATE_DEPTH))


func _make_floater_shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "FloaterShadow"
	mi.mesh = VoxelMat.get_box(Vector3(0.42, 0.03, 0.42))
	var mat: ShaderMaterial = VoxelMat.make(Color(0.08, 0.14, 0.20, 0.38))
	mi.material_override = mat
	_world.add_child(mi)
	return mi


func _compute_seasonal_hue() -> float:
	var month: int = Time.get_datetime_dict_from_system().get("month", 6)
	return sin((float(month) - 1.0) / 12.0 * TAU) * 0.08
