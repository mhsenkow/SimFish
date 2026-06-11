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

const CreatureNaming = preload("res://scripts/creature_naming.gd")
const UiPanelManagerScript = preload("res://scripts/ui_panel_manager.gd")

const GLOBAL_PREFS_PATH := "user://global_prefs.cfg"


@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display
@onready var camera: Camera3D = $SubViewport/World/Camera3D
@onready var world: Node3D = $SubViewport/World
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var render_panel: PanelContainer = $RenderPanel
@onready var sound_panel: PanelContainer = $SoundPanel
@onready var fish_store_panel: PanelContainer = $FishStorePanel
@onready var library_panel: PanelContainer = $LibraryPanel
@onready var creature_creator_panel: PanelContainer = $CreatureCreatorPanel
@onready var walkthrough_overlay: Control = $WalkthroughOverlay
@onready var aquascape_palette: PanelContainer = $AquascapeToolPalette

# Top-bar HUD — restructured 2026 into clusters + chip strip. All buttons are
# unique_name_in_owner so the script paths survive future re-parenting.
@onready var top_hud: Control = $TopHUD
@onready var right_rail: Control = %RightRail
@onready var left_cluster: PanelContainer = %LeftCluster
@onready var right_cluster: PanelContainer = %RightCluster
@onready var stats_bar: PanelContainer = %StatsBar
@onready var settings_toggle: Button = %SettingsToggle
@onready var render_toggle: Button = %RenderToggle
@onready var sound_toggle: Button = %SoundToggle
@onready var fish_store_toggle: Button = %FishStoreToggle
@onready var library_toggle: Button = %LibraryToggle
@onready var creature_creator_toggle: Button = %CreatureCreatorToggle
@onready var aquascape_toggle: Button = %AquascapeToggle
@onready var notifications_toggle: Button = %NotificationsToggle
@onready var menu_button: Button = %MenuButton
@onready var portal_toggle: Button = %PortalToggle
@onready var controls_hint: Label = $ControlsHint

# Focus / immersive mode — hides chrome for an unobstructed tank view.
var _immersive_mode: bool = false
var _immersive_exit_btn: Button = null
var _light_btn: Button = null
var _light_panel: PanelContainer = null
# Top-of-panel preset picker. "custom" means "user is on their own".
var _light_preset_option: OptionButton = null
# --- Global section (drives the postprocess tint, sun, room) ---
var _light_master_check: CheckBox = null
var _light_day_cycle_check: CheckBox = null
var _light_day_phase_slider: HSlider = null
var _light_day_phase_value: Label = null
var _light_day_length_slider: HSlider = null
var _light_day_length_value: Label = null
var _light_sunset_drama_slider: HSlider = null
var _light_sunset_drama_value: Label = null
var _light_global_intensity_slider: HSlider = null
var _light_global_intensity_value: Label = null
var _light_global_warmth_slider: HSlider = null
var _light_global_warmth_value: Label = null
# --- Tank fixture section (artificial light only) ---
var _light_tank_check: CheckBox = null
var _light_caustics_check: CheckBox = null
var _light_fixture_intensity_slider: HSlider = null
var _light_fixture_intensity_value: Label = null
var _light_fixture_color_picker: ColorPickerButton = null
# --- Accent & moonlight section ---
var _light_moon_check: CheckBox = null
var _light_moon_intensity_slider: HSlider = null
var _light_moon_intensity_value: Label = null
var _light_moon_color_picker: ColorPickerButton = null
var _light_accent1_check: CheckBox = null
var _light_accent1_intensity_slider: HSlider = null
var _light_accent1_intensity_value: Label = null
var _light_accent1_color_picker: ColorPickerButton = null
var _light_accent2_check: CheckBox = null
var _light_accent2_intensity_slider: HSlider = null
var _light_accent2_intensity_value: Label = null
var _light_accent2_color_picker: ColorPickerButton = null
# --- Post-process section (surfaces palette_quantize uniforms) ---
var _light_pp_vignette_slider: HSlider = null
var _light_pp_vignette_value: Label = null
var _light_pp_vignette_falloff_slider: HSlider = null
var _light_pp_vignette_falloff_value: Label = null
var _light_pp_bloom_threshold_slider: HSlider = null
var _light_pp_bloom_threshold_value: Label = null
var _light_pp_bloom_strength_slider: HSlider = null
var _light_pp_bloom_strength_value: Label = null
var _light_pp_outline_slider: HSlider = null
var _light_pp_outline_value: Label = null
var _light_pp_dither_slider: HSlider = null
var _light_pp_dither_value: Label = null
var _light_pp_crt_slider: HSlider = null
var _light_pp_crt_value: Label = null
var _light_pp_region_dither_check: CheckBox = null
var _light_pp_bank_lock_check: CheckBox = null
# --- Ambient / biolum / caustic strength (the "v2 quick wins") ---
var _light_ambient_floor_slider: HSlider = null
var _light_ambient_floor_value: Label = null
var _light_biolum_slider: HSlider = null
var _light_biolum_value: Label = null
var _light_caustic_strength_slider: HSlider = null
var _light_caustic_strength_value: Label = null
# --- Per-phase color override (#14) ---
var _light_tod_override_check: CheckBox = null
var _light_tod_dawn_picker: ColorPickerButton = null
var _light_tod_day_picker: ColorPickerButton = null
var _light_tod_dusk_picker: ColorPickerButton = null
var _light_tod_night_picker: ColorPickerButton = null
# --- Sun direction 2D pad (#5) ---
var _light_sun_pad: Control = null
# Set to true while a preset is being applied programmatically so the
# slider-change handlers don't snap the preset back to "custom".
var _light_applying_preset: bool = false

# Stat chip refs — built once in _ready, value labels updated on stats_changed.
# Keys: "state", "fauna", "flora", "water", "alert".
var _chips: Dictionary = {}
# Layout breakpoint — last computed, drives _apply_hud_layout decisions.
var _hud_layout: String = ""
var _rail_dock: String = ""
var _rail_vbox: VBoxContainer = null
var _rail_hbox: HBoxContainer = null
var _rail_spacer: Control = null
var _last_rail_sync_hash: int = -1
# Tracks last mobile orientation used for internal render sizing.
# -1 = unset, 0 = landscape, 1 = portrait.
var _mobile_render_orientation: int = -1
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
# Portrait-cylinder camera defaults. A tall round tank seen from a portrait
# phone reads best with the camera level (low pitch), pulled back further
# (cylinder is taller than the standard box), and looking at mid-height.
# Computed dynamically in _default_camera_for_tank() so it tracks the
# tank's actual height instead of hard-coding.
const PORTRAIT_DEFAULT_PITCH := 0.18
const PORTRAIT_DEFAULT_YAW := -0.35

var target: Vector3 = DEFAULT_TARGET
var radius: float = DEFAULT_RADIUS
var yaw: float = DEFAULT_YAW
var pitch: float = DEFAULT_PITCH


# Pick camera defaults that frame the current tank well. Tall cylinders in
# a portrait viewport get pulled back further and looked at level (low
# pitch) so the user sees the full water column top-to-bottom. Wide boxes
# in landscape keep the classic 3/4 perspective. Returns {target, radius,
# yaw, pitch} so callers can apply uniformly.
func _default_camera_for_tank() -> Dictionary:
	var cfg := get_node_or_null("/root/TankConfig")
	var shape: String = String(cfg.get("tank_shape")) if cfg != null else "box"
	var tank_h: float = float(cfg.get("tank_height")) if cfg != null else 7.0
	var tank_hw: float = float(cfg.get("tank_half_w")) if cfg != null else 8.0
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1536, 864)
	var portrait: bool = vp.y > vp.x * 1.02
	# Tall round tank seen on a tall screen: portrait camera.
	if shape == "cylinder" and portrait:
		var radius_px: float = clampf(tank_h * 1.65 + tank_hw * 1.6, 9.0, 28.0)
		return {
			"target": Vector3(0.0, tank_h * 0.42, 0.0),
			"radius": radius_px,
			"yaw": PORTRAIT_DEFAULT_YAW,
			"pitch": PORTRAIT_DEFAULT_PITCH,
		}
	# Anything else: classic 3/4 box-tank defaults.
	return {
		"target": DEFAULT_TARGET,
		"radius": DEFAULT_RADIUS,
		"yaw": DEFAULT_YAW,
		"pitch": DEFAULT_PITCH,
	}


# Apply the shape-aware defaults to the camera state. Used by F-key reset,
# double-tap reset, and the new "Reset view" button in the Camera Views
# panel. Calls _apply_camera() at the end so the change is immediate.
func _reset_camera_to_default() -> void:
	var d: Dictionary = _default_camera_for_tank()
	target = d["target"]
	radius = d["radius"]
	yaw = d["yaw"]
	pitch = d["pitch"]
	_follow_target = null
	_auto_orbit = false
	_apply_camera()


# ---- Camera Views panel API ----
# Called by the Camera Views panel's preset buttons. Each preset frames the
# tank from a distinctive angle. Cylinder tanks scale the radius up to keep
# the full vertical column in frame. Box tanks use their half-width.
func apply_camera_preset(preset_id: String) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	var shape: String = String(cfg.get("tank_shape")) if cfg != null else "box"
	var tank_h: float = float(cfg.get("tank_height")) if cfg != null else 7.0
	var tank_hw: float = float(cfg.get("tank_half_w")) if cfg != null else 8.0
	var tank_hd: float = float(cfg.get("tank_half_d")) if cfg != null else 4.0
	var base_r: float = maxf(tank_h * 1.5, maxf(tank_hw, tank_hd) * 2.4)
	_follow_target = null
	_auto_orbit = false
	match preset_id:
		"front":
			# Looking down the +Z axis at the front face. Camera level.
			target = Vector3(0.0, tank_h * 0.42, 0.0)
			yaw = 0.0
			pitch = 0.0
			radius = base_r
		"side":
			# Looking down the +X axis at the side. Camera level.
			target = Vector3(0.0, tank_h * 0.42, 0.0)
			yaw = -PI * 0.5
			pitch = 0.0
			radius = base_r
		"top":
			# Bird's-eye down. Particularly useful for cylinder tanks.
			# In this codebase y = sin(pitch), so POSITIVE pitch puts the
			# camera ABOVE the target — i.e. looking down. (DEFAULT_PITCH
			# is +0.48 for the same reason.) Just shy of MAX_PITCH (1.45)
			# so the up vector stays sane and look_at doesn't flip.
			target = Vector3(0.0, tank_h * 0.5, 0.0)
			yaw = 0.0
			pitch = 1.40
			radius = maxf(tank_hw, tank_hd) * 3.4
		"three_quarter":
			# Classic perspective from front-right, slight tilt down.
			target = Vector3(0.0, tank_h * 0.4, 0.0)
			yaw = -0.55
			pitch = 0.48
			radius = base_r * 1.05
		_:
			_reset_camera_to_default()
			return
	radius = clampf(radius, MIN_RADIUS, MAX_RADIUS)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	_apply_camera()
	_haptic(10)


func save_camera_view_slot(idx: int) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var view: Dictionary = {
		"target_x": target.x, "target_y": target.y, "target_z": target.z,
		"radius": radius, "yaw": yaw, "pitch": pitch,
		"fov": float(camera.fov) if camera != null else 55.0,
	}
	match idx:
		0: cfg.camera_view_slot_a = view
		1: cfg.camera_view_slot_b = view
		2: cfg.camera_view_slot_c = view
	cfg.save_to_disk()
	_haptic(18)


func recall_camera_view_slot(idx: int) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var view: Dictionary = {}
	match idx:
		0: view = cfg.camera_view_slot_a
		1: view = cfg.camera_view_slot_b
		2: view = cfg.camera_view_slot_c
	if view.is_empty():
		return  # never saved
	target = Vector3(float(view.get("target_x", 0.0)),
		float(view.get("target_y", 3.0)), float(view.get("target_z", 0.0)))
	radius = clampf(float(view.get("radius", DEFAULT_RADIUS)), MIN_RADIUS, MAX_RADIUS)
	yaw = float(view.get("yaw", DEFAULT_YAW))
	pitch = clampf(float(view.get("pitch", DEFAULT_PITCH)), MIN_PITCH, MAX_PITCH)
	_follow_target = null
	_auto_orbit = false
	_apply_camera()
	if camera != null and view.has("fov"):
		camera.fov = float(view["fov"])
	_haptic(12)


func set_auto_orbit_speed(v: float) -> void:
	AUTO_ORBIT_SPEED = clampf(v, 0.0, 1.0)


func set_camera_fov(v: float) -> void:
	if camera != null:
		camera.fov = clampf(v, 20.0, 110.0)
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.camera_fov = float(camera.fov) if camera != null else v


# Orthographic-projection world-space "size" — analogue of FOV for ortho
# cameras. Larger = wider view (zoom out). Stored on the camera; not
# persisted to TankConfig because perspective is the primary mode and the
# ortho size is recomputed when the user switches projection.
func set_camera_ortho_size(v: float) -> void:
	if camera != null:
		camera.size = clampf(v, 2.0, 80.0)


# Switch the camera projection. Each mode optionally snaps yaw/pitch to a
# canonical angle so the result reads as "isometric" / "top-down" /etc
# instead of needing the user to dial it in by hand. Pass-through camera
# state is preserved otherwise (target + radius stay put).
# All "looking down" angles are POSITIVE in this codebase's pitch convention
# (y = sin(pitch), so +pitch puts the eye above the target). DEFAULT_PITCH
# is +0.48 for the same reason — see _apply_camera.
const _ISO_YAW: float = -PI * 0.25       # 45° around Y
const _ISO_PITCH: float = 0.6155         # atan(1/sqrt(2)) ≈ 35.26° looking down
const _DIMETRIC_PITCH: float = 0.4636    # atan(1/2) ≈ 26.57° (2:1 tile look)
const _TOPDOWN_PITCH: float = 1.40       # near-vertical, just under MAX_PITCH 1.45

var _current_projection_id: String = "perspective"


func apply_camera_projection(proj_id: String) -> void:
	if camera == null:
		return
	_current_projection_id = proj_id
	match proj_id:
		"perspective":
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			# Restore the user's last FOV if Light panel had one saved.
			var cfg := get_node_or_null("/root/TankConfig")
			if cfg != null:
				camera.fov = float(cfg.get("camera_fov") if cfg.get("camera_fov") != null else 55.0)
		"orthographic":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			# Pick an ortho size that roughly matches what the current
			# perspective view was showing — uses tank-relative metric so
			# the switch isn't jarring. Falls back to a sensible default.
			camera.size = _ortho_size_from_tank()
		"isometric":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = _ortho_size_from_tank()
			yaw = _ISO_YAW
			pitch = _ISO_PITCH
			_auto_orbit = false
			_follow_target = null
			_apply_camera()
			_haptic(15)
		"dimetric":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = _ortho_size_from_tank()
			yaw = _ISO_YAW
			pitch = _DIMETRIC_PITCH
			_auto_orbit = false
			_follow_target = null
			_apply_camera()
			_haptic(15)
		"top_down_ortho":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = _ortho_size_from_tank() * 1.2
			pitch = _TOPDOWN_PITCH
			_auto_orbit = false
			_follow_target = null
			_apply_camera()
			_haptic(12)


func get_camera_projection_id() -> String:
	return _current_projection_id


# Pick a reasonable ortho viewport size from the live tank dimensions.
# Used both on initial projection switch and when the panel needs a
# starting value for the size slider.
func _ortho_size_from_tank() -> float:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 18.0
	var tank_h: float = float(cfg.get("tank_height") if cfg.get("tank_height") != null else 7.0)
	var tank_hw: float = float(cfg.get("tank_half_w") if cfg.get("tank_half_w") != null else 8.0)
	return clampf(maxf(tank_h * 1.4, tank_hw * 2.6), 6.0, 60.0)


func follow_random_fish() -> void:
	if _sim == null:
		return
	var fish_arr: Variant = _sim.get("fish")
	if not (fish_arr is Array) or (fish_arr as Array).is_empty():
		return
	var pool: Array = []
	for f in (fish_arr as Array):
		if is_instance_valid(f):
			pool.append(f)
	if pool.is_empty():
		return
	_follow_target = pool[randi() % pool.size()]
	_auto_orbit = false
	_haptic(12)


func clear_follow_target() -> void:
	_follow_target = null


# Add a Camera Views toggle to the right rail at runtime. Keeps the .tscn
# file simple and means the button picks up whatever theme/sizing the rest
# of the cluster uses. Inserted above the existing RailDivider so it sits
# in the "view tools" group (Light / Render / Sound) instead of the modal
# cluster (Library / Store / Creator).
func _install_camera_views_rail_button() -> void:
	var cluster_vbox: Node = get_node_or_null("RightRail/RightCluster/VBox")
	if cluster_vbox == null:
		return
	var btn := Button.new()
	btn.name = "CameraViewsToggle"
	btn.text = "📷"
	btn.tooltip_text = "Camera views — presets, projection, FOV (V)"
	btn.custom_minimum_size = Vector2(48, 48)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_toggle_camera_views_panel)
	cluster_vbox.add_child(btn)
	# Place it just above the divider so it groups with the view-tool
	# cluster (Render / Sound / Settings). If the divider isn't found
	# (older scene), it stays at the end which is still discoverable.
	var divider: Node = cluster_vbox.get_node_or_null("RailDivider")
	if divider != null:
		cluster_vbox.move_child(btn, divider.get_index())


# Lazy-build the Camera Views panel and toggle its visibility. Anchored
# bottom-right (above the mobile HUD action row); becomes visible/hidden
# in place. Calls sync_from_main on open so toggles reflect current state.
func _toggle_camera_views_panel() -> void:
	if _camera_views_panel == null:
		var script := load("res://scripts/camera_views_panel.gd")
		_camera_views_panel = script.new() as Control
		_camera_views_panel.name = "CameraViewsPanel"
		_camera_views_panel.set("main_ref", self)
		add_child(_camera_views_panel)
		# Position: anchored top-right, indented from the right rail.
		# Stays inside the viewport on rotation thanks to size_changed
		# reflow handled by Control anchors.
		_camera_views_panel.anchor_left = 1.0
		_camera_views_panel.anchor_top = 0.0
		_camera_views_panel.anchor_right = 1.0
		_camera_views_panel.anchor_bottom = 0.0
		_camera_views_panel.offset_left = -340.0
		_camera_views_panel.offset_top = 64.0
		_camera_views_panel.offset_right = -16.0
		_camera_views_panel.offset_bottom = 580.0
		_camera_views_panel.z_index = 130
	_camera_views_panel.visible = not _camera_views_panel.visible
	if _camera_views_panel.visible and _camera_views_panel.has_method("sync_from_main"):
		_camera_views_panel.sync_from_main()


const SENSITIVITY: float = 0.006
const ZOOM_FACTOR: float = 1.12
const MIN_RADIUS: float = 3.0
const MAX_RADIUS: float = 40.0
const MIN_PITCH: float = -1.45
const MAX_PITCH: float = 1.45
const PAN_SPEED: float = 6.0
# Auto-orbit angular speed (rad/sec). Now a var so the Camera Views panel
# can tune it live; default mirrors the old const value.
var AUTO_ORBIT_SPEED: float = 0.08
# Camera Views panel instance (lazy-built in _ready).
var _camera_views_panel: Control = null

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

# Aquascape sculpting (terrain, hardscape, trim, unified undo).
var _aquascape := AquascapeController.new()
const INVALID_HIT: Vector3 = Vector3(INF, INF, INF)
# Saved sim speed while the guided walkthrough holds the sim paused.
var _wt_saved_time_scale: float = 1.0
# Screen-space pick radius in SubViewport pixels (what you click on screen).
const PICK_RADIUS_PX: float = 48.0
# Desktop LMB: tight radius so open-water clicks feed instead of snapping to fish.
const PICK_RADIUS_PX_CLICK: float = 26.0
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
# Camera-motion deadzone. A drag has to move at least DRAG_DEADZONE_PX before
# orbit/pan/dolly start applying. Without this, every tap that drifts a pixel
# or two between touch-down and lift micro-rotates the camera AND eats the
# tap event — the most common "this feels unfinished" mobile bug. 8dp is the
# Material guideline for "touch slop".
const DRAG_DEADZONE_PX: float = 8.0
# Set once per drag-start; flips true the moment cumulative motion crosses
# DRAG_DEADZONE_PX. Camera-motion code only fires when this is true.
var _drag_committed: bool = false
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
# Compatibility fields for older discovery-toast UI flow.
# Current path routes discovery events through notification toasts, but keeping
# these declarations avoids parser/runtime issues if older references remain.
var _discovery_toast: Control = null
var _discovery_toast_tween: Tween = null

# ---- Notification center + toast feed ----
const NOTIF_MAX_HISTORY: int = 300
const NOTIF_TOAST_MAX_ACTIVE: int = 3
const NOTIF_SORT_NEWEST: int = 0
const NOTIF_SORT_OLDEST: int = 1
const NOTIF_SORT_SEVERITY: int = 2
const NOTIF_FILTER_ALL: String = "all"
const NOTIF_SEVERITY_INFO: String = "info"
const NOTIF_SEVERITY_IMPORTANT: String = "important"
const NOTIF_SEVERITY_CRITICAL: String = "critical"

var _notifications: Array[Dictionary] = []
var _notification_next_id: int = 1
var _notification_filter_kind: String = NOTIF_FILTER_ALL
var _notification_filter_severity: String = NOTIF_FILTER_ALL
var _notification_sort: int = NOTIF_SORT_NEWEST
var _notification_story_idx: int = 0
var _notification_toast_queue: Array[Dictionary] = []
var _notification_toast_active: int = 0

var _notifications_panel: PanelContainer = null
var _notifications_list: VBoxContainer = null
var _notifications_empty_label: Label = null
var _notifications_filter_kind: OptionButton = null
var _notifications_filter_severity: OptionButton = null
var _notifications_sort: OptionButton = null
var _notifications_toast_layer: Control = null

var _water_alert_low_o2_active: bool = false
var _water_alert_ammonia_active: bool = false
var _water_alert_nitrite_active: bool = false

var _welcome_toast_tween: Tween = null

# Panel exclusivity + modal backdrop.
var _ui_panels: UiPanelManager = UiPanelManagerScript.new()

