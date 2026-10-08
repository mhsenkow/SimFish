extends "res://scripts/main.gd"

var deliveries: Dictionary = {}

func _exit_tree() -> void:
	pass

func schedule() -> void:
	_defer_voice_presentation(func() -> void: deliveries.count += 1, 0.05)
