extends "res://scripts/world.gd"
var full: bool = false
var relocate: bool = false
func _ready() -> void:
	set_process(false)
func plants_at_capacity() -> bool:
	return full
func clamp_plant_site(x: float, z: float, _radius: float, _margin: float = 0.25, _world_y: float = NAN) -> Vector2:
	return Vector2(x, z)
func fits_plant_at(_x: float, _z: float, _radius: float, _margin: float = 0.25, _world_y: float = NAN) -> bool:
	return true
func spawn_position_on_floor(x: float, z: float, _y_offset: float = 0.0) -> Vector3:
	return Vector3(x, 1.0 + x * 0.1, z)
func _is_hardscape_occupied(x: float, _z: float, _clearance: float = 0.6) -> bool:
	return relocate and x < 1.5
func _pick_ecology_site(_is_saltwater: bool, _z_min: float, _z_max: float,
		_clearance: float = 0.4, _hardscape_clearance: float = 0.6, _edge_bias: float = -1.0) -> Vector2:
	return Vector2(2, 0)