# Consolidated rail (5 groups).
var _rail_create_btn: Button = null
var _rail_world_btn: Button = null
var _rail_appearance_btn: Button = null
var _rail_system_btn: Button = null
var _rail_alerts_btn: Button = null
var _rail_flyout: PanelContainer = null
var _rail_flyout_vbox: VBoxContainer = null
var _notif_badge: Label = null

# Cheat sheet + first-session coachmarks.
var _cheat_sheet: Control = null
var _coachmark_overlay: Control = null
var _coachmark_step: int = 0

# Tap-to-feed: 9/0 cycles type; plain click/tap on water drops food.
var _feed_subtype: int = WasteParticle.FOOD_SUB_PELLET
const _FEED_TYPE_LABELS: Array[String] = [
	"Flakes", "Pellets", "Bloodworm", "Algae wafer",
]
var _feed_toast: Label = null
var _feed_toast_tween: Tween = null


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
	_apply_portrait_camera_defaults_if_unsaved()
	_apply_camera()
	# Subscribe to SimDriver stats - they emit at ~1Hz with the ecosystem snapshot.
	await get_tree().process_frame
	_sim = world.get_node_or_null("SimDriver")
	if _sim != null and _sim.has_signal("stats_changed"):
		_sim.connect("stats_changed", _on_stats_changed)
	_ui_panels.setup(self)
	# Hook rail buttons through the panel manager (exclusivity + modal backdrop).
	if settings_toggle != null:
		settings_toggle.pressed.connect(func(): _ui_toggle_side(UiPanelManager.SIDE_SETTINGS))
	if render_toggle != null:
		render_toggle.pressed.connect(func(): _ui_toggle_side(UiPanelManager.SIDE_RENDER))
	if sound_toggle != null:
		sound_toggle.pressed.connect(func(): _ui_toggle_side(UiPanelManager.SIDE_SOUND))
	if fish_store_toggle != null:
		fish_store_toggle.pressed.connect(func(): _ui_toggle_modal(UiPanelManager.MODAL_STORE))
	if library_toggle != null:
		library_toggle.pressed.connect(func(): _ui_toggle_modal(UiPanelManager.MODAL_LIBRARY))
	if creature_creator_toggle != null:
		creature_creator_toggle.pressed.connect(func(): _ui_toggle_modal(UiPanelManager.MODAL_CREATOR))
	if notifications_toggle != null:
		notifications_toggle.pressed.connect(func(): _ui_toggle_side(UiPanelManager.SIDE_NOTIFICATIONS))
	# Insert a discoverable Camera Views rail button. Programmatic rather
	# than in the .tscn so it picks up the same VBox styling and adapts to
	# whatever rail dock the player ends up on. Inserted just above the
	# RailDivider so it lives in the "view tools" group alongside the
	# Light / Render / Sound toggles instead of the Modal cluster.
	_install_camera_views_rail_button()
	_setup_panel_close_hooks()
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
	_add_immersive_toggle_button()
	_aquascape.setup(self, camera, world, aquascape_palette)
	
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
	_setup_hud_styling()
	_add_tank_lights_toggle()
	_ensure_notifications_ui()
	_build_hud_chips()
	_setup_rail_groups()
	_on_viewport_resized()
	get_viewport().size_changed.connect(_on_viewport_resized)

	# ---- Mobile setup ----
	if _is_mobile():
		_pick_device_tier_if_unset()
		_setup_mobile_ui()
		# Drop the physics tick rate. SimDriver._physics_process gates on its
		# own SIM_DT accumulator (10Hz), so a 60Hz physics_process spends
		# most ticks doing nothing but waking the CPU. 30Hz on mobile lets
		# the chip coast between sim ticks and noticeably reduces thermal
		# load on devices like the Pixel that throttle aggressively.
		Engine.physics_ticks_per_second = 30
	call_deferred("_maybe_show_tutorial")
	call_deferred("_maybe_show_coachmarks")
	if controls_hint != null:
		controls_hint.visible = false
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
	_sync_rail_toggles()
	print_verbose("[walstad_loom] PiP portal %s" % ("OPEN" if _portal_open else "CLOSED"))


func _restore_camera_state() -> void:
	# Pull preserved camera yaw/pitch/radius/target from TankConfig if the
	# user has saved it (i.e. they Applied settings at least once and we
	# stashed the current view before reload).
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not cfg.camera_state_saved:
		return
	yaw = float(cfg.camera_yaw)
	pitch = float(cfg.camera_pitch)
	radius = float(cfg.camera_radius)
	target = Vector3(
		float(cfg.camera_target_x),
		float(cfg.camera_target_y),
		float(cfg.camera_target_z),
	)


func _apply_portrait_camera_defaults_if_unsaved() -> void:
	if not _is_mobile():
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or cfg.camera_state_saved:
		return
	# Use the shape-aware defaults helper. It already knows that a cylinder
	# in a portrait viewport wants different framing from a box in landscape,
	# and tracks the tank's actual height/half-width, so users get a tight
	# default crop regardless of which orientation they picked at new-tank
	# time. Falls through to the landscape defaults on a landscape phone.
	var d: Dictionary = _default_camera_for_tank()
	target = d["target"]
	radius = d["radius"]
	yaw = d["yaw"]
	pitch = d["pitch"]


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
	var render_w: int = int(cfg.render_width)
	var render_h: int = int(cfg.render_height)
	if _is_mobile():
		var oriented: Vector2i = _oriented_mobile_render_size(render_w, render_h)
		render_w = oriented.x
		render_h = oriented.y
	# SubViewport size.
	sub_viewport.size = Vector2i(render_w, render_h)
	# MSAA: 0=disabled, 1=2x, 2=4x, 3=8x (matches Viewport.MSAA enum).
	sub_viewport.msaa_3d = int(cfg.msaa) as Viewport.MSAA
	# Palette quantize shader uniforms.
	if display.material is ShaderMaterial:
		var sm: ShaderMaterial = display.material
		# Set dither strength + internal resolution.
		sm.set_shader_parameter("dither_strength", float(cfg.dither_strength))
		sm.set_shader_parameter("internal_resolution",
			Vector2(float(render_w), float(render_h)))
		sm.set_shader_parameter("region_aware_dither",
			1.0 if cfg.dither_region_aware else 0.0)
		sm.set_shader_parameter("palette_bank_lock",
			1.0 if cfg.palette_bank_lock else 0.0)
		sm.set_shader_parameter("outline_strength", float(cfg.outline_strength))
		sm.set_shader_parameter("crt_strength", float(cfg.crt_strength))
		sm.set_shader_parameter("material_hue_shift", float(cfg.material_hue_shift))
		sm.set_shader_parameter("material_saturation", float(cfg.material_saturation))
		sm.set_shader_parameter("material_warmth", float(cfg.material_warmth))
		sm.set_shader_parameter("material_value", float(cfg.material_value))
		var world_vis := world.get_node_or_null("AquariumVisuals") as AquariumVisuals
		if world_vis != null:
			sm.set_shader_parameter("seasonal_warmth", world_vis.seasonal_palette_shift())
	# Integer upscale: lock the display rect to an integer multiple of the
	# SubViewport size, centered, letterboxed with the parent control's
	# background. Off → full-rect anchored display (default).
	_apply_display_layout()
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
	apply_material_palette()


func apply_material_palette() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var water_mat: ShaderMaterial = null
	if world != null and world.get("_water_material_ref") != null:
		var wm: Variant = world.get("_water_material_ref")
		if wm is ShaderMaterial:
			water_mat = wm
	VoxelMat.apply_global_palette(cfg, water_mat)
	if display != null and display.material is ShaderMaterial:
		var sm: ShaderMaterial = display.material
		sm.set_shader_parameter("material_hue_shift", float(cfg.material_hue_shift))
		sm.set_shader_parameter("material_saturation", float(cfg.material_saturation))
		sm.set_shader_parameter("material_warmth", float(cfg.material_warmth))
		sm.set_shader_parameter("material_value", float(cfg.material_value))


func _process(dt: float) -> void:
	_aquascape.tick_paint_cooldown(dt)

	# Top-HUD idle-dim. Mirrors MobileHUD: after HUD_IDLE_DIM_SECONDS of no
	# input, fade the top bar so it stops competing with the scene.
	# _notify_hud_input() (called from _input + touch handlers) resets this.
	_hud_idle_seconds += dt
	if _hud_idle_seconds > HUD_IDLE_DIM_SECONDS:
		if top_hud != null and top_hud.modulate != HUD_DIM_MODULATE:
			top_hud.modulate = HUD_DIM_MODULATE
		if right_rail != null and right_rail.modulate != HUD_DIM_MODULATE:
			right_rail.modulate = HUD_DIM_MODULATE

	# Time-of-day palette tint. Drives the palette_quantize shader's
	# multiplicative tint so the same 48-color palette breathes between
	# dawn / day / dusk / night without needing 4 distinct PNGs. Cheap:
	# a vec3 set per frame on a single ShaderMaterial.
	_update_palette_tod_tint()

	# Frame-time sampling — feeds the render panel's mini-graph + the
	# adaptive quality controller below. Both are no-ops without the
	# corresponding TankConfig toggle, so the cost is just one append.
	_record_frame_time(dt)
	_adaptive_quality_tick(dt)

	# Periodic autosave. Only ticks the accumulator when we're actually
	# playing (not aquascape-paused, not manually paused) so the 5-minute
	# clock measures user-attention not wall-clock.
	if _sim != null and not _aquascape.is_active and float(_sim.time_scale) > 0.0:
		_autosave_accum += dt
		if _autosave_accum >= AUTOSAVE_INTERVAL_S:
			_autosave_accum = 0.0
			save_active_tank(not get_window().has_focus())

	# Player-glance hook. Push the camera's world position into the sim
	# so bold fish can drift over when the player leans into the glass.
	# Cheap (1 vec assignment + a few clamps + a distance) — runs every
	# frame is fine. The fish.gd side only consults it on its 10 Hz tick.
	if _sim != null and camera != null and _sim.has_method("update_player_glance"):
		_sim.update_player_glance(camera.global_position)
	
	# ---- Touch: long-press detection (runs every frame while finger is down) ----
	if _touches.size() == 1 and not _long_press_fired:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - _tap_start_time
		if elapsed >= LONG_PRESS_TIME and _tap_moved < TAP_MAX_MOVE:
			_long_press_fired = true
			# Aquascape mode: pop a radial tool picker centered on the finger.
			# Normal mode: keep the existing auto-orbit toggle. Painting that
			# was started on touch-down gets cancelled so the menu doesn't
			# also drop a voxel.
			if _aquascape.is_active:
				_drag_mode = ""
				_aquascape.end_drag()
				_haptic(22)
				_show_radial_menu(_tap_start_pos)
			else:
				_auto_orbit = not _auto_orbit
				_haptic(15)
				print_verbose("[walstad_loom] long-press: auto-orbit %s" % ("ON" if _auto_orbit else "OFF"))
	
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

	_sync_rail_toggles()

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
				_reset_camera_to_default()
				moved = false  # _reset_camera_to_default already called _apply_camera
			if moved:
				_apply_camera()

	# Timelapse + live state chip (needs dt from _process).
	if _timelapse_active:
		_timelapse_accum += dt
		if _timelapse_accum >= TIMELAPSE_INTERVAL:
			_timelapse_accum = 0.0
			var frame_path: String = "%s/frame_%05d.png" % [_timelapse_dir, _timelapse_index]
			_timelapse_index += 1
			_request_viewport_image(_save_timelapse_frame.bind(frame_path))
	_refresh_state_chip()
	if _light_panel != null and _light_panel.visible:
		_refresh_light_panel_live()


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
		_drag_committed = false
		if mmb:
			_drag_mode = "pan"
			_drag_button = MOUSE_BUTTON_MIDDLE
		elif rmb:
			_drag_button = MOUSE_BUTTON_RIGHT
			_drag_mode = "orbit" if _aquascape.is_active else "dolly"
		else:
			_drag_button = MOUSE_BUTTON_LEFT
			if pan_modifier:
				_drag_mode = "pan"
			elif _aquascape.is_active:
				if _begin_aquascape_drag(mouse_now):
					_drag_mode = "wood_drag"
				else:
					_drag_mode = "paint"
					_aquascape.place(mouse_now)
			else:
				_drag_mode = "orbit"
	elif not any_btn and _orbiting:
		_orbiting = false
		_aquascape.end_drag()
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
		# Deadzone: don't engage orbit/pan/dolly until the cursor has moved
		# at least DRAG_DEADZONE_PX since mousedown. Paint and wood_drag are
		# exempt — those are tool actions, not navigation, and need to fire
		# on the click itself. Once committed, stays committed for the
		# duration of this drag.
		if not _drag_committed and _drag_total >= DRAG_DEADZONE_PX:
			_drag_committed = true
		var nav_committed: bool = _drag_committed \
				or _drag_mode == "paint" or _drag_mode == "wood_drag"
		if delta.length_squared() > 0.0 and nav_committed:
			match _drag_mode:
				"pan":
					_pan_target(delta)
				"dolly":
					radius = clampf(radius * (1.0 + delta.y * DOLLY_MOUSE_SENSITIVITY),
						MIN_RADIUS, MAX_RADIUS)
					_apply_camera()
				"paint":
					if _aquascape.can_paint():
						_aquascape.place(mouse_now)
						_aquascape.mark_painted()
				"wood_drag":
					_aquascape.drag_hardscape(mouse_now)
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
		_handle_shortcut(KEY_V, _toggle_camera_views_panel)
		_handle_shortcut(KEY_1, func(): _on_one())
		_handle_shortcut(KEY_2, func(): _on_two())
		_handle_shortcut(KEY_3, func(): _on_three())
		_handle_shortcut(KEY_4, func(): _on_four())
		_handle_shortcut(KEY_5, func(): _on_five())
		_handle_shortcut(KEY_6, func(): _on_six())
		_handle_shortcut(KEY_7, func(): _on_seven())
		_handle_shortcut(KEY_8, func(): _on_eight())
		if _aquascape.is_active:
			_handle_shortcut(KEY_BRACKETLEFT, func(): _aquascape.adjust_brush(-1))
			_handle_shortcut(KEY_BRACKETRIGHT, func(): _aquascape.adjust_brush(1))
		var m_down: bool = Input.is_key_pressed(KEY_M)
		var m_was: bool = _key_was_pressed.get(KEY_M, false)
		if m_down and not m_was:
			if Input.is_key_pressed(KEY_SHIFT):
				_toggle_motion_debug()
			else:
				_ui_toggle_side(UiPanelManager.SIDE_SOUND)
		_key_was_pressed[KEY_M] = m_down
		_handle_shortcut(KEY_O, func(): _ui_toggle_side(UiPanelManager.SIDE_SETTINGS))
		_handle_shortcut(KEY_9, func(): _cycle_feed_subtype(-1))
		_handle_shortcut(KEY_0, func(): _cycle_feed_subtype(1))
		_handle_shortcut(KEY_F12, _take_photo)
		_handle_shortcut(KEY_ESCAPE, _clear_follow)
		_handle_shortcut(KEY_C, _toggle_portal)
		_handle_shortcut(KEY_T, _toggle_timelapse)
		_handle_shortcut(KEY_B, _toggle_aquascape)
		_handle_shortcut(KEY_H, _toggle_immersive_mode)
		_handle_shortcut(KEY_BACKSPACE, _aquascape_undo)
		_handle_shortcut(KEY_DELETE, _aquascape_undo)

	# Aquascape preview voxel: shown at the substrate projection of the
	# current mouse/touch position, ONLY when in aquascape mode.
	var cursor_pos: Vector2 = _touches.values()[0] if _touches.size() > 0 else get_window().get_mouse_position()
	if _aquascape.is_active:
		_aquascape.update_preview(cursor_pos)


func _update_aquascape_preview(mouse_pos: Vector2) -> void:
	_aquascape.update_preview(mouse_pos)


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


const GLASS_TAP_RADIUS: float = 14.0
const GLASS_TAP_RADIUS_SQ: float = GLASS_TAP_RADIUS * GLASS_TAP_RADIUS


func _startle_fish_near_tap(mouse_pos: Vector2) -> void:
	if _sim == null:
		return
	if _click_hits_interactive_hud(mouse_pos):
		return
	var hit: Vector3 = _project_to_surface(mouse_pos)
	if hit == INVALID_HIT:
		return
	if world != null and world.has_method("spawn_glass_tap_ripples"):
		world.spawn_glass_tap_ripples(hit)
	elif world != null and world.has_method("spawn_burst_ripple"):
		world.spawn_burst_ripple(hit, 1.75)
	if _sim.has_method("pulse_glass_tap"):
		_sim.pulse_glass_tap(hit)
	_haptic(14)
	for f in _sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var dx: float = f.position.x - hit.x
		var dz: float = f.position.z - hit.z
		var d2_xz: float = dx * dx + dz * dz
		if d2_xz > GLASS_TAP_RADIUS_SQ:
			continue
		var dist: float = sqrt(d2_xz)
		var prox: float = 1.0 - clampf(dist / GLASS_TAP_RADIUS, 0.0, 1.0)
		var away_xz: Vector3 = Vector3(dx, 0.0, dz)
		if away_xz.length_squared() < 1e-4:
			away_xz = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
		var away: Vector3 = away_xz.normalized()
		var toward: Vector3 = -away
		# Inner ring: some fish dart toward the tap (curiosity). Outer: flee.
		var curious: bool = dist < 7.0 and prox > 0.42 and randf() < 0.38
		if curious:
			f.heading_offset = toward * lerpf(0.55, 1.1, prox)
			f._startle_heading = toward
			f._startle_remaining = lerpf(0.22, 0.42, prox)
			f.burst_remaining = maxf(float(f.burst_remaining), lerpf(0.22, 0.38, prox))
		else:
			f.burst_remaining = maxf(float(f.burst_remaining), lerpf(0.38, 0.78, prox))
			f.heading_offset = away * lerpf(0.9, 1.9, prox)
			f._startle_heading = away
			f._startle_remaining = lerpf(0.28, 0.58, prox)
			f.stress = clampf(float(f.stress) + prox * 0.14, 0.0, 1.0)


func _drop_food_at_cursor(mouse_pos: Vector2) -> bool:
	if _sim == null or _aquascape.is_active:
		return false
	if display == null or not display.get_global_rect().has_point(mouse_pos):
		return false
	if _click_hits_interactive_hud(mouse_pos):
		return false
	var hit: Vector3 = _project_to_surface(mouse_pos)
	if hit == INVALID_HIT:
		return false
	if _sim.has_method("spawn_player_food"):
		_sim.spawn_player_food(hit, _feed_subtype)
	else:
		_sim._spawn_waste(hit, 0.45, WasteParticle.KIND_FOOD, _feed_subtype)
	_alert_fish_to_feed(hit, _feed_subtype)
	_show_feed_toast(_FEED_TYPE_LABELS[_feed_subtype])
	_haptic(10)
	return true


func _cycle_feed_subtype(delta: int) -> void:
	_feed_subtype = posmod(_feed_subtype + delta, _FEED_TYPE_LABELS.size())
	_show_feed_toast("Food: %s (tap water to drop)" % _FEED_TYPE_LABELS[_feed_subtype])


func _alert_fish_to_feed(hit: Vector3, food_subtype: int) -> void:
	if _sim == null:
		return
	var radius_sq: float = 196.0 if food_subtype == WasteParticle.FOOD_SUB_WORM else 81.0
	for f in _sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var d2: float = f.position.distance_squared_to(hit)
		if d2 > radius_sq:
			continue
		var to_food: Vector3 = hit - f.position
		if to_food.length_squared() < 1e-4:
			continue
		to_food = to_food.normalized()
		f.heading_offset = to_food * lerpf(0.5, 1.2, 1.0 - sqrt(d2 / radius_sq))
		if food_subtype == WasteParticle.FOOD_SUB_WORM:
			f.burst_remaining = maxf(float(f.burst_remaining), 0.55)
			f._startle_heading = to_food
			f._startle_remaining = 0.35
		elif food_subtype == WasteParticle.FOOD_SUB_FLAKE and int(f.mouth_orientation) < 0:
			f.burst_remaining = maxf(float(f.burst_remaining), 0.35)


func _show_feed_toast(text: String) -> void:
	if _feed_toast == null or not is_instance_valid(_feed_toast):
		_feed_toast = Label.new()
		_feed_toast.name = "FeedToast"
		_feed_toast.add_theme_font_size_override("font_size", 13)
		_feed_toast.add_theme_color_override("font_color", Color(0.95, 0.92, 0.75))
		_feed_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feed_toast.anchor_left = 0.5
		_feed_toast.anchor_right = 0.5
		_feed_toast.anchor_top = 1.0
		_feed_toast.offset_left = -160.0
		_feed_toast.offset_right = 160.0
		_feed_toast.offset_top = -(_hud_bottom_inset() + 28.0)
		_feed_toast.offset_bottom = -(_hud_bottom_inset() + 8.0)
		_feed_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_feed_toast)
	if _feed_toast_tween != null and is_instance_valid(_feed_toast_tween):
		_feed_toast_tween.kill()
	_feed_toast.text = text
	_feed_toast.modulate.a = 1.0
	_feed_toast_tween = create_tween()
	_feed_toast_tween.tween_interval(1.8)
	_feed_toast_tween.tween_property(_feed_toast, "modulate:a", 0.0, 0.5)


# ---- Time controls + photo mode ----

func _handle_shortcut(key: int, action: Callable) -> void:
	var pressed: bool = Input.is_key_pressed(key)
	var was: bool = _key_was_pressed.get(key, false)
	if pressed and not was:
		action.call()
	_key_was_pressed[key] = pressed


func _typing_focus_in_ui() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _click_hits_interactive_hud(mouse_pos: Vector2) -> bool:
	if _ui_panels != null and _ui_panels.is_modal_open():
		return true
	for panel in [settings_panel, render_panel, sound_panel, library_panel,
			creature_creator_panel, fish_store_panel]:
		if panel != null and panel.visible \
				and panel.get_global_rect().has_point(mouse_pos):
			return true
	if right_rail != null and right_rail.visible \
			and right_rail.get_global_rect().has_point(mouse_pos):
		return true
	if stats_bar != null and stats_bar.visible \
			and stats_bar.get_global_rect().has_point(mouse_pos):
		return true
	if left_cluster != null and left_cluster.visible \
			and left_cluster.get_global_rect().has_point(mouse_pos):
		return true
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		if hovered is BaseButton:
			return true
	return false


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


