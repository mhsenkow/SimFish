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
@onready var hud: RichTextLabel = $DebugHUD
@onready var world: Node3D = $SubViewport/World
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var render_panel: PanelContainer = $RenderPanel
@onready var settings_toggle: Button = $SettingsToggle
@onready var render_toggle: Button = $RenderToggle
@onready var fish_store_toggle: Button = $FishStoreToggle
@onready var fish_store_panel: PanelContainer = $FishStorePanel
@onready var aquascape_toggle: Button = $AquascapeToggle
@onready var aquascape_palette: PanelContainer = $AquascapeToolPalette

@onready var portal_viewport: SubViewport = $PortalViewport
@onready var portal_camera: Camera3D = $PortalViewport/PortalCamera
@onready var portal_container: Control = $PortalContainer
@onready var portal_display: TextureRect = $PortalContainer/PortalDisplay
@onready var portal_hint: Label = $PortalContainer/PortalHint
@onready var portal_toggle: Button = $PortalToggle

var _portal_open: bool = false
var _portal_target: Node3D = null
# Fish-local eye offsets (forward = -Z on fish/shrimp nodes).
const PORTAL_EYE_FISH := Vector3(0.0, 0.07, -0.16)
const PORTAL_EYE_SHRIMP := Vector3(0.0, 0.05, -0.10)
const PORTAL_EYE_DEFAULT := Vector3(0.0, 0.04, -0.08)
# The four tool buttons inside the palette - built procedurally in _ready
# because we want one button per AQUASCAPE_TOOLS entry without locking
# in a fixed scene tree.
var _tool_buttons: Dictionary = {}

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
var _auto_orbit_was_pressed: bool = false
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
# Drag-existing-driftwood state. While in aquascape mode, an LMB hold that
# starts on a placed wood log enters drag mode for that log: the entire
# log Node3D follows the cursor's substrate projection until LMB releases.
# This is what makes the wood tool feel like aquascaping software instead
# of stamping single voxels.
var _wood_drag: Node3D = null
var _wood_drag_y_offset: float = 0.0
# Paint-brush throttle. When LMB is held in aquascape mode (no log under
# cursor) we drop voxels along the drag path; this prevents stacking
# dozens of them per second on the same cell.
var _paint_cooldown: float = 0.0
const PAINT_INTERVAL: float = 0.08   # seconds between brush samples
# Screen-space pick radius in SubViewport pixels (what you click on screen).
const PICK_RADIUS_PX: float = 48.0
const PORTAL_PICK_RADIUS_PX: float = 72.0
const RAY_PICK_RADIUS: float = 2.0


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
	if fish_store_toggle != null and fish_store_panel != null:
		fish_store_toggle.pressed.connect(fish_store_panel.toggle)
	if aquascape_toggle != null:
		aquascape_toggle.pressed.connect(_toggle_aquascape)
	_build_aquascape_palette()
	
	if portal_toggle != null:
		portal_toggle.pressed.connect(_toggle_portal)
	_setup_portal()


