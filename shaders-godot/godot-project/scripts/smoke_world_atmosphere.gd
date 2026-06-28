extends SceneTree

const WorldAtmosphere = preload("res://scripts/world_atmosphere.gd")


func _init() -> void:
	var ln: Dictionary = WorldAtmosphere.day_night_lighting(null, null)
	if not ln.has("dl"):
		push_error("missing dl key")
		quit(1)
	print("[smoke_world_atmosphere] OK")
	quit()