func _toggle_motion_debug() -> void:
	if world == null or not world.has_method("toggle_motion_debug"):
		return
	var on: bool = world.toggle_motion_debug()
	if controls_hint != null:
		controls_hint.text = "Motion debug ON — cyan=preferred_y green=home_y gold=band red=wall push (M)"
		controls_hint.visible = on
	_haptic(8)


func _set_time_scale(s: float) -> void:
	if _sim == null:
		return
	_sim.time_scale = s
	_saved_time_scale = s
	_haptic(12)


func _on_one() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("aquasoil")
	else:
		_set_time_scale(1.0)


func _on_two() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("sand")
	else:
		_set_time_scale(4.0)


func _on_three() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("gravel")
	else:
		_set_time_scale(16.0)


func _on_four() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("peat")


func _on_five() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("stone")


func _on_six() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("wood")


func _on_seven() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("dig")


func _on_eight() -> void:
	if _aquascape.is_active:
		_aquascape.set_tool("trim")


func _take_photo() -> void:
	var world_node := get_node_or_null("SubViewport/World")
	if world_node != null and world_node.has_method("begin_screenshot_boost"):
		world_node.begin_screenshot_boost(3.0)
	_set_hud_visible_for_photo(false)
	_request_viewport_image(_finish_photo_with_hud_restore)


func _set_hud_visible_for_photo(visible: bool) -> void:
	if top_hud != null:
		top_hud.visible = visible
	if right_rail != null:
		right_rail.visible = visible


func _finish_photo_with_hud_restore(img: Image) -> void:
	_set_hud_visible_for_photo(true)
	_finish_photo(img)


func _finish_photo(img: Image) -> void:
	var dir: String = OS.get_user_data_dir() + "/captures"
	DirAccess.make_dir_recursive_absolute(dir)
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = dir + "/walstad_loom_" + ts + ".png"
	img.save_png(path)
	print_verbose("[walstad_loom] photo saved: ", path)
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
	await RenderingServer.frame_post_draw
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
		print_verbose("[walstad_loom] timelapse stopped: ", _timelapse_index, " frames in ", _timelapse_dir)
	else:
		var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		_timelapse_dir = OS.get_user_data_dir() + "/captures/timelapse_" + ts
		DirAccess.make_dir_recursive_absolute(_timelapse_dir)
		_timelapse_index = 0
		_timelapse_accum = 0.0
		_timelapse_active = true
		print_verbose("[walstad_loom] timelapse started: ", _timelapse_dir)


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


func _pick_creature_at_viewport(sv_pos: Vector2, creatures: Array,
		radius_override: float = -1.0) -> Node3D:
	if camera == null:
		return null
	# Pick radius: portal mode is most permissive; touch input gets a
	# fatter target than mouse because fingers are imprecise; otherwise the
	# desktop default. This makes small fish actually tappable on a phone
	# without sacrificing precision when a mouse is in use.
	var radius_px: float
	if radius_override > 0.0:
		radius_px = radius_override
	elif _portal_open:
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
		# Name — prefer the persistent display_name. When personality is
		# present we append an epithet ("Atlas the Bold") earned from the
		# top trait, so the player sees character at a glance.
		var c_name := ""
		if target_node.get("fish_name") != null and String(target_node.get("fish_name")) != "":
			c_name = String(target_node.get("fish_name"))
		elif target_node.get("shrimp_name") != null and String(target_node.get("shrimp_name")) != "":
			c_name = String(target_node.get("shrimp_name"))
		elif target_node.get("snail_name") != null and String(target_node.get("snail_name")) != "":
			c_name = String(target_node.get("snail_name"))
		elif target_node.get("_display_name") != null and String(target_node.get("_display_name")) != "":
			c_name = String(target_node.get("_display_name"))
		else:
			c_name = _creature_label(target_node).capitalize()
		var personality_v: Variant = target_node.get("personality")
		if personality_v is Dictionary and not (personality_v as Dictionary).is_empty():
			var epithet: String = CreatureNaming.epithet_for_personality(personality_v)
			if epithet != "":
				c_name = "%s %s" % [c_name, epithet]
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
		if target_node.get("sterile") != null and target_node.sterile:
			sterile_str = " · Sterile"
			
		_portal_stats_lbl.text = "Age: %s · Hunger: %d%%%s%s" % [age_str, hunger_pct, sex_str, sterile_str]
		# Lifetime journal — meals eaten, offspring sired. Only render when
		# the target carries a bio dict (added by the AIDirector pass).
		var bio_v: Variant = target_node.get("bio")
		if bio_v is Dictionary and not (bio_v as Dictionary).is_empty():
			var bio_d: Dictionary = bio_v
			var meals: int = int(bio_d.get("meals_eaten", 0))
			var kids: int = int(bio_d.get("offspring", 0))
			var fights: int = int(bio_d.get("fights_won", 0))
			var bio_parts: PackedStringArray = PackedStringArray()
			if meals > 0:
				bio_parts.append("%d %s" % [meals, "meal" if meals == 1 else "meals"])
			if kids > 0:
				bio_parts.append("%d %s" % [kids, "child" if kids == 1 else "children"])
			if fights > 0:
				bio_parts.append("%d %s won" % [fights, "fight" if fights == 1 else "fights"])
			if bio_parts.size() > 0:
				# Append to the existing stats line; the label is already
				# autowrap-disabled but the text overflow shows ellipsis,
				# which is fine — anyone curious can rescale the panel.
				_portal_stats_lbl.text += "\n" + " · ".join(bio_parts)


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
		print_verbose("[walstad_loom] portal tracking %s" % _creature_label(creature))
	else:
		_follow_target = creature
		_update_portal_pip()
		print_verbose("[walstad_loom] following %s" % _creature_label(creature))


func _pick_creature_at_click(screen_pos: Vector2, radius_px: float = PICK_RADIUS_PX_CLICK) -> Node3D:
	if _aquascape.is_active:
		return null
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE):
		return null
	if display == null or not display.get_global_rect().has_point(screen_pos):
		return null
	if _click_hits_interactive_hud(screen_pos):
		return null
	var sv_pos: Vector2 = _window_mouse_to_viewport(screen_pos)
	return _pick_creature_at_viewport(sv_pos, _gather_creatures(), radius_px)


func _click_targets_creature() -> bool:
	var picked: Node3D = _pick_creature_at_click(
		get_viewport().get_mouse_position(), PICK_RADIUS_PX_CLICK)
	if picked == null:
		return false
	_assign_creature_target(picked)
	return true


func _toggle_aquascape() -> void:
	_aquascape.toggle()


func _aquascape_undo() -> void:
	_aquascape.undo()


func _begin_aquascape_drag(pos: Vector2) -> bool:
	return _aquascape.begin_drag(pos)


func _aquascape_place(mouse_pos: Vector2) -> void:
	_aquascape.place(mouse_pos)


func _drag_hardscape_piece(mouse_pos: Vector2) -> void:
	_aquascape.drag_hardscape(mouse_pos)


func _project_to_substrate(mouse_pos: Vector2) -> Vector3:
	return _aquascape.project_to_substrate(mouse_pos)


func _aquascape_to_save_arr() -> Array:
	return _aquascape.to_save_arr()


func _restore_aquascape(arr: Array) -> void:
	_aquascape.restore_from_save(arr)


# ---- Walkthrough hooks (called by walkthrough.gd) ----

func _maybe_start_walkthrough() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not cfg.walkthrough_pending:
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
	if _aquascape.is_active != on:
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

	if event is InputEventKey and event.pressed and not event.echo \
			and not _typing_focus_in_ui():
		var ek: InputEventKey = event as InputEventKey
		if (ek.keycode == KEY_SLASH and ek.shift_pressed) or ek.keycode == KEY_QUESTION:
			_toggle_cheat_sheet()
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
				# Close chip popups on any click outside them (chips
				# themselves go through their own gui_input handler before
				# this runs, so taps that hit a chip never reach here).
				var closed_chip_popup: bool = false
				if _history_popup != null and _history_popup.visible \
						and not _history_popup.get_global_rect().has_point(mb.position):
					_history_popup.visible = false
					closed_chip_popup = true
				if _story_popup != null and _story_popup.visible \
						and not _story_popup.get_global_rect().has_point(mb.position):
					_story_popup.visible = false
					closed_chip_popup = true
				if _water_popup != null and _water_popup.visible \
						and not _water_popup.get_global_rect().has_point(mb.position):
					_water_popup.visible = false
					closed_chip_popup = true
				if closed_chip_popup:
					_chip_popup_key = ""
				if _notifications_panel != null and _notifications_panel.visible \
						and not _notifications_panel.get_global_rect().has_point(mb.position) \
						and notifications_toggle != null \
						and not notifications_toggle.get_global_rect().has_point(mb.position):
					_notifications_panel.visible = false
					_sync_rail_toggles()
				if _light_panel != null and _light_panel.visible \
						and not _light_panel.get_global_rect().has_point(mb.position) \
						and (_light_btn == null \
							or not _light_btn.get_global_rect().has_point(mb.position)):
					_light_panel.visible = false
					_sync_light_btn()
				# LMB on a creature (tight pick) → follow. Open water → feed.
				# Shift+LMB on water → startle (tap on glass).
				var picked: Node3D = _pick_creature_at_click(mb.position)
				if picked != null:
					_assign_creature_target(picked)
					_suppress_drag_until_release = true
				elif Input.is_key_pressed(KEY_SHIFT):
					_startle_fish_near_tap(mb.position)
					_suppress_drag_until_release = true
				elif _drop_food_at_cursor(mb.position):
					_suppress_drag_until_release = true


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
			_drag_committed = false

			# Edge-swipe from the right edge → opens settings. Only arm the
			# tracker if the touch starts very close to the screen's right
			# edge; the actual decision happens on lift in case the user
			# changes their mind mid-drag.
			var win_w: float = get_viewport().get_visible_rect().size.x
			if not _aquascape.is_active and ev.position.x >= win_w - EDGE_SWIPE_TRIGGER_PX:
				_edge_swipe_active = true
				_edge_swipe_start_x = ev.position.x

			# Aquascape: start painting immediately on touch-down (like LMB).
			if _aquascape.is_active:
				if _aquascape.begin_drag(ev.position):
					_drag_mode = "wood_drag"
				else:
					_drag_mode = "paint"
					_aquascape.place(ev.position)
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
			_aquascape.end_drag()
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
					# Double-tap → reset camera. Short pulse confirms the snap.
					_reset_camera_to_default()
					_haptic(20)
					_last_tap_time = -1.0
					print_verbose("[walstad_loom] double-tap: reset camera")
				else:
					_last_tap_time = now
					_last_tap_pos = ev.position
					# Tiny pulse on creature pick — confirms the tap landed on
					# something selectable vs an empty-water tap (food drop).
					if _touch_pick_creature(ev.position):
						_haptic(10)
					else:
						_drop_food_at_cursor(ev.position)
			
			# Check for completed edge-swipe gesture: started near right edge,
			# moved at least EDGE_SWIPE_MIN_PX to the left. Fire BEFORE we
			# clear state so the trigger is unambiguous.
			if _edge_swipe_active:
				var dx: float = _edge_swipe_start_x - ev.position.x
				if dx >= EDGE_SWIPE_MIN_PX:
					_edge_swipe_active = false
					_ui_toggle_side(UiPanelManager.SIDE_SETTINGS)
					_haptic(15)
					# Treat the swipe as consumed — don't also reset camera
					# via the tap/double-tap path.
					_long_press_fired = true
				else:
					_edge_swipe_active = false

			# End aquascape drag.
			_aquascape.end_drag()
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
		# Single-finger deadzone: don't orbit until the finger has moved
		# DRAG_DEADZONE_PX since touch-down. Below the deadzone we keep the
		# tap eligible; once crossed, the finger commits to navigation and
		# can't trigger a tap on lift. Paint / wood_drag are tool actions
		# and bypass the deadzone (they should fire on touch-down).
		if not _drag_committed and _tap_moved >= DRAG_DEADZONE_PX:
			_drag_committed = true
		var nav_committed: bool = _drag_committed \
				or _drag_mode == "paint" or _drag_mode == "wood_drag"
		# ---- Single finger: orbit or aquascape paint ----
		if _aquascape.is_active:
			match _drag_mode:
				"paint":
					if _aquascape.can_paint():
						_aquascape.place(ev.position)
						_aquascape.mark_painted()
				"wood_drag":
					_aquascape.drag_hardscape(ev.position)
				_:
					if nav_committed:
						# Even in aquascape, allow orbit if no tool action locked.
						yaw -= ev.relative.x * TOUCH_ORBIT_SENSITIVITY
						pitch -= ev.relative.y * TOUCH_ORBIT_SENSITIVITY
						pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
						_apply_camera()
		else:
			if nav_committed:
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


func _touch_pick_creature(screen_pos: Vector2) -> bool:
	if display == null or sub_viewport == null:
		return false
	var sv_pos: Vector2 = _window_mouse_to_viewport(screen_pos)
	var creatures: Array = _gather_creatures()
	var picked: Node3D = _pick_creature_at_viewport(sv_pos, creatures)
	if picked != null:
		_assign_creature_target(picked)
		print_verbose("[walstad_loom] touch-tap: picked %s" % _creature_label(picked))
		return true
	if _follow_target != null:
		_follow_target = null
		print_verbose("[walstad_loom] touch-tap: cleared follow")
	return false


# ---- Mobile UI setup ----

func _setup_mobile_ui() -> void:
	# Enlarge all header toggle buttons so they're finger-friendly (≥48×48dp).
	var toggle_buttons: Array[Button] = []
	if settings_toggle != null: toggle_buttons.append(settings_toggle)
	if render_toggle != null: toggle_buttons.append(render_toggle)
	if sound_toggle != null: toggle_buttons.append(sound_toggle)
	if fish_store_toggle != null: toggle_buttons.append(fish_store_toggle)
	if creature_creator_toggle != null: toggle_buttons.append(creature_creator_toggle)
	if aquascape_toggle != null: toggle_buttons.append(aquascape_toggle)
	if portal_toggle != null: toggle_buttons.append(portal_toggle)
	if library_toggle != null: toggle_buttons.append(library_toggle)
	if notifications_toggle != null: toggle_buttons.append(notifications_toggle)
	for btn in toggle_buttons:
		btn.custom_minimum_size = Vector2(52, 52)
		btn.add_theme_font_size_override("font_size", 18)
	_apply_rail_button_labels(true)
	_sync_rail_toggles()
	_apply_rail_dock_layout()
	
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
		if _mobile_hud.has_signal("camera_views_pressed"):
			_mobile_hud.connect("camera_views_pressed", _toggle_camera_views_panel)

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
	var pos: Vector3 = target + Vector3(x, y, z) * radius
	# Pixel-snap camera: round the eye position to multiples of the
	# world-space size of a single render pixel. Eliminates the sub-pixel
	# jitter you see on swimming fish when the camera is drifting.
	# world_per_pixel ≈ 2·tan(fov/2)·radius / render_height
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and bool(cfg.get("pixel_snap_camera")):
		var fov_rad: float = deg_to_rad(float(camera.fov))
		var rh: float = maxf(64.0, float(sub_viewport.size.y))
		var wpp: float = 2.0 * tan(fov_rad * 0.5) * radius / rh
		if wpp > 0.0001:
			pos.x = snappedf(pos.x, wpp)
			pos.y = snappedf(pos.y, wpp)
			pos.z = snappedf(pos.z, wpp)
	camera.global_position = pos
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
	_collect_story_notifications()
	_collect_water_alert_notifications()
	_push_telemetry_to_js()


# Web-only: forward the current stats snapshot to the host page so it can
# POST it to the headless launcher's /telemetry endpoint. No-op on native
# builds (no JavaScriptBridge there). The injected page-side shim defines
# window.__walstadLoomPushStats; if we're hosted somewhere else, this just
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
	# want. The shim defined window.__walstadLoomPushStats at top level.
	JavaScriptBridge.eval(
		"if (window.__walstadLoomPushStats) { window.__walstadLoomPushStats(" + body + "); }",
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
	# Carrying-capacity readout: fish/cap with warn-tint when over cap.
	# Pulled from SimDriver.fish_carrying_capacity() via the stats dict.
	var fish_cap: int = int(_stats.get("fish_carrying_capacity", 0))
	var stocking_ratio: float = float(_stats.get("fish_stocking_ratio", 0.0))
	var over_cap: bool = stocking_ratio > 1.05
	var fauna_compact: bool = _hud_layout == "compact"
	if fauna_compact:
		var fauna_total: int = fish_total + shrimp_total + snail_total
		var compact_sub: String = "fauna"
		if fish_cap > 0:
			compact_sub = "%d/%d cap" % [fish_total, fish_cap]
		_update_chip("fish", str(fauna_total), compact_sub, true, over_cap)
	else:
		var fish_sub: String
		if fish_total <= 0:
			fish_sub = "—"
		elif fish_cap > 0:
			fish_sub = "%dA %dF · %d/%d" % [fish_adults, fish_fry, fish_total, fish_cap]
		else:
			fish_sub = "%dA %dF" % [fish_adults, fish_fry]
		_update_chip("fish", str(fish_total), fish_sub, true, over_cap)
		_update_chip("shrimp", str(shrimp_total),
			("%dA %dF" % [shrimp_adults, shrimp_fry]) if shrimp_total > 0 else "—",
			true, false)
		_update_chip("snails", str(snail_total),
			("%dA %dB" % [snail_adults, snail_babies]) if snail_total > 0 else "—",
			true, false)

	# Flora chip.
	_update_chip("flora", str(plants), "biomass %d" % biomass, true, false)

	# Water chip: O₂ percentage + cycle phase; warn-tinted below 50%.
	var water_sub: String = HudController.water_chip_subtitle(_stats)
	_update_chip("water", "%d%%" % o2_pct, water_sub, true, o2_pct < 50)

	# Morphs chip — only meaningful once speciation has produced variants.
	_update_chip("morphs", "+%d" % distinct_morphs, "morphs", distinct_morphs > 0, false)

	# Mood chip — aggregate tank vibe across O₂, biomass, algae, waste.
	# Weights tuned so a healthy planted tank reads as "thriving" and a
	# crashed one as "🚨", with a clear in-between band so the chip
	# changes meaningfully as the tank trends rather than flipping at
	# one threshold. Mood is computed here rather than on sim_driver so
	# it can read the same _stats snapshot already in scope.
	var ammonia: float = float(_stats.get("ammonia", 0.0))
	var mood: float = 0.30 * o2 \
		+ 0.30 * clampf(float(biomass) / 600.0, 0.0, 1.0) \
		+ 0.20 * clampf(1.0 - float(algae) / 60.0, 0.0, 1.0) \
		+ 0.20 * clampf(1.0 - float(waste) / 100.0, 0.0, 1.0) \
		- clampf(ammonia * 0.25, 0.0, 0.35)
	mood = clampf(mood, 0.0, 1.0)
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
	if _aquascape.is_active:
		_update_chip("state", "AQUA", _aquascape_tool_label(), true, false)


func _aquascape_tool_label() -> String:
	match _aquascape.tool:
		"aquasoil", "dirt":
			return "SOIL"
		"sand":
			return "SAND r%d" % _aquascape.brush_radius
		"gravel":
			return "GRVL r%d" % _aquascape.brush_radius
		"peat":
			return "PEAT"
		"stone":
			return "STONE"
		"wood":
			return "WOOD"
		"dig":
			return "DIG r%d" % _aquascape.brush_radius
		"trim":
			return "TRIM"
	return _aquascape.tool.to_upper()


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
		{"key": "state",  "icon": UiIcons.chip_glyph("state"), "color": Color8(154, 168, 200)},
		{"key": "mood",   "icon": UiIcons.chip_glyph("mood"), "color": Color8(170, 220, 170)},
		{"key": "fish",   "icon": UiIcons.chip_glyph("fish"), "color": Color8(214, 176, 112)},
		{"key": "shrimp", "icon": UiIcons.chip_glyph("shrimp"), "color": Color8(214, 176, 112)},
		{"key": "snails", "icon": UiIcons.chip_glyph("snails"), "color": Color8(214, 176, 112)},
		{"key": "flora",  "icon": UiIcons.chip_glyph("flora"), "color": Color8(134, 192, 132)},
		{"key": "water",  "icon": UiIcons.chip_glyph("water"), "color": Color8(127, 183, 216)},
		{"key": "morphs", "icon": UiIcons.chip_glyph("morphs"), "color": Color8(224, 192, 96)},
		{"key": "alert",  "icon": UiIcons.chip_glyph("alert"), "color": Color8(224, 112, 112)},
	]
	for d in defs:
		var key: String = String(d["key"])
		var chip: Control = _make_chip(String(d["icon"]), d["color"] as Color, key)
		bar.add_child(chip)
		_chips[key] = chip
		# Tapping a chip opens a sparkline popup showing the last ~2 minutes
		# of that metric's history. PanelContainer accepts gui_input out of
		# the box; we route the key + accent color along so the popup can
		# title + tint itself.
		var color: Color = d["color"] as Color
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(func(ev): _on_chip_gui_input(ev, key, color))
	if not bool(_global_pref("chip_pulse_seen", false)):
		call_deferred("_pulse_stat_chips_once")


func _chip_tooltip(key: String) -> String:
	match key:
		"state": return "Tank time — tap for history"
		"mood": return "Ecosystem mood — tap for story log"
		"water": return "Water chemistry — tap for details"
		"alert": return "Active alerts — tap for details"
		"fish", "shrimp", "snails", "flora", "morphs": return "Population — tap for sparkline"
	return "Tap for details"


func _pulse_stat_chips_once() -> void:
	for chip in _chips.values():
		var tw := create_tween()
		tw.set_loops(2)
		tw.tween_property(chip, "modulate", Color(1.2, 1.2, 1.15, 1.0), 0.35)
		tw.tween_property(chip, "modulate", Color.WHITE, 0.35)
	_set_global_pref("chip_pulse_seen", true)


