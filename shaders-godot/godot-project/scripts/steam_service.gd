# Autoload stub — owns achievement tracking on every platform, and loads
# desktop Steam init only when GodotSteam is present.
extends Node

# Achievement tracking runs everywhere (BROAD_DIRECTIONS #2): web and Android
# have no GodotSteam, but a player who earns something there should still see
# it unlock the next time they open a Steam build on the same machine, so the
# local mirror is kept regardless. Steam pushes are guarded inside the node.
var achievements: SteamAchievements = null

var _desktop: Node = null


func _ready() -> void:
	achievements = SteamAchievements.new()
	achievements.name = "Achievements"
	add_child(achievements)

	# Steam API is for shipped desktop builds; skip editor to avoid init noise.
	if Engine.is_editor_hint():
		return
	if OS.has_feature("web") or OS.has_feature("android"):
		return
	if not ClassDB.class_exists("Steam"):
		push_warning("[walstad_loom] GodotSteam not installed; run steam/install_godotsteam.sh")
		return
	_desktop = load("res://scripts/steam_service_desktop.gd").new()
	add_child(_desktop)


# Called by main.gd once the SimDriver exists, so achievements can follow the
# 1 Hz stats signal. Safe to call repeatedly.
func attach_sim(sim: Node) -> void:
	if achievements != null:
		achievements.attach(sim)


func is_steam_running() -> bool:
	return _desktop != null and bool(_desktop.is_steam_running)
