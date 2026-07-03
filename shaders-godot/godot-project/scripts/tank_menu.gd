# Tank-selection menu.
#
# The new main_scene. Shows a grid of saved tanks; tapping a card opens
# that tank (loads its config, transitions to main.tscn). Players can also
# create new tanks, duplicate existing ones, or delete them here.

extends Control

const MAIN_SCENE := "res://main.tscn"
const GuardianMindOnboarding = preload("res://scripts/guardian_mind_onboarding.gd")

var _scene_fade: ColorRect = null
var _guardian_consent_layer: Control = null

@onready var _top_shell: VBoxContainer = $TopBarShell
@onready var _title_label: Label = $TopBarShell/TitleRow/Title
@onready var _action_row: HBoxContainer = $TopBarShell/ActionRow
@onready var _scroll: ScrollContainer = $Scroll
@onready var _grid: GridContainer = $Scroll/Grid
@onready var _empty_hero: CenterContainer = $EmptyHero

var _new_btn: Button = null
var _guided_btn: Button = null
var _design_btn: Button = null
var _info_btn: Button = null
var _select_all: CheckBox = null
var _delete_selected_btn: Button = null
var _create_cluster: HBoxContainer = null
var _manage_cluster: HBoxContainer = null
var _overflow_btn: Button = null
var _empty_card: PanelContainer = null

var _selected_slots: Dictionary = {}
var _slot_checkboxes: Dictionary = {}
var _listed_slots: Array[int] = []
var _syncing_select_all: bool = false


func _ready() -> void:
	_setup_chrome()
	_setup_top_bar()
	VoxelMat.warm_shader_variants(get_node_or_null("/root/TankConfig"))
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_refresh()
	call_deferred("_maybe_first_launch_flow")
	call_deferred("_fade_in_menu")
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm != null and glm.has_signal("consent_required"):
		glm.consent_required.connect(_on_guardian_consent_required)


func _setup_chrome() -> void:
	var bg: ColorRect = $Background
	if bg != null:
		bg.color = PanelTheme.SHELF_BG
	PanelTheme.as_serif(_title_label, PanelTheme.SIZE_TITLE, true)
	_title_label.add_theme_color_override("font_color", PanelTheme.TITLE_FG)


func _setup_top_bar() -> void:
	_new_btn = PanelTheme.make_primary_button("+ New tank")
	_new_btn.pressed.connect(_on_new_pressed)

	_guided_btn = PanelTheme.make_secondary_button("+ Guided setup")
	_guided_btn.tooltip_text = "Create an empty tank and walk through stocking step by step"
	_guided_btn.pressed.connect(_on_guided_pressed)

	_design_btn = PanelTheme.make_secondary_button("Design a scape")
	_design_btn.tooltip_text = "New empty tank and open build mode — sculpt before you stock fish"
	_design_btn.pressed.connect(_on_design_scape_pressed)

	_info_btn = PanelTheme.make_ghost_button("Info")
	_info_btn.tooltip_text = "Project website and GitHub issues"
	_info_btn.pressed.connect(func(): AppLinks.show_info_popup(self))

	_create_cluster = PanelTheme.make_action_cluster(
		[_new_btn, _guided_btn, _design_btn], 8)

	_select_all = CheckBox.new()
	_select_all.text = "Select all"
	_select_all.toggled.connect(_on_select_all_toggled)

	_delete_selected_btn = PanelTheme.make_secondary_button("Delete selected")
	_delete_selected_btn.disabled = true
	_delete_selected_btn.pressed.connect(_on_delete_selected_confirm)

	_overflow_btn = PanelTheme.make_secondary_button(UiIcons.menu_label("more"))
	_overflow_btn.tooltip_text = UiIcons.menu_tooltip("more")
	_overflow_btn.visible = false
	_overflow_btn.pressed.connect(_toggle_overflow_menu)

	_manage_cluster = PanelTheme.make_action_cluster(
		[_select_all, _delete_selected_btn, _overflow_btn], 8)

	for child in _action_row.get_children():
		child.queue_free()
	# Create actions anchor left (under the title), management + info push to the
	# right edge, with an elastic spacer between so the bar spans the full width
	# instead of bunching every button against the right margin.
	_action_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_action_row.add_child(_create_cluster)
	var bar_spacer := Control.new()
	bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_row.add_child(bar_spacer)
	_action_row.add_child(_manage_cluster)
	_action_row.add_child(_info_btn)


