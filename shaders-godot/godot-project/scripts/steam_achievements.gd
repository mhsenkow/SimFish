class_name SteamAchievements
extends Node

# Drives SteamStats against the live sim and pushes to Steam (BROAD_DIRECTIONS #2).
#
# Owns three things SteamStats deliberately does not:
#   - the hold timer for ACH_BALANCED,
#   - the "flowered at least once" latch (fired by an eco_event, not a stat),
#   - the actual Steam calls, every one of which is guarded.
#
# Attached by steam_service.gd on every platform. Without the Steam client
# (or on web/Android, where GodotSteam is absent) it still tracks progress
# into user://steam_stats.json and pushes nothing — so the next session that
# does have Steam flushes the backlog. Per ENGINEERING_CREED it never blocks:
# any failure here is a warning, not an interruption.

# Rich presence is rewritten at most this often (seconds) — it is a network
# call on Steam's side, so it must not ride the 1 Hz stats signal directly.
const PRESENCE_INTERVAL_S: float = 30.0

# Emitted whenever a milestone is newly earned, on every platform — this is
# what makes progression visible without Steam (BROAD_DIRECTIONS #3).
signal milestone_earned(api_name: String, definition: Dictionary)

var _unlocked: Dictionary = {}          # api_name -> true
var _balanced_hold_s: float = 0.0
var _has_flowered: bool = false
var _presence_timer: float = 0.0
var _last_presence: String = ""
var _steam_ready: bool = false
var _pending_flush: bool = false
# Set by attach(). This node lives under SteamService, not under the sim, so
# it cannot reach the SimDriver through the tree.
var _sim: Node = null
# Latest 1 Hz sample, kept so a UI can render milestone progress on demand
# instead of every panel re-deriving it.
var _last_stats: Dictionary = {}
var _last_extra: Dictionary = {}


func _ready() -> void:
	var state: Dictionary = SteamStats.load_local()
	for api_name in state.get("unlocked", []):
		_unlocked[String(api_name)] = true
	# Anything already earned locally but not yet pushed goes out as soon as
	# Steam reports ready.
	_pending_flush = not _unlocked.is_empty()


# Called by steam_service_desktop once steamInitEx() succeeds.
func set_steam_ready(is_ready: bool) -> void:
	_steam_ready = is_ready
	if is_ready and _pending_flush:
		_flush_to_steam()


# --- Sim hookup ------------------------------------------------------------

# Wire to sim_driver's signals. Safe to call more than once.
func attach(sim: Node) -> void:
	if sim == null:
		return
	_sim = sim
	if sim.has_signal("stats_changed") \
			and not sim.is_connected("stats_changed", _on_stats):
		sim.connect("stats_changed", _on_stats)
	if sim.has_signal("eco_event") and not sim.is_connected("eco_event", _on_eco_event):
		sim.connect("eco_event", _on_eco_event)


func _on_eco_event(kind: String, text: String, _severity: int) -> void:
	# ACH_FLOWERING has no stat to read — plant.gd announces it as an eco
	# event and the flower can be gone by the next 1 Hz sample, so latch it.
	if kind == "flora" and text.to_lower().contains("flower"):
		_has_flowered = true


func _on_stats(stats: Dictionary) -> void:
	var sim: Node = _sim if is_instance_valid(_sim) else null
	# stats_changed fires at 1 Hz, so dt is 1 sim second scaled by time_scale.
	var dt: float = 1.0
	if sim != null and sim.get("time_scale") != null:
		dt = maxf(0.0, float(sim.time_scale))
	var extra: Dictionary = _gather_extra(sim, stats)

	# Hold timer for the sustained-balance achievement. Falling out of the
	# window resets it — the achievement is for keeping a tank balanced, not
	# for touching the window repeatedly.
	if SteamStats.is_balanced(stats, extra):
		_balanced_hold_s += dt
	else:
		_balanced_hold_s = 0.0
	extra["balanced_hold_s"] = _balanced_hold_s
	_last_stats = stats
	_last_extra = extra

	for api_name in SteamStats.evaluate(stats, extra):
		unlock(api_name)

	_presence_timer += dt
	if _presence_timer >= PRESENCE_INTERVAL_S:
		_presence_timer = 0.0
		_update_presence(stats, extra)


