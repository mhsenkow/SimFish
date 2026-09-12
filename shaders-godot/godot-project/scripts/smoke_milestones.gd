extends SceneTree

# In-game progression model (BROAD_DIRECTIONS #3).
#
# Milestones are the achievement contract viewed as goals, so the main thing
# to prove is that they cannot drift from it, that "next goal" actually
# points somewhere useful, and that a banked milestone stays banked when the
# live tank regresses.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	var empty: Dictionary = {}

	# --- Every achievement appears exactly once, with usable metadata ---
	var rows: Array[Dictionary] = Milestones.rows(empty, empty)
	TestSupport.check(failed, rows.size() == SteamStats.ACHIEVEMENTS.size(),
		"rows() must cover every achievement (%d vs %d)"
			% [rows.size(), SteamStats.ACHIEVEMENTS.size()])
	TestSupport.check(failed, Milestones.total_count() == SteamStats.ACHIEVEMENTS.size(),
		"total_count() must match the contract")
	var seen: Dictionary = {}
	for r in rows:
		var api_name: String = String(r.get("api_name", ""))
		TestSupport.check(failed, not seen.has(api_name), "duplicate milestone row: %s" % api_name)
		seen[api_name] = true
		TestSupport.check(failed, not String(r.get("title", "")).is_empty(),
			"%s row needs a title" % api_name)
		TestSupport.check(failed, float(r.get("target", 0.0)) > 0.0,
			"%s needs a positive target (progress bars divide by it)" % api_name)
		TestSupport.check(failed, Milestones.GROUP_ORDER.has(String(r.get("group", ""))),
			"%s has group '%s', which is not in GROUP_ORDER"
				% [api_name, String(r.get("group", ""))])
	for n in SteamStats.api_names():
		TestSupport.check(failed, seen.has(n), "rows() dropped %s" % n)

	# --- Fresh tank: nothing earned, nothing complete ---
	for r in rows:
		TestSupport.check(failed, not bool(r.get("earned", false)),
			"%s must not be earned on a fresh tank" % String(r.get("api_name", "")))
		TestSupport.check(failed, is_equal_approx(float(r.get("fraction", -1.0)), 0.0),
			"%s must be 0%% on a fresh tank" % String(r.get("api_name", "")))

	# --- Ordering: Foundations first, cheap tier before expensive ---
	var groups_seen: Array[String] = []
	for r in rows:
		var g: String = String(r.get("group", ""))
		if not groups_seen.has(g):
			groups_seen.append(g)
	var expected_first: String = Milestones.GROUP_ORDER[0]
	TestSupport.check(failed, groups_seen.size() > 0 and groups_seen[0] == expected_first,
		"first group must be '%s', got '%s'"
			% [expected_first, "" if groups_seen.is_empty() else groups_seen[0]])
	# Groups must appear contiguously, in GROUP_ORDER sequence.
	var last_idx: int = -1
	for g in groups_seen:
		var idx: int = Milestones.GROUP_ORDER.find(g)
		TestSupport.check(failed, idx > last_idx, "group '%s' is out of GROUP_ORDER sequence" % g)
		last_idx = idx
	var gen3_pos: int = _row_index(rows, "ACH_GEN_3")
	var gen10_pos: int = _row_index(rows, "ACH_GEN_10")
	TestSupport.check(failed, gen3_pos >= 0 and gen10_pos >= 0 and gen3_pos < gen10_pos,
		"ACH_GEN_3 must list before ACH_GEN_10")

	# --- Progress tracks the sim ---
	var mid: Dictionary = {"shrimp_total": 20, "max_generation": 2}
	var mid_rows: Array[Dictionary] = Milestones.rows(mid, empty)
	var colony: Dictionary = _row(mid_rows, "ACH_SHRIMP_COLONY")
	TestSupport.check(failed, is_equal_approx(float(colony.get("current", 0.0)), 20.0),
		"shrimp progress must read from the stats payload")
	TestSupport.check(failed, absf(float(colony.get("fraction", 0.0)) - 0.8) < 0.01,
		"20/25 shrimp must be 80%%, got %.2f" % float(colony.get("fraction", 0.0)))
	TestSupport.check(failed, Milestones.row_label(colony) == "20 / 25 shrimp",
		"row_label should read '20 / 25 shrimp', got '%s'" % Milestones.row_label(colony))

	# Fraction is clamped — overshooting a target never exceeds 1.0.
	var over: Array[Dictionary] = Milestones.rows({"shrimp_total": 9999}, empty)
	TestSupport.check(failed, float(_row(over, "ACH_SHRIMP_COLONY").get("fraction", 0.0)) <= 1.0,
		"fraction must clamp at 1.0")

	# --- An earned milestone stays earned when the tank regresses ---
	# You do not un-raise a tenth generation by losing the fish.
	var banked: Dictionary = {"ACH_GEN_10": true}
	var regressed: Array[Dictionary] = Milestones.rows({"max_generation": 0}, empty, banked)
	var g10: Dictionary = _row(regressed, "ACH_GEN_10")
	TestSupport.check(failed, bool(g10.get("earned", false)),
		"a banked milestone must stay earned after a population crash")
	TestSupport.check(failed, is_equal_approx(float(g10.get("fraction", 0.0)), 1.0),
		"a banked milestone must read as complete")
	TestSupport.check(failed, Milestones.row_label(g10) == "Earned",
		"a banked milestone's label must be 'Earned'")

	# --- next_goal points at the closest unearned milestone ---
	# 22/25 species is nearer than anything else here, so it should win over
	# milestones that merely come first in the list.
	var deep: Dictionary = {"max_generation": 1}
	var deep_extra: Dictionary = {"library_count": 22}
	var goal: Dictionary = Milestones.next_goal(deep, deep_extra,
		{"ACH_LIBRARY_10": true})
	TestSupport.check(failed, String(goal.get("api_name", "")) == "ACH_LIBRARY_25",
		"next_goal should pick ACH_LIBRARY_25 (22/25), got '%s'"
			% String(goal.get("api_name", "")))
	TestSupport.check(failed, not bool(goal.get("earned", true)),
		"next_goal must never return an earned milestone")

	# All earned -> no goal left.
	var all_unlocked: Dictionary = {}
	for n in SteamStats.api_names():
		all_unlocked[n] = true
	TestSupport.check(failed, Milestones.next_goal(empty, empty, all_unlocked).is_empty(),
		"next_goal must be empty when everything is earned")
	TestSupport.check(failed, Milestones.earned_count(all_unlocked) == Milestones.total_count(),
		"earned_count must match total when all are unlocked")
	# A stale api_name in the unlocked set must not inflate the count.
	var stale: Dictionary = {"ACH_RETIRED": true}
	TestSupport.check(failed, Milestones.earned_count(stale) == 0,
		"earned_count must ignore api_names we no longer ship")

	# --- nearly_there only reports close, unearned milestones ---
	var near: Array[Dictionary] = Milestones.nearly_there(
		{"shrimp_total": 24}, empty)
	var near_names: Array[String] = []
	for r in near:
		near_names.append(String(r.get("api_name", "")))
	TestSupport.check(failed, near_names.has("ACH_SHRIMP_COLONY"),
		"24/25 shrimp should be 'nearly there', got: %s" % ", ".join(near_names))
	TestSupport.check(failed, Milestones.nearly_there({"shrimp_total": 24}, empty,
			{"ACH_SHRIMP_COLONY": true}).is_empty(),
		"nearly_there must skip milestones already earned")
	TestSupport.check(failed, Milestones.nearly_there(empty, empty).is_empty(),
		"a fresh tank has nothing nearly-there")

	# --- Summary label ---
	TestSupport.check(failed, Milestones.summary_label({}) == "0 / %d milestones"
			% Milestones.total_count(),
		"summary_label wrong for a fresh save: %s" % Milestones.summary_label({}))

	# --- Malformed stats must not break the progression model ---
	var junk_rows: Array[Dictionary] = Milestones.rows(
		{"shrimp_total": "lots", "max_generation": null}, {"library_count": []})
	TestSupport.check(failed, junk_rows.size() == SteamStats.ACHIEVEMENTS.size(),
		"rows() must survive a malformed stats payload")
	for r in junk_rows:
		TestSupport.check(failed, float(r.get("fraction", -1.0)) >= 0.0,
			"%s fraction must stay valid on junk input" % String(r.get("api_name", "")))

	quit(TestSupport.report("smoke_milestones", failed))


func _row(rows: Array[Dictionary], api_name: String) -> Dictionary:
	for r in rows:
		if String(r.get("api_name", "")) == api_name:
			return r
	return {}


func _row_index(rows: Array[Dictionary], api_name: String) -> int:
	for i in rows.size():
		if String(rows[i].get("api_name", "")) == api_name:
			return i
	return -1
