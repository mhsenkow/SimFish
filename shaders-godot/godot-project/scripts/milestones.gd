class_name Milestones
extends RefCounted

# In-game progression model (BROAD_DIRECTIONS #3).
#
# Before this the project had no progression layer at all: no goals, no
# milestones, no unlocks. The sim already tracked everything needed
# (succession, generations, morph drift, the species library) and nothing
# consumed it.
#
# Deliberately NOT a second definition list. Milestones ARE the achievement
# contract in `steam_stats.gd`, viewed as goals rather than trophies — so the
# in-game list and the Steam overlay can never disagree, and progression works
# identically on web/Android/DRM-free builds where Steam does not exist.
#
# This model is pure and Steam-free. `steam_achievements.gd` owns the unlock
# side effects; this owns "what should the player be reaching for next".

# A milestone within this fraction of done is "close" — worth nudging about.
const NEARLY_THERE: float = 0.75

# Groups, in the order a list should show them: foundations first, because a
# player who has not cycled a tank should not be reading about speciation.
const GROUP_ORDER: Array[String] = [
	"Foundations",
	"Population",
	"Flora",
	"Lineage",
	"Discovery",
]


# One row per milestone, ready for a UI list.
#
#   api_name, title, desc, group   — from the achievement contract
#   current, target, unit          — progress, in the milestone's own units
#   fraction                       — 0..1
#   earned                         — bool, from the passed-in unlocked set
#
# `unlocked` is api_name -> true (SteamAchievements keeps exactly that shape),
# so a milestone already banked stays earned even if the live tank no longer
# satisfies it — you do not un-raise a tenth generation by losing the fish.
static func rows(stats: Dictionary, extra: Dictionary,
		unlocked: Dictionary = {}) -> Array[Dictionary]:
	var prog: Dictionary = SteamStats.progress(stats, extra)
	var out: Array[Dictionary] = []
	for d in SteamStats.ACHIEVEMENTS:
		var api_name: String = String(d.get("api_name", ""))
		var target: float = float(d.get("target", 1.0))
		var current: float = float(prog.get(api_name, 0.0))
		var earned: bool = unlocked.has(api_name)
		out.append({
			"api_name": api_name,
			"title": String(d.get("title", "")),
			"desc": String(d.get("desc", "")),
			"group": String(d.get("group", "Foundations")),
			"unit": String(d.get("unit", "")),
			"current": current,
			"target": target,
			"fraction": 1.0 if earned else clampf(current / maxf(target, 0.0001), 0.0, 1.0),
			"earned": earned,
		})
	out.sort_custom(_by_group_then_target)
	return out


# Foundations before Lineage; within a group, the cheaper tier first so
# ACH_GEN_3 lists above ACH_GEN_10.
static func _by_group_then_target(a: Dictionary, b: Dictionary) -> bool:
	var ga: int = GROUP_ORDER.find(String(a.get("group", "")))
	var gb: int = GROUP_ORDER.find(String(b.get("group", "")))
	# An unrecognised group sorts last rather than first.
	if ga < 0:
		ga = GROUP_ORDER.size()
	if gb < 0:
		gb = GROUP_ORDER.size()
	if ga != gb:
		return ga < gb
	var ta: float = float(a.get("target", 0.0))
	var tb: float = float(b.get("target", 0.0))
	if ta != tb:
		return ta < tb
	return String(a.get("api_name", "")) < String(b.get("api_name", ""))


# The single milestone to point the player at: the unearned one they are
# closest to finishing. Returns {} when everything is earned.
#
# Closest-by-fraction rather than first-in-order, because "you are 22 of 25
# species in" is a far better nudge than "you have not cycled a tank" to
# someone 400 sim days deep.
static func next_goal(stats: Dictionary, extra: Dictionary,
		unlocked: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_frac: float = -1.0
	for row in rows(stats, extra, unlocked):
		if bool(row.get("earned", false)):
			continue
		var f: float = float(row.get("fraction", 0.0))
		if f > best_frac:
			best_frac = f
			best = row
	return best


# Milestones that are close but not yet earned — the "one more shrimp" set.
static func nearly_there(stats: Dictionary, extra: Dictionary,
		unlocked: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows(stats, extra, unlocked):
		if bool(row.get("earned", false)):
			continue
		if float(row.get("fraction", 0.0)) >= NEARLY_THERE:
			out.append(row)
	return out


static func earned_count(unlocked: Dictionary) -> int:
	var n: int = 0
	for api_name in SteamStats.api_names():
		if unlocked.has(api_name):
			n += 1
	return n


static func total_count() -> int:
	return SteamStats.ACHIEVEMENTS.size()


# "3 / 14 milestones" for a header.
static func summary_label(unlocked: Dictionary) -> String:
	return "%d / %d milestones" % [earned_count(unlocked), total_count()]


# Progress text for one row, e.g. "18 / 25 species" or "held 240s / 600s held".
static func row_label(row: Dictionary) -> String:
	if bool(row.get("earned", false)):
		return "Earned"
	var target: float = float(row.get("target", 1.0))
	var current: float = float(row.get("current", 0.0))
	var unit: String = String(row.get("unit", ""))
	# A one-shot milestone reads as a state, not a count.
	if target <= 1.0:
		return "Not yet"
	var suffix: String = (" %s" % unit) if not unit.is_empty() else ""
	return "%d / %d%s" % [int(current), int(target), suffix]
