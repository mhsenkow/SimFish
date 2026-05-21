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
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var render_panel: PanelContainer = $RenderPanel
@onready var settings_toggle: Button = $SettingsToggle
@onready var render_toggle: Button = $RenderToggle

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
# Drag gesture state. When a mouse button goes down we lock in which mode the
# drag is operating in for its lifetime. That avoids the gesture flipping
# mid-drag if the user accidentally chords a second button.
#   "orbit" - LMB drag, rotate camera around target (Maya style LMB tumble)
#   "pan"   - MMB or Shift+LMB drag, slide the target perpendicular to view
#   "dolly" - RMB drag, push/pull camera in/out (vertical mouse Y = radius)
var _drag_mode: String = ""
var _last_mouse: Vector2 = Vector2.ZERO
var _drag_start: Vector2 = Vector2.ZERO  # to distinguish click from drag
var _drag_total: float = 0.0
var _drag_button: int = 0  # which button initiated; used for click-vs-drag dispatch
var _auto_orbit: bool = false
var _space_was_pressed: bool = false
const PAN_MOUSE_SENSITIVITY: float = 0.012  # world units per pixel at radius=1
const DOLLY_MOUSE_SENSITIVITY: float = 0.012  # log-ish dolly per pixel
# Follow-cam: when set, camera target tracks this Node3D.
var _follow_target: Node3D = null

# Aquascape mode: when active, sim is paused, mouse cursor projects to the
# substrate, and clicks place voxels according to the current tool. Tools:
#   1 = dirt   (raise substrate by stacking a soil voxel)
#   2 = stone  (gray hardscape)
#   3 = wood   (driftwood / dark brown)
#   4 = dig    (remove the topmost voxel under cursor)
# Tool changes via number keys while in aquascape mode. HUD shows current.
var _aquascape_mode: bool = false
var _aquascape_placed: Array[Node3D] = []
var _aquascape_preview: MeshInstance3D = null
var _aquascape_saved_time_scale: float = 1.0
var _aquascape_tool: String = "dirt"
const AQUASCAPE_TOOLS: Array[String] = ["dirt", "stone", "wood", "dig"]


func _ready() -> void:
	# Apply render-config values BEFORE the SubViewport assigns its texture
	# so the resolution change takes effect.
	_apply_render_config()
	display.texture = sub_viewport.get_texture()
	# Restore camera state if we saved it before a scene reload. Otherwise
	# fall back to defaults set at declaration.
	_restore_camera_state()
	_apply_camera()
	# Subscribe to SimDriver stats - they emit at ~1Hz with the ecosystem snapshot.
	await get_tree().process_frame
	_sim = world.get_node_or_null("SimDriver")
	if _sim != null and _sim.has_signal("stats_changed"):
		_sim.connect("stats_changed", _on_stats_changed)
	# Hook toggle buttons to the panels' toggle methods.
	if settings_toggle != null and settings_panel != null:
		settings_toggle.pressed.connect(settings_panel.toggle)
	if render_toggle != null and render_panel != null:
		render_toggle.pressed.connect(render_panel.toggle)


func _restore_camera_state() -> void:
	# Pull preserved camera yaw/pitch/radius/target from TankConfig if the
	# user has saved it (i.e. they Applied settings at least once and we
	# stashed the current view before reload).
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.camera_state_saved):
		return
	yaw = float(cfg.camera_yaw)
	pitch = float(cfg.camera_pitch)
	radius = float(cfg.camera_radius)
	target = Vector3(
		float(cfg.camera_target_x),
		float(cfg.camera_target_y),
		float(cfg.camera_target_z),
	)


# Called by the settings + render panels just before they call
# reload_current_scene(). Stashes the current view so we can restore it
# in the next _ready().
func save_camera_state() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.camera_yaw = yaw
	cfg.camera_pitch = pitch
	cfg.camera_radius = radius
	cfg.camera_target_x = target.x
	cfg.camera_target_y = target.y
	cfg.camera_target_z = target.z
	cfg.camera_state_saved = true
	cfg.save_to_disk()


