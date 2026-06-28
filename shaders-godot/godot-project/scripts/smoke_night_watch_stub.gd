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
