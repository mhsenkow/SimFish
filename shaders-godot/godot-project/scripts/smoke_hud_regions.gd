extends SceneTree

# HudLayout.regions(): the screen carved into named HUD regions.
#
# The HUD bug class this guards: two things docking into the same rect. Side
# panels sat 8 px under the stats bar (HUD_TOP was 44, the bar ends at 52),
# the footer hung 8 px off-screen (48 vs 56), and the follow-thought strip,
# the toast stack and the bottom-centre toasts each picked a spot that
# ignored the others. Regions are the single statement of who owns which
# rect, so they must be disjoint and on-screen for every column state that
# can actually occur — both columns at a wide window; one column at a time
# where COLUMNS_EXCLUSIVE says both do not fit.

const H := preload("res://scripts/hud_layout.gd")

# CENTRE_MODAL sits over everything behind a scrim — it is not disjoint by
# design, only inside the viewport.
const DISJOINT: Array[String] = ["TOP_BAR", "RAIL", "BOTTOM_BAR", "LEFT_COLUMN",
	"RIGHT_COLUMN", "BOTTOM_LEFT_STACK", "BOTTOM_CENTRE"]


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_hud_regions")
	# Measured chrome of the shipped HUD: top bar ends at 52, footer is 56 tall,
	# rail cluster 64 px from the right edge.
	for vp in [Vector2(1536, 864), Vector2(900, 600), Vector2(1152, 648)]:
		var rail_left: float = vp.x - 64.0
		var probe: Dictionary = H.regions(vp, Vector4.ZERO, "right", 52.0, 56.0, rail_left)
		var excl: bool = bool(probe.get(H.COLUMNS_EXCLUSIVE, false))
		var states: Array = [[false, false], [true, false], [false, true]]
		if not excl:
			states.append([true, true])
		for st in states:
			var lo: bool = st[0]
			var ro: bool = st[1]
			var r: Dictionary = H.regions(vp, Vector4.ZERO, "right", 52.0, 56.0,
				rail_left, lo, ro)
			var tag: String = "%dx%d L=%s R=%s" % [int(vp.x), int(vp.y), lo, ro]
			for k in H.REGION_KEYS:
				t.check(r.has(k) and r[k] is Rect2, "%s: region %s present" % [tag, k])
				var rect: Rect2 = r.get(k, Rect2())
				t.check(rect.size.x > 0.0 and rect.size.y > 0.0,
					"%s: %s has area (%s)" % [tag, k, rect])
				t.check(Rect2(Vector2.ZERO, vp).encloses(rect),
					"%s: %s inside the viewport (%s)" % [tag, k, rect])
			# Only regions that can be occupied together must be disjoint: a
			# closed column's rect is free for the bottom band to use.
			var live: Array[String] = []
			for k in DISJOINT:
				if (k == "LEFT_COLUMN" and not lo) or (k == "RIGHT_COLUMN" and not ro):
					continue
				live.append(k)
			for i in live.size():
				for j in range(i + 1, live.size()):
					var a: Rect2 = r[live[i]]
					var b: Rect2 = r[live[j]]
					t.check(not a.intersects(b),
						"%s: %s %s overlaps %s %s" % [tag, live[i], a, live[j], b])
			var stack: Rect2 = r["BOTTOM_LEFT_STACK"]
			t.check(stack.size.y <= (r["LEFT_COLUMN"] as Rect2).size.y * H.STACK_MAX_FRAC + 0.5,
				"%s: bottom-left stack height-capped (%.0f)" % [tag, stack.size.y])
			t.check((r["BOTTOM_CENTRE"] as Rect2).size.x <= H.CENTRE_W + 0.5,
				"%s: bottom-centre slot is a slot, not full width" % tag)
		# The panel columns start below the MEASURED top bar and end above
		# the MEASURED footer.
		var col: Rect2 = probe["LEFT_COLUMN"]
		t.check(col.position.y >= 52.0, "%dx%d: column clears the top bar" % [vp.x, vp.y])
		t.check(col.end.y <= vp.y - 56.0, "%dx%d: column clears the footer" % [vp.x, vp.y])
	t.check(not bool(H.regions(Vector2(1536, 864), Vector4.ZERO, "right", 52.0, 56.0,
		1472.0).get(H.COLUMNS_EXCLUSIVE, true)), "1536 wide: both columns fit")
	t.check(bool(H.regions(Vector2(900, 600), Vector4.ZERO, "right", 52.0, 56.0,
		836.0).get(H.COLUMNS_EXCLUSIVE, false)), "900 wide: columns exclusive")
	# Safe-area insets move every region inside them.
	var notch: Dictionary = H.regions(Vector2(900, 600), Vector4(40, 20, 40, 20),
		"right", 72.0, 76.0, 796.0)
	t.check((notch["LEFT_COLUMN"] as Rect2).position.x >= 40.0, "left inset respected")
	# Source contracts: main places through the regions, and the manager
	# watches visibility instead of trusting notify_* calls.
	var m: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	t.check(m.contains("HudLayout.regions("), "main.gd computes HudLayout.regions()")
	t.check(m.contains("_ui_panels.relayout("), "main.gd hands regions to UiPanelManager")
	var u: String = FileAccess.get_file_as_string("res://scripts/ui_panel_manager.gd")
	t.check(u.contains("visibility_changed.connect(_on_entry_visibility"),
		"UiPanelManager watches visibility_changed")
	t.check(u.contains("func close_top("), "UiPanelManager has an Escape order")
	quit(t.finish())
