extends Node3D

# Test stub plant for MotionStaging LOS (#177). Not a smoke_* script.


func biomass() -> int:
	return 20


func canopy_shadow_sphere() -> Vector4:
	return Vector4(global_position.x, global_position.y + 0.4, global_position.z, 0.7)