func _toggle_overflow_menu() -> void:
	var popup := PopupMenu.new()
	popup.add_item("Select all", 0)
	popup.add_item(_delete_selected_btn.text, 1)
	popup.set_item_disabled(1, _delete_selected_btn.disabled)
	popup.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_select_all.button_pressed = not _select_all.button_pressed
		elif id == 1:
			_on_delete_selected_confirm())
	add_child(popup)
	popup.position = _overflow_btn.global_position + Vector2(0, _overflow_btn.size.y)
	popup.popup()


func _apply_responsive_layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var narrow: bool = vp.x < PanelTheme.MOBILE_NARROW_W

	if _top_shell != null:
		var top_h: float = PanelTheme.SHELF_TOP_BAR_H
		if narrow:
			top_h = 96.0
		_top_shell.offset_bottom = _top_shell.offset_top + top_h
		_scroll.offset_top = _top_shell.offset_top + top_h + PanelTheme.EDGE_MARGIN

	if _create_cluster != null:
		_create_cluster.visible = true
	if _manage_cluster != null:
		_manage_cluster.visible = not _listed_slots.is_empty()
	if _select_all != null and _delete_selected_btn != null and _overflow_btn != null:
		_select_all.visible = not narrow
		_delete_selected_btn.visible = not narrow
		_overflow_btn.visible = narrow and not _listed_slots.is_empty()
	if _info_btn != null:
		_info_btn.visible = not narrow or vp.x >= 360.0

	var m: Dictionary = _grid_metrics()
	_grid.columns = int(m["cols"])
	for card in _grid.get_children():
		if card is PanelContainer:
			card.custom_minimum_size.x = float(m["card_w"])


# Column count + card width chosen so the row fills the viewport instead of
# capping at three 320px cards and leaving the right half empty. Columns scale
# with width toward a ~360px target; cards then divide the available row width
# exactly so the grid spans edge to edge.
const _GRID_H_SEP: float = 16.0
const _CARD_TARGET_W: float = 360.0


func _grid_metrics() -> Dictionary:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vp.y > vp.x * 1.02
	# Inner width: viewport minus the scroll's edge insets and the vertical
	# scrollbar gutter, so cards don't run under the scrollbar.
	var avail: float = vp.x - PanelTheme.EDGE_MARGIN * 2.0 - 16.0
	var cols: int
	if portrait or vp.x < 520.0:
		cols = 1
	else:
		cols = clampi(int(round(avail / _CARD_TARGET_W)), 2, 6)
	var card_w: float = maxf((avail - _GRID_H_SEP * float(cols - 1)) / float(cols),
		PanelTheme.SHELF_CARD_MIN_W)
	return {"cols": cols, "card_w": card_w}


func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_slot_checkboxes.clear()
	_listed_slots.clear()
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	var tanks: Array = saves.list_tanks()
	var has_tanks: bool = not tanks.is_empty()
	_empty_hero.visible = not has_tanks
	_scroll.visible = has_tanks
	if not has_tanks:
		_build_empty_hero()
	for entry in tanks:
		var slot: int = int(entry["slot"])
		_listed_slots.append(slot)
		_grid.add_child(_make_card(entry))
	_prune_stale_selection()
	_sync_select_all_checkbox()
	_update_bulk_delete_ui()
	_apply_responsive_layout()


func _build_empty_hero() -> void:
	if _empty_card != null and is_instance_valid(_empty_card):
		_empty_card.queue_free()
	_empty_card = PanelContainer.new()
	PanelTheme.apply_shelf_card_chrome(_empty_card)
	_empty_card.custom_minimum_size = Vector2(320, 0)
	_empty_hero.add_child(_empty_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_empty_card.add_child(vb)

	vb.add_child(PanelTheme.make_title("Start your first living world"))
	var body := PanelTheme.make_subtitle(
		"Pick a scenario, stock gently, and watch the closed loop settle.")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)

	var cta := PanelTheme.make_primary_button("Create your first tank →")
	cta.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cta.pressed.connect(_on_new_pressed)
	vb.add_child(cta)


