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
@onready var world: Node3D = $SubViewport/World
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var render_panel: PanelContainer = $RenderPanel
@onready var fish_store_panel: PanelContainer = $FishStorePanel
@onready var library_panel: PanelContainer = $LibraryPanel
@onready var creature_creator_panel: PanelContainer = $CreatureCreatorPanel
@onready var walkthrough_overlay: Control = $WalkthroughOverlay
@onready var aquascape_palette: PanelContainer = $AquascapeToolPalette

# Top-bar HUD — restructured 2026 into clusters + chip strip. All buttons are
# unique_name_in_owner so the script paths survive future re-parenting.
@onready var top_hud: Control = $TopHUD
@onready var left_cluster: PanelContainer = %LeftCluster
@onready var right_cluster: PanelContainer = %RightCluster
@onready var stats_bar: PanelContainer = %StatsBar
@onready var settings_toggle: Button = %SettingsToggle
@onready var render_toggle: Button = %RenderToggle
@onready var fish_store_toggle: Button = %FishStoreToggle
@onready var library_toggle: Button = %LibraryToggle
@onready var creature_creator_toggle: Button = %CreatureCreatorToggle
@onready var aquascape_toggle: Button = %AquascapeToggle
@onready var menu_button: Button = %MenuButton
@onready var portal_toggle: Button = %PortalToggle

# Stat chip refs — built once in _ready, value labels updated on stats_changed.
# Keys: "state", "fauna", "flora", "water", "alert".
var _chips: Dictionary = {}
# Layout breakpoint — last computed, drives _apply_hud_layout decisions.
var _hud_layout: String = ""
# Idle-dim state for the top HUD (mirrors MobileHUD's behavior).
var _hud_idle_seconds: float = 0.0
const HUD_IDLE_DIM_SECONDS: float = 6.0
const HUD_DIM_MODULATE: Color = Color(1, 1, 1, 0.45)
const HUD_LIT_MODULATE: Color = Color(1, 1, 1, 1)

@onready var portal_viewport: SubViewport = $PortalViewport
@onready var portal_camera: Camera3D = $PortalViewport/PortalCamera
@onready var portal_container: Control = $PortalContainer
@onready var portal_display: TextureRect = $PortalContainer/PortalDisplay
@onready var portal_hint: Label = $PortalContainer/PortalHint

var _portal_open: bool = false
var _portal_target: Node3D = null
var _portal_mat: ShaderMaterial = null
const PORTAL_ZOOM: float = 3.5

# PiP info panel elements
var _portal_info_panel: PanelContainer = null
var _portal_name_lbl: Label = null
var _portal_lineage_lbl: Label = null
var _portal_stats_lbl: Label = null

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
const DEFAULT_RADIUS := 17.5
const DEFAULT_YAW := -0.55
const DEFAULT_PITCH := 0.48

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
# Set true when an LMB-down event lands on a creature (picking dispatch in
# `_input`). The `_process` polling reads `Input.is_mouse_button_pressed` —
# event handling can't stop polling, so without this flag the same press
# ALSO starts an orbit drag and every creature click spun the camera.
# Cleared the next frame LMB releases.
var _suppress_drag_until_release: bool = false

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
# Saved sim speed while the guided walkthrough holds the sim paused.
var _wt_saved_time_scale: float = 1.0
var _aquascape_tool: String = "dirt"
const AQUASCAPE_TOOLS: Array[String] = ["dirt", "stone", "wood", "dig"]
# Drag-existing-driftwood state. While in aquascape mode, an LMB hold that
# starts on a placed wood log enters drag mode for that log: the entire
# log Node3D follows the cursor's substrate projection until LMB releases.
# This is what makes the wood tool feel like aquascaping software instead
# of stamping single voxels.
var _wood_drag: Node3D = null
var _wood_drag_y_offset: float = 0.0
# Last substrate-projected cursor point during a hardscape-piece drag, used
# for delta-based movement so picking a big piece doesn't teleport it.
var _wood_drag_last_hit: Vector3 = Vector3(INF, INF, INF)
# Ad-hoc cluster of loose procedural hardscape voxels being dragged together.
var _drag_cluster: Array[Node3D] = []
# Paint-brush throttle. When LMB is held in aquascape mode (no log under
# cursor) we drop voxels along the drag path; this prevents stacking
# dozens of them per second on the same cell.
var _paint_cooldown: float = 0.0
const PAINT_INTERVAL: float = 0.08   # seconds between brush samples
# Screen-space pick radius in SubViewport pixels (what you click on screen).
const PICK_RADIUS_PX: float = 48.0
const PORTAL_PICK_RADIUS_PX: float = 72.0
# Fingers are less precise than a mouse cursor — bump the pick radius up so
# small fish are tappable. Applied in _pick_creature_at_viewport when touch
# is the active input source.
const PICK_RADIUS_PX_TOUCH: float = 110.0
const RAY_PICK_RADIUS: float = 2.0

# ---- Touch input state ----
# Active touch points keyed by finger index → current screen position.
var _touches: Dictionary = {}
var _touch_prev: Dictionary = {}  # previous frame positions for delta calc
# Pinch zoom: distance between two fingers on the previous frame.
var _pinch_distance: float = 0.0
# Tap detection: time and position when the first finger went down.
var _tap_start_time: float = 0.0
var _tap_start_pos: Vector2 = Vector2.ZERO
var _tap_moved: float = 0.0  # cumulative drag distance since touch-down
# Double-tap detection.
var _last_tap_time: float = -1.0
var _last_tap_pos: Vector2 = Vector2.ZERO
const DOUBLE_TAP_WINDOW: float = 0.4  # seconds
const DOUBLE_TAP_RADIUS: float = 40.0  # pixels
# Long-press detection.
var _long_press_fired: bool = false
const LONG_PRESS_TIME: float = 0.5  # seconds
const TAP_MAX_MOVE: float = 20.0  # pixels; beyond this it's a drag, not a tap
const TAP_MAX_TIME: float = 0.25  # seconds
# Touch sensitivity (slightly higher than mouse because fingers are less precise).
const TOUCH_ORBIT_SENSITIVITY: float = 0.004
const TOUCH_PAN_SENSITIVITY: float = 0.015
const PINCH_ZOOM_SENSITIVITY: float = 0.008
# Flag: true while any finger is touching the screen. Used to suppress
# mouse-polling so emulated mouse events from touch don't double-fire.
var _touch_active: bool = false
# Mobile HUD reference (wired in _ready if the node exists).
var _mobile_hud: Control = null

# ---- Two-finger twist gesture ----
# Angle (radians) between the two touching fingers on the previous frame.
# Compared against current angle in _handle_screen_drag to compute a delta
# we apply to camera yaw.
var _pinch_angle: float = 0.0
const TWIST_SENSITIVITY: float = 1.2  # multiplier on the raw radian delta

# ---- Edge swipe to open settings panel ----
# When a single touch lands within EDGE_SWIPE_TRIGGER_PX of the right screen
# edge AND the user then drags > EDGE_SWIPE_MIN_PX to the left, we toggle
# settings. Set on touch-down, cleared on lift or once consumed.
var _edge_swipe_active: bool = false
var _edge_swipe_start_x: float = 0.0
const EDGE_SWIPE_TRIGGER_PX: float = 28.0
const EDGE_SWIPE_MIN_PX: float = 80.0

# ---- Focus-out / background pause ----
# Stash time_scale when the OS sends FOCUS_OUT (user switched apps / locked
# screen). Restored on FOCUS_IN. We bail out gracefully if a pause was
# already in effect (aquascape mode, manual pause) so we don't clobber it.
var _focus_paused: bool = false
var _focus_saved_time_scale: float = 1.0

# ---- Aquascape radial menu (mobile only) ----
# Replaces the long-press-toggles-auto-orbit gesture WHEN in aquascape mode,
# so a long-press near a finger pops up a 4-tool wheel (dirt/stone/wood/dig).
# Tap an icon to select tool; tap outside to dismiss.
var _radial_menu: Control = null

# ---- Tutorial overlay ----
# Shown on first mobile launch; dismissed by tapping OK, persisted via
# TankConfig.tutorial_seen so it never returns.
var _tutorial_overlay: Control = null

# ---- Welcome-back toast (time-skip recap) ----
# Floating Label shown briefly on resume when we detect the user was away.
var _welcome_label: Label = null

# ---- Species discovery toast ----
var _discovery_toast: Label = null
var _discovery_toast_tween: Tween = null
var _welcome_toast_tween: Tween = null


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _is_touch_active() -> bool:
	return _touch_active


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
	if library_toggle != null and library_panel != null:
		library_toggle.pressed.connect(library_panel.toggle)
	if creature_creator_toggle != null and creature_creator_panel != null:
		creature_creator_toggle.pressed.connect(creature_creator_panel.toggle)
	if walkthrough_overlay != null and walkthrough_overlay.has_method("setup"):
		walkthrough_overlay.setup(self)
		# Launch the guided walkthrough if the tank menu flagged this tank for
		# it. Deferred so world/sim are fully ready first.
		call_deferred("_maybe_start_walkthrough")
	var species_lib := get_node_or_null("/root/SpeciesLibrary")
	if species_lib != null and species_lib.has_signal("species_discovered"):
		species_lib.species_discovered.connect(_on_species_discovered)
	if aquascape_toggle != null:
		aquascape_toggle.pressed.connect(_toggle_aquascape)
	if menu_button != null:
		menu_button.pressed.connect(_on_back_to_menu)
	_build_aquascape_palette()
	
	if portal_toggle != null:
		portal_toggle.pressed.connect(_toggle_portal)
	if portal_display != null:
		# PiP zooms the main tank render — no second 3D camera needed.
		portal_display.texture = sub_viewport.get_texture()
		if portal_display.material is ShaderMaterial:
			_portal_mat = portal_display.material as ShaderMaterial
	if portal_viewport != null:
		portal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# ---- Top HUD: build stat chips, apply responsive layout, watch resizes ----
	_build_hud_chips()
	_apply_hud_layout()
	get_viewport().size_changed.connect(_apply_hud_layout)

	# ---- Mobile setup ----
	if _is_mobile():
		_pick_device_tier_if_unset()
		_setup_mobile_ui()
	# Always apply the fps cap (works on desktop too, so the user can choose
	# a 60-fps lock to reduce GPU heat). Mobile gets a 60-fps default on first
	# launch if no cap has been set.
	_apply_fps_cap()
	# Welcome-back toast and time-stamp persistence — only meaningful on
	# subsequent launches, but cheap to set up unconditionally.
	_show_welcome_back_if_returning()
	# Tank state restore. Defers a frame so world.gd._ready has fully run
	# (substrate exists, roots are set up, plants_root etc. are wired) before
	# we start spawning entities into it.
	if _sim != null:
		call_deferred("_try_load_saved_state")
		
	_build_portal_info_ui()


func _toggle_portal() -> void:
	_portal_open = not _portal_open
	if portal_container != null:
		portal_container.visible = _portal_open
	if not _portal_open:
		_portal_target = null
	if portal_hint != null:
		portal_hint.visible = _portal_target == null
	if _portal_open:
		_update_portal_pip()
	print_verbose("[vivarium] PiP portal %s" % ("OPEN" if _portal_open else "CLOSED"))


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
	sub_viewport.msaa_3d = int(cfg.msaa) as Viewport.MSAA
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
		# Keep volumetric fog off on Metal/macOS — it was a major fence-timeout source.
		we.environment.volumetric_fog_enabled = false
		we.environment.volumetric_fog_density = float(cfg.fog_density)
		we.environment.volumetric_fog_anisotropy = float(cfg.fog_anisotropy)
		we.environment.volumetric_fog_ambient_inject = float(cfg.fog_ambient_inject)


