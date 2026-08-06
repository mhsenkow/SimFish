extends Node

@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display
@onready var camera: Camera3D = $SubViewport/World/Camera3D

var _frame := 0
var _angles := [
	{"yaw": -0.42, "pitch": 0.18, "radius": 15.5, "name": "hero"},
	{"yaw": 0.0,   "pitch": 0.14, "radius": 16.0, "name": "front"},
	{"yaw": 0.72,  "pitch": 0.18, "radius": 15.8, "name": "right_3q"},
	{"yaw": -0.42, "pitch": 0.10, "radius": 14.5, "name": "low"},
]
var _state := 0
var _state_timer := 0
var _shots_taken := 0
const SETTLE_FRAMES := 360
const CAMERA_SETTLE_FRAMES := 30

func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	_apply_camera(0)


func _apply_camera(idx: int) -> void:
	var a: Dictionary = _angles[idx]
	var target := Vector3(0.0, 2.8, 0.0)
	var yaw: float = a["yaw"]
	var pitch: float = a["pitch"]
	var r: float = a["radius"]
	var pos := target + Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch),
	) * r
	camera.global_transform = Transform3D(Basis(), pos)
	camera.look_at(target, Vector3.UP)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	_state_timer += 1
	if _state == 0:
		if _shots_taken >= _angles.size():
			get_tree().quit()
			return
		_apply_camera(_shots_taken)
		print("[camera] applied angle=", _angles[_shots_taken]["name"])
		_state = 1
		_state_timer = 0
	elif _state == 1:
		if _state_timer >= CAMERA_SETTLE_FRAMES:
			var a: Dictionary = _angles[_shots_taken]
			# Save BOTH the raw 3D subviewport AND the final shader output (root window)
			var raw_img: Image = sub_viewport.get_texture().get_image()
			if raw_img != null:
				raw_img.save_png("res://capture_pass_%s_raw.png" % a["name"])
			var root_img: Image = get_viewport().get_texture().get_image()
			if root_img != null:
				root_img.save_png("res://capture_pass_%s.png" % a["name"])
				print("captured: capture_pass_", a["name"], " (raw+final)")
			_shots_taken += 1
			_state = 0
			_state_timer = 0