func _make_card(entry: Dictionary) -> Control:
	var slot: int = int(entry["slot"])
	var card := PanelContainer.new()
	var card_w: float = float(_grid_metrics()["card_w"])
	card.custom_minimum_size = Vector2(card_w, 0)
	PanelTheme.apply_shelf_card_chrome(card)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)

	var thumb_h: float = card_w * 0.625
	var thumb_wrap := PanelContainer.new()
	thumb_wrap.custom_minimum_size = Vector2(0, thumb_h)
	var thumb_style := StyleBoxFlat.new()
	thumb_style.bg_color = Color(0.10, 0.12, 0.18, 1.0)
	thumb_style.corner_radius_top_left = 6
	thumb_style.corner_radius_top_right = 6
	thumb_style.corner_radius_bottom_left = 6
	thumb_style.corner_radius_bottom_right = 6
	thumb_wrap.add_theme_stylebox_override("panel", thumb_style)
	vb.add_child(thumb_wrap)

	var thumb := TextureRect.new()
	thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb.offset_left = 2.0
	thumb.offset_top = 2.0
	thumb.offset_right = -2.0
	thumb.offset_bottom = -2.0
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb_path: String = String(entry.get("thumbnail_path", ""))
	if thumb_path != "" and FileAccess.file_exists(thumb_path):
		var img := Image.load_from_file(thumb_path)
		if img != null:
			thumb.texture = ImageTexture.create_from_image(img)
	if thumb.texture == null:
		var ph := ColorRect.new()
		ph.color = Color(0.10, 0.12, 0.18, 1.0)
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var prev_shader: Shader = load("res://shaders/tank_preview.gdshader")
		if prev_shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = prev_shader
			mat.set_shader_parameter("seed", float(slot) * 0.37)
			ph.material = mat
		thumb_wrap.add_child(ph)
	else:
		thumb_wrap.add_child(thumb)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	vb.add_child(title_row)

	# Leading select checkbox — folded into the title row so the card opens
	# straight into the thumbnail instead of a floating "Select" band up top.
	var select_cb := CheckBox.new()
	select_cb.tooltip_text = "Select for bulk delete"
	select_cb.button_pressed = _selected_slots.has(slot)
	select_cb.toggled.connect(func(on: bool): _set_slot_selected(slot, on))
	title_row.add_child(select_cb)
	_slot_checkboxes[slot] = select_cb

	var name_lbl := Label.new()
	var tank_name: String = String(entry.get("name", "Tank %d" % slot))
	name_lbl.text = tank_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelTheme.as_serif(name_lbl, PanelTheme.SIZE_ITEM, true)
	name_lbl.add_theme_color_override("font_color", PanelTheme.TITLE_FG)
	title_row.add_child(name_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = tank_name
	name_edit.visible = false
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(new_name: String):
		_commit_tank_rename(slot, new_name, name_edit, name_lbl))
	name_edit.focus_exited.connect(func():
		_commit_tank_rename(slot, name_edit.text, name_edit, name_lbl))
	title_row.add_child(name_edit)

	var edit_btn := PanelTheme.make_icon_button(UiIcons.menu_label("edit"))
	edit_btn.tooltip_text = UiIcons.menu_tooltip("edit")
	edit_btn.pressed.connect(func():
		name_lbl.visible = false
		name_edit.visible = true
		name_edit.grab_focus()
		name_edit.select_all())
	title_row.add_child(edit_btn)

	var dup_btn := PanelTheme.make_icon_button(UiIcons.menu_label("duplicate"))
	dup_btn.tooltip_text = UiIcons.menu_tooltip("duplicate")
	dup_btn.pressed.connect(func(): _on_duplicate(slot))
	title_row.add_child(dup_btn)

	var del_btn := PanelTheme.make_icon_button(UiIcons.menu_label("delete"))
	del_btn.tooltip_text = UiIcons.menu_tooltip("delete")
	del_btn.pressed.connect(func():
		_on_delete_confirm([slot], [tank_name]))
	title_row.add_child(del_btn)

	# Meta block: tighter rhythm than the rest of the card so the cycle/day
	# glance and the run-history line read as one paragraph, not two bands.
	var meta_box := VBoxContainer.new()
	meta_box.add_theme_constant_override("separation", 2)
	vb.add_child(meta_box)

	# Only show the glance line when there's something to say — the old
	# "Tap to open" fallback just echoed the Open tank button below it.
	var glance: String = _format_status_glance(entry)
	if glance != "":
		var status := Label.new()
		status.text = glance
		PanelTheme.as_mono(status, PanelTheme.SIZE_CAPTION)
		status.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
		meta_box.add_child(status)

	var sub := Label.new()
	sub.text = _format_subtitle(entry)
	sub.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	sub.add_theme_font_size_override("font_size", PanelTheme.SIZE_CAPTION)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_box.add_child(sub)

	var open_btn := PanelTheme.make_primary_button("Open tank")
	open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_btn.pressed.connect(func(): _on_open(slot))
	vb.add_child(open_btn)

	return card


