# Main scene controller.
#
# Responsibilities:
#   - Bind the SubViewport's render output to the Display TextureRect.
#   - DRIVE THE ORBIT CAMERA. The Camera3D lives inside a SubViewport that has
#     no SubViewportContainer above it, which means input events and mouse
#     position queries inside the SubViewport are unreliable. So we do all
#     mouse + keyboard handling here at the root (where input absolutely
#     works) and just update the Camera3D's transform directly.
#   - Show a small debug HUD with live input state so we can diagnose what's
#     happening when the camera doesn't respond.

extends Node


@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display
@onready var camera: Camera3D = $SubViewport/World/Camera3D
@onready var hud: Label = $DebugHUD
@onready var world: Node3D = $SubViewport/World

# Cached SimDriver ref for time_scale + seed + day_phase queries.
var _sim: Node = null
# Last-known ecosystem stats (updated via SimDriver.stats_changed signal).
var _stats: Dictionary = {}
# Edge-detect for key triggers.
var _key_was_pressed: Dictionary = {}

# Orbit state - default angle is the "feels nice" view the user landed on
# (drag to refine, F to reset back to this).
const DEFAULT_TARGET := Vector3(0, 3.0, 0)
const DEFAULT_RADIUS := 14.0
const DEFAULT_YAW := -0.35
const DEFAULT_PITCH := 0.30

var target: Vector3 = DEFAULT_TARGET
var radius: float = DEFAULT_RADIUS
var yaw: float = DEFAULT_YAW
var pitch: float = DEFAULT_PITCH

const SENSITIVITY: float = 0.006
const ZOOM_FACTOR: float = 1.12
const MIN_RADIUS: float = 3.0
const MAX_RADIUS: float = 40.0
const MIN_PITCH: float = -1.45
const MAX_PITCH: float = 1.45
const PAN_SPEED: float = 6.0
const AUTO_ORBIT_SPEED: float = 0.08

var _orbiting: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_start: Vector2 = Vector2.ZERO  # to distinguish click from drag
var _drag_total: float = 0.0
var _auto_orbit: bool = false
var _space_was_pressed: bool = false
# Follow-cam: when set, camera target tracks this Node3D.
var _follow_target: Node3D = null

# Aquascape mode: when active, the sim is paused and left-click drops a
# hardscape voxel (stone) at the substrate level under the cursor. Shift+
# click drops driftwood. Backspace removes the most-recently placed.
var _aquascape_mode: bool = false
var _aquascape_placed: Array[Node3D] = []
var _aquascape_preview: MeshInstance3D = null
var _aquascape_saved_time_scale: float = 1.0


func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	_apply_camera()
	# Subscribe to SimDriver stats - they emit at ~1Hz with the ecosystem snapshot.
	await get_tree().process_frame
	_sim = world.get_node_or_null("SimDriver")
	if _sim != null and _sim.has_signal("stats_changed"):
		_sim.connect("stats_changed", _on_stats_changed)


