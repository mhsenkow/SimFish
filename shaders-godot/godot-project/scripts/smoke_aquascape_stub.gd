extends Node3D
# Minimal tank stub for headless aquascape smoke tests (no sim/fish spawn).

var WATER_HEIGHT: float = 6.5
var SUBSTRATE_DEPTH: float = 1.6
var TANK_HALF_W: float = 4.0
var TANK_HALF_D: float = 2.0


func is_inside_tank_volume(_x: float, _y: float, _z: float, _margin: float) -> bool:
	return true