func _format_status_glance(entry: Dictionary) -> String:
	var cycle_l: String = String(entry.get("cycle_label", ""))
	var day_l: String = String(entry.get("sim_day_label", ""))
	var parts: Array[String] = []
	if cycle_l != "":
		parts.append(cycle_l)
	if day_l != "":
		parts.append(day_l)
	var amb: String = String(entry.get("ambient_hint", ""))
	if amb != "":
		parts.append(amb)
	if parts.is_empty():
		return ""
	return " · ".join(parts)


func _commit_tank_rename(slot: int, new_name: String, field: LineEdit, label: Label) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	var meta: Dictionary = saves.get_tank_meta(slot)
	var old_name: String = String(meta.get("name", ""))
	var trimmed: String = new_name.strip_edges()
	if trimmed == "":
		trimmed = "Tank %d" % slot
	field.visible = false
	label.visible = true
	if trimmed == old_name:
		field.text = old_name if old_name != "" else trimmed
		label.text = field.text
		return
	var saved: String = saves.rename_tank(slot, trimmed)
	field.text = saved
	label.text = saved


func _set_slot_selected(slot: int, selected: bool) -> void:
	if selected:
		_selected_slots[slot] = true
	else:
		_selected_slots.erase(slot)
	_sync_select_all_checkbox()
	_update_bulk_delete_ui()


func _on_select_all_toggled(on: bool) -> void:
	if _syncing_select_all:
		return
	_selected_slots.clear()
	if on:
		for slot in _listed_slots:
			_selected_slots[slot] = true
	for slot in _slot_checkboxes.keys():
		var cb: CheckBox = _slot_checkboxes[slot]
		if cb != null and is_instance_valid(cb):
			cb.button_pressed = on
	_update_bulk_delete_ui()


func _sync_select_all_checkbox() -> void:
	_syncing_select_all = true
	if _listed_slots.is_empty():
		_select_all.button_pressed = false
	else:
		var all_selected: bool = true
		for slot in _listed_slots:
			if not _selected_slots.has(slot):
				all_selected = false
				break
		_select_all.button_pressed = all_selected
	_syncing_select_all = false


func _update_bulk_delete_ui() -> void:
	var n: int = _selected_slots.size()
	_delete_selected_btn.disabled = n <= 0
	_delete_selected_btn.text = "Delete selected" if n <= 1 else "Delete selected (%d)" % n


func _prune_stale_selection() -> void:
	for slot in _selected_slots.keys():
		if slot not in _listed_slots:
			_selected_slots.erase(slot)


func _format_subtitle(entry: Dictionary) -> String:
	var runtime_s: int = int(entry.get("runtime_s", 0))
	var last_opened: int = int(entry.get("last_opened_unix", 0))
	var run_str: String = _fmt_duration(runtime_s)
	var when_str: String = "never"
	if last_opened > 0:
		var ago: int = int(Time.get_unix_time_from_system()) - last_opened
		when_str = _fmt_duration(ago) + " ago"
	return "Ran for %s · last opened %s" % [run_str, when_str]


