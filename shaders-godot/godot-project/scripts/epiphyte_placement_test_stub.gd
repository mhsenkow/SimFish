extends "res://scripts/world.gd"

var spawned_config: Dictionary = {}
var spawned_at: Vector3 = Vector3.ZERO
func _ready() -> void:
	set_process(false)
func _sample_substrate_xz(_margin: float = 0.35, _edge_bias: float = -1.0,
		_min_lateral_room: float = 0.0) -> Vector2:
	return Vector2(-8.0, 0.0)
func spawn_seedling(pos: Vector3, _ramp: Array, _generation: int,
		seed_config: Dictionary) -> void:
	spawned_at = pos
	spawned_config = seed_config.duplicate(true)