# Construct a single chip widget. Caches the value + sublabel Labels via meta
# so _update_chip can find them without walking the subtree on every tick.
func _make_chip(icon: String, accent: Color, key: String = "") -> Control:
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
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	pc.add_child(hb)

	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.add_theme_font_size_override("font_size", 15)
	icon_lbl.add_theme_color_override("font_color", accent)
	hb.add_child(icon_lbl)

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 14)
	value_lbl.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	hb.add_child(value_lbl)

	var sublabel_lbl := Label.new()
	sublabel_lbl.add_theme_font_size_override("font_size", 10)
	sublabel_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85, 0.8))
	hb.add_child(sublabel_lbl)

	pc.set_meta("value_label", value_lbl)
	pc.set_meta("sublabel_label", sublabel_lbl)
	pc.set_meta("accent", accent)
	if not key.is_empty():
		pc.tooltip_text = _chip_tooltip(key)
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
#   wide   (≥1100):     all chips visible WITH sublabels
#   medium (700-1099):  all chips visible, sublabels hidden to save space
#   compact (<700, or touch+<900): minimal chips, tighter stats bar margins
# Called once at _ready and on every viewport size_changed.
func _on_viewport_resized() -> void:
	_apply_mobile_render_orientation_if_needed()
	_apply_hud_layout()
	_apply_rail_dock_layout()
	_apply_panel_layout()
	_apply_display_layout()


# Resize the Display TextureRect based on the current TankConfig settings.
# Two modes:
#   integer_upscale = false (default) → full-rect anchored display, stretched
#     to the window. Subpixel shimmer is possible at non-integer ratios but
#     the image fills the screen.
#   integer_upscale = true → display sized to (sub_viewport.size × N) where
#     N is the largest integer that fits, centered, letterboxed. Every
#     render pixel maps to an exact N×N block on the monitor — no shimmer.
# Rolling buffer of recent frame times. The Render panel reads this to
# draw its mini-sparkline; the adaptive-quality controller reads it to
# decide when to step the resolution up or down.
const _FRAME_HISTORY_LEN: int = 120
var _frame_history: PackedFloat32Array = PackedFloat32Array()
var _frame_history_head: int = 0
var _adaptive_t: float = 0.0
const _ADAPTIVE_TICK_S: float = 1.2


func _record_frame_time(dt: float) -> void:
	if _frame_history.size() < _FRAME_HISTORY_LEN:
		_frame_history.resize(_FRAME_HISTORY_LEN)
	_frame_history[_frame_history_head] = dt
	_frame_history_head = (_frame_history_head + 1) % _FRAME_HISTORY_LEN


func _frame_history_avg_fps() -> float:
	# Return rolling average FPS across the buffer. Discards zeros so a
	# half-filled buffer doesn't pull the average down.
	var sum: float = 0.0
	var n: int = 0
	for v in _frame_history:
		if v > 0.0001:
			sum += v
			n += 1
	if n == 0:
		return 60.0
	return float(n) / sum


# Pull the most recent N frame samples into a flat array ordered oldest
# → newest. Used by RenderPanel to draw the sparkline left-to-right.
func get_frame_history_ordered() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_FRAME_HISTORY_LEN)
	for i in _FRAME_HISTORY_LEN:
		out[i] = _frame_history[(_frame_history_head + i) % _FRAME_HISTORY_LEN]
	return out


# Step the SubViewport resolution + MSAA down when sustained FPS sits
# below target, and back up when there's headroom. Only runs when
# TankConfig.adaptive_quality is on. Stepping is conservative — one
# resolution tier per check, with a long hold between steps so we don't
# thrash near the threshold.
const _ADAPTIVE_RES_TIERS: Array = [
	{"w": 256, "h": 144},
	{"w": 384, "h": 216},
	{"w": 512, "h": 288},
	{"w": 768, "h": 432},
	{"w": 1024, "h": 576},
]


func _adaptive_quality_tick(dt: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.get("adaptive_quality")):
		return
	_adaptive_t += dt
	if _adaptive_t < _ADAPTIVE_TICK_S:
		return
	_adaptive_t = 0.0
	# Need a half-full buffer before we trust the average.
	var filled: int = 0
	for v in _frame_history:
		if v > 0.0001:
			filled += 1
	if filled < _FRAME_HISTORY_LEN / 2.0:
		return
	var fps: float = _frame_history_avg_fps()
	var target_fps: float = float(cfg.get("adaptive_quality_target_fps"))
	# Find current tier index.
	var cur_w: int = int(cfg.get("render_width"))
	var cur_h: int = int(cfg.get("render_height"))
	var cur_idx: int = -1
	for i in _ADAPTIVE_RES_TIERS.size():
		var t: Dictionary = _ADAPTIVE_RES_TIERS[i]
		if int(t["w"]) == cur_w and int(t["h"]) == cur_h:
			cur_idx = i
			break
	if cur_idx < 0:
		return  # custom resolution; don't auto-adjust
	# Step down if we're missing target by >10%.
	if fps < target_fps * 0.90 and cur_idx > 0:
		var nt: Dictionary = _ADAPTIVE_RES_TIERS[cur_idx - 1]
		cfg.set("render_width", int(nt["w"]))
		cfg.set("render_height", int(nt["h"]))
		_apply_render_config()
		_frame_history.fill(0.0)  # invalidate history so next decision uses fresh frames
		return
	# Step up if we have >25% headroom and could increase quality.
	if fps > target_fps * 1.25 and cur_idx < _ADAPTIVE_RES_TIERS.size() - 1:
		var nt2: Dictionary = _ADAPTIVE_RES_TIERS[cur_idx + 1]
		cfg.set("render_width", int(nt2["w"]))
		cfg.set("render_height", int(nt2["h"]))
		_apply_render_config()
		_frame_history.fill(0.0)


# Update the palette_quantize shader's `palette_tint` uniform based on
# the current SimDriver day_phase. Picks one of four anchor tints and
# blends smoothly between them so the visual transition is continuous,
# not stepwise. Anchors:
#   day_phase 0.00 (dawn)    → warm rose
#   day_phase 0.25 (midday)  → neutral 1,1,1
#   day_phase 0.50 (dusk)    → amber
#   day_phase 0.75 (midnight)→ dark cool blue (actually dark this time)
#
# Anchors below set the BASE tint per phase. The Light panel's intensity /
# warmth / master controls then multiply on top so the user gets visible
# feedback when they touch the sliders. _TOD_NIGHT used to be (0.78, 0.86,
# 1.04) which just shifted hue without darkening — night looked like day.
const _TOD_DAWN: Vector3 = Vector3(1.02, 0.88, 0.82)
const _TOD_DAY: Vector3 = Vector3(1.00, 1.00, 1.00)
const _TOD_DUSK: Vector3 = Vector3(1.04, 0.82, 0.70)
const _TOD_NIGHT: Vector3 = Vector3(0.38, 0.42, 0.52)


func _update_palette_tod_tint() -> void:
	if display == null or not (display.material is ShaderMaterial):
		return
	var phase: float = 0.25  # default to midday if no sim yet
	if _sim != null and _sim.get("day_phase") != null:
		phase = fposmod(float(_sim.day_phase), 1.0)
	# Pick the four anchor tints — built-in unless the user has overridden
	# them in the per-phase color section of the Light panel.
	var cfg_pre := get_node_or_null("/root/TankConfig")
	var dawn_v: Vector3 = _TOD_DAWN
	var day_v: Vector3 = _TOD_DAY
	var dusk_v: Vector3 = _TOD_DUSK
	var night_v: Vector3 = _TOD_NIGHT
	if cfg_pre != null and bool(cfg_pre.tod_use_overrides):
		dawn_v = Vector3(cfg_pre.tod_dawn_color.r, cfg_pre.tod_dawn_color.g, cfg_pre.tod_dawn_color.b)
		day_v = Vector3(cfg_pre.tod_day_color.r, cfg_pre.tod_day_color.g, cfg_pre.tod_day_color.b)
		dusk_v = Vector3(cfg_pre.tod_dusk_color.r, cfg_pre.tod_dusk_color.g, cfg_pre.tod_dusk_color.b)
		night_v = Vector3(cfg_pre.tod_night_color.r, cfg_pre.tod_night_color.g, cfg_pre.tod_night_color.b)
	# Four-segment lerp on the unit circle: 0→0.25 dawn→day, 0.25→0.5 day→dusk,
	# 0.5→0.75 dusk→night, 0.75→1 night→dawn.
	var t: Vector3
	if phase < 0.25:
		t = dawn_v.lerp(day_v, phase / 0.25)
	elif phase < 0.5:
		t = day_v.lerp(dusk_v, (phase - 0.25) / 0.25)
	elif phase < 0.75:
		t = dusk_v.lerp(night_v, (phase - 0.5) / 0.25)
	else:
		t = night_v.lerp(dawn_v, (phase - 0.75) / 0.25)
	# Apply user controls so the sliders are NOT cosmetic. Order matters:
	#   1. Intensity scales overall brightness (cfg.light_energy 0..1).
	#   2. Warmth nudges hue between cool and warm (cfg.light_warmth 0..1).
	#   3. Master kill switch overrides everything → near-black.
	# Defaults preserve the legacy feel when sliders sit at their mid-points.
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		# Global intensity is a 2-segment curve anchored at 0.5 → 1.0 so saved
		# tanks keep their look. Below 0.5 the scene dims down toward 0.15;
		# above 0.5 it lifts to 1.4 for an over-bright "noon" feel.
		var e: float = clampf(float(cfg.global_intensity), 0.0, 1.0)
		var bright: float = (0.15 + (e / 0.5) * 0.85) if e <= 0.5 \
			else (1.0 + ((e - 0.5) / 0.5) * 0.25)
		t *= bright
		# Warmth tint: 0.0 cools (boost blue, drop red), 1.0 warms (boost red,
		# drop blue). 0.5 is neutral. Effect is multiplicative on top of the
		# phase tint so dusk + max warmth reads as a deep amber.
		var warmth: float = clampf(float(cfg.global_warmth), 0.0, 1.0)
		var warm_mod: Vector3 = Vector3(
			lerpf(0.90, 1.06, warmth),  # red
			lerpf(0.96, 1.00, warmth),  # green
			lerpf(1.06, 0.86, warmth))  # blue (inverse)
		t *= warm_mod
		# Master off: the tank effectively goes black. Tiny ambient floor so
		# silhouettes are still readable enough to find the rail buttons.
		if not bool(cfg.light_master_enabled):
			t = Vector3(0.04, 0.04, 0.07)
	var mat: ShaderMaterial = display.material as ShaderMaterial
	mat.set_shader_parameter("palette_tint", t)
	# Drive the day/night palette blend off the same daylight curve the
	# sim uses for photosynthesis. Smoothstep on top of the cosine bell so
	# the transition has a defined "dusk" knee instead of feeling washy.
	var dl: float = 1.0
	if _sim != null and _sim.has_method("daylight"):
		dl = float(_sim.daylight())
	var night_blend: float = smoothstep(0.05, 0.55, 1.0 - dl)
	if _sim != null:
		var sunset_hour: float = clampf(
			1.0 - absf(fposmod(float(_sim.day_phase), 1.0) - 0.5) / 0.12, 0.0, 1.0)
		night_blend *= 1.0 - sunset_hour * 0.28
		var deep_night: float = 1.0 - smoothstep(0.08, 0.38, dl)
		var tank_on: bool = cfg == null or cfg.tank_lights_on
		if tank_on and deep_night > 0.35:
			night_blend *= lerpf(1.0, 0.38, smoothstep(0.35, 1.0, deep_night))
			mat.set_shader_parameter("bloom_strength", 0.85 + deep_night * 0.14)
			mat.set_shader_parameter("bloom_threshold", 0.68 - deep_night * 0.14)
		else:
			mat.set_shader_parameter("bloom_strength", 0.85)
			mat.set_shader_parameter("bloom_threshold", 0.68)
	mat.set_shader_parameter("palette_night_blend", night_blend)
	# Push user-controlled post-process uniforms every tick. Cheap (constant
	# count of small uniforms) and lets the sliders react live.
	if cfg != null:
		mat.set_shader_parameter("vignette_strength", float(cfg.pp_vignette_strength))
		mat.set_shader_parameter("vignette_falloff", float(cfg.pp_vignette_falloff))
		# Bloom + outline + dither + CRT only override the defaults when the
		# user has actually moved them off the legacy values (we still set
		# every frame for simplicity — the shader handles 0 gracefully).
		mat.set_shader_parameter("outline_strength", float(cfg.outline_strength))
		mat.set_shader_parameter("dither_strength", float(cfg.dither_strength))
		mat.set_shader_parameter("crt_strength", float(cfg.crt_strength))
		mat.set_shader_parameter("region_aware_dither",
			1.0 if cfg.dither_region_aware else 0.0)
		mat.set_shader_parameter("palette_bank_lock",
			1.0 if cfg.palette_bank_lock else 0.0)
		# Bloom is now a real user control — always push the slider value so
		# the panel feels responsive. The dynamic night-bloom boost is
		# preserved by the per-section logic above, which writes BEFORE this
		# line — so we override it with the user's pick if they touched it.
		mat.set_shader_parameter("bloom_strength", float(cfg.pp_bloom_strength))
		mat.set_shader_parameter("bloom_threshold", float(cfg.pp_bloom_threshold))


func _apply_display_layout() -> void:
	if display == null:
		return
	var cfg := get_node_or_null("/root/TankConfig")
	var integer_lock: bool = cfg != null and bool(cfg.get("integer_upscale"))
	if not integer_lock:
		# Restore full-rect anchored layout (matches the .tscn default).
		display.anchor_left = 0.0
		display.anchor_top = 0.0
		display.anchor_right = 1.0
		display.anchor_bottom = 1.0
		display.offset_left = 0.0
		display.offset_top = 0.0
		display.offset_right = 0.0
		display.offset_bottom = 0.0
		return
	# Integer letterbox. Read the window size, divide by render size, floor,
	# then center.
	var win: Vector2 = Vector2(get_window().size)
	var sv: Vector2 = Vector2(sub_viewport.size)
	if sv.x <= 0.0 or sv.y <= 0.0:
		return
	var scale_x: float = floorf(win.x / sv.x)
	var scale_y: float = floorf(win.y / sv.y)
	var n: float = maxf(1.0, minf(scale_x, scale_y))
	var out_size: Vector2 = sv * n
	# Coverage guard — if integer scaling would shrink the tank to less
	# than 70% of the window dimension on either axis, the letterboxing
	# is worse than the shimmer it's supposed to fix. Fall back to the
	# stretched full-rect layout in that case so the player isn't staring
	# at a tiny tank inside a huge black border. This typically fires when
	# the render resolution is high relative to a small window.
	var coverage_x: float = out_size.x / win.x
	var coverage_y: float = out_size.y / win.y
	if coverage_x < 0.70 or coverage_y < 0.70:
		display.anchor_left = 0.0
		display.anchor_top = 0.0
		display.anchor_right = 1.0
		display.anchor_bottom = 1.0
		display.offset_left = 0.0
		display.offset_top = 0.0
		display.offset_right = 0.0
		display.offset_bottom = 0.0
		return
	var origin: Vector2 = ((win - out_size) * 0.5).floor()
	display.anchor_left = 0.0
	display.anchor_top = 0.0
	display.anchor_right = 0.0
	display.anchor_bottom = 0.0
	display.offset_left = origin.x
	display.offset_top = origin.y
	display.offset_right = origin.x + out_size.x
	display.offset_bottom = origin.y + out_size.y


func _rail_edge_inset() -> float:
	if _rail_dock == "bottom":
		return PanelTheme.EDGE_MARGIN + 4.0
	return PanelTheme.RAIL_WIDTH + PanelTheme.EDGE_MARGIN + 4.0


func _hud_bottom_inset() -> float:
	if _rail_dock == "bottom":
		return PanelTheme.HUD_BOTTOM + PanelTheme.RAIL_BOTTOM_HEIGHT
	return PanelTheme.HUD_BOTTOM


func _want_bottom_rail(_vp: Vector2) -> bool:
	# Keep controls as a true right-side vertical rail on mobile portrait.
	# The old bottom dock read as "landscape" and hid options from the right.
	return false


func _oriented_mobile_render_size(base_w: int, base_h: int) -> Vector2i:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return Vector2i(base_w, base_h)
	var portrait: bool = vp.y > vp.x * 1.02
	var base_landscape: bool = base_w >= base_h
	if portrait and base_landscape:
		return Vector2i(base_h, base_w)
	if not portrait and not base_landscape:
		return Vector2i(base_h, base_w)
	return Vector2i(base_w, base_h)


func _apply_mobile_render_orientation_if_needed() -> void:
	if not _is_mobile():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var portrait: bool = vp.y > vp.x * 1.02
	var current: int = 1 if portrait else 0
	if current == _mobile_render_orientation:
		return
	_mobile_render_orientation = current
	_apply_render_config()


func _setup_hud_styling() -> void:
	if left_cluster != null:
		left_cluster.add_theme_stylebox_override("panel",
			PanelTheme.make_hud_cluster_style())
	if stats_bar != null:
		stats_bar.add_theme_stylebox_override("panel",
			PanelTheme.make_hud_cluster_style())
	if right_cluster != null:
		right_cluster.add_theme_stylebox_override("panel",
			PanelTheme.make_rail_cluster_style())

	var left_buttons: Array[Button] = []
	if menu_button != null:
		left_buttons.append(menu_button)
	for btn in left_buttons:
		PanelTheme.style_hud_toggle_button(btn)
	if menu_button != null:
		UiIcons.apply_rail_button(menu_button, "menu", _is_mobile())

	_rail_vbox = right_cluster.get_node_or_null("VBox") as VBoxContainer
	if _rail_hbox == null and right_cluster != null:
		_rail_hbox = HBoxContainer.new()
		_rail_hbox.name = "RailHBox"
		_rail_hbox.add_theme_constant_override("separation", 4)
		_rail_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		_rail_hbox.visible = false
		right_cluster.add_child(_rail_hbox)

	var rail_buttons: Array[Button] = _ordered_rail_buttons()
	for btn in rail_buttons:
		PanelTheme.style_rail_button(btn, false)
	_apply_rail_button_labels(false)

	var divider: HSeparator = right_cluster.get_node_or_null("VBox/RailDivider") as HSeparator
	if divider != null:
		var rule_style := StyleBoxFlat.new()
		rule_style.bg_color = PanelTheme.RULE_FG
		divider.add_theme_stylebox_override("separator", rule_style)


func _sync_rail_toggles() -> void:
	var h: int = 0
	h = h * 31 + int(_portal_open)
	h = h * 31 + int(_aquascape.is_active)
	h = h * 31 + int(settings_panel != null and settings_panel.visible)
	h = h * 31 + int(render_panel != null and render_panel.visible)
	h = h * 31 + int(sound_panel != null and sound_panel.visible)
	h = h * 31 + int(_light_panel != null and _light_panel.visible)
	h = h * 31 + int(fish_store_panel != null and fish_store_panel.visible)
	h = h * 31 + int(library_panel != null and library_panel.visible)
	h = h * 31 + int(creature_creator_panel != null and creature_creator_panel.visible)
	h = h * 31 + int(_notifications_panel != null and _notifications_panel.visible)
	if h == _last_rail_sync_hash:
		return
	_last_rail_sync_hash = h
	if _rail_create_btn != null:
		var create_on: bool = (creature_creator_panel != null and creature_creator_panel.visible) \
			or (fish_store_panel != null and fish_store_panel.visible) \
			or (library_panel != null and library_panel.visible)
		PanelTheme.style_rail_button(_rail_create_btn, create_on)
	if _rail_world_btn != null:
		PanelTheme.style_rail_button(_rail_world_btn, _portal_open or _aquascape.is_active)
	if _rail_appearance_btn != null:
		var look_on: bool = (_light_panel != null and _light_panel.visible) \
			or (render_panel != null and render_panel.visible) \
			or (sound_panel != null and sound_panel.visible)
		PanelTheme.style_rail_button(_rail_appearance_btn, look_on)
	if _rail_system_btn != null:
		PanelTheme.style_rail_button(_rail_system_btn,
			settings_panel != null and settings_panel.visible)
	_update_notification_badge()
	_apply_rail_button_labels(_rail_dock == "bottom")


func _ordered_rail_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for btn in [
		_rail_create_btn, _rail_world_btn, _rail_appearance_btn,
		_rail_system_btn, _rail_alerts_btn,
	]:
		if btn != null:
			out.append(btn)
	return out


func _apply_rail_button_labels(force_short: bool) -> void:
	var short: bool = force_short or _is_mobile()
	if portal_toggle != null:
		UiIcons.apply_rail_button(portal_toggle, "portal", short)
	if aquascape_toggle != null:
		UiIcons.apply_rail_button(aquascape_toggle, "aquascape", short)
	if creature_creator_toggle != null:
		UiIcons.apply_rail_button(creature_creator_toggle, "creator", short)
	if fish_store_toggle != null:
		UiIcons.apply_rail_button(fish_store_toggle, "store", short)
	if library_toggle != null:
		UiIcons.apply_rail_button(library_toggle, "library", short)
	if notifications_toggle != null:
		UiIcons.apply_rail_button(notifications_toggle, "notifications", short)
	if render_toggle != null:
		UiIcons.apply_rail_button(render_toggle, "render", short)
	if sound_toggle != null:
		UiIcons.apply_rail_button(sound_toggle, "sound", short)
	if settings_toggle != null:
		UiIcons.apply_rail_button(settings_toggle, "settings", short)