func _process(dt: float) -> void:
	# Mouse position: use the WINDOW's mouse position (not the SubViewport's),
	# since that's where the OS cursor actually lives. get_window() returns
	# this scene's OS window.
	var mouse_now: Vector2 = get_window().get_mouse_position()
	var any_btn: bool = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)

	if any_btn and not _orbiting:
		_orbiting = true
		_last_mouse = mouse_now
		_drag_start = mouse_now
		_drag_total = 0.0
	elif not any_btn and _orbiting:
		_orbiting = false
		# If total drag distance was small, treat as a click. In aquascape
		# mode, place a hardscape voxel at the cursor; otherwise try
		# follow-cam on the creature under the cursor.
		if _drag_total < 5.0:
			if _aquascape_mode:
				_aquascape_place(mouse_now)
			else:
				_try_follow_click(mouse_now)

	if _orbiting:
		var delta: Vector2 = mouse_now - _last_mouse
		_last_mouse = mouse_now
		_drag_total += delta.length()
		if delta.length_squared() > 0.0:
			yaw -= delta.x * SENSITIVITY
			pitch -= delta.y * SENSITIVITY
			pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
			_apply_camera()

	# Follow-cam: smoothly track the followed creature.
	if _follow_target != null:
		if not is_instance_valid(_follow_target):
			_follow_target = null
		else:
			target = target.lerp(_follow_target.global_position, clampf(dt * 3.0, 0.0, 1.0))
			_apply_camera()

	# WASD pan target along view direction.
	var fwd: Vector3 = (target - camera.global_position)
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		fwd = fwd.normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		var step: float = PAN_SPEED * dt
		var moved: bool = false
		if Input.is_key_pressed(KEY_W): target += fwd * step; moved = true
		if Input.is_key_pressed(KEY_S): target -= fwd * step; moved = true
		if Input.is_key_pressed(KEY_D): target += right * step; moved = true
		if Input.is_key_pressed(KEY_A): target -= right * step; moved = true
		if Input.is_key_pressed(KEY_E): target.y += step; moved = true
		if Input.is_key_pressed(KEY_Q): target.y -= step; moved = true
		if Input.is_key_pressed(KEY_F):
			target = DEFAULT_TARGET
			radius = DEFAULT_RADIUS
			yaw = DEFAULT_YAW
			pitch = DEFAULT_PITCH
			moved = true
		if moved:
			_apply_camera()

	# Space toggles auto-orbit.
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	if space_now and not _space_was_pressed:
		_auto_orbit = not _auto_orbit
	_space_was_pressed = space_now
	if _auto_orbit:
		yaw += AUTO_ORBIT_SPEED * dt
		_apply_camera()

	# Edge-triggered shortcuts: P pause toggle, 1/2/3 time-scale, F12 photo,
	# ESC clears follow-cam.
	_handle_shortcut(KEY_P, _toggle_pause)
	_handle_shortcut(KEY_1, func(): _set_time_scale(1.0))
	_handle_shortcut(KEY_2, func(): _set_time_scale(4.0))
	_handle_shortcut(KEY_3, func(): _set_time_scale(16.0))
	_handle_shortcut(KEY_F12, _take_photo)
	_handle_shortcut(KEY_ESCAPE, _clear_follow)
	_handle_shortcut(KEY_T, _toggle_timelapse)
	_handle_shortcut(KEY_B, _toggle_aquascape)
	_handle_shortcut(KEY_BACKSPACE, _aquascape_undo)
	_handle_shortcut(KEY_DELETE, _aquascape_undo)

	# Aquascape preview voxel: shown at the substrate projection of the
	# current mouse position, ONLY when in aquascape mode.
	if _aquascape_mode:
		_update_aquascape_preview(mouse_now)

	# Timelapse: dump a frame every TIMELAPSE_INTERVAL real seconds.
	if _timelapse_active:
		_timelapse_accum += dt
		if _timelapse_accum >= TIMELAPSE_INTERVAL:
			_timelapse_accum = 0.0
			var img: Image = sub_viewport.get_texture().get_image()
			img.save_png("%s/frame_%05d.png" % [_timelapse_dir, _timelapse_index])
			_timelapse_index += 1

	# Keep header in sync with time-scale + day phase live, not just at 1Hz.
	_render_header()


# ---- Time controls + photo mode ----

func _handle_shortcut(key: int, action: Callable) -> void:
	var pressed: bool = Input.is_key_pressed(key)
	var was: bool = _key_was_pressed.get(key, false)
	if pressed and not was:
		action.call()
	_key_was_pressed[key] = pressed


var _saved_time_scale: float = 1.0

func _toggle_pause() -> void:
	if _sim == null:
		return
	if float(_sim.time_scale) > 0.0:
		_saved_time_scale = float(_sim.time_scale)
		_sim.time_scale = 0.0
	else:
		_sim.time_scale = _saved_time_scale


func _set_time_scale(s: float) -> void:
	if _sim == null:
		return
	_sim.time_scale = s
	_saved_time_scale = s


func _take_photo() -> void:
	var img: Image = sub_viewport.get_texture().get_image()
	# Save into the user's app-data dir under ./captures
	var dir: String = OS.get_user_data_dir() + "/captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = dir + "/vivarium_" + ts + ".png"
	img.save_png(path)
	print("[vivarium] photo saved: ", path)


# ---- Timelapse mode ----
# Press T to start recording. Auto-dumps a frame every 0.5 real seconds into
# captures/timelapse_<timestamp>/. Press T again to stop. The user assembles
# the PNG sequence into a GIF/MP4 via their favorite tool.
var _timelapse_active: bool = false
var _timelapse_dir: String = ""
var _timelapse_index: int = 0
var _timelapse_accum: float = 0.0
const TIMELAPSE_INTERVAL: float = 0.5


func _toggle_timelapse() -> void:
	if _timelapse_active:
		_timelapse_active = false
		print("[vivarium] timelapse stopped: ", _timelapse_index, " frames in ", _timelapse_dir)
	else:
		var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		_timelapse_dir = OS.get_user_data_dir() + "/captures/timelapse_" + ts
		DirAccess.make_dir_recursive_absolute(_timelapse_dir)
		_timelapse_index = 0
		_timelapse_accum = 0.0
		_timelapse_active = true
		print("[vivarium] timelapse started: ", _timelapse_dir)


