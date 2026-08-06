# Window parallax, weather, and room lighting bleed — extracted from world.gd.
class_name WorldRoomBuilder
extends RefCounted

const SKY_W: float = 7.0
const SKY_H: float = 5.0
# Silhouettes stay in the lower band of the window opening so they read
# through the frame, not as giant voxels from oblique camera angles.
const SILHOUETTE_BASE_Y: float = -SKY_H * 0.44
const SILHOUETTE_MAX_H: float = 0.72


static func build_window(parent: Node3D, wall_z: float, desk_y: float, preset: Dictionary,
		frame_mat: Material) -> Dictionary:
	var sky_y: float = desk_y + 4.5
	var backdrop: String = String(preset.get("window_backdrop", "clouds"))
	var weather: String = String(preset.get("window_weather", "clear"))
	var state: Dictionary = {
		"sky_y": sky_y,
		"wall_z": wall_z,
		"backdrop": backdrop,
		"weather": weather,
		"sky_mat": null,
		"stars": [],
		"parallax_layers": [],
		"city_lights": [],
		"moon": null,
		"rain": null,
		"weather_dim": 1.0,
	}

	_build_sky_plane(parent, wall_z, sky_y, preset, state)
	_build_backdrop_layers(parent, wall_z, sky_y, backdrop, state)
	_build_stars(parent, wall_z, sky_y, state)
	if backdrop == "city":
		_build_city_lights(parent, wall_z, sky_y, state)
	_build_moon(parent, wall_z, sky_y, state)
	if weather == "rain":
		state["rain"] = _build_rain(parent, wall_z, sky_y)
	_build_window_frame(parent, wall_z, sky_y, frame_mat)
	return state


static func _silhouette_mat(color: Color) -> ShaderMaterial:
	# Flat unlit cutouts — must not use make_room (haze makes them blow out).
	return VoxelMat.make(color)


static func _add_skyline_pillars(layer: Node3D, wall_z: float, sky_y: float, z_back: float,
		color: Color, count: int, height_scale: float, rng: RandomNumberGenerator) -> void:
	var mat := _silhouette_mat(color)
	var base_y: float = sky_y + SILHOUETTE_BASE_Y
	for pi in count:
		var t: float = float(pi) / float(maxi(1, count - 1))
		var px: float = lerpf(-SKY_W * 0.44, SKY_W * 0.44, t)
		px += sin(float(pi) * 1.9) * 0.12
		var h: float = rng.randf_range(0.18, SILHOUETTE_MAX_H) * height_scale
		var w: float = rng.randf_range(0.28, 0.48)
		var pillar := MeshInstance3D.new()
		pillar.mesh = VoxelMat.get_box(Vector3(w, h, 0.05))
		pillar.material_override = mat
		pillar.position = Vector3(px, base_y + h * 0.5, wall_z - z_back)
		layer.add_child(pillar)


static func _build_sky_plane(parent: Node3D, wall_z: float, sky_y: float,
		preset: Dictionary, state: Dictionary) -> void:
	var sky := MeshInstance3D.new()
	sky.name = "WindowSky"
	sky.mesh = VoxelMat.get_box(Vector3(SKY_W, SKY_H, 0.08))
	var sky_rgb: Array = preset.get("light_color", [255, 235, 200])
	var sky_col := Color8(sky_rgb[0], sky_rgb[1], sky_rgb[2])
	var sky_mat: ShaderMaterial = VoxelMat.make(sky_col).duplicate()
	sky_mat.set_shader_parameter("albedo", sky_col.lightened(0.08))
	sky.material_override = sky_mat
	sky.position = Vector3(0.0, sky_y, wall_z - 0.22)
	parent.add_child(sky)
	# Window value gradient — brighter at the top, bloom shoulder (#21–22).
	var sky_top := MeshInstance3D.new()
	sky_top.name = "WindowSkyTop"
	sky_top.mesh = VoxelMat.get_box(Vector3(SKY_W * 0.92, SKY_H * 0.35, 0.06))
	sky_top.material_override = VoxelMat.make(sky_col.lightened(0.22))
	sky_top.position = Vector3(0.0, sky_y + SKY_H * 0.28, wall_z - 0.18)
	parent.add_child(sky_top)
	state["sky_mat"] = sky_mat


