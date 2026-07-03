class_name MainUiRefs
extends RefCounted

# PERFORMANCE_UNTHROTTLED #73 — cached autoload refs for hot main.gd paths.

static var _cfg: Node = null
static var _ai: Node = null
static var _glm: Node = null
static var _music: Node = null
static var _species: Node = null
static var _saves: Node = null
static var _ui_ticker: Node = null
static var _night_watch: Node = null
static var _valid: bool = false


static func reset_for_test() -> void:
	_cfg = null
	_ai = null
	_glm = null
	_music = null
	_species = null
	_saves = null
	_ui_ticker = null
	_night_watch = null
	_valid = false


static func bind_from(host: Node) -> void:
	if host == null:
		return
	_cfg = host.get_node_or_null("/root/TankConfig")
	_ai = host.get_node_or_null("/root/AIDirector")
	_glm = host.get_node_or_null("/root/GuardianLlm")
	_music = host.get_node_or_null("/root/MusicContext")
	_species = host.get_node_or_null("/root/SpeciesLibrary")
	_saves = host.get_node_or_null("/root/TankSaves")
	_ui_ticker = host.get_node_or_null("/root/UiTicker")
	_night_watch = host.get_node_or_null("/root/NightWatch")
	_valid = true


static func tank_config(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _cfg if is_instance_valid(_cfg) else null


static func ai_director(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _ai if is_instance_valid(_ai) else null


static func guardian_llm(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _glm if is_instance_valid(_glm) else null


static func music_context(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _music if is_instance_valid(_music) else null


static func species_library(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _species if is_instance_valid(_species) else null


static func tank_saves(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _saves if is_instance_valid(_saves) else null


static func ui_ticker(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _ui_ticker if is_instance_valid(_ui_ticker) else null


static func night_watch(host: Node = null) -> Node:
	if not _valid and host != null:
		bind_from(host)
	return _night_watch if is_instance_valid(_night_watch) else null
