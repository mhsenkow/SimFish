extends SceneTree

# Steam achievement contract (BROAD_DIRECTIONS #2).
#
# Runs headless with no Steam client: that is the point. The unlock path must
# track progress locally and push nothing, per ENGINEERING_CREED "never
# blocks" / "offline degrades". SteamStats.evaluate() is pure, so the
# threshold logic is exercised directly.


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []

	# --- Registry integrity ---
	var names: Array[String] = SteamStats.api_names()
	TestSupport.check(failed, names.size() == SteamStats.ACHIEVEMENTS.size(),
		"api_names() must cover every definition")
	var seen: Dictionary = {}
	for n in names:
		TestSupport.check(failed, not n.is_empty(), "achievement api_name must not be empty")
		TestSupport.check(failed, not seen.has(n), "duplicate achievement api_name: %s" % n)
		seen[n] = true
		var d: Dictionary = SteamStats.definition(n)
		TestSupport.check(failed, not String(d.get("title", "")).is_empty(),
			"%s needs a display title" % n)
		TestSupport.check(failed, not String(d.get("desc", "")).is_empty(),
			"%s needs a description" % n)
	TestSupport.check(failed, SteamStats.definition("ACH_DOES_NOT_EXIST").is_empty(),
		"definition() must return empty for an unknown api_name")

	# --- A fresh tank earns nothing ---
	var empty: Dictionary = {}
	TestSupport.check(failed, SteamStats.evaluate(empty, {}).is_empty(),
		"an empty stats payload must earn nothing (got %s)"
			% ", ".join(SteamStats.evaluate(empty, {})))

	# --- Thresholds fire at the boundary, not before ---
	TestSupport.check(failed, not SteamStats.evaluate({"max_generation": 2}, {}).has("ACH_GEN_3"),
		"gen 2 must not earn ACH_GEN_3")
	TestSupport.check(failed, SteamStats.evaluate({"max_generation": 3}, {}).has("ACH_GEN_3"),
		"gen 3 must earn ACH_GEN_3")
	# gen 10 implies gen 3 — achievements are cumulative, not exclusive.
	var g10: Array[String] = SteamStats.evaluate({"max_generation": 10}, {})
	TestSupport.check(failed, g10.has("ACH_GEN_3") and g10.has("ACH_GEN_10"),
		"gen 10 must earn both generation achievements")

	TestSupport.check(failed, SteamStats.evaluate({"fish_fry": 1}, {}).has("ACH_FIRST_FRY"),
		"one fry must earn ACH_FIRST_FRY")
	TestSupport.check(failed, SteamStats.evaluate({"shrimp_total": 25}, {}).has("ACH_SHRIMP_COLONY"),
		"25 shrimp must earn ACH_SHRIMP_COLONY")
	TestSupport.check(failed, not SteamStats.evaluate({"shrimp_total": 24}, {}).has("ACH_SHRIMP_COLONY"),
		"24 shrimp must not earn ACH_SHRIMP_COLONY")
	TestSupport.check(failed, SteamStats.evaluate({"plants_alive": 30}, {}).has("ACH_JUNGLE"),
		"30 plants must earn ACH_JUNGLE")
	TestSupport.check(failed, SteamStats.evaluate({}, {"cycle_established": true}).has("ACH_CYCLED"),
		"established cycle must earn ACH_CYCLED")
	TestSupport.check(failed, SteamStats.evaluate({}, {"library_count": 25}).has("ACH_LIBRARY_10"),
		"25 library entries must also earn the 10 tier")
	TestSupport.check(failed, SteamStats.evaluate({}, {"tank_age_days": 100.0}).has("ACH_OLD_TANK"),
		"100 sim days must earn ACH_OLD_TANK")
	TestSupport.check(failed, SteamStats.evaluate({}, {"has_flowered": true}).has("ACH_FLOWERING"),
		"a flowering latch must earn ACH_FLOWERING")

	# --- ACH_BALANCED needs the full healthy window AND the hold ---
	var healthy: Dictionary = {
		"dissolved_o2": 0.8, "ammonia": 0.0, "fish_stocking_ratio": 0.5,
	}
	var cycled: Dictionary = {"cycle_established": true}
	TestSupport.check(failed, SteamStats.is_balanced(healthy, cycled),
		"healthy + cycled must count as balanced")
	TestSupport.check(failed, not SteamStats.is_balanced(healthy, {}),
		"an uncycled tank is never balanced")
	TestSupport.check(failed, not SteamStats.is_balanced(
			{"dissolved_o2": 0.2, "ammonia": 0.0, "fish_stocking_ratio": 0.5}, cycled),
		"low O2 must not count as balanced")
	TestSupport.check(failed, not SteamStats.is_balanced(
			{"dissolved_o2": 0.8, "ammonia": 0.9, "fish_stocking_ratio": 0.5}, cycled),
		"high ammonia must not count as balanced")
	TestSupport.check(failed, not SteamStats.is_balanced(
			{"dissolved_o2": 0.8, "ammonia": 0.0, "fish_stocking_ratio": 2.0}, cycled),
		"overstocked must not count as balanced")
	# In the window but not held long enough.
	var short_hold: Dictionary = cycled.duplicate()
	short_hold["balanced_hold_s"] = SteamStats.BALANCED_HOLD_S - 1.0
	TestSupport.check(failed, not SteamStats.evaluate(healthy, short_hold).has("ACH_BALANCED"),
		"balance held under the threshold must not earn ACH_BALANCED")
	var full_hold: Dictionary = cycled.duplicate()
	full_hold["balanced_hold_s"] = SteamStats.BALANCED_HOLD_S
	TestSupport.check(failed, SteamStats.evaluate(healthy, full_hold).has("ACH_BALANCED"),
		"balance held to the threshold must earn ACH_BALANCED")

	# --- evaluate() is pure: no mutation of its inputs ---
	var stats_in: Dictionary = {"max_generation": 10, "fish_fry": 3}
	var extra_in: Dictionary = {"library_count": 25, "cycle_established": true}
	var stats_before: int = stats_in.size()
	var extra_before: int = extra_in.size()
	SteamStats.evaluate(stats_in, extra_in)
	TestSupport.check(failed, stats_in.size() == stats_before and extra_in.size() == extra_before,
		"evaluate() must not mutate its arguments")

	# --- Malformed payloads must not crash the achievement path ---
	# int("x") / int(null) throw in GDScript, so every read goes through
	# SteamStats._num()/_flag(). Assert the *result*, not that we got here.
	var junk: Dictionary = {
		"max_generation": "not a number",
		"fish_fry": null,
		"plants_alive": [],
		"shrimp_total": {"nope": 1},
	}
	var junk_earned: Array[String] = SteamStats.evaluate(
		junk, {"library_count": "x", "tank_age_days": null, "cycle_established": "yes"})
	TestSupport.check(failed, junk_earned.is_empty(),
		"a malformed payload must earn nothing, got: %s" % ", ".join(junk_earned))
	# Numeric strings ARE accepted — the stats payload crosses JSON on the
	# save path, where an int can come back as "3".
	TestSupport.check(failed, SteamStats.evaluate({"max_generation": "3"}, {}).has("ACH_GEN_3"),
		"a numeric string must still satisfy a threshold")
	TestSupport.check(failed, not SteamStats.is_balanced(
			{"dissolved_o2": null, "ammonia": null, "fish_stocking_ratio": null},
			{"cycle_established": true}),
		"null vitals must not read as balanced")

	# --- Unlock path with no Steam client ---
	var ach := SteamAchievements.new()
	root.add_child(ach)
	await process_frame
	TestSupport.check(failed, not ach._steam_available(),
		"no Steam client in a headless smoke, so pushes must be disabled")
	var before: int = ach.unlocked_count()
	TestSupport.check(failed, ach.unlock("ACH_CYCLED"), "first unlock returns true")
	TestSupport.check(failed, not ach.unlock("ACH_CYCLED"), "re-unlocking is idempotent")
	TestSupport.check(failed, ach.is_unlocked("ACH_CYCLED"), "unlock is recorded locally")
	TestSupport.check(failed, ach.unlocked_count() == before + 1,
		"unlocked_count advances by exactly one")
	TestSupport.check(failed, not ach.unlock("ACH_NOT_REAL"),
		"an unknown api_name must be refused, not recorded")
	TestSupport.check(failed, not ach.is_unlocked("ACH_NOT_REAL"),
		"a refused unlock must not be stored")

	# attach(null) must be a no-op rather than an error.
	ach.attach(null)
	TestSupport.check(failed, true, "attach(null) survives")

	# --- Local mirror round-trips and drops retired names ---
	SteamStats.save_local({
		"version": SteamStats.LOCAL_VERSION,
		"unlocked": ["ACH_CYCLED", "ACH_RETIRED_NAME", "ACH_CYCLED"],
	})
	var loaded: Dictionary = SteamStats.load_local()
	var unl: Array = loaded.get("unlocked", [])
	TestSupport.check(failed, unl.has("ACH_CYCLED"), "mirror keeps a known api_name")
	TestSupport.check(failed, not unl.has("ACH_RETIRED_NAME"),
		"mirror drops an api_name we no longer ship")
	TestSupport.check(failed, unl.size() == 1, "mirror de-duplicates (got %d)" % unl.size())

	# --- Partner manifest covers every achievement ---
	var manifest: String = SteamStats.partner_manifest()
	for n in names:
		TestSupport.check(failed, manifest.contains(n),
			"partner_manifest() must list %s" % n)

	# Leave no test state behind for the next smoke.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SteamStats.LOCAL_PATH))

	quit(TestSupport.report("smoke_steam_stats", failed))