static func _build_stars(parent: Node3D, wall_z: float, sky_y: float, state: Dictionary) -> void:
	var star_positions := [
		Vector3(-2.2, sky_y + 1.6, wall_z - 0.16),
		Vector3(-1.1, sky_y + 0.8, wall_z - 0.16),
		Vector3(0.4, sky_y + 2.0, wall_z - 0.16),
		Vector3(1.8, sky_y + 1.2, wall_z - 0.16),
		Vector3(2.5, sky_y + 0.4, wall_z - 0.16),
		Vector3(-0.6, sky_y + 1.3, wall_z - 0.16),
		Vector3(1.0, sky_y + 0.2, wall_z - 0.16),
	]
	var star_mat := VoxelMat.make(Color8(255, 255, 240))
	var stars: Array = []
	for pos in star_positions:
		var star := MeshInstance3D.new()
		star.mesh = VoxelMat.get_box(Vector3(0.06, 0.06, 0.06))
		star.material_override = star_mat
		star.position = pos
		star.visible = false
		parent.add_child(star)
		stars.append(star)
	state["stars"] = stars


static func _build_backdrop_layers(parent: Node3D, wall_z: float, sky_y: float,
		backdrop: String, state: Dictionary) -> void:
	var layers: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(backdrop) & 0x7fffffff
	match backdrop:
		"forest":
			var specs: Array = [
				{"z": 0.50, "col": Color8(12, 22, 16), "scale": 1.0, "drift": 0.010},
				{"z": 0.44, "col": Color8(18, 30, 22), "scale": 0.82, "drift": 0.016},
				{"z": 0.38, "col": Color8(24, 38, 28), "scale": 0.65, "drift": 0.022},
			]
			for i in specs.size():
				var spec: Dictionary = specs[i]
				var layer := Node3D.new()
				layer.name = "ParallaxForest%d" % i
				_add_skyline_pillars(layer, wall_z, sky_y, spec["z"], spec["col"],
					10, float(spec["scale"]), rng)
				layer.set_meta("drift_scale", float(spec["drift"]))
				parent.add_child(layer)
				layers.append(layer)
		"clouds":
			var layer := Node3D.new()
			layer.name = "ParallaxClouds"
			var cloud_mat := _silhouette_mat(Color8(248, 250, 252))
			var specs := [
				Vector2(-1.6, 0.9), Vector2(0.5, 1.2), Vector2(2.0, 0.5), Vector2(-0.2, 1.6),
			]
			for spec in specs:
				var puff := MeshInstance3D.new()
				var pw: float = rng.randf_range(0.8, 1.4)
				puff.mesh = VoxelMat.get_box(Vector3(pw, pw * 0.22, 0.05))
				puff.material_override = cloud_mat
				puff.position = Vector3(spec.x, sky_y + spec.y, wall_z - 0.36)
				layer.add_child(puff)
			layer.set_meta("drift_scale", 0.018)
			parent.add_child(layer)
			layers.append(layer)
		"city":
			var layer := Node3D.new()
			layer.name = "ParallaxCitySilhouette"
			var roof_mat := _silhouette_mat(Color8(22, 24, 32))
			for bi in 9:
				var bx: float = lerpf(-SKY_W * 0.42, SKY_W * 0.42, float(bi) / 8.0)
				var bh: float = rng.randf_range(0.22, 0.58)
				var block := MeshInstance3D.new()
				block.mesh = VoxelMat.get_box(Vector3(rng.randf_range(0.4, 0.7), bh, 0.05))
				block.material_override = roof_mat
				block.position = Vector3(bx, sky_y + SILHOUETTE_BASE_Y + bh * 0.5, wall_z - 0.42)
				layer.add_child(block)
			layer.set_meta("drift_scale", 0.008)
			parent.add_child(layer)
			layers.append(layer)
	state["parallax_layers"] = layers


static func _build_city_lights(parent: Node3D, wall_z: float, sky_y: float,
		state: Dictionary) -> void:
	var lights: Array = []
	var warm := VoxelMat.make(Color8(255, 200, 120))
	for i in 16:
		var dot := MeshInstance3D.new()
		dot.mesh = VoxelMat.get_box(Vector3(0.09, 0.12, 0.05))
		dot.material_override = warm
		dot.position = Vector3(
			randf_range(-SKY_W * 0.38, SKY_W * 0.38),
			sky_y + randf_range(-SKY_H * 0.15, SKY_H * 0.32),
			wall_z - 0.20)
		dot.visible = false
		dot.set_meta("phase", randf() * TAU)
		parent.add_child(dot)
		lights.append(dot)
	state["city_lights"] = lights


