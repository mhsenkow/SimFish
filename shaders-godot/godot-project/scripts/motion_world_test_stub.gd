extends Node3D
const WATER_HEIGHT: float = 6.5

func clamp_xyz_in_tank(pos: Vector3, _margin: float, _body_radius: float) -> Vector3:
	return Vector3(clampf(pos.x, -12.0, 12.0), clampf(pos.y, -6.0, 6.3), clampf(pos.z, -12.0, 12.0))
