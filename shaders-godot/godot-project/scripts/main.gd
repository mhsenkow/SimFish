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
const MakeItThere = preload("res://scripts/make_it_there.gd")
const GuardianJournal = preload("res://scripts/guardian_journal.gd")
const GuardianMindOnboarding = preload("res://scripts/guardian_mind_onboarding.gd")
const MindNarrator = preload("res://scripts/mind_narrator.gd")
const MindDebug = preload("res://scripts/mind_debug.gd")
const MindScheduler = preload("res://scripts/mind_scheduler.gd")
const KeeperInput = preload("res://scripts/keeper_input.gd")
const _DartTrailPoolScript = preload("res://scripts/dart_trail_pool.gd")
const KeeperCare = preload("res://scripts/keeper_care.gd")
const MindConversation = preload("res://scripts/mind_conversation.gd")
const UiPanelManagerScript = preload("res://scripts/ui_panel_manager.gd")
const OnboardingRuntimeScript = preload("res://scripts/onboarding_runtime.gd")
const _QuantizeShader = preload("res://shaders/palette_quantize.gdshader")
const _QuantizePotatoShader = preload("res://shaders/palette_quantize_potato.gdshader")

const GLOBAL_PREFS_PATH := "user://global_prefs.cfg"
const VOICE_BODY_FIRST_DELAY_S: float = 0.75
const VOICE_TEMPLATE_DELAY_S: float = 0.35


@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display
# Internal-res post chain: 3D SubViewport → palette quantize at render size →
# Display upscales the post output (cheap nearest blit, no fullscreen shader).
var _post_viewport: SubViewport = null
var _post_display: TextureRect = null
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
@onready var controls_hint: Label = $FooterBar/Margin/HBox/ControlsHint
@onready var footer_bar: PanelContainer = $FooterBar
@onready var footer_hint_spacer: Control = $FooterBar/Margin/HBox/Spacer

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
var _light_heater_check: CheckBox = null
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
const SCREENSAVER_DIM_MODULATE: Color = Color(1, 1, 1, 0.08)
const NIGHT_WATCHSCREENSAVER_S: float = 120.0
var _moonlight_suggested: bool = false
const HUD_LIT_MODULATE: Color = Color(1, 1, 1, 1)

@onready var portal_container: Control = $PortalContainer
@onready var portal_display: TextureRect = $PortalContainer/PortalDisplay
@onready var portal_hint: Label = $PortalContainer/PortalHint

# Follow system. ONE creature is followed at a time; _follow_mode decides how
# it's presented. PIP = circular magnifier overlay (the main camera stays free);
# CINEMATIC = the main camera glides to track it. This replaces the old split
# between _portal_open/_portal_target (PiP) and a separate _follow_target.
enum FollowMode { OFF, PIP, CINEMATIC }
var _follow_mode: int = FollowMode.OFF
# Scope that next/prev (← / →, portal arrows, panel) walks through.
enum CycleScope { ALL, FAVORITES, SPECIES }
var _cycle_scope: int = CycleScope.ALL
# Emitted whenever the followed creature changes (null when follow stops) so the
# Residents panel can sync its "now following" header and row highlight.
signal follow_target_changed(creature: Node)
var _portal_mat: ShaderMaterial = null
const PORTAL_ZOOM: float = 3.5
# Live magnifier zoom (scroll over the porthole to adjust); defaults to PORTAL_ZOOM.
var _portal_zoom: float = PORTAL_ZOOM
const PORTAL_ZOOM_MIN: float = 1.5
const PORTAL_ZOOM_MAX: float = 7.0

# PiP info panel elements
var _portal_info_panel: MarginContainer = null
var _portal_name_lbl: Label = null
var _portal_lineage_lbl: Label = null
var _portal_relation_lbl: Label = null
var _portal_stats_lbl: Label = null
# Portal overlay controls (cycle / favorite / cinematic-toggle).
var _portal_prev_btn: Button = null
var _portal_next_btn: Button = null
var _portal_fav_btn: Button = null
var _portal_mode_btn: Button = null
var _portal_layout_btn: Button = null
# Glass-card redesign: one frosted-glass card holds the porthole + info, with two
# switchable arrangements (porthole above vs beside the info).
enum PortalLayout { ABOVE, BESIDE }
var _portal_layout: int = PortalLayout.ABOVE
var _portal_glass_bg: ColorRect = null
var _portal_glass_mat: ShaderMaterial = null
var _portal_info_vbox: VBoxContainer = null
var _portal_ctrls: HBoxContainer = null
var _portal_scaffold: Control = null
# Rename dialog (click the portal name to rename the followed creature).
var _rename_dialog: AcceptDialog = null
var _rename_edit: LineEdit = null
var _rename_target: Node = null
# In-tank favorite halos: instance_id -> Label3D star parented to the creature.
var _fav_halos: Dictionary = {}
# In-tank thought marker on the followed fish (symbol only — text is screen UI).
var _follow_thought_symbol: Label3D = null
var _follow_thought_strip: PanelContainer = null
var _follow_thought_strip_name: Label = null
var _follow_thought_strip_body: Label = null
var _follow_thought_tw_full: String = ""
var _follow_thought_tw_idx: int = 0
var _follow_thought_tw_gen: int = 0
var _keeper_say_edit: LineEdit = null
var _keeper_ack_label: Label = null
var _keeper_ack_t: float = 0.0
var _keeper_cam_prev: Vector3 = Vector3.ZERO
var _keeper_cursor_prev: Vector2 = Vector2.ZERO
const FOLLOW_THOUGHT_CHAR_S: float = 0.034
const FOLLOW_INNER_THOUGHT_INTERVAL_S: float = 48.0
var _follow_inner_thought_cd: float = 0.0
var _follow_inner_thought_last_line: String = ""
var _workspace_inspector: Label = null
var _workspace_inspector_accum: float = 0.0
var _perf_hud: Label = null
# In-place body label for streaming away-recap toasts (avoids notification spam).
var _guardian_recap_toast_body: Label = null
var _last_guardian_line_shown: String = ""
# Selection reticle ring on the currently-followed creature (distinct from the
# favorite halos). Lives under `world`, repositioned each frame.
var _follow_reticle: MeshInstance3D = null
var _attention_halo: MeshInstance3D = null
var _reticle_phase: float = 0.0
# Cinematic framing + auto-tour "cinema mode".
var _follow_lock: bool = false            # true = rigidly centered; false = deadzone roam
var _cinema_active: bool = false
var _cinema_accum: float = 0.0
var _cinema_auto: bool = false            # true when the idle screensaver started the tour
const FOLLOW_LEAD_TIME: float = 0.4       # seconds of velocity lookahead
const FOLLOW_LERP_K: float = 3.0
const FOLLOW_DEADZONE: float = 0.9        # world units the subject may roam before the cam chases
const CINEMA_INTERVAL_S: float = 12.0
const SCREENSAVER_IDLE_S: float = 45.0    # idle time before an auto favorites-tour kicks in

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
	_release_cinematic_follow()
	_auto_orbit = false
	_apply_camera()


func _zoom_camera_by_factor(factor: float) -> void:
	if camera == null:
		return
	if _current_projection_id == "perspective":
		radius = CameraController.zoom_radius(radius, factor)
	else:
		camera.size = CameraController.zoom_ortho(camera.size, factor)
	_apply_camera()


func _save_aquascape_camera() -> void:
	_aquascape_saved_camera = {
		"target": target,
		"radius": radius,
		"yaw": yaw,
		"pitch": pitch,
		"projection": _current_projection_id,
		"fov": float(camera.fov) if camera != null else 55.0,
		"ortho_size": float(camera.size) if camera != null else 18.0,
	}


func _restore_aquascape_camera() -> void:
	if _aquascape_saved_camera.is_empty():
		_reset_camera_to_default()
		apply_camera_projection("perspective")
		return
	var saved := _aquascape_saved_camera
	target = saved["target"]
	radius = clampf(float(saved["radius"]), MIN_RADIUS, MAX_RADIUS)
	yaw = float(saved["yaw"])
	pitch = clampf(float(saved["pitch"]), MIN_PITCH, MAX_PITCH)
	_release_cinematic_follow()
	_auto_orbit = false
	var proj: String = String(saved.get("projection", "perspective"))
	_current_projection_id = proj
	if camera != null:
		match proj:
			"perspective":
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = float(saved.get("fov", 55.0))
			"top_down_ortho", "orthographic", "isometric", "dimetric":
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = float(saved.get("ortho_size", 18.0))
			_:
				apply_camera_projection(proj)
				_aquascape_saved_camera.clear()
				return
	_apply_camera()
	_aquascape_saved_camera.clear()


func _aquascape_scroll_build_plane(wheel_up: bool) -> bool:
	if not _aquascape.is_active or not Input.is_key_pressed(KEY_SHIFT):
		return false
	if _aquascape.tool not in _AQUASCAPE_BUILD_PLANE_TOOLS:
		return false
	var delta := TerrainVoxelGrid.CELL_SIZE if wheel_up else -TerrainVoxelGrid.CELL_SIZE
	_aquascape.adjust_build_plane(delta)
	return true


# ---- Camera Views panel API ----
# Called by the Camera Views panel's preset buttons. Each preset frames the
# tank from a distinctive angle. Cylinder tanks scale the radius up to keep
# the full vertical column in frame. Box tanks use their half-width.
func apply_camera_preset(preset_id: String) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	var tank_h: float = float(cfg.get("tank_height")) if cfg != null else 7.0
	var tank_hw: float = float(cfg.get("tank_half_w")) if cfg != null else 8.0
	var tank_hd: float = float(cfg.get("tank_half_d")) if cfg != null else 4.0
	var base_r: float = maxf(tank_h * 1.5, maxf(tank_hw, tank_hd) * 2.4)
	_release_cinematic_follow()
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
			# Bird's-eye down. Framing follows the tank footprint so round
			# bowls fill the frame instead of swimming in a box-shaped crop.
			var top_frame: Dictionary = _topdown_framing()
			target = top_frame["target"]
			yaw = 0.0
			pitch = 1.40
			radius = float(top_frame["radius"])
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
	_release_cinematic_follow()
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
		if TopdownMotion.is_overhead(self) and _sim != null:
			var cen: Vector2 = _school_centroid_xz()
			target.x = cen.x
			target.z = cen.y
		_apply_camera()


func apply_pond_mode(enable: bool = true) -> void:
	TopdownMotion.pond_active = enable
	TopdownMotion.overhead_yaw_spin = enable
	TopdownMotion.pond_bowl_vignette = enable
	if enable:
		apply_camera_preset("top")
		apply_camera_projection("top_down_ortho")
		call_deferred("_establish_pond_framing")
		if TopdownMotion.should_show_pond_hint():
			call_deferred("_show_pond_view_hint")
	else:
		TopdownMotion.overhead_yaw_spin = false
		TopdownMotion.pond_bowl_vignette = false
	_apply_pond_visuals(enable)
	_haptic(18)


func is_pond_mode() -> bool:
	return TopdownMotion.pond_active


func take_pond_photo() -> void:
	if not TopdownMotion.is_overhead(self):
		apply_pond_mode(true)
	_take_photo()


func _pond_surface_tap(mouse_pos: Vector2) -> bool:
	if _sim == null or not is_pond_mode():
		return false
	if display == null or not display.get_global_rect().has_point(mouse_pos):
		return false
	if _click_hits_interactive_hud(mouse_pos):
		return false
	var hit: Vector3 = _project_to_surface(mouse_pos)
	if hit == INVALID_HIT:
		return false
	if world != null and world.has_method("spawn_glass_tap_ripples"):
		world.spawn_glass_tap_ripples(hit)
	elif world != null and world.has_method("spawn_burst_ripple"):
		world.spawn_burst_ripple(hit, 1.5)
	if _sim.has_method("pulse_startle_bolt"):
		_sim.pulse_startle_bolt(hit)
	_haptic(10)
	for f in _sim.fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var dx: float = f.position.x - hit.x
		var dz: float = f.position.z - hit.z
		var d2: float = dx * dx + dz * dz
		if d2 > 12.0:
			continue
		var prox: float = 1.0 - clampf(sqrt(d2) / 3.5, 0.0, 1.0)
		var radial: Vector3 = TopdownMotion.startle_radial_dir(f.position, hit, f.heading)
		f._startle_heading = radial
		f._startle_remaining = maxf(float(f._startle_remaining), lerpf(0.12, 0.35, prox))
		f.curiosity_drive = clampf(float(f.curiosity_drive) + prox * 0.08, 0.0, 1.0)
	return true


var _pond_conduct_pts: Array = []
const _POND_CONDUCT_MIN_STEP: float = 0.35


func _pond_conduct_add(hit: Vector3) -> void:
	if hit == INVALID_HIT:
		return
	if _pond_conduct_pts.is_empty():
		_pond_conduct_pts.append(hit)
		return
	var last: Vector3 = _pond_conduct_pts[_pond_conduct_pts.size() - 1]
	if last.distance_to(hit) >= _POND_CONDUCT_MIN_STEP:
		_pond_conduct_pts.append(hit)


func _finish_pond_conduct() -> void:
	if _pond_conduct_pts.size() < 3:
		_pond_conduct_pts.clear()
		return
	var cfg: TopdownMotion.ConductResult = TopdownMotion.conduct_from_stroke(_pond_conduct_pts)
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.has_method("conduct"):
		mc.conduct(cfg.move, cfg.formation)
	if _sim != null and _sim.has_method("set_conduct_anchor"):
		_sim.set_conduct_anchor(cfg.center, cfg.radius)
	_pond_conduct_pts.clear()
	_haptic(14)


func _school_centroid_xz() -> Vector2:
	if _sim == null:
		return Vector2(target.x, target.z)
	var c := Vector3.ZERO
	var n: int = 0
	for f in _sim.fish:
		if is_instance_valid(f) and f.get("_dying") != true:
			c += f.global_position
			n += 1
	if n <= 0:
		return Vector2(target.x, target.z)
	c /= float(n)
	return Vector2(c.x, c.z)


func _establish_pond_framing() -> void:
	if _sim == null or _sim.fish.is_empty():
		return
	var cen: Vector2 = _school_centroid_xz()
	target.x = lerpf(target.x, cen.x, 0.72)
	target.z = lerpf(target.z, cen.y, 0.72)
	_apply_camera()


func _show_pond_view_hint() -> void:
	TopdownMotion.mark_pond_hint_shown()
	if _onboarding != null and _onboarding.has_method("show_topdown_hint"):
		_onboarding.show_topdown_hint()
	else:
		_show_photo_toast("Play music for mandala dances · Alt+drag to conduct · F12 postcard · T timelapse")


func _apply_pond_visuals(on: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	if on:
		cfg.pp_vignette_strength = maxf(float(cfg.pp_vignette_strength), 0.32)
		if world != null:
			var light: DirectionalLight3D = world.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
			if light != null:
				light.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
				light.light_energy = maxf(light.light_energy, 1.15)
			if world.has_method("_tick_topdown_surface"):
				world.call("_tick_topdown_surface", 0.0)
	else:
		cfg.pp_vignette_strength = maxf(float(cfg.pp_vignette_strength) * 0.85, 0.20)


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
			_release_cinematic_follow()
			_apply_camera()
			_haptic(15)
		"dimetric":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = _ortho_size_from_tank()
			yaw = _ISO_YAW
			pitch = _DIMETRIC_PITCH
			_auto_orbit = false
			_release_cinematic_follow()
			_apply_camera()
			_haptic(15)
		"top_down_ortho":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			var top_ortho: Dictionary = _topdown_framing()
			target = top_ortho["target"]
			camera.size = float(top_ortho["ortho_size"])
			pitch = _TOPDOWN_PITCH
			yaw = 0.0
			_auto_orbit = false
			_release_cinematic_follow()
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


# TOPDOWN_MOTION #10 — plan-view framing per tank_shape (ortho size + target).
const _TOPDOWN_GLASS_MARGIN: float = 0.35


func _tank_footprint_from_config(cfg: Node) -> TankFootprint:
	var fp := TankFootprint.from_config(cfg)
	if cfg == null:
		return fp
	var tank_h: float = float(cfg.get("tank_height") if cfg.get("tank_height") != null else 7.0)
	fp.tank_height = tank_h
	fp.substrate_y = tank_h * float(cfg.get("substrate_depth_fraction") if cfg.get("substrate_depth_fraction") != null else 0.23)
	fp.water_y = tank_h * float(cfg.get("water_surface_fraction") if cfg.get("water_surface_fraction") != null else 0.93)
	if world != null and world.get("WATER_HEIGHT") != null:
		fp.water_y = float(world.get("WATER_HEIGHT"))
		if world.get("SUBSTRATE_DEPTH") != null:
			fp.substrate_y = float(world.get("SUBSTRATE_DEPTH"))
	return fp


func _topdown_plan_half_extents(fp: TankFootprint) -> Vector2:
	match fp.shape:
		"cylinder", "sphere":
			var rad: float = fp.radius_at_height(fp.water_y, _TOPDOWN_GLASS_MARGIN)
			if rad <= 0.0:
				rad = fp.effective_radius(_TOPDOWN_GLASS_MARGIN)
			return Vector2(rad, rad)
		_:
			return fp.bounding_half_extents(_TOPDOWN_GLASS_MARGIN)


func _topdown_ortho_size_for_extents(half_ext: Vector2, shape: String) -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1536.0, 864.0)
	var aspect: float = maxf(1.0, vp.x / maxf(1.0, vp.y))
	var pad: float = 1.08
	match shape:
		"cylinder", "sphere":
			pad = 1.06
		"hex":
			pad = 1.10
		"triangle":
			pad = 1.12
	var need: float = maxf(half_ext.y, half_ext.x / aspect) * pad
	return clampf(need, 6.0, 60.0)


func _topdown_perspective_radius(half_ext: Vector2, shape: String) -> float:
	var r_plan: float = maxf(half_ext.x, half_ext.y)
	match shape:
		"cylinder", "sphere":
			return clampf(r_plan * 3.05, MIN_RADIUS, MAX_RADIUS)
		"hex":
			return clampf(r_plan * 3.22, MIN_RADIUS, MAX_RADIUS)
		"triangle":
			return clampf(r_plan * 3.32, MIN_RADIUS, MAX_RADIUS)
		_:
			return clampf(r_plan * 3.4, MIN_RADIUS, MAX_RADIUS)


func _topdown_framing() -> Dictionary:
	var cfg := get_node_or_null("/root/TankConfig")
	var fp := _tank_footprint_from_config(cfg)
	var half_ext: Vector2 = _topdown_plan_half_extents(fp)
	var target_y: float = fp.water_y if cfg != null else 6.5
	return {
		"target": Vector3(0.0, target_y, 0.0),
		"ortho_size": _topdown_ortho_size_for_extents(half_ext, fp.shape),
		"radius": _topdown_perspective_radius(half_ext, fp.shape),
	}


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
	follow_creature(pool[randi() % pool.size()], FollowMode.CINEMATIC)
	_haptic(12)


func clear_follow_target() -> void:
	clear_follow()


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
		_apply_panel_layout()
	var opening: bool = not _camera_views_panel.visible
	if opening:
		_prepare_panel_open()
		if _ui_panels != null:
			_ui_panels.close_side_panels()
	_camera_views_panel.visible = not _camera_views_panel.visible
	if _camera_views_panel.visible and _camera_views_panel.has_method("sync_from_main"):
		_camera_views_panel.sync_from_main()


# Add a Residents toggle to the right rail. Like Camera Views, it lives in the
# view-tools group (above the divider), built at runtime so it inherits the
# cluster's theme/sizing.
func _install_residents_rail_button() -> void:
	var cluster_vbox: Node = get_node_or_null("RightRail/RightCluster/VBox")
	if cluster_vbox == null:
		return
	var btn := Button.new()
	btn.name = "ResidentsToggle"
	btn.text = "👥"
	btn.tooltip_text = "Residents — follow & favorite your creatures (K)"
	btn.custom_minimum_size = Vector2(48, 48)
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_toggle_residents_panel)
	cluster_vbox.add_child(btn)
	var divider: Node = cluster_vbox.get_node_or_null("RailDivider")
	if divider != null:
		cluster_vbox.move_child(btn, divider.get_index())


# Lazy-build the Residents panel and toggle its visibility. Docks full-height on
# the LEFT so the right-side follow portal stays visible — "browse left, watch
# right". Opening it closes manager side panels so they don't collide.
func _toggle_residents_panel() -> void:
	if _residents_panel == null:
		var script := load("res://scripts/residents_panel.gd")
		_residents_panel = script.new() as Control
		_residents_panel.name = "ResidentsPanel"
		_residents_panel.set("main_ref", self)
		add_child(_residents_panel)
		_residents_panel.z_index = 130
		_apply_panel_layout()
	var opening: bool = not _residents_panel.visible
	if opening:
		_prepare_panel_open()
		if _ui_panels != null:
			_ui_panels.close_modal()
	_residents_panel.visible = not _residents_panel.visible
	if _residents_panel.visible:
		if _ui_panels != null:
			_ui_panels.close_side_panels()
		if _residents_panel.has_method("sync_from_main"):
			_residents_panel.sync_from_main()


# Camera tuning re-exported from CameraController (single source of truth — the
# orbit/pan/dolly math now lives there; these aliases keep main's other
# references, e.g. persistence clamps, pointed at the same values). #2 / 0B.
const SENSITIVITY: float = CameraController.SENSITIVITY
const ZOOM_FACTOR: float = CameraController.ZOOM_FACTOR
const MIN_RADIUS: float = CameraController.MIN_RADIUS
const MAX_RADIUS: float = CameraController.MAX_RADIUS
const MIN_PITCH: float = CameraController.MIN_PITCH
const MAX_PITCH: float = CameraController.MAX_PITCH
const PAN_SPEED: float = 6.0
# Auto-orbit angular speed (rad/sec). Now a var so the Camera Views panel
# can tune it live; default mirrors the old const value.
var AUTO_ORBIT_SPEED: float = 0.08
# Camera Views panel instance (lazy-built in _ready).
var _camera_views_panel: Control = null
# Residents panel instance (lazy-built on first toggle).
var _residents_panel: Control = null

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
const PAN_MOUSE_SENSITIVITY: float = CameraController.PAN_MOUSE_SENSITIVITY
const DOLLY_MOUSE_SENSITIVITY: float = CameraController.DOLLY_MOUSE_SENSITIVITY
# Follow-cam: when set, camera target tracks this Node3D.
var _follow_target: Node3D = null
# Set true when an LMB-down event lands on a creature (picking dispatch in
# `_input`). The `_process` polling reads `Input.is_mouse_button_pressed` —
# event handling can't stop polling, so without this flag the same press
# ALSO starts an orbit drag and every creature click spun the camera.
# Cleared the next frame LMB releases.
var _suppress_drag_until_release: bool = false
var _press_skip_feed: bool = false

# Aquascape sculpting (terrain, hardscape, trim, unified undo).
var _aquascape := AquascapeController.new()
var _aquascape_view_bar: PanelContainer = null
var _aquascape_saved_camera: Dictionary = {}
const _AQUASCAPE_BUILD_PLANE_TOOLS: Array[String] = [
	"block", "eraser", "object", "eyedropper", "line", "box", "paste",
]
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
const DRAG_DEADZONE_PX: float = CameraController.DRAG_DEADZONE_PX
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
var _toast_recent_keys: Dictionary = {}

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
var _onboarding: Node = null

# Tap-to-feed: pick food in the footer dock; click/tap water to drop.
var _feed_subtype: int = WasteParticle.FOOD_SUB_PELLET
var _feed_dock: HBoxContainer = null
var _feed_btns: Array[Button] = []
var _feed_toast_panel: PanelContainer = null
var _feed_toast: Label = null
var _feed_toast_tween: Tween = null
var _feed_hint_shown: bool = false
var _feed_dock_lbl: Label = null


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _is_touch_active() -> bool:
	return _touch_active


