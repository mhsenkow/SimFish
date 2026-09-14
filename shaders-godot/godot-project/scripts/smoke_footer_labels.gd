extends SceneTree

# The primary verbs of the game are words when there is room for words
# (VISUAL_DIRECTIONS #18).
#
# A capture of the shipped HUD showed the footer reading
#
#     Feed  Fl  Pt  Wm  Wf  |  Care  H₂O  Fil
#
# on a 1536-wide window with space to spare. Those are unglossed two-letter
# abbreviations for Flakes, Pellets, Worm, Wafer, Water and Filter — the
# primary verbs of the game, rendered as a code the player has to learn.
#
# The strange part is that it was never intended. `UiIcons.FEED` carries a
# readable `name` for every entry, and the comment above it says buttons
# "always show a readable name". The short form is a `force_short` fallback for
# narrow layouts, and both call sites in main.gd passed a hardcoded `true`, so
# the readable path had never once been taken.

const UiIconsScript = preload("res://scripts/ui_icons.gd")
const HudLayoutScript = preload("res://scripts/hud_layout.gd")


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_footer_labels")

	# --- Every food and care action has a word, and it is not the code ---
	for id in UiIconsScript.FEED_SUBTYPE_KEYS:
		var entry: Dictionary = UiIconsScript.FEED[id]
		var word: String = String(entry.get("name", ""))
		var code: String = String(entry.get("text", ""))
		t.check(word.length() >= 4,
			"'%s' needs a readable name, got '%s'" % [id, word])
		t.check(word != code,
			"'%s' name and short code must differ (both '%s')" % [id, word])
		var long_label: String = UiIconsScript.feed_button_label(id, false)
		t.check(long_label.contains(word),
			"the long label for '%s' carries the word (got '%s')" % [id, long_label])
		t.equals(UiIconsScript.feed_button_label(id, true), code,
			"the short label for '%s' is the code" % id)
		t.check(UiIconsScript.feed_tooltip(id).length() > 12,
			"'%s' explains what the food does" % id)

	for id in ["water", "filter"]:
		var entry: Dictionary = UiIconsScript.CARE[id]
		t.check(String(entry.get("name", "")).length() >= 5,
			"care '%s' needs a readable name" % id)
		t.check(UiIconsScript.care_button_label(id, false)
				.contains(String(entry["name"])),
			"the long care label for '%s' carries the word" % id)
		t.equals(UiIconsScript.care_button_label(id, true), String(entry["text"]),
			"the short care label for '%s' is the code" % id)

	# --- Compact is a response to width, not a constant ---
	# This is the regression: both call sites passed `true` unconditionally, so
	# "compact" meant "always".
	t.equals(HudLayoutScript.layout_for(1536.0, false), "wide",
		"a 1536px desktop window is wide")
	t.equals(HudLayoutScript.layout_for(640.0, false), "compact",
		"a 640px window is compact")
	t.equals(HudLayoutScript.layout_for(800.0, true), "compact",
		"a touch device under 900px is compact")
	t.equals(HudLayoutScript.layout_for(1200.0, true), "wide",
		"a wide touch device is not compact")

	var src: String = _read("res://scripts/main.gd")
	t.check(not src.contains("var compact: bool = true"),
		"main.gd must not hardcode the footer to its short labels")
	t.check(src.contains("_footer_labels_compact()"),
		"…it asks whether there is room")
	t.check(src.count("_footer_labels_compact()") >= 5,
		"every feed AND care button site asks, not just one — found %d"
			% src.count("_footer_labels_compact()"))

	# --- The short form still exists and still fits ---
	# Compact is a real mode, not a thing to delete: two letters is what a
	# 640px footer has room for.
	for id in UiIconsScript.FEED_SUBTYPE_KEYS:
		t.check(UiIconsScript.feed_button_label(id, true).length() <= 4,
			"the compact label for '%s' stays short" % id)

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