func _apply_rail_dock_layout() -> void:
	if right_rail == null or right_cluster == null or _rail_vbox == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var dock: String = "bottom" if _want_bottom_rail(vp) else "right"
	if dock != _rail_dock:
		_rail_dock = dock
		var rail_target: BoxContainer = _rail_vbox
		var source: BoxContainer = _rail_hbox
		if dock == "bottom":
			rail_target = _rail_hbox
			source = _rail_vbox
		if dock == "bottom" and _rail_spacer == null:
			_rail_spacer = Control.new()
			_rail_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_rail_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for btn in _ordered_rail_buttons():
			if btn.get_parent() == source:
				source.remove_child(btn)
				rail_target.add_child(btn)
		if dock == "bottom":
			if _rail_spacer != null and _rail_spacer.get_parent() != _rail_hbox:
				var idx: int = mini(5, _rail_hbox.get_child_count())
				_rail_hbox.add_child(_rail_spacer)
				_rail_hbox.move_child(_rail_spacer, idx)
			_rail_vbox.visible = false
			_rail_hbox.visible = true
		else:
			if _rail_spacer != null and _rail_spacer.get_parent() == _rail_hbox:
				_rail_hbox.remove_child(_rail_spacer)
			_rail_hbox.visible = false
			_rail_vbox.visible = true
		_apply_rail_button_labels(dock == "bottom")

	if dock == "bottom":
		right_rail.anchor_left = 0.0
		right_rail.anchor_top = 1.0
		right_rail.anchor_right = 1.0
		right_rail.anchor_bottom = 1.0
		right_rail.offset_left = PanelTheme.EDGE_MARGIN
		right_rail.offset_top = -PanelTheme.RAIL_BOTTOM_HEIGHT
		right_rail.offset_right = -PanelTheme.EDGE_MARGIN
		right_rail.offset_bottom = -PanelTheme.EDGE_MARGIN
	else:
		var compact: bool = _hud_layout == "compact"
		right_rail.anchor_left = 1.0
		right_rail.anchor_top = 0.0
		right_rail.anchor_right = 1.0
		right_rail.anchor_bottom = 1.0
		if compact:
			right_rail.offset_left = -56.0
			right_rail.offset_top = 44.0
			right_rail.offset_right = -4.0
			right_rail.offset_bottom = -76.0
		else:
			right_rail.offset_left = -64.0
			right_rail.offset_top = 48.0
			right_rail.offset_right = -8.0
			right_rail.offset_bottom = -32.0


func _apply_panel_layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var top: float = PanelTheme.HUD_TOP
	var bottom: float = _hud_bottom_inset()
	var edge: float = PanelTheme.EDGE_MARGIN
	var rail: float = _rail_edge_inset()
	var panel_w: float = clampf(vp.x * 0.33, PanelTheme.PANEL_MIN_W, PanelTheme.PANEL_MAX_W)

	if settings_panel != null:
		settings_panel.offset_top = top
		settings_panel.offset_bottom = -bottom
		settings_panel.offset_right = -rail
		settings_panel.offset_left = -(rail + panel_w)

	if render_panel != null:
		render_panel.offset_top = top
		render_panel.offset_bottom = -bottom
		render_panel.offset_left = edge
		render_panel.offset_right = edge + panel_w

	var sound_w: float = clampf(vp.x * 0.38, 400.0, 560.0)
	if sound_panel != null:
		sound_panel.offset_top = top
		sound_panel.offset_bottom = -bottom
		sound_panel.offset_left = -sound_w * 0.5
		sound_panel.offset_right = sound_w * 0.5

	if library_panel != null:
		library_panel.offset_left = edge
		library_panel.offset_top = top
		library_panel.offset_right = -rail
		library_panel.offset_bottom = -bottom

	var modal_w: float = clampf(vp.x * 0.55, 560.0, 820.0)
	var modal_h: float = clampf(vp.y * 0.62, 420.0, 620.0)
	if creature_creator_panel != null:
		creature_creator_panel.offset_left = -modal_w * 0.5
		creature_creator_panel.offset_right = modal_w * 0.5
		creature_creator_panel.offset_top = -modal_h * 0.5
		creature_creator_panel.offset_bottom = modal_h * 0.5

	var store_w: float = clampf(minf(vp.x * 0.42, 480.0), 320.0, 480.0)
	var store_h: float = clampf(vp.y * 0.52, 360.0, 520.0)
	if fish_store_panel != null:
		fish_store_panel.offset_left = -store_w * 0.5
		fish_store_panel.offset_right = store_w * 0.5
		fish_store_panel.offset_top = -store_h * 0.5
		fish_store_panel.offset_bottom = store_h * 0.5

	if portal_container != null:
		var pip: float = minf(192.0, vp.x * 0.14)
		portal_container.offset_right = -rail
		portal_container.offset_left = -(rail + pip)
		portal_container.offset_top = top + 4.0
		portal_container.offset_bottom = top + 4.0 + pip


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
	var layout_changed: bool = layout != _hud_layout
	if layout_changed:
		_hud_layout = layout
		for chip in _chips.values():
			var s: Label = (chip as Control).get_meta("sublabel_label", null) as Label
			if s != null:
				s.visible = layout == "wide"
		var compact_only_chips := ["shrimp", "snails", "morphs"]
		for k in compact_only_chips:
			var chip: Control = _chips.get(k, null) as Control
			if chip != null and layout == "compact":
				chip.visible = false

	var rail_edge: float = _rail_edge_inset()
	var left_inset: float = 128.0 if layout != "compact" else 112.0
	if stats_bar != null:
		stats_bar.offset_left = left_inset
		stats_bar.offset_right = -rail_edge

	if layout_changed:
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
	# Clicking the same chip twice closes the open popup; clicking a different
	# chip swaps the popup over. Both paths funnel through _close_chip_popups
	# so we never leave two modals stacked on top of each other.
	var was_open: bool = _chip_popup_key == key
	_close_chip_popups()
	if was_open:
		return
	# Mood chip opens the story log instead of a sparkline. The aggregate
	# "how is the tank doing" feel routes naturally to "what happened in
	# this tank's life so far."
	if key == "mood":
		_show_story_popup(color)
		return
	if key == "water":
		_show_water_chemistry_popup(color)
		return
	var hist_key: String = _CHIP_TO_HISTORY.get(key, "")
	if hist_key == "":
		return  # state/morphs chips have no useful history
	_show_history_popup(hist_key, key, color)


# Tracks which chip's popup is currently open (mood/water/<history-key>).
# Empty string when nothing is open.
var _chip_popup_key: String = ""


func _close_chip_popups() -> void:
	if _history_popup != null and _history_popup.visible:
		_history_popup.visible = false
	if _story_popup != null and _story_popup.visible:
		_story_popup.visible = false
	if _water_popup != null and _water_popup.visible:
		_water_popup.visible = false
	_chip_popup_key = ""


func _ui_toggle_side(id: String) -> void:
	_ui_panels.toggle_side(id)
	_sync_rail_toggles()


func _ui_toggle_modal(id: String) -> void:
	_ui_panels.toggle_modal(id)
	_sync_rail_toggles()


func _on_modal_closed(id: String) -> void:
	_ui_panels.notify_modal_closed(id)
	_sync_rail_toggles()


func _ui_open_side(id: String) -> void:
	_ui_panels.open_side(id)
	_sync_rail_toggles()


func _setup_panel_close_hooks() -> void:
	for panel in [settings_panel, render_panel, sound_panel]:
		if panel != null:
			panel.visibility_changed.connect(_on_managed_panel_visibility_changed)


func _on_managed_panel_visibility_changed() -> void:
	if settings_panel != null and not settings_panel.visible:
		_ui_panels.notify_side_closed(UiPanelManager.SIDE_SETTINGS)
	if render_panel != null and not render_panel.visible:
		_ui_panels.notify_side_closed(UiPanelManager.SIDE_RENDER)
	if sound_panel != null and not sound_panel.visible:
		_ui_panels.notify_side_closed(UiPanelManager.SIDE_SOUND)
	_sync_rail_toggles()


func _open_light_panel_exclusive() -> void:
	_ensure_light_panel()
	if _light_panel == null:
		return
	_pull_light_panel_values()
	_light_panel.visible = true
	_light_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("_position_light_panel")
	_sync_light_btn()


func _close_light_panel() -> void:
	if _light_panel != null and _light_panel.visible:
		_light_panel.visible = false
		_light_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_light_btn()


func _open_notifications_panel_exclusive() -> void:
	_ensure_notifications_ui()
	if _notifications_panel == null:
		return
	_notifications_panel.visible = true
	_notifications_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_notifications_panel()


func _close_notifications_panel() -> void:
	if _notifications_panel != null:
		_notifications_panel.visible = false
		_notifications_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _toggle_notifications_panel() -> void:
	_ui_toggle_side(UiPanelManager.SIDE_NOTIFICATIONS)


func _global_pref(key: String, default_val: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(GLOBAL_PREFS_PATH) == OK:
		return cfg.get_value("app", key, default_val)
	return default_val


func _set_global_pref(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(GLOBAL_PREFS_PATH)
	cfg.set_value("app", key, value)
	cfg.save(GLOBAL_PREFS_PATH)


func _setup_rail_groups() -> void:
	if _rail_vbox == null:
		return
	# Hide legacy per-feature rail buttons; group flyouts replace them.
	for btn in [
		portal_toggle, aquascape_toggle, creature_creator_toggle,
		fish_store_toggle, library_toggle, notifications_toggle,
		_light_btn, render_toggle, sound_toggle, settings_toggle,
	]:
		if btn != null:
			btn.visible = false
	var divider: HSeparator = right_cluster.get_node_or_null("VBox/RailDivider") as HSeparator \
		if right_cluster != null else null
	if divider != null:
		divider.visible = false

	_rail_create_btn = _make_rail_group_button("create", "Create")
	_rail_world_btn = _make_rail_group_button("world", "World")
	_rail_appearance_btn = _make_rail_group_button("appearance", "Look")
	_rail_system_btn = _make_rail_group_button("system", "System")
	_rail_alerts_btn = _make_rail_group_button("alerts", "Alerts")
	for gb in [_rail_create_btn, _rail_world_btn, _rail_appearance_btn, _rail_system_btn, _rail_alerts_btn]:
		if gb != null:
			_rail_vbox.add_child(gb)

	_rail_flyout = PanelContainer.new()
	_rail_flyout.name = "RailFlyout"
	_rail_flyout.visible = false
	_rail_flyout.mouse_filter = Control.MOUSE_FILTER_STOP
	_rail_flyout.z_index = 120
	PanelTheme.apply_panel_chrome(_rail_flyout)
	add_child(_rail_flyout)
	_rail_flyout_vbox = VBoxContainer.new()
	_rail_flyout_vbox.add_theme_constant_override("separation", 4)
	_rail_flyout.add_child(_rail_flyout_vbox)

	_notif_badge = Label.new()
	_notif_badge.text = ""
	_notif_badge.add_theme_font_size_override("font_size", 9)
	_notif_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_notif_badge.position = Vector2(34, 2)
	_notif_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _rail_alerts_btn != null:
		_rail_alerts_btn.add_child(_notif_badge)


func _make_rail_group_button(group_id: String, _label: String) -> Button:
	var btn := Button.new()
	btn.name = "RailGroup_%s" % group_id
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(PanelTheme.RAIL_BUTTON, PanelTheme.RAIL_BUTTON)
	UiIcons.apply_rail_button(btn, group_id, _is_mobile())
	btn.pressed.connect(func(): _toggle_rail_flyout(group_id, btn))
	PanelTheme.style_rail_button(btn, false)
	return btn


func _toggle_rail_flyout(group_id: String, anchor: Button) -> void:
	if _rail_flyout == null or _rail_flyout_vbox == null:
		return
	if _rail_flyout.visible and _rail_flyout.has_meta("group") \
			and String(_rail_flyout.get_meta("group")) == group_id:
		_rail_flyout.visible = false
		return
	for c in _rail_flyout_vbox.get_children():
		c.queue_free()
	_rail_flyout.set_meta("group", group_id)
	var items: Array[Dictionary] = _rail_flyout_items(group_id)
	for item in items:
		var b := Button.new()
		b.text = String(item.get("label", "?"))
		b.tooltip_text = String(item.get("tip", ""))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(200, 36)
		b.pressed.connect(func():
			_rail_flyout.visible = false
			var action: Callable = item.get("action")
			if action.is_valid():
				action.call())
		_rail_flyout_vbox.add_child(b)
	_rail_flyout.visible = true
	var grect: Rect2 = anchor.get_global_rect()
	_rail_flyout.global_position = Vector2(grect.position.x - 210.0, grect.position.y)
	_rail_flyout.size = Vector2(200, 8 + items.size() * 40)


func _rail_flyout_items(group_id: String) -> Array[Dictionary]:
	match group_id:
		"create":
			return [
				{"label": "Creature Creator", "tip": "Design fish, shrimp, plants…",
					"action": func(): _ui_toggle_modal(UiPanelManager.MODAL_CREATOR)},
				{"label": "Fish Store", "tip": "Buy procedurally generated fish",
					"action": func(): _ui_toggle_modal(UiPanelManager.MODAL_STORE)},
				{"label": "Life Library", "tip": "Discovered species collection",
					"action": func(): _ui_toggle_modal(UiPanelManager.MODAL_LIBRARY)},
			]
		"world":
			return [
				{"label": "Aquascape", "tip": "Sculpt substrate and hardscape (B)",
					"action": _toggle_aquascape},
				{"label": "Follow Portal", "tip": "Creature picture-in-picture (C)",
					"action": _toggle_portal},
			]
		"appearance":
			return [
				{"label": "Lighting", "tip": "Sun, day cycle, post-process",
					"action": func(): _ui_toggle_side(UiPanelManager.SIDE_LIGHT)},
				{"label": "Rendering", "tip": "Resolution, fog, MSAA (R)",
					"action": func(): _ui_toggle_side(UiPanelManager.SIDE_RENDER)},
				{"label": "Sound Studio", "tip": "Procedural music (M)",
					"action": func(): _ui_toggle_side(UiPanelManager.SIDE_SOUND)},
			]
		"system":
			return [
				{"label": "Settings", "tip": "Tank shape, stocking, AI (O)",
					"action": func(): _ui_toggle_side(UiPanelManager.SIDE_SETTINGS)},
			]
		"alerts":
			return [
				{"label": "Notifications", "tip": "Events, discoveries, alerts",
					"action": func(): _ui_toggle_side(UiPanelManager.SIDE_NOTIFICATIONS)},
			]
	return []


func _update_notification_badge() -> void:
	if _notif_badge == null:
		return
	var unread: int = 0
	for n in _notifications:
		if not bool(n.get("read", false)):
			unread += 1
	_notif_badge.text = str(unread) if unread > 0 else ""
	if _rail_alerts_btn != null:
		PanelTheme.style_rail_button(_rail_alerts_btn, unread > 0)


func _ensure_notifications_ui() -> void:
	if _notifications_panel != null and is_instance_valid(_notifications_panel):
		return
	_notifications_toast_layer = Control.new()
	_notifications_toast_layer.name = "NotificationToasts"
	_notifications_toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notifications_toast_layer.anchor_left = 1.0
	_notifications_toast_layer.anchor_top = 0.0
	_notifications_toast_layer.anchor_right = 1.0
	_notifications_toast_layer.anchor_bottom = 0.0
	_notifications_toast_layer.offset_left = -360.0
	_notifications_toast_layer.offset_top = 56.0
	_notifications_toast_layer.offset_right = -74.0
	_notifications_toast_layer.offset_bottom = 300.0
	add_child(_notifications_toast_layer)

	_notifications_panel = PanelContainer.new()
	_notifications_panel.visible = false
	_notifications_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_notifications_panel.custom_minimum_size = Vector2(560, 360)
	_notifications_panel.anchor_left = 1.0
	_notifications_panel.anchor_top = 0.0
	_notifications_panel.anchor_right = 1.0
	_notifications_panel.anchor_bottom = 1.0
	_notifications_panel.offset_left = -640.0
	_notifications_panel.offset_top = 56.0
	_notifications_panel.offset_right = -74.0
	_notifications_panel.offset_bottom = -40.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.95)
	style.border_color = Color(0.35, 0.45, 0.6, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	_notifications_panel.add_theme_stylebox_override("panel", style)
	add_child(_notifications_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notifications_panel.add_child(root)

	var title := Label.new()
	title.text = "Notifications"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99))
	root.add_child(title)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	root.add_child(controls)

	_notifications_filter_kind = OptionButton.new()
	_notifications_filter_kind.add_item("Kind: All", 0)
	_notifications_filter_kind.add_item("Kind: Discovery", 1)
	_notifications_filter_kind.add_item("Kind: Population", 2)
	_notifications_filter_kind.add_item("Kind: Water", 3)
	_notifications_filter_kind.add_item("Kind: Milestone", 4)
	_notifications_filter_kind.add_item("Kind: Welcome", 5)
	_notifications_filter_kind.item_selected.connect(_on_notifications_kind_filter_selected)
	controls.add_child(_notifications_filter_kind)

	_notifications_filter_severity = OptionButton.new()
	_notifications_filter_severity.add_item("Severity: All", 0)
	_notifications_filter_severity.add_item("Severity: Info", 1)
	_notifications_filter_severity.add_item("Severity: Important", 2)
	_notifications_filter_severity.add_item("Severity: Critical", 3)
	_notifications_filter_severity.item_selected.connect(_on_notifications_severity_filter_selected)
	controls.add_child(_notifications_filter_severity)

	_notifications_sort = OptionButton.new()
	_notifications_sort.add_item("Sort: Newest", NOTIF_SORT_NEWEST)
	_notifications_sort.add_item("Sort: Oldest", NOTIF_SORT_OLDEST)
	_notifications_sort.add_item("Sort: Severity", NOTIF_SORT_SEVERITY)
	_notifications_sort.item_selected.connect(_on_notifications_sort_selected)
	controls.add_child(_notifications_sort)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_clear_notifications)
	controls.add_child(clear_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_notifications_list = VBoxContainer.new()
	_notifications_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notifications_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_notifications_list)

	_notifications_empty_label = Label.new()
	_notifications_empty_label.text = "No notifications yet."
	_notifications_empty_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 0.9))
	_notifications_list.add_child(_notifications_empty_label)


func _on_notifications_kind_filter_selected(idx: int) -> void:
	match idx:
		1: _notification_filter_kind = "discovery"
		2: _notification_filter_kind = "population"
		3: _notification_filter_kind = "water_alert"
		4: _notification_filter_kind = "milestone"
		5: _notification_filter_kind = "welcome_back"
		_: _notification_filter_kind = NOTIF_FILTER_ALL
	_refresh_notifications_panel()


func _on_notifications_severity_filter_selected(idx: int) -> void:
	match idx:
		1: _notification_filter_severity = NOTIF_SEVERITY_INFO
		2: _notification_filter_severity = NOTIF_SEVERITY_IMPORTANT
		3: _notification_filter_severity = NOTIF_SEVERITY_CRITICAL
		_: _notification_filter_severity = NOTIF_FILTER_ALL
	_refresh_notifications_panel()


func _on_notifications_sort_selected(idx: int) -> void:
	_notification_sort = idx
	_refresh_notifications_panel()


func _clear_notifications() -> void:
	_notifications.clear()
	if _sim != null:
		_notification_story_idx = (_sim.story_events as Array).size()
	else:
		_notification_story_idx = 0
	_refresh_notifications_panel()


func _kind_icon(kind: String) -> String:
	match kind:
		"discovery":
			return UiIcons.fauna_label("fish")
		"population":
			return "◉"
		"water_alert":
			return "!"
		"milestone":
			return "*"
		"welcome_back":
			return "↺"
		_:
			return "•"


func _severity_rank(sev: String) -> int:
	match sev:
		NOTIF_SEVERITY_CRITICAL:
			return 2
		NOTIF_SEVERITY_IMPORTANT:
			return 1
		_:
			return 0


func _format_notification_age(unix_ts: int) -> String:
	var delta: int = max(0, int(Time.get_unix_time_from_system()) - unix_ts)
	if delta < 60:
		return "%ds ago" % delta
	if delta < 3600:
		return "%dm ago" % int(delta / 60.0)
	var h: int = int(delta / 3600.0)
	if h < 24:
		return "%dh ago" % h
	return "%dd ago" % int(delta / 86400.0)


func _refresh_notifications_panel() -> void:
	if _notifications_list == null:
		return
	for c in _notifications_list.get_children():
		c.queue_free()
	var rows: Array[Dictionary] = []
	for n in _notifications:
		var kind: String = String(n.get("kind", "system"))
		var sev: String = String(n.get("severity", NOTIF_SEVERITY_INFO))
		if _notification_filter_kind != NOTIF_FILTER_ALL and kind != _notification_filter_kind:
			continue
		if _notification_filter_severity != NOTIF_FILTER_ALL and sev != _notification_filter_severity:
			continue
		rows.append(n)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _notification_sort == NOTIF_SORT_OLDEST:
			return int(a.get("ts", 0)) < int(b.get("ts", 0))
		if _notification_sort == NOTIF_SORT_SEVERITY:
			var ar: int = _severity_rank(String(a.get("severity", NOTIF_SEVERITY_INFO)))
			var br: int = _severity_rank(String(b.get("severity", NOTIF_SEVERITY_INFO)))
			if ar == br:
				return int(a.get("ts", 0)) > int(b.get("ts", 0))
			return ar > br
		return int(a.get("ts", 0)) > int(b.get("ts", 0))
	)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No notifications match this filter."
		empty.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86, 0.9))
		_notifications_list.add_child(empty)
		return
	for n in rows:
		_notifications_list.add_child(_build_notification_row(n))