func _setup_portal() -> void:
	if portal_viewport == null or portal_camera == null or sub_viewport == null:
		return
	portal_viewport.world_3d = sub_viewport.world_3d
	portal_camera.set_as_top_level(true)
	portal_camera.current = true
	portal_camera.fov = 88.0
	portal_camera.near = 0.04
	portal_camera.far = 80.0
	if portal_display != null:
		portal_display.texture = portal_viewport.get_texture()
	portal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _toggle_portal() -> void:
	_portal_open = not _portal_open
	if portal_container != null:
		portal_container.visible = _portal_open
	if portal_viewport != null:
		portal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS \
			if _portal_open else SubViewport.UPDATE_DISABLED
	if not _portal_open:
		_portal_target = null
	if portal_hint != null:
		portal_hint.visible = _portal_target == null
	if _portal_open:
		_update_portal_pip()
	print("[vivarium] PiP portal %s" % ("OPEN" if _portal_open else "CLOSED"))


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
	# Tick the aquascape brush cooldown so drag-painting deposits voxels
	# at a steady rate regardless of frame timing.
	_paint_cooldown = maxf(0.0, _paint_cooldown - dt)
	# Mouse position: use the WINDOW's mouse position (not the SubViewport's),
	# since that's where the OS cursor actually lives. get_window() returns
	# this scene's OS window.
	var mouse_now: Vector2 = get_window().get_mouse_position()
	var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var rmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	# Pan modifier = either Shift OR Space held. Photoshop / Figma users have
	# "hold space to pan" in their muscle memory; CAD / DCC users reach for
	# Shift. Support both so neither group has to think.
	var pan_modifier: bool = Input.is_key_pressed(KEY_SHIFT) \
		or Input.is_key_pressed(KEY_SPACE)
	var any_btn: bool = lmb or mmb or rmb

	if any_btn and not _orbiting:
		_orbiting = true
		_last_mouse = mouse_now
		_drag_start = mouse_now
		_drag_total = 0.0
		# Pick the drag mode based on which button started + modifiers.
		#   MMB / Shift+LMB / Space+LMB -> pan target
		#   RMB                          -> dolly (push/pull camera distance)
		#   LMB                          -> orbit
		if mmb:
			_drag_mode = "pan"
			_drag_button = MOUSE_BUTTON_MIDDLE
		elif rmb:
			_drag_button = MOUSE_BUTTON_RIGHT
			# Aquascape mode swaps RMB from dolly to orbit so the user can
			# still rotate the camera while LMB is busy with the brush. In
			# normal mode RMB stays as dolly (wheel covers zoom anyway).
			_drag_mode = "orbit" if _aquascape_mode else "dolly"
		else:
			_drag_button = MOUSE_BUTTON_LEFT
			if pan_modifier:
				_drag_mode = "pan"
			elif _aquascape_mode:
				# Aquascape: LMB NEVER orbits. Either we're dragging an
				# existing wood log (mouse went down ON a log) or we're
				# painting voxels with the active tool. Painting fires
				# immediately on LMB-down + continues on drag, throttled
				# by _paint_cooldown so we don't stack 60 dirt voxels per
				# second.
				var picked: Node3D = _pick_wood_log(mouse_now)
				if picked != null:
					_wood_drag = picked
					_wood_drag_y_offset = picked.global_position.y \
						- _substrate_top_y()
					_drag_mode = "wood_drag"
				else:
					_drag_mode = "paint"
					_paint_cooldown = 0.0
					_aquascape_place(mouse_now)
			else:
				_drag_mode = "orbit"
	elif not any_btn and _orbiting:
		_orbiting = false
		_wood_drag = null
		# Click vs drag: only a pure LMB tap (no Shift/Space held, no
		# significant drag distance) dispatches as a click. MMB/RMB release
		# never places aquascape voxels or starts a follow. A Shift-LMB or
		# Space-LMB tap is treated as the user reaching for pan and then
		# changing their mind - no action.
		# Aquascape places happen DURING the drag (paint mode), not on
		# release. So in aquascape mode the only click-like action left is
		# the follow-fish dispatch (and that's disabled anyway since LMB
		# in aquascape goes to paint/wood_drag, never to orbit). For
		# normal mode this dispatches follow-cam on a clean LMB tap.
		_drag_mode = ""
		_drag_button = 0

	if _orbiting:
		# Dynamic modifier re-evaluation: while LMB is held, pressing OR
		# releasing Shift/Space mid-drag flips orbit <-> pan immediately.
		# MMB stays pan and RMB stays dolly for their whole gesture - the
		# starting button's intent wins for non-LMB drags.
		#
		# CRITICAL: don't touch paint / wood_drag modes here. Those were
		# locked in at LMB-down by the aquascape branch above; overwriting
		# them every frame is what made the original "I can't paint dirt"
		# bug - the moment the cursor moved, the mode flipped back to
		# orbit and the camera ate the drag.
		if _drag_button == MOUSE_BUTTON_LEFT \
				and _drag_mode != "paint" \
				and _drag_mode != "wood_drag":
			_drag_mode = "pan" if pan_modifier else "orbit"
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
				"paint":
					# Aquascape brush. Drop a voxel at the current cursor
					# every PAINT_INTERVAL seconds; this lets the user
					# "paint" dirt by dragging instead of clicking once per
					# voxel. The cooldown is ticked elsewhere in _process.
					if _paint_cooldown <= 0.0:
						_aquascape_place(mouse_now)
						_paint_cooldown = PAINT_INTERVAL
				"wood_drag":
					# Move the held driftwood log to the current cursor
					# projection on the substrate. Preserve its original
					# Y offset so logs that were sitting up on a stone pile
					# don't snap down into the floor.
					if _wood_drag != null and is_instance_valid(_wood_drag):
						var hit: Vector3 = _project_to_substrate(mouse_now)
						if hit != INVALID_HIT:
							_wood_drag.global_position = Vector3(
								hit.x,
								_substrate_top_y() + _wood_drag_y_offset,
								hit.z)
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
			
	if _portal_open:
		_update_portal_pip()

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

	# G toggles auto-orbit. (Space used to do this; it's now reserved as the
	# hold-to-pan modifier, matching Photoshop / Figma muscle memory.)
	var g_now: bool = Input.is_key_pressed(KEY_G)
	if g_now and not _auto_orbit_was_pressed:
		_auto_orbit = not _auto_orbit
	_auto_orbit_was_pressed = g_now
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
	_handle_shortcut(KEY_C, _toggle_portal)
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
		_refresh_tool_buttons()
	else:
		_set_time_scale(1.0)