func _ready() -> void:
	_DartTrailPoolScript.reset_for_test()
	MainUiRefs.bind_from(self)
	ShaderUniformLedger.set_debug(OS.is_debug_build())
	# Apply render-config values BEFORE the SubViewport assigns its texture
	# so the resolution change takes effect.
	_ensure_post_pipeline()
	_apply_render_config()
	VoxelMat.warm_shader_variants(get_node_or_null("/root/TankConfig"))
	VoxelMat.refresh_fauna_rims()
	_wire_post_textures()
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
	if _sim != null and _sim.has_signal("eco_event"):
		_sim.connect("eco_event", _on_eco_event)
	if _sim != null and _sim.has_signal("creature_removed"):
		_sim.connect("creature_removed", _on_creature_removed)
	if _sim != null and _sim.has_signal("favorites_changed"):
		_sim.connect("favorites_changed", _refresh_favorite_halos)
		_refresh_favorite_halos.call_deferred()
	if _sim != null and _sim.has_signal("guardian_spoke"):
		_sim.connect("guardian_spoke", _on_guardian_spoke)
	if _sim != null and _sim.has_signal("guardian_recap_streaming"):
		_sim.connect("guardian_recap_streaming", _on_guardian_recap_streaming)
	if _sim != null and _sim.has_signal("fish_thought_spoke"):
		_sim.connect("fish_thought_spoke", _on_fish_thought_spoke)
	var ai_dir := get_node_or_null("/root/AIDirector")
	if ai_dir != null and ai_dir.has_signal("fish_thought_streaming"):
		if not ai_dir.fish_thought_streaming.is_connected(_on_fish_thought_streaming):
			ai_dir.fish_thought_streaming.connect(_on_fish_thought_streaming)
	if _sim != null and _sim.has_signal("fish_voiced_wake"):
		_sim.connect("fish_voiced_wake", _on_fish_voiced_wake)
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm != null and glm.has_signal("status_changed"):
		glm.status_changed.connect(_on_guardian_llm_status)
	if glm != null and glm.has_signal("consent_required"):
		if not glm.consent_required.is_connected(_on_guardian_consent_required):
			glm.consent_required.connect(_on_guardian_consent_required)
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
	_install_residents_rail_button()
	_setup_panel_close_hooks()
	if walkthrough_overlay != null and walkthrough_overlay.has_method("setup"):
		walkthrough_overlay.setup(self)
		call_deferred("_maybe_start_walkthrough")
		call_deferred("_maybe_open_aquascape_on_load")
	_onboarding = OnboardingRuntimeScript.new()
	_onboarding.setup(self)
	add_child(_onboarding)
	_onboarding.ensure_ui(self)
	var species_lib := get_node_or_null("/root/SpeciesLibrary")
	if species_lib != null and species_lib.has_signal("species_discovered"):
		species_lib.species_discovered.connect(_on_species_discovered)
	if aquascape_toggle != null:
		aquascape_toggle.pressed.connect(_toggle_aquascape)
	if menu_button != null:
		menu_button.pressed.connect(_on_back_to_menu)
	_add_immersive_toggle_button()
	_aquascape.setup(self, camera, world, aquascape_palette)
	_aquascape.mode_changed.connect(_sync_viewport_update_mode)
	call_deferred("_refresh_aquascape_build_appearance")
	_ensure_aquascape_view_bar()
	_sync_aquascape_view_bar()
	_sync_viewport_update_mode(_aquascape.is_active)
	call_deferred("_fade_in_from_black")
	
	if portal_toggle != null:
		portal_toggle.pressed.connect(_toggle_portal)
	if portal_display != null:
		# PiP zooms the main tank render — no second 3D camera needed.
		portal_display.texture = sub_viewport.get_texture()
		if portal_display.material is ShaderMaterial:
			_portal_mat = portal_display.material as ShaderMaterial

	# ---- Top HUD: build stat chips, apply responsive layout, watch resizes ----
	_setup_hud_styling()
	_setup_footer_bar()
	_setup_feed_dock()
	call_deferred("_maybe_feed_hint")
	_setup_speed_hud()
	_add_tank_lights_toggle()
	_ensure_notifications_ui()
	_build_hud_chips()
	_setup_rail_groups()
	_on_viewport_resized()
	get_viewport().size_changed.connect(_on_viewport_resized)

	# Re-layout the display once the window has its final size. On first
	# launch the initial pass can run before the window is fully sized,
	# which leaves integer-upscale letterboxing clipped to a corner.
	call_deferred("_apply_display_layout")

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
	call_deferred("_sync_speed_hud")
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
	call_deferred("_maybe_show_sentience_intro")
		
	_build_portal_info_ui()
	_build_follow_thought_ui()
	if _rail_vbox != null and _onboarding != null:
		_onboarding.install_help_rail_button(_rail_vbox)


func _toggle_portal() -> void:
	if _follow_mode == FollowMode.PIP:
		clear_follow()
	else:
		# Open the magnifier. Keep the current target if we were in cinematic
		# (demotes to PiP); otherwise the portal opens empty awaiting a pick.
		_follow_mode = FollowMode.PIP
		if portal_container != null:
			portal_container.visible = true
		if portal_hint != null:
			portal_hint.visible = _follow_target == null
		_update_portal_pip()
		_sync_rail_toggles()
		follow_target_changed.emit(_follow_target)
	print_verbose("[walstad_loom] PiP portal %s" % ("OPEN" if _follow_mode == FollowMode.PIP else "CLOSED"))


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
	# Saved views from extreme scroll-zoom can pin the camera inside the glass.
	var d: Dictionary = _default_camera_for_tank()
	var sane_min: float = maxf(MIN_RADIUS, float(d["radius"]) * 0.55)
	if radius < sane_min:
		radius = float(d["radius"])
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


func _quantize_material() -> ShaderMaterial:
	if _post_display != null and _post_display.material is ShaderMaterial:
		return _post_display.material as ShaderMaterial
	if display != null and display.material is ShaderMaterial:
		return display.material as ShaderMaterial
	return null


func _ensure_post_pipeline() -> void:
	if is_instance_valid(_post_viewport) and is_instance_valid(_post_display):
		return
	_post_viewport = null
	_post_display = null
	if not is_instance_valid(sub_viewport):
		return
	_post_viewport = SubViewport.new()
	_post_viewport.name = "PostViewport"
	_post_viewport.transparent_bg = true
	_post_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_post_viewport)
	_post_display = TextureRect.new()
	_post_display.name = "PostDisplay"
	_post_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_post_display.stretch_mode = TextureRect.STRETCH_SCALE
	_post_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if display.material is ShaderMaterial:
		_post_display.material = display.material
		display.material = null
	_post_viewport.add_child(_post_display)


func _wire_post_textures() -> void:
	if not is_instance_valid(sub_viewport):
		return
	if is_instance_valid(_post_display):
		_post_display.texture = sub_viewport.get_texture()
	if is_instance_valid(_post_viewport) and display != null:
		display.texture = _post_viewport.get_texture()
	elif display != null:
		display.texture = sub_viewport.get_texture()


func _viewport_needs_live_render(aquascape_active: bool) -> bool:
	if aquascape_active:
		return true
	if creature_creator_panel != null and creature_creator_panel.visible:
		return true
	# Keep the tank visible while the guided setup runs (sim paused, player stocking).
	if walkthrough_overlay != null and walkthrough_overlay.visible:
		return true
	return false


func _sync_viewport_update_mode(active: bool) -> void:
	if not is_instance_valid(sub_viewport):
		return
	var live: bool = _viewport_needs_live_render(active)
	var mode := SubViewport.UPDATE_ALWAYS
	if not live and _sim != null and float(_sim.time_scale) <= 0.0:
		mode = SubViewport.UPDATE_DISABLED
	if sub_viewport.render_target_update_mode != mode:
		sub_viewport.render_target_update_mode = mode
	if is_instance_valid(_post_viewport):
		_post_viewport.render_target_update_mode = mode
	_sync_speed_hud()
	_apply_hud_layout()


func _exit_tree() -> void:
	if _aquascape.mode_changed.is_connected(_sync_viewport_update_mode):
		_aquascape.mode_changed.disconnect(_sync_viewport_update_mode)


func _apply_render_config() -> void:
	# Read TankConfig render settings and apply them to the SubViewport,
	# the palette-quantize shader on the Display TextureRect, and the camera.
	var cfg := MainUiRefs.tank_config(self)
	if cfg == null:
		cfg = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	var render_w: int = int(cfg.render_width)
	var render_h: int = int(cfg.render_height)
	if _is_mobile():
		var oriented: Vector2i = _oriented_mobile_render_size(render_w, render_h)
		render_w = oriented.x
		render_h = oriented.y
	if not RenderResolutionAudit.post_matches_3d(render_w, render_h, render_w, render_h):
		push_warning("Render post chain must match 3D internal resolution")
	# SubViewport size.
	if is_instance_valid(sub_viewport):
		sub_viewport.size = Vector2i(render_w, render_h)
	if is_instance_valid(_post_viewport):
		_post_viewport.size = Vector2i(render_w, render_h)
		_wire_post_textures()
	# MSAA: 0=disabled, 1=2x, 2=4x, 3=8x (matches Viewport.MSAA enum).
	if is_instance_valid(sub_viewport):
		sub_viewport.msaa_3d = int(cfg.msaa) as Viewport.MSAA
	# Palette quantize shader uniforms (runs on the internal-res post pass).
	var sm := _quantize_material()
	if sm != null:
		var tier: int = int(cfg.shader_perf_tier)
		var want_shader: Shader = _QuantizePotatoShader if tier >= 2 else _QuantizeShader
		if sm.shader != want_shader:
			sm.shader = want_shader
		var dither_v: float = float(cfg.dither_strength)
		if render_w <= 256:
			dither_v = maxf(dither_v, 0.90)
		if bool(cfg.get("pixel_purity")):
			dither_v = maxf(dither_v, 0.94)
		sm.set_shader_parameter("dither_strength", dither_v)
		ShaderUniformLedger.write(sm, &"internal_resolution",
			Vector2(float(render_w), float(render_h)))
		ShaderUniformLedger.write(sm, &"region_aware_dither",
			1.0 if cfg.dither_region_aware else 0.0)
		ShaderUniformLedger.write(sm, &"dither_world_lock",
			1.0 if cfg.dither_world_lock else 0.0)
		ShaderUniformLedger.write(sm, &"dither_world_origin",
			Vector2(float(cfg.camera_target_x), float(cfg.camera_target_z)))
		ShaderUniformLedger.write(sm, &"blue_noise_amount", float(cfg.blue_noise_amount))
		ShaderUniformLedger.write(sm, &"shader_perf_tier", float(cfg.shader_perf_tier))
		ShaderUniformLedger.write(sm, &"palette_bank_lock",
			1.0 if cfg.palette_bank_lock else 0.0)
		ShaderUniformLedger.write(sm, &"outline_strength", float(cfg.outline_strength))
		ShaderUniformLedger.write(sm, &"creature_outline_strength", float(cfg.creature_outline_strength))
		ShaderUniformLedger.write(sm, &"crt_strength", float(cfg.crt_strength))
		ShaderUniformLedger.write(sm, &"material_hue_shift", float(cfg.material_hue_shift))
		sm.set_shader_parameter("material_saturation", float(cfg.material_saturation))
		sm.set_shader_parameter("material_warmth", float(cfg.material_warmth))
		sm.set_shader_parameter("material_value", float(cfg.material_value))
		var world_vis := world.get_node_or_null("AquariumVisuals") as AquariumVisuals
		if world_vis != null:
			sm.set_shader_parameter("seasonal_warmth", world_vis.seasonal_palette_shift())
		# Per-biotope palette swap: a blackwater tank quantizes through amber
		# tannin colors, a reef through bright alkaline blues, planted through
		# the verdant default. Built at runtime so no extra PNGs are needed.
		_apply_biotope_palette(sm, cfg)
		_apply_adaptive_shader_cost()
	VoxelMat.set_shader_perf_tier(int(cfg.shader_perf_tier))
	if sm != null:
		var tier: int = int(cfg.shader_perf_tier)
		if tier >= 2:
			sm.set_shader_parameter("outline_strength", 0.0)
			sm.set_shader_parameter("crt_strength", 0.0)
			sm.set_shader_parameter("film_grain_strength", 0.0)
		elif tier >= 1:
			sm.set_shader_parameter("outline_strength", minf(float(cfg.outline_strength), 0.15))
			sm.set_shader_parameter("crt_strength", minf(float(cfg.crt_strength), 0.12))
	_sync_biotope_ui_cohesion(cfg)
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
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_current_projection_id = "perspective"
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


# 48-color biotope palettes (hex), matching shaders-godot/make_palette.py.
# Built into ImageTextures on demand so each biotope reads in its own color
# story instead of forcing every tank through the planted palette.
const BIOTOPE_PALETTES: Dictionary = {
	"planted": [
		"0b1a22","163040","23475a","356379","4b8095","69a1b3","92c3d0","c5e2e7",
		"102614","1d3b22","2c5a30","3e7f40","57a253","79c069","a5d97e","d0eb9a",
		"1a120c","2c1f15","432f1f","5d4128","785538","95714e","b18f6a","cdb088",
		"1a1a1f","2a2a30","3d3d44","555560","707081","8c8ca0","a8a8bd","c4c4d6",
		"ffffff","e0eef2","b9d6df","c33b3b","d97e2c","e6c92a","2a7a4b","4a52c4",
		"872cb0","c44a8e","2c1810","1a0f08","0d0805","503820","000000","f8f4e0",
	],
	"blackwater": [
		"0a0907","15110b","251c10","382a14","4d3a1c","6a5128","8c7042","b9986a",
		"0c0905","1a130a","2b2014","3d2f1e","57442d","735c40","927758","b29575",
		"0e1a0d","1b2d18","2c4527","4a6738","6c894e","95ad6f","0d1015","1a1d22",
		"2c2f34","444751","5d6068","777a82","92959c","adb0b6","c8cad0","e2e3e7",
		"ffffff","f4e4c8","e0c89a","a13a2a","b86a30","d4a838","2e5a3c","3a4ca0",
		"5e2c80","9c3c70","000000","7d6240","5a4630","3c2f20","241b12","ffffff",
	],
	"hard_alkaline": [
		"0d1f25","1a3947","2e5a6e","467c92","62a1b4","87c2cf","b3def0","dff1f6",
		"2a2620","423d34","5d574b","7c7466","9e957f","c0b899","ddd6b5","f0ecd2",
		"4a4943","6b685d","8b8678","aaa595","c5c0b0","ddd9c8","efeddc","fbfbf0",
		"10301c","1d4a2c","2c6440","458056","6ba07a","94c0a0","ffffff","000000",
		"c44848","d97e2c","e6c92a","2c6db3","3a4ca0","7c2cb0","c44a8e","202020",
		"3a3a3a","5a5a5a","7a7a7a","9a9a9a","bababa","dadada","f0f0f0","ffffff",
	],
	"amazon_clearwater": [
		"081820","122830","1e3f4e","2e5868","428099","5ea3b5","86c4d0","b8e2ea",
		"0a2010","163820","245830","387842","52a058","72c070","a0dc90","d0f0b0",
		"181008","2a1810","3e2818","563820","705030","8c6848","a88868","c8a888",
		"181820","282830","383840","505058","686870","808088","9898a0","b0b0b8",
		"ffffff","e8f4f8","c8e8f0","d84040","e88830","f0d040","289858","4858c8",
		"7828a8","c04888","1a1008","0c0804","000000","584020","f8f4e8","ffffff",
	],
	"tanganyika_rock": [
		"101820","1c2838","2c4050","406878","588ca0","78b0c0","a8d0dc","d8ecf0",
		"201810","382818","503828","685040","887060","a89078","c8b098","e8d8c0",
		"282420","403830","585040","706858","888070","a09880","b8b098","d0c8b0",
		"101418","202428","303438","484c50","606468","787c80","909498","a8acb0",
		"ffffff","f0ece0","d8d0c0","c04038","d87828","e8b830","3878a8","4048a0",
		"682898","984878","000000","584830","383020","201810","f8f4e8","ffffff",
	],
	"asian_peat": [
		"080806","100e0a","1a1610","282018","383020","504830","6a6040","887858",
		"0a1008","142010","202818","2c3820","3c5028","507038","689048","88b060",
		"100c08","201810","302818","403828","504838","605848","706858","807868",
		"141210","242220","343230","444240","545250","646260","747270","848280",
		"ffffff","e8dcc8","d0c0a0","983828","b06028","c89830","286840","384898",
		"582878","883868","000000","604820","403018","201008","f0e8d8","ffffff",
	],
	"temperate": [
		"101820","1a2830","283840","385058","507080","6898a8","90b8c8","c0dce8",
		"101810","182818","243828","345038","486848","608860","88a880","b0d0b0",
		"181410","282018","383028","484038","585048","686058","787068","888078",
		"181818","282828","383838","484848","585858","686868","787878","888888",
		"ffffff","e0e8ec","c0d0d8","a83838","c06830","d8a838","387858","4858a0",
		"682880","984870","000000","504838","302820","181410","f0ece4","ffffff",
	],
	"brackish": [
		"101810","1a2818","283828","385038","486848","588058","709870","90b890",
		"181408","282010","383018","484028","585038","686048","787058","888068",
		"141810","202820","2c3830","384840","485850","586860","687870","788880",
		"181818","282820","383830","484840","585850","686860","787870","888880",
		"ffffff","e8ece0","d0d8c8","b04030","c87028","d8a830","387888","404890",
		"602878","904868","000000","585040","403828","282018","f0ece0","ffffff",
	],
	"reef": [
		"081828","102838","183848","205868","288898","40b0c8","70d0e0","a8ecf4",
		"081818","102828","184038","205850","287868","389878","50b898","78d8b8",
		"201008","382010","502818","683820","805028","986838","b08048","c89858",
		"101018","202028","303038","404048","505058","606068","707078","808088",
		"ffffff","f0f8fc","d0e8f0","ff4040","ff8830","ffe040","30c868","4060ff",
		"ff40c0","ff6088","000000","404040","202020","101010","f8fcff","ffffff",
	],
}
var _biotope_palette_cache: Dictionary = {}


# Pick the palette key for the current tank from its preset/biotope.
func _current_biotope_palette_key(cfg: Node) -> String:
	return AestheticsRuntime.biotope_palette_key(cfg)


# Build (and cache) day+night ImageTextures for a biotope palette key.
# Night is a darkened, cooled copy of the day ramp, preserving the brightest
# slots so emissive content still burns through the moonlit field.
func _biotope_palette_textures(key: String) -> Array:
	if _biotope_palette_cache.has(key):
		return _biotope_palette_cache[key]
	var hexes: Array = BIOTOPE_PALETTES.get(key, BIOTOPE_PALETTES["planted"])
	var cfg := get_node_or_null("/root/TankConfig")
	var cb_mode := "none"
	if cfg != null:
		cb_mode = String(cfg.get("colorblind_palette"))
	hexes = AestheticsRuntime.remap_palette_hexes(hexes, cb_mode)
	var day_img := Image.create(48, 1, false, Image.FORMAT_RGBA8)
	var night_img := Image.create(48, 1, false, Image.FORMAT_RGBA8)
	for i in range(min(48, hexes.size())):
		var c := Color.from_string("#" + String(hexes[i]), Color.BLACK)
		day_img.set_pixel(i, 0, c)
		var lum: float = c.get_luminance()
		# Darken + cool; keep near-white highlights mostly intact.
		var night := c.darkened(0.42)
		night = night.lerp(Color(night.r * 0.7, night.g * 0.82, night.b * 1.1, 1.0), 0.5)
		night = c.lerp(night, clampf(1.0 - lum * 0.6, 0.3, 1.0))
		night.a = 1.0
		night_img.set_pixel(i, 0, night)
	var day_tex := ImageTexture.create_from_image(day_img)
	var night_tex := ImageTexture.create_from_image(night_img)
	var out: Array = [day_tex, night_tex]
	_biotope_palette_cache[key] = out
	return out


# Assign the biotope's palette textures to the quantize material.
func _apply_biotope_palette(sm: ShaderMaterial, cfg: Node) -> void:
	if sm == null:
		return
	var key := _current_biotope_palette_key(cfg)
	var texs := _biotope_palette_textures(key)
	if texs.size() == 2:
		sm.set_shader_parameter("palette_tex", texs[0])
		sm.set_shader_parameter("palette_tex_night", texs[1])


func _sync_biotope_ui_cohesion(cfg: Node) -> void:
	if cfg == null:
		return
	var key := _current_biotope_palette_key(cfg)
	var hexes: Array = BIOTOPE_PALETTES.get(key, BIOTOPE_PALETTES["planted"])
	hexes = AestheticsRuntime.remap_palette_hexes(hexes, String(cfg.get("colorblind_palette")))
	PanelTheme.sync_biotope_cohesion(hexes)
	if _portal_glass_mat != null:
		_portal_glass_mat.set_shader_parameter("tint", PanelTheme.glass_panel_tint())
	if render_panel != null:
		PanelTheme.apply_panel_chrome(render_panel)


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
	var sm := _quantize_material()
	if sm != null:
		sm.set_shader_parameter("material_hue_shift", float(cfg.material_hue_shift))
		sm.set_shader_parameter("material_saturation", float(cfg.material_saturation))
		sm.set_shader_parameter("material_warmth", float(cfg.material_warmth))
		sm.set_shader_parameter("material_value", float(cfg.material_value))


func _process(dt: float) -> void:
	ShaderUniformLedger.tick(dt)
	_aquascape.tick_paint_cooldown(dt)

	# Top-HUD idle-dim. Mirrors MobileHUD: after HUD_IDLE_DIM_SECONDS of no
	# input, fade the top bar so it stops competing with the scene.
	# _notify_hud_input() (called from _input + touch handlers) resets this.
	_hud_idle_seconds += dt
	if _sim != null and _sim.has_method("set_room_idle"):
		_sim.set_room_idle(_hud_idle_seconds)
	var dl_idle: float = float(_sim.daylight()) if _sim != null and _sim.has_method("daylight") else 1.0
	var screensaver: bool = _hud_idle_seconds > NIGHT_WATCHSCREENSAVER_S and dl_idle < 0.35
	if _sim != null and _sim.has_method("set_screensaver_mode"):
		_sim.set_screensaver_mode(screensaver)
	var hud_dim: Color = Color.WHITE
	if screensaver:
		hud_dim = SCREENSAVER_DIM_MODULATE
	elif _hud_idle_seconds > HUD_IDLE_DIM_SECONDS:
		hud_dim = HUD_DIM_MODULATE
	if top_hud != null and top_hud.modulate != hud_dim:
		top_hud.modulate = hud_dim
	if right_rail != null and right_rail.modulate != hud_dim:
		right_rail.modulate = hud_dim
	if footer_bar != null and footer_bar.modulate != hud_dim:
		footer_bar.modulate = hud_dim
	if screensaver and not _moonlight_suggested:
		var cfg_m := get_node_or_null("/root/TankConfig")
		if cfg_m != null and cfg_m.has_method("apply_lighting_preset"):
			cfg_m.apply_lighting_preset("moonlit")
			_moonlight_suggested = true
	if not screensaver:
		_moonlight_suggested = false

	# Time-of-day palette tint. Drives the palette_quantize shader's
	# multiplicative tint so the same 48-color palette breathes between
	# dawn / day / dusk / night without needing 4 distinct PNGs. Cheap:
	# a vec3 set per frame on a single ShaderMaterial.
	_ambient_breath_t += dt
	_update_palette_tod_tint()

	# Frame-time sampling — feeds the render panel's mini-graph + the
	# adaptive quality controller below. Both are no-ops without the
	# corresponding TankConfig toggle, so the cost is just one append.
	_record_frame_time(dt)
	PerfGovernor.record_frame(dt)
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
		var cp: Vector3 = camera.global_position
		var rot_h: float = camera.global_basis.get_euler().length()
		if cp.distance_squared_to(_glance_cam_pos) > 0.0004 \
				or absf(rot_h - _glance_cam_rot_hash) > 0.002:
			_glance_cam_pos = cp
			_glance_cam_rot_hash = rot_h
			_sim.update_player_glance(cp)
	
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
	_update_plant_hover_meter()

	# Follow-cam: smoothly track the followed creature. Use the
	# frame-rate-independent lerp formula `1 - exp(-k*dt)` instead of the
	# naive `clampf(dt * k, ...)` so the follow feels equally smooth at 30,
	# 60, or 144 FPS. With the old form, at 30 FPS the lerp weight was 0.1
	# (jumpy), at 144 FPS it was 0.02 (sluggish) — same `k=3` produced
	# very different behavior on different displays.
	if _follow_mode == FollowMode.CINEMATIC and _follow_target != null:
		if not is_instance_valid(_follow_target):
			clear_follow()
		else:
			# Lead the subject by its velocity so the camera anticipates instead
			# of trailing. Free framing lets it roam within a deadzone (less
			# jitter); lock framing keeps it rigidly centered.
			var aim: Vector3 = _follow_target.global_position
			var vel_v: Variant = _follow_target.get("velocity")
			if vel_v is Vector3:
				aim += (vel_v as Vector3) * FOLLOW_LEAD_TIME
			var t: float = 1.0 - exp(-FOLLOW_LERP_K * dt)
			if _follow_lock:
				target = target.lerp(aim, t)
			else:
				var d: Vector3 = aim - target
				var dist: float = d.length()
				if dist > FOLLOW_DEADZONE:
					target = target.lerp(aim - d.normalized() * FOLLOW_DEADZONE, t)
			_apply_camera()
			
	if _follow_mode != FollowMode.OFF or (_portal_info_panel != null and _portal_info_panel.visible):
		_update_portal_pip()

	_tick_keeper_input(dt)
	_update_follow_reticle(dt)
	_update_attention_halo(dt)
	_tick_follow_inner_thoughts(dt)
	_tick_workspace_inspector(dt)
	_tick_perf_hud(dt)
	_update_follow_dof()
	if _cinema_active:
		_cinema_accum += dt
		if _cinema_accum >= CINEMA_INTERVAL_S:
			_cinema_accum = 0.0
			cycle_follow(1)
	elif _follow_mode == FollowMode.OFF and _hud_idle_seconds > SCREENSAVER_IDLE_S \
			and _sim != null and _sim.has_method("favorite_creatures") \
			and not _sim.favorite_creatures().is_empty():
		# Idle screensaver: drift through your favorites until you touch anything.
		set_cycle_scope(CycleScope.FAVORITES)
		set_cinema_mode(true, true)

	_sync_rail_toggles()

	# WASD pan target along view direction (desktop only — no keyboard on mobile).
	if not _is_touch_active() and not _typing_focus_in_ui():
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

	# Timelapse + dance capture (needs dt from _process).
	if _timelapse_active:
		_timelapse_accum += dt
		if _timelapse_accum >= TIMELAPSE_INTERVAL:
			_timelapse_accum = 0.0
			var frame_path: String = "%s/frame_%05d.png" % [_timelapse_dir, _timelapse_index]
			_timelapse_index += 1
			_request_viewport_image(_save_timelapse_frame.bind(frame_path))
	if _dance_capture_active:
		_dance_capture_accum += dt
		if _dance_capture_accum >= DANCE_CAPTURE_INTERVAL:
			_dance_capture_accum = 0.0
			if _dance_capture_index < DANCE_CAPTURE_FRAMES:
				var dance_path: String = "%s/frame_%05d.png" % [_dance_capture_dir, _dance_capture_index]
				_dance_capture_index += 1
				_request_viewport_image(_save_dance_frame.bind(dance_path))
			else:
				_finish_dance_capture()
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
				if _aquascape.begin_gumball_drag(mouse_now):
					_drag_mode = "gumball"
				elif _begin_aquascape_drag(mouse_now):
					_drag_mode = "wood_drag"
				else:
					_drag_mode = "paint"
					_aquascape.begin_stroke()
					_aquascape.place(mouse_now)
			else:
				if is_pond_mode() and Input.is_key_pressed(KEY_ALT):
					_drag_mode = "pond_conduct"
					_pond_conduct_pts.clear()
				else:
					_drag_mode = "orbit"
	elif not any_btn and _orbiting:
		if _drag_mode == "pond_conduct":
			_finish_pond_conduct()
		if _drag_button == MOUSE_BUTTON_LEFT and _drag_mode == "orbit" \
				and _drag_total < DRAG_DEADZONE_PX and not _aquascape.is_active:
			if not _press_skip_feed and not is_pond_mode():
				_drop_food_at_cursor(_drag_start)
			else:
				_try_pick_plant_at(_last_mouse)
		_orbiting = false
		_aquascape.end_stroke()
		_aquascape.end_drag()
		_drag_mode = ""
		_drag_button = 0

	if _orbiting:
		if _drag_button == MOUSE_BUTTON_LEFT \
				and _drag_mode != "paint" \
				and _drag_mode != "wood_drag" \
				and _drag_mode != "gumball" \
				and _drag_mode != "pond_conduct":
			_drag_mode = "pan" if pan_modifier else "orbit"
		var delta: Vector2 = mouse_now - _last_mouse
		_last_mouse = mouse_now
		_drag_total += delta.length()
		# Deadzone: don't engage orbit/pan/dolly until the cursor has moved
		# at least DRAG_DEADZONE_PX since mousedown. Paint and wood_drag are
		# exempt — those are tool actions, not navigation, and need to fire
		# on the click itself. Once committed, stays committed for the
		# duration of this drag.
		if not _drag_committed and CameraController.drag_committed(_drag_total):
			_drag_committed = true
		var nav_committed: bool = _drag_committed \
				or _drag_mode == "paint" or _drag_mode == "wood_drag" \
				or _drag_mode == "gumball" or _drag_mode == "pond_conduct"
		if delta.length_squared() > 0.0 and nav_committed:
			match _drag_mode:
				"pan":
					_pan_target(delta)
				"dolly":
					radius = CameraController.dolly(radius, delta.y)
					_apply_camera()
				"paint":
					if _aquascape.can_paint() and _aquascape.allows_drag_paint():
						_aquascape.place(mouse_now)
						_aquascape.mark_painted()
				"wood_drag":
					_aquascape.drag_hardscape(mouse_now)
				"gumball":
					_aquascape.drag_gumball(mouse_now)
				"pond_conduct":
					_pond_conduct_add(_project_to_surface(mouse_now))
				_:
					if is_pond_mode() and _current_projection_id == "top_down_ortho":
						_pan_target(delta)
						_pond_conduct_add(_project_to_surface(mouse_now))
					else:
						var ob: Vector2 = CameraController.orbit(yaw, pitch, delta)
						yaw = ob.x
						pitch = ob.y
						_apply_camera()


	# G toggles auto-orbit. (Space used to do this; it's now reserved as the
	# hold-to-pan modifier, matching Photoshop / Figma muscle memory.)
	if not _is_touch_active() and not _typing_focus_in_ui():
		var g_now: bool = Input.is_key_pressed(KEY_G)
		if g_now and not _auto_orbit_was_pressed:
			_auto_orbit = not _auto_orbit
		_auto_orbit_was_pressed = g_now
	if _auto_orbit and AccessibilityRuntime.motion_scale() > 0.0:
		yaw = CameraController.auto_orbit_yaw(yaw, AUTO_ORBIT_SPEED, dt)
		_apply_camera()
	elif TopdownMotion.overhead_yaw_spin and _current_projection_id == "top_down_ortho":
		yaw += 0.035 * dt
		_apply_camera()

	# Edge-triggered shortcuts (keyboard only — mobile gets on-screen buttons).
	if not _is_touch_active() and not _typing_focus_in_ui():
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
			var q_down: bool = Input.is_key_pressed(KEY_Q)
			var q_was: bool = _key_was_pressed.get(KEY_Q, false)
			if q_down and not q_was:
				_aquascape.rotate_selected_hardscape(15.0)
			_key_was_pressed[KEY_Q] = q_down
			var e_down: bool = Input.is_key_pressed(KEY_E)
			var e_was: bool = _key_was_pressed.get(KEY_E, false)
			if e_down and not e_was:
				_aquascape.rotate_selected_hardscape(-15.0)
			_key_was_pressed[KEY_E] = e_down
			if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
				var c_down: bool = Input.is_key_pressed(KEY_C)
				var c_was: bool = _key_was_pressed.get(KEY_C, false)
				if c_down and not c_was:
					_aquascape.copy_build()
				_key_was_pressed[KEY_C] = c_down
				var v_down: bool = Input.is_key_pressed(KEY_V)
				var v_was: bool = _key_was_pressed.get(KEY_V, false)
				if v_down and not v_was and _aquascape.tool != "paste":
					_aquascape.set_tool("paste")
				_key_was_pressed[KEY_V] = v_down
		var m_down: bool = Input.is_key_pressed(KEY_M)
		var m_was: bool = _key_was_pressed.get(KEY_M, false)
		if m_down and not m_was:
			if Input.is_key_pressed(KEY_SHIFT):
				_toggle_motion_debug()
			else:
				_ui_toggle_side(UiPanelManager.SIDE_SOUND)
		_key_was_pressed[KEY_M] = m_down
		_handle_shortcut(KEY_O, func(): _ui_toggle_side(UiPanelManager.SIDE_SETTINGS))
		if _aquascape.is_active:
			_handle_shortcut(KEY_9, func(): _aquascape.set_tool("block"))
			_handle_shortcut(KEY_0, func(): _aquascape.set_tool("eraser"))
		else:
			_handle_shortcut(KEY_9, func(): _cycle_feed_subtype(-1))
			_handle_shortcut(KEY_0, func(): _cycle_feed_subtype(1))
		_handle_shortcut(KEY_F12, func():
			if Input.is_key_pressed(KEY_SHIFT):
				_take_signature_shot()
			elif is_pond_mode():
				take_pond_photo()
			else:
				_take_photo())
		if _chip_popup_key != "":
			_handle_shortcut(KEY_ESCAPE, _close_chip_popups)
		else:
			_handle_shortcut(KEY_ESCAPE, _clear_follow)
		if _aquascape.is_active and _aquascape.has_selection():
			var step: float = TerrainVoxelGrid.CELL_SIZE
			if Input.is_key_pressed(KEY_SHIFT):
				step *= 4.0
			_handle_shortcut(KEY_UP, func(): _aquascape.nudge_selection(Vector3(0, 0, -step)))
			_handle_shortcut(KEY_DOWN, func(): _aquascape.nudge_selection(Vector3(0, 0, step)))
			_handle_shortcut(KEY_LEFT, func(): _aquascape.nudge_selection(Vector3(-step, 0, 0)))
			_handle_shortcut(KEY_RIGHT, func(): _aquascape.nudge_selection(Vector3(step, 0, 0)))
		else:
			_handle_shortcut(KEY_LEFT, func(): cycle_follow(-1))
			_handle_shortcut(KEY_RIGHT, func(): cycle_follow(1))
		_handle_shortcut(KEY_C, _toggle_portal)
		_handle_shortcut(KEY_K, _toggle_residents_panel)
		_handle_shortcut(KEY_APOSTROPHE, follow_primary_favorite)
		_handle_shortcut(KEY_T, _toggle_timelapse)
		_handle_shortcut(KEY_B, _toggle_aquascape)
		_handle_shortcut(KEY_H, _toggle_immersive_mode)
		_handle_shortcut(KEY_F, _reset_camera_to_default)
		_handle_shortcut(KEY_BACKSPACE, _aquascape_undo)
		_handle_shortcut(KEY_DELETE, _aquascape_undo)
		if _aquascape.is_active:
			var z_down: bool = Input.is_key_pressed(KEY_Z)
			var z_was: bool = _key_was_pressed.get(KEY_Z, false)
			if z_down and not z_was and Input.is_key_pressed(KEY_SHIFT):
				_aquascape.redo()
			_key_was_pressed[KEY_Z] = z_down

	# Aquascape preview voxel: shown at the substrate projection of the
	# current mouse/touch position, ONLY when in aquascape mode.
	var cursor_pos: Vector2 = _touches.values()[0] if _touches.size() > 0 else get_window().get_mouse_position()
	if _aquascape.is_active:
		_aquascape.update_workbench(cursor_pos)


func _update_aquascape_preview(mouse_pos: Vector2) -> void:
	_aquascape.update_workbench(mouse_pos)


func _project_to_surface(mouse_pos: Vector2) -> Vector3:
	if camera == null or world == null:
		return INVALID_HIT
	var sv_pos: Vector2 = _window_mouse_to_viewport(mouse_pos)
	var origin: Vector3 = camera.project_ray_origin(sv_pos)
	var dir: Vector3 = camera.project_ray_normal(sv_pos).normalized()
	var surface_y: float = float(world.get("WATER_HEIGHT")) if world.get("WATER_HEIGHT") != null else 6.5
	if absf(dir.y) < 1e-5:
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
	if Input.is_key_pressed(KEY_SHIFT) and world != null \
			and world.has_method("wipe_mineral_spots_near"):
		if world.wipe_mineral_spots_near(hit) > 0:
			return
	if world != null and world.has_method("spawn_glass_tap_ripples"):
		world.spawn_glass_tap_ripples(hit)
	elif world != null and world.has_method("spawn_burst_ripple"):
		world.spawn_burst_ripple(hit, 1.75)
	if _sim.has_method("pulse_glass_tap"):
		_sim.pulse_glass_tap(hit)
	if _sim.has_method("pulse_startle_bolt"):
		_sim.pulse_startle_bolt(hit)
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
		_show_feed_toast("Click inside the tank view")
		return false
	if _click_hits_interactive_hud(mouse_pos):
		return false
	var hit: Vector3 = _project_to_surface(mouse_pos)
	if hit == INVALID_HIT:
		_show_feed_toast("Aim at the water inside the tank")
		return false
	_play_feed_vfx(hit)
	var feed_hit: Vector3 = hit
	if world != null and world.get("WATER_HEIGHT") != null:
		feed_hit.y = float(world.WATER_HEIGHT) - 0.025
	if _sim.has_method("spawn_player_food"):
		_sim.spawn_player_food(feed_hit, _feed_subtype)
	else:
		_sim._spawn_waste(feed_hit, 0.45, WasteParticle.KIND_FOOD, _feed_subtype)
	var noticed: int = _alert_fish_to_feed(feed_hit, _feed_subtype)
	var msg: String = "%s dropped" % _feed_toast_label()
	if noticed > 0:
		msg = "%s · %d fish noticed" % [msg, noticed]
	else:
		msg = "%s · watch for ripples" % msg
	_show_feed_toast(msg)
	_pulse_feed_dock()
	_haptic(10)
	if _onboarding != null:
		_onboarding.on_first_feed()
	_clear_click_drag_state()
	return true


func _clear_click_drag_state() -> void:
	_orbiting = false
	_drag_mode = ""
	_drag_button = 0
	_drag_total = 0.0
	_drag_committed = false
	_press_skip_feed = false
	_suppress_drag_until_release = false


func _play_feed_vfx(hit: Vector3) -> void:
	if world == null:
		return
	if world.has_method("spawn_feeding_boil"):
		world.spawn_feeding_boil(hit)
	elif world.has_method("spawn_burst_ripple"):
		world.spawn_burst_ripple(hit, 1.75)


func _set_feed_subtype(subtype: int) -> void:
	_feed_subtype = posmod(subtype, UiIcons.FEED_SUBTYPE_KEYS.size())
	_sync_feed_dock()
	_show_feed_toast("%s — click water to drop" % _feed_toast_label())


func _feed_toast_label() -> String:
	return UiIcons.feed_button_label(UiIcons.feed_subtype_key(_feed_subtype), _is_mobile())


func _cycle_feed_subtype(delta: int) -> void:
	_set_feed_subtype(_feed_subtype + delta)


func _setup_feed_dock() -> void:
	if footer_bar == null:
		return
	var hbox: HBoxContainer = footer_bar.get_node_or_null("Margin/HBox") as HBoxContainer
	if hbox == null:
		return
	_feed_dock = HBoxContainer.new()
	_feed_dock.name = "FeedDock"
	_feed_dock.add_theme_constant_override("separation", 6)
	_feed_dock.tooltip_text = UiIcons.feed_tooltip("dock")
	var feed_lbl := Label.new()
	feed_lbl.text = "Feed · click water"
	feed_lbl.tooltip_text = UiIcons.feed_tooltip("dock")
	PanelTheme.apply_font(feed_lbl, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	feed_lbl.add_theme_color_override("font_color", PanelTheme.SECTION_FG)
	feed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_dock_lbl = feed_lbl
	_feed_dock.add_child(feed_lbl)
	_feed_dock.add_child(PanelTheme.make_hud_chip_divider())
	_feed_btns.clear()
	var compact: bool = _is_mobile()
	for i in UiIcons.FEED_SUBTYPE_KEYS.size():
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(56 if compact else 0, PanelTheme._button_min_height() - 4)
		var food_id: String = UiIcons.FEED_SUBTYPE_KEYS[i]
		UiIcons.apply_feed_button(btn, food_id, i == _feed_subtype, compact)
		var idx: int = i
		btn.pressed.connect(func(): _set_feed_subtype(idx))
		_feed_dock.add_child(btn)
		_feed_btns.append(btn)
	var spacer_idx: int = hbox.get_node("Spacer").get_index()
	hbox.add_child(_feed_dock)
	hbox.move_child(_feed_dock, spacer_idx)
	_sync_feed_dock()


func _sync_feed_dock() -> void:
	if _feed_dock == null:
		return
	var show: bool = not _aquascape.is_active
	_feed_dock.visible = show
	var compact: bool = _is_mobile()
	for i in _feed_btns.size():
		UiIcons.apply_feed_button(
			_feed_btns[i], UiIcons.FEED_SUBTYPE_KEYS[i], i == _feed_subtype, compact)


func _pulse_feed_dock() -> void:
	if _feed_dock == null:
		return
	var tw := create_tween()
	tw.tween_property(_feed_dock, "modulate", Color(1.35, 1.22, 0.82, 1.0), 0.12)
	tw.tween_property(_feed_dock, "modulate", Color.WHITE, 0.35)


func _sync_feed_dock_visibility() -> void:
	_sync_feed_dock()


func _alert_fish_to_feed(hit: Vector3, food_subtype: int) -> int:
	if _sim == null:
		return 0
	var noticed: int = 0
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
		noticed += 1
	return noticed


func _maybe_feed_hint() -> void:
	if _feed_hint_shown or _aquascape.is_active or is_pond_mode() or _sim == null:
		return
	_feed_hint_shown = true
	_show_feed_toast("Choose food below · click the water to drop")


func _show_feed_toast(text: String) -> void:
	if _feed_toast_panel == null or not is_instance_valid(_feed_toast_panel):
		_feed_toast_panel = PanelContainer.new()
		_feed_toast_panel.name = "FeedToast"
		_feed_toast_panel.add_theme_stylebox_override("panel", PanelTheme.make_hud_cluster_style())
		_feed_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_feed_toast_panel.z_index = 80
		_feed_toast_panel.anchor_left = 0.5
		_feed_toast_panel.anchor_right = 0.5
		_feed_toast_panel.anchor_top = 1.0
		_feed_toast = Label.new()
		_feed_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		PanelTheme.apply_font(_feed_toast, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
		_feed_toast.add_theme_color_override("font_color", Color(0.98, 0.96, 0.82))
		_feed_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 12)
		pad.add_theme_constant_override("margin_right", 12)
		pad.add_theme_constant_override("margin_top", 6)
		pad.add_theme_constant_override("margin_bottom", 6)
		pad.add_child(_feed_toast)
		_feed_toast_panel.add_child(pad)
		add_child(_feed_toast_panel)
	_layout_feed_toast()
	if _feed_toast_tween != null and is_instance_valid(_feed_toast_tween):
		_feed_toast_tween.kill()
	_feed_toast.text = text
	_feed_toast_panel.modulate.a = 1.0
	_feed_toast_panel.visible = true
	_layout_feed_toast()
	_feed_toast_tween = create_tween()
	_feed_toast_tween.tween_interval(2.6)
	_feed_toast_tween.tween_property(_feed_toast_panel, "modulate:a", 0.0, 0.6)


func _layout_feed_toast() -> void:
	if _feed_toast_panel == null or not is_instance_valid(_feed_toast_panel):
		return
	var inset: float = _hud_bottom_inset() + 36.0
	_feed_toast_panel.offset_left = -220.0
	_feed_toast_panel.offset_right = 220.0
	_feed_toast_panel.offset_top = -(inset + 34.0)
	_feed_toast_panel.offset_bottom = -inset


func _fade_in_from_black() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color.BLACK
	add_child(overlay)
	overlay.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(overlay.queue_free)


# ---- Time controls + photo mode ----

func _handle_shortcut(key: int, action: Callable) -> void:
	var pressed: bool = Input.is_key_pressed(key)
	var was: bool = _key_was_pressed.get(key, false)
	if pressed and not was:
		action.call()
	_key_was_pressed[key] = pressed


func _typing_focus_in_ui() -> bool:
	return PanelTheme.typing_focus_in_ui(get_viewport())


func _keeper_input_active() -> bool:
	return _keeper_say_edit != null and is_instance_valid(_keeper_say_edit) \
			and _keeper_say_edit.has_focus()


func _prepare_panel_open() -> void:
	_close_rail_flyout()
	_close_chip_popups()


func _close_rail_flyout() -> bool:
	if _rail_flyout != null and _rail_flyout.visible:
		_rail_flyout.visible = false
		return true
	return false


func _close_residents_panel() -> void:
	if _residents_panel == null:
		return
	_residents_panel.visible = false
	if _residents_panel.has_method("_hide_panel"):
		_residents_panel.call("_hide_panel")


func _close_camera_views_panel() -> void:
	if _camera_views_panel == null:
		return
	_camera_views_panel.visible = false


func _click_hits_interactive_hud(mouse_pos: Vector2) -> bool:
	if _ui_panels != null and _ui_panels.is_modal_open():
		return true
	for panel in [settings_panel, render_panel, sound_panel, library_panel,
			creature_creator_panel, fish_store_panel, _notifications_panel,
			_light_panel, _residents_panel, _camera_views_panel]:
		if panel != null and panel.visible \
				and panel.get_global_rect().has_point(mouse_pos):
			return true
	if _rail_flyout != null and _rail_flyout.visible \
			and _rail_flyout.get_global_rect().has_point(mouse_pos):
		return true
	if _follow_thought_strip != null and _follow_thought_strip.visible \
			and _follow_thought_strip.get_global_rect().has_point(mouse_pos):
		return true
	if _cheat_sheet != null and is_instance_valid(_cheat_sheet) \
			and _cheat_sheet.get_global_rect().has_point(mouse_pos):
		return true
	if footer_bar != null and footer_bar.visible \
			and footer_bar.get_global_rect().has_point(mouse_pos):
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
	_sync_viewport_update_mode(_aquascape.is_active)
	_sync_speed_hud()
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
	_sync_viewport_update_mode(_aquascape.is_active)
	_sync_speed_hud()
	_haptic(12)


func _on_one() -> void:
	if _aquascape.is_active:
		_aquascape.snap_camera("top")
	else:
		_set_time_scale(1.0)


func _on_two() -> void:
	if _aquascape.is_active:
		_aquascape.snap_camera("front")
	else:
		_set_time_scale(4.0)


func _on_three() -> void:
	if _aquascape.is_active:
		_aquascape.snap_camera("side")
	else:
		_set_time_scale(16.0)


func _on_four() -> void:
	if _aquascape.is_active:
		_aquascape.snap_camera("three_quarter")


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


func _take_signature_shot() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		AestheticsRuntime.apply_signature_shot(cfg, _sim)
		_apply_render_config()
	if world != null and world.has_method("begin_screenshot_boost"):
		world.begin_screenshot_boost(4.0)
	_set_hud_visible_for_photo(false)
	get_tree().create_timer(0.06).timeout.connect(
		func(): _request_viewport_image(_finish_photo_with_hud_restore))


func _set_hud_visible_for_photo(visible: bool) -> void:
	if top_hud != null:
		top_hud.visible = visible
	if right_rail != null:
		right_rail.visible = visible
	if footer_bar != null:
		footer_bar.visible = visible


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
		if not is_pond_mode():
			apply_pond_mode(true)
		var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		_timelapse_dir = OS.get_user_data_dir() + "/captures/pond_timelapse_" + ts
		DirAccess.make_dir_recursive_absolute(_timelapse_dir)
		_timelapse_index = 0
		_timelapse_accum = 0.0
		_timelapse_active = true
		print_verbose("[walstad_loom] timelapse started: ", _timelapse_dir)


# ---- Dance moment capture (Sound Studio) ----
var _dance_capture_active: bool = false
var _dance_capture_dir: String = ""
var _dance_capture_index: int = 0
var _dance_capture_accum: float = 0.0
const DANCE_CAPTURE_INTERVAL: float = 0.1
const DANCE_CAPTURE_FRAMES: int = 20


func capture_dance_moment() -> void:
	if _dance_capture_active:
		return
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_dance_capture_dir = OS.get_user_data_dir() + "/captures/dance_" + ts
	DirAccess.make_dir_recursive_absolute(_dance_capture_dir)
	_dance_capture_index = 0
	_dance_capture_accum = 0.0
	_dance_capture_active = true
	var world_node := get_node_or_null("SubViewport/World")
	if world_node != null and world_node.has_method("begin_screenshot_boost"):
		world_node.begin_screenshot_boost(3.0)
	_set_hud_visible_for_photo(false)
	_request_viewport_image(_save_dance_hero)


func _save_dance_hero(img: Image) -> void:
	if img == null:
		return
	var path: String = _dance_capture_dir + "/hero.png"
	img.save_png(path)
	print_verbose("[walstad_loom] dance hero saved: ", path)


func _save_dance_frame(img: Image, frame_path: String) -> void:
	if img != null:
		img.save_png(frame_path)


func _finish_dance_capture() -> void:
	_dance_capture_active = false
	_set_hud_visible_for_photo(true)
	print_verbose("[walstad_loom] dance capture done: ", _dance_capture_dir)
	_haptic(25)
	_show_photo_toast(_dance_capture_dir + "/hero.png")


# ---- Follow-cam ----

# Public follow API. One creature, one presentation mode. Used by the Residents
# panel, click/tap picking, cycling, and the portal toggle.
func follow_creature(creature: Node, mode: int = FollowMode.PIP) -> void:
	if creature == null or not is_instance_valid(creature) or not (creature is Node3D):
		return
	if _follow_target != creature:
		_clear_follow_thought_ui()
		_follow_inner_thought_last_line = ""
		_follow_inner_thought_cd = 0.0
	_follow_target = creature as Node3D
	_follow_mode = mode
	_auto_orbit = false
	if creature is Fish and _sim != null:
		var ai: Node = get_node_or_null("/root/AIDirector")
		if ai != null and ai.has_method("set_followed_fish"):
			ai.set_followed_fish(String(creature.id))
		MindScheduler.precache_for_fish(creature as Fish, _sim)
		if _sim.has_method("request_creature_thought"):
			var thought: String = String(_sim.request_creature_thought(creature, "follow")).strip_edges()
			var cfg := get_node_or_null("/root/TankConfig")
			if thought != "" and cfg != null and bool(cfg.effective_fish_thought_voice_enabled()):
				_show_follow_thought_typewriter(creature as Fish, _creature_display_name(creature), thought)
	if portal_container != null:
		portal_container.visible = (mode != FollowMode.OFF)
	_update_portal_pip()
	_sync_rail_toggles()
	follow_target_changed.emit(_follow_target)


# Switch how the current target is presented (PIP <-> CINEMATIC). No-op when
# nothing is being followed.
func set_follow_mode(mode: int) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	_follow_mode = mode
	if portal_container != null:
		portal_container.visible = (mode != FollowMode.OFF)
	_update_portal_pip()
	_sync_rail_toggles()


# Stop following entirely: clears the target and hides the portal + info panel.
func clear_follow() -> void:
	_follow_target = null
	_follow_mode = FollowMode.OFF
	_cinema_active = false
	_clear_follow_thought_ui()
	if portal_container != null:
		portal_container.visible = false
	_update_portal_pip()
	_sync_rail_toggles()
	follow_target_changed.emit(null)


# Manual camera control (presets, projection, pan) breaks a CINEMATIC follow but
# leaves a PIP overlay alone — the magnifier is independent of the main camera.
func _release_cinematic_follow() -> void:
	if _follow_mode == FollowMode.CINEMATIC:
		clear_follow()


# ESC handler — full stop (kept under the original bound name).
func _clear_follow() -> void:
	clear_follow()


# ---- Cycling through residents ----

func set_cycle_scope(scope: int) -> void:
	_cycle_scope = scope


func get_cycle_scope() -> int:
	return _cycle_scope


# Ordered roster that next/prev walks, filtered by the active scope.
func _cycle_pool() -> Array:
	if _sim == null or not _sim.has_method("living_creatures"):
		return []
	var all: Array = _sim.living_creatures()
	match _cycle_scope:
		CycleScope.FAVORITES:
			var favs: Array = []
			for c in all:
				if _sim.has_method("is_favorite") and _sim.is_favorite(c):
					favs.append(c)
			return favs
		CycleScope.SPECIES:
			if _follow_target == null or not is_instance_valid(_follow_target) \
					or _follow_target.get("species") == null:
				return all
			var sp: String = String(_follow_target.species)
			var same: Array = []
			for c in all:
				if c.get("species") != null and String(c.species) == sp:
					same.append(c)
			return same
		_:
			return all


# Advance follow to the next (+1) / previous (-1) creature in scope. Only acts
# while already following — arrow keys don't start a follow from nothing.
func cycle_follow(dir: int) -> void:
	if _follow_mode == FollowMode.OFF:
		return
	var pool: Array = _cycle_pool()
	if pool.is_empty():
		return
	var idx: int = pool.find(_follow_target)
	var n: int = pool.size()
	var next_idx: int = 0 if idx < 0 else (((idx + dir) % n) + n) % n
	follow_creature(pool[next_idx], _follow_mode)
	_haptic(8)


# A followed creature left the tank — hand off to the next one in scope (or stop)
# and let the player know who swam on.
func _on_creature_removed(c: Node) -> void:
	if c == null or not is_inside_tree():
		return
	# Memorial: a favorite has died — mark it even if we weren't following it.
	if _sim != null and _sim.has_method("is_favorite") and _sim.is_favorite(c):
		var fav_name: String = _creature_display_name(c)
		if has_method("_push_notification"):
			_push_notification("residents", "important", "In memoriam", "%s has passed on" % fav_name, true)
		if _sim.has_method("_note_ai_event"):
			_sim._note_ai_event("creature_died", "%s, a favorite, has died" % fav_name)
	# Follow handoff — only when the departed creature was the one we followed.
	if c != _follow_target:
		return
	var name_str: String = _creature_display_name(c)
	var nxt: Node = null
	for cand in _cycle_pool():
		if cand != c and is_instance_valid(cand):
			nxt = cand
			break
	if nxt != null:
		follow_creature(nxt, _follow_mode)
	else:
		clear_follow()
	if name_str != "" and has_method("_push_notification"):
		_push_notification("residents", "info", "Residents", "%s swam on" % name_str, true)


func _toggle_follow_favorite() -> void:
	if _sim == null or _follow_target == null or not is_instance_valid(_follow_target):
		return
	if _sim.has_method("toggle_favorite"):
		_sim.toggle_favorite(_follow_target)


func _toggle_follow_presentation() -> void:
	if _follow_target == null:
		return
	set_follow_mode(FollowMode.PIP if _follow_mode == FollowMode.CINEMATIC else FollowMode.CINEMATIC)


func _mouse_over_porthole() -> bool:
	if portal_container == null or not portal_container.visible:
		return false
	if portal_display == null or not portal_display.visible:
		return false
	return portal_display.get_global_rect().has_point(portal_display.get_global_mouse_position())


func _adjust_portal_zoom(factor: float) -> void:
	_portal_zoom = clampf(_portal_zoom * factor, PORTAL_ZOOM_MIN, PORTAL_ZOOM_MAX)
	if _portal_mat != null:
		_portal_mat.set_shader_parameter("zoom", _portal_zoom)


func _mouse_over_portal_card() -> bool:
	if portal_container == null or not portal_container.visible:
		return false
	return portal_container.get_global_rect().has_point(portal_container.get_global_mouse_position())


func _on_portal_name_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _follow_target != null:
		_prompt_rename(_follow_target)


# Small dialog to give a creature a custom name. Writes the instance field AND
# the saved genome so it survives a reload (fish/shrimp persist via genome,
# snail/clam via the instance field).
func _prompt_rename(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	if _rename_dialog == null:
		_rename_dialog = AcceptDialog.new()
		_rename_dialog.title = "Rename creature"
		_rename_dialog.ok_button_text = "Rename"
		_rename_edit = LineEdit.new()
		_rename_edit.custom_minimum_size = Vector2(260, 0)
		_rename_edit.max_length = 24
		_rename_dialog.add_child(_rename_edit)
		_rename_dialog.register_text_enter(_rename_edit)
		_rename_dialog.confirmed.connect(_on_rename_confirmed)
		add_child(_rename_dialog)
	_rename_target = creature
	_rename_edit.text = _creature_display_name(creature)
	_rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _on_rename_confirmed() -> void:
	if _rename_target == null or not is_instance_valid(_rename_target) or _rename_edit == null:
		return
	var nm: String = _rename_edit.text.strip_edges()
	if nm == "":
		return
	var old_nm: String = _creature_display_name(_rename_target)
	for k in ["fish_name", "shrimp_name", "snail_name", "clam_name"]:
		if _rename_target.get(k) != null:
			_rename_target.set(k, nm)
			var g: Variant = _rename_target.get("_saved_genome")
			if g is Dictionary:
				(g as Dictionary)[k] = nm
			break
	if _rename_target is Fish and _sim != null and _sim.has_method("append_fish_journal_entry"):
		var line: String = MakeItThere.naming_journal_line(old_nm, nm)
		if line != "":
			_sim.append_fish_journal_entry(_rename_target as Fish, line,
					PackedStringArray(["naming", "consecration"]))
			if is_instance_valid(_rename_target) and (_rename_target as Fish).has_method("pulse_affect_cue"):
				(_rename_target as Fish).pulse_affect_cue()
	if _portal_name_lbl != null and _rename_target == _follow_target:
		_portal_name_lbl.text = nm
	if _rename_target is Fish:
		KeeperInput.on_creature_named(_rename_target as Fish, nm)
	follow_target_changed.emit(_follow_target)


# Best display name for a creature (fish/shrimp/snail/clam), else a type label.
func _creature_display_name(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	for key in ["fish_name", "shrimp_name", "snail_name", "clam_name", "_display_name"]:
		if node.get(key) != null and String(node.get(key)) != "":
			return String(node.get(key))
	return _creature_label(node).capitalize()


func _make_portal_ctrl_btn(txt: String, tip: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 24)
	b.add_theme_font_size_override("font_size", 14)
	return b


# Keep a faint gold ★ floating above each favorited creature so you can spot
# them swimming. Driven by SimDriver.favorites_changed; the star is a billboarded
# fixed-size Label3D parented to the creature (so it tracks + survives its death
# via the parent's queue_free). No creature-script changes needed.
func _refresh_favorite_halos() -> void:
	if _sim == null or not _sim.has_method("favorite_creatures"):
		return
	var want: Dictionary = {}
	for c in _sim.favorite_creatures():
		if c is Node3D and is_instance_valid(c):
			want[c.get_instance_id()] = c
	# Drop halos for creatures that are no longer favorites (or are gone).
	for id in _fav_halos.keys():
		if not want.has(id):
			var h: Variant = _fav_halos[id]
			if is_instance_valid(h):
				h.queue_free()
			_fav_halos.erase(id)
	# Add a star for any newly favorited creature.
	for id in want:
		if _fav_halos.has(id):
			continue
		var c: Node3D = want[id]
		var star := Label3D.new()
		var is_g: bool = _sim.has_method("is_guardian_creature") \
			and _sim.is_guardian_creature(c)
		if is_g:
			star.text = "◆"
			star.modulate = Color(0.55, 0.88, 1.0)
		else:
			star.text = "★"
			star.modulate = Color(1.0, 0.85, 0.3)
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.fixed_size = true
		star.pixel_size = 0.0006
		star.outline_modulate = Color(0, 0, 0, 0.75)
		star.outline_size = 8
		star.position = Vector3(0.0, 0.55, 0.0)
		c.add_child(star)
		_fav_halos[id] = star


func _voice_ui_enabled() -> bool:
	var cfg := get_node_or_null("/root/TankConfig")
	return cfg == null or not bool(cfg.sentience_voice_off)


func _on_guardian_spoke(text: String, speaker: Fish, action: String) -> void:
	if not _voice_ui_enabled() or text.strip_edges() == "":
		return
	if speaker != null and is_instance_valid(speaker):
		_pulse_creature_affect(speaker)
	var nm: String = _creature_display_name(speaker) if speaker != null else "Tank voice"
	var important: bool = action in ["enable_autofeed", "drop_feed", "lost", "intro", "successor"]
	var line: String = text.strip_edges()
	if action == "refined" and line == _last_guardian_line_shown:
		return
	var sev: String = "important" if important else "info"
	var track_recap: bool = action == "away_recap"
	if action == "refined":
		_defer_voice_presentation(func() -> void:
			_present_guardian_toast(nm, line, sev, important, false)
			_last_guardian_line_shown = line, VOICE_BODY_FIRST_DELAY_S)
		return
	var delay: float = VOICE_TEMPLATE_DELAY_S
	_defer_voice_presentation(func() -> void:
		_present_guardian_toast(nm, line, sev, important, track_recap)
		_last_guardian_line_shown = line, delay)


func _on_guardian_recap_streaming(text: String) -> void:
	if not _voice_ui_enabled() or text.strip_edges() == "":
		return
	if _guardian_recap_toast_body != null and is_instance_valid(_guardian_recap_toast_body):
		_guardian_recap_toast_body.text = text.strip_edges()


func _present_guardian_toast(title: String, body: String, severity: String,
		important: bool, track_recap: bool) -> void:
	if not has_method("_push_notification"):
		return
	_guardian_recap_toast_body = null
	if track_recap:
		_push_notification("guardian", severity, title, body, important)
		if _notifications_toast_layer != null and _notifications_toast_layer.get_child_count() > 0:
			var card: Node = _notifications_toast_layer.get_child(
					_notifications_toast_layer.get_child_count() - 1)
			if card is PanelContainer:
				var lbl: Label = _find_toast_body_label(card as PanelContainer)
				if lbl != null:
					_guardian_recap_toast_body = lbl
	else:
		_push_notification("guardian", severity, title, body, important)


func _find_toast_body_label(card: PanelContainer) -> Label:
	for c in card.get_children():
		if c is VBoxContainer:
			for ch in (c as VBoxContainer).get_children():
				if ch is Label and (ch as Label).get_index() == 1:
					return ch as Label
	return null


func _on_fish_thought_spoke(speaker: Fish, text: String) -> void:
	if text.strip_edges() == "" or speaker == null:
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and not bool(cfg.effective_fish_thought_voice_enabled()):
		if is_instance_valid(speaker) and speaker.has_method("answer_affect_cue"):
			speaker.answer_affect_cue("gaze_lock")
		return
	if not _voice_ui_enabled():
		return
	if is_instance_valid(speaker):
		_pulse_creature_affect(speaker)
	var fish_id: String = String(speaker.id) if speaker != null else ""
	var nm: String = _creature_display_name(speaker)
	var line: String = text.strip_edges()
	var follow_this: bool = _follow_target == speaker and is_instance_valid(speaker)
	_defer_voice_presentation(func() -> void:
		var sp: Fish = _fish_by_id(fish_id)
		if follow_this and sp != null:
			var is_reply: bool = MindConversation.session_active(sp)
			_show_follow_thought_typewriter(sp, nm, line, is_reply)
		elif has_method("_push_notification"):
			_push_notification("fish_thought", "info", nm, line, false), VOICE_BODY_FIRST_DELAY_S)


func _on_fish_thought_streaming(fish_id: String, partial: String, situation: String) -> void:
	if situation != "keeper_reply" or partial.strip_edges() == "":
		return
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	if String(_follow_target.id) != fish_id:
		return
	if _follow_thought_strip_body != null and _follow_thought_strip != null:
		_follow_thought_strip.visible = true
		_follow_thought_strip_body.text = partial.strip_edges()
		_follow_thought_tw_full = partial.strip_edges()
		_follow_thought_tw_idx = partial.length()
		_layout_follow_thought_strip()


func _pulse_creature_affect(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	if creature.has_method("pulse_affect_cue"):
		creature.pulse_affect_cue()
		return


func _defer_voice_presentation(show_fn: Callable, delay_s: float = VOICE_BODY_FIRST_DELAY_S) -> void:
	var tree := get_tree()
	if tree == null:
		if show_fn.is_valid():
			show_fn.call()
		return
	var wait_s: float = maxf(delay_s, 0.05)
	tree.create_timer(wait_s).timeout.connect(func() -> void:
		if show_fn.is_valid():
			show_fn.call()
	, CONNECT_ONE_SHOT)


func _fish_by_id(fish_id: String) -> Fish:
	if _sim == null or fish_id == "":
		return null
	for f in _sim.fish:
		if is_instance_valid(f) and f is Fish and String(f.id) == fish_id:
			return f
	return null


func _maybe_show_sentience_intro() -> void:
	if not _voice_ui_enabled():
		return
	if bool(OnboardingLegibility.global_pref("sentience_north_star_seen", false)):
		_maybe_show_mind_upgrade_toast()
		return
	OnboardingLegibility.set_global_pref("sentience_north_star_seen", true)
	call_deferred("_show_sentience_north_star_modal")


func _maybe_show_mind_upgrade_toast() -> void:
	var seen_ver: int = int(OnboardingLegibility.global_pref("mind_system_version_seen", 0))
	if seen_ver >= MindNarrator.MIND_SYSTEM_VERSION:
		return
	OnboardingLegibility.set_global_pref("mind_system_version_seen",
			MindNarrator.MIND_SYSTEM_VERSION)
	var msg: String = MindNarrator.mind_upgrade_message(seen_ver,
			MindNarrator.MIND_SYSTEM_VERSION)
	if msg != "" and has_method("_push_notification"):
		_push_notification("mind_upgrade", "info", "The tank", msg, false)


func _show_sentience_north_star_modal() -> void:
	if _guardian_consent_layer != null and is_instance_valid(_guardian_consent_layer):
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_size(vp_size)
	add_child(backdrop)
	_guardian_consent_layer = backdrop
	var modal: PanelContainer = GuardianMindOnboarding.open_in(backdrop,
			GuardianMindOnboarding.Mode.NORTH_STAR)
	modal.closed.connect(func(_accepted: bool) -> void:
		if is_instance_valid(backdrop):
			backdrop.queue_free()
		_guardian_consent_layer = null
		_maybe_show_mind_upgrade_toast())


func _on_fish_voiced_wake(f: Fish) -> void:
	if f == null or not is_instance_valid(f):
		return
	var nm: String = _creature_display_name(f)
	if _onboarding != null and _onboarding.has_method("show_voiced_wake"):
		_onboarding.show_voiced_wake(nm)
	elif has_method("_push_notification"):
		_push_notification("voiced_wake", "info", nm,
				"This fish thinks aloud now — follow or tap to overhear.", false)


func _build_follow_thought_ui() -> void:
	if _follow_thought_strip != null:
		return
	_follow_thought_strip = PanelContainer.new()
	_follow_thought_strip.name = "FollowThoughtStrip"
	_follow_thought_strip.visible = false
	_follow_thought_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow_thought_strip.z_index = 97
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.14, 0.88)
	style.border_color = Color(0.42, 0.62, 0.88, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_follow_thought_strip.add_theme_stylebox_override("panel", style)
	add_child(_follow_thought_strip)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_follow_thought_strip.add_child(vb)
	_follow_thought_strip_name = Label.new()
	_follow_thought_strip_name.text = ""
	PanelTheme.as_serif(_follow_thought_strip_name, PanelTheme.SIZE_CAPTION, true)
	_follow_thought_strip_name.add_theme_color_override("font_color", Color8(255, 215, 130))
	_follow_thought_strip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_follow_thought_strip_name)
	_follow_thought_strip_body = Label.new()
	_follow_thought_strip_body.text = ""
	_follow_thought_strip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.as_serif_italic(_follow_thought_strip_body, PanelTheme.SIZE_BODY)
	_follow_thought_strip_body.add_theme_color_override("font_color", Color8(220, 232, 248))
	_follow_thought_strip_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_follow_thought_strip_body)
	_keeper_say_edit = LineEdit.new()
	_keeper_say_edit.placeholder_text = "say something… (Enter to send)"
	_keeper_say_edit.tooltip_text = (
		"Gamified bond: steady the tank first, then they open up. "
		+ "Comfort words (safe, calm, hello) soothe wary fish. "
		+ "The guardian fish can advise on tank care when things are rough. "
		+ "Press Enter to send.")
	_keeper_say_edit.max_length = 120
	_keeper_say_edit.visible = false
	_keeper_say_edit.text_submitted.connect(_on_keeper_say_submitted)
	_keeper_say_edit.focus_exited.connect(_on_keeper_say_focus_exited)
	PanelTheme.as_sans(_keeper_say_edit, PanelTheme.SIZE_BODY)
	vb.add_child(_keeper_say_edit)
	_keeper_ack_label = Label.new()
	_keeper_ack_label.text = ""
	_keeper_ack_label.visible = false
	_keeper_ack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.as_serif_italic(_keeper_ack_label, PanelTheme.SIZE_CAPTION)
	_keeper_ack_label.add_theme_color_override("font_color", Color8(120, 145, 135))
	_keeper_ack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_keeper_ack_label)


func _on_keeper_say_submitted(text: String) -> void:
	_submit_keeper_line(text)


func _on_keeper_say_focus_exited() -> void:
	if _keeper_say_edit == null:
		return
	_submit_keeper_line(_keeper_say_edit.text)
	_pump_notification_toast_queue()


func _submit_keeper_line(raw: String) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target) or not (_follow_target is Fish):
		return
	var line: String = raw.strip_edges()
	if line == "":
		return
	var f: Fish = _follow_target as Fish
	var result: Dictionary = KeeperInput.submit_to_fish(f, line, _sim)
	if not bool(result.get("ok", false)):
		var reason_line: String = KeeperInput.ui_ack_line(result, f.fish_name, _sim, f)
		if reason_line != "":
			_show_keeper_ack(reason_line)
		return
	MindConversation.on_keeper_submit(f, line, _sim, result)
	if _keeper_say_edit != null:
		_keeper_say_edit.text = ""
	var ack: String = KeeperInput.ui_ack_line(result, f.fish_name, _sim, f)
	if bool(result.get("is_guardian_advisor", false)):
		var advisor: String = KeeperCare.guardian_advisor_line(f, _sim)
		if advisor != "":
			ack = advisor if ack == "" else "%s · %s" % [ack, advisor]
	elif _sim != null:
		var interject: String = KeeperCare.maybe_guardian_interject(_sim, f)
		if interject != "":
			ack = "%s · %s" % [ack, interject]
			if _sim.has_method("append_fish_journal_entry"):
				var g: Fish = _sim._find_guardian_fish() if _sim.has_method("_find_guardian_fish") else null
				if g != null:
					_sim.append_fish_journal_entry(g, interject, PackedStringArray(["advisor", "tank_care"]))
	_show_keeper_ack(ack)
	MindDebug.log_stream(f, "keeper → %s" % str(result.get("text", line)))
	if _sim != null and _sim.has_method("request_keeper_reply"):
		_sim.request_keeper_reply(f, result)
	elif f.has_method("pulse_affect_cue"):
		f.pulse_affect_cue()
	if not bool(result.get("too_wary", false)):
		f._keeper_message_salience = maxf(float(f._keeper_message_salience), 0.48)


func _show_keeper_you_said(text: String) -> void:
	_show_keeper_ack(text)


func _show_keeper_ack(text: String) -> void:
	if _keeper_ack_label == null:
		return
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		return
	_keeper_ack_label.text = trimmed
	_keeper_ack_label.visible = true
	_keeper_ack_t = 6.5
	_layout_follow_thought_strip()


func _tick_keeper_input(dt: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target) or not (_follow_target is Fish):
		if _keeper_say_edit != null:
			_keeper_say_edit.visible = false
		return
	var f: Fish = _follow_target as Fish
	if _keeper_say_edit != null:
		_keeper_say_edit.visible = KeeperInput.ears_enabled()
		if _keeper_say_edit.visible:
			_keeper_say_edit.placeholder_text = KeeperCare.placeholder_for_fish(f, _sim)
	if _keeper_ack_t > 0.0:
		_keeper_ack_t = maxf(0.0, _keeper_ack_t - dt)
		if _keeper_ack_t <= 0.0 and _keeper_ack_label != null:
			_keeper_ack_label.visible = false
			_keeper_ack_label.text = ""
	var cam_still: bool = false
	if _follow_mode == FollowMode.CINEMATIC:
		cam_still = target.distance_squared_to(_keeper_cam_prev) < 0.0004
		_keeper_cam_prev = target
	KeeperInput.tick_gaze(f, dt, cam_still)
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var cursor_speed: float = mouse.distance_to(_keeper_cursor_prev) / maxf(dt, 0.001)
	_keeper_cursor_prev = mouse
	var cam: Camera3D = sub_viewport.get_camera_3d() if sub_viewport != null else null
	if cam != null:
		var screen: Vector2 = cam.unproject_position(f.global_position)
		if mouse.distance_to(screen) < 72.0:
			KeeperInput.cursor_near_fish_id = str(f.id)
			KeeperInput.cursor_speed = cursor_speed
		elif KeeperInput.cursor_near_fish_id == str(f.id):
			KeeperInput.cursor_near_fish_id = ""
			KeeperInput.cursor_speed = 0.0


func _layout_follow_thought_strip() -> void:
	if _follow_thought_strip == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bottom: float = _hud_bottom_inset()
	var edge: float = PanelTheme.EDGE_MARGIN
	var left_pad: float = edge + 8.0
	if _residents_panel != null and _residents_panel.visible:
		left_pad = maxf(left_pad, _residents_panel.size.x + edge + 12.0)
	var strip_w: float = clampf(vp.x * 0.38, 300.0, 420.0)
	var strip_h: float = 92.0
	if _follow_thought_strip_body != null and _follow_thought_strip_body.text != "":
		var line_h: float = float(PanelTheme.scaled_size(PanelTheme.SIZE_BODY)) + 6.0
		var lines: int = maxi(1, _follow_thought_strip_body.get_line_count())
		strip_h = maxf(92.0, float(lines) * line_h + 40.0)
	if _keeper_ack_label != null and _keeper_ack_label.visible:
		strip_h = 118.0
	var toast_clearance: float = 0.0
	if _notification_toast_active > 0 and not _keeper_input_active():
		toast_clearance = PanelTheme.TOAST_STACK_H + 10.0
	_follow_thought_strip.anchor_left = 0.0
	_follow_thought_strip.anchor_top = 1.0
	_follow_thought_strip.anchor_right = 0.0
	_follow_thought_strip.anchor_bottom = 1.0
	_follow_thought_strip.offset_left = left_pad
	_follow_thought_strip.offset_right = left_pad + strip_w
	_follow_thought_strip.offset_bottom = -(bottom + 10.0 + toast_clearance)
	_follow_thought_strip.offset_top = -(bottom + 10.0 + strip_h + toast_clearance)


func _clear_follow_thought_ui() -> void:
	_follow_thought_tw_gen += 1
	_follow_thought_tw_full = ""
	_follow_thought_tw_idx = 0
	if _follow_thought_symbol != null and is_instance_valid(_follow_thought_symbol):
		_follow_thought_symbol.queue_free()
	_follow_thought_symbol = null
	if _follow_thought_strip != null:
		_follow_thought_strip.visible = false
	if _follow_thought_strip_body != null:
		_follow_thought_strip_body.text = ""
	if _follow_thought_strip_name != null:
		_follow_thought_strip_name.text = ""
	if _keeper_ack_label != null:
		_keeper_ack_label.visible = false
		_keeper_ack_label.text = ""
	_keeper_ack_t = 0.0


func _ensure_follow_thought_symbol(speaker: Fish) -> void:
	if speaker == null or not is_instance_valid(speaker):
		return
	if _follow_thought_symbol != null and is_instance_valid(_follow_thought_symbol) \
			and _follow_thought_symbol.get_parent() == speaker:
		return
	if _follow_thought_symbol != null and is_instance_valid(_follow_thought_symbol):
		_follow_thought_symbol.queue_free()
	_follow_thought_symbol = Label3D.new()
	_follow_thought_symbol.text = "…"
	_follow_thought_symbol.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_follow_thought_symbol.fixed_size = true
	_follow_thought_symbol.pixel_size = 0.0018
	_follow_thought_symbol.modulate = Color(0.75, 0.88, 1.0, 0.85)
	_follow_thought_symbol.outline_modulate = Color(0, 0, 0, 0.65)
	_follow_thought_symbol.outline_size = 8
	_follow_thought_symbol.position = Vector3(0.0, 0.78, 0.0)
	_follow_thought_symbol.font_size = 28
	speaker.add_child(_follow_thought_symbol)
	_follow_thought_symbol.visible = false


func _pulse_follow_thought_symbol() -> void:
	if _follow_thought_symbol == null or not is_instance_valid(_follow_thought_symbol):
		return
	_follow_thought_symbol.visible = true
	_follow_thought_symbol.modulate.a = 0.35
	var tw := create_tween()
	tw.tween_property(_follow_thought_symbol, "modulate:a", 0.92, 0.18)
	tw.tween_property(_follow_thought_symbol, "modulate:a", 0.72, 0.55)


func _show_follow_thought_typewriter(speaker: Fish, speaker_name: String, text: String,
		is_reply: bool = false) -> void:
	if _follow_target != speaker or not is_instance_valid(speaker):
		return
	var line: String = text.strip_edges()
	if line == "":
		_clear_follow_thought_ui()
		return
	_ensure_follow_thought_symbol(speaker)
	_pulse_follow_thought_symbol()
	if _follow_thought_strip == null:
		_build_follow_thought_ui()
	_layout_follow_thought_strip()
	_follow_thought_strip_name.text = speaker_name if not is_reply else "— %s" % speaker_name
	_follow_thought_tw_full = line
	_follow_thought_tw_idx = 0
	_follow_thought_tw_gen += 1
	var gen: int = _follow_thought_tw_gen
	_follow_thought_strip_body.text = ""
	_follow_thought_strip.visible = true
	_follow_thought_strip.modulate.a = 0.0
	_follow_inner_thought_last_line = line
	_follow_inner_thought_cd = FOLLOW_INNER_THOUGHT_INTERVAL_S
	var fade := create_tween()
	fade.tween_property(_follow_thought_strip, "modulate:a", 1.0, 0.22)
	_follow_thought_typewriter_step(gen)


func _follow_thought_typewriter_step(gen: int) -> void:
	if gen != _follow_thought_tw_gen:
		return
	if _follow_thought_strip_body == null:
		return
	if _follow_thought_tw_idx >= _follow_thought_tw_full.length():
		_layout_follow_thought_strip()
		return
	_follow_thought_tw_idx += 1
	_follow_thought_strip_body.text = _follow_thought_tw_full.substr(0, _follow_thought_tw_idx)
	if _follow_thought_tw_idx >= _follow_thought_tw_full.length():
		_layout_follow_thought_strip()
	var delay: float = FOLLOW_THOUGHT_CHAR_S
	var ch: String = _follow_thought_tw_full.substr(_follow_thought_tw_idx - 1, 1)
	if ch in [".", ",", "!", "?", ";", ":"]:
		delay *= 2.6
	elif ch == " ":
		delay *= 0.55
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(delay).timeout.connect(
			func() -> void: _follow_thought_typewriter_step(gen), CONNECT_ONE_SHOT)


func _tick_follow_inner_thoughts(dt: float) -> void:
	if _follow_mode == FollowMode.OFF or _sim == null:
		return
	if _follow_target == null or not is_instance_valid(_follow_target) or not (_follow_target is Fish):
		return
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.effective_fish_thought_voice_enabled()):
		return
	if _follow_thought_tw_full != "" and _follow_thought_tw_idx < _follow_thought_tw_full.length():
		return
	_follow_inner_thought_cd -= dt
	if _follow_inner_thought_cd > 0.0:
		return
	_follow_inner_thought_cd = FOLLOW_INNER_THOUGHT_INTERVAL_S
	var f: Fish = _follow_target as Fish
	var bucket: int = int(Time.get_unix_time_from_system() / int(FOLLOW_INNER_THOUGHT_INTERVAL_S))
	var thought: String = String(_sim.request_creature_thought(f, "follow_%d" % bucket)).strip_edges()
	if thought == "" or thought == _follow_inner_thought_last_line:
		return
	_show_follow_thought_typewriter(f, _creature_display_name(f), thought)


func _ensure_workspace_inspector() -> void:
	if _workspace_inspector != null and is_instance_valid(_workspace_inspector):
		return
	_workspace_inspector = Label.new()
	_workspace_inspector.visible = false
	_workspace_inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace_inspector.custom_minimum_size = Vector2(360, 200)
	_workspace_inspector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PanelTheme.apply_font(_workspace_inspector, PanelTheme.FONT_MONO, PanelTheme.SIZE_CAPTION)
	_workspace_inspector.add_theme_color_override("font_color", Color(0.85, 0.95, 0.88, 0.92))
	add_child(_workspace_inspector)


func _tick_workspace_inspector(dt: float) -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	var show_panel: bool = OS.is_debug_build()
	if cfg != null and cfg.get("inner_life_panel") != null:
		show_panel = bool(cfg.inner_life_panel)
	if not show_panel:
		if _workspace_inspector != null and is_instance_valid(_workspace_inspector):
			_workspace_inspector.visible = false
		return
	_ensure_workspace_inspector()
	if _follow_target == null or not is_instance_valid(_follow_target) or not (_follow_target is Fish):
		_workspace_inspector.visible = false
		return
	_workspace_inspector_accum += dt
	if _workspace_inspector_accum < 0.25:
		return
	_workspace_inspector_accum = 0.0
	var f: Fish = _follow_target as Fish
	MindDebug.set_inspector_fish(f)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(MindDebug.inspector_text(f))
	if f.get("_spark_signals") is Dictionary:
		var sig: Dictionary = f._spark_signals as Dictionary
		lines.append("affect v=%.2f a=%.2f · φ=%.2f" % [
			float(sig.get("valence", 0.0)), float(sig.get("arousal", 0.0)),
			float(sig.get("phi_proxy", 0.0))])
	var stream: PackedStringArray = MindDebug.stream_log()
	if stream.size() > 0:
		lines.append("--- stream ---")
		for i in range(maxi(0, stream.size() - 4), stream.size()):
			lines.append(stream[i])
	_workspace_inspector.text = "\n".join(lines)
	_workspace_inspector.position = Vector2(12, 12)
	_workspace_inspector.visible = true


func _ensure_perf_hud() -> void:
	if _perf_hud != null and is_instance_valid(_perf_hud):
		return
	_perf_hud = Label.new()
	_perf_hud.visible = false
	_perf_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PanelTheme.apply_font(_perf_hud, PanelTheme.FONT_MONO, PanelTheme.SIZE_CAPTION)
	_perf_hud.add_theme_color_override("font_color", Color(0.75, 0.88, 0.78, 0.85))
	add_child(_perf_hud)


func _tick_perf_hud(_dt: float) -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.get("perf_hud_enabled") if cfg.get("perf_hud_enabled") != null else false):
		if _perf_hud != null and is_instance_valid(_perf_hud):
			_perf_hud.visible = false
		return
	_ensure_perf_hud()
	var fish_n: int = _sim.fish.size() if _sim != null else 0
	var draw_n: int = floori(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_perf_hud.text = PerfGovernor.hud_line(fish_n, draw_n)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_perf_hud.position = Vector2(vp.x - 420.0, 8.0)
	_perf_hud.visible = true



func _on_guardian_llm_status(message: String) -> void:
	if message.strip_edges() == "":
		return
	var low: String = message.to_lower()
	if low.contains("download"):
		_push_notification("guardian_llm", NOTIF_SEVERITY_INFO, "Guardian mind", message, false)
	elif low.contains("error"):
		_push_notification("guardian_llm", NOTIF_SEVERITY_IMPORTANT, "Guardian mind", message, false)


func _on_guardian_consent_required(needs_download: bool) -> void:
	if _guardian_consent_layer != null and is_instance_valid(_guardian_consent_layer):
		return
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_size(vp_size)
	add_child(backdrop)
	_guardian_consent_layer = backdrop
	var mode: int = GuardianMindOnboarding.Mode.DOWNLOAD if needs_download \
			else GuardianMindOnboarding.Mode.BUNDLED_INFO
	var modal: PanelContainer = GuardianMindOnboarding.open_in(backdrop, mode)
	modal.closed.connect(func(accepted: bool) -> void:
		if is_instance_valid(backdrop):
			backdrop.queue_free()
		_guardian_consent_layer = null
		if needs_download:
			glm.on_consent_result(accepted)
		else:
			glm.on_bundled_info_dismissed())


# Human-readable "what is this creature doing right now", from its state machine.
func creature_activity_label(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node is Fish:
		var fa := ["Cruising", "Foraging", "Courting", "Spawning", "Fleeing", "Resting"]
		var m: int = int(node.current_mode)
		return fa[m] if m >= 0 and m < fa.size() else ""
	if node is Shrimp:
		var sa := ["Wandering", "Scavenging", "Climbing", "Nibbling", "Hunting", "Courting", "Resting", "Cleaning"]
		var m2: int = int(node.current_mode)
		return sa[m2] if m2 >= 0 and m2 < sa.size() else ""
	var scr: Script = node.get_script()
	var p: String = scr.resource_path if scr != null else ""
	if p.ends_with("clam.gd") and node.get("current_mode") != null:
		var ca := ["Resting", "Opening", "Filtering", "Closing"]
		var m3: int = int(node.current_mode)
		return ca[m3] if m3 >= 0 and m3 < ca.size() else ""
	if p.ends_with("snail.gd"):
		return "Grazing"  # snails have no state machine; they graze
	return ""


# A relationship blurb: a paired partner takes priority, else the strongest
# grudge (a rival), resolved to a living creature's name. "" if neither.
func _creature_relationship_line(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var partner_v: Variant = node.get("partner")
	if partner_v != null and is_instance_valid(partner_v):
		var pn: String = _creature_display_name(partner_v)
		if pn != "":
			return "♥ Paired with %s" % pn
	var grudges_v: Variant = node.get("grudges")
	if grudges_v is Dictionary and not (grudges_v as Dictionary).is_empty():
		var best_id := ""
		var best_t := 0.0
		for gid in (grudges_v as Dictionary):
			var tg: float = float((grudges_v as Dictionary)[gid])
			if tg > best_t:
				best_t = tg
				best_id = String(gid)
		var rival: Node = _find_creature_by_id(best_id)
		if rival != null:
			var rn: String = _creature_display_name(rival)
			if rn != "":
				return "⚔ Wary of %s" % rn
	return ""


func _find_creature_by_id(cid: String) -> Node:
	if _sim == null or not _sim.has_method("living_creatures") or cid == "":
		return null
	for c in _sim.living_creatures():
		if c.get("id") != null and String(c.id) == cid:
			return c
	return null


# A pulsing cyan ring on the followed creature so it's findable in the tank even
# outside the portal. Lives under `world`; repositioned + pulsed each frame.
# Subtle depth-of-field that focuses on the creature you're following, blurring
# the far layers so the eye locks onto the subject — a cinematic, intimate read.
# Disabled (and the blur eased off) when not following.
var _follow_cam_attr: CameraAttributesPractical = null
var _follow_dof_amount: float = 0.0


func _update_follow_dof() -> void:
	if camera == null:
		return
	var want: bool = _follow_mode != FollowMode.OFF and _follow_target != null \
		and is_instance_valid(_follow_target)
	# Opt-in: the follow depth-of-field is off unless the player enables it in
	# the Render panel. When disabled, `want` falls to false so any active blur
	# eases out and the camera attributes are cleared below.
	var cfg_dof := get_node_or_null("/root/TankConfig")
	if cfg_dof == null or not bool(cfg_dof.follow_depth_of_field):
		want = false
	# Ease the effect in/out so toggling follow doesn't pop the focus.
	_follow_dof_amount = lerpf(_follow_dof_amount, 1.0 if want else 0.0, 0.12)
	if _follow_dof_amount < 0.01 and not want:
		if _follow_cam_attr != null:
			_follow_cam_attr.dof_blur_far_enabled = false
			_follow_cam_attr.dof_blur_near_enabled = false
		return
	if _follow_cam_attr == null:
		_follow_cam_attr = CameraAttributesPractical.new()
	if camera.attributes != _follow_cam_attr:
		camera.attributes = _follow_cam_attr
	var dist: float = 6.0
	if want:
		dist = maxf(camera.global_position.distance_to(_follow_target.global_position), 0.5)
	var blur_strength: float = 0.06
	var far_soft: float = 2.0
	var near_soft: float = 1.6
	var focus_margin: float = 1.2
	var near_on: bool = true
	if cfg_dof != null:
		blur_strength = float(cfg_dof.follow_dof_blur_strength)
		far_soft = float(cfg_dof.follow_dof_far_softness)
		near_soft = float(cfg_dof.follow_dof_near_softness)
		focus_margin = float(cfg_dof.follow_dof_focus_margin)
		near_on = bool(cfg_dof.follow_dof_near_enabled)
	_follow_cam_attr.dof_blur_far_enabled = true
	_follow_cam_attr.dof_blur_far_distance = dist + focus_margin
	_follow_cam_attr.dof_blur_far_transition = far_soft
	_follow_cam_attr.dof_blur_near_enabled = near_on
	_follow_cam_attr.dof_blur_near_distance = maxf(dist - focus_margin * 1.15, 0.2)
	_follow_cam_attr.dof_blur_near_transition = near_soft
	_follow_cam_attr.dof_blur_amount = blur_strength * _follow_dof_amount

	# Per-fish audio presence: pan the aquatic ambience toward where the
	# followed creature sits on screen, so the Portal cam feels intimate.
	var audio := get_node_or_null("AmbientAudio")
	if audio != null and audio.has_method("set_presence_pan"):
		if want and not camera.is_position_behind(_follow_target.global_position):
			var sp: Vector2 = camera.unproject_position(_follow_target.global_position)
			var vw: float = maxf(float(sub_viewport.size.x), 1.0)
			audio.set_presence_pan(clampf((sp.x / vw) * 2.0 - 1.0, -1.0, 1.0) * _follow_dof_amount)
		else:
			audio.set_presence_pan(0.0)


func _update_follow_reticle(dt: float) -> void:
	var on: bool = _follow_mode != FollowMode.OFF and _follow_target != null \
		and is_instance_valid(_follow_target)
	if not on:
		if _follow_reticle != null and is_instance_valid(_follow_reticle):
			_follow_reticle.visible = false
		return
	if _follow_reticle == null or not is_instance_valid(_follow_reticle):
		if world == null or not is_instance_valid(world):
			return
		_follow_reticle = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.46
		torus.outer_radius = 0.56
		_follow_reticle.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.35, 0.9, 1.0, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.9, 1.0)
		mat.emission_energy_multiplier = 1.4
		_follow_reticle.material_override = mat
		_follow_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_follow_reticle)
	_follow_reticle.visible = true
	_follow_reticle.global_position = _follow_target.global_position
	_reticle_phase += dt
	var pulse: float = 1.0 + 0.10 * sin(_reticle_phase * 3.0)
	_follow_reticle.scale = Vector3(pulse, pulse, pulse)


# SENTIENCE_THE_SPARK #70 — subtle halo on what the followed fish attends to.
func _update_attention_halo(dt: float) -> void:
	var show: bool = _follow_mode != FollowMode.OFF and _follow_target != null \
		and is_instance_valid(_follow_target) and _follow_target is Fish
	if not show:
		if _attention_halo != null and is_instance_valid(_attention_halo):
			_attention_halo.visible = false
		return
	var ff: Fish = _follow_target as Fish
	var focus: String = str(ff.attention_focus if ff.get("attention_focus") != null else "")
	var focus_pos: Vector3 = ff._interest_target if ff.get("_interest_target") is Vector3 else Vector3.ZERO
	if focus == "" or focus_pos.length_squared() < 0.04 \
			or focus_pos.distance_squared_to(ff.global_position) < 0.16:
		if _attention_halo != null and is_instance_valid(_attention_halo):
			_attention_halo.visible = false
		return
	if _attention_halo == null or not is_instance_valid(_attention_halo):
		if world == null or not is_instance_valid(world):
			return
		_attention_halo = MeshInstance3D.new()
		var disc := TorusMesh.new()
		disc.inner_radius = 0.22
		disc.outer_radius = 0.30
		_attention_halo.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.82, 0.35, 0.42)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.78, 0.28)
		mat.emission_energy_multiplier = 1.1
		_attention_halo.material_override = mat
		_attention_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_attention_halo)
	_attention_halo.visible = true
	_attention_halo.global_position = focus_pos
	_reticle_phase += dt
	var halo_pulse: float = 1.0 + 0.14 * sin(_reticle_phase * 4.2)
	_attention_halo.scale = Vector3(halo_pulse, halo_pulse, halo_pulse)


# Re-acquire and re-follow the saved creature after a tank load. Called by
# SaveManager.try_load once creatures are spawned (see save_manager.gd).
func restore_follow_from_save(d: Dictionary) -> void:
	var sim_d: Dictionary = d.get("sim", {})
	var fid: String = String(sim_d.get("followed_id", ""))
	if fid == "" or _sim == null or not _sim.has_method("living_creatures"):
		return
	set_cycle_scope(int(sim_d.get("cycle_scope", CycleScope.ALL)))
	var c: Node = _find_creature_by_id(fid)
	if c != null:
		follow_creature(c, int(sim_d.get("follow_mode", FollowMode.PIP)))


# Open the Library modal focused on the followed creature's species.
func view_followed_in_library() -> void:
	_open_followed_in_library(false)


# Open the Library on the followed creature's species, in lineage (tree) view.
func view_followed_lineage() -> void:
	_open_followed_in_library(true)


func _open_followed_in_library(tree: bool) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target) \
			or not _follow_target.has_method("get_saved_genome"):
		return
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or library_panel == null:
		return
	var key: String = ""
	if lib.has_method("species_key"):
		key = String(lib.species_key(_follow_target.get_saved_genome()))
	if _ui_panels != null:
		_ui_panels.open_modal(UiPanelManager.MODAL_LIBRARY)
	if library_panel.has_method("select_species"):
		library_panel.select_species(key, tree)


# Quick-jump the camera to the player's primary favorite (cinematic).
func follow_primary_favorite() -> void:
	if _sim == null or not _sim.has_method("primary_favorite_creature"):
		return
	var c: Node = _sim.primary_favorite_creature()
	if c != null and is_instance_valid(c):
		follow_creature(c, FollowMode.CINEMATIC)
		_haptic(10)


# Follow a random creature within the current cycle scope (the Residents shuffle).
func follow_random() -> void:
	var pool: Array = _cycle_pool()
	if pool.is_empty() and _sim != null and _sim.has_method("living_creatures"):
		pool = _sim.living_creatures()
	if pool.is_empty():
		return
	var pick: Node = pool[randi() % pool.size()]
	if pick == _follow_target and pool.size() > 1:
		pick = pool[(pool.find(_follow_target) + 1) % pool.size()]
	follow_creature(pick, _follow_mode if _follow_mode != FollowMode.OFF else FollowMode.PIP)
	_haptic(8)


# Copy the followed creature's genome as a shareable strain code to the clipboard.
func share_followed_strain() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target) \
			or not _follow_target.has_method("get_saved_genome"):
		return
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or not lib.has_method("encode_strain"):
		return
	var code: String = lib.encode_strain(_follow_target.get_saved_genome())
	if code == "":
		return
	DisplayServer.clipboard_set(code)
	if has_method("_push_notification"):
		_push_notification("residents", "info", "Strain copied",
			"%s's strain code is on your clipboard" % _creature_display_name(_follow_target), true)


func toggle_follow_lock() -> void:
	_follow_lock = not _follow_lock

func is_follow_lock() -> bool:
	return _follow_lock

func is_cinema_active() -> bool:
	return _cinema_active

func toggle_cinema_mode() -> void:
	set_cinema_mode(not _cinema_active)

# Auto-tour: cinematic-follow the first creature in scope, then advance every
# CINEMA_INTERVAL_S of no interaction (see _process + _notify_hud_input).
func set_cinema_mode(on: bool, auto: bool = false) -> void:
	_cinema_active = on
	_cinema_accum = 0.0
	_cinema_auto = on and auto
	if on:
		var pool: Array = _cycle_pool()
		if pool.is_empty() and _sim != null and _sim.has_method("living_creatures"):
			pool = _sim.living_creatures()
		if not pool.is_empty():
			follow_creature(pool[0], FollowMode.CINEMATIC)


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


func _subviewport_to_root_ui(sv_pos: Vector2) -> Vector2:
	# Inverse of _window_mouse_to_viewport — maps SubViewport pixels to root UI space.
	if display != null and sub_viewport != null and display.size.x > 1.0:
		var local: Vector2 = Vector2(
			clampf(sv_pos.x / float(sub_viewport.size.x), 0.0, 1.0) * display.size.x,
			clampf(sv_pos.y / float(sub_viewport.size.y), 0.0, 1.0) * display.size.y,
		)
		return display.get_global_rect().position + local
	if sub_viewport == null:
		return sv_pos
	var win_size: Vector2 = get_window().size
	var sv_size: Vector2 = Vector2(sub_viewport.size)
	if sv_size.x <= 0.0 or sv_size.y <= 0.0:
		return sv_pos
	return sv_pos * (win_size / sv_size)


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
	elif _follow_mode == FollowMode.PIP:
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
	if camera == null or portal_container == null:
		return
	if _follow_mode == FollowMode.OFF:
		portal_container.visible = false
		return
	portal_container.visible = true

	var target_node: Node3D = _follow_target
	var has_target: bool = target_node != null and is_instance_valid(target_node)

	# The porthole magnifier shows whenever we're following; it tracks the target
	# (or shows the whole tank while awaiting a pick).
	if portal_display != null:
		portal_display.visible = true
		if _portal_mat != null:
			if has_target and camera.is_inside_tree() and target_node.is_inside_tree() \
					and not camera.is_position_behind(target_node.global_position):
				var screen_pt: Vector2 = camera.unproject_position(target_node.global_position)
				_portal_mat.set_shader_parameter("center_uv", Vector2(
					screen_pt.x / float(sub_viewport.size.x),
					screen_pt.y / float(sub_viewport.size.y)))
				_portal_mat.set_shader_parameter("zoom", _portal_zoom)
			elif not has_target:
				_portal_mat.set_shader_parameter("center_uv", Vector2(0.5, 0.5))
	if portal_hint != null:
		portal_hint.visible = not has_target
	if _portal_lineage_lbl != null:
		_portal_lineage_lbl.visible = has_target
	if _portal_stats_lbl != null:
		_portal_stats_lbl.visible = has_target
	if not has_target:
		if _portal_relation_lbl != null:
			_portal_relation_lbl.visible = false
		if _portal_name_lbl != null:
			_portal_name_lbl.text = "Select a creature"
		return

	# Refresh the name / lineage / stats at ~10 Hz (the magnifier tracks every
	# frame above).
	_portal_label_skip = (_portal_label_skip + 1) % 6
	if _portal_label_skip == 0:
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
			var stable_key: String = c_name
			if target_node.get("id") != null and String(target_node.get("id")) != "":
				stable_key = String(target_node.get("id"))
			var epithet: String = CreatureNaming.epithet_for_personality(
					personality_v, stable_key)
			if epithet != "":
				c_name = "%s %s" % [c_name, epithet]
		if _portal_name_lbl.text != c_name:
			_portal_name_lbl.text = c_name

		# Reflect favorite + presentation state on the overlay buttons.
		if _portal_fav_btn != null:
			var is_fav: bool = _sim != null and _sim.has_method("is_favorite") and _sim.is_favorite(target_node)
			_portal_fav_btn.text = "★" if is_fav else "☆"
		if _portal_mode_btn != null:
			_portal_mode_btn.text = "🎬" if _follow_mode == FollowMode.CINEMATIC else "⛶"
		
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
			
		var act: String = creature_activity_label(target_node)
		var act_prefix: String = (act + " · ") if act != "" else ""
		_portal_stats_lbl.text = "%sAge: %s · Hunger: %d%%%s%s" % [act_prefix, age_str, hunger_pct, sex_str, sterile_str]
		# Relationships — partner or top rival, resolved to a living name.
		if _portal_relation_lbl != null:
			var rel: String = _creature_relationship_line(target_node)
			_portal_relation_lbl.text = rel
			_portal_relation_lbl.visible = rel != ""
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
	portal_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Frosted-glass background — a shaded ColorRect behind everything, sized to
	# the card by _relayout_portal. Added FIRST so it draws behind the content.
	_portal_glass_bg = ColorRect.new()
	_portal_glass_bg.name = "PortalGlass"
	_portal_glass_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portal_glass_bg.color = Color(1, 1, 1, 1)
	_portal_glass_mat = ShaderMaterial.new()
	_portal_glass_mat.shader = load("res://shaders/glass_panel.gdshader")
	_portal_glass_bg.material = _portal_glass_mat
	portal_container.add_child(_portal_glass_bg)

	# Card content holder (margins inside the glass). The scaffold lives here.
	_portal_info_panel = MarginContainer.new()
	_portal_info_panel.name = "PortalCard"
	_portal_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portal_container.add_child(_portal_info_panel)

	# Porthole: reuse the magnifier TextureRect, pulled out of its scene slot so
	# the scaffold can place it. The hint label rides on top of the circle.
	if portal_display != null:
		if portal_display.get_parent() != null:
			portal_display.get_parent().remove_child(portal_display)
		portal_display.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portal_display.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portal_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if portal_hint != null:
		if portal_hint.get_parent() != null:
			portal_hint.get_parent().remove_child(portal_hint)
		if portal_display != null:
			portal_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			portal_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portal_display.add_child(portal_hint)
	if _portal_mat != null:
		_portal_mat.set_shader_parameter("border_color", Color(1, 1, 1, 0.3))
		if sub_viewport != null and sub_viewport.size.y > 0:
			_portal_mat.set_shader_parameter("aspect",
				float(sub_viewport.size.x) / float(sub_viewport.size.y))

	# Info labels (persisted; reparented per layout by _relayout_portal).
	_portal_info_vbox = VBoxContainer.new()
	_portal_info_vbox.add_theme_constant_override("separation", 2)
	_portal_info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_portal_name_lbl = Label.new()
	_portal_name_lbl.text = "Select a creature"
	PanelTheme.as_sans(_portal_name_lbl, PanelTheme.SIZE_ITEM, true)
	_portal_name_lbl.add_theme_color_override("font_color", Color8(240, 237, 229))
	_portal_name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	_portal_name_lbl.tooltip_text = "Click to rename"
	_portal_name_lbl.gui_input.connect(_on_portal_name_input)
	_portal_info_vbox.add_child(_portal_name_lbl)

	_portal_lineage_lbl = Label.new()
	_portal_lineage_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.as_sans(_portal_lineage_lbl, PanelTheme.SIZE_CAPTION)
	_portal_lineage_lbl.add_theme_color_override("font_color", Color8(154, 160, 166))
	_portal_info_vbox.add_child(_portal_lineage_lbl)

	_portal_relation_lbl = Label.new()
	PanelTheme.as_serif_italic(_portal_relation_lbl, PanelTheme.SIZE_CAPTION)
	_portal_relation_lbl.add_theme_color_override("font_color", Color8(198, 184, 206))
	_portal_relation_lbl.visible = false
	_portal_info_vbox.add_child(_portal_relation_lbl)

	_portal_stats_lbl = Label.new()
	_portal_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.as_mono(_portal_stats_lbl, PanelTheme.SIZE_CAPTION)
	_portal_stats_lbl.add_theme_color_override("font_color", Color8(199, 203, 209))
	_portal_info_vbox.add_child(_portal_stats_lbl)

	# Controls (persisted; reparented per layout). + a layout-toggle button.
	_portal_ctrls = HBoxContainer.new()
	_portal_ctrls.alignment = BoxContainer.ALIGNMENT_CENTER
	_portal_ctrls.add_theme_constant_override("separation", 10)
	_portal_prev_btn = _make_portal_ctrl_btn("◀", "Previous creature (←)")
	_portal_prev_btn.pressed.connect(func(): cycle_follow(-1))
	_portal_ctrls.add_child(_portal_prev_btn)
	_portal_fav_btn = _make_portal_ctrl_btn("☆", "Favorite this creature")
	_portal_fav_btn.pressed.connect(_toggle_follow_favorite)
	_portal_ctrls.add_child(_portal_fav_btn)
	_portal_mode_btn = _make_portal_ctrl_btn("⛶", "Cinematic / picture-in-picture")
	_portal_mode_btn.pressed.connect(_toggle_follow_presentation)
	_portal_ctrls.add_child(_portal_mode_btn)
	_portal_layout_btn = _make_portal_ctrl_btn("▤", "Switch porthole layout")
	_portal_layout_btn.pressed.connect(_toggle_portal_layout)
	_portal_ctrls.add_child(_portal_layout_btn)
	_portal_next_btn = _make_portal_ctrl_btn("▶", "Next creature (→)")
	_portal_next_btn.pressed.connect(func(): cycle_follow(1))
	_portal_ctrls.add_child(_portal_next_btn)

	_relayout_portal()
	portal_container.visible = false


# Position + arrange the glass card for the current _portal_layout. The single
# authority for portal geometry (the responsive HUD layout calls this too).
func _relayout_portal() -> void:
	if portal_container == null or _portal_info_panel == null:
		return
	var above: bool = _portal_layout == PortalLayout.ABOVE
	var card_w: float = 208.0 if above else 312.0
	var card_h: float = 330.0 if above else 176.0
	var port: float = 156.0 if above else 104.0

	# Dock the card top-right, clear of the rail + top HUD.
	var right_inset: float = PanelTheme.RAIL_WIDTH + 10.0
	var top_inset: float = PanelTheme.HUD_TOP + 6.0
	portal_container.anchor_left = 1.0
	portal_container.anchor_right = 1.0
	portal_container.anchor_top = 0.0
	portal_container.anchor_bottom = 0.0
	portal_container.offset_right = -right_inset
	portal_container.offset_left = -right_inset - card_w
	portal_container.offset_top = top_inset
	portal_container.offset_bottom = top_inset + card_h

	if _portal_glass_bg != null:
		_portal_glass_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _portal_glass_mat != null:
			_portal_glass_mat.set_shader_parameter("rect_px", Vector2(card_w, card_h))
			_portal_glass_mat.set_shader_parameter("radius_px", 18.0)
			_portal_glass_mat.set_shader_parameter("tint", PanelTheme.glass_panel_tint())

	_portal_info_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portal_info_panel.add_theme_constant_override("margin_left", 16)
	_portal_info_panel.add_theme_constant_override("margin_right", 16)
	_portal_info_panel.add_theme_constant_override("margin_top", 14)
	_portal_info_panel.add_theme_constant_override("margin_bottom", 12)

	if portal_display != null:
		portal_display.custom_minimum_size = Vector2(port, port)

	var halign := HORIZONTAL_ALIGNMENT_CENTER if above else HORIZONTAL_ALIGNMENT_LEFT
	for lbl in [_portal_name_lbl, _portal_lineage_lbl, _portal_relation_lbl, _portal_stats_lbl]:
		if lbl != null:
			lbl.horizontal_alignment = halign
	if _portal_info_vbox != null:
		_portal_info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Detach persistent pieces from the previous scaffold, then rebuild it.
	for piece in [portal_display, _portal_info_vbox, _portal_ctrls]:
		if piece != null and piece.get_parent() != null:
			piece.get_parent().remove_child(piece)
	if _portal_scaffold != null and is_instance_valid(_portal_scaffold):
		_portal_scaffold.queue_free()

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 8)
	if above:
		root.add_child(portal_display)
		root.add_child(_portal_info_vbox)
	else:
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 12)
		hb.add_child(portal_display)
		_portal_info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(_portal_info_vbox)
		root.add_child(hb)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	root.add_child(_portal_ctrls)
	_portal_info_panel.add_child(root)
	_portal_scaffold = root


func _toggle_portal_layout() -> void:
	_portal_layout = PortalLayout.BESIDE if _portal_layout == PortalLayout.ABOVE else PortalLayout.ABOVE
	_relayout_portal()
	_update_portal_pip()


func _assign_creature_target(creature: Node3D) -> void:
	# Keep the current viewing style when re-targeting; default to PiP for a
	# fresh pick (design: a tap/click opens the portal, promotable to cinematic).
	var mode: int = _follow_mode if _follow_mode != FollowMode.OFF else FollowMode.PIP
	follow_creature(creature, mode)
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
	if not _aquascape.is_active:
		_save_aquascape_camera()
	_aquascape.toggle()
	if not _aquascape.is_active:
		_restore_aquascape_camera()
	if _aquascape.is_active and _onboarding != null:
		_onboarding.show_mode_coachmark(
			"aquascape",
			"Aquascape mode",
			"Scroll zooms · Shift+scroll build height · 1–4 views · F reset · B exit."
		)
	_sync_aquascape_view_bar()
	_apply_panel_layout()
	_apply_hud_layout()


func _aquascape_workbench_left() -> float:
	return PanelTheme.EDGE_MARGIN + 92.0


func _aquascape_workbench_width() -> float:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	if _is_mobile() or vp_w < PanelTheme.MOBILE_NARROW_W:
		return clampf(168.0, 152.0, 188.0)
	return PanelTheme.AQUASCAPE_WORKBENCH_W


func _sync_aquascape_chrome(_active: bool) -> void:
	_sync_aquascape_view_bar()
	_sync_feed_dock_visibility()
	_apply_panel_layout()
	_apply_hud_layout()
	_sync_rail_toggles()


func _ensure_aquascape_view_bar() -> void:
	if _aquascape_view_bar != null:
		return
	_aquascape_view_bar = PanelContainer.new()
	_aquascape_view_bar.name = "AquascapeViewBar"
	_aquascape_view_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_aquascape_view_bar.visible = false
	PanelTheme.apply_aquascape_toolbar_chrome(_aquascape_view_bar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	_aquascape_view_bar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	for vdef in [
		{"id": "top", "label": "Top", "key": "1"},
		{"id": "front", "label": "Front", "key": "2"},
		{"id": "side", "label": "Side", "key": "3"},
		{"id": "three_quarter", "label": "Persp", "key": "4"},
	]:
		var btn := Button.new()
		btn.text = "%s %s" % [vdef["label"], vdef["key"]]
		btn.tooltip_text = "Snap to %s view (%s)" % [String(vdef["label"]).to_lower(), vdef["key"]]
		btn.focus_mode = Control.FOCUS_NONE
		PanelTheme.style_compact_tool_button(btn, false)
		var view_id: String = String(vdef["id"])
		btn.pressed.connect(func(): _aquascape.snap_camera(view_id))
		row.add_child(btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset F"
	reset_btn.tooltip_text = "Restore default view (F)"
	reset_btn.focus_mode = Control.FOCUS_NONE
	PanelTheme.style_compact_tool_button(reset_btn, false)
	reset_btn.pressed.connect(func():
		_reset_camera_to_default()
		apply_camera_projection("perspective")
	)
	row.add_child(reset_btn)
	var sep := PanelTheme.make_hud_chip_divider()
	row.add_child(sep)
	var hint := Label.new()
	hint.text = "Scroll zoom · Shift+scroll plane · Q/E rotate"
	PanelTheme.as_mono(hint, PanelTheme.SIZE_CAPTION)
	hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	row.add_child(hint)
	add_child(_aquascape_view_bar)
	_aquascape_view_bar.z_index = 120


func _sync_aquascape_view_bar() -> void:
	_ensure_aquascape_view_bar()
	if _aquascape_view_bar == null:
		return
	var show: bool = _aquascape.is_active and not _immersive_mode
	_aquascape_view_bar.visible = show
	_sync_feed_dock()
	if not show:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bar_w: float = clampf(420.0, 320.0, vp.x * 0.42)
	var left: float = _aquascape_workbench_left() + _aquascape_workbench_width() + 12.0
	var top: float = PanelTheme.HUD_TOP + 2.0
	_aquascape_view_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_aquascape_view_bar.offset_left = left
	_aquascape_view_bar.offset_top = top
	_aquascape_view_bar.offset_right = left + bar_w
	_aquascape_view_bar.offset_bottom = top + PanelTheme.AQUASCAPE_VIEW_BAR_H


func _aquascape_undo() -> void:
	_aquascape.undo()


func _aquascape_redo() -> void:
	_aquascape.redo()


func _set_aquascape_fauna_hidden(hidden: bool) -> void:
	if _sim == null:
		return
	for p in _sim.plants:
		if is_instance_valid(p):
			p.visible = not hidden
	for f in _sim.fish:
		if is_instance_valid(f):
			f.visible = not hidden
	for s in _sim.shrimp:
		if is_instance_valid(s):
			s.visible = not hidden
	if _sim.get("snails_root") != null:
		var sr: Node = _sim.snails_root
		if sr != null:
			for c in sr.get_children():
				if is_instance_valid(c):
					c.visible = not hidden


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


func _refresh_aquascape_build_appearance() -> void:
	if _aquascape.has_method("refresh_build_appearance"):
		_aquascape.refresh_build_appearance()


func _aquascape_camera_snap(mode: String) -> void:
	if not _aquascape.is_active:
		return
	match mode:
		"top", "front", "side", "three_quarter":
			apply_camera_preset(mode)


func _aquascape_import_continue() -> void:
	if _aquascape.has_method("continue_import"):
		_aquascape.continue_import()


func _maybe_open_aquascape_on_load() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not bool(cfg.get("aquascape_pending")):
		return
	cfg.aquascape_pending = false
	if not _aquascape.is_active:
		_toggle_aquascape()


# ---- Walkthrough hooks (called by walkthrough.gd) ----

func _maybe_start_walkthrough() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	if cfg.walkthrough_pending:
		cfg.walkthrough_pending = false
		if walkthrough_overlay != null and walkthrough_overlay.has_method("begin"):
			walkthrough_overlay.begin()
		return
	if not cfg.walkthrough_completed and int(cfg.walkthrough_step) > 0 \
			and walkthrough_overlay != null and walkthrough_overlay.has_method("resume_from_step"):
		walkthrough_overlay.resume_from_step(int(cfg.walkthrough_step))


func wt_pause_sim(on: bool) -> void:
	if _sim == null:
		return
	if on:
		var cur: float = float(_sim.time_scale)
		_wt_saved_time_scale = cur if cur > 0.0 else 1.0
		_sim.time_scale = 0.0
	else:
		_sim.time_scale = _wt_saved_time_scale
	_sync_viewport_update_mode(_aquascape.is_active)
	_sync_speed_hud()


func wt_set_aquascape(on: bool) -> void:
	if _aquascape.is_active != on:
		_toggle_aquascape()


func wt_open_creator(kind_str: String) -> void:
	if creature_creator_panel != null and creature_creator_panel.has_method("open_to_kind"):
		creature_creator_panel.open_to_kind(kind_str)
	_sync_viewport_update_mode(_aquascape.is_active)


func wt_close_creator() -> void:
	if creature_creator_panel != null and creature_creator_panel.visible \
			and creature_creator_panel.has_method("close"):
		creature_creator_panel.close()
	_sync_viewport_update_mode(_aquascape.is_active)


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


func wt_on_walkthrough_finish() -> void:
	if _onboarding != null:
		_onboarding.on_walkthrough_finish()


func wt_on_walkthrough_skip() -> void:
	if _onboarding != null:
		_onboarding.on_walkthrough_skip()


func wt_on_step_changed(step: int) -> void:
	if _onboarding != null:
		_onboarding.on_walkthrough_step_changed(step)


func _get_chip(key: String) -> Control:
	return _chips.get(key, null) as Control


func _pulse_chip(key: String) -> void:
	var chip: Control = _get_chip(key)
	if chip == null:
		return
	var tw := create_tween()
	tw.tween_property(chip, "modulate", Color(1.35, 1.2, 1.1, 1.0), 0.22)
	tw.tween_property(chip, "modulate", Color.WHITE, 0.35)



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
		# Short-click feed on LMB release (before the pressed branch).
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# Short click on water → feed (on release, before _process polling).
			if not _aquascape.is_active and not is_pond_mode() \
					and not _press_skip_feed and _drag_button == MOUSE_BUTTON_LEFT \
					and _drag_mode == "orbit" and _drag_total < DRAG_DEADZONE_PX:
				if _drop_food_at_cursor(_drag_start):
					get_viewport().set_input_as_handled()
					return
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
					or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _click_hits_interactive_hud(mb.position):
					return
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if _aquascape_scroll_build_plane(true):
					pass
				elif _mouse_over_porthole():
					_adjust_portal_zoom(1.1)
				else:
					_zoom_camera_by_factor(1.0 / ZOOM_FACTOR)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _aquascape_scroll_build_plane(false):
					pass
				elif _mouse_over_porthole():
					_adjust_portal_zoom(1.0 / 1.1)
				else:
					_zoom_camera_by_factor(ZOOM_FACTOR)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				# Clicks on the magnifier don't pick or drop food; a
				# double-click there promotes the follow to cinematic.
				if _mouse_over_portal_card():
					if mb.double_click and _mouse_over_porthole():
						_toggle_follow_presentation()
					return
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
				if _alert_popup != null and _alert_popup.visible \
						and not _alert_popup.get_global_rect().has_point(mb.position):
					_alert_popup.visible = false
					closed_chip_popup = true
				if closed_chip_popup:
					_chip_popup_key = ""
				if _rail_flyout != null and _rail_flyout.visible:
					var on_rail: bool = false
					for btn in _ordered_rail_buttons():
						if btn.get_global_rect().has_point(mb.position):
							on_rail = true
							break
					if not _rail_flyout.get_global_rect().has_point(mb.position) and not on_rail:
						_close_rail_flyout()
				if _notifications_panel != null and _notifications_panel.visible \
						and not _notifications_panel.get_global_rect().has_point(mb.position):
					var on_alerts_rail: bool = _rail_alerts_btn != null \
							and _rail_alerts_btn.get_global_rect().has_point(mb.position)
					if not on_alerts_rail:
						_close_notifications_panel()
						_sync_rail_toggles()
				if _light_panel != null and _light_panel.visible \
						and not _light_panel.get_global_rect().has_point(mb.position) \
						and (_light_btn == null \
							or not _light_btn.get_global_rect().has_point(mb.position)) \
						and (_rail_appearance_btn == null \
							or not _rail_appearance_btn.get_global_rect().has_point(mb.position)):
					_close_light_panel()
				# LMB on a creature → follow. Short click on water → feed. Shift+LMB → startle.
				_press_skip_feed = false
				var picked: Node3D = _pick_creature_at_click(mb.position)
				if picked != null:
					_assign_creature_target(picked)
					_suppress_drag_until_release = true
					_press_skip_feed = true
				elif Input.is_key_pressed(KEY_SHIFT):
					_startle_fish_near_tap(mb.position)
					_suppress_drag_until_release = true
					_press_skip_feed = true
				elif is_pond_mode() and _pond_surface_tap(mb.position):
					_suppress_drag_until_release = true
					_press_skip_feed = true


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
					_aquascape.begin_stroke()
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
			if is_pond_mode() and _pond_conduct_pts.size() >= 4:
				_finish_pond_conduct()
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
					# Creature tap → follow; empty water tap → feed.
					if _touch_pick_creature(ev.position):
						_haptic(10)
					elif not _aquascape.is_active and not is_pond_mode():
						_drop_food_at_cursor(ev.position)
						_haptic(10)
			
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
			_aquascape.end_stroke()
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
				or _drag_mode == "paint" or _drag_mode == "wood_drag" or _drag_mode == "gumball"
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
						if is_pond_mode() and _current_projection_id == "top_down_ortho":
							_pan_target(ev.relative * (TOUCH_PAN_SENSITIVITY / PAN_MOUSE_SENSITIVITY))
							_pond_conduct_add(_project_to_surface(ev.position))
						else:
							yaw -= ev.relative.x * TOUCH_ORBIT_SENSITIVITY
							pitch -= ev.relative.y * TOUCH_ORBIT_SENSITIVITY
							pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
							_apply_camera()
		else:
			if nav_committed:
				if is_pond_mode() and _current_projection_id == "top_down_ortho":
					_pan_target(ev.relative * (TOUCH_PAN_SENSITIVITY / PAN_MOUSE_SENSITIVITY))
					_pond_conduct_add(_project_to_surface(ev.position))
				else:
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
			_zoom_camera_by_factor(1.0 - zoom_delta / 100.0)
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
	if _follow_mode != FollowMode.OFF:
		clear_follow()
		print_verbose("[walstad_loom] touch-tap: cleared follow")
	return false


# ---- Mobile UI setup ----

func _setup_footer_bar() -> void:
	if footer_bar == null:
		return
	footer_bar.add_theme_stylebox_override("panel", PanelTheme.make_footer_bar_style())
	footer_bar.offset_left = PanelTheme.EDGE_MARGIN
	footer_bar.offset_right = -PanelTheme.EDGE_MARGIN
	footer_bar.offset_top = -PanelTheme.FOOTER_HEIGHT
	footer_bar.offset_bottom = 0.0
	if controls_hint != null:
		controls_hint.label_settings = null
		PanelTheme.apply_font(controls_hint, PanelTheme.FONT_MONO, PanelTheme.SIZE_SMALL)
		controls_hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)


func _setup_speed_hud() -> void:
	_mobile_hud = get_node_or_null("MobileHUD")
	if _mobile_hud == null:
		return
	if _mobile_hud.has_signal("pause_pressed"):
		if not _mobile_hud.pause_pressed.is_connected(_toggle_pause):
			_mobile_hud.pause_pressed.connect(_toggle_pause)
	if _mobile_hud.has_signal("speed_pressed"):
		if not _mobile_hud.speed_pressed.is_connected(_set_time_scale):
			_mobile_hud.speed_pressed.connect(_set_time_scale)


func _sync_speed_hud() -> void:
	if _mobile_hud != null and _sim != null and _mobile_hud.has_method("sync_time_scale"):
		_mobile_hud.sync_time_scale(float(_sim.time_scale))


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
	if controls_hint != null:
		controls_hint.text = "drag orbit · pinch zoom · tap water to feed · pick food in footer · tap creature to follow"
	
	# Wire up mobile-only MobileHUD actions (speed dock wired in _setup_speed_hud).
	_mobile_hud = get_node_or_null("MobileHUD")
	if _mobile_hud != null:
		if _mobile_hud.has_signal("photo_pressed"):
			_mobile_hud.connect("photo_pressed", _take_photo)
		if _mobile_hud.has_signal("undo_pressed"):
			_mobile_hud.connect("undo_pressed", _aquascape_undo)
		if _mobile_hud.has_signal("aquascape_tool_pressed"):
			_mobile_hud.connect("aquascape_tool_pressed", func(tool: String):
				_aquascape.set_tool(tool))
		if _mobile_hud.has_signal("build_plane_pressed"):
			_mobile_hud.connect("build_plane_pressed", func(delta: float):
				_aquascape.adjust_build_plane(delta * TerrainVoxelGrid.CELL_SIZE))
		if _mobile_hud.has_signal("camera_views_pressed"):
			_mobile_hud.connect("camera_views_pressed", _toggle_camera_views_panel)
		if _mobile_hud.has_signal("residents_pressed"):
			_mobile_hud.connect("residents_pressed", _toggle_residents_panel)

	# Show the first-launch gesture tutorial on top of everything else.
	# Defers a frame so the panel doesn't fight with other mobile-setup
	# layout passes for size/anchor positioning.
	call_deferred("_maybe_show_tutorial")


func _apply_camera() -> void:
	if camera == null:
		return
	var hero_yaw: float = yaw
	var hero_pitch: float = pitch
	var mc := get_node_or_null("/root/MusicContext")
	if mc != null and mc.has_method("hero_camera_bias"):
		var hb: Dictionary = mc.hero_camera_bias()
		var hb_blend: float = float(hb.get("blend", 0.0))
		if hb_blend > 0.01:
			hero_yaw += float(hb.get("yaw", 0.0)) * hb_blend
			hero_pitch = clampf(hero_pitch + float(hb.get("pitch", 0.0)) * hb_blend, MIN_PITCH, MAX_PITCH)
	# Clamp target to a generous bounding box every time we apply. This is
	# the single convergence point for pan / WASD / follow-cam — clamping
	# here means a stray big delta from any of those paths can't push the
	# target through the camera (breaking `look_at`) or to ±∞.
	target = CameraController.clamp_target(target)
	var pos: Vector3 = CameraController.eye_position(target, hero_yaw, hero_pitch, radius)
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
	# Dragging RIGHT pushes the scene right (target moves left). The basis
	# right/up + radius-scaled sensitivity math lives in CameraController.
	var basis: Basis = camera.global_transform.basis
	target = CameraController.pan_target(target, delta, basis.x, basis.y, radius)
	# `target` is clamped to a sane box inside `_apply_camera()` (every
	# update path calls through there, so the clamp lives at the single
	# convergence point).
	# Clear follow-cam when the user manually pans - they're taking control back.
	_release_cinematic_follow()
	_apply_camera()


func _on_stats_changed(stats: Dictionary) -> void:
	_stats = stats
	_render_header()
	_apply_ecology_hud_layout()
	_refresh_cycle_banner()
	_collect_story_notifications()
	_collect_water_alert_notifications()
	_push_telemetry_to_js()
	if _onboarding != null:
		_onboarding.bind_sim(_sim)
		_onboarding.on_stats(stats)


func _on_eco_event(kind: String, text: String, severity: int) -> void:
	if _onboarding != null:
		_onboarding.on_eco_event(kind, text)
	var sev: String = NOTIF_SEVERITY_INFO
	if severity >= 2:
		sev = NOTIF_SEVERITY_CRITICAL
	elif severity >= 1:
		sev = NOTIF_SEVERITY_IMPORTANT
	var title: String = "Ecosystem"
	match kind:
		"cycle":
			title = "Tank cycle"
		"reef":
			title = "Reef"
		"trophic", "population":
			title = "Food web"
		"flora":
			title = "Flora"
	_push_notification(kind, sev, title, text, severity >= 2)


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


func _fauna_age_sub(adults: int, juveniles: int, fry: int, total: int, cap: int) -> String:
	var ages: String = "%dA" % adults
	if juveniles > 0:
		ages += " %dJ" % juveniles
	if fry > 0:
		ages += " %dF" % fry
	if cap > 0:
		return "%s · %d/%d" % [ages, total, cap]
	return ages


func _render_header() -> void:
	if _chips.is_empty():
		return

	var fish_total: int = int(_stats.get("fish_total", 0))
	var fish_adults: int = int(_stats.get("fish_adults", 0))
	var fish_juveniles: int = int(_stats.get("fish_juveniles", 0))
	var fish_fry: int = int(_stats.get("fish_fry", 0))
	var shrimp_total: int = int(_stats.get("shrimp_total", 0))
	var shrimp_adults: int = int(_stats.get("shrimp_adults", 0))
	var shrimp_juveniles: int = int(_stats.get("shrimp_juveniles", 0))
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
		if String(_stats.get("hud_mode", "")) == "cycle":
			var day_l: String = String(_stats.get("sim_day_label", ""))
			if not day_l.is_empty():
				state_sub = "%s · %s" % [day_l, state_sub]
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
			fish_sub = _fauna_age_sub(fish_adults, fish_juveniles, fish_fry, fish_total, fish_cap)
		else:
			fish_sub = _fauna_age_sub(fish_adults, fish_juveniles, fish_fry, fish_total, 0)
		_update_chip("fish", str(fish_total), fish_sub, true, over_cap)
		_update_chip("shrimp", str(shrimp_total),
			_fauna_age_sub(shrimp_adults, shrimp_juveniles, shrimp_fry, shrimp_total, 0)
				if shrimp_total > 0 else "—",
			true, false)
		_update_chip("snails", str(snail_total),
			("%dA %dB" % [snail_adults, snail_babies]) if snail_total > 0 else "—",
			true, false)

	# Flora chip.
	var flora_sub: String = HudController.flora_chip_subtitle(_stats)
	var flora_warn: bool = float(_stats.get("bloom_intensity", 0.0)) >= 0.40
	_update_chip("flora", str(plants), flora_sub, true, flora_warn)

	# Water chip — during cycle mode the phase is primary; O₂ moves to sublabel.
	var water_primary: String = HudController.water_chip_primary(_stats)
	var water_sub: String = HudController.water_chip_subtitle(_stats)
	var water_warn: bool = HudController.water_chip_warn(_stats)
	_update_chip("water", water_primary, water_sub, true, water_warn)

	# Morphs chip — only meaningful once speciation has produced variants.
	_update_chip("morphs", "+%d" % distinct_morphs, "morphs", distinct_morphs > 0, false)

	# Mood chip — aggregate tank vibe across O₂, biomass, algae, waste.
	# Weights tuned so a healthy planted tank reads as "thriving" and a
	# crashed one as "🚨", with a clear in-between band so the chip
	# changes meaningfully as the tank trends rather than flipping at
	# one threshold. Mood is computed here rather than on sim_driver so
	# it can read the same _stats snapshot already in scope.
	var ammonia: float = float(_stats.get("ammonia", 0.0))
	var mood: float
	if not not _stats.get("is_saltwater", false):
		var bleach: float = float(_stats.get("reef_bleach_level", 0.0))
		var alk: float = float(_stats.get("alkalinity_proxy", 8.0))
		var warmth: float = float(_stats.get("effective_warmth", 0.55))
		mood = 0.35 * o2 \
			+ 0.28 * clampf(1.0 - bleach, 0.0, 1.0) \
			+ 0.20 * clampf((alk - 6.8) / 1.4, 0.0, 1.0) \
			+ 0.17 * clampf(1.0 - maxf(0.0, warmth - 0.78) * 3.2, 0.0, 1.0)
	else:
		mood = 0.30 * o2 \
			+ 0.30 * clampf(float(biomass) / 600.0, 0.0, 1.0) \
			+ 0.20 * clampf(1.0 - float(algae) / 60.0, 0.0, 1.0) \
			+ 0.20 * clampf(1.0 - float(waste) / 100.0, 0.0, 1.0) \
			- clampf(ammonia * 0.25, 0.0, 0.35)
	mood = clampf(mood, 0.0, 1.0)
	var mood_glyph: String
	if mood >= 0.78:
		mood_glyph = "🙂"
	elif mood >= 0.55:
		mood_glyph = "😌"
	elif mood >= 0.32:
		mood_glyph = "😟"
	else:
		mood_glyph = "🚨"
	_update_chip("mood", mood_glyph, OnboardingLegibility.mood_driver(_stats, mood), true, mood < 0.32)

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
	elif float(_stats.get("nitrite", 0.0)) >= 0.22:
		has_alert = true
		alert_value = "NO₂"
		alert_sub = "nitrites"
	elif float(_stats.get("ammonia", 0.0)) >= 0.25:
		has_alert = true
		alert_value = "NH₃"
		alert_sub = "ammonia"
	elif float(_stats.get("reef_bleach_level", 0.0)) >= 0.35:
		has_alert = true
		alert_value = "bleach"
		alert_sub = "corals"
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
		"block":
			return "BLOCK y%.1f" % _aquascape.build_plane_y
		"eraser":
			return "ERASE"
		"object":
			return "OBJ %s" % _aquascape.selected_object_id
		"eyedropper":
			return "PICK"
		"line":
			return "LINE"
		"box":
			return "BOX"
		"paste":
			return "PASTE"
		"select":
			return "SELECT"
		"lava_rock", "white_sand", "dark_soil", "clay", "crushed_coral":
			return _aquascape.tool.to_upper().replace("_", " ")
		"smooth", "raise", "fill", "grad":
			return _aquascape.tool.to_upper()
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
		{"key": "mood",   "icon": UiIcons.chip_glyph("mood"), "color": Color8(170, 220, 170), "tier": "primary"},
		{"key": "water",  "icon": UiIcons.chip_glyph("water"), "color": Color8(127, 183, 216), "tier": "primary"},
		{"key": "alert",  "icon": UiIcons.chip_glyph("alert"), "color": Color8(224, 112, 112), "tier": "primary"},
		{"key": "state",  "icon": UiIcons.chip_glyph("state"), "color": Color8(154, 168, 200), "tier": "secondary"},
		{"key": "fish",   "icon": UiIcons.chip_glyph("fish"), "color": Color8(214, 176, 112), "tier": "secondary"},
		{"key": "flora",  "icon": UiIcons.chip_glyph("flora"), "color": Color8(134, 192, 132), "tier": "secondary"},
		{"key": "shrimp", "icon": UiIcons.chip_glyph("shrimp"), "color": Color8(214, 176, 112), "tier": "tertiary"},
		{"key": "snails", "icon": UiIcons.chip_glyph("snails"), "color": Color8(214, 176, 112), "tier": "tertiary"},
		{"key": "morphs", "icon": UiIcons.chip_glyph("morphs"), "color": Color8(224, 192, 96), "tier": "tertiary"},
	]
	for d in defs:
		var key: String = String(d["key"])
		var tier: String = String(d.get("tier", "secondary"))
		if key == "state" or (tier == "secondary" and key == "fish"):
			bar.add_child(PanelTheme.make_hud_chip_divider())
		var chip: Control = _make_chip(String(d["icon"]), d["color"] as Color, key, tier)
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
		"state": return "Sim day & time scale — tap for cycle history"
		"mood": return "Ecosystem mood — tap for story log"
		"water": return "N-cycle & O₂ — tap for chemistry details"
		"alert": return "Active alerts — tap for guidance"
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
func _make_chip(icon: String, accent: Color, key: String = "", tier: String = "secondary") -> Control:
	var pc := PanelContainer.new()
	var style := StyleBoxFlat.new()
	# Chips sit inside the StatsBar's tinted panel — no fill, just a 2-px
	# accent strip on the left so the eye can find each category.
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = accent
	style.border_width_left = 3 if tier == "primary" else 2
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
	icon_lbl.add_theme_font_size_override("font_size", PanelTheme.SIZE_ITEM)
	icon_lbl.add_theme_color_override("font_color", accent)
	hb.add_child(icon_lbl)

	# Value → Mono so digits line up; size carries the tier hierarchy.
	var value_lbl := Label.new()
	value_lbl.add_theme_color_override("font_color", PanelTheme.VALUE_FG)
	PanelTheme.as_mono(value_lbl, PanelTheme.SIZE_BODY if tier == "primary" else PanelTheme.SIZE_SMALL)
	hb.add_child(value_lbl)

	# Sublabel floored at SIZE_CAPTION (11) — the project's legibility minimum.
	var sublabel_lbl := Label.new()
	sublabel_lbl.add_theme_font_size_override("font_size", PanelTheme.SIZE_CAPTION)
	sublabel_lbl.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	hb.add_child(sublabel_lbl)

	pc.set_meta("value_label", value_lbl)
	pc.set_meta("sublabel_label", sublabel_lbl)
	pc.set_meta("accent", accent)
	pc.set_meta("tier", tier)
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
		s.text = _truncate_chip_sublabel(sublabel, key)
	chip.modulate = Color(1.0, 0.7, 0.7) if warn else Color(1.0, 1.0, 1.0)


func _truncate_chip_sublabel(text: String, key: String) -> String:
	if text.is_empty():
		return text
	var max_len: int = 28
	if _hud_layout == "wide":
		max_len = 22 if key in ["flora", "fish", "mood"] else 32
	elif _hud_layout == "medium":
		max_len = 18
	else:
		max_len = 14
	if text.length() <= max_len:
		return text
	return text.substr(0, max(0, max_len - 1)) + "…"


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
var _ambient_breath_t: float = 0.0
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
# After resolution hits the floor, step shader cost down instead of thrashing.
var _adaptive_shader_cost: int = 0


func _apply_adaptive_shader_cost() -> void:
	var sm := _quantize_material()
	var cfg := get_node_or_null("/root/TankConfig")
	if sm == null or cfg == null:
		return
	sm.set_shader_parameter("outline_strength", float(cfg.outline_strength))
	sm.set_shader_parameter("creature_outline_strength", float(cfg.creature_outline_strength))
	sm.set_shader_parameter("crt_strength", float(cfg.crt_strength))
	sm.set_shader_parameter("region_aware_dither",
		1.0 if cfg.dither_region_aware else 0.0)
	sm.set_shader_parameter("palette_bank_lock",
		1.0 if cfg.palette_bank_lock else 0.0)
	sm.set_shader_parameter("bloom_strength", float(cfg.get("pp_bloom_strength")))
	sm.set_shader_parameter("dither_strength", float(cfg.dither_strength))
	if _adaptive_shader_cost >= 1:
		sm.set_shader_parameter("outline_strength", 0.0)
		sm.set_shader_parameter("crt_strength", 0.0)
	if _adaptive_shader_cost >= 2:
		sm.set_shader_parameter("region_aware_dither", 0.0)
		sm.set_shader_parameter("palette_bank_lock", 0.0)
	if _adaptive_shader_cost >= 3:
		sm.set_shader_parameter("bloom_strength", 0.0)
		sm.set_shader_parameter("dither_strength", 0.4)
	if _sim != null:
		if _adaptive_shader_cost >= 3:
			_sim.pearling_budget_scale = 0.0
		elif _adaptive_shader_cost >= 2:
			_sim.pearling_budget_scale = 0.45
		else:
			_sim.pearling_budget_scale = 1.0


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
	# #63 — fold governor p95 pressure into the FPS the scaler sees.
	fps -= PerfGovernor.adaptive_fps_penalty()
	var governor_down: bool = PerfGovernor.governor_step_down()
	var governor_block_up: bool = PerfGovernor.governor_step_up_block()
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
	# Step down if we're missing target by >10%, or the governor is hot.
	if fps < target_fps * 0.90 or (governor_down and fps < target_fps * 1.08):
		if cur_idx > 0:
			var nt: Dictionary = _ADAPTIVE_RES_TIERS[cur_idx - 1]
			cfg.set("render_width", int(nt["w"]))
			cfg.set("render_height", int(nt["h"]))
			_apply_render_config()
			_frame_history.fill(0.0)
			return
		if _adaptive_shader_cost < 3:
			_adaptive_shader_cost += 1
			_apply_adaptive_shader_cost()
			_frame_history.fill(0.0)
			return
	# Step up if we have >25% headroom and could increase quality.
	if fps > target_fps * 1.25 and not governor_block_up:
		if _adaptive_shader_cost > 0:
			_adaptive_shader_cost -= 1
			_apply_adaptive_shader_cost()
			_frame_history.fill(0.0)
			return
		if cur_idx < _ADAPTIVE_RES_TIERS.size() - 1:
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
var _palette_tint_smooth: Vector3 = Vector3(1.0, 1.0, 1.0)
var _last_written_palette_tint: Vector3 = Vector3(-999.0, -999.0, -999.0)
var _glance_cam_pos: Vector3 = Vector3(INF, INF, INF)
var _glance_cam_rot_hash: float = 0.0
const _PALETTE_TINT_EPS: float = 1.0 / 512.0


func _write_palette_tint_if_changed(mat: ShaderMaterial, tint: Vector3) -> void:
	if tint.distance_squared_to(_last_written_palette_tint) >= _PALETTE_TINT_EPS * _PALETTE_TINT_EPS:
		ShaderUniformLedger.write(mat, "palette_tint", tint)
		_last_written_palette_tint = tint


func _update_palette_tod_tint() -> void:
	var mat := _quantize_material()
	if mat == null:
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
		var calm: float = 0.75
		if _sim != null and _sim.get("calm") != null:
			calm = clampf(float(_sim.calm), 0.0, 1.0)
		var breath: float = 1.0 + AestheticsRuntime.ambient_breath(_ambient_breath_t, calm)
		var target_t: Vector3 = t * breath
		_palette_tint_smooth = _palette_tint_smooth.lerp(target_t, minf(1.0, get_process_delta_time() * 2.4))
		_write_palette_tint_if_changed(mat, _palette_tint_smooth)
	else:
		var breath_e: float = 1.0 + AestheticsRuntime.ambient_breath(_ambient_breath_t, 0.75)
		var target_e: Vector3 = t * breath_e
		_palette_tint_smooth = _palette_tint_smooth.lerp(target_e, minf(1.0, get_process_delta_time() * 2.4))
		_write_palette_tint_if_changed(mat, _palette_tint_smooth)
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
			var bloom_boost: float = 0.85 + deep_night * 0.14
			if _sim != null and _sim.has_method("spark_dawn_active") and _sim.spark_dawn_active():
				bloom_boost = 1.05 + deep_night * 0.25
			var a11y: float = _sim.night_a11y_pulse() if _sim != null and _sim.has_method("night_a11y_pulse") else 0.0
			if a11y > 0.0:
				bloom_boost *= 1.0 + a11y * 0.08
			mat.set_shader_parameter("bloom_strength", bloom_boost)
			mat.set_shader_parameter("bloom_threshold", 0.68 - deep_night * 0.14)
		else:
			mat.set_shader_parameter("bloom_strength", 0.85)
			mat.set_shader_parameter("bloom_threshold", 0.68)
	night_blend = smoothstep(0.0, 1.0, night_blend)
	mat.set_shader_parameter("palette_night_blend", night_blend)
	# Push user-controlled post-process uniforms every tick. Cheap (constant
	# count of small uniforms) and lets the sliders react live.
	if cfg != null:
		var vig: float = float(cfg.pp_vignette_strength)
		if dl < 0.28:
			vig = maxf(vig, 0.32 + (1.0 - dl) * 0.22)
		if _sim != null and _sim.has_method("spark_dawn_active") and _sim.spark_dawn_active():
			vig *= 0.82
		mat.set_shader_parameter("vignette_strength", vig)
		mat.set_shader_parameter("vignette_falloff", float(cfg.pp_vignette_falloff))
		# Bloom + outline + dither + CRT only override the defaults when the
		# user has actually moved them off the legacy values (we still set
		# every frame for simplicity — the shader handles 0 gracefully).
		mat.set_shader_parameter("outline_strength", float(cfg.outline_strength))
		mat.set_shader_parameter("creature_outline_strength", float(cfg.creature_outline_strength))
		mat.set_shader_parameter("dither_strength", float(cfg.dither_strength))
		mat.set_shader_parameter("crt_strength", float(cfg.crt_strength))
		mat.set_shader_parameter("region_aware_dither",
			1.0 if cfg.dither_region_aware else 0.0)
		mat.set_shader_parameter("palette_bank_lock",
			1.0 if cfg.palette_bank_lock else 0.0)
		mat.set_shader_parameter("dither_world_lock",
			1.0 if cfg.dither_world_lock else 0.0)
		mat.set_shader_parameter("dither_world_origin",
			Vector2(float(cfg.camera_target_x), float(cfg.camera_target_z)))
		# Bloom is now a real user control — always push the slider value so
		# the panel feels responsive. The dynamic night-bloom boost is
		# preserved by the per-section logic above, which writes BEFORE this
		# line — so we override it with the user's pick if they touched it.
		mat.set_shader_parameter("bloom_strength", float(cfg.pp_bloom_strength))
		mat.set_shader_parameter("bloom_threshold", float(cfg.pp_bloom_threshold))
		mat.set_shader_parameter("film_grain_strength", float(cfg.film_grain_strength))
		mat.set_shader_parameter("selective_glow", float(cfg.selective_glow_strength))
		mat.set_shader_parameter("crt_mode", float(cfg.crt_mode))
		mat.set_shader_parameter("outline_subject_bias", 0.82)
		mat.set_shader_parameter("dither_substrate_coarse", 0.35)
		var trans: float = 1.0
		if world != null:
			var wc: Variant = world.get("_cached_water_column")
			if wc is Dictionary and not (wc as Dictionary).is_empty():
				trans = float((wc as Dictionary).get("transmittance", 1.0))
		mat.set_shader_parameter("health_grade",
			AestheticsRuntime.health_grade_from_transmittance(trans))
		if bool(cfg.pixel_purity):
			mat.set_shader_parameter("dither_strength", maxf(float(cfg.dither_strength), 0.94))
			mat.set_shader_parameter("palette_bank_lock", 1.0)
			mat.set_shader_parameter("film_grain_strength",
				maxf(float(cfg.film_grain_strength), 0.08))


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
	# Integer letterbox. Use the drawable viewport size (not raw window size)
	# so HiDPI / chrome insets match what the player actually sees.
	var win: Vector2 = get_viewport().get_visible_rect().size
	var sv: Vector2 = Vector2(sub_viewport.size)
	if sv.x <= 0.0 or sv.y <= 0.0 or win.x <= 1.0 or win.y <= 1.0:
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
	# Also fall back when the letterboxed rect would exceed the window —
	# otherwise the display is clipped and the player sees a zoomed-in
	# corner of the render (common when render res > window width).
	var coverage_x: float = out_size.x / win.x
	var coverage_y: float = out_size.y / win.y
	if coverage_x < 0.70 or coverage_y < 0.70 \
			or out_size.x > win.x + 0.5 or out_size.y > win.y + 0.5:
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
		return PanelTheme.FOOTER_HEIGHT + PanelTheme.RAIL_BOTTOM_HEIGHT
	return PanelTheme.FOOTER_HEIGHT


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
	if _rail_vbox != null:
		_rail_vbox.add_theme_constant_override("separation", 8)
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
	h = h * 31 + _follow_mode
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
		PanelTheme.style_rail_button(_rail_world_btn, _follow_mode == FollowMode.PIP or _aquascape.is_active)
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

	for panel in [settings_panel, render_panel, sound_panel]:
		if panel != null:
			PanelTheme.layout_side_panel(panel, rail, top, bottom, panel_w, "right")

	if _notifications_panel != null:
		PanelTheme.layout_side_panel(_notifications_panel, rail, top, bottom, panel_w, "right")

	if _light_panel != null:
		PanelTheme.layout_side_panel(_light_panel, rail, top, bottom, panel_w, "right")
		var scroll: Control = _light_panel.get_meta("scroll_container", null) as Control
		if scroll != null:
			var body_h: float = vp.y - top - bottom - 100.0
			scroll.custom_minimum_size = Vector2(0, clampf(body_h, 280.0, 640.0))

	if _notifications_toast_layer != null:
		PanelTheme.layout_toast_stack(_notifications_toast_layer, bottom)

	if _residents_panel != null:
		PanelTheme.layout_side_panel(_residents_panel, edge, top, bottom, panel_w, "left")

	_layout_follow_thought_strip()

	if library_panel != null:
		PanelTheme.layout_side_panel(library_panel, edge, top, bottom, panel_w, "left")
		library_panel.offset_right = -rail

	if aquascape_palette != null:
		var work_w: float = _aquascape_workbench_width()
		var work_left: float = _aquascape_workbench_left()
		aquascape_palette.anchor_left = 0.0
		aquascape_palette.anchor_top = 0.0
		aquascape_palette.anchor_right = 0.0
		aquascape_palette.anchor_bottom = 1.0
		aquascape_palette.offset_left = work_left
		aquascape_palette.offset_top = top
		aquascape_palette.offset_right = work_left + work_w
		aquascape_palette.offset_bottom = -bottom
	_sync_aquascape_view_bar()

	if _camera_views_panel != null:
		var cam_w: float = clampf(panel_w * 0.72, 280.0, 380.0)
		PanelTheme.layout_side_panel(_camera_views_panel, rail, top, bottom, cam_w, "right")
		_camera_views_panel.z_index = 130

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

	# The glass follow-card owns its own geometry (size depends on the chosen
	# porthole layout); re-apply it on resize rather than forcing a square here.
	if portal_container != null:
		_relayout_portal()


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
			s.visible = layout == "wide" and not _aquascape.is_active

	var aqua_build: bool = _aquascape.is_active
	var compact_only_chips := ["shrimp", "snails", "morphs"]
	var aqua_hidden := ["fish", "flora", "shrimp", "snails", "morphs"]
	for k in _chips.keys():
		var chip: Control = _chips.get(k, null) as Control
		if chip == null:
			continue
		if aqua_build and k in aqua_hidden:
			chip.visible = false
		elif layout == "compact" and k in compact_only_chips:
			chip.visible = false
		elif k != "alert":
			chip.visible = true

	var rail_edge: float = _rail_edge_inset()
	var left_inset: float = 128.0 if layout != "compact" else 112.0
	if aqua_build:
		left_inset = _aquascape_workbench_left() + _aquascape_workbench_width() + 8.0
	if stats_bar != null:
		stats_bar.offset_left = left_inset
		stats_bar.offset_right = -rail_edge

	if layout_changed:
		_render_header()
	_apply_ecology_hud_layout()


var _cycle_banner: Label = null
var _cycle_banner_dismissed: bool = false


func _ensure_cycle_banner() -> void:
	if _cycle_banner != null:
		return
	_cycle_banner = Label.new()
	_cycle_banner.visible = false
	_cycle_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cycle_banner.add_theme_font_size_override("font_size", 12)
	_cycle_banner.add_theme_color_override("font_color", Color(0.82, 0.92, 0.85, 1.0))
	_cycle_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cycle_banner.offset_top = 46.0
	_cycle_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_cycle_banner.gui_input.connect(_on_cycle_banner_input)
	add_child(_cycle_banner)


func _on_cycle_banner_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_cycle_banner_dismissed = true
		var saves := get_node_or_null("/root/TankSaves")
		if saves != null:
			_set_global_pref("cycle_banner_dismissed_%d" % int(saves.active_slot), true)
		_refresh_cycle_banner()


func _refresh_cycle_banner() -> void:
	_ensure_cycle_banner()
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null:
		_cycle_banner_dismissed = bool(_global_pref(
			"cycle_banner_dismissed_%d" % int(saves.active_slot), false))
	if _cycle_banner_dismissed:
		_cycle_banner.visible = false
		return
	var mode: String = String(_stats.get("hud_mode", ""))
	var banner: String = String(_stats.get("cycle_banner", ""))
	if mode != "cycle" or banner.is_empty():
		_cycle_banner.visible = false
		return
	_cycle_banner.text = banner + "  (tap to dismiss)"
	_cycle_banner.visible = true


func _apply_ecology_hud_layout() -> void:
	if _chips.is_empty():
		return
	var mode: String = String(_stats.get("hud_mode", "established"))
	var morphs: int = int(_stats.get("morph_distinct", 0))
	var morph_chip: Control = _chips.get("morphs", null) as Control
	if morph_chip != null and _hud_layout != "compact":
		morph_chip.visible = morphs > 0 or mode != "cycle"


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
	"state": "cycle_phase",
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
		_sync_chip_popup_tooltips(true)
		_show_story_popup(color)
		return
	if key == "water":
		_sync_chip_popup_tooltips(true)
		_show_water_chemistry_popup(color)
		return
	if key == "alert":
		_sync_chip_popup_tooltips(true)
		_show_alert_guidance_popup(color)
		return
	if key == "state":
		_sync_chip_popup_tooltips(true)
		_show_history_popup("cycle_phase", key, color)
		return
	var hist_key: String = _CHIP_TO_HISTORY.get(key, "")
	if hist_key == "":
		return  # morphs chip has no sparkline history
	_sync_chip_popup_tooltips(true)
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
	if _alert_popup != null and _alert_popup.visible:
		_alert_popup.visible = false
	_chip_popup_key = ""
	_sync_chip_popup_tooltips(false)


func _sync_chip_popup_tooltips(suppress: bool) -> void:
	for key in _chips.keys():
		var chip: Control = _chips.get(key) as Control
		if chip == null:
			continue
		chip.tooltip_text = "" if suppress else _chip_tooltip(key)


func _chip_popup_stylebox(accent: Color = PanelTheme.HUD_BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.96)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.68)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _position_chip_popup(panel: Control, chip_key: String) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = panel.size
	if sz.x < 1.0:
		sz = panel.custom_minimum_size
	var x: float = (vp.x - sz.x) * 0.5
	var y: float = PanelTheme.HUD_TOP + 6.0
	var chip: Control = _get_chip(chip_key)
	if chip != null:
		var chip_rect: Rect2 = chip.get_global_rect()
		x = clampf(chip_rect.position.x + chip_rect.size.x * 0.5 - sz.x * 0.5, 8.0, vp.x - sz.x - 8.0)
		y = clampf(chip_rect.end.y + 6.0, PanelTheme.HUD_TOP, vp.y - sz.y - 8.0)
	panel.position = Vector2(x, y)


func _history_popup_dimensions(hist_key: String) -> Vector2:
	match hist_key:
		"dissolved_o2", "cycle_phase":
			return Vector2(288, 90)
		"algae_clusters":
			return Vector2(272, 86)
		_:
			return Vector2(248, 78)


func _chip_popup_size_for_lines(line_count: int, min_w: float = 236.0) -> Vector2:
	var body_h: float = float(maxi(line_count, 1)) * 17.0
	var h: float = clampf(44.0 + body_h, 72.0, 200.0)
	return Vector2(min_w, h)


func _ui_toggle_side(id: String) -> void:
	_prepare_panel_open()
	_ui_panels.toggle_side(id)
	_sync_rail_toggles()


func _ui_toggle_modal(id: String) -> void:
	_prepare_panel_open()
	_ui_panels.toggle_modal(id)
	_sync_rail_toggles()
	_sync_viewport_update_mode(_aquascape.is_active)


func _on_modal_closed(id: String) -> void:
	_ui_panels.notify_modal_closed(id)
	_sync_rail_toggles()
	_sync_viewport_update_mode(_aquascape.is_active)


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
	_apply_panel_layout()
	_sync_light_btn()


func _close_light_panel() -> void:
	if _light_panel != null and _light_panel.visible:
		_light_panel.visible = false
		_light_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _ui_panels != null:
		_ui_panels.notify_side_closed(UiPanelManager.SIDE_LIGHT)
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
	if _ui_panels != null:
		_ui_panels.notify_side_closed(UiPanelManager.SIDE_NOTIFICATIONS)


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
	_close_chip_popups()
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
				{"label": "Info & links", "tip": "Website, bug reports, source code",
					"action": func(): AppLinks.show_info_popup(self)},
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
	_notifications_toast_layer.z_index = 95
	add_child(_notifications_toast_layer)

	_notifications_panel = PanelContainer.new()
	_notifications_panel.visible = false
	_notifications_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_notifications_panel.custom_minimum_size = Vector2(PanelTheme.PANEL_MIN_W, 360)
	_notifications_panel.z_index = 110
	PanelTheme.apply_panel_chrome(_notifications_panel)
	add_child(_notifications_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notifications_panel.add_child(root)

	root.add_child(PanelTheme.make_title("Notifications"))
	root.add_child(PanelTheme.make_rule())

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

	var clear_btn := PanelTheme.make_secondary_button("Clear all")
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

	root.add_child(PanelTheme.make_panel_footer(func() -> void:
		_close_notifications_panel()
		_sync_rail_toggles()))

	_apply_panel_layout()


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
		var dedup_key: String = "%s|%s" % [kind, body]
		var now_unix: int = int(Time.get_unix_time_from_system())
		if _toast_recent_keys.has(dedup_key) \
				and now_unix - int(_toast_recent_keys[dedup_key]) < 180:
			show_toast = false
		else:
			_toast_recent_keys[dedup_key] = now_unix
	if show_toast:
		_notification_toast_queue.append(notif)
		_pump_notification_toast_queue()
	if _notifications_panel != null and _notifications_panel.visible:
		_refresh_notifications_panel()


func _pump_notification_toast_queue() -> void:
	if _notifications_toast_layer == null:
		return
	if _typing_focus_in_ui():
		return
	while _notification_toast_active < NOTIF_TOAST_MAX_ACTIVE and not _notification_toast_queue.is_empty():
		var notif: Dictionary = _notification_toast_queue.pop_front()
		_spawn_notification_toast(notif)


func _spawn_notification_toast(notif: Dictionary) -> void:
	_notification_toast_active += 1
	var card := PanelContainer.new()
	card.modulate.a = 0.0
	var stack_idx: int = _notification_toast_active - 1
	var layer_h: float = _notifications_toast_layer.size.y
	if layer_h < 1.0:
		layer_h = PanelTheme.TOAST_STACK_H
	card.position = Vector2(0.0, layer_h - float(stack_idx + 1) * 74.0)
	card.scale = Vector2(0.96, 0.96)
	card.custom_minimum_size = Vector2(PanelTheme.TOAST_STACK_W - 8.0, 64)
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
	if _follow_thought_strip != null and _follow_thought_strip.visible:
		_layout_follow_thought_strip()

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
		if _follow_thought_strip != null and _follow_thought_strip.visible:
			_layout_follow_thought_strip()
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
		if text == "" or bool(e.get("skip_notification", false)):
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
var _story_title: Label = null
var _story_tab: String = "tank"
var _story_tab_tank_btn: Button = null
var _story_tab_guardian_btn: Button = null
var _story_copy_btn: Button = null
var _story_follow_row: HBoxContainer = null
var _guardian_consent_layer: Control = null
var _plant_inspector: PanelContainer = null
var _plant_inspector_body: Label = null
var _plant_hover: Plant = null
var _plant_hover_meter: Control = null
var _plant_hover_bar: ProgressBar = null


func _ensure_story_popup() -> void:
	if _story_popup != null and is_instance_valid(_story_popup):
		return
	_story_popup = PanelContainer.new()
	_story_popup.visible = false
	_story_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_story_popup.z_index = 220
	_story_popup.custom_minimum_size = Vector2(400, 248)
	_story_popup.add_theme_stylebox_override("panel", _chip_popup_stylebox())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_story_popup.add_child(vbox)

	var header := PanelTheme.make_chip_popup_header("Tank story", _close_chip_popups)
	vbox.add_child(header)
	_story_title = header.get_child(0) as Label

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_row)
	_story_tab_tank_btn = Button.new()
	_story_tab_tank_btn.text = "Story"
	_story_tab_tank_btn.pressed.connect(func() -> void:
		_story_tab = "tank"
		_refresh_story_popup_body())
	tab_row.add_child(_story_tab_tank_btn)
	_story_tab_guardian_btn = Button.new()
	_story_tab_guardian_btn.text = "Guardian"
	_story_tab_guardian_btn.pressed.connect(func() -> void:
		_story_tab = "guardian"
		_refresh_story_popup_body())
	tab_row.add_child(_story_tab_guardian_btn)
	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)
	_story_copy_btn = PanelTheme.make_icon_button("⧉")
	_story_copy_btn.tooltip_text = "Copy diary"
	_story_copy_btn.custom_minimum_size = Vector2(28, 28)
	_story_copy_btn.pressed.connect(_export_guardian_journal)
	tab_row.add_child(_story_copy_btn)

	_story_follow_row = HBoxContainer.new()
	vbox.add_child(_story_follow_row)
	var follow_btn := PanelTheme.make_ghost_button("Find guardian in tank →")
	follow_btn.pressed.connect(_follow_guardian_from_story)
	_story_follow_row.add_child(follow_btn)

	_story_list = RichTextLabel.new()
	_story_list.bbcode_enabled = true
	_story_list.fit_content = false
	_story_list.scroll_active = true
	_story_list.scroll_following = false
	_story_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_list.custom_minimum_size = Vector2(376, 168)
	_story_list.add_theme_color_override("default_color", Color(0.86, 0.90, 0.96, 0.95))
	# The tank's narrative voice → Serif.
	PanelTheme.apply_font(_story_list, PanelTheme.FONT_SERIF, PanelTheme.SIZE_BODY)
	vbox.add_child(_story_list)

	add_child(_story_popup)


func _show_story_popup(_chip_color: Color) -> void:
	_ensure_story_popup()
	if _sim == null:
		return
	_story_tab = "tank"
	_refresh_story_popup_body()
	_story_popup.size = _story_popup.custom_minimum_size
	_position_chip_popup(_story_popup, "mood")
	_story_popup.visible = true
	_chip_popup_key = "mood"


func _refresh_story_popup_body() -> void:
	if _sim == null or _story_list == null:
		return
	if _story_tab == "guardian":
		if _story_title != null:
			_story_title.text = "Guardian diary"
		var journal: Array = _sim.get_guardian_journal() if _sim.has_method("get_guardian_journal") else []
		_story_list.text = GuardianJournal.format_bbcode(journal)
	else:
		if _story_title != null:
			_story_title.text = "Tank story"
		var events: Array = _sim.story_events
		if events.is_empty():
			_story_list.text = "[color=#9aa8c8]No story yet. Wait for things to happen.[/color]"
		else:
			var lines: Array[String] = []
			for i in range(events.size() - 1, -1, -1):
				var e: Dictionary = events[i]
				var t: float = float(e.get("t", 0.0))
				lines.append("[color=#9aa8c8]%s[/color]  %s" % [
					_format_story_t(t, e), String(e.get("text", "")),
				])
			_story_list.text = "\n".join(lines)
	_sync_story_tab_chrome()


func _sync_story_tab_chrome() -> void:
	if _story_tab_tank_btn != null:
		PanelTheme.style_compact_tool_button(_story_tab_tank_btn, _story_tab == "tank")
	if _story_tab_guardian_btn != null:
		PanelTheme.style_compact_tool_button(_story_tab_guardian_btn, _story_tab == "guardian")
	if _story_copy_btn != null:
		_story_copy_btn.visible = _story_tab == "guardian"
	if _story_follow_row != null:
		_story_follow_row.visible = _story_tab == "guardian"


func _follow_guardian_from_story() -> void:
	if _sim == null or not _sim.has_method("_find_guardian_fish"):
		return
	var g: Fish = _sim._find_guardian_fish()
	if g == null:
		_push_notification("guardian", "info", "No guardian", "The guardian hasn't arrived yet.", false)
		return
	_assign_creature_target(g)
	_close_chip_popups()


func _export_guardian_journal() -> void:
	if _sim == null or not _sim.has_method("export_guardian_journal_plain"):
		return
	DisplayServer.clipboard_set(_sim.export_guardian_journal_plain())
	if has_method("_push_notification"):
		_push_notification("guardian", "info", "Diary copied", "Guardian journal copied to clipboard.", false)


func _try_pick_plant_at(screen_pos: Vector2) -> void:
	if _sim == null or camera == null:
		return
	var picked: Plant = _ray_pick_plant(screen_pos)
	if picked == null:
		if _plant_inspector != null:
			_plant_inspector.visible = false
		return
	_show_plant_inspector(picked)


func _ray_pick_plant(screen_pos: Vector2) -> Plant:
	var sv_pos: Vector2 = _window_mouse_to_viewport(screen_pos)
	var ro: Vector3 = camera.project_ray_origin(sv_pos)
	var rd: Vector3 = camera.project_ray_normal(sv_pos)
	var best: Plant = null
	var best_d2: float = 2.25
	for p in _sim.plants:
		if not is_instance_valid(p):
			continue
		var pt: Vector3 = p.global_position + Vector3(0, p.top_world_y() * 0.45, 0)
		var t: float = clampf((pt - ro).dot(rd), 0.0, 120.0)
		var closest: Vector3 = ro + rd * t
		var d2: float = closest.distance_squared_to(pt)
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _ensure_plant_inspector() -> void:
	if _plant_inspector != null and is_instance_valid(_plant_inspector):
		return
	_plant_inspector = PanelContainer.new()
	_plant_inspector.visible = false
	_plant_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	_plant_inspector.custom_minimum_size = Vector2(320, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.08, 0.94)
	style.border_color = Color(0.35, 0.55, 0.42, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_plant_inspector.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	_plant_inspector.add_child(vbox)
	_plant_inspector_body = Label.new()
	_plant_inspector_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plant_inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelTheme.apply_font(_plant_inspector_body, PanelTheme.FONT_SANS, PanelTheme.SIZE_BODY)
	vbox.add_child(_plant_inspector_body)
	add_child(_plant_inspector)


func _show_plant_inspector(plant: Plant) -> void:
	_ensure_plant_inspector()
	if not plant.has_method("get_growth_inspector"):
		return
	var info: Dictionary = plant.get_growth_inspector()
	var diag: Dictionary = info.get("diag", {})
	var lines: PackedStringArray = []
	lines.append(String(info.get("species", "Plant")))
	lines.append("Health %d%% · growth to next voxel %d%%" % [
		int(round(float(info.get("health", 0.0)) * 100.0)),
		int(round(float(info.get("growth_pct", 0.0)))),
	])
	lines.append("Limiting: %s" % String(info.get("limiting_text", "balanced")))
	if not diag.is_empty():
		lines.append("%.1fs per voxel · light %.0f%% co₂ %.0f%%" % [
			float(diag.get("seconds_per_voxel", 0.0)),
			float(diag.get("f_light", 0.0)) * 100.0,
			float(diag.get("f_co2", 0.0)) * 100.0,
		])
	_plant_inspector_body.text = "\n".join(lines)
	var anchor: Vector3 = plant.global_position + Vector3(0, plant.top_world_y() + 0.35, 0)
	var screen: Vector2 = _subviewport_to_root_ui(camera.unproject_position(anchor))
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var panel_sz: Vector2 = _plant_inspector.custom_minimum_size
	_plant_inspector.position = Vector2(
		clampf(screen.x - panel_sz.x * 0.5, 8.0, vp.x - panel_sz.x - 8.0),
		clampf(screen.y - panel_sz.y - 14.0, 8.0, vp.y - panel_sz.y - 8.0),
	)
	_plant_inspector.visible = true


func _ensure_plant_hover_meter() -> void:
	if _plant_hover_meter != null and is_instance_valid(_plant_hover_meter):
		return
	_plant_hover_meter = Control.new()
	_plant_hover_meter.visible = false
	_plant_hover_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plant_hover_meter.custom_minimum_size = Vector2(64, 10)
	add_child(_plant_hover_meter)
	_plant_hover_bar = ProgressBar.new()
	_plant_hover_bar.show_percentage = false
	_plant_hover_bar.custom_minimum_size = Vector2(64, 8)
	_plant_hover_bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.12, 0.10, 0.55)
	bg.set_corner_radius_all(3)
	_plant_hover_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 0.92, 0.62, 0.92)
	fill.set_corner_radius_all(3)
	_plant_hover_bar.add_theme_stylebox_override("fill", fill)
	_plant_hover_meter.add_child(_plant_hover_bar)


func _update_plant_hover_meter() -> void:
	if _sim == null or camera == null or _aquascape.is_active or _orbiting \
			or _is_touch_active():
		if _plant_hover_meter != null:
			_plant_hover_meter.visible = false
		_plant_hover = null
		return
	var picked: Plant = _ray_pick_plant(_last_mouse)
	if picked == null:
		if _plant_hover_meter != null:
			_plant_hover_meter.visible = false
		_plant_hover = null
		return
	_plant_hover = picked
	_ensure_plant_hover_meter()
	var pct: float = 0.0
	if picked.has_method("get_growth_inspector"):
		pct = float(picked.get_growth_inspector().get("growth_pct", 0.0))
	_plant_hover_bar.value = pct
	var anchor: Vector3 = picked.global_position + Vector3(0, picked.top_world_y() + 0.25, 0)
	var screen: Vector2 = _subviewport_to_root_ui(camera.unproject_position(anchor))
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if screen.x < -40.0 or screen.y < -40.0 or screen.x > vp.x + 40.0 or screen.y > vp.y + 40.0:
		_plant_hover_meter.visible = false
		return
	_plant_hover_meter.position = screen + Vector2(-32.0, -18.0)
	_plant_hover_meter.modulate.a = lerpf(_plant_hover_meter.modulate.a, 1.0, 0.18)
	_plant_hover_meter.visible = true


var _water_popup: PanelContainer = null
var _water_detail: Label = null
var _alert_popup: PanelContainer = null
var _alert_detail: Label = null


func _ensure_water_popup() -> void:
	if _water_popup != null:
		return
	_water_popup = PanelContainer.new()
	_water_popup.visible = false
	_water_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_water_popup.z_index = 220
	_water_popup.add_theme_stylebox_override("panel", _chip_popup_stylebox(Color8(127, 183, 216)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_water_popup.add_child(vb)
	vb.add_child(PanelTheme.make_chip_popup_header("Water chemistry", _close_chip_popups))
	_water_detail = Label.new()
	_water_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.apply_font(_water_detail, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	vb.add_child(_water_detail)
	add_child(_water_popup)


func _show_water_chemistry_popup(_chip_color: Color) -> void:
	_ensure_water_popup()
	var lines: PackedStringArray = OnboardingLegibility.water_detail_lines(_stats)
	_water_detail.text = "\n".join(lines)
	_water_popup.custom_minimum_size = _chip_popup_size_for_lines(lines.size(), 248.0)
	_water_popup.size = _water_popup.custom_minimum_size
	_position_chip_popup(_water_popup, "water")
	_water_popup.visible = true
	_chip_popup_key = "water"


func _ensure_alert_popup() -> void:
	if _alert_popup != null:
		return
	_alert_popup = PanelContainer.new()
	_alert_popup.visible = false
	_alert_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_alert_popup.z_index = 220
	_alert_popup.add_theme_stylebox_override("panel", _chip_popup_stylebox(Color8(224, 112, 112)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_alert_popup.add_child(vb)
	vb.add_child(PanelTheme.make_chip_popup_header("Tank alert", _close_chip_popups))
	_alert_detail = Label.new()
	_alert_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PanelTheme.apply_font(_alert_detail, PanelTheme.FONT_SANS, PanelTheme.SIZE_SMALL)
	vb.add_child(_alert_detail)
	add_child(_alert_popup)


func _current_alert_kind() -> String:
	var o2_pct: int = int(round(float(_stats.get("dissolved_o2", 0.0)) * 100.0))
	var algae: int = int(_stats.get("algae_clusters", 0))
	var waste: int = int(_stats.get("waste_particles", 0))
	if o2_pct < 30:
		return "low_o2"
	if algae > 20:
		return "algae"
	if waste > 30:
		return "waste"
	if float(_stats.get("nitrite", 0.0)) >= 0.22:
		return "nitrite"
	if float(_stats.get("ammonia", 0.0)) >= 0.25:
		return "ammonia"
	if float(_stats.get("reef_bleach_level", 0.0)) >= 0.35:
		return "bleach"
	return "none"


func _show_alert_guidance_popup(_chip_color: Color) -> void:
	var kind: String = _current_alert_kind()
	if kind == "none":
		_show_water_chemistry_popup(_chip_color)
		return
	_ensure_alert_popup()
	var lines: PackedStringArray = OnboardingLegibility.alert_guidance(kind, _stats)
	_alert_detail.text = "\n".join(lines)
	if kind in ["bleach", "ammonia", "nitrite", "low_o2"]:
		lines.append("")
		lines.append("— Chemistry —")
		for wl in OnboardingLegibility.water_detail_lines(_stats):
			lines.append(wl)
		_alert_detail.text = "\n".join(lines)
	_alert_popup.custom_minimum_size = _chip_popup_size_for_lines(lines.size(), 260.0)
	_alert_popup.size = _alert_popup.custom_minimum_size
	_position_chip_popup(_alert_popup, "alert")
	_alert_popup.visible = true
	_chip_popup_key = "alert"


# Render an elapsed sim-time into a short "Xm" / "Xh Ym" string for the
# left margin of each story line. Keeps the diary scannable rather than
# raw-second timestamped.
func _format_story_t(t: float, ev: Dictionary = {}) -> String:
	if ev.has("sim_day") and String(ev.get("sim_day", "")) != "":
		return String(ev.get("sim_day"))
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
	_history_popup.z_index = 220
	_history_popup.add_theme_stylebox_override("panel", _chip_popup_stylebox())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_history_popup.add_child(vbox)

	var header := PanelTheme.make_chip_popup_header("Population", _close_chip_popups)
	vbox.add_child(header)
	_history_title = header.get_child(0) as Label

	_history_stats = Label.new()
	_history_stats.add_theme_font_size_override("font_size", 10)
	_history_stats.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85, 0.85))
	vbox.add_child(_history_stats)

	_history_sparkline = _make_sparkline()
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
	var band: Vector2 = OnboardingLegibility.history_healthy_band(hist_key)
	if band.y > 0.0:
		_history_stats.text += "   healthy %.0f–%.0f%%" % [band.x * 100.0, band.y * 100.0]
	_history_sparkline.set_meta("samples", hist.duplicate())
	_history_sparkline.set_meta("color", color)
	_history_sparkline.queue_redraw()
	var dims: Vector2 = _history_popup_dimensions(hist_key)
	_history_popup.custom_minimum_size = dims
	_history_popup.size = dims
	_history_sparkline.custom_minimum_size = Vector2(
		maxf(180.0, dims.x - 28.0), maxf(32.0, dims.y - 42.0))
	_history_popup.add_theme_stylebox_override("panel", _chip_popup_stylebox(color))
	_position_chip_popup(_history_popup, chip_key)
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
	# Each interaction restarts the cinema-tour dwell so it advances only after
	# you've stopped fiddling.
	_cinema_accum = 0.0
	# A real interaction ends the idle "screensaver" tour (but not one you
	# started yourself with the Cinema button).
	if _cinema_auto and _cinema_active:
		set_cinema_mode(false)
	if top_hud != null and top_hud.modulate != HUD_LIT_MODULATE:
		top_hud.modulate = HUD_LIT_MODULATE
	if right_rail != null and right_rail.modulate != HUD_LIT_MODULATE:
		right_rail.modulate = HUD_LIT_MODULATE
	if footer_bar != null and footer_bar.modulate != HUD_LIT_MODULATE:
		footer_bar.modulate = HUD_LIT_MODULATE


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
	_light_panel.custom_minimum_size = Vector2(PanelTheme.PANEL_MIN_W, 0)
	PanelTheme.apply_panel_chrome(_light_panel)
	add_child(_light_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_light_panel.add_child(outer)

	outer.add_child(PanelTheme.make_title("Light"))
	outer.add_child(PanelTheme.make_rule())

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

	_light_heater_check = CheckBox.new()
	_light_heater_check.text = "Substrate heater on (warmth near the rod)"
	_light_heater_check.toggled.connect(_on_heater_toggled)
	vbox.add_child(_light_heater_check)
	_attach_reset(_light_heater_check, "heater_enabled")

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

	outer.add_child(PanelTheme.make_panel_footer(func() -> void:
		_close_light_panel()
		_sync_rail_toggles()))


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
	"heater_enabled": true,
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
	if _light_heater_check != null:
		_light_heater_check.set_pressed_no_signal(bool(cfg.heater_enabled))
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
	_apply_panel_layout()


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


func _on_heater_toggled(v: bool) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.heater_enabled = v
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
	if footer_hint_spacer != null:
		footer_hint_spacer.visible = not _immersive_mode
	if footer_bar != null:
		footer_bar.visible = true
	if _mobile_hud != null:
		if _mobile_hud.has_method("set_immersive_mode"):
			_mobile_hud.set_immersive_mode(_immersive_mode)
		_mobile_hud.visible = true
	if aquascape_palette != null:
		if _immersive_mode:
			aquascape_palette.visible = false
		elif _aquascape.is_active:
			aquascape_palette.visible = true
	_sync_aquascape_view_bar()
	if portal_container != null and _immersive_mode:
		portal_container.visible = false
	if _immersive_mode:
		_close_panels_for_immersive()
	_ensure_immersive_exit_button()
	if _immersive_exit_btn != null:
		_immersive_exit_btn.visible = _immersive_mode
	if not _immersive_mode and _follow_mode != FollowMode.OFF and portal_container != null:
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
	_immersive_exit_btn.focus_mode = Control.FOCUS_NONE
	PanelTheme.style_hud_toggle_button(_immersive_exit_btn, false)
	_immersive_exit_btn.custom_minimum_size = Vector2(108, 36)
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
	if _sim != null and _sim.has_method("reset_make_it_there_session"):
		_sim.reset_make_it_there_session()
	_sync_speed_hud()


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
						if _sim != null and _sim.has_method("_clamp_loaded_entities"):
							_sim.call("_clamp_loaded_entities")
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
	if _sim.has_method("on_player_focus_out"):
		_sim.on_player_focus_out()
	# Only freeze if the sim is currently running; if it was already paused
	# don't store 0 as the "saved" value — we'd unpause on resume.
	var ts: float = float(_sim.time_scale)
	if ts > 0.0:
		_focus_saved_time_scale = ts
		_sim.time_scale = 0.0
		_focus_paused = true
		_sync_viewport_update_mode(_aquascape.is_active)
		_sync_speed_hud()


func _on_focus_in() -> void:
	if _sim == null or not _focus_paused:
		pass
	else:
		_sim.time_scale = _focus_saved_time_scale
		_focus_paused = false
		_sync_viewport_update_mode(_aquascape.is_active)
		_sync_speed_hud()
	if _sim != null and _sim.has_method("on_player_focus_in"):
		_sim.on_player_focus_in()


func _persist_last_quit_unix() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.last_quit_unix = int(Time.get_unix_time_from_system())
	cfg.save_to_disk()


# ---- Device tier pick (first mobile launch) ----
# Cheap heuristic for classifying device tier on first mobile launch.
# Records screen class only — does not override render resolution or adaptive quality.
func _pick_device_tier_if_unset() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	if String(cfg.device_tier) != "":
		return
	var sz: Vector2i = DisplayServer.screen_get_size()
	var short_side: int = min(sz.x, sz.y) if sz.x > 0 and sz.y > 0 else 0
	var ram_gb: float = 0.0
	if OS.has_method("get_memory_info"):
		var info: Dictionary = OS.get_memory_info()
		var total: int = int(info.get("physical", 0))
		if total > 0:
			ram_gb = float(total) / (1024.0 * 1024.0 * 1024.0)
	var low_ram: bool = ram_gb > 0.0 and ram_gb < 3.5
	if low_ram or short_side < 900:
		cfg.device_tier = "low"
	elif short_side >= 1500:
		cfg.device_tier = "high"
	else:
		cfg.device_tier = "mid"
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
	if cfg == null:
		return
	var sm := _quantize_material()
	if sm == null:
		return
	var saver: bool = bool(cfg.get("battery_saver"))
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
		sm.set_shader_parameter("creature_outline_strength", float(cfg.get("creature_outline_strength")))
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
	lab.anchor_right = 0.0
	lab.anchor_top = 1.0
	lab.anchor_bottom = 1.0
	lab.offset_left = PanelTheme.EDGE_MARGIN
	lab.offset_right = PanelTheme.EDGE_MARGIN + PanelTheme.TOAST_STACK_W
	lab.offset_top = -(_hud_bottom_inset() + PanelTheme.TOAST_STACK_H + 8.0)
	lab.offset_bottom = -(_hud_bottom_inset() + PanelTheme.TOAST_STACK_H - 24.0)
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
	if _onboarding != null:
		_onboarding.toggle_help()
		return
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
	var lines: PackedStringArray = OnboardingLegibility.cheat_sheet_lines(_is_mobile())
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
	if bool(OnboardingLegibility.global_pref("tour_complete", false)):
		return
	if bool(_global_pref("coachmarks_seen", false)):
		return
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
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
		"Click water to feed · pick food in the footer · drag to orbit.",
	]
	if step >= hints.size():
		_set_global_pref("coachmarks_seen", true)
		return
	_coachmark_step = step
	_coachmark_overlay = Control.new()
	_coachmark_overlay.name = "CoachmarkOverlay"
	_coachmark_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_coachmark_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_coachmark_overlay.z_index = 490
	add_child(_coachmark_overlay)
	move_child(_coachmark_overlay, get_child_count() - 1)
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
	# One layer per press — innermost / most transient UI first.
	if _close_rail_flyout():
		return true
	if _chip_popup_key != "":
		_close_chip_popups()
		return true
	if _cheat_sheet != null and is_instance_valid(_cheat_sheet):
		_toggle_cheat_sheet()
		return true
	if _camera_views_panel != null and _camera_views_panel.visible:
		_close_camera_views_panel()
		return true
	if _residents_panel != null and _residents_panel.visible:
		_close_residents_panel()
		return true
	if _notifications_panel != null and _notifications_panel.visible:
		_close_notifications_panel()
		_sync_rail_toggles()
		return true
	if _light_panel != null and _light_panel.visible:
		_close_light_panel()
		return true
	if settings_panel != null and settings_panel.visible:
		if settings_panel.has_method("toggle"):
			settings_panel.toggle()
		else:
			settings_panel.visible = false
			settings_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _ui_panels != null:
			_ui_panels.notify_side_closed(UiPanelManager.SIDE_SETTINGS)
		_sync_rail_toggles()
		return true
	if render_panel != null and render_panel.visible:
		render_panel.visible = false
		render_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _ui_panels != null:
			_ui_panels.notify_side_closed(UiPanelManager.SIDE_RENDER)
		_sync_rail_toggles()
		return true
	if sound_panel != null and sound_panel.visible:
		if sound_panel.has_method("_close"):
			sound_panel._close()
		else:
			sound_panel.visible = false
			sound_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _ui_panels != null:
			_ui_panels.notify_side_closed(UiPanelManager.SIDE_SOUND)
		_sync_rail_toggles()
		return true
	if creature_creator_panel != null and creature_creator_panel.visible:
		if creature_creator_panel.has_method("close"):
			creature_creator_panel.close()
		else:
			creature_creator_panel.visible = false
		if _ui_panels != null:
			_ui_panels.notify_modal_closed(UiPanelManager.MODAL_CREATOR)
		_sync_rail_toggles()
		return true
	if fish_store_panel != null and fish_store_panel.visible:
		fish_store_panel.visible = false
		fish_store_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _ui_panels != null:
			_ui_panels.notify_modal_closed(UiPanelManager.MODAL_STORE)
		_sync_rail_toggles()
		return true
	if library_panel != null and library_panel.visible:
		if library_panel.has_method("close"):
			library_panel.close()
		else:
			library_panel.visible = false
		if _ui_panels != null:
			_ui_panels.notify_modal_closed(UiPanelManager.MODAL_LIBRARY)
		_sync_rail_toggles()
		return true
	if walkthrough_overlay != null and walkthrough_overlay.visible:
		if walkthrough_overlay.has_method("_finish"):
			walkthrough_overlay._finish()
		else:
			walkthrough_overlay.visible = false
		return true
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		_dismiss_tutorial_overlay(_tutorial_overlay)
		return true
	if _ui_panels != null and _ui_panels.is_modal_open():
		_ui_panels.close_modal()
		_sync_rail_toggles()
		return true
	if _radial_menu != null and is_instance_valid(_radial_menu):
		_dismiss_radial_menu()
		return true
	return false


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
	overlay.name = "TutorialOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 500
	add_child(overlay)
	move_child(overlay, get_child_count() - 1)
	# Dim background — dismiss on tap outside the card only.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			_dismiss_tutorial_overlay(overlay)
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_dismiss_tutorial_overlay(overlay))
	overlay.add_child(bg)
	# Centered scrollable panel so the Got-it button stays reachable on
	# small screens / Windows scaling where a fixed-height card clips.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_top = -200
	panel.offset_right = 220
	panel.offset_bottom = 200
	PanelTheme.apply_panel_chrome(panel)
	overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
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
			"• Pick food in the footer, then tap water to feed",
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
	var ok := PanelTheme.make_primary_button("Got it")
	ok.custom_minimum_size = Vector2(0, 48)
	ok.focus_mode = Control.FOCUS_ALL
	ok.pressed.connect(func():
		_dismiss_tutorial_overlay(overlay))
	vb.add_child(ok)
	_tutorial_overlay = overlay
	ok.call_deferred("grab_focus")


func _dismiss_tutorial_overlay(overlay: Control) -> void:
	_set_global_pref("tutorial_seen", true)
	_haptic(12)
	if is_instance_valid(overlay):
		overlay.queue_free()
	_tutorial_overlay = null
	call_deferred("_maybe_show_coachmarks")


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
		{"key": "block", "label": "block",   "angle": -PI / 2, "color": Color8(180, 200, 255)},
		{"key": "eraser",  "label": "erase",   "angle": 0.0,     "color": Color8(220, 90, 90)},
		{"key": "line",    "label": "line",    "angle": PI / 2,  "color": Color8(140, 255, 180)},
		{"key": "object",  "label": "object",  "angle": PI,      "color": Color8(255, 220, 140)},
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
