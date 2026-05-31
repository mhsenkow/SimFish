# Desktop Steam API init (loaded dynamically when GodotSteam GDExtension is present).
extends Node

const APP_ID := 4796460

var is_steam_running := false


func _ready() -> void:
	# steamInitEx(app_id, embed_callbacks) — order matters; bool first was wrong.
	var init: Dictionary = Steam.steamInitEx(APP_ID, true)
	var status: int = int(init.get("status", -1))
	is_steam_running = status == Steam.STEAM_API_INIT_RESULT_OK
	if is_steam_running:
		var user_label := "unknown"
		if Steam.isSteamRunning():
			user_label = Steam.getPersonaName()
		print("[walstad_loom] Steam initialized (AppID %d, user %s)" % [APP_ID, user_label])
	else:
		push_warning("[walstad_loom] Steam init failed: %s" % str(init.get("verbal", init)))


func _process(_delta: float) -> void:
	if is_steam_running:
		Steam.run_callbacks()
