# Aquascape world stand-in for the aquascape smokes.
#
# Deliberately NOT named smoke_* : run_smokes.sh and smoke_runner.gd glob
# scripts/smoke_*.gd and execute every match. This is a helper, not a smoke —
# it has no SceneTree MainLoop, so being executed booted the whole game and
# hung the run forever. That is what used to stall the aggregate runner.

extends Node3D
# Minimal tank stub for headless aquascape smoke tests (no sim/fish spawn).

var WATER_HEIGHT: float = 6.5
var SUBSTRATE_DEPTH: float = 1.6
var TANK_HALF_W: float = 4.0
var TANK_HALF_D: float = 2.0


func is_inside_tank_volume(_x: float, _y: float, _z: float, _margin: float) -> bool:
	return true