func _apply_render_config() -> void:
	# Read TankConfig render settings and apply them to the SubViewport,
	# the palette-quantize shader on the Display TextureRect, and the camera.
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	# SubViewport size.
	sub_viewport.size = Vector2i(int(cfg.render_width), int(cfg.render_height))
	# MSAA: 0=disabled, 1=2x, 2=4x, 3=8x (matches Viewport.MSAA enum).
	sub_viewport.msaa_3d = int(cfg.msaa)
	# Palette quantize shader uniforms.
	if display.material is ShaderMaterial:
		var sm: ShaderMaterial = display.material
		# Set dither strength + internal resolution.
		sm.set_shader_parameter("dither_strength", float(cfg.dither_strength))
		sm.set_shader_parameter("internal_resolution",
			Vector2(float(cfg.render_width), float(cfg.render_height)))
	# If palette is disabled, swap the Display's shader to a passthrough by
	# setting dither_strength to 0 AND increasing palette_size temporarily.
	# Simpler: just set dither to 0 - the quantize still happens but no dither.
	# True bypass would require a separate shader; flagged as TODO.
	# Camera FOV.
	if camera != null:
		camera.fov = float(cfg.camera_fov)
	# Fog: read from environment if available.
	var we := world.get_node_or_null("WorldEnvironment")
	if we != null and we.environment != null:
		we.environment.volumetric_fog_density = float(cfg.fog_density)
		we.environment.volumetric_fog_anisotropy = float(cfg.fog_anisotropy)
		we.environment.volumetric_fog_ambient_inject = float(cfg.fog_ambient_inject)


func _process(dt: float) -> void:
	# Mouse position: use the WINDOW's mouse position (not the SubViewport's),
	# since that's where the OS cursor actually lives. get_window() returns
	# this scene's OS window.
	var mouse_now: Vector2 = get_window().get_mouse_position()
	var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var rmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var any_btn: bool = lmb or mmb or rmb

	if any_btn and not _orbiting:
		_orbiting = true
		_last_mouse = mouse_now
		_drag_start = mouse_now
		_drag_total = 0.0
		# Pick the drag mode based on which button started + modifiers.
		#   MMB or Shift+LMB -> pan target
		#   RMB              -> dolly (push/pull camera distance)
		#   LMB              -> orbit
		if mmb:
			_drag_mode = "pan"
			_drag_button = MOUSE_BUTTON_MIDDLE
		elif rmb:
			_drag_mode = "dolly"
			_drag_button = MOUSE_BUTTON_RIGHT
		else:
			_drag_button = MOUSE_BUTTON_LEFT
			_drag_mode = "pan" if shift else "orbit"
	elif not any_btn and _orbiting:
		_orbiting = false
		# Click vs drag: only the LMB tap dispatches as a click. MMB/RMB
		# release never places aquascape voxels or starts a follow.
		# Threshold loosened from 5 -> 12 to be more forgiving of trackpad
		# jitter during clicks.
		if _drag_button == MOUSE_BUTTON_LEFT and _drag_total < 12.0:
			if _aquascape_mode:
				_aquascape_place(mouse_now)
			else:
				_try_follow_click(mouse_now)
		_drag_mode = ""
		_drag_button = 0

	if _orbiting:
		var delta: Vector2 = mouse_now - _last_mouse
		_last_mouse = mouse_now
		_drag_total += delta.length()
		if delta.length_squared() > 0.0:
			match _drag_mode:
				"pan":
					_pan_target(delta)
				"dolly":
					# Vertical mouse motion = distance change. Drag DOWN pushes
					# camera away (radius up), drag UP pulls closer.
					radius = clampf(radius * (1.0 + delta.y * DOLLY_MOUSE_SENSITIVITY),
						MIN_RADIUS, MAX_RADIUS)
					_apply_camera()
				_:
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

	# Edge-triggered shortcuts. In aquascape mode 1/2/3/4 switch the tool;
	# otherwise they're the time-scale 1x/4x/16x keys.
	_handle_shortcut(KEY_P, _toggle_pause)
	_handle_shortcut(KEY_1, func(): _on_one())
	_handle_shortcut(KEY_2, func(): _on_two())
	_handle_shortcut(KEY_3, func(): _on_three())
	_handle_shortcut(KEY_4, func(): _on_four())
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


func _on_one() -> void:
	if _aquascape_mode:
		_aquascape_tool = "dirt"
	else:
		_set_time_scale(1.0)


func _on_two() -> void:
	if _aquascape_mode:
		_aquascape_tool = "stone"
	else:
		_set_time_scale(4.0)


