extends Node

var last_camera_view: String = ""
var last_projection: String = ""

func _window_mouse_to_viewport(pos: Vector2) -> Vector2:
	return pos

func _render_header() -> void:
	pass

func _aquascape_camera_snap(mode: String) -> void:
	last_camera_view = mode

func apply_camera_projection(proj_id: String) -> void:
	last_projection = proj_id

func _sync_aquascape_chrome(_active: bool) -> void:
	pass
