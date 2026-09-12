class_name SteamStats
extends RefCounted

# Steam achievements + stats (BROAD_DIRECTIONS #2).
#
# Before this, steam_service.gd only called steamInitEx() — no achievements,
# no stats, no presence. This module owns the achievement contract.
#
# Three design rules, in order:
#
#   1. **Never blocks** (ENGINEERING_CREED). Every Steam call is guarded. With
#      no Steam client, on web, or on Android, this degrades to local-only
#      bookkeeping and the game is unaffected.
#   2. **Earned offline still counts.** Progress is mirrored to
#      user://steam_stats.json, so a player who plays without the Steam client
#      running gets their unlocks pushed on the next session that has it.
#   3. **`evaluate()` is pure.** Achievement logic is a static function of the
#      1 Hz stats payload — no Steam, no scene tree, no clock. That is what
#      smoke_steam_stats.gd exercises.
#
# ACHIEVEMENTS is the source of truth: each api_name here must also exist in
# Steamworks → Achievements with the same API name. `partner_manifest()`
# renders the list for copy-paste so the two cannot drift silently.

const LOCAL_PATH := "user://steam_stats.json"
const LOCAL_VERSION := 1

# Sustained-balance achievement needs the tank held healthy this long
# (sim seconds) rather than passing through the window for one frame.
const BALANCED_HOLD_S: float = 600.0

# Canonical achievement definitions.
#   api_name — must match Steamworks exactly (SCREAMING_SNAKE by convention)
#   title    — display name on the partner site
#   desc     — display description
#   hidden   — Steamworks "hidden until unlocked"
const ACHIEVEMENTS: Array[Dictionary] = [
	{"api_name": "ACH_CYCLED", "title": "Cycled",
	 "desc": "Bring a tank through the nitrogen cycle to established.", "hidden": false,
	 "group": "Foundations", "target": 1.0, "unit": ""},
	{"api_name": "ACH_FIRST_FRY", "title": "New Arrivals",
	 "desc": "See your first fry hatch in a tank you built.", "hidden": false,
	 "group": "Foundations", "target": 1.0, "unit": "fry"},
	{"api_name": "ACH_GEN_3", "title": "Third Generation",
	 "desc": "Raise a lineage to its third generation.", "hidden": false,
	 "group": "Lineage", "target": float(GEN_3), "unit": "gen"},
	{"api_name": "ACH_GEN_10", "title": "Ten Generations Deep",
	 "desc": "Raise a lineage to its tenth generation.", "hidden": false,
	 "group": "Lineage", "target": float(GEN_10), "unit": "gen"},
	{"api_name": "ACH_MORPH_FIRST", "title": "Something New",
	 "desc": "Watch a lineage drift far enough to become its own morph.", "hidden": false,
	 "group": "Lineage", "target": 1.0, "unit": "morph"},
	{"api_name": "ACH_MORPH_5", "title": "Speciation Event",
	 "desc": "Hold five distinct emergent morphs in one tank.", "hidden": false,
	 "group": "Lineage", "target": float(MORPH_5), "unit": "morphs"},
	{"api_name": "ACH_SHRIMP_COLONY", "title": "Colony",
	 "desc": "Grow a shrimp population past twenty-five.", "hidden": false,
	 "group": "Population", "target": float(SHRIMP_COLONY), "unit": "shrimp"},
	{"api_name": "ACH_SNAIL_CREW", "title": "Cleanup Crew",
	 "desc": "Keep ten or more snails working the glass.", "hidden": false,
	 "group": "Population", "target": float(SNAIL_CREW), "unit": "snails"},
	{"api_name": "ACH_JUNGLE", "title": "Jungle",
	 "desc": "Fill a tank with thirty living plants.", "hidden": false,
	 "group": "Population", "target": float(JUNGLE_PLANTS), "unit": "plants"},
	{"api_name": "ACH_FLOWERING", "title": "Above the Waterline",
	 "desc": "Coax an aquatic plant into flowering.", "hidden": false,
	 "group": "Flora", "target": 1.0, "unit": ""},
	{"api_name": "ACH_BALANCED", "title": "Walstad Balance",
	 "desc": "Hold a cycled tank at healthy oxygen and near-zero ammonia, "
		+ "understocked, for ten sim minutes.", "hidden": false,
	 "group": "Foundations", "target": BALANCED_HOLD_S, "unit": "s held"},
	{"api_name": "ACH_LIBRARY_10", "title": "Field Notes",
	 "desc": "Record ten species in the library.", "hidden": false,
	 "group": "Discovery", "target": float(LIBRARY_10), "unit": "species"},
	{"api_name": "ACH_LIBRARY_25", "title": "Taxonomist",
	 "desc": "Record twenty-five species in the library.", "hidden": false,
	 "group": "Discovery", "target": float(LIBRARY_25), "unit": "species"},
	{"api_name": "ACH_OLD_TANK", "title": "Mature Tank",
	 "desc": "Keep a single tank running for a hundred sim days.", "hidden": false,
	 "group": "Foundations", "target": OLD_TANK_DAYS, "unit": "days"},
]

