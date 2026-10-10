extends SceneTree

const Rig = preload("res://scripts/lighting_rig.gd")

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := TestSupport.Suite.new("light_sources")
	var cfg: Node = root.get_node("TankConfig")
	cfg.capture_mode = true
	cfg.reset_to_defaults()
	var world_script: GDScript = load("res://scripts/lighting_world_test_stub.gd")
	var w: Node3D = world_script.new()
	root.add_child(w)
	w._cfg_node = cfg
	w._build_light_fixture()
	t.check(w._light_fixture_spots.size() == 4, "default LED bar has four parallel sources")
	t.check(w._god_ray_materials.size() == 1, "LED bar has one continuous scattering curtain")
	var particle_amount: int = 0
	for child in w._light_fixture_root.get_children():
		if child is GPUParticles3D:
			particle_amount += child.amount
	t.equals(particle_amount, 48, "bar curtain uses 48 motes instead of four 32-mote emitters")
	var old_root: Node3D = w._light_fixture_root
	cfg.apply_lighting_preset("clip_spot_night")
	w._refresh_light_fixture_from_config()
	t.check(w._light_fixture_root != old_root, "preset replaces actual fixture geometry")
	t.check(old_root.get_parent() == null, "old fixture detaches before deferred free")
	t.check(w._light_fixture_spots.size() == 1, "clip spot contains one source")
	t.check(not w._light_fixture_spots[0].shadow_enabled, "unshaded rig avoids unused hardware shadow maps")
	var new_root: Node3D = w._light_fixture_root
	w._refresh_light_fixture_from_config()
	t.check(w._light_fixture_root == new_root, "unchanged settings never rebuild the lamp")
	w.set_light_placement(0.2, -0.1, 0.0, 0.0)
	w._refresh_light_fixture_from_config()
	t.check(w._light_fixture_root == new_root, "aim/position changes reuse geometry")
	t.check(w._light_fixture_spots.size() == 1, "drag cannot accumulate old spot references")
	cfg.global_intensity = 0.0
	cfg.room_darkness = 1.0
	cfg.tank_fixture_intensity = 0.5
	cfg.tank_fixture_color = Color.WHITE
	cfg.fixture_follow_day_cycle = false
	w._cache_plant_light(1.0, cfg)
	var target: Vector3 = w.light_aim_world() + Vector3.UP * 0.5
	t.check(w.irradiance_at(target) > 0.3, "plants receive actual aimed fixture")
	cfg.tank_lights_on = false
	w._cache_plant_light(1.0, cfg)
	t.approx(w.irradiance_at(target), 0.0, "daytime fixture toggle also removes plant exposure")
	cfg.tank_lights_on = true
	cfg.light_master_enabled = false
	w._cache_plant_light(1.0, cfg)
	t.approx(w.irradiance_at(target), 0.0, "master blackout reaches local biology")
	cfg.light_master_enabled = true
	cfg.fixture_follow_day_cycle = true
	w._cache_plant_light(0.0, cfg)
	t.approx(w.irradiance_at(target), 0.0, "automatic fixture gives plants a dark night")
	cfg.fixture_follow_day_cycle = false
	w._cache_plant_light(0.0, cfg)
	t.check(w.irradiance_at(target) > 0.3, "manual fixture illuminates night plants")
	cfg.light_volumetric = false
	w._sync_light_beam_visibility(false)
	var beams: int = 0
	for child in w._light_fixture_root.get_children():
		if not child.has_meta(w.BEAM_MOTES_META):
			continue
		beams += 1
		var motes: GPUParticles3D = child.get_meta(w.BEAM_MOTES_META)
		t.check(not child.visible and not motes.visible and not motes.emitting,
			"live beam switch removes shaft and particle light together")
	t.check(beams > 0, "probe exercises actual volumetric shaft")
	w._sync_light_beam_visibility(true)
	for child in w._light_fixture_root.get_children():
		if child.has_meta(w.BEAM_MOTES_META):
			t.check(child.visible, "existing shaft resumes without rebuilding")
	cfg.accent1_enabled = true
	cfg.accent2_enabled = true
	cfg.moonlight_enabled = true
	w._update_accent_lights(cfg, 1.0, true)
	t.check(w._moonlight.visible and w._accent1_light.visible and w._accent2_light.visible,
		"all optional sources activate")
	t.check(absf(w._accent1_light.position.x) < w.TANK_HALF_W \
		and absf(w._accent1_light.position.z) < w.TANK_HALF_D,
		"accents stay inside the current tank footprint")
	w._update_accent_lights(cfg, 1.0, false)
	t.check(not w._moonlight.visible and not w._accent1_light.visible and not w._accent2_light.visible,
		"master kills every optional source")
	w._glass_material_ref = ShaderMaterial.new()
	w._glass_material_ref.shader = load("res://shaders/glass.gdshader")
	cfg.light_caustics = false
	cfg.global_intensity = 0.5
	cfg.room_darkness = 0.0
	w._sync_glass_lighting(1.0, 0.5, 0.0, true)
	t.check(float(w._glass_material_ref.get_shader_parameter("reflection_strength")) > 0.1,
		"glass reflects useful light with caustics disabled")
	w._sync_glass_lighting(1.0, 0.5, 0.0, false)
	t.approx(float(w._glass_material_ref.get_shader_parameter("reflection_strength")), 0.0,
		"glass blackout still updates while caustics disabled")
	for slug: String in cfg.LIGHTING_PRESETS:
		cfg.apply_lighting_preset(slug)
		w._refresh_light_fixture_from_config()
		t.check(w._light_fixture_spots.size() == (4 if cfg.light_fixture == "bar" else 1),
			"%s live preset matches actual fixture" % slug)
		await process_frame
	cfg.room_darkness = 0.9
	cfg.beam_strength = 2.0
	cfg.backlight_enabled = true
	cfg.backlight_intensity = 1.0
	cfg.reset_to_defaults()
	t.approx(cfg.room_darkness, 0.0, "reset clears dark room")
	t.approx(cfg.beam_strength, 1.0, "reset clears shaft gain")
	t.check(not cfg.backlight_enabled and cfg.backlight_intensity == 0.0, "reset clears rear fill")
	t.check(cfg.fixture_follow_day_cycle, "new tanks restore automatic photoperiod")
	t.approx(Rig.beam_end_radius(8.0, 45.0), 8.0, "45degree angular radius has equal drop and spread")
	var linear: Vector3 = Rig.linear_light_rgb(Color(0.5, 0.5, 0.5))
	t.approx(linear.x, 0.214041, "color-picker mid-grey packs linear light", 0.0001)
	var falloff := Vector4(4.0, 0.1, 2.0, 0.0)
	t.approx(Rig.distance_falloff(8.0, falloff) / Rig.distance_falloff(4.0, falloff),
		0.25, "point lamp flux follows inverse-square falloff", 0.001)
	t.in_range(Rig.distance_falloff(0.0, falloff), 0.0, 1.5, "finite emitter avoids singularity")
	w.queue_free()
	await process_frame
	quit(t.finish())
