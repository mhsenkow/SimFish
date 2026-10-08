extends Node
var creature_visible: bool = true
var time_scale: float = 1.0
var dissolved_o2: float = 0.95
var total_plant_biomass: float = 300.0
var substrate_top_y: float = 0.6
func daylight() -> float:
	return 1.0
func is_creature_visible_to_camera(_creature: Node3D) -> bool:
	return creature_visible
