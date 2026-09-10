# Sim stand-in for smoke_night_watch.gd.
#
# Deliberately NOT named smoke_* : run_smokes.sh and smoke_runner.gd glob
# scripts/smoke_*.gd and execute every match. This is a helper, not a smoke —
# it has no SceneTree MainLoop, so being executed booted the whole game and
# hung the run forever. That is what used to stall the aggregate runner.

extends RefCounted

var fish: Array = []
var day_phase: float = 0.78
var dissolved_o2: float = 0.9
var stability: float = 0.85
var _away_dream_count: int = 0
var story_events: Array = []
var _spark_night_cathedral: bool = false
var _tank_mind: Dictionary = {}


func daylight() -> float:
	return 0.08


func fish_carrying_capacity() -> int:
	return 12
