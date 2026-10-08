extends "res://scripts/world.gd"

var clamp_calls: int = 0
func _ready() -> void:
	set_process(false)
func clamp_xyz_in_tank(p: Vector3, margin: float = 0.25,
		body_radius: float = 0.0) -> Vector3:
	clamp_calls += 1
	return super.clamp_xyz_in_tank(p, margin, body_radius)