func _on_three() -> void:
	if _aquascape_mode:
		_aquascape_tool = "wood"
	else:
		_set_time_scale(16.0)


func _on_four() -> void:
	if _aquascape_mode:
		_aquascape_tool = "dig"


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
	if _aquascape_mode:
		# Pause sim (if available) + clear any follow target.
		if _sim != null:
			_aquascape_saved_time_scale = float(_sim.time_scale)
			_sim.time_scale = 0.0
		_follow_target = null
		_ensure_aquascape_preview()
		print("[vivarium] aquascape ON. click to place stones, shift-click for driftwood, backspace undo, B exit.")
	else:
		if _sim != null:
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
	# If the cursor isn't pointing at a valid substrate cell inside the tank,
	# hide the preview so the user gets clear feedback that placement won't
	# happen here.
	if hit == INVALID_HIT:
		_aquascape_preview.visible = false
		return
	_aquascape_preview.visible = true
	# Snap to a 0.5-unit grid on X/Z so placement is tidy.
	hit.x = floorf(hit.x / 0.5) * 0.5 + 0.25
	hit.z = floorf(hit.z / 0.5) * 0.5 + 0.25
	# Y just above substrate.
	hit.y = _substrate_top_y() + 0.45
	_aquascape_preview.global_position = hit


const INVALID_HIT: Vector3 = Vector3(INF, INF, INF)


func _project_to_substrate(mouse_pos: Vector2) -> Vector3:
	# Project the cursor's ray onto the horizontal plane y = SUBSTRATE_TOP.
	# Returns INVALID_HIT if the ray doesn't hit the plane in front of the
	# camera OR if the hit falls outside the tank's footprint. Callers must
	# check before placing.
	if camera == null:
		return INVALID_HIT
	var win_size: Vector2 = get_window().size
	var sv_size: Vector2 = Vector2(sub_viewport.size)
	var sv_pos: Vector2 = mouse_pos * (sv_size / win_size)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	var top_y: float = _substrate_top_y()
	# Ray must be going DOWN for it to hit the substrate plane from above.
	if dir.y > -0.01:
		return INVALID_HIT
	var t: float = (top_y - origin.y) / dir.y
	if t < 0.0:
		return INVALID_HIT
	var hit: Vector3 = origin + dir * t
	# Reject points outside the tank's footprint - prevents placing dirt
	# in empty space when the cursor is past the glass wall.
	if world != null and world.has_method("is_inside_tank"):
		if not world.is_inside_tank(hit.x, hit.z, 0.3):
			return INVALID_HIT
	return hit


func _substrate_top_y() -> float:
	# World keeps SUBSTRATE_DEPTH publicly accessible.
	return float(world.get("SUBSTRATE_DEPTH")) if world != null else 1.6


func _aquascape_place(mouse_pos: Vector2) -> void:
	if world == null:
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	# Refuse to place when the cursor isn't over a valid substrate cell -
	# this is the fix for "dirt placed in empty space when clicking outside
	# the tank glass".
	if hit == INVALID_HIT:
		print("[vivarium] aquascape: cursor not over tank, skipping placement")
		return
	# Snap horizontally to a 0.5-unit grid so placement reads tidy.
	hit.x = floorf(hit.x / 0.5) * 0.5 + 0.25
	hit.z = floorf(hit.z / 0.5) * 0.5 + 0.25

	if _aquascape_tool == "dig":
		_aquascape_dig(hit)
		return

	# Look up the current top of the column (stack height under cursor) so
	# we place ON TOP of whatever is already there - this is what makes the
	# dirt tool feel like sculpting.
	var top_y: float = _column_top_y(hit.x, hit.z)
	var size_y: float = 0.5
	hit.y = top_y + size_y * 0.5

	# Pick color + voxel size based on tool.
	var color: Color
	var voxel_size: Vector3 = Vector3(0.5, size_y, 0.5)
	match _aquascape_tool:
		"dirt":
			# Substrate voxel - blends with the existing soil. Use the active
			# ramp's mid tones so it visually merges with the rest of the floor.
			var ramp: Array = world.get("ACTIVE_SOIL_RAMP")
			if ramp != null and ramp.size() == 6:
				color = ramp[3 + randi() % 2]   # one of the lighter soil tones
			else:
				color = Color8(95, 70, 45)
		"stone":
			var palette: Array[Color] = [
				Color8(85, 85, 96), Color8(75, 70, 78),
				Color8(105, 100, 92), Color8(60, 60, 70),
			]
			color = palette[randi() % palette.size()]
			voxel_size = Vector3(0.9, 0.9, 0.9)
		"wood":
			color = Color8(78, 52, 32)
			voxel_size = Vector3(0.9, 0.9, 0.9)
		_:
			color = Color8(120, 120, 120)
			voxel_size = Vector3(0.5, 0.5, 0.5)

	# For stones / wood, adjust hit.y so the bigger voxel rests on the column.
	hit.y = top_y + voxel_size.y * 0.5

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = voxel_size
	mi.mesh = bm
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	if voxel_mat_script != null:
		mi.material_override = voxel_mat_script.make(color)
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		mi.material_override = sm
	# add_child first, then global_position (Godot 4 transform ordering).
	world.add_child(mi)
	mi.global_position = hit
	mi.set_meta("aquascape_tool", _aquascape_tool)
	_aquascape_placed.append(mi)
	print("[vivarium] placed %s at %s (total %d)" % [_aquascape_tool, hit, _aquascape_placed.size()])


