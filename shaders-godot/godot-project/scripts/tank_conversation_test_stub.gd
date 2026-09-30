# Sim stand-in for smoke_tank_conversation.gd.
#
# Deliberately NOT named smoke_* : run_smokes.sh and smoke_runner.gd glob
# scripts/smoke_*.gd and execute every match. This is a helper, not a smoke.

extends Node


class Chem:
	extends RefCounted
	var ammonia: float = 0.02
	var nitrite: float = 0.0
	var nitrate: float = 0.1


var fish: Array = []
var day_phase: float = 0.4
var dissolved_o2: float = 0.9
var stability: float = 0.85
var story_events: Array = []
var water_chemistry: Chem = Chem.new()
@warning_ignore("unused_private_class_variable")
var _spark_night_cathedral: bool = false
@warning_ignore("unused_private_class_variable")
var _tank_mind: Dictionary = {}
var daylight_value: float = 0.8
var tank_age_s: float = 1000.0
@warning_ignore("unused_private_class_variable")
var _last_feed_unix: int = 0


func daylight() -> float:
	return daylight_value


func fish_carrying_capacity() -> int:
	return 12