func _process(dt: float) -> void:
	# Tick the aquascape brush cooldown so drag-painting deposits voxels
	# at a steady rate regardless of frame timing.
	_paint_cooldown = maxf(0.0, _paint_cooldown - dt)

	# Top-HUD idle-dim. Mirrors MobileHUD: after HUD_IDLE_DIM_SECONDS of no
	# input, fade the top bar so it stops competing with the scene.
	# _notify_hud_input() (called from _input + touch handlers) resets this.
	_hud_idle_seconds += dt
	if top_hud != null and _hud_idle_seconds > HUD_IDLE_DIM_SECONDS:
		if top_hud.modulate != HUD_DIM_MODULATE:
			top_hud.modulate = HUD_DIM_MODULATE

	# Periodic autosave. Only ticks the accumulator when we're actually
	# playing (not aquascape-paused, not manually paused) so the 5-minute
	# clock measures user-attention not wall-clock.
	if _sim != null and not _aquascape_mode and float(_sim.time_scale) > 0.0:
		_autosave_accum += dt
		if _autosave_accum >= AUTOSAVE_INTERVAL_S:
			_autosave_accum = 0.0
			save_active_tank(not get_window().has_focus())
	
	# ---- Touch: long-press detection (runs every frame while finger is down) ----
	if _touches.size() == 1 and not _long_press_fired:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - _tap_start_time
		if elapsed >= LONG_PRESS_TIME and _tap_moved < TAP_MAX_MOVE:
			_long_press_fired = true
			# Aquascape mode: pop a radial tool picker centered on the finger.
			# Normal mode: keep the existing auto-orbit toggle. Painting that
			# was started on touch-down gets cancelled so the menu doesn't
			# also drop a voxel.
			if _aquascape_mode:
				_drag_mode = ""
				_wood_drag = null
				_drag_cluster.clear()
				_wood_drag_last_hit = INVALID_HIT
				_haptic(22)
				_show_radial_menu(_tap_start_pos)
			else:
				_auto_orbit = not _auto_orbit
				_haptic(15)
				print_verbose("[vivarium] long-press: auto-orbit %s" % ("ON" if _auto_orbit else "OFF"))
	
	# ---- Mouse input (skipped when touch is active to avoid double-fire) ----
	if _is_touch_active():
		# Touch is being handled in _input(); skip mouse polling entirely.
		# Still run keyboard shortcuts, follow-cam, auto-orbit, etc. below.
		pass
	else:
		_process_mouse_input(dt)
	
	# Follow-cam: smoothly track the followed creature. Use the
	# frame-rate-independent lerp formula `1 - exp(-k*dt)` instead of the
	# naive `clampf(dt * k, ...)` so the follow feels equally smooth at 30,
	# 60, or 144 FPS. With the old form, at 30 FPS the lerp weight was 0.1
	# (jumpy), at 144 FPS it was 0.02 (sluggish) — same `k=3` produced
	# very different behavior on different displays.
	if _follow_target != null:
		if not is_instance_valid(_follow_target):
			_follow_target = null
		else:
			var t: float = 1.0 - exp(-3.0 * dt)
			target = target.lerp(_follow_target.global_position, t)
			_apply_camera()
			
	if _portal_open or _follow_target != null or (_portal_info_panel != null and _portal_info_panel.visible):
		_update_portal_pip()

	# WASD pan target along view direction (desktop only — no keyboard on mobile).
	if not _is_touch_active():
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
				_follow_target = null
				_auto_orbit = false
				moved = true
			if moved:
				_apply_camera()

# Extracted mouse-polling logic. Called from _process() only when touch
# is NOT active (prevents emulated mouse events from fighting touch).
func _process_mouse_input(dt: float) -> void:
	var mouse_now: Vector2 = get_window().get_mouse_position()
	var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	var rmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var pan_modifier: bool = Input.is_key_pressed(KEY_SHIFT) \
		or Input.is_key_pressed(KEY_SPACE)
	var any_btn: bool = lmb or mmb or rmb
	if not any_btn:
		_suppress_drag_until_release = false

	if any_btn and not _orbiting and not _suppress_drag_until_release:
		_orbiting = true
		_last_mouse = mouse_now
		_drag_start = mouse_now
		_drag_total = 0.0
		if mmb:
			_drag_mode = "pan"
			_drag_button = MOUSE_BUTTON_MIDDLE
		elif rmb:
			_drag_button = MOUSE_BUTTON_RIGHT
			_drag_mode = "orbit" if _aquascape_mode else "dolly"
		else:
			_drag_button = MOUSE_BUTTON_LEFT
			if pan_modifier:
				_drag_mode = "pan"
			elif _aquascape_mode:
				if _begin_aquascape_drag(mouse_now):
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
		_drag_cluster.clear()
		_wood_drag_last_hit = INVALID_HIT
		_drag_mode = ""
		_drag_button = 0

	if _orbiting:
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
					radius = clampf(radius * (1.0 + delta.y * DOLLY_MOUSE_SENSITIVITY),
						MIN_RADIUS, MAX_RADIUS)
					_apply_camera()
				"paint":
					if _paint_cooldown <= 0.0:
						_aquascape_place(mouse_now)
						_paint_cooldown = PAINT_INTERVAL
				"wood_drag":
					_drag_hardscape_piece(mouse_now)
				_:
					yaw -= delta.x * SENSITIVITY
					pitch -= delta.y * SENSITIVITY
					pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
					_apply_camera()


	# G toggles auto-orbit. (Space used to do this; it's now reserved as the
	# hold-to-pan modifier, matching Photoshop / Figma muscle memory.)
	if not _is_touch_active():
		var g_now: bool = Input.is_key_pressed(KEY_G)
		if g_now and not _auto_orbit_was_pressed:
			_auto_orbit = not _auto_orbit
		_auto_orbit_was_pressed = g_now
	if _auto_orbit:
		yaw += AUTO_ORBIT_SPEED * dt
		_apply_camera()

	# Edge-triggered shortcuts (keyboard only — mobile gets on-screen buttons).
	if not _is_touch_active():
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
	# current mouse/touch position, ONLY when in aquascape mode.
	var cursor_pos: Vector2 = _touches.values()[0] if _touches.size() > 0 else get_window().get_mouse_position()
	if _aquascape_mode:
		_update_aquascape_preview(cursor_pos)

	# Timelapse: dump a frame every TIMELAPSE_INTERVAL real seconds.
	if _timelapse_active:
		_timelapse_accum += dt
		if _timelapse_accum >= TIMELAPSE_INTERVAL:
			_timelapse_accum = 0.0
			var frame_path: String = "%s/frame_%05d.png" % [_timelapse_dir, _timelapse_index]
			_timelapse_index += 1
			_request_viewport_image(_save_timelapse_frame.bind(frame_path))

	# Keep the speed / day-phase chip live without rebuilding all 9 chips every
	# frame. The full header re-renders on stats_changed (1 Hz); here we only
	# touch the UI when the state text actually changes (speed nudge, pause,
	# phase rollover), so idle frames cost two string builds and a compare.
	_refresh_state_chip()


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
	_haptic(12)


func _set_time_scale(s: float) -> void:
	if _sim == null:
		return
	_sim.time_scale = s
	_saved_time_scale = s
	_haptic(12)


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
	_request_viewport_image(_finish_photo)


func _finish_photo(img: Image) -> void:
	var dir: String = OS.get_user_data_dir() + "/captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = dir + "/vivarium_" + ts + ".png"
	img.save_png(path)
	print_verbose("[vivarium] photo saved: ", path)
	_haptic(25)
	_show_photo_toast(path)


func _save_timelapse_frame(img: Image, frame_path: String) -> void:
	img.save_png(frame_path)


# Defer GPU readback until after the viewport finishes presenting.
func _request_viewport_image(on_ready: Callable) -> void:
	if sub_viewport == null or not is_instance_valid(sub_viewport):
		return
	var frame: int = Engine.get_process_frames()
	if _viewport_capture_busy \
			or frame - _last_viewport_capture_frame < VIEWPORT_CAPTURE_FRAME_GAP:
		return
	_viewport_capture_busy = true
	_run_viewport_capture(on_ready)


func _run_viewport_capture(on_ready: Callable) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = null
	if sub_viewport != null and is_instance_valid(sub_viewport):
		var tex: ViewportTexture = sub_viewport.get_texture()
		if tex != null:
			img = tex.get_image()
	_viewport_capture_busy = false
	_last_viewport_capture_frame = Engine.get_process_frames()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		on_ready.call(img)


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
		print_verbose("[vivarium] timelapse stopped: ", _timelapse_index, " frames in ", _timelapse_dir)
	else:
		var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		_timelapse_dir = OS.get_user_data_dir() + "/captures/timelapse_" + ts
		DirAccess.make_dir_recursive_absolute(_timelapse_dir)
		_timelapse_index = 0
		_timelapse_accum = 0.0
		_timelapse_active = true
		print_verbose("[vivarium] timelapse started: ", _timelapse_dir)


# ---- Follow-cam ----

func _clear_follow() -> void:
	_follow_target = null
	_portal_target = null
	_update_portal_pip()


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


func _pick_creature_at_viewport(sv_pos: Vector2, creatures: Array) -> Node3D:
	if camera == null:
		return null
	# Pick radius: portal mode is most permissive; touch input gets a
	# fatter target than mouse because fingers are imprecise; otherwise the
	# desktop default. This makes small fish actually tappable on a phone
	# without sacrificing precision when a mouse is in use.
	var radius_px: float
	if _portal_open:
		radius_px = PORTAL_PICK_RADIUS_PX
	elif _is_touch_active():
		radius_px = PICK_RADIUS_PX_TOUCH
	else:
		radius_px = PICK_RADIUS_PX
	var best: Node3D = null
	var best_score: float = radius_px
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	for c in creatures:
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


func _pick_creature_from_display(creatures: Array) -> Node3D:
	if display == null or sub_viewport == null:
		return null
	var sv_pos: Vector2 = _window_mouse_to_viewport(get_viewport().get_mouse_position())
	return _pick_creature_at_viewport(sv_pos, creatures)


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


var _portal_label_skip: int = 0

func _update_portal_pip() -> void:
	if camera == null:
		return
		
	var target_node: Node3D = null
	if _portal_open:
		target_node = _portal_target
	else:
		target_node = _follow_target
		
	if target_node == null or not is_instance_valid(target_node):
		# No target to track
		if not _portal_open:
			if portal_container != null:
				portal_container.visible = false
			if _portal_info_panel != null:
				_portal_info_panel.visible = false
			return
		else:
			# Portal is open but has no target
			if portal_container != null:
				portal_container.visible = true
			if portal_display != null:
				portal_display.visible = true
				if _portal_mat != null:
					_portal_mat.set_shader_parameter("center_uv", Vector2(0.5, 0.5))
			if portal_hint != null:
				portal_hint.visible = true
			if _portal_info_panel != null:
				_portal_info_panel.visible = false
			return

	# We have a valid target!
	if portal_container != null:
		portal_container.visible = true
		
	if _portal_open:
		if portal_display != null:
			portal_display.visible = true
		if portal_hint != null:
			portal_hint.visible = false
			
		if _portal_mat != null:
			if not camera.is_position_behind(target_node.global_position):
				var screen_pt: Vector2 = camera.unproject_position(target_node.global_position)
				var center_uv: Vector2 = Vector2(
					screen_pt.x / float(sub_viewport.size.x),
					screen_pt.y / float(sub_viewport.size.y),
				)
				_portal_mat.set_shader_parameter("center_uv", center_uv)
				_portal_mat.set_shader_parameter("zoom", PORTAL_ZOOM)
				
		if _portal_info_panel != null:
			_portal_info_panel.offset_top = 196.0
			_portal_info_panel.offset_bottom = 292.0
			_portal_info_panel.visible = true
	else:
		if portal_display != null:
			portal_display.visible = false
		if portal_hint != null:
			portal_hint.visible = false
			
		if _portal_info_panel != null:
			_portal_info_panel.offset_top = 0.0
			_portal_info_panel.offset_bottom = 96.0
			_portal_info_panel.visible = true

	# Update the dynamic creature stats and lineage labels. The center_uv zoom
	# above is updated every frame so portal tracking stays smooth, but the
	# name / lineage / age / hunger text barely changes — rebuild those strings
	# at ~10 Hz instead of every frame.
	_portal_label_skip = (_portal_label_skip + 1) % 6
	if _portal_label_skip == 0 and _portal_info_panel != null and _portal_info_panel.visible:
		# Name
		var c_name := ""
		if target_node.get("fish_name") != null and String(target_node.get("fish_name")) != "":
			c_name = String(target_node.get("fish_name"))
		elif target_node.get("shrimp_name") != null and String(target_node.get("shrimp_name")) != "":
			c_name = String(target_node.get("shrimp_name"))
		elif target_node.get("_display_name") != null and String(target_node.get("_display_name")) != "":
			c_name = String(target_node.get("_display_name"))
		else:
			c_name = _creature_label(target_node).capitalize()
		_portal_name_lbl.text = c_name
		
		# Lineage (Generation & Parents)
		var spec := _creature_label(target_node).capitalize()
		var gen := 0
		if target_node.get("generation") != null:
			gen = int(target_node.generation)
			
		var lin := "Founders"
		if target_node.get("parent_lineage") != null and String(target_node.get("parent_lineage")) != "":
			lin = String(target_node.get("parent_lineage"))
		_portal_lineage_lbl.text = "%s · Gen %d\nFrom: %s" % [spec, gen, lin]
		
		# Stats (Age, hunger, sex, and sterile flag)
		var age_str := ""
		if target_node.get("age") != null:
			var sec: float = target_node.age
			var m := int(sec / 60.0)
			var s := int(sec) % 60
			if m > 0:
				age_str = "%dm %ds" % [m, s]
			else:
				age_str = "%ds" % s
		else:
			age_str = "N/A"
			
		var hunger_val := 0.0
		if target_node.get("hunger") != null:
			hunger_val = float(target_node.hunger)
		var hunger_pct := int(clampf(hunger_val, 0.0, 1.0) * 100.0)
		
		var sex_str := ""
		if target_node.get("sex") != null:
			sex_str = " · Male" if target_node.sex == 0 else " · Female"
			
		var sterile_str := ""
		if target_node.get("sterile") != null and bool(target_node.sterile):
			sterile_str = " · Sterile"
			
		_portal_stats_lbl.text = "Age: %s · Hunger: %d%%%s%s" % [age_str, hunger_pct, sex_str, sterile_str]


