# Desktop Steam API init (loaded dynamically when GodotSteam GDExtension is present).
extends Node

const APP_ID := 4796460

var is_steam_running := false


func _ready() -> void:
	var init: Dictionary = Steam.steamInitEx(true, APP_ID)
	var status: int = int(init.get("status", 0))
	is_steam_running = status == 1
	if is_steam_running:
		print("[walstad_loom] Steam initialized (AppID %d, user %s)" % [
			APP_ID,
			Steam.getPersonaName(),
		])
	else:
		push_warning("[walstad_loom] Steam init failed: %s" % str(init.get("verbal", init)))


func _process(_delta: float) -> void:
	if is_steam_running:
		Steam.run_callbacks()