static func _build_moon(parent: Node3D, wall_z: float, sky_y: float, state: Dictionary) -> void:
	var moon := MeshInstance3D.new()
	moon.name = "WindowMoon"
	moon.mesh = VoxelMat.get_box(Vector3(0.45, 0.45, 0.05))
	moon.material_override = VoxelMat.make(Color8(240, 238, 220))
	moon.position = Vector3(SKY_W * 0.26, sky_y + SKY_H * 0.18, wall_z - 0.24)
	moon.visible = false
	parent.add_child(moon)
	state["moon"] = moon


static func _build_rain(parent: Node3D, wall_z: float, sky_y: float) -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "WindowRain"
	rain.amount = 36
	rain.lifetime = 0.75
	rain.preprocess = rain.lifetime
	rain.randomness = 0.35
	rain.local_coords = true
	rain.position = Vector3(0.0, sky_y + SKY_H * 0.42, wall_z - 0.06)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SKY_W * 0.46, 0.06, 0.08)
	pm.direction = Vector3(0.04, -1.0, 0.0)
	pm.spread = 6.0
	pm.initial_velocity_min = 2.2
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0.0, -1.0, 0.0)
	pm.scale_min = 0.015
	pm.scale_max = 0.03
	rain.process_material = pm
	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.14, 0.015)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.75, 0.82, 0.92, 0.35)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = sm
	rain.draw_pass_1 = streak
	rain.emitting = false
	parent.add_child(rain)
	return rain


static func _build_window_frame(parent: Node3D, wall_z: float, sky_y: float,
		frame_mat: Material) -> void:
	var frame_thickness := 0.25
	var frame_depth := 0.5
	var f_left := MeshInstance3D.new()
	f_left.mesh = VoxelMat.get_box(Vector3(frame_thickness, SKY_H + frame_thickness, frame_depth))
	f_left.material_override = frame_mat
	f_left.position = Vector3(-SKY_W * 0.5 - frame_thickness * 0.5, sky_y, wall_z)
	parent.add_child(f_left)
	var f_right := MeshInstance3D.new()
	f_right.mesh = VoxelMat.get_box(Vector3(frame_thickness, SKY_H + frame_thickness, frame_depth))
	f_right.material_override = frame_mat
	f_right.position = Vector3(SKY_W * 0.5 + frame_thickness * 0.5, sky_y, wall_z)
	parent.add_child(f_right)
	var f_top := MeshInstance3D.new()
	f_top.mesh = VoxelMat.get_box(Vector3(SKY_W + frame_thickness * 2.0, frame_thickness, frame_depth))
	f_top.material_override = frame_mat
	f_top.position = Vector3(0.0, sky_y + SKY_H * 0.5 + frame_thickness * 0.5, wall_z)
	parent.add_child(f_top)
	var f_bottom := MeshInstance3D.new()
	f_bottom.mesh = VoxelMat.get_box(Vector3(SKY_W + frame_thickness * 2.0, frame_thickness * 1.5, frame_depth * 1.2))
	f_bottom.material_override = frame_mat
	f_bottom.position = Vector3(0.0, sky_y - SKY_H * 0.5 - frame_thickness * 0.75, wall_z + frame_depth * 0.05)
	parent.add_child(f_bottom)
	var m_vert := MeshInstance3D.new()
	m_vert.mesh = VoxelMat.get_box(Vector3(0.12, SKY_H, frame_depth * 0.7))
	m_vert.material_override = frame_mat
	m_vert.position = Vector3(0.0, sky_y, wall_z + 0.05)
	parent.add_child(m_vert)
	var m_horiz := MeshInstance3D.new()
	m_horiz.mesh = VoxelMat.get_box(Vector3(SKY_W, 0.12, frame_depth * 0.7))
	m_horiz.material_override = frame_mat
	m_horiz.position = Vector3(0.0, sky_y, wall_z + 0.05)
	parent.add_child(m_horiz)