# ---- Follow-cam ----

func _clear_follow() -> void:
	_follow_target = null


func _try_follow_click(screen_pos: Vector2) -> void:
	# Project a ray from the camera through the click point, find the closest
	# Fish/Shrimp within ~0.5 unit perpendicular distance, lock the cam target
	# onto it.
	if camera == null:
		return
	# Convert window-space mouse to SubViewport-space, since the camera is
	# inside the SubViewport.
	var win_size: Vector2 = get_window().size
	var sv_size: Vector2 = Vector2(sub_viewport.size)
	var sv_pos: Vector2 = screen_pos * (sv_size / win_size)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	# Find the closest Fish or Shrimp to the ray within reach.
	var best: Node3D = null
	var best_perp: float = 0.7
	var creatures: Array = []
	if _sim != null:
		for f in _sim.fish:
			if is_instance_valid(f): creatures.append(f)
		for s in _sim.shrimp:
			if is_instance_valid(s): creatures.append(s)
	for c in creatures:
		var n: Node3D = c
		var to_n: Vector3 = n.global_position - origin
		var t: float = to_n.dot(dir)
		if t < 0.0: continue  # behind camera
		var closest: Vector3 = origin + dir * t
		var perp: float = closest.distance_to(n.global_position)
		if perp < best_perp:
			best_perp = perp
			best = n
	if best != null:
		_follow_target = best
		print("[vivarium] following ", best.name)


# ---- Aquascape mode ----

func _toggle_aquascape() -> void:
	_aquascape_mode = not _aquascape_mode
	if _sim == null:
		return
	if _aquascape_mode:
		# Pause the sim and clear any follow target.
		_aquascape_saved_time_scale = float(_sim.time_scale)
		_sim.time_scale = 0.0
		_follow_target = null
		_ensure_aquascape_preview()
		print("[vivarium] aquascape ON. click to place stones, shift-click for wood, backspace undo, B exit.")
	else:
		_sim.time_scale = _aquascape_saved_time_scale
		if _aquascape_preview != null:
			_aquascape_preview.visible = false
		print("[vivarium] aquascape OFF (resumed at %gx)" % _aquascape_saved_time_scale)


func _ensure_aquascape_preview() -> void:
	if _aquascape_preview != null:
		_aquascape_preview.visible = true
		return
	# Build a small wireframe-like preview cube. We attach it to the World
	# node so its position is in world space.
	if world == null:
		return
	_aquascape_preview = MeshInstance3D.new()
	_aquascape_preview.name = "AquascapePreview"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 0.9)
	_aquascape_preview.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.4)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aquascape_preview.material_override = mat
	world.add_child(_aquascape_preview)


func _update_aquascape_preview(mouse_pos: Vector2) -> void:
	if _aquascape_preview == null or camera == null or world == null:
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	# Snap to a 0.5-unit grid on X/Z so placement is tidy.
	hit.x = floorf(hit.x / 0.5) * 0.5 + 0.25
	hit.z = floorf(hit.z / 0.5) * 0.5 + 0.25
	# Y just above substrate.
	hit.y = _substrate_top_y() + 0.45
	_aquascape_preview.global_position = hit


func _project_to_substrate(mouse_pos: Vector2) -> Vector3:
	# Project the cursor's ray onto the horizontal plane y = SUBSTRATE_TOP.
	if camera == null:
		return Vector3.ZERO
	var win_size: Vector2 = get_window().size
	var sv_size: Vector2 = Vector2(sub_viewport.size)
	var sv_pos: Vector2 = mouse_pos * (sv_size / win_size)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	var top_y: float = _substrate_top_y()
	if absf(dir.y) < 1e-4:
		return origin
	var t: float = (top_y - origin.y) / dir.y
	if t < 0.0:
		return origin
	return origin + dir * t


func _substrate_top_y() -> float:
	# World keeps SUBSTRATE_DEPTH publicly accessible.
	return float(world.get("SUBSTRATE_DEPTH")) if world != null else 1.6