func _build_portal_info_ui() -> void:
	if portal_container == null:
		return
		
	# Expand the portal container size so the text panel fits cleanly
	portal_container.offset_bottom = 340.0
	
	_portal_info_panel = PanelContainer.new()
	_portal_info_panel.name = "PortalInfoPanel"
	_portal_info_panel.anchors_preset = Control.PRESET_BOTTOM_WIDE
	_portal_info_panel.offset_top = 196.0
	_portal_info_panel.offset_bottom = 292.0
	_portal_info_panel.offset_left = 0
	_portal_info_panel.offset_right = 0
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.85)
	style.border_color = Color(0.35, 0.45, 0.6, 0.5)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_portal_info_panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_portal_info_panel.add_child(vbox)
	
	_portal_name_lbl = Label.new()
	_portal_name_lbl.text = "Unknown"
	_portal_name_lbl.add_theme_font_size_override("font_size", 12)
	_portal_name_lbl.add_theme_color_override("font_color", Color8(255, 215, 80))
	_portal_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_portal_name_lbl)
	
	_portal_lineage_lbl = Label.new()
	_portal_lineage_lbl.text = "Gen 0 · Founders"
	_portal_lineage_lbl.add_theme_font_size_override("font_size", 9)
	_portal_lineage_lbl.add_theme_color_override("font_color", Color8(200, 210, 225))
	_portal_lineage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_portal_lineage_lbl)
	
	_portal_stats_lbl = Label.new()
	_portal_stats_lbl.text = "Age: 0s · Hunger: 0%"
	_portal_stats_lbl.add_theme_font_size_override("font_size", 9)
	_portal_stats_lbl.add_theme_color_override("font_color", Color8(150, 230, 150))
	_portal_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_portal_stats_lbl)
	
	portal_container.add_child(_portal_info_panel)
	_portal_info_panel.visible = false