func _on_two() -> void:
	if _aquascape_mode:
		_aquascape_tool = "stone"
		_refresh_tool_buttons()
	else:
		_set_time_scale(4.0)


func _on_three() -> void:
	if _aquascape_mode:
		_aquascape_tool = "wood"
		_refresh_tool_buttons()
	else:
		_set_time_scale(16.0)


func _on_four() -> void:
	if _aquascape_mode:
		_aquascape_tool = "dig"
		_refresh_tool_buttons()


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
	_portal_target = null
	if portal_hint != null and _portal_open:
		portal_hint.visible = true


func _window_mouse_to_viewport(mouse: Vector2) -> Vector2:
	# Prefer Display-local coords (Retina-safe). Fall back to global rect math.
	if display != null and sub_viewport != null and display.size.x > 1.0:
		var local: Vector2 = display.get_local_mouse_position()
		if local.x >= 0.0 and local.y >= 0.0 \
				and local.x <= display.size.x and local.y <= display.size.y:
			return Vector2(
				local.x / display.size.x * float(sub_viewport.size.x),
				local.y / display.size.y * float(sub_viewport.size.y),
			)
		var rect: Rect2 = display.get_global_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			var glocal: Vector2 = mouse - rect.position
			return Vector2(
				clampf(glocal.x / rect.size.x, 0.0, 1.0) * float(sub_viewport.size.x),
				clampf(glocal.y / rect.size.y, 0.0, 1.0) * float(sub_viewport.size.y),
			)
	if sub_viewport == null:
		return mouse
	var win_size: Vector2 = get_window().size
	var sv_size: Vector2 = Vector2(sub_viewport.size)
	return mouse * (sv_size / win_size)


func _gather_creatures() -> Array:
	var creatures: Array = []
	var seen: Dictionary = {}
	if _sim != null:
		for f in _sim.fish:
			if is_instance_valid(f) and not seen.has(f.get_instance_id()):
				seen[f.get_instance_id()] = true
				creatures.append(f)
		for s in _sim.shrimp:
			if is_instance_valid(s) and not seen.has(s.get_instance_id()):
				seen[s.get_instance_id()] = true
				creatures.append(s)
		if _sim.snails_root != null:
			for sn in _sim.snails_root.get_children():
				if is_instance_valid(sn) and not seen.has(sn.get_instance_id()):
					seen[sn.get_instance_id()] = true
					creatures.append(sn)
	# Fallback: scan the scene tree if SimDriver arrays are empty/stale.
	if creatures.is_empty() and world != null:
		var fauna: Node = world.get_node_or_null("Fauna")
		if fauna != null:
			for c in fauna.get_children():
				if is_instance_valid(c) and c is Node3D \
						and not seen.has(c.get_instance_id()):
					seen[c.get_instance_id()] = true
					creatures.append(c)
		var snails: Node = world.get_node_or_null("Snails")
		if snails != null:
			for c in snails.get_children():
				if is_instance_valid(c) and c is Node3D \
						and not seen.has(c.get_instance_id()):
					seen[c.get_instance_id()] = true
					creatures.append(c)
	return creatures