func _build_notification_row(n: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.78)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var icon := Label.new()
	icon.text = _kind_icon(String(n.get("kind", "system")))
	icon.custom_minimum_size = Vector2(20, 0)
	hb.add_child(icon)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var title := Label.new()
	var title_txt: String = String(n.get("title", "Notification"))
	var age_txt: String = _format_notification_age(int(n.get("ts", 0)))
	title.text = "%s · %s" % [title_txt, age_txt]
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 0.99))
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var body := Label.new()
	body.text = String(n.get("body", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(0.80, 0.86, 0.94, 0.95))
	body.add_theme_font_size_override("font_size", 11)
	vb.add_child(body)
	return row


func _push_notification(kind: String, severity: String, title: String, body: String,
		show_toast: bool = false, meta: Dictionary = {}) -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var notif: Dictionary = {
		"id": _notification_next_id,
		"ts": now,
		"kind": kind,
		"severity": severity,
		"title": title,
		"body": body,
		"meta": meta,
	}
	_notification_next_id += 1
	notif["read"] = false
	_notifications.append(notif)
	if _notifications.size() > NOTIF_MAX_HISTORY:
		_notifications.pop_front()
	_update_notification_badge()
	if show_toast:
		_notification_toast_queue.append(notif)
		_pump_notification_toast_queue()
	if _notifications_panel != null and _notifications_panel.visible:
		_refresh_notifications_panel()


func _pump_notification_toast_queue() -> void:
	if _notifications_toast_layer == null:
		return
	while _notification_toast_active < NOTIF_TOAST_MAX_ACTIVE and not _notification_toast_queue.is_empty():
		var notif: Dictionary = _notification_toast_queue.pop_front()
		_spawn_notification_toast(notif)


func _spawn_notification_toast(notif: Dictionary) -> void:
	_notification_toast_active += 1
	var card := PanelContainer.new()
	card.modulate.a = 0.0
	card.position = Vector2(28, float(_notification_toast_active - 1) * 74.0)
	card.scale = Vector2(0.96, 0.96)
	card.custom_minimum_size = Vector2(250, 64)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.19, 0.96)
	style.border_color = Color(0.35, 0.45, 0.6, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)

	var title := Label.new()
	title.text = "%s %s" % [_kind_icon(String(notif.get("kind", "system"))), String(notif.get("title", ""))]
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.add_theme_font_size_override("font_size", 12)
	vb.add_child(title)

	var body := Label.new()
	body.text = String(notif.get("body", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color(0.80, 0.88, 0.96, 0.95))
	body.add_theme_font_size_override("font_size", 10)
	vb.add_child(body)
	_notifications_toast_layer.add_child(card)

	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.20)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.20)
	tw.tween_interval(4.2)
	tw.tween_property(card, "modulate:a", 0.0, 1.15)
	tw.parallel().tween_property(card, "position:y", card.position.y - 14.0, 1.15)
	tw.tween_callback(func() -> void:
		if is_instance_valid(card):
			card.queue_free()
		_notification_toast_active = maxi(0, _notification_toast_active - 1)
		_pump_notification_toast_queue()
	)


func _collect_story_notifications() -> void:
	if _sim == null:
		return
	var events: Array = _sim.story_events
	if _notification_story_idx < 0:
		_notification_story_idx = 0
	if _notification_story_idx > events.size():
		_notification_story_idx = events.size()
	for i in range(_notification_story_idx, events.size()):
		var e: Dictionary = events[i]
		var text: String = String(e.get("text", ""))
		if text == "":
			continue
		var info: Dictionary = _classify_story_notification(text)
		_push_notification(
			String(info.get("kind", "milestone")),
			String(info.get("severity", NOTIF_SEVERITY_INFO)),
			String(info.get("title", "Tank event")),
			text,
			bool(info.get("toast", false))
		)
	_notification_story_idx = events.size()


func _classify_story_notification(text: String) -> Dictionary:
	var low: String = text.to_lower()
	if low.contains("collapsed") or low.contains("extirpated") or low.contains("gone"):
		return {"kind": "population", "severity": NOTIF_SEVERITY_CRITICAL, "title": "Population collapse", "toast": true}
	if low.contains("swelling") or low.contains("population at"):
		return {"kind": "population", "severity": NOTIF_SEVERITY_IMPORTANT, "title": "Population shift", "toast": true}
	if low.contains("generation") or low.contains("lineages deepening") or low.contains("reached"):
		return {"kind": "milestone", "severity": NOTIF_SEVERITY_IMPORTANT, "title": "Milestone reached", "toast": true}
	if low.contains("bloom") or low.contains("walstad pulse"):
		return {"kind": "population", "severity": NOTIF_SEVERITY_INFO, "title": "Ecosystem update", "toast": false}
	return {"kind": "milestone", "severity": NOTIF_SEVERITY_INFO, "title": "Story event", "toast": false}


func _collect_water_alert_notifications() -> void:
	if _stats.is_empty():
		return
	var o2: float = float(_stats.get("dissolved_o2", 1.0))
	var ammonia: float = float(_stats.get("ammonia", 0.0))
	var nitrite: float = float(_stats.get("nitrite", 0.0))

	var o2_crit: bool = o2 < 0.42
	if o2_crit and not _water_alert_low_o2_active:
		_water_alert_low_o2_active = true
		_push_notification("water_alert", NOTIF_SEVERITY_CRITICAL,
			"Critical O2", "Dissolved oxygen dropped to %d%%." % int(round(o2 * 100.0)), true)
	elif not o2_crit and _water_alert_low_o2_active and o2 > 0.56:
		_water_alert_low_o2_active = false
		_push_notification("water_alert", NOTIF_SEVERITY_IMPORTANT,
			"O2 recovering", "Dissolved oxygen recovered to %d%%." % int(round(o2 * 100.0)), false)

	var ammonia_crit: bool = ammonia >= 0.35
	if ammonia_crit and not _water_alert_ammonia_active:
		_water_alert_ammonia_active = true
		_push_notification("water_alert", NOTIF_SEVERITY_CRITICAL,
			"Ammonia spike", "Ammonia reached %.2f ppm." % ammonia, true)
	elif not ammonia_crit and _water_alert_ammonia_active and ammonia < 0.22:
		_water_alert_ammonia_active = false
		_push_notification("water_alert", NOTIF_SEVERITY_IMPORTANT,
			"Ammonia easing", "Ammonia fell to %.2f ppm." % ammonia, false)

	var nitrite_crit: bool = nitrite >= 0.30
	if nitrite_crit and not _water_alert_nitrite_active:
		_water_alert_nitrite_active = true
		_push_notification("water_alert", NOTIF_SEVERITY_CRITICAL,
			"Nitrite spike", "Nitrite reached %.2f ppm." % nitrite, true)
	elif not nitrite_crit and _water_alert_nitrite_active and nitrite < 0.20:
		_water_alert_nitrite_active = false
		_push_notification("water_alert", NOTIF_SEVERITY_IMPORTANT,
			"Nitrite easing", "Nitrite fell to %.2f ppm." % nitrite, false)


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
	_chip_popup_key = "mood"


var _water_popup: PanelContainer = null
var _water_detail: Label = null


func _ensure_water_popup() -> void:
	if _water_popup != null:
		return
	_water_popup = PanelContainer.new()
	_water_popup.visible = false
	_water_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_water_popup.custom_minimum_size = Vector2(220, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.94)
	style.border_color = Color(0.35, 0.45, 0.6, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_water_popup.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	_water_popup.add_child(vb)
	var title := Label.new()
	title.text = "Water chemistry"
	title.add_theme_font_size_override("font_size", 13)
	vb.add_child(title)
	_water_detail = Label.new()
	_water_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_water_detail)
	add_child(_water_popup)


func _show_water_chemistry_popup(_chip_color: Color) -> void:
	_ensure_water_popup()
	var lines: PackedStringArray = HudController.water_detail_lines(_stats)
	_water_detail.text = "\n".join(lines)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_water_popup.size = _water_popup.custom_minimum_size
	_water_popup.position = Vector2((vp.x - _water_popup.size.x) * 0.5, 56.0)
	_water_popup.visible = true
	_chip_popup_key = "water"


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
	_chip_popup_key = chip_key


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
	if right_rail != null and right_rail.modulate != HUD_LIT_MODULATE:
		right_rail.modulate = HUD_LIT_MODULATE


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


func _is_night_time() -> bool:
	if _sim == null:
		return false
	var p: float = fposmod(float(_sim.day_phase), 1.0)
	return p >= 0.5 and p < 0.875


func _add_tank_lights_toggle() -> void:
	# Always-visible Light rail button. Click opens _light_panel where the
	# tank-lights toggle, intensity, warmth, and caustics live together.
	if _rail_vbox == null:
		return
	_light_btn = Button.new()
	_light_btn.name = "LightToggle"
	_light_btn.focus_mode = Control.FOCUS_NONE
	_light_btn.pressed.connect(_toggle_light_panel)
	_rail_vbox.add_child(_light_btn)
	# Slot between Notifications and the RailDivider so it groups with the
	# transient alert-style toggles, not the settings cluster below.
	var notif_idx: int = notifications_toggle.get_index() if notifications_toggle != null else -1
	if notif_idx >= 0:
		_rail_vbox.move_child(_light_btn, notif_idx + 1)
	UiIcons.apply_rail_button(_light_btn, "light", _is_mobile())
	PanelTheme.style_rail_button(_light_btn, false)


func _toggle_light_panel() -> void:
	_ui_toggle_side(UiPanelManager.SIDE_LIGHT)


func _ensure_light_panel() -> void:
	if _light_panel != null and is_instance_valid(_light_panel):
		return
	_light_panel = PanelContainer.new()
	_light_panel.name = "LightPanel"
	_light_panel.visible = false
	_light_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_light_panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.95)
	style.border_color = Color(0.35, 0.45, 0.6, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	_light_panel.add_theme_stylebox_override("panel", style)
	add_child(_light_panel)

	# Panel grew quite tall (preset row + 4 sections) so wrap the body in a
	# ScrollContainer; the panel itself is height-capped in _position_light_panel.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_light_panel.add_child(outer)

	var title := Label.new()
	title.text = "Light"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99))
	outer.add_child(title)

	# Preset row: dropdown at the top so users can grab a curated look in
	# one click. Selecting a non-custom preset applies its values; touching
	# any slider/checkbox snaps back to "custom" (via _light_applying_preset
	# guard).
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	outer.add_child(preset_row)
	var preset_lbl := Label.new()
	preset_lbl.text = "Preset"
	preset_lbl.custom_minimum_size = Vector2(72, 0)
	preset_row.add_child(preset_lbl)
	_light_preset_option = OptionButton.new()
	_light_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_preset_option.add_item("Custom")
	_light_preset_option.set_item_metadata(0, "custom")
	for key in TankConfig.LIGHTING_PRESETS.keys():
		var preset: Dictionary = TankConfig.LIGHTING_PRESETS[key]
		_light_preset_option.add_item(String(preset.get("label", key)))
		_light_preset_option.set_item_metadata(_light_preset_option.item_count - 1, key)
	_light_preset_option.item_selected.connect(_on_lighting_preset_selected)
	preset_row.add_child(_light_preset_option)
	# Randomize button — picks a preset at random and jitters the values
	# so successive presses still give variety.
	var random_btn := Button.new()
	random_btn.text = "🎲"
	random_btn.tooltip_text = "Randomize lighting (picks a preset and jitters its values)"
	random_btn.custom_minimum_size = Vector2(36, 0)
	random_btn.focus_mode = Control.FOCUS_NONE
	random_btn.pressed.connect(_on_lighting_randomize_pressed)
	preset_row.add_child(random_btn)

	# Scroll body — every section gets added to `vbox` inside the scroll.
	# ScrollContainer's natural vertical size is 0; without a min height
	# it collapses to a single pixel and the user sees only the preset row.
	# Give it a generous height that _position_light_panel can re-clamp once
	# the viewport size is known.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 560)
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	# Stash so _position_light_panel can resize it to fit the viewport.
	_light_panel.set_meta("scroll_container", scroll)

	# ---- Global section ----
	_add_light_section(vbox, "Global")

	_light_master_check = CheckBox.new()
	_light_master_check.text = "Lights enabled (master)"
	_light_master_check.toggled.connect(_on_light_master_toggled)
	vbox.add_child(_light_master_check)
	_attach_reset(_light_master_check, "light_master_enabled")

	_light_day_cycle_check = CheckBox.new()
	_light_day_cycle_check.text = "Day / night cycle running"
	_light_day_cycle_check.toggled.connect(_on_day_cycle_toggled)
	vbox.add_child(_light_day_cycle_check)
	_attach_reset(_light_day_cycle_check, "day_cycle_enabled")

	_light_day_phase_value = Label.new()
	_light_day_phase_slider = PanelTheme.add_slider_row(
		vbox, "Day phase (dawn→noon→dusk→night)", 0.0, 1.0, 0.01,
		_light_day_phase_value)
	_light_day_phase_slider.value_changed.connect(_on_day_phase_changed)
	# (No reset — day phase is sim runtime state, not a user-default.)

	_light_day_length_value = Label.new()
	_light_day_length_slider = PanelTheme.add_slider_row(
		vbox, "Day length (seconds)", 30.0, 3600.0, 15.0, _light_day_length_value)
	_light_day_length_slider.value_changed.connect(_on_day_length_changed)
	_attach_reset(_light_day_length_slider, "day_length_s")

	_light_sunset_drama_value = Label.new()
	_light_sunset_drama_slider = PanelTheme.add_slider_row(
		vbox, "Sunset drama", 0.0, 2.5, 0.05, _light_sunset_drama_value)
	_light_sunset_drama_slider.value_changed.connect(_on_sunset_drama_changed)
	_attach_reset(_light_sunset_drama_slider, "sunset_drama")

	_light_global_intensity_value = Label.new()
	_light_global_intensity_slider = PanelTheme.add_slider_row(
		vbox, "Global intensity", 0.0, 1.0, 0.05, _light_global_intensity_value)
	_light_global_intensity_slider.value_changed.connect(_on_global_intensity_changed)
	_attach_reset(_light_global_intensity_slider, "global_intensity")

	_light_global_warmth_value = Label.new()
	_light_global_warmth_slider = PanelTheme.add_slider_row(
		vbox, "Global warmth (cool→warm)", 0.0, 1.0, 0.05, _light_global_warmth_value)
	_light_global_warmth_slider.value_changed.connect(_on_global_warmth_changed)
	_attach_reset(_light_global_warmth_slider, "global_warmth")

	_light_ambient_floor_value = Label.new()
	_light_ambient_floor_slider = PanelTheme.add_slider_row(
		vbox, "Ambient floor (dark-floor lift)", 0.0, 1.0, 0.05, _light_ambient_floor_value)
	_light_ambient_floor_slider.value_changed.connect(_on_ambient_floor_changed)
	_attach_reset(_light_ambient_floor_slider, "ambient_floor")

	_light_biolum_value = Label.new()
	_light_biolum_slider = PanelTheme.add_slider_row(
		vbox, "Bioluminescence ×", 0.0, 3.0, 0.1, _light_biolum_value)
	_light_biolum_slider.value_changed.connect(_on_biolum_changed)
	_attach_reset(_light_biolum_slider, "biolum_multiplier")

	# Sun direction 2D pad. Click/drag inside the box to set yaw (X axis) and
	# pitch (Y axis). The pad mirrors cfg.light_yaw + cfg.light_pitch and
	# replaces the two separate sliders that used to live in Settings.
	_light_sun_pad = _make_sun_direction_pad(vbox)

	# Phase chips — quick jump-to-anchor buttons under the Day phase slider.
	# Trivial code, big convenience: tap to land on dawn/noon/dusk/midnight.
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	vbox.add_child(chip_row)
	var chip_lbl := Label.new()
	chip_lbl.text = "Jump"
	chip_lbl.custom_minimum_size = Vector2(160, 0)
	chip_row.add_child(chip_lbl)
	for chip in [
		{"label": "Dawn", "phase": 0.0},
		{"label": "Noon", "phase": 0.25},
		{"label": "Dusk", "phase": 0.5},
		{"label": "Night", "phase": 0.75},
	]:
		var b := Button.new()
		b.text = String(chip["label"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p: float = float(chip["phase"])
		b.pressed.connect(func(): _jump_to_phase(p))
		chip_row.add_child(b)

	# ---- Tank fixture section ----
	_add_light_section(vbox, "Tank fixture")

	_light_tank_check = CheckBox.new()
	_light_tank_check.text = "Tank lights on (artificial fixture at night)"
	_light_tank_check.toggled.connect(_on_light_tank_toggled)
	vbox.add_child(_light_tank_check)
	_attach_reset(_light_tank_check, "tank_lights_on")

	_light_fixture_intensity_value = Label.new()
	_light_fixture_intensity_slider = PanelTheme.add_slider_row(
		vbox, "Fixture intensity", 0.0, 1.0, 0.05, _light_fixture_intensity_value)
	_light_fixture_intensity_slider.value_changed.connect(_on_fixture_intensity_changed)
	_attach_reset(_light_fixture_intensity_slider, "tank_fixture_intensity")

	_light_fixture_color_picker = _make_color_row(vbox, "Fixture color",
		_on_fixture_color_changed)
	_attach_reset(_light_fixture_color_picker, "tank_fixture_color")

	_light_caustics_check = CheckBox.new()
	_light_caustics_check.text = "Show surface caustics"
	_light_caustics_check.toggled.connect(_on_light_caustics_toggled)
	vbox.add_child(_light_caustics_check)
	_attach_reset(_light_caustics_check, "light_caustics")

	_light_caustic_strength_value = Label.new()
	_light_caustic_strength_slider = PanelTheme.add_slider_row(
		vbox, "Caustic intensity ×", 0.0, 2.0, 0.05, _light_caustic_strength_value)
	_light_caustic_strength_slider.value_changed.connect(_on_caustic_strength_changed)
	_attach_reset(_light_caustic_strength_slider, "caustic_intensity_user")

	# ---- Accent & moonlight section ----
	_add_light_section(vbox, "Accent & moonlight")

	_light_moon_check = CheckBox.new()
	_light_moon_check.text = "Moonlight (cool nighttime fill)"
	_light_moon_check.toggled.connect(_on_moon_toggled)
	vbox.add_child(_light_moon_check)
	_attach_reset(_light_moon_check, "moonlight_enabled")
	_light_moon_intensity_value = Label.new()
	_light_moon_intensity_slider = PanelTheme.add_slider_row(
		vbox, "Moon intensity", 0.0, 1.0, 0.05, _light_moon_intensity_value)
	_light_moon_intensity_slider.value_changed.connect(_on_moon_intensity_changed)
	_attach_reset(_light_moon_intensity_slider, "moonlight_intensity")
	_light_moon_color_picker = _make_color_row(vbox, "Moon color", _on_moon_color_changed)
	_attach_reset(_light_moon_color_picker, "moonlight_color")

	_light_accent1_check = CheckBox.new()
	_light_accent1_check.text = "Accent 1 (front-left, mid-water)"
	_light_accent1_check.toggled.connect(_on_accent1_toggled)
	vbox.add_child(_light_accent1_check)
	_attach_reset(_light_accent1_check, "accent1_enabled")
	_light_accent1_intensity_value = Label.new()
	_light_accent1_intensity_slider = PanelTheme.add_slider_row(
		vbox, "Accent 1 intensity", 0.0, 1.5, 0.05, _light_accent1_intensity_value)
	_light_accent1_intensity_slider.value_changed.connect(_on_accent1_intensity_changed)
	_attach_reset(_light_accent1_intensity_slider, "accent1_intensity")
	_light_accent1_color_picker = _make_color_row(vbox, "Accent 1 color", _on_accent1_color_changed)
	_attach_reset(_light_accent1_color_picker, "accent1_color")

	_light_accent2_check = CheckBox.new()
	_light_accent2_check.text = "Accent 2 (back-right, mid-water)"
	_light_accent2_check.toggled.connect(_on_accent2_toggled)
	vbox.add_child(_light_accent2_check)
	_attach_reset(_light_accent2_check, "accent2_enabled")
	_light_accent2_intensity_value = Label.new()
	_light_accent2_intensity_slider = PanelTheme.add_slider_row(
		vbox, "Accent 2 intensity", 0.0, 1.5, 0.05, _light_accent2_intensity_value)
	_light_accent2_intensity_slider.value_changed.connect(_on_accent2_intensity_changed)
	_attach_reset(_light_accent2_intensity_slider, "accent2_intensity")
	_light_accent2_color_picker = _make_color_row(vbox, "Accent 2 color", _on_accent2_color_changed)
	_attach_reset(_light_accent2_color_picker, "accent2_color")

	# ---- Post-process section ----
	_add_light_section(vbox, "Post-process")

	_light_pp_vignette_value = Label.new()
	_light_pp_vignette_slider = PanelTheme.add_slider_row(
		vbox, "Vignette", 0.0, 1.0, 0.05, _light_pp_vignette_value)
	_light_pp_vignette_slider.value_changed.connect(_on_pp_vignette_changed)
	_attach_reset(_light_pp_vignette_slider, "pp_vignette_strength")

	_light_pp_vignette_falloff_value = Label.new()
	_light_pp_vignette_falloff_slider = PanelTheme.add_slider_row(
		vbox, "Vignette falloff", 0.5, 4.0, 0.1, _light_pp_vignette_falloff_value)
	_light_pp_vignette_falloff_slider.value_changed.connect(_on_pp_vignette_falloff_changed)
	_attach_reset(_light_pp_vignette_falloff_slider, "pp_vignette_falloff")

	_light_pp_bloom_threshold_value = Label.new()
	_light_pp_bloom_threshold_slider = PanelTheme.add_slider_row(
		vbox, "Bloom threshold", 0.0, 1.0, 0.02, _light_pp_bloom_threshold_value)
	_light_pp_bloom_threshold_slider.value_changed.connect(_on_pp_bloom_threshold_changed)
	_attach_reset(_light_pp_bloom_threshold_slider, "pp_bloom_threshold")

	_light_pp_bloom_strength_value = Label.new()
	_light_pp_bloom_strength_slider = PanelTheme.add_slider_row(
		vbox, "Bloom strength", 0.0, 1.0, 0.02, _light_pp_bloom_strength_value)
	_light_pp_bloom_strength_slider.value_changed.connect(_on_pp_bloom_strength_changed)
	_attach_reset(_light_pp_bloom_strength_slider, "pp_bloom_strength")

	_light_pp_outline_value = Label.new()
	_light_pp_outline_slider = PanelTheme.add_slider_row(
		vbox, "Edge outline", 0.0, 1.0, 0.05, _light_pp_outline_value)
	_light_pp_outline_slider.value_changed.connect(_on_pp_outline_changed)
	_attach_reset(_light_pp_outline_slider, "outline_strength")

	_light_pp_dither_value = Label.new()
	_light_pp_dither_slider = PanelTheme.add_slider_row(
		vbox, "Dither", 0.0, 1.0, 0.05, _light_pp_dither_value)
	_light_pp_dither_slider.value_changed.connect(_on_pp_dither_changed)
	_attach_reset(_light_pp_dither_slider, "dither_strength")

	_light_pp_crt_value = Label.new()
	_light_pp_crt_slider = PanelTheme.add_slider_row(
		vbox, "CRT scanline", 0.0, 1.0, 0.05, _light_pp_crt_value)
	_light_pp_crt_slider.value_changed.connect(_on_pp_crt_changed)
	_attach_reset(_light_pp_crt_slider, "crt_strength")

	_light_pp_region_dither_check = CheckBox.new()
	_light_pp_region_dither_check.text = "Region-aware dither (heavy on water, light on fauna)"
	_light_pp_region_dither_check.toggled.connect(_on_pp_region_dither_toggled)
	vbox.add_child(_light_pp_region_dither_check)
	_attach_reset(_light_pp_region_dither_check, "dither_region_aware")

	_light_pp_bank_lock_check = CheckBox.new()
	_light_pp_bank_lock_check.text = "Lock palette to nearest hue bank (16-color feel)"
	_light_pp_bank_lock_check.toggled.connect(_on_pp_bank_lock_toggled)
	vbox.add_child(_light_pp_bank_lock_check)
	_attach_reset(_light_pp_bank_lock_check, "palette_bank_lock")

	# ---- Per-phase color override section (#14) ----
	_add_light_section(vbox, "Per-phase colors")

	_light_tod_override_check = CheckBox.new()
	_light_tod_override_check.text = "Use these instead of the built-in dawn/day/dusk/night"
	_light_tod_override_check.toggled.connect(_on_tod_override_toggled)
	vbox.add_child(_light_tod_override_check)
	_attach_reset(_light_tod_override_check, "tod_use_overrides")

	_light_tod_dawn_picker = _make_color_row(vbox, "Dawn", _on_tod_dawn_changed)
	_attach_reset(_light_tod_dawn_picker, "tod_dawn_color")
	_light_tod_day_picker = _make_color_row(vbox, "Day (noon)", _on_tod_day_changed)
	_attach_reset(_light_tod_day_picker, "tod_day_color")
	_light_tod_dusk_picker = _make_color_row(vbox, "Dusk", _on_tod_dusk_changed)
	_attach_reset(_light_tod_dusk_picker, "tod_dusk_color")
	_light_tod_night_picker = _make_color_row(vbox, "Night", _on_tod_night_changed)
	_attach_reset(_light_tod_night_picker, "tod_night_color")

	var hint := PanelTheme.make_description()
	hint.text = "Master off renders the tank near-black. For fixture type, direction, and beams open Settings."
	vbox.add_child(hint)


# 2D pad widget for the sun direction. The X axis maps to cfg.light_yaw
# (0..1, full circle) and Y axis to cfg.light_pitch (0 top-down → 1 horizontal).
# Drawing draws a faint axis cross + a marker at the current value.
# Default values for every Light-panel control. Keyed by TankConfig var name
# so _attach_reset can look up "what does ↻ on this slider mean?" Defaults
# here MUST stay in sync with TankConfig.reset_to_defaults().
const _LIGHT_DEFAULTS: Dictionary = {
	"light_master_enabled": true,
	"day_cycle_enabled": true,
	"day_length_s": 360.0,
	"sunset_drama": 0.75,
	"global_intensity": 0.5,
	"global_warmth": 0.6,
	"tank_lights_on": true,
	"tank_fixture_intensity": 0.5,
	"tank_fixture_color": Color(1.0, 0.95, 0.85),
	"light_caustics": true,
	"caustic_intensity_user": 1.0,
	"moonlight_enabled": true,
	"moonlight_intensity": 0.4,
	"moonlight_color": Color(0.55, 0.70, 1.0),
	"accent1_enabled": false,
	"accent1_intensity": 0.6,
	"accent1_color": Color(1.0, 0.45, 0.75),
	"accent2_enabled": false,
	"accent2_intensity": 0.6,
	"accent2_color": Color(0.45, 0.85, 1.0),
	"pp_vignette_strength": 0.24,
	"pp_vignette_falloff": 1.6,
	"pp_bloom_threshold": 0.72,
	"pp_bloom_strength": 0.68,
	"outline_strength": 0.0,
	"dither_strength": 0.85,
	"crt_strength": 0.0,
	"dither_region_aware": true,
	"palette_bank_lock": true,
	"ambient_floor": 0.0,
	"biolum_multiplier": 1.0,
	"tod_use_overrides": false,
	"tod_dawn_color": Color(1.02, 0.88, 0.82),
	"tod_day_color": Color(1.00, 1.00, 1.00),
	"tod_dusk_color": Color(1.04, 0.82, 0.70),
	"tod_night_color": Color(0.38, 0.42, 0.52),
}


# Attach a small "↻" reset button to the right of an HSlider / CheckBox /
# ColorPickerButton, looking up its default from _LIGHT_DEFAULTS by key.
# Setting the control programmatically fires its change signal, so cfg
# and value label both update.
func _attach_reset(control: Control, cfg_key: String) -> void:
	if control == null:
		return
	var row: Node = control.get_parent()
	if row == null:
		return
	if not _LIGHT_DEFAULTS.has(cfg_key):
		return
	var default_v: Variant = _LIGHT_DEFAULTS[cfg_key]
	var btn := Button.new()
	btn.text = "↻"
	btn.tooltip_text = "Reset to default"
	btn.custom_minimum_size = Vector2(22, 0)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85, 0.7))
	btn.pressed.connect(func():
		if control is HSlider:
			(control as HSlider).value = float(default_v)
		elif control is CheckBox:
			(control as CheckBox).button_pressed = bool(default_v)
		elif control is ColorPickerButton:
			var cb: ColorPickerButton = control
			cb.color = default_v
			cb.color_changed.emit(default_v)
	)
	row.add_child(btn)


