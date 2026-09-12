# Mind panel (BROAD_DIRECTIONS #17).
#
# Surfaces what a creature is actually thinking. Until now, 48 `mind_*.gd`
# modules ran a global workspace, active inference, felt-self layers and
# episodic memory, and NO panel referenced any of it — the project's largest
# investment was invisible.
#
# This is a thin view. All phrasing lives in `mind_legible.gd` (pure, unit
# tested), so this file only decides layout and refresh cadence. Two
# deliberate choices:
#
#   - **Follows the followed creature.** It reads main's `_follow_target`
#     rather than owning a selection, so "watch this fish" and "read this
#     fish's mind" are the same gesture instead of two.
#   - **"Inner workings" is collapsed by default.** The headline and detail
#     are for everyone; the workspace/prediction-error view is for players
#     who want the machinery, and it should not be the first thing seen.
#
# Refresh is 2 Hz via UiTicker — mind state moves on ~1 s timescales and a
# per-frame rebuild of this many labels is pure waste.

extends PanelContainer
class_name MindPanel

const REFRESH_INTERVAL_S: float = 0.5

# Reference to main.gd, set on instantiation. Duck-typed, like the other
# panels, so this does not drag a class dependency on main.
var main_ref: Node = null

var _name_label: Label = null
var _headline_label: Label = null
var _detail_box: VBoxContainer = null
var _drive_box: VBoxContainer = null
var _workings_btn: Button = null
var _workings_box: VBoxContainer = null
var _empty_label: Label = null
var _body: VBoxContainer = null

var _show_workings: bool = false
var _accum: float = 0.0
var _last_subject: Object = null


func _ready() -> void:
	PanelTheme.apply_panel_chrome(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 0)
	_build_ui()
	visible = false


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	outer.add_child(PanelTheme.make_title("Mind"))
	outer.add_child(PanelTheme.make_rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	# Shown when nothing is being followed — an empty panel with no
	# explanation reads as broken.
	_empty_label = PanelTheme.make_description()
	_empty_label.text = ("Follow a creature to read its mind — tap one in the "
		+ "tank, or use Residents.")
	_body.add_child(_empty_label)

	_name_label = PanelTheme.make_subtitle("")
	_body.add_child(_name_label)

	_headline_label = PanelTheme.make_description()
	_headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_headline_label)

	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 4)
	_body.add_child(_detail_box)

	_body.add_child(PanelTheme.make_section("Drives"))
	_drive_box = VBoxContainer.new()
	_drive_box.add_theme_constant_override("separation", 4)
	_body.add_child(_drive_box)

	_workings_btn = PanelTheme.make_secondary_button("Show inner workings")
	_workings_btn.tooltip_text = ("What the mind is doing underneath — competing "
		+ "impulses, expectations, sense of self")
	_workings_btn.pressed.connect(_toggle_workings)
	_body.add_child(_workings_btn)

	_workings_box = VBoxContainer.new()
	_workings_box.add_theme_constant_override("separation", 4)
	_workings_box.visible = false
	_body.add_child(_workings_box)

	# Footer with a Close button — the house pattern every other panel uses.
	# Without it this panel could be opened and not dismissed.
	outer.add_child(PanelTheme.make_panel_footer(_request_close))


func _toggle_workings() -> void:
	_show_workings = not _show_workings
	_workings_box.visible = _show_workings
	_workings_btn.text = tr("Hide inner workings") if _show_workings \
			else "Show inner workings"
	refresh()


# --- Refresh ---------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_bind_ticker(visible and is_inside_tree())


func _bind_ticker(on: bool) -> void:
	var ticker: Node = get_node_or_null("/root/UiTicker")
	if ticker == null or not ticker.has_signal("tick"):
		return
	if on and not ticker.is_connected("tick", _on_tick):
		ticker.connect("tick", _on_tick)
	elif not on and ticker.is_connected("tick", _on_tick):
		ticker.disconnect("tick", _on_tick)


