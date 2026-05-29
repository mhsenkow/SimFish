# Autoload stub — loads desktop Steam init only when GodotSteam is present.
extends Node


func _ready() -> void:
	if OS.has_feature("web") or OS.has_feature("android"):
		return
	if not ClassDB.class_exists("Steam"):
		push_warning("[walstad_loom] GodotSteam not installed; run steam/install_godotsteam.sh")
		return
	var desktop: Node = load("res://scripts/steam_service_desktop.gd").new()
	add_child(desktop)
