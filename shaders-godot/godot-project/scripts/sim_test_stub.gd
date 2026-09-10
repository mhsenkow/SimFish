# SimDriver stand-in for the refinement / cognition smokes.
#
# Deliberately NOT named smoke_* : run_smokes.sh and smoke_runner.gd glob
# scripts/smoke_*.gd and execute every match. This is a helper, not a smoke —
# it has no SceneTree MainLoop, so being executed booted the whole game and
# hung the run forever. That is what used to stall the aggregate runner.

extends Node

# Minimal sim host for headless smokes (META #15 / #31).
const SimRngScript = preload("res://scripts/sim_rng.gd")

var rng: SimRngScript = SimRngScript.new()
var time_scale: float = 1.0