func _pick_creature_at_viewport(sv_pos: Vector2) -> Node3D:
	if camera == null:
		return null
	var radius_px: float = PORTAL_PICK_RADIUS_PX if _portal_open else PICK_RADIUS_PX
	var best: Node3D = null
	var best_score: float = radius_px
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	for c in _gather_creatures():
		var n: Node3D = c as Node3D
		if n == null:
			continue
		if camera.is_position_behind(n.global_position):
			continue
		var screen_pt: Vector2 = camera.unproject_position(n.global_position)
		var screen_dist: float = screen_pt.distance_to(sv_pos)
		var to_n: Vector3 = n.global_position - origin
		var t: float = to_n.dot(dir)
		var ray_dist: float = 9999.0
		if t > 0.05:
			var closest: Vector3 = origin + dir * t
			ray_dist = closest.distance_to(n.global_position)
		var score: float = minf(screen_dist, ray_dist * 24.0)
		if score < best_score:
			best_score = score
			best = n
	return best


func _pick_creature_from_display() -> Node3D:
	if display == null or sub_viewport == null:
		return null
	var sv_pos: Vector2 = _window_mouse_to_viewport(get_viewport().get_mouse_position())
	return _pick_creature_at_viewport(sv_pos)


func _creature_label(creature: Node) -> String:
	if creature is Fish:
		if creature.get("maturity") != null and creature.maturity == Fish.MATURITY_FRY:
			return "fish (fry)"
		return "fish"
	if creature is Shrimp:
		if creature.get("is_baby") != null and creature.is_baby:
			return "shrimp (baby)"
		return "shrimp"
	var scr: Script = creature.get_script()
	if scr != null and scr.resource_path.ends_with("snail.gd"):
		return "snail"
	return creature.name


func _creature_eye_local(creature: Node) -> Vector3:
	if creature is Fish:
		return PORTAL_EYE_FISH
	if creature is Shrimp:
		return PORTAL_EYE_SHRIMP
	return PORTAL_EYE_DEFAULT


func _creature_swim_forward(creature: Node3D) -> Vector3:
	if creature.get("heading") != null:
		var h: Variant = creature.get("heading")
		if h is Vector3 and (h as Vector3).length_squared() > 0.01:
			return (h as Vector3).normalized()
	return -creature.global_transform.basis.z.normalized()


func _creature_eye_transform(creature: Node3D) -> Transform3D:
	var t: Transform3D = creature.global_transform
	var eye_pos: Vector3 = t * _creature_eye_local(creature)
	var fwd: Vector3 = _creature_swim_forward(creature)
	var up: Vector3 = t.basis.y
	if absf(fwd.dot(up)) > 0.92:
		up = Vector3.UP
	return Transform3D(Basis.looking_at(fwd, up), eye_pos)


func _update_portal_pip() -> void:
	if not _portal_open or portal_camera == null:
		return
	if _portal_target == null or not is_instance_valid(_portal_target):
		_portal_target = null
		if portal_hint != null:
			portal_hint.visible = true
		return
	portal_camera.global_transform = _creature_eye_transform(_portal_target)
	if portal_hint != null:
		portal_hint.visible = false


func _assign_creature_target(creature: Node3D) -> void:
	if _portal_open:
		_portal_target = creature
		_update_portal_pip()
		print("[vivarium] portal tracking %s" % _creature_label(creature))
	else:
		_follow_target = creature
		print("[vivarium] following %s" % _creature_label(creature))


