extends SceneTree

# Panel contract (UI consistency pass).
#
# The Mind panel shipped with no close button, no `_close_*` function and no
# entry in the Escape cascade — it could be opened and then not dismissed.
# Nothing caught that, because "is this panel closable" was a convention
# rather than a checked contract.
#
# Every player-facing panel must be dismissable THREE ways, because players
# reach for different ones:
#   1. a visible Close control,
#   2. the Escape key,
#   3. its own rail/menu toggle.
#
# Source-inspected rather than instantiated: panels need main, the theme and
# several autoloads, none of which a `--script` run mounts.

# panel script -> the main.gd close function that must dismiss it.
const PANELS: Dictionary = {
	"mind_panel.gd": "close_mind_panel",
	"camera_views_panel.gd": "_close_camera_views_panel",
	"residents_panel.gd": "_close_residents_panel",
	"notifications_panel.gd": "close_notifications_panel",
	"vessel_picker.gd": "close_vessel_picker",
}

# Panels reached through UiPanelManager instead of a bespoke close function.
const MANAGED_PANELS: Array[String] = [
	"settings_panel.gd", "render_panel.gd", "sound_panel.gd",
	"library_panel.gd", "adopt_panel.gd",
]


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_panel_contract")
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	t.check(not main_src.is_empty(), "main.gd readable")

	# --- 1. Every panel offers a visible way out ---
	for name in _all_panels():
		var src: String = FileAccess.get_file_as_string("res://scripts/" + name)
		if src.is_empty():
			continue
		var has_footer: bool = src.contains("make_panel_footer")
		var has_close: bool = src.contains("make_close_button")
		var has_header: bool = src.contains("make_panel_header")
		t.check(has_footer or has_close or has_header,
			"%s has no Close control — it can be opened and not dismissed. "
				% name
			+ "Use PanelTheme.make_panel_footer(on_close).")

	# --- 2. Bespoke panels have a close function, and Escape reaches it ---
	for name in PANELS.keys():
		var fn: String = String(PANELS[name])
		t.check(main_src.contains("func %s(" % fn),
			"main.gd is missing %s() for %s" % [fn, name])
		# The Escape cascade must call it, or Escape silently skips the panel.
		var esc_at: int = main_src.find("func _dismiss_blocking_overlays")
		t.check(esc_at >= 0, "main.gd must have the Escape cascade")
		if esc_at >= 0:
			var cascade: String = main_src.substr(esc_at, 3000)
			t.check(cascade.contains("%s()" % fn),
				"Escape does not dismiss %s — add it to _dismiss_blocking_overlays"
					% name)

	# --- 3. Panels are laid out, or they render at a default position ---
	for name in PANELS.keys():
		var field: String = "_" + name.replace(".gd", "")
		t.check(main_src.contains(field),
			"main.gd has no field for %s" % name)

	# --- 4. Managed panels go through UiPanelManager ---
	var mgr_src: String = FileAccess.get_file_as_string("res://scripts/ui_panel_manager.gd")
	t.check(not mgr_src.is_empty(), "ui_panel_manager.gd readable")
	t.check(mgr_src.contains("func close_side_panels"),
		"UiPanelManager must expose close_side_panels()")

	# --- 5. Pad reachability: every panel in the rail is in the pad menu ---
	# A panel a controller cannot open is a Full Controller Support failure
	# (Valve #24083947) as much as a missing quit.
	var labels: PackedStringArray = ControllerMenu.destination_labels(false)
	for want in ["Mind", "Residents", "Camera views", "Settings"]:
		t.check(labels.has(want),
			"pad menu is missing '%s' — a rail panel must be pad-reachable" % want)

	# --- 6. Opening a panel closes the side panels (no stacking) ---
	for name in PANELS.keys():
		var toggle: String = "_toggle_" + name.replace("_panel.gd", "") + "_panel"
		if not main_src.contains("func %s(" % toggle):
			continue
		var at: int = main_src.find("func %s(" % toggle)
		var body: String = main_src.substr(at, 1400)
		# Three legitimate ways to avoid stacking: clear the side panels
		# directly, go through _prepare_panel_open, or delegate to
		# UiPanelManager (whose open_side() closes every other side panel).
		# The first version of this check only knew the first two and
		# false-flagged the notifications panel, which uses the third.
		var clears: bool = body.contains("close_side_panels") \
			or body.contains("_prepare_panel_open") \
			or body.contains("_ui_toggle_side") \
			or body.contains("_ui_toggle_modal")
		t.check(clears,
			"%s does not clear other panels on open — panels will stack" % toggle)

	quit(t.finish())


func _all_panels() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with("_panel.gd") and not f.begins_with("smoke_") \
				and f != "ui_panel_manager.gd" and f != "panel_theme.gd":
			out.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