func _assign_creature_target(creature: Node3D) -> void:
	if _portal_open:
		_portal_target = creature
		_update_portal_pip()
		print_verbose("[vivarium] portal tracking %s" % _creature_label(creature))
	else:
		_follow_target = creature
		_update_portal_pip()
		print_verbose("[vivarium] following %s" % _creature_label(creature))


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
	var creatures: Array = _gather_creatures()
	var picked: Node3D = _pick_creature_from_display(creatures)
	if picked == null:
		if _portal_open or creatures.size() > 0:
			print_verbose("[vivarium] pick miss: creatures=%d mouse=%s sv=%s" % [
				creatures.size(),
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
		print_verbose("[vivarium] aquascape ON. 1 dirt / 2 stone / 3 wood / 4 dig; drag a piece to move it; BACKSPACE undo; B exit.")
	else:
		if _sim != null:
			_sim.time_scale = _aquascape_saved_time_scale
		if _aquascape_preview != null:
			_aquascape_preview.visible = false
		if aquascape_palette != null:
			aquascape_palette.visible = false
		print_verbose("[vivarium] aquascape OFF (resumed at %gx)" % _aquascape_saved_time_scale)
	# Notify mobile HUD to show/hide the undo button.
	if _mobile_hud != null and _mobile_hud.has_method("set_aquascape_mode"):
		_mobile_hud.set_aquascape_mode(_aquascape_mode)


# ---- Walkthrough hooks (called by walkthrough.gd) ----

func _maybe_start_walkthrough() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.walkthrough_pending):
		return
	# Consume the flag so it doesn't re-trigger on the next scene load.
	cfg.walkthrough_pending = false
	if walkthrough_overlay != null and walkthrough_overlay.has_method("begin"):
		walkthrough_overlay.begin()


func wt_pause_sim(on: bool) -> void:
	if _sim == null:
		return
	if on:
		var cur: float = float(_sim.time_scale)
		_wt_saved_time_scale = cur if cur > 0.0 else 1.0
		_sim.time_scale = 0.0
	else:
		_sim.time_scale = _wt_saved_time_scale


func wt_set_aquascape(on: bool) -> void:
	if _aquascape_mode != on:
		_toggle_aquascape()


func wt_open_creator(kind_str: String) -> void:
	if creature_creator_panel != null and creature_creator_panel.has_method("open_to_kind"):
		creature_creator_panel.open_to_kind(kind_str)


func wt_close_creator() -> void:
	if creature_creator_panel != null and creature_creator_panel.visible \
			and creature_creator_panel.has_method("close"):
		creature_creator_panel.close()


func wt_counts() -> Dictionary:
	var d: Dictionary = {"fish": 0, "shrimp": 0, "snail": 0, "plant": 0}
	if _sim == null:
		return d
	d["fish"] = _sim.fish.size()
	d["shrimp"] = _sim.shrimp.size()
	d["plant"] = _sim.plants.size()
	var sr: Variant = _sim.get("snails_root")
	if sr != null and is_instance_valid(sr):
		var n: int = 0
		for c in (sr as Node).get_children():
			var scr: Script = c.get_script()
			if scr != null and scr.resource_path.ends_with("snail.gd"):
				n += 1
		d["snail"] = n
	return d


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
func _hardscape_node() -> Node3D:
	# The Hardscape container holds all editable pieces (procedural driftwood/
	# rocks + player-placed stones and logs). Falls back to world root if it
	# wasn't built (shouldn't happen — _build_hardscape always makes it).
	if world == null:
		return null
	var hs: Node = world.get_node_or_null("Hardscape")
	return (hs as Node3D) if hs != null else world


# Pick a draggable player-placed piece under the cursor: wood logs and
# stones. Dirt is terrain (only diggable). Procedural driftwood/rocks are
# handled separately by _gather_procedural_cluster (they aren't grouped into
# single nodes, so fish per-voxel clearance keeps working). Returns null if
# nothing placed is hit.
func _pick_hardscape_piece(mouse_pos: Vector2) -> Node3D:
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
		if String(v.get_meta("aquascape_tool", "")) == "dirt":
			continue
		var radius: float = 1.6 if String(v.get_meta("aquascape_tool", "")) == "wood" else 0.9
		var to_c: Vector3 = v.global_position - origin
		var t: float = to_c.dot(dir)
		if t < 0.0:
			continue
		var closest: Vector3 = origin + dir * t
		var perp_sq: float = (closest - v.global_position).length_squared()
		if perp_sq < radius * radius and t < best_t:
			best_t = t
			best = v
	return best


# Collect the loose procedural hardscape voxels (driftwood / rocks) within a
# small XZ radius of a point. These aren't grouped into one node, so we drag
# them together as an ad-hoc cluster for the duration of one drag.
func _gather_procedural_cluster(hit: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var hs: Node3D = _hardscape_node()
	if hs == null:
		return out
	const CLUSTER_R: float = 1.2
	for child in hs.get_children():
		if not (child is MeshInstance3D) or not is_instance_valid(child):
			continue
		if _aquascape_placed.has(child):
			continue  # player placement - handled by _pick_hardscape_piece
		var gp: Vector3 = (child as Node3D).global_position
		if Vector2(gp.x - hit.x, gp.z - hit.z).length() < CLUSTER_R:
			out.append(child)
	return out


# Try to start dragging hardscape at the cursor: a placed piece first, then a
# procedural cluster. Returns true if a drag began.
func _begin_aquascape_drag(pos: Vector2) -> bool:
	if _aquascape_tool == "dig":
		return false
	var picked: Node3D = _pick_hardscape_piece(pos)
	if picked != null:
		_wood_drag = picked
		_drag_cluster.clear()
		_wood_drag_y_offset = picked.global_position.y - _substrate_top_y()
		_wood_drag_last_hit = _project_to_substrate(pos)
		return true
	var hit: Vector3 = _project_to_substrate(pos)
	if hit != INVALID_HIT:
		var cluster: Array[Node3D] = _gather_procedural_cluster(hit)
		if not cluster.is_empty():
			_wood_drag = null
			_drag_cluster = cluster
			_wood_drag_last_hit = hit
			return true
	return false


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


# Project cursor onto the water surface plane (y = WATER_HEIGHT). Symmetric
# with _project_to_substrate but hits the *top* of the water. Used by the
# Ctrl+LMB tap-to-feed gesture so flakes drop at the precise surface point
# the player tapped, then bob there for 8 sim-seconds before falling
# (waste_particle.gd handles the bob).
func _project_to_surface(mouse_pos: Vector2) -> Vector3:
	if camera == null or world == null:
		return INVALID_HIT
	var sv_pos: Vector2 = _window_mouse_to_viewport(mouse_pos)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos)
	var surface_y: float = float(world.get("WATER_HEIGHT")) if world.get("WATER_HEIGHT") != null else 6.5
	if dir.y > -0.01:
		return INVALID_HIT
	var t: float = (surface_y - origin.y) / dir.y
	if t < 0.0:
		return INVALID_HIT
	var hit: Vector3 = origin + dir * t
	if world.has_method("is_inside_tank"):
		if not world.is_inside_tank(hit.x, hit.z, 0.3):
			return INVALID_HIT
	return hit


# Tap-glass startle. The player clicked somewhere in the tank but didn't
# pick a creature and didn't drop food. Project the click into the tank
# and trigger a brief flee burst on any fish within STARTLE_RADIUS. Real
# fish do exactly this when something thuds on the glass — the visible
# "the school just bolted" response sells the interactivity of the tank
# without needing a separate UI affordance.
const STARTLE_RADIUS_SQ: float = 9.0  # 3-unit blast radius
func _startle_fish_near_tap(mouse_pos: Vector2) -> void:
	if _sim == null:
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		return
	for f in _sim.fish:
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		if f.position.distance_squared_to(hit) > STARTLE_RADIUS_SQ:
			continue
		# Inject a flee burst away from the tap point. We poke the
		# burst_remaining + heading_offset directly because there's no
		# event channel for "external scare" — keeps the change local
		# to main.gd without modifying fish.gd's tick signature.
		var away: Vector3 = (f.position - hit)
		if away.length_squared() < 1e-4:
			away = Vector3(randf_range(-1, 1), 0.1, randf_range(-1, 1))
		away = away.normalized()
		f.burst_remaining = 0.5
		f.heading_offset = away * 1.4
		f._startle_heading = away
		f._startle_remaining = 0.4


# Drop a cluster of 4-6 food pellets at the surface point under the cursor.
# Returns true if the cluster spawned (used by the caller to suppress orbit
# drag for that gesture so the camera doesn't yank during feeding).
# Each pellet bobs on the surface for ~8s before sinking — exactly like
# real flake food. Fish converge on it via the existing food-pickup tier.
func _drop_food_at_cursor(mouse_pos: Vector2) -> bool:
	if _sim == null:
		return false
	var hit: Vector3 = _project_to_surface(mouse_pos)
	if hit == INVALID_HIT:
		return false
	var count: int = randi_range(4, 6)
	for i in count:
		# Small jitter so the cluster reads as a sprinkle, not a stack.
		var jx: float = randf_range(-0.18, 0.18)
		var jz: float = randf_range(-0.18, 0.18)
		var pos: Vector3 = Vector3(hit.x + jx, hit.y - 0.02, hit.z + jz)
		_sim._spawn_waste(pos, 0.45, 3)  # 3 = KIND_FOOD
	print_verbose("[vivarium] tap-feed: %d flakes at %s" % [count, hit])
	return true


func _aquascape_place(mouse_pos: Vector2) -> void:
	if world == null:
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	# Refuse to place when the cursor isn't over a valid substrate cell -
	# this is the fix for "dirt placed in empty space when clicking outside
	# the tank glass".
	if hit == INVALID_HIT:
		print_verbose("[vivarium] aquascape: cursor not over tank, skipping placement")
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
	# Parent under Hardscape so the piece is real hardscape: fish/fry hide
	# behavior, plant-spawn avoidance, and snail retreat all read this
	# container, and the occupancy grid keeps creatures from clipping it.
	# add_child first, then global_position (Godot 4 transform ordering).
	var hs := _hardscape_node()
	hs.add_child(mi)
	mi.global_position = hit
	mi.set_meta("aquascape_tool", _aquascape_tool)
	_aquascape_placed.append(mi)
	if world.has_method("_mark_hardscape_occupancy"):
		world._mark_hardscape_occupancy(hit, voxel_size)
	print_verbose("[vivarium] placed %s at %s (total %d)" % [_aquascape_tool, hit, _aquascape_placed.size()])


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
	var log_node := Node3D.new()
	log_node.name = "AquaLog"
	hardscape.add_child(log_node)
	log_node.global_position = base + Vector3(0, 0.35, 0)
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
		log_node.add_child(seg)
		seg.position = offset
	log_node.set_meta("aquascape_tool", "wood")
	_aquascape_placed.append(log_node)
	print_verbose("[vivarium] placed driftwood log at %s" % base)


func _column_top_y(x: float, z: float, exclude: Node = null) -> float:
	# Find the topmost Y in this XZ column by scanning every hardscape voxel
	# (procedural driftwood/rocks + player-placed dirt/stone/wood, which all
	# live under the Hardscape container). `exclude` skips a node + its
	# subtree so a piece being dragged doesn't stack on top of itself.
	# Returns the world-space Y of the top face of the topmost voxel.
	var top: float = _substrate_top_y()
	var hs: Node3D = _hardscape_node()
	if hs != null:
		top = _scan_column_top(hs, x, z, exclude, top)
	# Legacy: any placement still parented to the world root (old saves).
	for v in _aquascape_placed:
		if not is_instance_valid(v) or v == exclude:
			continue
		if v.get_parent() == hs:
			continue  # already counted by the recursive scan
		var gp: Vector3 = v.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var size_y: float = 0.5
			if v is MeshInstance3D:
				var bm := (v as MeshInstance3D).mesh as BoxMesh
				if bm != null:
					size_y = bm.size.y
			top = maxf(top, gp.y + size_y * 0.5)
	return top


func _scan_column_top(node: Node, x: float, z: float, exclude: Node, top: float) -> float:
	if node == exclude:
		return top
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var gp: Vector3 = mi.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var sy: float = 0.5
			var bm := mi.mesh as BoxMesh
			if bm != null:
				sy = bm.size.y
			top = maxf(top, gp.y + sy * 0.5)
	for c in node.get_children():
		top = _scan_column_top(c, x, z, exclude, top)
	return top


# Move the currently-grabbed hardscape piece by the cursor delta (so big
# procedural pieces don't teleport when picked) and rest it on the terrain
# column beneath, excluding itself so it doesn't climb its own height.
func _drag_hardscape_piece(mouse_pos: Vector2) -> void:
	var has_single: bool = _wood_drag != null and is_instance_valid(_wood_drag)
	if not has_single and _drag_cluster.is_empty():
		return
	var hit: Vector3 = _project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		return
	if _wood_drag_last_hit == INVALID_HIT:
		_wood_drag_last_hit = hit
	var d: Vector3 = hit - _wood_drag_last_hit
	_wood_drag_last_hit = hit
	var dxz: Vector3 = Vector3(d.x, 0.0, d.z)
	if has_single:
		# Single placed piece: follow terrain height (excluding itself).
		var np: Vector3 = _wood_drag.global_position + dxz
		np.y = _column_top_y(np.x, np.z, _wood_drag) + _wood_drag_y_offset
		_wood_drag.global_position = np
	else:
		# Procedural cluster: translate horizontally as a rigid clump.
		for v in _drag_cluster:
			if is_instance_valid(v):
				v.global_position += dxz


func _aquascape_dig(hit: Vector3) -> void:
	# Chip away the topmost hardscape voxel at this cursor XZ — works on both
	# player placements AND the procedural driftwood / rocks (they all live
	# under Hardscape). Grouped pieces lose one voxel per dig.
	var hs: Node3D = _hardscape_node()
	if hs == null:
		return
	var acc: Dictionary = {"node": null, "y": -INF}
	_scan_top_voxel(hs, hit.x, hit.z, acc)
	var best: Node = acc["node"]
	if best == null:
		# Fall back to any legacy world-parented placement.
		var by: float = -INF
		for v in _aquascape_placed:
			if not is_instance_valid(v):
				continue
			var gp: Vector3 = v.global_position
			if absf(gp.x - hit.x) < 0.45 and absf(gp.z - hit.z) < 0.45 and gp.y > by:
				by = gp.y
				best = v
	if best == null:
		return
	_aquascape_placed.erase(best)
	best.queue_free()
	_haptic(12)


func _scan_top_voxel(node: Node, x: float, z: float, acc: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var gp: Vector3 = mi.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var sy: float = 0.5
			var bm := mi.mesh as BoxMesh
			if bm != null:
				sy = bm.size.y
			var topy: float = gp.y + sy * 0.5
			if topy > float(acc["y"]):
				acc["y"] = topy
				acc["node"] = mi
	for c in node.get_children():
		_scan_top_voxel(c, x, z, acc)


# ---- Aquascape save / load ----
# _aquascape_placed holds two kinds of nodes:
#   - MeshInstance3D (single voxel, kind "voxel"): dirt or stone
#   - Node3D container (kind "log"): wood, with N MeshInstance3D children
# Both have set_meta("aquascape_tool", "dirt"|"stone"|"wood") on the root.
func _aquascape_to_save_arr() -> Array:
	var out: Array = []
	for v in _aquascape_placed:
		if not is_instance_valid(v):
			continue
		var tool: String = String(v.get_meta("aquascape_tool", ""))
		if v is MeshInstance3D:
			var mi: MeshInstance3D = v
			var bm: BoxMesh = mi.mesh as BoxMesh
			var color: Color = Color.WHITE
			if mi.material_override is BaseMaterial3D:
				color = (mi.material_override as BaseMaterial3D).albedo_color
			out.append({
				"kind": "voxel",
				"tool": tool,
				"pos": SaveHelpers.vec3_to_array(mi.global_position),
				"size": SaveHelpers.vec3_to_array(bm.size if bm != null else Vector3.ONE),
				"color": SaveHelpers.color_to_array(color),
			})
		else:
			# Log: walk children to capture each segment.
			var segs: Array = []
			for child in v.get_children():
				if not (child is MeshInstance3D):
					continue
				var seg: MeshInstance3D = child
				var seg_bm: BoxMesh = seg.mesh as BoxMesh
				var seg_color: Color = Color.WHITE
				if seg.material_override is BaseMaterial3D:
					seg_color = (seg.material_override as BaseMaterial3D).albedo_color
				segs.append({
					"offset": SaveHelpers.vec3_to_array(seg.position),
					"size": SaveHelpers.vec3_to_array(seg_bm.size if seg_bm != null else Vector3.ONE),
					"color": SaveHelpers.color_to_array(seg_color),
				})
			out.append({
				"kind": "log",
				"tool": tool,
				"pos": SaveHelpers.vec3_to_array(v.global_position),
				"segments": segs,
			})
	return out


# Restore aquascape from a previously-saved array. Builds nodes with the
# exact saved positions/colors/sizes — no procedural jitter.
func _restore_aquascape(arr: Array) -> void:
	if world == null:
		return
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	var hardscape := world.get_node_or_null("Hardscape")
	if hardscape == null:
		hardscape = world
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var kind: String = String(entry.get("kind", ""))
		var tool: String = String(entry.get("tool", ""))
		var pos: Vector3 = SaveHelpers.array_to_vec3(entry.get("pos", []), Vector3.ZERO)
		if kind == "voxel":
			var size: Vector3 = SaveHelpers.array_to_vec3(entry.get("size", []), Vector3(0.5, 0.5, 0.5))
			var color: Color = SaveHelpers.array_to_color(entry.get("color", []), Color.WHITE)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			if voxel_mat_script != null:
				mi.material_override = voxel_mat_script.make(color)
			else:
				var sm := StandardMaterial3D.new()
				sm.albedo_color = color
				mi.material_override = sm
			hardscape.add_child(mi)
			mi.global_position = pos
			mi.set_meta("aquascape_tool", tool)
			_aquascape_placed.append(mi)
			if world.has_method("_mark_hardscape_occupancy"):
				world._mark_hardscape_occupancy(pos, size)
		elif kind == "log":
			var log_node := Node3D.new()
			log_node.name = "AquaLog"
			hardscape.add_child(log_node)
			log_node.global_position = pos
			for seg_entry in entry.get("segments", []):
				if not (seg_entry is Dictionary):
					continue
				var seg := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = SaveHelpers.array_to_vec3(seg_entry.get("size", []), Vector3(0.7, 0.6, 0.7))
				seg.mesh = bm
				var c: Color = SaveHelpers.array_to_color(seg_entry.get("color", []), Color.WHITE)
				if voxel_mat_script != null:
					seg.material_override = voxel_mat_script.make(c)
				else:
					var sm := StandardMaterial3D.new()
					sm.albedo_color = c
					seg.material_override = sm
				log_node.add_child(seg)
				seg.position = SaveHelpers.array_to_vec3(seg_entry.get("offset", []), Vector3.ZERO)
			log_node.set_meta("aquascape_tool", tool)
			_aquascape_placed.append(log_node)


func _aquascape_undo() -> void:
	if not _aquascape_mode:
		return
	while _aquascape_placed.size() > 0:
		var v: Node3D = _aquascape_placed.pop_back()
		if is_instance_valid(v):
			v.queue_free()
			_haptic(15)
			return


# Scroll wheel + creature clicks come through as events (not reliable via polling).
func _input(event: InputEvent) -> void:
	# Any input keeps the top HUD lit. Cheap, runs once per input event.
	if event is InputEventMouseMotion or event is InputEventMouseButton or \
			event is InputEventScreenTouch or event is InputEventScreenDrag or \
			event is InputEventKey:
		_notify_hud_input()

	if event.is_action_pressed("ui_cancel"):
		if _dismiss_blocking_overlays():
			get_viewport().set_input_as_handled()
			return

	# ---- Touch events ----
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
		return
	
	# ---- Mouse events (skip when touch is active) ----
	if _is_touch_active():
		return
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
				# Close history / story popups on any click outside them
				# (chips themselves go through their own gui_input handler
				# before this runs).
				if _history_popup != null and _history_popup.visible \
						and not _history_popup.get_global_rect().has_point(mb.position):
					_history_popup.visible = false
				if _story_popup != null and _story_popup.visible \
						and not _story_popup.get_global_rect().has_point(mb.position):
					_story_popup.visible = false
				# Ctrl+LMB = tap-to-feed. Projects the cursor onto the water
				# surface and drops a small cluster of food pellets there;
				# nearby fish converge from below. Suppresses orbit so the
				# camera doesn't yank during the feed gesture.
				if Input.is_key_pressed(KEY_CTRL) \
						or Input.is_key_pressed(KEY_META):
					if _drop_food_at_cursor(mb.position):
						_suppress_drag_until_release = true
				# If the click hit a creature, suppress the polled orbit drag
				# for this LMB gesture — without this, every successful pick
				# also yanked the camera as the user moved the cursor.
				elif _click_targets_creature():
					_suppress_drag_until_release = true
				else:
					# Tap-glass: the click hit empty water (or the glass).
					# Project to substrate and spook any fish within the
					# tap radius — real fish bolt when something thuds on
					# the glass. We don't return / consume the gesture,
					# so the orbit drag still works if the player intended
					# to drag the camera (a true tap = small drag_total).
					_startle_fish_near_tap(mb.position)


# ---- Touch gesture handlers ----

func _handle_screen_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		# Finger down.
		_touches[ev.index] = ev.position
		_touch_prev[ev.index] = ev.position
		_touch_active = true
		# Keep the mobile HUD lit while the user is interacting.
		if _mobile_hud != null and _mobile_hud.has_method("notify_input"):
			_mobile_hud.notify_input()

		if _touches.size() == 1:
			# First finger: start tap / long-press timers.
			_tap_start_time = Time.get_ticks_msec() / 1000.0
			_tap_start_pos = ev.position
			_tap_moved = 0.0
			_long_press_fired = false

			# Edge-swipe from the right edge → opens settings. Only arm the
			# tracker if the touch starts very close to the screen's right
			# edge; the actual decision happens on lift in case the user
			# changes their mind mid-drag.
			var win_w: float = get_viewport().get_visible_rect().size.x
			if not _aquascape_mode and ev.position.x >= win_w - EDGE_SWIPE_TRIGGER_PX:
				_edge_swipe_active = true
				_edge_swipe_start_x = ev.position.x

			# Aquascape: start painting immediately on touch-down (like LMB).
			if _aquascape_mode:
				if _begin_aquascape_drag(ev.position):
					_drag_mode = "wood_drag"
				else:
					_drag_mode = "paint"
					_paint_cooldown = 0.0
					_aquascape_place(ev.position)
		elif _touches.size() == 2:
			# Second finger: record pinch baseline distance + angle.
			var positions: Array = _touches.values()
			var p0: Vector2 = positions[0] as Vector2
			var p1: Vector2 = positions[1] as Vector2
			_pinch_distance = p0.distance_to(p1)
			_pinch_angle = (p1 - p0).angle()
			# Cancel any pending tap / long-press — this is a multi-touch gesture.
			_long_press_fired = true
			# Cancel aquascape paint if we were in it — 2-finger means navigate.
			if _drag_mode == "paint":
				_drag_mode = ""
			_wood_drag = null
			_drag_cluster.clear()
			_wood_drag_last_hit = INVALID_HIT
			# Cancel any in-flight edge swipe — multi-touch overrides it.
			_edge_swipe_active = false
	else:
		# Finger up.
		if ev.index == 0 and _touches.size() == 1:
			# Last finger lifted: check for tap / double-tap.
			var elapsed: float = Time.get_ticks_msec() / 1000.0 - _tap_start_time
			var is_tap: bool = elapsed < TAP_MAX_TIME and _tap_moved < TAP_MAX_MOVE \
				and not _long_press_fired
			
			if is_tap:
				var now: float = Time.get_ticks_msec() / 1000.0
				# Double-tap check.
				if _last_tap_time > 0.0 \
						and (now - _last_tap_time) < DOUBLE_TAP_WINDOW \
						and ev.position.distance_to(_last_tap_pos) < DOUBLE_TAP_RADIUS:
					# Double-tap → reset camera.
					target = DEFAULT_TARGET
					radius = DEFAULT_RADIUS
					yaw = DEFAULT_YAW
					pitch = DEFAULT_PITCH
					_follow_target = null
					_auto_orbit = false
					_apply_camera()
					_last_tap_time = -1.0
					print_verbose("[vivarium] double-tap: reset camera")
				else:
					# Single tap → try to pick a creature.
					_last_tap_time = now
					_last_tap_pos = ev.position
					_touch_pick_creature(ev.position)
			
			# Check for completed edge-swipe gesture: started near right edge,
			# moved at least EDGE_SWIPE_MIN_PX to the left. Fire BEFORE we
			# clear state so the trigger is unambiguous.
			if _edge_swipe_active:
				var dx: float = _edge_swipe_start_x - ev.position.x
				if dx >= EDGE_SWIPE_MIN_PX:
					_edge_swipe_active = false
					if settings_panel != null and settings_panel.has_method("toggle"):
						settings_panel.toggle()
						_haptic(15)
						# Treat the swipe as consumed — don't also reset camera
						# via the tap/double-tap path.
						_long_press_fired = true
				else:
					_edge_swipe_active = false

			# End aquascape drag.
			_wood_drag = null
			_drag_cluster.clear()
			_wood_drag_last_hit = INVALID_HIT
			_drag_mode = ""

		_touches.erase(ev.index)
		_touch_prev.erase(ev.index)
		if _touches.is_empty():
			_touch_active = false
			_pinch_distance = 0.0
			_pinch_angle = 0.0
			_edge_swipe_active = false


func _handle_screen_drag(ev: InputEventScreenDrag) -> void:
	_touches[ev.index] = ev.position
	if _mobile_hud != null and _mobile_hud.has_method("notify_input"):
		_mobile_hud.notify_input()

	# Track cumulative movement for tap detection.
	if ev.index == 0:
		_tap_moved += ev.relative.length()
	
	if _touches.size() == 1:
		# ---- Single finger: orbit or aquascape paint ----
		if _aquascape_mode:
			match _drag_mode:
				"paint":
					if _paint_cooldown <= 0.0:
						_aquascape_place(ev.position)
						_paint_cooldown = PAINT_INTERVAL
				"wood_drag":
					_drag_hardscape_piece(ev.position)
				_:
					# Even in aquascape, allow orbit if no tool action locked.
					yaw -= ev.relative.x * TOUCH_ORBIT_SENSITIVITY
					pitch -= ev.relative.y * TOUCH_ORBIT_SENSITIVITY
					pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
					_apply_camera()
		else:
			# Normal mode: 1-finger drag orbits.
			yaw -= ev.relative.x * TOUCH_ORBIT_SENSITIVITY
			pitch -= ev.relative.y * TOUCH_ORBIT_SENSITIVITY
			pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
			_apply_camera()
		
		_touch_prev[ev.index] = ev.position
	
	elif _touches.size() == 2:
		# ---- Two fingers: pan + pinch zoom + twist rotate ----
		_touch_prev[ev.index] = ev.position
		var positions: Array = _touches.values()
		var p0: Vector2 = positions[0] as Vector2
		var p1: Vector2 = positions[1] as Vector2

		# Pinch zoom: compare current finger distance to previous frame.
		var cur_dist: float = p0.distance_to(p1)
		if _pinch_distance > 10.0:  # avoid division issues on initial frame
			var zoom_delta: float = (cur_dist - _pinch_distance) * PINCH_ZOOM_SENSITIVITY
			radius = clampf(radius * (1.0 - zoom_delta / 100.0), MIN_RADIUS, MAX_RADIUS)
			_apply_camera()
		_pinch_distance = cur_dist

		# Twist: angle between the two fingers. Apply the delta to yaw so a
		# clockwise twist rotates the view clockwise (matches Maps/photo
		# viewers). Skip the very first frame after the second finger lands
		# because the previous angle was set on touch-down with both fingers
		# already in place.
		var cur_angle: float = (p1 - p0).angle()
		var angle_delta: float = cur_angle - _pinch_angle
		# Wrap to [-PI, PI] so a 359→1 jump becomes a small +2° delta.
		if angle_delta > PI:
			angle_delta -= TAU
		elif angle_delta < -PI:
			angle_delta += TAU
		# Only act on substantial twists so accidental hand jitter doesn't
		# spin the view while the user just wants to pan/zoom.
		if absf(angle_delta) > 0.005 and absf(angle_delta) < 0.5:
			yaw -= angle_delta * TWIST_SENSITIVITY
			_apply_camera()
		_pinch_angle = cur_angle

		# 2-finger pan: average of both deltas.
		if _touch_prev.size() == 2:
			var avg_delta: Vector2 = ev.relative * 0.5  # approximate
			_pan_target(avg_delta * (TOUCH_PAN_SENSITIVITY / PAN_MOUSE_SENSITIVITY))


func _touch_pick_creature(screen_pos: Vector2) -> void:
	# Convert touch position to SubViewport coordinates and pick.
	if display == null or sub_viewport == null:
		return
	var sv_pos: Vector2 = _window_mouse_to_viewport(screen_pos)
	var creatures: Array = _gather_creatures()
	var picked: Node3D = _pick_creature_at_viewport(sv_pos, creatures)
	if picked != null:
		_assign_creature_target(picked)
		print_verbose("[vivarium] touch-tap: picked %s" % _creature_label(picked))
	else:
		# Tap on empty area clears follow (replaces ESC on desktop).
		if _follow_target != null:
			_follow_target = null
			print_verbose("[vivarium] touch-tap: cleared follow")


# ---- Mobile UI setup ----

func _setup_mobile_ui() -> void:
	# Enlarge all header toggle buttons so they're finger-friendly (≥48×48dp).
	var toggle_buttons: Array[Button] = []
	if settings_toggle != null: toggle_buttons.append(settings_toggle)
	if render_toggle != null: toggle_buttons.append(render_toggle)
	if fish_store_toggle != null: toggle_buttons.append(fish_store_toggle)
	if creature_creator_toggle != null: toggle_buttons.append(creature_creator_toggle)
	if aquascape_toggle != null: toggle_buttons.append(aquascape_toggle)
	if portal_toggle != null: toggle_buttons.append(portal_toggle)
	for btn in toggle_buttons:
		btn.custom_minimum_size = Vector2(64, 48)
		btn.add_theme_font_size_override("font_size", 16)
	
	# Update the controls hint to show touch gestures instead of keyboard.
	var hint: Label = get_node_or_null("ControlsHint")
	if hint != null:
		hint.text = "drag orbit · pinch zoom · 2-finger pan + twist · tap creature · double-tap reset · long-press auto-orbit · edge-swipe settings"
	
	# Wire up the MobileHUD node if it exists in the scene tree.
	_mobile_hud = get_node_or_null("MobileHUD")
	if _mobile_hud != null and _mobile_hud.has_signal("pause_pressed"):
		_mobile_hud.connect("pause_pressed", _toggle_pause)
		_mobile_hud.connect("speed_pressed", _set_time_scale)
		_mobile_hud.connect("photo_pressed", _take_photo)
		_mobile_hud.connect("undo_pressed", _aquascape_undo)

	# Show the first-launch gesture tutorial on top of everything else.
	# Defers a frame so the panel doesn't fight with other mobile-setup
	# layout passes for size/anchor positioning.
	call_deferred("_maybe_show_tutorial")


func _apply_camera() -> void:
	if camera == null:
		return
	# Clamp target to a generous bounding box every time we apply. This is
	# the single convergence point for pan / WASD / follow-cam — clamping
	# here means a stray big delta from any of those paths can't push the
	# target through the camera (breaking `look_at`) or to ±∞.
	target.x = clampf(target.x, -20.0, 20.0)
	target.y = clampf(target.y, -2.0, 12.0)
	target.z = clampf(target.z, -20.0, 20.0)
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
	var pan_sc: float = PAN_MOUSE_SENSITIVITY * radius
	target -= right * (delta.x * pan_sc)
	target += up * (delta.y * pan_sc)
	# `target` is clamped to a sane box inside `_apply_camera()` (every
	# update path calls through there, so the clamp lives at the single
	# convergence point).
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


# Chip layout: a row of icon-prefixed metric cards in the top-center StatsBar
# panel. Each chip is pre-built once in _build_hud_chips() and updated in
# place here. Warnings (low O₂, algae outbreak, paused, etc.) re-tint the
# affected chip without rebuilding it. Visibility per-chip is driven by
# _apply_hud_layout() — compact breakpoints hide secondary chips.
var _last_state_value: String = ""
var _last_state_sub: String = ""

# Lightweight per-frame refresh of just the speed / day-phase chip. Computes the
# two short strings the state chip shows and only repaints the chip when they
# change — so a paused or steady-speed tank does zero UI work on idle frames,
# while a speed nudge or phase rollover still updates instantly.
func _refresh_state_chip() -> void:
	if _chips.is_empty():
		return
	var state_value: String = "1×"
	var state_sub: String = "—"
	var state_warn: bool = false
	if _sim != null:
		var ts: float = float(_sim.time_scale)
		if ts == 0.0:
			state_value = "⏸"
			state_warn = true
		elif is_equal_approx(ts, 1.0):
			state_value = "1×"
		else:
			state_value = "%s×" % ts
		state_sub = _day_label(float(_sim.day_phase))
	if state_value == _last_state_value and state_sub == _last_state_sub:
		return
	_last_state_value = state_value
	_last_state_sub = state_sub
	_update_chip("state", state_value, state_sub, true, state_warn)


func _render_header() -> void:
	if _chips.is_empty():
		return

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
	var plants: int = int(_stats.get("plants_alive", 0))
	var biomass: int = int(_stats.get("plant_total_biomass", 0))
	var waste: int = int(_stats.get("waste_particles", 0))
	var o2: float = float(_stats.get("dissolved_o2", 1.0))
	var fixture: String = String(_stats.get("aeration_fixture", "?"))
	var o2_pct: int = int(round(o2 * 100.0))
	var distinct_morphs: int = int(_stats.get("morph_distinct", 0))

	# State chip: speed indicator + day phase.
	var state_value: String = "1×"
	var state_sub: String = "—"
	var state_warn: bool = false
	if _sim != null:
		var ts: float = float(_sim.time_scale)
		if ts == 0.0:
			state_value = "⏸"
			state_warn = true
		elif is_equal_approx(ts, 1.0):
			state_value = "1×"
		else:
			# GDScript's `%` operator doesn't accept `%g` (Python-style auto
			# precision) — using it threw a String formatting error on every
			# stats tick once the player nudged time_scale off 1×. `%s` calls
			# str() on the value, which renders cleanly: 4.0 → "4", 1.5 → "1.5".
			state_value = "%s×" % ts
		state_sub = _day_label(float(_sim.day_phase))
	_update_chip("state", state_value, state_sub, true, state_warn)

	# Fauna chips. On compact layout the shrimp+snails chips are hidden and
	# the "fish" chip shows the grand fauna total instead.
	var fauna_compact: bool = _hud_layout == "compact"
	if fauna_compact:
		var fauna_total: int = fish_total + shrimp_total + snail_total
		_update_chip("fish", str(fauna_total), "fauna", true, false)
	else:
		_update_chip("fish", str(fish_total),
			("%dA %dF" % [fish_adults, fish_fry]) if fish_total > 0 else "—",
			true, false)
		_update_chip("shrimp", str(shrimp_total),
			("%dA %dF" % [shrimp_adults, shrimp_fry]) if shrimp_total > 0 else "—",
			true, false)
		_update_chip("snails", str(snail_total),
			("%dA %dB" % [snail_adults, snail_babies]) if snail_total > 0 else "—",
			true, false)

	# Flora chip.
	_update_chip("flora", str(plants), "biomass %d" % biomass, true, false)

	# Water chip: O₂ percentage + fixture name; warn-tinted below 50%.
	_update_chip("water", "%d%%" % o2_pct, fixture, true, o2_pct < 50)

	# Morphs chip — only meaningful once speciation has produced variants.
	_update_chip("morphs", "+%d" % distinct_morphs, "morphs", distinct_morphs > 0, false)

	# Mood chip — aggregate tank vibe across O₂, biomass, algae, waste.
	# Weights tuned so a healthy planted tank reads as "thriving" and a
	# crashed one as "🚨", with a clear in-between band so the chip
	# changes meaningfully as the tank trends rather than flipping at
	# one threshold. Mood is computed here rather than on sim_driver so
	# it can read the same _stats snapshot already in scope.
	var mood: float = 0.30 * o2 \
		+ 0.30 * clampf(float(biomass) / 600.0, 0.0, 1.0) \
		+ 0.20 * clampf(1.0 - float(algae) / 60.0, 0.0, 1.0) \
		+ 0.20 * clampf(1.0 - float(waste) / 100.0, 0.0, 1.0)
	var mood_label: String
	var mood_glyph: String
	if mood >= 0.78:
		mood_glyph = "🙂"
		mood_label = "thriving"
	elif mood >= 0.55:
		mood_glyph = "😌"
		mood_label = "ok"
	elif mood >= 0.32:
		mood_glyph = "😟"
		mood_label = "stressed"
	else:
		mood_glyph = "🚨"
		mood_label = "crashing"
	_update_chip("mood", mood_glyph, mood_label, true, mood < 0.32)

	# Alert chip — surfaces the most pressing problem so a glance reveals trouble.
	var has_alert: bool = false
	var alert_value: String = "!"
	var alert_sub: String = ""
	if o2_pct < 30:
		has_alert = true
		alert_sub = "low O₂"
	elif algae > 20:
		has_alert = true
		alert_value = "%d" % algae
		alert_sub = "algae"
	elif waste > 30:
		has_alert = true
		alert_value = "%d" % waste
		alert_sub = "waste"
	_update_chip("alert", alert_value, alert_sub, has_alert, true)

	# Aquascape mode replaces the state chip's sublabel with the tool name so
	# the player sees the active tool at a glance.
	if _aquascape_mode:
		_update_chip("state", "AQUA", _aquascape_tool.to_upper(), true, false)


# Build the chip widgets inside the StatsBar's HBox. Called once from _ready
# after the scene is set up. Each chip is a PanelContainer with a category-
# tinted left border, an emoji/glyph icon, the numeric value, and an optional
# sublabel. The chip itself is cached in _chips[key]; its value/sublabel
# Labels are exposed via meta so _update_chip can rewrite them without
# walking the tree.
func _build_hud_chips() -> void:
	if stats_bar == null:
		return
	var bar: HBoxContainer = stats_bar.get_node_or_null("HBox") as HBoxContainer
	if bar == null:
		return
	# Clear any pre-existing children (re-entrant safety in case _ready runs twice).
	for c in bar.get_children():
		c.queue_free()
	_chips.clear()

	# Defs: ordered list of (key, icon, accent_color). Order = visual order
	# left-to-right in the bar.
	var defs: Array = [
		{"key": "state",  "icon": "◴", "color": Color8(154, 168, 200)},
		{"key": "mood",   "icon": "♥", "color": Color8(170, 220, 170)},
		{"key": "fish",   "icon": "🐟", "color": Color8(214, 176, 112)},
		{"key": "shrimp", "icon": "🦐", "color": Color8(214, 176, 112)},
		{"key": "snails", "icon": "🐌", "color": Color8(214, 176, 112)},
		{"key": "flora",  "icon": "🌿", "color": Color8(134, 192, 132)},
		{"key": "water",  "icon": "💧", "color": Color8(127, 183, 216)},
		{"key": "morphs", "icon": "✦", "color": Color8(224, 192, 96)},
		{"key": "alert",  "icon": "⚠", "color": Color8(224, 112, 112)},
	]
	for d in defs:
		var chip: Control = _make_chip(String(d["icon"]), d["color"] as Color)
		bar.add_child(chip)
		_chips[d["key"]] = chip
		# Tapping a chip opens a sparkline popup showing the last ~2 minutes
		# of that metric's history. PanelContainer accepts gui_input out of
		# the box; we route the key + accent color along so the popup can
		# title + tint itself.
		var key: String = String(d["key"])
		var color: Color = d["color"] as Color
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(func(ev): _on_chip_gui_input(ev, key, color))


# Construct a single chip widget. Caches the value + sublabel Labels via meta
# so _update_chip can find them without walking the subtree on every tick.
func _make_chip(icon: String, accent: Color) -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	# Chips sit inside the StatsBar's tinted panel — no fill, just a 2-px
	# accent strip on the left so the eye can find each category.
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = accent
	style.border_width_left = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	pc.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	pc.add_child(hb)

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 14)
	icon_lbl.add_theme_color_override("font_color", accent)
	hb.add_child(icon_lbl)

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 13)
	value_lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	hb.add_child(value_lbl)

	var sublabel_lbl := Label.new()
	sublabel_lbl.add_theme_font_size_override("font_size", 10)
	sublabel_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85, 0.85))
	hb.add_child(sublabel_lbl)

	pc.set_meta("value_label", value_lbl)
	pc.set_meta("sublabel_label", sublabel_lbl)
	pc.set_meta("accent", accent)
	return pc