func _click_targets_creature() -> bool:
	if _aquascape_mode:
		return false
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE):
		return false
	if display == null:
		return false
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != display:
		if hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			if hovered is BaseButton or hovered is PanelContainer:
				return false
	var gp: Vector2 = display.get_global_mouse_position()
	if not display.get_global_rect().has_point(gp):
		return false
	var picked: Node3D = _pick_creature_from_display()
	if picked == null:
		var n_creatures: int = _gather_creatures().size()
		if _portal_open or n_creatures > 0:
			print("[vivarium] pick miss: creatures=%d mouse=%s sv=%s" % [
				n_creatures,
				display.get_local_mouse_position(),
				_window_mouse_to_viewport(get_viewport().get_mouse_position()),
			])
		return false
	_assign_creature_target(picked)
	return true


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
		if aquascape_palette != null:
			aquascape_palette.visible = true
		_refresh_tool_buttons()
		print("[vivarium] aquascape ON. click to place stones, shift-click for driftwood, backspace undo, B exit.")
	else:
		if _sim != null:
			_sim.time_scale = _aquascape_saved_time_scale
		if _aquascape_preview != null:
			_aquascape_preview.visible = false
		if aquascape_palette != null:
			aquascape_palette.visible = false
		print("[vivarium] aquascape OFF (resumed at %gx)" % _aquascape_saved_time_scale)


# Build the floating tool palette shown at top-center while in aquascape
# mode. Each tool gets a button; the currently-selected tool is
# highlighted. Buttons forward to the existing number-key handlers so
# the keyboard + UI paths stay consistent.
func _build_aquascape_palette() -> void:
	if aquascape_palette == null:
		return
	for c in aquascape_palette.get_children():
		c.queue_free()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	aquascape_palette.add_child(hb)
	var header := Label.new()
	header.text = "AQUASCAPE  →"
	header.add_theme_color_override("font_color", Color8(255, 220, 80))
	header.add_theme_font_size_override("font_size", 12)
	hb.add_child(header)
	var defs := [
		{"key": "dirt",  "label": "1·dirt",  "color": Color8(150, 110, 70)},
		{"key": "stone", "label": "2·stone", "color": Color8(120, 120, 130)},
		{"key": "wood",  "label": "3·wood",  "color": Color8(95, 65, 35)},
		{"key": "dig",   "label": "4·dig",   "color": Color8(220, 90, 90)},
	]
	for def in defs:
		var btn := Button.new()
		btn.text = String(def["label"])
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_font_size_override("font_size", 12)
		var key: String = String(def["key"])
		btn.pressed.connect(func():
			_aquascape_tool = key
			_refresh_tool_buttons())
		hb.add_child(btn)
		_tool_buttons[key] = btn
	# Help hint at the right side.
	var hint := Label.new()
	hint.text = "  drag a log to move · BACKSPACE undo · B exit"
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	hint.add_theme_font_size_override("font_size", 10)
	hb.add_child(hint)


# Update which tool button looks selected. Called whenever the tool
# changes - either by keyboard (1/2/3/4) or by clicking the palette.
func _refresh_tool_buttons() -> void:
	for k in _tool_buttons.keys():
		var btn: Button = _tool_buttons[k]
		if btn == null:
			continue
		if k == _aquascape_tool:
			btn.modulate = Color(1.4, 1.4, 0.7)
		else:
			btn.modulate = Color(0.85, 0.85, 0.85)


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


# Pick the topmost placed wood log under the cursor (or null). Iterates
# _aquascape_placed, ray-tests against each log's bounding sphere computed
# from its first child voxel's distance to centroid. Cheap because the
# list is small (usually < 8 logs).
func _pick_wood_log(mouse_pos: Vector2) -> Node3D:
	if camera == null:
		return null
	var sv_pos: Vector2 = _window_mouse_to_viewport(mouse_pos)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	var best: Node3D = null
	var best_t: float = 1e9
	for v in _aquascape_placed:
		if not is_instance_valid(v):
			continue
		# Wood logs are Node3D containers with multiple voxel children;
		# single-voxel placements (dirt, stone) are MeshInstance3D leaves.
		# Tool meta tells us the kind reliably.
		if v.get_meta("aquascape_tool", "") != "wood":
			continue
		# Sphere test: log "radius" approximated as 1.6 (~5 voxels of 0.7).
		var to_c: Vector3 = v.global_position - origin
		var t: float = to_c.dot(dir)
		if t < 0.0:
			continue
		var closest: Vector3 = origin + dir * t
		var perp_sq: float = (closest - v.global_position).length_squared()
		if perp_sq < 1.6 * 1.6 and t < best_t:
			best_t = t
			best = v
	return best


