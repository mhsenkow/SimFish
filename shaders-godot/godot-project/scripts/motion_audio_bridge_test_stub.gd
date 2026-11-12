extends Node

# Stub AmbientAudio for smoke_motion_audio_bridge — records pan + SFX calls.

var last_pan_pos: Vector3 = Vector3.INF
var startle_calls: int = 0
var eat_calls: int = 0
var bubble_calls: int = 0
var last_startle_intensity: float = -1.0


func reset_counts() -> void:
	startle_calls = 0
	eat_calls = 0
	bubble_calls = 0
	last_startle_intensity = -1.0
	last_pan_pos = Vector3.INF


func set_event_world_pos(pos: Vector3) -> void:
	last_pan_pos = pos


func play_startle_sfx(_intensity: float = 0.5) -> void:
	startle_calls += 1
	last_startle_intensity = _intensity


func play_eat_sfx(_intensity: float = 0.5) -> void:
	eat_calls += 1


func play_bubble_sfx(_intensity: float = 0.2) -> void:
	bubble_calls += 1
