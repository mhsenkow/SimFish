extends SceneTree

# Care actions land in the tank, not on the button (VISUAL_DIRECTIONS #16).
#
# Feed, water change, filter rinse, glass wipe — every one changes the sim, and
# the strongest visual feedback any of them produced was `_pulse_care_dock()`,
# which flashes the button the player just pressed, plus a toast saying in
# words what happened. In a game whose pitch is a living picture, words are the
# fallback, not the channel.
#
# These pin the grammar: same four questions for every action, answered
# differently, and never answered with a constant.

const CF = preload("res://scripts/care_feedback.gd")

const ACTIONS: Array[String] = ["water_change", "filter_rinse", "glass_wipe", "feed"]


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_care_feedback")

	# --- Every action has an answer, and unknown ones do not invent one ---
	for a in ACTIONS:
		t.check(CF.is_known(a), "'%s' has a feedback event" % a)
	t.check(not CF.is_known("nonsense"), "an unknown action produces nothing")
	t.check(CF.event_for("", 0.5).is_empty(), "an empty action produces nothing")

	# --- Magnitude actually matters: no constant responses ---
	for a in ACTIONS:
		var small: Dictionary = CF.event_for(a, 0.05)
		var large: Dictionary = CF.event_for(a, 1.0)
		t.check(float(large["duration_s"]) > float(small["duration_s"]),
			"'%s' must read longer when it matters more" % a)
		t.check(int(large["bursts"]) >= int(small["bursts"]),
			"'%s' must not spend fewer bursts on a bigger effect" % a)

	# --- Duration is bounded at both ends ---
	for a in ACTIONS:
		for m: float in [0.0, 0.25, 0.5, 0.75, 1.0, 4.0, -2.0]:
			var e: Dictionary = CF.event_for(a, m)
			t.in_range(float(e["duration_s"]), CF.MIN_DURATION_S, CF.MAX_DURATION_S,
				"'%s' at magnitude %.2f stays inside the read window" % [a, m])
			t.check(int(e["bursts"]) >= 1, "'%s' always spends at least one burst" % a)
			t.in_range(float(e["glass_wipe"]), 0.0, 1.0, "'%s' wipe in range" % a)
			t.in_range(float(e["substrate_disturb"]), 0.0, 1.0,
				"'%s' disturb in range" % a)

	# --- The actions are distinguishable from each other ---
	# A grammar where every action looks the same is a flash, not a language.
	var seen_colors: Dictionary = {}
	for a in ACTIONS:
		var c: Color = CF.event_for(a, 0.8)["color"]
		var key: String = "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
		t.check(not seen_colors.has(key),
			"'%s' shares a colour with '%s'" % [a, str(seen_colors.get(key, "?"))])
		seen_colors[key] = a

	# --- Each action's emphasis matches what it does ---
	var wipe_e: Dictionary = CF.event_for("glass_wipe", 1.0)
	t.check(float(wipe_e["glass_wipe"]) > 0.8,
		"a glass wipe's whole point is that the glass gets clean")
	t.approx(float(wipe_e["substrate_disturb"]), 0.0,
		"…and it does not stir the substrate", 0.001)
	var rinse_e: Dictionary = CF.event_for("filter_rinse", 1.0)
	t.check(float(rinse_e["substrate_disturb"]) > 0.3,
		"a filter rinse lifts silt")
	t.check(not bool(rinse_e["at_surface"]),
		"…at the intake, not at the waterline")
	var water_e: Dictionary = CF.event_for("water_change", 1.0)
	t.check(bool(water_e["at_surface"]),
		"a fill happens at the surface")
	t.check(float(water_e["duration_s"]) >= float(rinse_e["duration_s"]),
		"the action visible from across the room gets the longest read")

	# --- Burst placement spreads, and is stable ---
	for n in [1, 2, 3, 6]:
		var offs: Array[Vector3] = CF.burst_offsets(n, 2.0)
		t.equals(offs.size(), n, "%d bursts, %d offsets" % [n, n])
		for o in offs:
			t.check(o.length() <= 2.001,
				"a burst offset stays inside the spread (got %.2f)" % o.length())
			t.approx(o.y, 0.0, "offsets are horizontal", 0.0001)
		if n > 1:
			# Distinct positions — otherwise a multi-burst event is one puff
			# drawn several times.
			var uniq: Dictionary = {}
			for o in offs:
				uniq["%.3f,%.3f" % [o.x, o.z]] = true
			t.equals(uniq.size(), n, "%d bursts land in %d places" % [n, n])
	t.equals(CF.burst_offsets(0, 2.0).size(), 1,
		"zero bursts still yields one placement rather than nothing")
	t.equals(CF.burst_offsets(-4, 2.0).size(), 1, "…and so does a negative count")

	# --- The driver and the call sites exist ---
	var world_src: String = _read("res://scripts/world.gd")
	t.check(world_src.contains("func play_care_feedback"),
		"world.gd can spend a care event")
	t.check(world_src.contains("TransientParticlePool.burst"),
		"…using the pool that already exists")
	var main_src: String = _read("res://scripts/main.gd")
	t.check(main_src.contains('_play_care_feedback("water_change"'),
		"a water change reaches the tank")
	t.check(main_src.contains('_play_care_feedback("filter_rinse"'),
		"a filter rinse reaches the tank")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