func _project_to_substrate(mouse_pos: Vector2) -> Vector3:
	# Project the cursor's ray onto the horizontal plane y = SUBSTRATE_TOP.
	# Returns INVALID_HIT if the ray doesn't hit the plane in front of the
	# camera OR if the hit falls outside the tank's footprint. Callers must
	# check before placing.
	if camera == null:
		return INVALID_HIT
	var sv_pos: Vector2 = _window_mouse_to_viewport(mouse_pos)
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

	# Wood is special: spawn a multi-voxel "log" (5-7 voxels in a gentle
	# curve) parented onto the world's Hardscape container so the fry
	# hide-at-log behavior can find it. Returns early after spawning the
	# log so we don't fall into the generic single-voxel path below.
	if _aquascape_tool == "wood":
		_aquascape_place_log(Vector3(hit.x, top_y, hit.z))
		return

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
		_:
			color = Color8(120, 120, 120)
			voxel_size = Vector3(0.5, 0.5, 0.5)

	# For stones, adjust hit.y so the bigger voxel rests on the column.
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


# Spawn a driftwood "log" as a 5-7 voxel chain in a gentle curve, parented
# to the world's Hardscape container so fry can hide against it. The log
# is a Node3D so the entire piece moves as one when the user drags it
# during aquascape mode.
func _aquascape_place_log(base: Vector3) -> void:
	if world == null:
		return
	var hardscape := world.get_node_or_null("Hardscape")
	if hardscape == null:
		# Fall back to world root if Hardscape wasn't built yet.
		hardscape = world
	var log := Node3D.new()
	log.name = "AquaLog"
	hardscape.add_child(log)
	log.global_position = base + Vector3(0, 0.35, 0)
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	# Random orientation: pick an angle in the XZ plane + a curve sign.
	var theta: float = randf_range(0.0, TAU)
	var forward: Vector3 = Vector3(cos(theta), 0, sin(theta))
	var curve_sign: float = 1.0 if randf() < 0.5 else -1.0
	var dark := Color8(58, 38, 22)
	var mid := Color8(78, 52, 32)
	var light := Color8(98, 70, 46)
	var palette: Array[Color] = [dark, mid, light, mid, dark]
	var n_segments: int = randi_range(5, 7)
	for i in n_segments:
		var t: float = float(i) / float(maxi(1, n_segments - 1))
		# Curve offset perpendicular to forward.
		var perp: Vector3 = Vector3(-forward.z, 0, forward.x) * curve_sign
		var offset: Vector3 = forward * (i - n_segments * 0.5) * 0.6 \
			+ perp * sin(t * PI) * 0.35
		# Slight Y arc (logs are not flat).
		offset.y = sin(t * PI) * 0.2
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		# Slight size variation so the log doesn't look made of identical bricks.
		var s: float = 0.7 + randf_range(-0.1, 0.1)
		bm.size = Vector3(s, s * 0.85, s)
		seg.mesh = bm
		var c: Color = palette[i % palette.size()]
		if voxel_mat_script != null:
			seg.material_override = voxel_mat_script.make(c)
		else:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = c
			seg.material_override = sm
		log.add_child(seg)
		seg.position = offset
	log.set_meta("aquascape_tool", "wood")
	_aquascape_placed.append(log)
	print("[vivarium] placed driftwood log at %s" % base)


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


# Scroll wheel + creature clicks come through as events (not reliable via polling).
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
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_click_targets_creature()


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
	_push_telemetry_to_js()


