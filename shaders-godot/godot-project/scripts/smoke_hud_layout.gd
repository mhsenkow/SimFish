extends SceneTree

# Top-bar geometry (HudLayout).
#
# THE BUG. The stats bar's left edge was a literal - 128 in the scene, 96/88
# at runtime - while the menu cluster next to it is a PanelContainer that
# sizes to its contents. Nothing connected them, so once the cluster grew
# past the guess it slid under the stats chips and the Menu and fullscreen
# buttons stopped being clickable. Translation makes this certain rather
# than likely: the pseudolocale alone renders labels ~40% wider.

const H := preload("res://scripts/hud_layout.gd")


func _init() -> void:
	var t := TestSupport.Suite.new("hud_layout")
	var vw := 1600.0

	# --- the stats bar must never start before the cluster ends -----------
	# This is the whole bug, so it is asserted across every cluster width a
	# translation or UI scale could plausibly produce.
	for cw in [40.0, 80.0, 112.0, 150.0, 210.0, 300.0]:
		var left: float = 8.0
		var inset: float = H.stats_left_inset(left, cw, 0.0, vw)
		t.check(inset >= left + cw,
			"stats bar clears a %.0fpx cluster (inset %.1f)" % [cw, inset])
		t.check(inset >= left + cw + H.CLUSTER_GAP - 0.01,
			"and leaves a gap rather than touching it")

	# A cluster that has not been measured yet must not collapse the bar
	# onto the left edge.
	t.check(H.stats_left_inset(8.0, 0.0, 0.0, vw) >= H.MIN_INSET,
		"an unmeasured cluster falls back to the floor, not to zero")

	# Safe-area padding (notches) shifts both, not one.
	var plain: float = H.stats_left_inset(8.0, 100.0, 0.0, vw)
	var notched: float = H.stats_left_inset(8.0 + 44.0, 100.0, 44.0, vw)
	t.check(notched > plain, "a notch pushes the stats bar across too")

	# A pathological measurement must not push the chips off screen.
	var absurd: float = H.stats_left_inset(8.0, 5000.0, 0.0, vw)
	t.check(absurd <= vw * H.MAX_INSET_FRAC + 0.01,
		"a runaway cluster width is capped (%.1f)" % absurd)
	t.check(absurd < vw, "the stats bar stays on screen")

	# Monotonic: a wider cluster never pulls the bar LEFT.
	var prev: float = -1.0
	for i in 40:
		var cw: float = float(i) * 8.0
		var v: float = H.stats_left_inset(8.0, cw, 0.0, vw)
		t.check(v >= prev - 0.01, "inset never moves left as the cluster grows")
		prev = v

	# --- breakpoints -------------------------------------------------------
	t.equals(H.layout_for(1600.0, false), "wide", "a desktop is wide")
	t.equals(H.layout_for(900.0, false), "medium", "a small window is medium")
	t.equals(H.layout_for(600.0, false), "compact", "a narrow window is compact")
	t.equals(H.layout_for(850.0, true), "compact",
		"a phone stays compact even at 850 - fingers need the room")
	t.equals(H.layout_for(850.0, false), "medium",
		"the same width with a mouse is not compact")
	for w in [320.0, 700.0, 1100.0, 2560.0]:
		t.check(H.layout_for(w, false) in ["compact", "medium", "wide"],
			"always a known layout at %.0f" % w)

	# --- wiring ------------------------------------------------------------
	var m: String = _read("res://scripts/main.gd")
	t.check(m.contains("HudLayout.stats_left_inset("),
		"main.gd derives the inset from the measured cluster")
	t.check(not m.contains('(96.0 if layout != "compact" else 88.0)'),
		"the hard-coded 96/88 guess is gone")
	t.check(m.contains("left_cluster.get_combined_minimum_size()"),
		"and the cluster is actually measured")
	t.check(m.contains("HudLayout.layout_for("),
		"the breakpoints are shared, not duplicated inline")
	# The scene's first-frame default must not contradict the runtime floor.
	var scene: String = _read("res://main.tscn")
	t.check(not scene.contains("offset_left = 128.0"),
		"the scene no longer hard-codes a wider inset than the runtime floor")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt
