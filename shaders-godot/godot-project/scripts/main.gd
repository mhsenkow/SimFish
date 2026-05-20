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

# Last-known ecosystem stats (updated via SimDriver.stats_changed signal).
var _stats: Dictionary = {}

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
var _auto_orbit: bool = false
var _space_was_pressed: bool = false


func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	_apply_camera()
	# Subscribe to SimDriver stats - they emit at ~1Hz with the ecosystem snapshot.
	await get_tree().process_frame
	var sim_node: Node = world.get_node_or_null("SimDriver")
	if sim_node != null and sim_node.has_signal("stats_changed"):
		sim_node.connect("stats_changed", _on_stats_changed)


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
	elif not any_btn and _orbiting:
		_orbiting = false

	if _orbiting:
		var delta: Vector2 = mouse_now - _last_mouse
		_last_mouse = mouse_now
		if delta.length_squared() > 0.0:
			yaw -= delta.x * SENSITIVITY
			pitch -= delta.y * SENSITIVITY
			pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
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

	# Update debug HUD every frame.
	_update_hud(mouse_now, any_btn)


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
	parts.append("fish %d (%d/%d)" % [fish_total, fish_adults, fish_fry])
	parts.append("shrimp %d (%d/%d)" % [shrimp_total, shrimp_adults, shrimp_fry])
	parts.append("eggs %d" % eggs)
	parts.append("plants %d / biomass %d" % [plants, biomass])
	parts.append("waste %d" % waste)
	parts.append("nutrients %.1f" % nutrients)
	hud.text = "   ·   ".join(parts)
