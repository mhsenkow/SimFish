extends SceneTree

# Notification centre contract (messaging consolidation).
#
# The panel was ~407 lines inside main.gd, with its filter/sort logic
# duplicated in `_mark_visible_notifications_read` — so once the panel owned
# that state, main's copy went stale and "mark visible read" would have
# marked the wrong set. Filtering now lives in one place and is pure, which
# is what lets this test it directly.


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_notifications_panel")

	var p := NotificationsPanel.new()
	root.add_child(p)
	await process_frame

	var now: int = 1_000_000
	var src: Array = [
		{"kind": "care", "severity": "info", "title": "Fed", "body": "b", "ts": now - 10},
		{"kind": "water_alert", "severity": "critical", "title": "Low O2",
			"body": "b", "ts": now - 300},
		{"kind": "milestone", "severity": "important", "title": "Cycled",
			"body": "b", "ts": now - 60},
		{"kind": "care", "severity": "info", "title": "Rinsed", "body": "b", "ts": now - 5},
	]

	# --- Default: everything, newest first ---
	var rows: Array[Dictionary] = p.visible_rows(src)
	t.equals(rows.size(), 4, "no filter shows everything")
	t.equals(String(rows[0]["title"]), "Rinsed", "default sort is newest first")
	t.equals(String(rows[3]["title"]), "Low O2", "oldest lands last")

	# --- Sort: oldest ---
	p._on_sort_selected(NotificationsPanel.Sort.OLDEST)
	rows = p.visible_rows(src)
	t.equals(String(rows[0]["title"]), "Low O2", "oldest-first reverses the order")

	# --- Sort: severity, with recency as the tiebreak ---
	p._on_sort_selected(NotificationsPanel.Sort.SEVERITY)
	rows = p.visible_rows(src)
	t.equals(String(rows[0]["title"]), "Low O2", "critical sorts to the top")
	t.equals(String(rows[1]["title"]), "Cycled", "important comes next")
	t.equals(String(rows[2]["title"]), "Rinsed",
		"equal severity falls back to newest-first")
	p._on_sort_selected(NotificationsPanel.Sort.NEWEST)

	# --- Severity filter ---
	p._on_severity_selected(3)   # critical
	rows = p.visible_rows(src)
	t.equals(rows.size(), 1, "critical filter shows only critical")
	t.equals(String(rows[0]["severity"]), "critical", "and it is the right one")
	p._on_severity_selected(0)
	t.equals(p.visible_rows(src).size(), 4, "clearing the filter restores all")

	# --- Severity ranking ---
	t.check(NotificationsPanel.severity_rank("critical")
			> NotificationsPanel.severity_rank("important"),
		"critical outranks important")
	t.check(NotificationsPanel.severity_rank("important")
			> NotificationsPanel.severity_rank("info"),
		"important outranks info")
	t.equals(NotificationsPanel.severity_rank("nonsense"),
		NotificationsPanel.severity_rank("info"),
		"an unknown severity ranks as info rather than throwing")

	# --- Malformed entries are skipped, not fatal ---
	var junk: Array = [null, "a string", 42, {"kind": "care", "ts": now}]
	t.equals(p.visible_rows(junk).size(), 1,
		"non-Dictionary entries must be skipped")
	t.equals(p.visible_rows([]).size(), 0, "an empty store yields no rows")

	# --- Age formatting ---
	t.equals(NotificationsPanel.format_age(now - 30, now), "30s ago", "seconds")
	t.equals(NotificationsPanel.format_age(now - 300, now), "5m ago", "minutes")
	t.equals(NotificationsPanel.format_age(now - 7200, now), "2h ago", "hours")
	t.equals(NotificationsPanel.format_age(now - 172800, now), "2d ago", "days")
	t.equals(NotificationsPanel.format_age(now + 500, now), "0s ago",
		"a future timestamp must not produce a negative age")

	# --- Rendering ---
	p.refresh(src)
	await process_frame
	t.check(p.build_row(src[0]) != null, "a row builds")
	# Severity stripe matches the toast accent, so a message reads the same
	# urgency wherever it appears.
	var crit_row: Control = p.build_row(src[1])
	var sb: StyleBox = crit_row.get_theme_stylebox("panel")
	var flat := sb as StyleBoxFlat
	t.check(flat != null, "row uses a StyleBoxFlat")
	if flat != null:
		var want: Color = Toast.LEVEL_ACCENT[Toast.Level.CRITICAL]
		t.approx(flat.border_color.r, want.r,
			"a critical row's stripe matches the critical toast accent", 0.01)

	# --- The empty state distinguishes "nothing" from "filtered out" ---
	# The same message for both is how a filter gets left on by accident.
	var src_txt: String = FileAccess.get_file_as_string(
		"res://scripts/notifications_panel.gd")
	t.check(src_txt.contains("No notifications yet.")
			and src_txt.contains("No notifications match this filter."),
		"empty state must distinguish an empty store from an empty filter")

	# --- main no longer duplicates the filtering ---
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	t.check(main_src.contains("_notifications_panel.visible_rows("),
		"main must ask the panel what is visible rather than re-filtering")
	t.check(not main_src.contains("var _notification_filter_kind"),
		"main must not keep its own copy of the panel's filter state")

	p.free()
	quit(t.finish())