# Web-only: forward the current stats snapshot to the host page so it can
# POST it to the headless launcher's /telemetry endpoint. No-op on native
# builds (no JavaScriptBridge there). The injected page-side shim defines
# window.__vivariumPushStats; if we're hosted somewhere else, this just
# silently does nothing.
func _push_telemetry_to_js() -> void:
	if not OS.has_feature("web"):
		return
	var payload: Dictionary = _stats.duplicate()
	if _sim != null:
		payload["time_scale"] = float(_sim.time_scale)
		payload["day_phase"] = float(_sim.day_phase)
		payload["tank_seed"] = int(_sim.tank_seed)
		# Effective sim tick rate. SimDriver runs the inner loop at SIM_HZ
		# but multiplies the incoming delta by time_scale, so the *observed*
		# tick rate scales with it. Pause => 0.
		payload["sim_fps"] = float(_sim.SIM_HZ) * float(_sim.time_scale)
	payload["render_fps"] = float(Engine.get_frames_per_second())
	# Use compact JSON; the host shim parses it as a plain JS object.
	var body: String = JSON.stringify(payload)
	# eval(code, use_global_execution_context). Global context is what we
	# want. The shim defined window.__vivariumPushStats at top level.
	JavaScriptBridge.eval(
		"if (window.__vivariumPushStats) { window.__vivariumPushStats(" + body + "); }",
		true,
	)


func _update_hud(_mouse_pos: Vector2, _any_btn: bool) -> void:
	# Header re-rendered on stats_changed; nothing per-frame.
	pass