# Update a chip's value + sublabel. `warn` re-tints the chip red when a
# threshold is crossed (low O₂, paused, etc.); `visible_` hides the whole chip
# when the metric isn't relevant (e.g. no morphs yet).
func _update_chip(key: String, value: String, sublabel: String,
		visible_: bool, warn: bool) -> void:
	var chip: Control = _chips.get(key, null) as Control
	if chip == null:
		return
	chip.visible = visible_
	if not visible_:
		return
	var v: Label = chip.get_meta("value_label", null) as Label
	var s: Label = chip.get_meta("sublabel_label", null) as Label
	if v != null:
		v.text = value
	if s != null:
		s.text = sublabel
	chip.modulate = Color(1.0, 0.7, 0.7) if warn else Color(1.0, 1.0, 1.0)


# Responsive layout. Three breakpoints driven by viewport width + touch:
#   wide   (≥1100):     all chips visible WITH sublabels, both clusters at top
#   medium (700-1099):  all chips visible, sublabels hidden to save space
#   compact (<700, or
#           touch+<900): minimal chips (state/fish/flora/water/alert), right
#                       cluster moves to bottom-right thumb zone
# Called once at _ready and on every viewport size_changed.
func _apply_hud_layout() -> void:
	if top_hud == null or stats_bar == null:
		return
	var w: float = get_viewport().get_visible_rect().size.x
	var is_touch: bool = _is_mobile()

	var layout: String = "wide"
	if w < 700.0 or (is_touch and w < 900.0):
		layout = "compact"
	elif w < 1100.0:
		layout = "medium"
	if layout == _hud_layout:
		return
	_hud_layout = layout

	# Sublabel visibility: only shown on the wide breakpoint.
	for chip in _chips.values():
		var s: Label = (chip as Control).get_meta("sublabel_label", null) as Label
		if s != null:
			s.visible = layout == "wide"

	# Compact: hide secondary fauna chips (their data folds into the "fish"
	# chip via _render_header's compact branch).
	var compact_only_chips := ["shrimp", "snails", "morphs"]
	for k in compact_only_chips:
		var chip: Control = _chips.get(k, null) as Control
		if chip != null:
			# Visibility is also gated by _render_header (morphs only shown
			# when >0). In compact, force-hide regardless.
			if layout == "compact":
				chip.visible = false

	# Right cluster: top-right on wide/medium, bottom-right (FAB zone) on compact.
	if right_cluster != null:
		if layout == "compact":
			right_cluster.anchor_left = 1.0
			right_cluster.anchor_top = 1.0
			right_cluster.anchor_right = 1.0
			right_cluster.anchor_bottom = 1.0
			right_cluster.offset_left = -12.0
			right_cluster.offset_top = -12.0
			right_cluster.offset_right = -12.0
			right_cluster.offset_bottom = -12.0
			right_cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			right_cluster.grow_vertical = Control.GROW_DIRECTION_BEGIN
		else:
			right_cluster.anchor_left = 1.0
			right_cluster.anchor_top = 0.0
			right_cluster.anchor_right = 1.0
			right_cluster.anchor_bottom = 0.0
			right_cluster.offset_left = -12.0
			right_cluster.offset_top = 8.0
			right_cluster.offset_right = -12.0
			right_cluster.offset_bottom = 8.0
			right_cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			right_cluster.grow_vertical = Control.GROW_DIRECTION_END

	# Re-render chip values so the compact-fauna branch kicks in immediately.
	_render_header()