func _on_tick(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_INTERVAL_S:
		return
	_accum = 0.0
	refresh()


# Called by main when the panel opens, and on the 2 Hz tick.
func refresh() -> void:
	var subject: Object = _subject()
	var have: bool = subject != null
	_empty_label.visible = not have
	_name_label.visible = have
	_headline_label.visible = have
	_detail_box.visible = have
	_drive_box.visible = have
	_workings_btn.visible = have
	_workings_box.visible = have and _show_workings
	if not have:
		return

	_name_label.text = _subject_name(subject)
	_headline_label.text = MindLegible.headline(subject)
	_fill_lines(_detail_box, MindLegible.detail_lines(subject))
	_fill_drives(_drive_box, MindLegible.drives(subject))
	if _show_workings:
		_fill_workings(_workings_box, MindLegible.workings(subject))
	_last_subject = subject


# The creature whose mind to show: whatever main is following.
func _subject() -> Object:
	if main_ref == null or not is_instance_valid(main_ref):
		return null
	var target: Variant = main_ref.get("_follow_target")
	if target == null or not (target is Object):
		return null
	if target is Node and not is_instance_valid(target):
		return null
	return target


func _subject_name(subject: Object) -> String:
	var nm: Variant = subject.get("display_name")
	if nm != null and not String(nm).is_empty():
		return String(nm)
	nm = subject.get("creature_name")
	if nm != null and not String(nm).is_empty():
		return String(nm)
	var species: Variant = subject.get("species")
	if species != null and not String(species).is_empty():
		return String(species).capitalize()
	return "This creature"


# --- Row builders ----------------------------------------------------------

# Rebuild only when the content actually changed, so the panel is not
# churning ~12 labels twice a second for no visible difference.
func _fill_lines(box: VBoxContainer, lines: Array[String]) -> void:
	var want: String = "\n".join(lines)
	if box.get_meta("last", "") == want:
		return
	box.set_meta("last", want)
	for c in box.get_children():
		c.queue_free()
	for line in lines:
		var lbl := PanelTheme.make_description()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = line
		box.add_child(lbl)


func _fill_drives(box: VBoxContainer, rows: Array[Dictionary]) -> void:
	var sig := PackedStringArray()
	for r in rows:
		# Quantise to 5% so a drifting float does not rebuild every tick.
		sig.append("%s:%d" % [String(r["label"]), int(float(r["value"]) * 20.0)])
	var want: String = ",".join(sig)
	if box.get_meta("last", "") == want:
		return
	box.set_meta("last", want)
	for c in box.get_children():
		c.queue_free()
	if rows.is_empty():
		var none := PanelTheme.make_description()
		none.text = tr("Nothing pressing.")
		box.add_child(none)
		return
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := PanelTheme.make_description()
		lbl.text = String(r["label"])
		lbl.custom_minimum_size = Vector2(84, 0)
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(float(r["value"]), 0.0, 1.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		box.add_child(row)


func _fill_workings(box: VBoxContainer, rows: Array[Dictionary]) -> void:
	var sig := PackedStringArray()
	for r in rows:
		sig.append("%s=%s" % [String(r["label"]), String(r["value"])])
	var want: String = "|".join(sig)
	if box.get_meta("last", "") == want:
		return
	box.set_meta("last", want)
	for c in box.get_children():
		c.queue_free()
	if rows.is_empty():
		var none := PanelTheme.make_description()
		none.text = tr("Nothing to report right now.")
		box.add_child(none)
		return
	for r in rows:
		var lbl := PanelTheme.make_description()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = "%s: %s" % [String(r["label"]), String(r["value"])]
		box.add_child(lbl)


# Ask main to close us, so the rail toggle and Escape cascade stay in step.
# Hiding ourselves directly would desync the toggle button's pressed state.
func _request_close() -> void:
	if main_ref != null and is_instance_valid(main_ref) \
			and main_ref.has_method("close_mind_panel"):
		main_ref.call("close_mind_panel")
	else:
		visible = false