func _render_header() -> void:
	if hud == null:
		return
	# Four-group BBCode strip. Each group has a softly tinted label so the
	# eye can scan to its category fast without reading every number.
	# Groups separated by double-bullets; items inside a group by single
	# bullets. Warning conditions (paused, low O2, algae outbreak) get a
	# colored highlight + a "!" prefix so trouble is visible at a glance.
	#
	#   [STATE]  cafef155 · 1× · day
	#   [FAUNA]  fish 22 / 11A 11F · shrimp 11 / 8A 3F · snails 6 / 5A 1B
	#   [FLORA]  plants 89 · biomass 451 · algae 3
	#   [WATER]  O2 87% disk · nutrients 6.4 · waste 0 · gen 4
	var fish_total: int = int(_stats.get("fish_total", 0))
	var fish_adults: int = int(_stats.get("fish_adults", 0))
	var fish_fry: int = int(_stats.get("fish_fry", 0))
	var shrimp_total: int = int(_stats.get("shrimp_total", 0))
	var shrimp_adults: int = int(_stats.get("shrimp_adults", 0))
	var shrimp_fry: int = int(_stats.get("shrimp_fry", 0))
	var snail_total: int = int(_stats.get("snails_total", 0))
	var snail_adults: int = int(_stats.get("snails_adults", 0))
	var snail_babies: int = int(_stats.get("snails_babies", 0))
	var algae: int = int(_stats.get("algae_clusters", 0))
	var eggs: int = int(_stats.get("eggs", 0))
	var plants: int = int(_stats.get("plants_alive", 0))
	var biomass: int = int(_stats.get("plant_total_biomass", 0))
	var waste: int = int(_stats.get("waste_particles", 0))
	var nutrients: float = float(_stats.get("substrate_nutrients_total", 0.0))
	var o2: float = float(_stats.get("dissolved_o2", 1.0))
	var fixture: String = String(_stats.get("aeration_fixture", "?"))
	var max_gen: int = int(_stats.get("max_generation", 0))

	# Soft, distinct group tints so the eye can find each section.
	var c_state := "#9aa8c8"
	var c_fauna := "#d6b070"
	var c_flora := "#86c084"
	var c_water := "#7fb7d8"
	var c_warn := "#e07070"

	var groups: Array[String] = []

	# Aquascape banner takes priority when active.
	if _aquascape_mode:
		groups.append("[color=#e0c060]AQUASCAPE %s[/color] (1 dirt · 2 stone · 3 wood · 4 dig)"
			% _aquascape_tool.to_upper())

	# --- STATE: seed · clock · day phase ---
	if _sim != null:
		var seed_str: String = "%08x" % int(_sim.tank_seed)
		var ts: float = float(_sim.time_scale)
		var clock: String
		if ts == 0.0:
			clock = "[color=%s]paused[/color]" % c_warn
		elif is_equal_approx(ts, 1.0):
			clock = "1×"
		else:
			clock = "%g×" % ts
		var day: String = _day_label(float(_sim.day_phase))
		groups.append("[color=%s]state[/color] %s · %s · %s" % [c_state, seed_str, clock, day])

	# --- FAUNA: fish · shrimp · snails · eggs ---
	# Population format helper renders "0", "N", or "N / aA fF" depending on
	# the breakdown. Suffix letters: A=adults, F=fry, B=babies for snails.
	var fauna_parts: Array[String] = []
	fauna_parts.append("fish " + _pop_str(fish_total, fish_adults, fish_fry, "A", "F"))
	fauna_parts.append("shrimp " + _pop_str(shrimp_total, shrimp_adults, shrimp_fry, "A", "F"))
	fauna_parts.append("snails " + _pop_str(snail_total, snail_adults, snail_babies, "A", "B"))
	if eggs > 0:
		fauna_parts.append("eggs %d" % eggs)
	groups.append("[color=%s]fauna[/color] %s" % [c_fauna, " · ".join(fauna_parts)])

	# --- FLORA: plants · biomass · algae ---
	var flora_parts: Array[String] = []
	flora_parts.append("plants %d" % plants)
	flora_parts.append("biomass %d" % biomass)
	if algae > 0:
		# Algae > 20 is becoming an outbreak; flag in red so the player can
		# tune light / nutrients to bring it down.
		var algae_str: String = "%d" % algae
		if algae > 20:
			algae_str = "[color=%s]!%d[/color]" % [c_warn, algae]
		flora_parts.append("algae " + algae_str)
	groups.append("[color=%s]flora[/color] %s" % [c_flora, " · ".join(flora_parts)])

	# --- WATER: O2 + fixture · nutrients · waste · gen ---
	var water_parts: Array[String] = []
	var o2_pct: int = int(round(o2 * 100.0))
	if o2_pct < 30:
		water_parts.append("[color=%s]!O₂ %d%% %s[/color]" % [c_warn, o2_pct, fixture])
	elif o2_pct < 50:
		water_parts.append("[color=#d9bb70]O₂ %d%% %s[/color]" % [o2_pct, fixture])
	else:
		water_parts.append("O₂ %d%% %s" % [o2_pct, fixture])
	water_parts.append("nutrients %.1f" % nutrients)
	water_parts.append("waste %d" % waste)
	if max_gen > 0:
		water_parts.append("gen %d" % max_gen)
	# Emergent speciation: show how many distinct morphs are alive. Greater
	# than 1 means the founding species has fragmented into recognizable
	# variants - the system is actively speciating.
	var distinct: int = int(_stats.get("morph_distinct", 0))
	if distinct > 0:
		water_parts.append("[color=#e0c060]morphs +%d[/color]" % distinct)
	groups.append("[color=%s]water[/color] %s" % [c_water, " · ".join(water_parts)])

	# Join groups with double bullets so the eye groups them visually.
	# RichTextLabel handles BBCode + horizontal centering via inline alignment.
	hud.text = "[center]" + "   ··   ".join(groups) + "[/center]"


# Format "{total} / {adults}{a_suf} {kids}{k_suf}" with the breakdown hidden
# if the population is zero or undifferentiated. Examples:
#   fish 0       -> "0" dim
#   fish 6       -> "6"            (no babies, no adults stat available)
#   fish 4 ad/2f -> "4 / 2A 2F"
func _pop_str(total: int, adults: int, kids: int, a_suf: String, k_suf: String) -> String:
	if total == 0:
		return "[color=#777777]0[/color]"
	if adults == 0 and kids == 0:
		return "%d" % total
	return "%d / %d%s %d%s" % [total, adults, a_suf, kids, k_suf]


func _day_label(p: float) -> String:
	# Map day_phase (0=dawn, 0.25=midday, 0.5=dusk, 0.75=midnight) to a label.
	if p < 0.125: return "dawn"
	elif p < 0.375: return "day"
	elif p < 0.5: return "dusk"
	elif p < 0.875: return "night"
	else: return "dawn"