func _column_top_y(x: float, z: float) -> float:
	# Walk through all the placed objects + existing substrate visuals to
	# find the topmost Y in this XZ column. Cheap because we just iterate
	# the aquascape_placed list + the world's Substrate container.
	# Returns the world-space Y of the top face of the topmost voxel.
	var top: float = _substrate_top_y()
	# Aquascape placements first (these are the things the user just made).
	for v in _aquascape_placed:
		if not is_instance_valid(v):
			continue
		var gp: Vector3 = v.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			# Use the voxel's mesh size to compute its top.
			var size_y: float = 0.5
			if v is MeshInstance3D:
				var bm := (v as MeshInstance3D).mesh as BoxMesh
				if bm != null:
					size_y = bm.size.y
			var voxel_top: float = gp.y + size_y * 0.5
			if voxel_top > top:
				top = voxel_top
	return top


func _aquascape_dig(hit: Vector3) -> void:
	# Find the topmost aquascape-placed voxel at this cursor XZ and remove it.
	var best: Node3D = null
	var best_y: float = -INF
	for v in _aquascape_placed:
		if not is_instance_valid(v):
			continue
		var gp: Vector3 = v.global_position
		if absf(gp.x - hit.x) < 0.45 and absf(gp.z - hit.z) < 0.45 and gp.y > best_y:
			best_y = gp.y
			best = v
	if best == null:
		return
	_aquascape_placed.erase(best)
	best.queue_free()


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


# Pan: slide the orbit target perpendicular to the view direction. Mouse
# motion delta is in screen pixels; we convert to world units using the
# camera basis. Pan speed scales with radius so the world doesn't "fly past"
# at far zooms or feel sticky when zoomed in close. Mouse-right drag moves
# the world the same way (i.e. target goes LEFT under the camera).
func _pan_target(delta: Vector2) -> void:
	if camera == null:
		return
	var basis: Basis = camera.global_transform.basis
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	# Negate so dragging RIGHT pushes the scene right (target moves left).
	var scale: float = PAN_MOUSE_SENSITIVITY * radius
	target -= right * (delta.x * scale)
	target += up * (delta.y * scale)
	# Clear follow-cam when the user manually pans - they're taking control back.
	_follow_target = null
	_apply_camera()


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
	# Aquascape mode chip: shown only when active, calls out the current tool.
	if _aquascape_mode:
		parts.append("AQUASCAPE: %s (1 dirt · 2 stone · 3 wood · 4 dig)" %
			_aquascape_tool.to_upper())
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
	# Dissolved O2 - shown as a percent; <30 % gets a warning glyph so the
	# player notices the tank is gasping.
	if _stats.has("dissolved_o2"):
		var o2_pct: int = int(round(float(_stats["dissolved_o2"]) * 100.0))
		var fixture: String = String(_stats.get("aeration_fixture", "?"))
		var prefix: String = "!" if o2_pct < 30 else ""
		parts.append("%sO₂ %d%% (%s)" % [prefix, o2_pct, fixture])
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