# The facts evaluate() needs that the stats payload does not carry.
func _gather_extra(sim: Node, _stats: Dictionary) -> Dictionary:
	var extra: Dictionary = {
		"has_flowered": _has_flowered,
		"cycle_established": false,
		"library_count": 0,
		"tank_age_days": 0.0,
	}
	if sim != null:
		var chem: Variant = sim.get("water_chemistry")
		if chem != null and chem.get("cycle_phase") != null:
			extra["cycle_established"] = \
				int(chem.cycle_phase) == WaterChemistry.CyclePhase.ESTABLISHED
		# sim_day() is the canonical accessor (tank_age_s / SIM_DAY_S); the
		# raw-field path is only for a stripped test double.
		if sim.has_method("sim_day"):
			extra["tank_age_days"] = float(sim.call("sim_day"))
		elif sim.get("tank_age_s") != null:
			extra["tank_age_days"] = float(sim.tank_age_s) / WaterChemistry.SIM_DAY_S
	var lib: Node = get_node_or_null("/root/SpeciesLibrary")
	if lib != null and lib.get("tank_entries") != null:
		var tank_n: int = (lib.tank_entries as Array).size()
		var global_n: int = 0
		if lib.get("global_entries") != null:
			global_n = (lib.global_entries as Array).size()
		extra["library_count"] = maxi(tank_n, global_n)
	return extra


# --- Unlocking -------------------------------------------------------------

# Idempotent. Records locally first so an unlock earned with no Steam client
# is never lost, then pushes if Steam is available.
func unlock(api_name: String) -> bool:
	if api_name.is_empty() or _unlocked.has(api_name):
		return false
	if SteamStats.definition(api_name).is_empty():
		push_warning("[walstad_loom] unknown achievement: %s" % api_name)
		return false
	_unlocked[api_name] = true
	_persist()
	if _steam_ready:
		_push_one(api_name)
	else:
		_pending_flush = true
	# After the local record, so a listener that reads is_unlocked() during
	# the signal sees the new state.
	milestone_earned.emit(api_name, SteamStats.definition(api_name))
	return true


func is_unlocked(api_name: String) -> bool:
	return _unlocked.has(api_name)


func unlocked_count() -> int:
	return _unlocked.size()


func _persist() -> void:
	var names: Array = []
	for k in _unlocked.keys():
		names.append(String(k))
	SteamStats.save_local({"version": SteamStats.LOCAL_VERSION, "unlocked": names})


func _push_one(api_name: String) -> void:
	if not _steam_available():
		return
	Steam.setAchievement(api_name)
	Steam.storeStats()


func _flush_to_steam() -> void:
	if not _steam_available():
		return
	# Steam is the authority. Pull its state first so a reinstall (empty
	# local mirror, achievements already on the account) does not re-fire
	# toasts, and so anything earned offline gets pushed exactly once.
	var pushed: int = 0
	for api_name in SteamStats.api_names():
		var on_steam: bool = bool(Steam.getAchievement(api_name).get("achieved", false))
		if on_steam:
			# Adopt Steam's state locally — this is how progress earned on
			# another machine shows up here.
			_unlocked[api_name] = true
		elif _unlocked.has(api_name):
			Steam.setAchievement(api_name)
			pushed += 1
	if pushed > 0:
		Steam.storeStats()
	_persist()
	_pending_flush = false
	print_verbose("[walstad_loom] achievements reconciled (%d pushed)" % pushed)


# --- Rich presence ---------------------------------------------------------

func _update_presence(stats: Dictionary, extra: Dictionary) -> void:
	if not _steam_available():
		return
	var phase: String = "cycling"
	if bool(extra.get("cycle_established", false)):
		phase = "cycled"
	var text: String = "%s tank · %d fish · %d plants · gen %d" % [
		phase.capitalize(),
		int(stats.get("fish_total", 0)),
		int(stats.get("plants_alive", 0)),
		int(stats.get("max_generation", 0)),
	]
	if text == _last_presence:
		return
	_last_presence = text
	# "steam_display" needs a matching localisation token in the app's rich
	# presence config; #Status_Tank maps to "{#status}".
	Steam.setRichPresence("status", text)
	Steam.setRichPresence("steam_display", "#Status_Tank")


func _steam_available() -> bool:
	return _steam_ready and ClassDB.class_exists("Steam")


# --- Progression surface (BROAD_DIRECTIONS #3) -----------------------------

# api_name -> true. Copied, so a caller cannot mutate our state.
func unlocked_set() -> Dictionary:
	return _unlocked.duplicate()


# Milestone rows against the latest stats sample, for a UI list.
func milestone_rows() -> Array[Dictionary]:
	return Milestones.rows(_last_stats, _last_extra, _unlocked)


# The milestone to point the player at next, or {} when all are earned.
func next_goal() -> Dictionary:
	return Milestones.next_goal(_last_stats, _last_extra, _unlocked)


func summary_label() -> String:
	return Milestones.summary_label(_unlocked)