# Thresholds, named so evaluate() reads as intent rather than magic numbers.
const GEN_3: int = 3
const GEN_10: int = 10
const MORPH_5: int = 5
const SHRIMP_COLONY: int = 25
const SNAIL_CREW: int = 10
const JUNGLE_PLANTS: int = 30
const LIBRARY_10: int = 10
const LIBRARY_25: int = 25
const OLD_TANK_DAYS: float = 100.0

# "Healthy" window for ACH_BALANCED.
const BALANCED_O2_MIN: float = 0.6
const BALANCED_AMMONIA_MAX: float = 0.05
const BALANCED_STOCKING_MAX: float = 1.0


# --- Safe coercion ---------------------------------------------------------
# int("not a number") and int(null) both *throw* in GDScript, so a stats
# payload with a corrupted or absent field would take the achievement path
# down with it. Every read in evaluate() goes through these.

static func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key)
	if v == null:
		return fallback
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var sv: String = String(v)
			return float(sv) if sv.is_valid_float() else fallback
		_:
			return fallback


static func _flag(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key)
	if v == null:
		return false
	match typeof(v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		_:
			return false


# --- Pure evaluation -------------------------------------------------------

# Which achievements the given tank state earns, as api_names.
#
# `stats` is sim_driver's 1 Hz stats_changed payload. `extra` carries the
# few facts that payload does not include:
#   cycle_established : bool  — water_chemistry phase == ESTABLISHED
#   library_count     : int   — SpeciesLibrary entry count
#   tank_age_days     : float — sim days on this tank
#   balanced_hold_s   : float — how long the healthy window has held
#   has_flowered      : bool  — a flora flowering event has fired
#
# Pure: same inputs, same output, no side effects. Unknown, missing, null or
# wrong-typed keys are treated as "not earned" rather than raising -- see
# _num()/_flag(), which exist because int("x") and int(null) both throw.
static func evaluate(stats: Dictionary, extra: Dictionary) -> Array[String]:
	var earned: Array[String] = []

	if _flag(extra, "cycle_established"):
		earned.append("ACH_CYCLED")
	if _num(stats, "fish_fry", 0.0) >= 1.0:
		earned.append("ACH_FIRST_FRY")

	var gen: float = _num(stats, "max_generation", 0.0)
	if gen >= float(GEN_3):
		earned.append("ACH_GEN_3")
	if gen >= float(GEN_10):
		earned.append("ACH_GEN_10")

	var morphs: float = _num(stats, "morph_distinct", 0.0)
	if morphs >= 1.0:
		earned.append("ACH_MORPH_FIRST")
	if morphs >= float(MORPH_5):
		earned.append("ACH_MORPH_5")

	if _num(stats, "shrimp_total", 0.0) >= float(SHRIMP_COLONY):
		earned.append("ACH_SHRIMP_COLONY")
	if _num(stats, "snails_total", 0.0) >= float(SNAIL_CREW):
		earned.append("ACH_SNAIL_CREW")
	if _num(stats, "plants_alive", 0.0) >= float(JUNGLE_PLANTS):
		earned.append("ACH_JUNGLE")

	if _flag(extra, "has_flowered"):
		earned.append("ACH_FLOWERING")

	if is_balanced(stats, extra) \
			and _num(extra, "balanced_hold_s", 0.0) >= BALANCED_HOLD_S:
		earned.append("ACH_BALANCED")

	var lib: float = _num(extra, "library_count", 0.0)
	if lib >= float(LIBRARY_10):
		earned.append("ACH_LIBRARY_10")
	if lib >= float(LIBRARY_25):
		earned.append("ACH_LIBRARY_25")

	if _num(extra, "tank_age_days", 0.0) >= OLD_TANK_DAYS:
		earned.append("ACH_OLD_TANK")

	return earned


# Is the tank inside the healthy window right now? Split out so the caller
# can accumulate hold time without duplicating the thresholds.
static func is_balanced(stats: Dictionary, extra: Dictionary) -> bool:
	if not _flag(extra, "cycle_established"):
		return false
	if _num(stats, "dissolved_o2", 0.0) < BALANCED_O2_MIN:
		return false
	if _num(stats, "ammonia", 1.0) > BALANCED_AMMONIA_MAX:
		return false
	if _num(stats, "fish_stocking_ratio", 99.0) > BALANCED_STOCKING_MAX:
		return false
	return true


# Current value toward each milestone, as api_name -> float, in the same
# units as its "target". Pure, same inputs as evaluate() — this is what the
# in-game milestone list reads so the two can never disagree (see
# scripts/milestones.gd, BROAD_DIRECTIONS #3).
static func progress(stats: Dictionary, extra: Dictionary) -> Dictionary:
	var gen: float = _num(stats, "max_generation", 0.0)
	var morphs: float = _num(stats, "morph_distinct", 0.0)
	var lib: float = _num(extra, "library_count", 0.0)
	return {
		"ACH_CYCLED": 1.0 if _flag(extra, "cycle_established") else 0.0,
		"ACH_FIRST_FRY": _num(stats, "fish_fry", 0.0),
		"ACH_GEN_3": gen,
		"ACH_GEN_10": gen,
		"ACH_MORPH_FIRST": morphs,
		"ACH_MORPH_5": morphs,
		"ACH_SHRIMP_COLONY": _num(stats, "shrimp_total", 0.0),
		"ACH_SNAIL_CREW": _num(stats, "snails_total", 0.0),
		"ACH_JUNGLE": _num(stats, "plants_alive", 0.0),
		"ACH_FLOWERING": 1.0 if _flag(extra, "has_flowered") else 0.0,
		"ACH_BALANCED": _num(extra, "balanced_hold_s", 0.0),
		"ACH_LIBRARY_10": lib,
		"ACH_LIBRARY_25": lib,
		"ACH_OLD_TANK": _num(extra, "tank_age_days", 0.0),
	}


# 0..1 completion for one milestone. Targets are never zero in ACHIEVEMENTS,
# but guard anyway rather than dividing by it.
static func fraction(api_name: String, stats: Dictionary, extra: Dictionary) -> float:
	var d: Dictionary = definition(api_name)
	if d.is_empty():
		return 0.0
	var target: float = float(d.get("target", 1.0))
	if target <= 0.0:
		return 0.0
	var current: float = float(progress(stats, extra).get(api_name, 0.0))
	return clampf(current / target, 0.0, 1.0)


static func api_names() -> Array[String]:
	var out: Array[String] = []
	for a in ACHIEVEMENTS:
		out.append(String(a.get("api_name", "")))
	return out


static func definition(api_name: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if String(a.get("api_name", "")) == api_name:
			return a
	return {}


# Markdown table of the achievement contract, for pasting into the
# Steamworks admin pages. Keeps the partner site and the code in step.
static func partner_manifest() -> String:
	var lines: Array[String] = [
		"| API Name | Display Name | Description |",
		"|---|---|---|",
	]
	for a in ACHIEVEMENTS:
		lines.append("| `%s` | %s | %s |" % [
			String(a.get("api_name", "")),
			String(a.get("title", "")),
			String(a.get("desc", "")),
		])
	return "\n".join(lines)


# --- Local mirror ----------------------------------------------------------

# Unlocked api_names recorded locally. Survives sessions with no Steam
# client so they can be pushed later.
static func load_local() -> Dictionary:
	# Bounded + type-checked: this file is user-writable (#6).
	var d: Dictionary = SafeJson.read_dict(LOCAL_PATH, 65_536, "achievements")
	if d.is_empty():
		return {"version": LOCAL_VERSION, "unlocked": []}
	# Drop api_names we no longer ship, so a renamed achievement cannot keep
	# being pushed to Steam forever.
	var known: Array[String] = api_names()
	var clean: Array = []
	var raw_unlocked: Variant = d.get("unlocked")
	if not (raw_unlocked is Array):
		raw_unlocked = []
	for v in (raw_unlocked as Array):
		if known.has(String(v)) and not clean.has(String(v)):
			clean.append(String(v))
	return {"version": int(d.get("version", LOCAL_VERSION)), "unlocked": clean}


static func save_local(state: Dictionary) -> void:
	var f := FileAccess.open(LOCAL_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[walstad_loom] achievement mirror unwritable: %s" % LOCAL_PATH)
		return
	f.store_string(JSON.stringify(state, "  "))
	f.close()