# Chip-tap handler — opens a sparkline popup with the last ~2 minutes of
# history for that metric. The mapping from chip key to the sim's
# population_history key is mostly identity, with a couple of aliases for
# chips that aggregate (e.g. "flora" → plants_alive, "water" → dissolved_o2).
const _CHIP_TO_HISTORY := {
	"fish": "fish_total",
	"shrimp": "shrimp_total",
	"snails": "snails_total",
	"flora": "plants_alive",
	"water": "dissolved_o2",
	"alert": "algae_clusters",
}


func _on_chip_gui_input(ev: InputEvent, key: String, color: Color) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = ev
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# Mood chip opens the story log instead of a sparkline. The aggregate
	# "how is the tank doing" feel routes naturally to "what happened in
	# this tank's life so far."
	if key == "mood":
		_show_story_popup(color)
		return
	var hist_key: String = _CHIP_TO_HISTORY.get(key, "")
	if hist_key == "":
		return  # state/morphs chips have no useful history
	_show_history_popup(hist_key, key, color)


# Story popup — scrollable list of milestone events from sim.story_events.
# Reuses the same chrome as the history popup but swaps the sparkline for
# a RichTextLabel showing one event per line, newest first.
var _story_popup: PanelContainer = null
var _story_list: RichTextLabel = null


func _ensure_story_popup() -> void:
	if _story_popup != null and is_instance_valid(_story_popup):
		return
	_story_popup = PanelContainer.new()
	_story_popup.visible = false
	_story_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_story_popup.custom_minimum_size = Vector2(420, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.94)
	style.border_color = Color(0.35, 0.45, 0.6, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	_story_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_story_popup.add_child(vbox)

	var title := Label.new()
	title.text = "Tank story"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	vbox.add_child(title)

	_story_list = RichTextLabel.new()
	_story_list.bbcode_enabled = true
	_story_list.fit_content = false
	_story_list.scroll_active = true
	_story_list.scroll_following = false
	_story_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_list.custom_minimum_size = Vector2(390, 180)
	_story_list.add_theme_color_override("default_color", Color(0.86, 0.90, 0.96, 0.95))
	_story_list.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_story_list)

	add_child(_story_popup)


func _show_story_popup(_chip_color: Color) -> void:
	_ensure_story_popup()
	if _sim == null:
		return
	var events: Array = _sim.story_events
	if events.is_empty():
		_story_list.text = "[color=#9aa8c8]No story yet. Wait for things to happen.[/color]"
	else:
		var lines: Array[String] = []
		# Newest events first so the most recent reads at the top.
		for i in range(events.size() - 1, -1, -1):
			var e: Dictionary = events[i]
			var t: float = float(e.get("t", 0.0))
			lines.append("[color=#9aa8c8]%s[/color]  %s" % [
				_format_story_t(t), String(e.get("text", "")),
			])
		_story_list.text = "\n".join(lines)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_story_popup.size = _story_popup.custom_minimum_size
	_story_popup.position = Vector2(
		(vp.x - _story_popup.size.x) * 0.5, 56.0)
	_story_popup.visible = true


# Render an elapsed sim-time into a short "Xm" / "Xh Ym" string for the
# left margin of each story line. Keeps the diary scannable rather than
# raw-second timestamped.
func _format_story_t(t: float) -> String:
	var s: int = int(t)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm" % int(s / 60.0)
	var h: int = int(s / 3600.0)
	var m: int = int((s % 3600) / 60.0)
	return "%dh %dm" % [h, m]