func _fmt_duration(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % seconds
	if seconds < 3600:
		return "%dm" % int(seconds / 60.0)
	if seconds < 86400:
		var h: int = int(seconds / 3600.0)
		var m: int = int((seconds % 3600) / 60.0)
		return "%dh %dm" % [h, m] if m > 0 else "%dh" % h
	return "%dd" % int(seconds / 86400.0)


func _on_design_scape_pressed() -> void:
	var saves := get_node_or_null("/root/TankSaves")
	var cfg := get_node_or_null("/root/TankConfig")
	if saves == null or cfg == null:
		return
	var slot: int = saves.new_tank("Design scape")
	cfg.switch_to_slot(slot)
	cfg.tank_preset = "empty"
	cfg.aquascape_pending = true
	cfg.save_to_disk()
	_transition_to_main()


func _on_guided_pressed() -> void:
	var saves := get_node_or_null("/root/TankSaves")
	var cfg := get_node_or_null("/root/TankConfig")
	if saves == null or cfg == null:
		return
	var slot: int = saves.new_tank("Guided tank")
	cfg.switch_to_slot(slot)
	cfg.tank_preset = "empty"
	cfg.walkthrough_pending = true
	cfg.save_to_disk()
	_transition_to_main()


func _on_new_pressed() -> void:
	if _is_mobile():
		_show_orientation_picker()
		return
	_open_scenario_picker()


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _open_scenario_picker() -> void:
	var picker: ScenarioPicker = ScenarioPicker.new()
	picker.name = "ScenarioPicker"
	add_child(picker)
	picker.scenario_chosen.connect(_on_scenario_chosen)
	picker.canceled.connect(func(): pass)


func _show_orientation_picker() -> void:
	var root := PanelTheme.make_modal_root(self, PanelTheme.Z_MENU_MODAL)
	var overlay: Control = root["overlay"]
	var center: CenterContainer = root["center"]

	var panel := PanelContainer.new()
	PanelTheme.apply_panel_chrome(panel)
	PanelTheme.layout_modal_panel(panel, get_viewport().get_visible_rect().size, 340.0, 320.0, 0.94, 0.75)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	vb.add_child(PanelTheme.make_title("Tank orientation"))
	vb.add_child(PanelTheme.make_subtitle(
		"Pick the shape that fits how you hold the phone. Change later in Settings → Tank."))

	var make_choice := func(label: String, fit: String, desc: String) -> Button:
		var b := PanelTheme.make_secondary_button("%s — %s" % [label, desc])
		b.pressed.connect(func():
			var cfg := get_node_or_null("/root/TankConfig")
			if cfg != null:
				cfg.new_tank_fit = fit
				cfg.save_to_disk()
			overlay.queue_free()
			_open_scenario_picker())
		return b

	vb.add_child(make_choice.call("Auto", "auto",
		"match screen — portrait gives cylinder, landscape gives box"))
	vb.add_child(make_choice.call("Portrait", "round", "tall cylindrical tank"))
	vb.add_child(make_choice.call("Landscape", "rect", "wide rectangular tank"))

	var footer := PanelTheme.make_panel_footer(func(): overlay.queue_free())
	vb.add_child(footer)


func _on_scenario_chosen(scenario: Dictionary) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	var cfg := get_node_or_null("/root/TankConfig")
	if saves == null or cfg == null:
		return
	if not _walkthrough_offer_seen():
		_pending_scenario = scenario
		_show_walkthrough_offer()
		return
	_finish_new_tank(scenario)


var _pending_scenario: Dictionary = {}


func _walkthrough_offer_seen() -> bool:
	var path := "user://global_prefs.cfg"
	var file := ConfigFile.new()
	if file.load(path) == OK:
		return bool(file.get_value("app", "walkthrough_offer_seen", false))
	return false


func _set_walkthrough_offer_seen() -> void:
	var file := ConfigFile.new()
	file.load("user://global_prefs.cfg")
	file.set_value("app", "walkthrough_offer_seen", true)
	file.save("user://global_prefs.cfg")


func _show_walkthrough_offer() -> void:
	var root := PanelTheme.make_modal_root(self, PanelTheme.Z_MENU_MODAL)
	var overlay: Control = root["overlay"]
	var center: CenterContainer = root["center"]

	var panel := PanelContainer.new()
	PanelTheme.apply_panel_chrome(panel)
	PanelTheme.layout_modal_panel(panel, get_viewport().get_visible_rect().size, 400.0, 220.0, 0.88, 0.5)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	vb.add_child(PanelTheme.make_title("Take a guided tour?"))
	var body := PanelTheme.make_subtitle(
		"Walk through aquascaping and stocking step by step, or jump straight into your new tank.")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)

	var skip := PanelTheme.make_secondary_button("Skip")
	skip.pressed.connect(func():
		_set_walkthrough_offer_seen()
		overlay.queue_free()
		_finish_new_tank(_pending_scenario))

	var yes := PanelTheme.make_primary_button("Guided tour")
	yes.pressed.connect(func():
		_set_walkthrough_offer_seen()
		overlay.queue_free()
		_finish_new_tank(_pending_scenario, true))

	vb.add_child(PanelTheme.make_rule())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.add_child(skip)
	row.add_child(yes)
	vb.add_child(row)