static func tick_window(state: Dictionary, ln: Dictionary, room_time: float,
		sky_col: Color) -> Color:
	if state.is_empty():
		return sky_col
	var dl: float = ln["dl"]
	var dp: float = ln["dp"]
	var weather: String = String(state.get("weather", "clear"))
	var out: Color = sky_col
	if weather == "overcast":
		out = out.lerp(Color8(168, 174, 182), 0.28)
		state["weather_dim"] = 0.82
	elif weather == "rain":
		out = out.lerp(Color8(140, 148, 162), 0.38)
		state["weather_dim"] = 0.68
	else:
		state["weather_dim"] = 1.0

	var sky_mat = state.get("sky_mat")
	if sky_mat != null:
		sky_mat.set_shader_parameter("albedo", out)

	var show_stars: bool = dl < 0.30
	for star in state.get("stars", []):
		if is_instance_valid(star):
			star.visible = show_stars
			if show_stars:
				var sp: float = star.position.x * 12.3 + star.position.y * 7.9
				var sc: float = 0.65 + 0.35 * sin(room_time * 3.5 + sp)
				star.scale = Vector3(sc, sc, sc)

	for layer in state.get("parallax_layers", []):
		if not is_instance_valid(layer):
			continue
		var drift: float = float(layer.get_meta("drift_scale", 0.012))
		layer.position.x = sin(room_time * 0.18 + drift * 40.0) * drift * 3.5

	var moon = state.get("moon")
	if moon != null and is_instance_valid(moon):
		moon.visible = dl < 0.32
		if moon.visible:
			moon.position.x = sin(dp * TAU) * SKY_W * 0.20

	var show_city: bool = dl < 0.38
	for dot in state.get("city_lights", []):
		if not is_instance_valid(dot):
			continue
		dot.visible = show_city
		if show_city:
			var ph: float = float(dot.get_meta("phase", 0.0))
			var tw: float = 0.55 + 0.45 * sin(room_time * 2.8 + ph)
			dot.scale = Vector3(tw, tw * 1.25, tw)

	var rain = state.get("rain")
	if rain != null and is_instance_valid(rain):
		var want_rain: bool = weather == "rain" and dl > 0.08
		rain.emitting = want_rain
		rain.visible = want_rain

	return out


static func tick_room_lights(spill: OmniLight3D, wall_bounce: OmniLight3D,
		side_light: OmniLight3D, desk_rim: SpotLight3D, window_glow: OmniLight3D,
		ln: Dictionary, fixture_color: Color, fixture_energy: float,
		tank_lights_on: bool, desk_y: float, haze_base: Color) -> void:
	var dl: float = ln["dl"]
	var deep_night: float = ln["deep_night"]
	var sunset: float = ln["sunset_hour"]
	var night_on: float = deep_night * (1.0 if tank_lights_on else 0.12)

	if spill != null and is_instance_valid(spill):
		var day_spill: float = 0.28 + dl * 0.32
		var night_spill: float = fixture_energy * 3.4
		var spill_e: float = lerpf(day_spill, night_spill, night_on)
		spill.light_energy = spill_e
		var day_col: Color = Color(1.0, 0.96, 0.88)
		var night_col: Color = fixture_color.lerp(Color(0.82, 0.90, 1.0), 0.12)
		spill.light_color = day_col.lerp(night_col, night_on)
		spill.position.y = desk_y + 0.08 + night_on * 0.55

	if wall_bounce != null and is_instance_valid(wall_bounce):
		var bounce_day: float = 0.14 + dl * 0.16 + sunset * 0.22
		var bounce_night: float = fixture_energy * 2.8 * night_on
		wall_bounce.light_energy = bounce_day + bounce_night
		wall_bounce.light_color = fixture_color.lerp(Color(1.0, 0.88, 0.72), 1.0 - night_on * 0.72)

	if side_light != null and is_instance_valid(side_light):
		# Dimmer side fill — room must stay below tank mid-water (#18, #27).
		var side_e: float = 0.06 + dl * 0.08 + sunset * 0.08
		side_light.light_energy = side_e * lerpf(1.0, 0.10, deep_night)

	if desk_rim != null and is_instance_valid(desk_rim):
		desk_rim.light_color = fixture_color.lerp(Color(1.0, 0.95, 0.88), 0.25)
		var rim_day: float = 0.04 + dl * 0.06
		var rim_night: float = fixture_energy * 1.9 * night_on
		desk_rim.light_energy = lerpf(rim_day, rim_night, night_on)

	if window_glow != null and is_instance_valid(window_glow):
		var moon_rim: float = clampf((0.24 - dl) / 0.24, 0.0, 1.0) * deep_night
		window_glow.light_color = Color(0.58, 0.70, 0.94).lerp(
			fixture_color, night_on * 0.28)
		window_glow.light_energy = fixture_energy * 0.55 * night_on + moon_rim * 0.48

	# Subtle haze tint toward fixture — keep it gentle so walls don't flood green.
	var haze_day: Color = haze_base
	var haze_night: Color = haze_base.lerp(fixture_color, 0.38)
	var haze_mix: float = clampf(night_on * 0.42, 0.0, 0.42)
	VoxelMat.update_room_haze(haze_day.lerp(haze_night, haze_mix))