# History popup. Single instance — reused across taps. Opens centered
# under the StatsBar with the sparkline + min / max / current labels.
var _history_popup: PanelContainer = null
var _history_sparkline: Control = null
var _history_title: Label = null
var _history_stats: Label = null


func _ensure_history_popup() -> void:
	if _history_popup != null and is_instance_valid(_history_popup):
		return
	_history_popup = PanelContainer.new()
	_history_popup.visible = false
	_history_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_history_popup.custom_minimum_size = Vector2(320, 110)
	# Match the cluster chrome — same look as the top HUD pills.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.94)
	style.border_color = Color(0.35, 0.45, 0.6, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	_history_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_history_popup.add_child(vbox)

	_history_title = Label.new()
	_history_title.add_theme_font_size_override("font_size", 13)
	_history_title.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	vbox.add_child(_history_title)

	_history_stats = Label.new()
	_history_stats.add_theme_font_size_override("font_size", 10)
	_history_stats.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85, 0.85))
	vbox.add_child(_history_stats)

	_history_sparkline = _make_sparkline()
	_history_sparkline.custom_minimum_size = Vector2(290, 56)
	vbox.add_child(_history_sparkline)

	add_child(_history_popup)


# Build a Control whose _draw paints the polyline over a soft fill region.
# Stores its data in metadata so we don't need a custom class file.
func _make_sparkline() -> Control:
	var c := Control.new()
	c.set_meta("samples", [])
	c.set_meta("color", Color.WHITE)
	# Use a script-on-the-fly via a connected _draw lambda. Godot 4 supports
	# the `draw` signal that fires when a Control redraws, which lets us
	# paint without a separate .gd file.
	c.draw.connect(_draw_sparkline_on.bind(c))
	return c


func _draw_sparkline_on(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	_draw_sparkline(c)


func _draw_sparkline(c: Control) -> void:
	var samples: Array = c.get_meta("samples", [])
	if samples.size() < 2:
		return
	var color: Color = c.get_meta("color", Color.WHITE)
	var max_v: float = -INF
	var min_v: float = INF
	for v in samples:
		var fv: float = float(v)
		if fv > max_v:
			max_v = fv
		if fv < min_v:
			min_v = fv
	var rng: float = max_v - min_v
	if rng < 0.001:
		rng = 1.0
	var sz: Vector2 = c.size
	var dx: float = sz.x / float(samples.size() - 1)
	var pts := PackedVector2Array()
	for i in samples.size():
		var v: float = float(samples[i])
		var y: float = sz.y - ((v - min_v) / rng) * sz.y
		pts.append(Vector2(i * dx, y))
	# Soft fill under the line for legibility against the dark backdrop.
	var fill := pts.duplicate()
	fill.append(Vector2(sz.x, sz.y))
	fill.append(Vector2(0, sz.y))
	var fill_color := color
	fill_color.a = 0.18
	c.draw_colored_polygon(fill, fill_color)
	c.draw_polyline(pts, color, 1.6, true)


func _show_history_popup(hist_key: String, chip_key: String, color: Color) -> void:
	_ensure_history_popup()
	if _sim == null:
		return
	var hist: Array = _sim.population_history.get(hist_key, [])
	if hist.is_empty():
		# Single placeholder so the popup isn't empty on a fresh tank.
		hist = [0, 0]
	# Title + min/max/current line. We keep the units implicit (the chip's
	# icon already conveys "fish" / "plants" / etc.) so the number itself
	# is the focus.
	var title := chip_key.capitalize()
	_history_title.text = title + " — last %d s" % hist.size()
	var cur: float = float(hist[-1])
	var lo: float = float(hist[0])
	var hi: float = float(hist[0])
	for v in hist:
		var fv: float = float(v)
		if fv < lo:
			lo = fv
		if fv > hi:
			hi = fv
	_history_stats.text = "now %s   min %s   max %s" % [
		_fmt_history(cur), _fmt_history(lo), _fmt_history(hi),
	]
	_history_sparkline.set_meta("samples", hist.duplicate())
	_history_sparkline.set_meta("color", color)
	_history_sparkline.queue_redraw()
	# Position centered under the stats bar.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_history_popup.size = _history_popup.custom_minimum_size
	_history_popup.position = Vector2(
		(vp.x - _history_popup.size.x) * 0.5,
		56.0,
	)
	_history_popup.visible = true


# Tight number formatter: integers as-is, fractions to 2 decimals.
# Keeps the "now 1.00   min 0.85   max 1.00" row readable for the
# dissolved_o2 chip which is in [0, 1] while still showing "now 12"
# for integer-valued fish counts.
func _fmt_history(v: float) -> String:
	if absf(v - round(v)) < 0.005:
		return str(int(round(v)))
	return "%.2f" % v


# Mirror MobileHUD's idle-dim for the top HUD. Resets the timer; called from
# every input handler. Restores full brightness if we were dimmed.
func _notify_hud_input() -> void:
	_hud_idle_seconds = 0.0
	if top_hud != null and top_hud.modulate != HUD_LIT_MODULATE:
		top_hud.modulate = HUD_LIT_MODULATE


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


# ---- Back-to-menu navigation ----
# The Menu button (top-left of main.tscn) saves the active tank and
# transitions back to the tank picker. Also bound to Android's back button
# via NOTIFICATION_WM_GO_BACK_REQUEST in _notification.
func _on_back_to_menu() -> void:
	if _save_restored:
		# Avoid GPU readback on menu navigation. On Metal/macOS the thumbnail
		# capture can still hit "timeout waiting for fence" if the render queue
		# is saturated right when leaving the scene.
		save_active_tank(true)
	_haptic(15)
	get_tree().change_scene_to_file("res://tank_menu.tscn")


# ---- Tank save / load orchestration ----
# main.gd owns the file-level save/load because it has the SimDriver ref +
# the aquascape voxel array. SimDriver covers everything sim-side; this
# wrapper combines its dict with aquascape data, atomically writes JSON,
# captures a thumbnail, and updates per-slot meta.

# Periodic autosave cadence. 5 minutes of real time between disk writes —
# frequent enough that a phone OS kill rarely loses more than a few minutes
# of progress, infrequent enough that the cost is negligible.
const AUTOSAVE_INTERVAL_S: float = 300.0
var _autosave_accum: float = 0.0
# GPU readback guard — synchronous get_image() on macOS often trips
# "timeout waiting for fence" if we read while the viewport is still drawing.
var _viewport_capture_busy: bool = false
var _last_viewport_capture_frame: int = -9999
const VIEWPORT_CAPTURE_FRAME_GAP: int = 45
# True once we've successfully restored state (or determined there's nothing
# to restore). Guards against running load_state twice.
var _save_restored: bool = false
# Sticky last-running time_scale: when the user pauses for aquascape or
# manually, we save the previous non-zero value so the next session opens
# at the speed they were playing at — not paused.
var _save_pending_time_scale: float = 1.0


func _try_load_saved_state() -> void:
	if _save_restored:
		return
	_save_restored = true
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	# world.gd already deleted incompatible state files before its spawn
	# decision, but check again here so a race in autoload order can't
	# resurrect a stale load.
	if not saves.is_active_save_compatible():
		return
	var path: String = saves.state_path(int(saves.active_slot))
	if not FileAccess.file_exists(path):
		return
	var d: Dictionary = saves.read_json(path)
	if d.is_empty():
		# Parse failed — likely corruption. Surface the prompt.
		_show_corrupt_save_prompt(path)
		return
	if _sim != null and _sim.has_method("load_state"):
		_sim.load_state(d)
	# Aquascape lives outside the sim dict.
	if d.has("aquascape"):
		_restore_aquascape(d["aquascape"])
	print_verbose("[vivarium] restored save from ", path)


# Snapshot the world to disk. Called by:
#   - the 5-minute periodic autosave
#   - app focus-out (NOTIFICATION_APPLICATION_FOCUS_OUT)
#   - the back-to-menu button
#   - clean app quit
# Skip if we're in the middle of aquascape mode (time_scale=0 from that path
# would freeze the session at "paused" forever).
func save_active_tank(skip_thumbnail: bool = false) -> void:
	if _sim == null or not _sim.has_method("save_state"):
		return
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	# Don't write a paused-by-aquascape time_scale. Save the running speed
	# the player chose so reload picks up at that speed.
	var live_ts: float = float(_sim.time_scale)
	if live_ts > 0.0:
		_save_pending_time_scale = live_ts
	var state_d: Dictionary = _sim.save_state()
	state_d["sim"]["time_scale"] = _save_pending_time_scale
	state_d["aquascape"] = _aquascape_to_save_arr()
	var path: String = saves.state_path(int(saves.active_slot))
	var err: int = saves.write_text_atomic(path, JSON.stringify(state_d, "  "))
	if err != OK:
		push_warning("[vivarium] save failed at %s: err %d" % [path, err])
		return
	# Capture a thumbnail for the menu card. Cheap — pulls the existing
	# SubViewport texture, no extra rendering.
	# On macOS/Metal this readback is the top freeze trigger under load.
	if not skip_thumbnail and not OS.has_feature("macos"):
		_save_thumbnail(saves.thumbnail_path(int(saves.active_slot)))
	# Update per-tank meta: accumulated runtime + last-opened.
	var meta: Dictionary = saves.get_tank_meta(int(saves.active_slot))
	if meta.is_empty():
		meta = {
			"name": "Tank %d" % int(saves.active_slot),
			"runtime_s": 0,
			"created_unix": int(Time.get_unix_time_from_system()),
			"last_opened_unix": int(Time.get_unix_time_from_system()),
		}
	meta["runtime_s"] = int(_sim.elapsed_runtime_s) if _sim.get("elapsed_runtime_s") != null else int(meta.get("runtime_s", 0))
	meta["last_opened_unix"] = int(Time.get_unix_time_from_system())
	saves.update_tank_meta(int(saves.active_slot), meta)


func _save_thumbnail(path: String) -> void:
	if sub_viewport == null:
		return
	if not get_window().has_focus():
		return
	_request_viewport_image(_finish_save_thumbnail.bind(path))


func _finish_save_thumbnail(img: Image, path: String) -> void:
	var w: int = 480
	var h: int = int(round(float(img.get_height()) * (float(w) / float(img.get_width()))))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.save_png(path)


# Show a modal prompt offering to start fresh or attempt the .bak file. Only
# fires when state.json existed but failed to parse — corruption.
func _show_corrupt_save_prompt(state_path: String) -> void:
	var bak_path: String = state_path + ".bak"
	var dialog := AcceptDialog.new()
	if FileAccess.file_exists(bak_path):
		dialog.dialog_text = "This tank's save file is corrupted.\nA backup is available."
		dialog.add_button("Restore from backup", true, "restore_bak")
		dialog.add_button("Start fresh", false, "start_fresh")
	else:
		dialog.dialog_text = "This tank's save file is corrupted and there's no backup.\nStarting fresh."
	dialog.title = "Save file problem"
	add_child(dialog)
	dialog.custom_action.connect(func(action: StringName):
		if String(action) == "restore_bak":
			var saves := get_node_or_null("/root/TankSaves")
			if saves != null:
				var d: Dictionary = saves.read_json(bak_path)
				if not d.is_empty() and _sim != null:
					_sim.load_state(d)
					if d.has("aquascape"):
						_restore_aquascape(d["aquascape"])
		dialog.queue_free())
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.popup_centered()


# ---- App-lifecycle: pause sim when backgrounded ----
# Android (and other mobile OSes) keep the process running when the user
# switches away, which means the sim would tick the whole time and drain
# battery. We freeze time_scale on FOCUS_OUT and restore it on FOCUS_IN. The
# pause is best-effort: if some other code (manual pause, aquascape) already
# zeroed time_scale we leave it alone so we don't accidentally un-pause.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_on_focus_out()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_on_focus_in()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_last_quit_unix()
		if _save_restored:
			save_active_tank(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android system back button. Save and pop to the tank menu rather
		# than letting the OS kill the activity outright.
		_on_back_to_menu()


func _on_focus_out() -> void:
	# Remember when the user left so we can show a welcome-back toast on
	# resume. Done on focus-out (rather than only on exit) because Android
	# rarely sends a clean exit notification.
	_persist_last_quit_unix()
	# Snapshot tank state to disk. Best-effort — if it fails, we still want
	# the lifecycle hooks to continue.
	if _save_restored:
		save_active_tank(true)
	if _sim == null:
		return
	# Only freeze if the sim is currently running; if it was already paused
	# don't store 0 as the "saved" value — we'd unpause on resume.
	var ts: float = float(_sim.time_scale)
	if ts > 0.0:
		_focus_saved_time_scale = ts
		_sim.time_scale = 0.0
		_focus_paused = true


func _on_focus_in() -> void:
	if _sim == null or not _focus_paused:
		return
	_sim.time_scale = _focus_saved_time_scale
	_focus_paused = false


func _persist_last_quit_unix() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.last_quit_unix = int(Time.get_unix_time_from_system())
	cfg.save_to_disk()


# ---- Device tier pick (first mobile launch) ----
# Cheap heuristic for picking an initial render scale: use the screen's
# short-side pixel count. Phones report ~720-1200 short side; tablets are
# 1200+. We only set device_tier once (when "") so the user's later choice
# is preserved across launches. Render res is bumped on tablets only —
# phones keep the current default that's already working well.
func _pick_device_tier_if_unset() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	if String(cfg.device_tier) != "":
		return  # already picked
	var sz: Vector2i = DisplayServer.screen_get_size()
	var short_side: int = min(sz.x, sz.y) if sz.x > 0 and sz.y > 0 else 0
	if short_side >= 1500:
		cfg.device_tier = "high"
		# Bump render res so the tank fills the bigger tablet panel with
		# more detail. Stays well within typical mobile GPU budgets.
		cfg.render_width = 768
		cfg.render_height = 432
	elif short_side >= 900:
		cfg.device_tier = "mid"
	else:
		cfg.device_tier = "low"
		# Tiny / old phones: drop one notch so we stay smooth.
		cfg.render_width = 384
		cfg.render_height = 216
	cfg.save_to_disk()
	print_verbose("[vivarium] device_tier picked: %s (short side %d px)" % [cfg.device_tier, short_side])


# ---- FPS cap (battery saver) ----
func _apply_fps_cap() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	# First-mobile-launch default: if no cap is set, lock to 60 to save
	# battery + thermals. User can override in settings (when wired up).
	if _is_mobile() and int(cfg.fps_cap) == 0:
		cfg.fps_cap = 60
		cfg.save_to_disk()
	if int(cfg.fps_cap) > 0:
		Engine.max_fps = int(cfg.fps_cap)


# ---- Welcome-back toast ----
# Cheap floating Label that auto-fades after a few seconds. Doesn't
# fast-forward the sim — that'd risk creature/state divergence. Players
# accept a soft "you were away" message readily; sim time-skip would need
# a more careful implementation.
func _show_welcome_back_if_returning() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var last_quit: int = int(cfg.last_quit_unix)
	if last_quit <= 0:
		return
	var now: int = int(Time.get_unix_time_from_system())
	var delta: int = now - last_quit
	if delta < 30:
		return  # ignore brief reloads
	var msg: String = "Welcome back. You were away for %s." % _format_duration(delta)
	_spawn_welcome_label(msg)


func _on_species_discovered(entry: Dictionary) -> void:
	_show_discovery_toast(entry)


func _show_discovery_toast(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var otype: String = String(entry.get("organism_type", "fish"))
	var icon: String = "🐟"
	match otype:
		"shrimp":
			icon = "🦐"
		"snail":
			icon = "🐌"
		"plant":
			icon = "🌿"
	var display: String = String(entry.get("display_name", "?"))
	var gen: int = int(entry.get("generation", 0))
	var src: String = String(entry.get("source", ""))
	var src_hint: String = ""
	if src == "founder":
		src_hint = " · founder"
	elif src == "store":
		src_hint = " · store"
	_kill_discovery_toast_tween()
	if _discovery_toast != null and is_instance_valid(_discovery_toast):
		_discovery_toast.queue_free()
		_discovery_toast = null
	var lab := Label.new()
	lab.text = "%s New discovery: %s (gen %d)%s" % [icon, display, gen, src_hint]
	lab.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_font_size_override("font_size", 14 if _is_mobile() else 13)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.anchor_left = 0.0
	lab.anchor_right = 1.0
	lab.anchor_top = 0.0
	lab.anchor_bottom = 0.0
	lab.offset_top = 108.0
	lab.offset_bottom = 140.0
	add_child(lab)
	_discovery_toast = lab
	_discovery_toast_tween = create_tween()
	_discovery_toast_tween.tween_interval(3.2)
	_discovery_toast_tween.tween_property(lab, "modulate:a", 0.0, 0.9)
	_discovery_toast_tween.tween_callback(_clear_discovery_toast)


func _kill_discovery_toast_tween() -> void:
	if _discovery_toast_tween != null and _discovery_toast_tween.is_valid():
		_discovery_toast_tween.kill()
	_discovery_toast_tween = null


func _clear_discovery_toast() -> void:
	_discovery_toast_tween = null
	if _discovery_toast != null and is_instance_valid(_discovery_toast):
		_discovery_toast.queue_free()
	_discovery_toast = null


func _spawn_welcome_label(text: String) -> void:
	if _welcome_toast_tween != null and _welcome_toast_tween.is_valid():
		_welcome_toast_tween.kill()
		_welcome_toast_tween = null
	if _welcome_label != null and is_instance_valid(_welcome_label):
		_welcome_label.queue_free()
		_welcome_label = null
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", Color(1, 1, 0.85, 1))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_font_size_override("font_size", 14 if _is_mobile() else 13)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.anchor_left = 0.0
	lab.anchor_right = 1.0
	lab.anchor_top = 0.0
	lab.anchor_bottom = 0.0
	lab.offset_top = 64.0
	lab.offset_bottom = 96.0
	add_child(lab)
	_welcome_label = lab
	# Fade out after 4 seconds. Use a tween so the message gently disappears
	# instead of yanking on/off.
	_welcome_toast_tween = create_tween()
	_welcome_toast_tween.tween_interval(4.0)
	_welcome_toast_tween.tween_property(lab, "modulate:a", 0.0, 1.5)
	_welcome_toast_tween.tween_callback(_clear_welcome_label)


func _clear_welcome_label() -> void:
	_welcome_toast_tween = null
	if _welcome_label != null and is_instance_valid(_welcome_label):
		_welcome_label.queue_free()
	_welcome_label = null


func _format_duration(seconds: int) -> String:
	if seconds < 60:
		return "%d seconds" % seconds
	if seconds < 3600:
		return "%d min" % int(seconds / 60.0)
	if seconds < 86400:
		var h: int = int(seconds / 3600.0)
		var m: int = int((seconds % 3600) / 60.0)
		if m == 0:
			return "%d hr" % h
		return "%d hr %d min" % [h, m]
	return "%d days" % int(seconds / 86400.0)


# ---- Haptic feedback ----
# Short vibration on key actions (photo, undo, place, speed change). 15-30ms
# is the "tactile click" range; longer than 50ms starts to feel annoying.
# Input.vibrate_handheld is a no-op on desktop.
func _haptic(duration_ms: int = 15) -> void:
	if _is_mobile():
		Input.vibrate_handheld(duration_ms)


# ---- Tutorial overlay ----
# Built on first mobile launch from main._setup_mobile_ui. A semi-transparent
# panel with gesture hints and a single OK button that persists
# tutorial_seen=true so it never returns. Doesn't block sim — user can
# dismiss instantly or admire the tank behind it.
func _dismiss_blocking_overlays() -> bool:
	var dismissed := false
	if library_panel != null and library_panel.visible:
		if library_panel.has_method("close"):
			library_panel.close()
		else:
			library_panel.visible = false
		dismissed = true
	if settings_panel != null and settings_panel.visible:
		settings_panel.visible = false
		settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dismissed = true
	if render_panel != null and render_panel.visible:
		render_panel.visible = false
		render_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dismissed = true
	if fish_store_panel != null and fish_store_panel.visible:
		fish_store_panel.visible = false
		fish_store_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dismissed = true
	if creature_creator_panel != null and creature_creator_panel.visible:
		if creature_creator_panel.has_method("close"):
			creature_creator_panel.close()
		else:
			creature_creator_panel.visible = false
		dismissed = true
	if walkthrough_overlay != null and walkthrough_overlay.visible:
		# ESC during the walkthrough finishes it (resumes the sim).
		if walkthrough_overlay.has_method("_finish"):
			walkthrough_overlay._finish()
		else:
			walkthrough_overlay.visible = false
		dismissed = true
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		var cfg := get_node_or_null("/root/TankConfig")
		if cfg != null:
			cfg.tutorial_seen = true
			cfg.save_to_disk()
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
		dismissed = true
	_dismiss_radial_menu()
	return dismissed


func _maybe_show_tutorial() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or bool(cfg.tutorial_seen):
		return
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # block input behind
	overlay.z_index = 300
	add_child(overlay)
	# Dim background so the panel reads as a modal.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			cfg.tutorial_seen = true
			cfg.save_to_disk()
			overlay.queue_free()
			_tutorial_overlay = null
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			cfg.tutorial_seen = true
			cfg.save_to_disk()
			overlay.queue_free()
			_tutorial_overlay = null)
	overlay.add_child(bg)
	# Centered panel with the gesture cheat-sheet.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200
	panel.offset_top = -160
	panel.offset_right = 200
	panel.offset_bottom = 160
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Welcome to your tank"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.6, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hints: Array[String] = [
		"• Drag to orbit",
		"• Pinch to zoom",
		"• Two-finger drag to pan",
		"• Twist two fingers to rotate",
		"• Tap a creature to follow",
		"• Double-tap to reset view",
		"• Long-press for auto-orbit",
		"• Swipe in from right edge for settings",
	]
	for h in hints:
		var lab := Label.new()
		lab.text = h
		lab.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1))
		lab.add_theme_font_size_override("font_size", 14)
		vb.add_child(lab)
	var ok := Button.new()
	ok.text = "Got it"
	ok.custom_minimum_size = Vector2(0, 48)
	ok.add_theme_font_size_override("font_size", 16)
	ok.pressed.connect(func():
		cfg.tutorial_seen = true
		cfg.save_to_disk()
		_haptic(12)
		if is_instance_valid(overlay):
			overlay.queue_free()
		_tutorial_overlay = null)
	vb.add_child(ok)
	_tutorial_overlay = overlay


