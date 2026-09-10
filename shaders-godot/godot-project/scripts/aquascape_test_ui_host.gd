# Host node the aquascape UI smokes mount panels onto.
#
# Deliberately NOT named smoke_* : run_smokes.sh and smoke_runner.gd glob
# scripts/smoke_*.gd and execute every match. This is a helper, not a smoke —
# it has no SceneTree MainLoop, so being executed booted the whole game and
# hung the run forever. That is what used to stall the aggregate runner.

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