func _aquascape_place(mouse_pos: Vector2) -> void:
	if world == null:
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	hit.x = floorf(hit.x / 0.5) * 0.5 + 0.25
	hit.z = floorf(hit.z / 0.5) * 0.5 + 0.25
	hit.y = _substrate_top_y() + 0.45
	# Shift-click = driftwood, plain click = stone.
	var is_driftwood: bool = Input.is_key_pressed(KEY_SHIFT)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 0.9)
	mi.mesh = bm
	var color: Color
	if is_driftwood:
		color = Color8(78, 52, 32)
	else:
		# Pick a stone shade for variety.
		var palette: Array[Color] = [
			Color8(85, 85, 96), Color8(75, 70, 78), Color8(105, 100, 92),
			Color8(60, 60, 70),
		]
		color = palette[randi() % palette.size()]
	# Use the same VoxelMat helper if it loads cleanly, otherwise inline mat.
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	if voxel_mat_script != null:
		mi.material_override = voxel_mat_script.make(color)
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		mi.material_override = sm
	mi.global_position = hit
	# Slight Y jitter so adjacent placements don't z-fight.
	mi.global_position.y += randf_range(-0.02, 0.02)
	world.add_child(mi)
	_aquascape_placed.append(mi)


func _aquascape_undo() -> void:
	if not _aquascape_mode:
		return
	while _aquascape_placed.size() > 0:
		var v: Node3D = _aquascape_placed.pop_back()
		if is_instance_valid(v):
			v.queue_free()
			return


# Scroll wheel comes through as button events, not as Input.is_pressed state.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				radius = maxf(MIN_RADIUS, radius / ZOOM_FACTOR)
				_apply_camera()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				radius = minf(MAX_RADIUS, radius * ZOOM_FACTOR)
				_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	var x := cos(pitch) * sin(yaw)
	var y := sin(pitch)
	var z := cos(pitch) * cos(yaw)
	camera.global_position = target + Vector3(x, y, z) * radius
	camera.look_at(target, Vector3.UP)


func _on_stats_changed(stats: Dictionary) -> void:
	_stats = stats
	_render_header()


func _update_hud(_mouse_pos: Vector2, _any_btn: bool) -> void:
	# Header re-rendered on stats_changed; nothing per-frame.
	pass


func _render_header() -> void:
	if hud == null:
		return
	# Single-line subtle header grouped by trophic role. Use middle-dots so
	# the line reads as a continuous strip rather than a list.
	#
	#   FAUNA  fish 22 (11/11) · shrimp 11 (8/3) · eggs 0
	#   FLORA  plants 89 · biomass 451
	#   DETRITUS  waste 0 · nutrients 6.4
	var fish_total: int = int(_stats.get("fish_total", 0))
	var fish_adults: int = int(_stats.get("fish_adults", 0))
	var fish_fry: int = int(_stats.get("fish_fry", 0))
	var shrimp_total: int = int(_stats.get("shrimp_total", 0))
	var shrimp_adults: int = int(_stats.get("shrimp_adults", 0))
	var shrimp_fry: int = int(_stats.get("shrimp_fry", 0))
	var eggs: int = int(_stats.get("eggs", 0))
	var plants: int = int(_stats.get("plants_alive", 0))
	var biomass: int = int(_stats.get("plant_total_biomass", 0))
	var waste: int = int(_stats.get("waste_particles", 0))
	var nutrients: float = float(_stats.get("substrate_nutrients_total", 0.0))

	var parts: Array[String] = []
	# Seed + clock state at the head of the line so they're glanceable.
	if _sim != null:
		var seed_str: String = "%08x" % int(_sim.tank_seed)
		var ts: float = float(_sim.time_scale)
		var clock: String
		if ts == 0.0:
			clock = "paused"
		elif is_equal_approx(ts, 1.0):
			clock = "1x"
		else:
			clock = "%gx" % ts
		var day: String = _day_label(float(_sim.day_phase))
		parts.append("seed %s · %s · %s" % [seed_str, clock, day])
	parts.append("fish %d (%d/%d)" % [fish_total, fish_adults, fish_fry])
	parts.append("shrimp %d (%d/%d)" % [shrimp_total, shrimp_adults, shrimp_fry])
	parts.append("eggs %d" % eggs)
	parts.append("plants %d / biomass %d" % [plants, biomass])
	parts.append("waste %d" % waste)
	parts.append("nutrients %.1f" % nutrients)
	var max_gen: int = int(_stats.get("max_generation", 0))
	if max_gen > 0:
		parts.append("gen %d" % max_gen)
	hud.text = "   ·   ".join(parts)


func _day_label(p: float) -> String:
	# Map day_phase (0=dawn, 0.25=midday, 0.5=dusk, 0.75=midnight) to a label.
	if p < 0.125: return "dawn"
	elif p < 0.375: return "day"
	elif p < 0.5: return "dusk"
	elif p < 0.875: return "night"
	else: return "dawn"