func _make_sun_direction_pad(parent: Node) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = "Sun direction"
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(120, 90)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.gui_input.connect(_on_sun_pad_input.bind(pad))
	pad.draw.connect(_on_sun_pad_draw.bind(pad))
	row.add_child(pad)
	return pad


func _on_sun_pad_input(ev: InputEvent, pad: Control) -> void:
	var drag: bool = false
	var pos: Vector2 = Vector2.ZERO
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			drag = true
			pos = mb.position
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			drag = true
			pos = mm.position
	if not drag:
		return
	var sz: Vector2 = pad.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	# Locals named `light_yaw_v` / `light_pitch_v` to avoid shadowing the
	# camera's `yaw` / `pitch` class members at line 180/181.
	var light_yaw_v: float = clampf(pos.x / sz.x, 0.0, 1.0)
	var light_pitch_v: float = clampf(pos.y / sz.y, 0.0, 1.0)
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.light_yaw = light_yaw_v
		cfg.light_pitch = light_pitch_v
	pad.queue_redraw()
	_light_mark_custom()


func _on_sun_pad_draw(pad: Control) -> void:
	var sz: Vector2 = pad.size
	# Background frame
	pad.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.10, 0.12, 0.18, 0.95), true)
	pad.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.35, 0.45, 0.6, 0.6), false)
	# Faint cross
	pad.draw_line(Vector2(sz.x * 0.5, 0), Vector2(sz.x * 0.5, sz.y),
		Color(0.4, 0.45, 0.55, 0.4))
	pad.draw_line(Vector2(0, sz.y * 0.5), Vector2(sz.x, sz.y * 0.5),
		Color(0.4, 0.45, 0.55, 0.4))
	# Marker for the current sun position
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	# See _on_sun_pad_input — these locals avoid shadowing camera yaw/pitch.
	var light_yaw_v: float = clampf(float(cfg.light_yaw), 0.0, 1.0)
	var light_pitch_v: float = clampf(float(cfg.light_pitch), 0.0, 1.0)
	var p: Vector2 = Vector2(light_yaw_v * sz.x, light_pitch_v * sz.y)
	pad.draw_circle(p, 5.0, Color(1.0, 0.85, 0.45, 0.9))
	pad.draw_circle(p, 2.0, Color(1.0, 1.0, 1.0, 1.0))


# Snap day_phase to one of the four anchors and refresh the slider/value
# label so the UI reflects the jump immediately.
func _jump_to_phase(p: float) -> void:
	if _sim != null:
		_sim.day_phase = fposmod(p, 1.0)
	if _light_day_phase_slider != null:
		_light_day_phase_slider.set_value_no_signal(p)
	if _light_day_phase_value != null:
		_light_day_phase_value.text = _day_phase_label(p)


# Helper for "label  [ColorPickerButton]" rows in the Light popup. Keeps the
# section markup consistent without dragging in a third PanelTheme variant.
func _make_color_row(parent: Node, label_text: String, on_changed: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	row.add_child(l)
	var btn := ColorPickerButton.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 26)
	btn.edit_alpha = false
	btn.color_changed.connect(on_changed)
	row.add_child(btn)
	return btn


func _add_light_section(parent: Node, label_text: String) -> void:
	parent.add_child(PanelTheme.make_spacer(4))
	var hdr := Label.new()
	hdr.text = label_text
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85, 0.85))
	parent.add_child(hdr)
	parent.add_child(PanelTheme.make_rule())


func _pull_light_panel_values() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	# Suppress the "user touched a control → switch to Custom" hook while we
	# rewrite UI state from cfg.
	_light_applying_preset = true
	if _light_preset_option != null:
		var slug: String = String(cfg.lighting_preset)
		for i in _light_preset_option.item_count:
			if String(_light_preset_option.get_item_metadata(i)) == slug:
				_light_preset_option.select(i)
				break
	if _light_master_check != null:
		_light_master_check.set_pressed_no_signal(bool(cfg.light_master_enabled))
	if _light_day_cycle_check != null:
		_light_day_cycle_check.set_pressed_no_signal(bool(cfg.day_cycle_enabled))
	if _light_day_phase_slider != null:
		var phase: float = float(_sim.day_phase) if _sim != null else 0.25
		_light_day_phase_slider.set_value_no_signal(phase)
		_light_day_phase_value.text = _day_phase_label(phase)
	if _light_day_length_slider != null:
		_light_day_length_slider.set_value_no_signal(float(cfg.day_length_s))
		_light_day_length_value.text = _fmt_duration(float(cfg.day_length_s))
	if _light_sunset_drama_slider != null:
		_light_sunset_drama_slider.set_value_no_signal(float(cfg.sunset_drama))
		_light_sunset_drama_value.text = "%.2f" % float(cfg.sunset_drama)
	if _light_global_intensity_slider != null:
		_light_global_intensity_slider.set_value_no_signal(float(cfg.global_intensity))
		_light_global_intensity_value.text = "%.2f" % float(cfg.global_intensity)
	if _light_global_warmth_slider != null:
		_light_global_warmth_slider.set_value_no_signal(float(cfg.global_warmth))
		_light_global_warmth_value.text = "%.2f" % float(cfg.global_warmth)
	if _light_tank_check != null:
		_light_tank_check.set_pressed_no_signal(bool(cfg.tank_lights_on))
	if _light_caustics_check != null:
		_light_caustics_check.set_pressed_no_signal(bool(cfg.light_caustics))
	if _light_fixture_intensity_slider != null:
		_light_fixture_intensity_slider.set_value_no_signal(float(cfg.tank_fixture_intensity))
		_light_fixture_intensity_value.text = "%.2f" % float(cfg.tank_fixture_intensity)
	if _light_fixture_color_picker != null:
		_light_fixture_color_picker.color = cfg.tank_fixture_color
	if _light_moon_check != null:
		_light_moon_check.set_pressed_no_signal(bool(cfg.moonlight_enabled))
	if _light_moon_intensity_slider != null:
		_light_moon_intensity_slider.set_value_no_signal(float(cfg.moonlight_intensity))
		_light_moon_intensity_value.text = "%.2f" % float(cfg.moonlight_intensity)
	if _light_moon_color_picker != null:
		_light_moon_color_picker.color = cfg.moonlight_color
	if _light_accent1_check != null:
		_light_accent1_check.set_pressed_no_signal(bool(cfg.accent1_enabled))
	if _light_accent1_intensity_slider != null:
		_light_accent1_intensity_slider.set_value_no_signal(float(cfg.accent1_intensity))
		_light_accent1_intensity_value.text = "%.2f" % float(cfg.accent1_intensity)
	if _light_accent1_color_picker != null:
		_light_accent1_color_picker.color = cfg.accent1_color
	if _light_accent2_check != null:
		_light_accent2_check.set_pressed_no_signal(bool(cfg.accent2_enabled))
	if _light_accent2_intensity_slider != null:
		_light_accent2_intensity_slider.set_value_no_signal(float(cfg.accent2_intensity))
		_light_accent2_intensity_value.text = "%.2f" % float(cfg.accent2_intensity)
	if _light_accent2_color_picker != null:
		_light_accent2_color_picker.color = cfg.accent2_color
	if _light_pp_vignette_slider != null:
		_light_pp_vignette_slider.set_value_no_signal(float(cfg.pp_vignette_strength))
		_light_pp_vignette_value.text = "%.2f" % float(cfg.pp_vignette_strength)
	if _light_pp_bloom_threshold_slider != null:
		_light_pp_bloom_threshold_slider.set_value_no_signal(float(cfg.pp_bloom_threshold))
		_light_pp_bloom_threshold_value.text = "%.2f" % float(cfg.pp_bloom_threshold)
	if _light_pp_bloom_strength_slider != null:
		_light_pp_bloom_strength_slider.set_value_no_signal(float(cfg.pp_bloom_strength))
		_light_pp_bloom_strength_value.text = "%.2f" % float(cfg.pp_bloom_strength)
	if _light_pp_outline_slider != null:
		_light_pp_outline_slider.set_value_no_signal(float(cfg.outline_strength))
		_light_pp_outline_value.text = "%.2f" % float(cfg.outline_strength)
	if _light_pp_dither_slider != null:
		_light_pp_dither_slider.set_value_no_signal(float(cfg.dither_strength))
		_light_pp_dither_value.text = "%.2f" % float(cfg.dither_strength)
	if _light_pp_crt_slider != null:
		_light_pp_crt_slider.set_value_no_signal(float(cfg.crt_strength))
		_light_pp_crt_value.text = "%.2f" % float(cfg.crt_strength)
	if _light_pp_vignette_falloff_slider != null:
		_light_pp_vignette_falloff_slider.set_value_no_signal(float(cfg.pp_vignette_falloff))
		_light_pp_vignette_falloff_value.text = "%.2f" % float(cfg.pp_vignette_falloff)
	if _light_pp_region_dither_check != null:
		_light_pp_region_dither_check.set_pressed_no_signal(bool(cfg.dither_region_aware))
	if _light_pp_bank_lock_check != null:
		_light_pp_bank_lock_check.set_pressed_no_signal(bool(cfg.palette_bank_lock))
	if _light_ambient_floor_slider != null:
		_light_ambient_floor_slider.set_value_no_signal(float(cfg.ambient_floor))
		_light_ambient_floor_value.text = "%.2f" % float(cfg.ambient_floor)
	if _light_biolum_slider != null:
		_light_biolum_slider.set_value_no_signal(float(cfg.biolum_multiplier))
		_light_biolum_value.text = "%.2f" % float(cfg.biolum_multiplier)
	if _light_caustic_strength_slider != null:
		_light_caustic_strength_slider.set_value_no_signal(float(cfg.caustic_intensity_user))
		_light_caustic_strength_value.text = "%.2f" % float(cfg.caustic_intensity_user)
	if _light_tod_override_check != null:
		_light_tod_override_check.set_pressed_no_signal(bool(cfg.tod_use_overrides))
	if _light_tod_dawn_picker != null:
		_light_tod_dawn_picker.color = cfg.tod_dawn_color
	if _light_tod_day_picker != null:
		_light_tod_day_picker.color = cfg.tod_day_color
	if _light_tod_dusk_picker != null:
		_light_tod_dusk_picker.color = cfg.tod_dusk_color
	if _light_tod_night_picker != null:
		_light_tod_night_picker.color = cfg.tod_night_color
	if _light_sun_pad != null:
		_light_sun_pad.queue_redraw()
	_light_applying_preset = false


# Format a seconds count as "Xs" / "Xm" / "Xh" for the day-length slider value column.
func _fmt_duration(s: float) -> String:
	if s < 90.0:
		return "%ds" % int(s)
	if s < 3600.0:
		return "%dm" % int(round(s / 60.0))
	return "%.1fh" % (s / 3600.0)


# "0.62  dusk" — gives the slider both a numeric and a phase-word readout.
func _day_phase_label(p: float) -> String:
	return "%.2f  %s" % [p, _day_label(p)]


# While the Light panel is open and the cycle is running, mirror sim.day_phase
# into the slider so the user sees the sun actually moving. Skip when the
# user is grabbing the slider, otherwise the live update fights their drag.
func _refresh_light_panel_live() -> void:
	if _light_day_phase_slider == null or _sim == null:
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.day_cycle_enabled):
		return
	if _light_day_phase_slider.has_focus():
		return
	var phase: float = float(_sim.day_phase)
	_light_day_phase_slider.set_value_no_signal(phase)
	if _light_day_phase_value != null:
		_light_day_phase_value.text = _day_phase_label(phase)


func _position_light_panel() -> void:
	if _light_panel == null:
		return
	# Float the panel just left of the rail. Rather than fight the layout
	# after the fact, size the ScrollContainer to ~75% of the viewport
	# height *before* reset_size() so the panel grows to a known target
	# height and the scroll body always has a real clip rect.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var scroll: Control = _light_panel.get_meta("scroll_container", null) as Control
	if scroll != null:
		var target_h: float = clampf(vp.y * 0.75, 360.0, 760.0)
		scroll.custom_minimum_size = Vector2(0, target_h)
	_light_panel.size = Vector2.ZERO  # let it shrink to content
	_light_panel.reset_size()
	var sz: Vector2 = _light_panel.size
	if sz.x < _light_panel.custom_minimum_size.x:
		sz.x = _light_panel.custom_minimum_size.x
	var btn_rect: Rect2 = Rect2()
	if _light_btn != null:
		btn_rect = _light_btn.get_global_rect()
	var x: float
	var y: float
	if _rail_dock == "bottom":
		# Bottom-docked rail: float above the button.
		x = clampf(btn_rect.position.x + btn_rect.size.x * 0.5 - sz.x * 0.5,
			8.0, vp.x - sz.x - 8.0)
		y = btn_rect.position.y - sz.y - 8.0
		if y < 8.0:
			y = 8.0
	else:
		# Right-docked rail: float to the left of the button.
		x = btn_rect.position.x - sz.x - 8.0
		if x < 8.0:
			x = 8.0
		y = clampf(btn_rect.position.y, 8.0, vp.y - sz.y - 8.0)
	_light_panel.position = Vector2(x, y)


func _sync_light_btn() -> void:
	if _light_btn == null:
		return
	var open: bool = _light_panel != null and _light_panel.visible
	PanelTheme.style_rail_button(_light_btn, open)


# Any user-driven control change snaps the preset selector back to "Custom"
# so the dropdown doesn't lie about which preset is currently active. The
# _light_applying_preset guard skips this when we're the ones writing.
func _light_mark_custom() -> void:
	if _light_applying_preset:
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.lighting_preset = "custom"
	if _light_preset_option != null and _light_preset_option.item_count > 0:
		_light_preset_option.select(0)  # index 0 is Custom


func _on_light_tank_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tank_lights_on = v
	_light_mark_custom()


func _on_light_caustics_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.light_caustics = v
	_light_mark_custom()


func _on_global_intensity_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.global_intensity = v
	if _light_global_intensity_value != null:
		_light_global_intensity_value.text = "%.2f" % v
	_light_mark_custom()


func _on_global_warmth_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.global_warmth = v
	if _light_global_warmth_value != null:
		_light_global_warmth_value.text = "%.2f" % v
	_light_mark_custom()


func _on_fixture_intensity_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tank_fixture_intensity = v
	if _light_fixture_intensity_value != null:
		_light_fixture_intensity_value.text = "%.2f" % v
	_light_mark_custom()


func _on_fixture_color_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tank_fixture_color = c
	_light_mark_custom()


func _on_light_master_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.light_master_enabled = v
	_light_mark_custom()


func _on_day_cycle_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.day_cycle_enabled = v
	_light_mark_custom()


func _on_day_phase_changed(v: float) -> void:
	if _sim != null:
		_sim.day_phase = fposmod(v, 1.0)
	if _light_day_phase_value != null:
		_light_day_phase_value.text = _day_phase_label(v)
	# Day phase is a runtime value, not part of the preset definition, so
	# don't snap to Custom here — the user wants to scrub freely.


func _on_day_length_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.day_length_s = v
	if _light_day_length_value != null:
		_light_day_length_value.text = _fmt_duration(v)
	_light_mark_custom()


func _on_sunset_drama_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.sunset_drama = v
	if _light_sunset_drama_value != null:
		_light_sunset_drama_value.text = "%.2f" % v
	_light_mark_custom()


func _on_moon_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.moonlight_enabled = v
	_light_mark_custom()


func _on_moon_intensity_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.moonlight_intensity = v
	if _light_moon_intensity_value != null:
		_light_moon_intensity_value.text = "%.2f" % v
	_light_mark_custom()


func _on_moon_color_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.moonlight_color = c
	_light_mark_custom()


func _on_accent1_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent1_enabled = v
	_light_mark_custom()


func _on_accent1_intensity_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent1_intensity = v
	if _light_accent1_intensity_value != null:
		_light_accent1_intensity_value.text = "%.2f" % v
	_light_mark_custom()


func _on_accent1_color_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent1_color = c
	_light_mark_custom()


func _on_accent2_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent2_enabled = v
	_light_mark_custom()


func _on_accent2_intensity_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent2_intensity = v
	if _light_accent2_intensity_value != null:
		_light_accent2_intensity_value.text = "%.2f" % v
	_light_mark_custom()


func _on_accent2_color_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.accent2_color = c
	_light_mark_custom()