# ---- Aquascape long-press radial menu (mobile only) ----
# Shown when the user long-presses inside aquascape mode. 4 buttons arranged
# around the finger position; tapping one selects the tool, tapping outside
# (or on the same press release) dismisses. Replaces the auto-orbit
# long-press gesture WHEN aquascape mode is active.
func _show_radial_menu(center: Vector2) -> void:
	_dismiss_radial_menu()
	var overlay := Control.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Tap on background dismisses without selecting.
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_dismiss_radial_menu()
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_dismiss_radial_menu())
	add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)
	# 4 tool buttons around the touch point. Lay out at 0/90/180/270 degrees.
	var defs := [
		{"key": "dirt",  "label": "dirt",  "angle": -PI / 2, "color": Color8(150, 110, 70)},
		{"key": "stone", "label": "stone", "angle": 0.0,     "color": Color8(120, 120, 130)},
		{"key": "wood",  "label": "wood",  "angle": PI / 2,  "color": Color8(95, 65, 35)},
		{"key": "dig",   "label": "dig",   "angle": PI,      "color": Color8(220, 90, 90)},
	]
	var ring_radius: float = 90.0
	var btn_size: Vector2 = Vector2(72, 56)
	for def in defs:
		var btn := Button.new()
		btn.text = String(def["label"])
		btn.custom_minimum_size = btn_size
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", def["color"])
		var key: String = String(def["key"])
		btn.pressed.connect(func():
			_aquascape_tool = key
			_refresh_tool_buttons()
			_haptic(18)
			_dismiss_radial_menu())
		var angle: float = float(def["angle"])
		var bx: float = center.x + cos(angle) * ring_radius - btn_size.x * 0.5
		var by: float = center.y + sin(angle) * ring_radius - btn_size.y * 0.5
		btn.anchor_left = 0.0
		btn.anchor_top = 0.0
		btn.anchor_right = 0.0
		btn.anchor_bottom = 0.0
		btn.offset_left = bx
		btn.offset_top = by
		btn.offset_right = bx + btn_size.x
		btn.offset_bottom = by + btn_size.y
		overlay.add_child(btn)
	_radial_menu = overlay


func _dismiss_radial_menu() -> void:
	if _radial_menu != null and is_instance_valid(_radial_menu):
		_radial_menu.queue_free()
	_radial_menu = null


# ---- Photo feedback toast ----
# Lightweight Label that flashes in for 1.5s after a photo is taken so the
# user gets visual confirmation. Mobile-only; desktop uses the existing
# verbose log.
func _show_photo_toast(path: String) -> void:
	if not _is_mobile():
		return
	var lab := Label.new()
	# Show just the filename, not the full path — useful but not noisy.
	var file_name: String = path.get_file()
	lab.text = "Photo saved: %s" % file_name
	lab.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_font_size_override("font_size", 14)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.anchor_left = 0.0
	lab.anchor_right = 1.0
	lab.anchor_top = 1.0
	lab.anchor_bottom = 1.0
	lab.offset_top = -120
	lab.offset_bottom = -90
	add_child(lab)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(lab, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lab.queue_free)
