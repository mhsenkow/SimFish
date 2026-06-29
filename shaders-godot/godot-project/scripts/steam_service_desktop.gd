# Desktop Steam API init (loaded dynamically when GodotSteam GDExtension is present).
extends Node

const APP_ID := 4796460

var is_steam_running := false

# Expected when launching outside the Steam client (editor F5, Finder, dev builds).
const _BENIGN_INIT_FRAGMENTS = [
	"Could not determine Steam client install directory",
	"ConnectToGlobalUser failed",
	"SteamAPI_Init(): SteamAPI_IsSteamRunning() returned false",
	"SteamAPI_Init(): Failed to initialize",
]


func _benign_steam_unavailable(verbal: String) -> bool:
	var v: String = verbal.to_lower()
	for frag in _BENIGN_INIT_FRAGMENTS:
		if v.findn(frag.to_lower()) != -1:
			return true
	return false


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
		var verbal: String = str(init.get("verbal", init))
		if _benign_steam_unavailable(verbal):
			print_verbose("[walstad_loom] Steam unavailable in this session: %s" % verbal)
		else:
			push_warning("[walstad_loom] Steam init failed: %s" % verbal)


func _process(_delta: float) -> void:
	if is_steam_running:
		Steam.run_callbacks()