func _on_pp_vignette_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.pp_vignette_strength = v
	if _light_pp_vignette_value != null:
		_light_pp_vignette_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_bloom_threshold_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.pp_bloom_threshold = v
	if _light_pp_bloom_threshold_value != null:
		_light_pp_bloom_threshold_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_bloom_strength_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.pp_bloom_strength = v
	if _light_pp_bloom_strength_value != null:
		_light_pp_bloom_strength_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_outline_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.outline_strength = v
	if _light_pp_outline_value != null:
		_light_pp_outline_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_dither_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.dither_strength = v
	if _light_pp_dither_value != null:
		_light_pp_dither_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_crt_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.crt_strength = v
	if _light_pp_crt_value != null:
		_light_pp_crt_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_vignette_falloff_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.pp_vignette_falloff = v
	if _light_pp_vignette_falloff_value != null:
		_light_pp_vignette_falloff_value.text = "%.2f" % v
	_light_mark_custom()


func _on_pp_region_dither_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.dither_region_aware = v
	_light_mark_custom()


func _on_pp_bank_lock_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.palette_bank_lock = v
	_light_mark_custom()


func _on_ambient_floor_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.ambient_floor = v
	if _light_ambient_floor_value != null:
		_light_ambient_floor_value.text = "%.2f" % v
	_light_mark_custom()


func _on_biolum_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.biolum_multiplier = v
	if _light_biolum_value != null:
		_light_biolum_value.text = "%.2f" % v
	_light_mark_custom()


func _on_caustic_strength_changed(v: float) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.caustic_intensity_user = v
	if _light_caustic_strength_value != null:
		_light_caustic_strength_value.text = "%.2f" % v
	_light_mark_custom()


func _on_tod_override_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tod_use_overrides = v
	_light_mark_custom()


func _on_tod_dawn_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tod_dawn_color = c
	_light_mark_custom()


func _on_tod_day_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tod_day_color = c
	_light_mark_custom()


func _on_tod_dusk_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tod_dusk_color = c
	_light_mark_custom()


func _on_tod_night_changed(c: Color) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.tod_night_color = c
	_light_mark_custom()


# Randomize button: picks a random non-custom preset, jitters its values
# ±15% to keep the result varied even when the user mashes the button.
func _on_lighting_randomize_pressed() -> void:
	var slugs: Array = TankConfig.LIGHTING_PRESETS.keys()
	if slugs.is_empty():
		return
	var pick: String = String(slugs[randi() % slugs.size()])
	# Apply through the same path as the dropdown so UI stays in sync, then
	# nudge a few key values for variety. Marking custom afterwards so the
	# dropdown reflects the manual tweak.
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	_light_applying_preset = true
	if cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(pick)
	# Jitter a handful of numeric fields ±15% — bounded into legal ranges.
	cfg.global_intensity = clampf(float(cfg.global_intensity) * randf_range(0.85, 1.15), 0.0, 1.0)
	cfg.global_warmth = clampf(float(cfg.global_warmth) + randf_range(-0.12, 0.12), 0.0, 1.0)
	cfg.tank_fixture_intensity = clampf(
		float(cfg.tank_fixture_intensity) * randf_range(0.85, 1.15), 0.0, 1.0)
	cfg.sunset_drama = clampf(
		float(cfg.sunset_drama) * randf_range(0.85, 1.20), 0.0, 2.5)
	cfg.lighting_preset = "custom"  # randomized → no longer pure preset
	_pull_light_panel_values()
	_light_applying_preset = false


# Preset selector: writes the preset's values into TankConfig, then pulls
# them back into the UI so every slider/picker updates visually too. The
# _light_applying_preset guard prevents the slider change events from
# snapping the dropdown back to "Custom" mid-apply.
func _on_lighting_preset_selected(idx: int) -> void:
	if _light_preset_option == null:
		return
	var slug: String = String(_light_preset_option.get_item_metadata(idx))
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	_light_applying_preset = true
	if cfg.has_method("apply_lighting_preset"):
		cfg.apply_lighting_preset(slug)
	else:
		cfg.lighting_preset = slug
	_pull_light_panel_values()
	_light_applying_preset = false


# ---- Focus / immersive mode ----
# Hides top HUD, bottom hints, mobile controls, and open panels so the tank
# fills the screen. Press H or the ⛶ button to toggle; a small pill restores UI.
func _add_immersive_toggle_button() -> void:
	if menu_button == null:
		return
	var hbox: Node = menu_button.get_parent()
	if hbox == null:
		return
	var btn := Button.new()
	btn.text = UiIcons.rail_label("immersive", _is_mobile())
	btn.tooltip_text = UiIcons.rail_tooltip("immersive")
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = menu_button.custom_minimum_size
	btn.pressed.connect(_toggle_immersive_mode)
	hbox.add_child(btn)
	hbox.move_child(btn, menu_button.get_index() + 1)


func _toggle_immersive_mode() -> void:
	_immersive_mode = not _immersive_mode
	_apply_immersive_mode()


func _apply_immersive_mode() -> void:
	if top_hud != null:
		top_hud.visible = not _immersive_mode
	if right_rail != null:
		right_rail.visible = not _immersive_mode
	if controls_hint != null:
		controls_hint.visible = not _immersive_mode
	if _mobile_hud != null and _mobile_hud.visible:
		_mobile_hud.visible = not _immersive_mode
	if aquascape_palette != null and _immersive_mode:
		aquascape_palette.visible = false
	if portal_container != null and _immersive_mode:
		portal_container.visible = false
	if _immersive_mode:
		_close_panels_for_immersive()
	_ensure_immersive_exit_button()
	if _immersive_exit_btn != null:
		_immersive_exit_btn.visible = _immersive_mode
	if not _immersive_mode and _portal_open and portal_container != null:
		portal_container.visible = true


func _close_panels_for_immersive() -> void:
	for panel in [
		settings_panel, render_panel, sound_panel, fish_store_panel,
		library_panel, creature_creator_panel, _light_panel,
	]:
		if panel != null and panel.visible:
			panel.visible = false
	if _light_btn != null:
		_sync_light_btn()


func _ensure_immersive_exit_button() -> void:
	if _immersive_exit_btn != null:
		return
	_immersive_exit_btn = Button.new()
	_immersive_exit_btn.name = "ImmersiveExit"
	_immersive_exit_btn.text = "Show UI  (H)"
	_immersive_exit_btn.tooltip_text = "Exit focus mode"
	_immersive_exit_btn.anchor_left = 0.0
	_immersive_exit_btn.anchor_top = 0.0
	_immersive_exit_btn.anchor_right = 0.0
	_immersive_exit_btn.anchor_bottom = 0.0
	_immersive_exit_btn.offset_left = 12.0
	_immersive_exit_btn.offset_top = 12.0
	_immersive_exit_btn.custom_minimum_size = Vector2(108, 36)
	_immersive_exit_btn.modulate = Color(1, 1, 1, 0.82)
	_immersive_exit_btn.visible = false
	_immersive_exit_btn.pressed.connect(_toggle_immersive_mode)
	add_child(_immersive_exit_btn)


# ---- Back-to-menu navigation ----
# The Menu button (top-left of main.tscn) saves the active tank and
# transitions back to the tank picker. Also bound to Android's back button
# via NOTIFICATION_WM_GO_BACK_REQUEST in _notification.
func _on_back_to_menu() -> void:
	if _save_restored:
		await _save_active_tank_with_thumbnail()
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
	SaveManager.try_load(self, _sim, world, _aquascape, &"_save_restored")


# Snapshot the world to disk. Called by:
#   - the 5-minute periodic autosave
#   - app focus-out (NOTIFICATION_APPLICATION_FOCUS_OUT)
#   - the back-to-menu button
#   - clean app quit
# Skip if we're in the middle of aquascape mode (time_scale=0 from that path
# would freeze the session at "paused" forever).
func save_active_tank(skip_thumbnail: bool = false) -> void:
	_save_pending_time_scale = SaveManager.save_active(
		self, _sim, world, _aquascape, _save_pending_time_scale, skip_thumbnail)


# Write state + block until the menu-card thumbnail is on disk.
func _save_active_tank_with_thumbnail() -> void:
	save_active_tank(true)
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	await _capture_thumbnail_to_path(saves.thumbnail_path(int(saves.active_slot)))


func _save_thumbnail(path: String) -> void:
	if sub_viewport == null:
		return
	_request_viewport_image(_finish_save_thumbnail.bind(path))


func _capture_thumbnail_to_path(path: String) -> void:
	if sub_viewport == null or not is_instance_valid(sub_viewport):
		return
	# Wait for the SubViewport to finish presenting before GPU readback.
	await RenderingServer.frame_post_draw
	var img: Image = null
	var tex: ViewportTexture = sub_viewport.get_texture()
	if tex != null:
		img = tex.get_image()
	if img != null and img.get_width() > 0 and img.get_height() > 0:
		_finish_save_thumbnail(img, path)
	else:
		push_warning("[walstad_loom] thumbnail capture failed for %s" % path)


func _finish_save_thumbnail(img: Image, path: String) -> void:
	var dir: String = path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var w: int = 480
	var h: int = int(round(float(img.get_height()) * (float(w) / float(img.get_width()))))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var err: int = img.save_png(path)
	if err != OK:
		push_warning("[walstad_loom] thumbnail save failed at %s: err %d" % [path, err])


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
					if d.has("terrain") and world != null \
							and world.has_method("terrain_apply_save_dict"):
						world.terrain_apply_save_dict(d["terrain"])
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
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		# APPLICATION_PAUSED is the Android lifecycle event that fires when
		# the activity is moved to onPause (full backgrounding). FOCUS_OUT
		# fires on overlays / lock screen too. We treat all three the same:
		# stop ticking the sim so the device can sleep its CPU/GPU.
		_on_focus_out()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_IN \
			or what == NOTIFICATION_APPLICATION_RESUMED:
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
	# RAM-aware downshift: a phone with a 1440p screen and 3GB of RAM is a
	# budget device that will choke if we render at the "high" tier just
	# because the screen is big. Read the OS memory hint where available
	# and force a low tier when total RAM is under ~3.5GB. Godot exposes
	# get_memory_info() with a "free"/"available"/"total" map on most
	# desktops, but on Android we fall back to a best-effort static usage
	# check and assume conservative tier when info isn't available.
	var ram_gb: float = 0.0
	if OS.has_method("get_memory_info"):
		var info: Dictionary = OS.get_memory_info()
		var total: int = int(info.get("physical", 0))
		if total > 0:
			ram_gb = float(total) / (1024.0 * 1024.0 * 1024.0)
	var low_ram: bool = ram_gb > 0.0 and ram_gb < 3.5
	if low_ram:
		# Force the low tier regardless of screen size. Tablet-size screen
		# with low RAM (common on budget Android tablets) still wants the
		# small render target.
		cfg.device_tier = "low"
		cfg.render_width = 256
		cfg.render_height = 144
	elif short_side >= 1500:
		cfg.device_tier = "high"
		# Bump render res so the tank fills the bigger tablet panel with
		# more detail. Stays well within typical mobile GPU budgets.
		cfg.render_width = 768
		cfg.render_height = 432
	elif short_side >= 900:
		cfg.device_tier = "mid"
		# Phones with 1080p-ish short sides (Pixel 10 is 1080) — the
		# palette-quantize shader runs at OUTPUT resolution, so any extra
		# source pixels above 384×216 just pay for themselves twice (once
		# to render, again to quantize+dither at output res). 384×216
		# upscales to 1080 at 5x integer, which the palette shader handles
		# cleanly. Was 512×288 — measurably hot on the Pixel 10.
		cfg.render_width = 384
		cfg.render_height = 216
	else:
		cfg.device_tier = "low"
		# Tiny / old phones: drop one notch so we stay smooth.
		cfg.render_width = 384
		cfg.render_height = 216
	# On mobile, enable adaptive quality on first launch with a 28fps floor.
	# Pixel-class phones thermal-throttle the GPU during long sessions; the
	# adaptive_quality tick will step the SubViewport down a tier when
	# sustained fps drops below the floor, giving the chip room to cool.
	# Steps back up when there's headroom, so the user gets the best res
	# their thermal envelope can hold instead of a fixed-and-hot ceiling.
	if not cfg.adaptive_quality:
		cfg.adaptive_quality = true
		cfg.adaptive_quality_target_fps = 28
	cfg.save_to_disk()
	print_verbose("[walstad_loom] device_tier picked: %s (short side %d px, %.1f GB RAM)" \
		% [cfg.device_tier, short_side, ram_gb])


# ---- FPS cap (battery saver) ----
func _apply_fps_cap() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	# First-mobile-launch default: if no cap is set, lock to 30 — sim ticks
	# at 10Hz independent of frame rate so 30fps is plenty smooth for the
	# tank's gentle motion, and it ~halves GPU power vs 60. User can lift
	# the cap in settings (Advanced → Performance).
	if _is_mobile() and int(cfg.fps_cap) == 0:
		cfg.fps_cap = 30
		cfg.save_to_disk()
	# Battery saver forces 30 regardless of what fps_cap is set to.
	if bool(cfg.get("battery_saver")) and int(cfg.fps_cap) != 30:
		cfg.fps_cap = 30
		cfg.save_to_disk()
	if int(cfg.fps_cap) > 0:
		Engine.max_fps = int(cfg.fps_cap)
	# Apply the shader-cost knobs for battery saver. The palette-quantize
	# shader on the Display TextureRect runs at OUTPUT resolution (~2.6M px
	# on a Pixel 10), so each per-pixel branch we kill is real GPU work
	# saved. Battery saver = no bloom post-process, no region-aware dither
	# branch, no palette bank-lock second-search loop, and a dimmer dither.
	# Visually quieter and noticeably cooler.
	_apply_battery_saver_visuals()


# Toggle the heavy parts of the palette / post-process pipeline based on
# TankConfig.battery_saver. Called from _apply_fps_cap on startup and from
# the settings toggle whenever the user flips it. Reads the current display
# ShaderMaterial and writes uniforms; falls back to a no-op if the material
# isn't ready yet (e.g. called before _apply_render_config in _ready).
func _apply_battery_saver_visuals() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or display == null:
		return
	var saver: bool = bool(cfg.get("battery_saver"))
	if not (display.material is ShaderMaterial):
		return
	var sm: ShaderMaterial = display.material
	if saver:
		sm.set_shader_parameter("bloom_strength", 0.0)
		sm.set_shader_parameter("region_aware_dither", 0.0)
		sm.set_shader_parameter("palette_bank_lock", 0.0)
		sm.set_shader_parameter("outline_strength", 0.0)
		sm.set_shader_parameter("crt_strength", 0.0)
		sm.set_shader_parameter("dither_strength", 0.4)
	else:
		# Restore the user's last-saved values (the Light panel writes these
		# to TankConfig). Reading from cfg keeps the user's preferences
		# intact across saver toggles.
		sm.set_shader_parameter("bloom_strength", float(cfg.get("pp_bloom_strength")))
		sm.set_shader_parameter("region_aware_dither",
			1.0 if cfg.get("dither_region_aware") else 0.0)
		sm.set_shader_parameter("palette_bank_lock",
			1.0 if cfg.get("palette_bank_lock") else 0.0)
		sm.set_shader_parameter("outline_strength", float(cfg.get("outline_strength")))
		sm.set_shader_parameter("crt_strength", float(cfg.get("crt_strength")))
		sm.set_shader_parameter("dither_strength", float(cfg.get("dither_strength")))


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
	_push_notification("welcome_back", NOTIF_SEVERITY_IMPORTANT, "Welcome back", msg, true)


func _on_species_discovered(entry: Dictionary) -> void:
	_show_discovery_toast(entry)


func _show_discovery_toast(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	# Legacy discovery-toast state (pre-notification-center). We keep these
	# fields nulled so old hot-reload references stay valid without rendering
	# duplicate UI.
	if _discovery_toast_tween != null and _discovery_toast_tween.is_valid():
		_discovery_toast_tween.kill()
	_discovery_toast_tween = null
	_discovery_toast = null
	var otype: String = String(entry.get("organism_type", "fish"))
	var icon: String = UiIcons.fauna_label(otype)
	var display_name: String = String(entry.get("display_name", "?"))
	var gen: int = int(entry.get("generation", 0))
	var src: String = String(entry.get("source", ""))
	var src_hint: String = ""
	if src == "founder":
		src_hint = " · founder"
	elif src == "store":
		src_hint = " · store"
	_push_notification(
		"discovery",
		NOTIF_SEVERITY_INFO,
		"New discovery",
		"%s %s (gen %d)%s" % [icon, display_name, gen, src_hint],
		false
	)


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


func _toggle_cheat_sheet() -> void:
	if _cheat_sheet != null and is_instance_valid(_cheat_sheet):
		_cheat_sheet.queue_free()
		_cheat_sheet = null
		return
	_cheat_sheet = Control.new()
	_cheat_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cheat_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_cheat_sheet.z_index = 280
	add_child(_cheat_sheet)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_toggle_cheat_sheet())
	_cheat_sheet.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_top = -220
	panel.offset_right = 240
	panel.offset_bottom = 220
	PanelTheme.apply_panel_chrome(panel)
	_cheat_sheet.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(PanelTheme.make_title("Controls"))
	vb.add_child(PanelTheme.make_rule())
	var lines: PackedStringArray = PackedStringArray([
		"O — Settings", "R — Rendering", "M — Sound Studio", "Shift+M — Motion debug",
		"C — Follow portal", "B — Aquascape", "H — Focus mode", "P — Pause",
		"1–8 — Sim speed", "T — Timelapse", "F12 — Photo", "? / Shift+/ — This help",
		"Click water — feed fish", "9 / 0 — cycle food type",
		"Shift+click water — tap glass (ripples + fish react)",
		"Click stat chips — history / water / mood details",
		"Right rail — Create · World · Look · System · Alerts",
	])
	for line in lines:
		var lab := Label.new()
		lab.text = line
		lab.add_theme_font_size_override("font_size", 13)
		lab.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
		vb.add_child(lab)
	var close := PanelTheme.make_primary_button("Close")
	close.pressed.connect(_toggle_cheat_sheet)
	vb.add_child(close)


func _maybe_show_coachmarks() -> void:
	if bool(_global_pref("coachmarks_seen", false)):
		return
	if walkthrough_overlay != null and walkthrough_overlay.visible:
		return
	_show_coachmark_step(0)


func _show_coachmark_step(step: int) -> void:
	if _coachmark_overlay != null and is_instance_valid(_coachmark_overlay):
		_coachmark_overlay.queue_free()
		_coachmark_overlay = null
	var hints: Array[String] = [
		"Use the right rail: Create · World · Look · System · Alerts",
		"Tap the stat chips at the top for water chemistry and history",
		"Click water to feed fish (9/0 to change food). Drag to orbit.",
	]
	if step >= hints.size():
		_set_global_pref("coachmarks_seen", true)
		return
	_coachmark_step = step
	_coachmark_overlay = Control.new()
	_coachmark_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_coachmark_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_coachmark_overlay.z_index = 290
	add_child(_coachmark_overlay)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 1.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -260
	panel.offset_top = -120
	panel.offset_right = 260
	panel.offset_bottom = -24
	PanelTheme.apply_panel_chrome(panel)
	_coachmark_overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Tip %d of %d" % [step + 1, hints.size()]
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", PanelTheme.SECTION_FG)
	vb.add_child(title)
	var body := Label.new()
	body.text = hints[step]
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var skip := PanelTheme.make_secondary_button("Skip")
	skip.pressed.connect(func():
		_set_global_pref("coachmarks_seen", true)
		if is_instance_valid(_coachmark_overlay):
			_coachmark_overlay.queue_free()
		_coachmark_overlay = null)
	row.add_child(skip)
	var next := PanelTheme.make_primary_button("Next" if step + 1 < hints.size() else "Done")
	next.pressed.connect(func():
		if is_instance_valid(_coachmark_overlay):
			_coachmark_overlay.queue_free()
		_coachmark_overlay = null
		_show_coachmark_step(step + 1))
	row.add_child(next)


# ---- Tutorial overlay ----
# Built on first launch (desktop + mobile). A semi-transparent
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
	if sound_panel != null and sound_panel.visible:
		sound_panel.visible = false
		sound_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		_set_global_pref("tutorial_seen", true)
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
		dismissed = true
	if _ui_panels.is_modal_open():
		_ui_panels.close_modal()
		_sync_rail_toggles()
		dismissed = true
	_dismiss_radial_menu()
	return dismissed


func _maybe_show_tutorial() -> void:
	if bool(_global_pref("tutorial_seen", false)):
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and cfg.tutorial_seen:
		_set_global_pref("tutorial_seen", true)
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
			_set_global_pref("tutorial_seen", true)
			overlay.queue_free()
			_tutorial_overlay = null
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_set_global_pref("tutorial_seen", true)
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
	# Touch-grammar vs keyboard/mouse-grammar hints. On mobile the user never
	# touches a keyboard, so any mention of "press 9/0" or "press ?" reads as
	# unfinished. Build the bullet list for the actual input modality.
	var hints: Array[String] = []
	if _is_mobile():
		hints = [
			"• Drag to orbit the tank",
			"• Pinch to zoom · two-finger drag to pan",
			"• Two-finger twist to rotate the view",
			"• Tap a creature to follow it",
			"• Tap empty water to drop food",
			"• Double-tap anywhere to reset the camera",
			"• Long-press in build mode for the tool menu",
			"• Swipe from the right edge to open settings",
			"• Stat chips at top — tap for water & history",
		]
	else:
		hints = [
			"• Drag to orbit the tank",
			"• Click water to feed (9/0 cycles food type)",
			"• Tap a creature to follow it",
			"• Stat chips at top — tap for water & history",
			"• Right rail — Create · World · Look · System · Alerts",
			"• Press ? for keyboard shortcuts",
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
		_set_global_pref("tutorial_seen", true)
		_haptic(12)
		if is_instance_valid(overlay):
			overlay.queue_free()
		_tutorial_overlay = null
		call_deferred("_maybe_show_coachmarks"))
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
		{"key": "aquasoil", "label": "soil",   "angle": -PI / 2, "color": Color8(120, 85, 56)},
		{"key": "sand",     "label": "sand",   "angle": 0.0,     "color": Color8(225, 215, 185)},
		{"key": "gravel",   "label": "gravel", "angle": PI / 2,  "color": Color8(125, 125, 135)},
		{"key": "dig",      "label": "dig",    "angle": PI,      "color": Color8(220, 90, 90)},
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
			_aquascape.set_tool(key)
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
	_push_notification("system", NOTIF_SEVERITY_INFO, "Photo saved", file_name, false)
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