func _finish_new_tank(scenario: Dictionary, guided: bool = false) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	var cfg := get_node_or_null("/root/TankConfig")
	if saves == null or cfg == null:
		return
	var tank_name: String = String(scenario.get("name", "New tank"))
	var slot: int = saves.new_tank(tank_name)
	cfg.switch_to_slot(slot)
	ScenarioPicker.apply_scenario(scenario, cfg)
	if guided:
		cfg.tank_preset = "empty"
		cfg.walkthrough_pending = true
		cfg.walkthrough_scenario_preset = String(scenario.get("config", {}).get("tank_preset", "classic_community"))
	cfg.save_to_disk()
	_show_toast("Saved '%s'" % tank_name)
	_transition_to_main()


func _fade_in_menu() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color.BLACK
	overlay.modulate.a = 1.0
	overlay.z_index = PanelTheme.Z_TUTORIAL + 5
	add_child(overlay)
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(overlay.queue_free)


func _transition_to_main() -> void:
	if _scene_fade != null:
		return
	_scene_fade = ColorRect.new()
	_scene_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scene_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_scene_fade.color = Color.BLACK
	_scene_fade.modulate.a = 0.0
	_scene_fade.z_index = PanelTheme.Z_TUTORIAL + 10
	add_child(_scene_fade)
	var tw := create_tween()
	tw.tween_property(_scene_fade, "modulate:a", 1.0, 0.38) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file(MAIN_SCENE))


func _maybe_first_launch_flow() -> void:
	var file := ConfigFile.new()
	file.load("user://global_prefs.cfg")
	if bool(file.get_value("app", "first_launch_done", false)):
		return
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null or not saves.list_tanks().is_empty():
		return
	_open_scenario_picker()
	file.set_value("app", "first_launch_done", true)
	file.save("user://global_prefs.cfg")


func _show_toast(msg: String) -> void:
	var lab := Label.new()
	lab.text = msg
	lab.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lab.offset_top = -48.0
	lab.offset_bottom = -16.0
	PanelTheme.as_sans(lab, PanelTheme.SIZE_BODY)
	lab.add_theme_color_override("font_color", PanelTheme.LABEL_FG)
	add_child(lab)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(lab, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lab.queue_free)


func _on_open(slot: int) -> void:
	_open_slot(slot)


func _open_slot(slot: int) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.switch_to_slot(slot)
	_transition_to_main()


func _on_duplicate(slot: int) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	saves.duplicate_tank(slot)
	_show_toast("Duplicated tank")
	_refresh()


func _on_delete_selected_confirm() -> void:
	if _selected_slots.is_empty():
		return
	var slots: Array[int] = []
	var names: Array[String] = []
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	for entry in saves.list_tanks():
		var slot: int = int(entry["slot"])
		if not _selected_slots.has(slot):
			continue
		slots.append(slot)
		names.append(String(entry.get("name", "Tank %d" % slot)))
	if slots.is_empty():
		return
	_on_delete_confirm(slots, names)


func _on_delete_confirm(slots: Array, names: Array) -> void:
	var dialog := ConfirmationDialog.new()
	if slots.size() == 1:
		dialog.dialog_text = "Delete \"%s\"?\nThis cannot be undone." % names[0]
	else:
		var preview: String = ", ".join(names.slice(0, 3))
		if names.size() > 3:
			preview += ", …"
		dialog.dialog_text = "Delete %d tanks?\n\n%s\n\nThis cannot be undone." % [slots.size(), preview]
	dialog.ok_button_text = "Delete"
	add_child(dialog)
	dialog.confirmed.connect(func():
		var saves := get_node_or_null("/root/TankSaves")
		if saves != null:
			for slot in slots:
				saves.delete_tank(int(slot))
			_selected_slots.clear()
			_refresh()
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()


func _on_guardian_consent_required(needs_download: bool) -> void:
	if _guardian_consent_layer != null and is_instance_valid(_guardian_consent_layer):
		return
	var glm := get_node_or_null("/root/GuardianLlm")
	if glm == null:
		return
	var root := PanelTheme.make_modal_root(self, PanelTheme.Z_GUARDIAN)
	var backdrop: Control = root["overlay"]
	_guardian_consent_layer = backdrop
	var mode: int = GuardianMindOnboarding.Mode.DOWNLOAD if needs_download \
			else GuardianMindOnboarding.Mode.BUNDLED_INFO
	var modal: PanelContainer = GuardianMindOnboarding.open_in(self, mode)
	modal.closed.connect(func(accepted: bool) -> void:
		if is_instance_valid(backdrop):
			backdrop.queue_free()
		_guardian_consent_layer = null
		if needs_download:
			glm.on_consent_result(accepted)
		else:
			glm.on_bundled_info_dismissed())
