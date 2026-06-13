# Tank-selection menu.
#
# The new main_scene. Shows a grid of saved tanks; tapping a card opens
# that tank (loads its config, transitions to main.tscn). Players can also
# create new tanks, duplicate existing ones, or delete them here.
#
# This scene is intentionally simple — no 3D rendering, no sim. Just a
# scrollable card grid built procedurally so we don't have to maintain a
# scene file with per-card nodes.

extends Control

const MAIN_SCENE := "res://main.tscn"

@onready var _grid: GridContainer = $Scroll/Grid
@onready var _empty_label: Label = $EmptyLabel
@onready var _new_btn: Button = $TopBar/NewButton
@onready var _select_all: CheckBox = $TopBar/SelectAllCheck
@onready var _delete_selected_btn: Button = $TopBar/DeleteSelectedBtn

var _selected_slots: Dictionary = {}
var _slot_checkboxes: Dictionary = {}
var _listed_slots: Array[int] = []
var _syncing_select_all: bool = false


func _ready() -> void:
	_new_btn.pressed.connect(_on_new_pressed)
	_select_all.toggled.connect(_on_select_all_toggled)
	_delete_selected_btn.pressed.connect(_on_delete_selected_confirm)
	_add_guided_button()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_refresh()


# Add a "Guided setup" button next to "+ New tank" that creates an empty tank
# and launches the step-by-step walkthrough.
func _add_guided_button() -> void:
	var top_bar: Node = _new_btn.get_parent()
	if top_bar == null:
		return
	var b := Button.new()
	b.text = "+ Guided setup"
	b.tooltip_text = "Create an empty tank and walk through stocking it step by step"
	b.custom_minimum_size = Vector2(0, maxf(36.0, _new_btn.custom_minimum_size.y))
	b.pressed.connect(_on_guided_pressed)
	top_bar.add_child(b)
	top_bar.move_child(b, _new_btn.get_index() + 1)


func _on_guided_pressed() -> void:
	var saves := get_node_or_null("/root/TankSaves")
	var cfg := get_node_or_null("/root/TankConfig")
	if saves == null or cfg == null:
		return
	var slot: int = saves.new_tank("Guided tank")
	cfg.switch_to_slot(slot)
	# Start empty so the player stocks everything during the walkthrough.
	cfg.tank_preset = "empty"
	cfg.walkthrough_pending = true
	cfg.save_to_disk()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _apply_responsive_layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = vp.y > vp.x * 1.02
	if portrait:
		_grid.columns = 1
	else:
		_grid.columns = 1 if vp.x < 520.0 else (2 if vp.x < 900.0 else 3)


func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_slot_checkboxes.clear()
	_listed_slots.clear()
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	var tanks: Array = saves.list_tanks()
	_empty_label.visible = tanks.is_empty()
	_select_all.visible = not tanks.is_empty()
	_delete_selected_btn.visible = not tanks.is_empty()
	for entry in tanks:
		var slot: int = int(entry["slot"])
		_listed_slots.append(slot)
		_grid.add_child(_make_card(entry))
	_prune_stale_selection()
	_sync_select_all_checkbox()
	_update_bulk_delete_ui()


# Build a single tank card with thumbnail, name, runtime, and the small
# delete/duplicate buttons that appear on tap-hold. Touch-friendly sizes.
func _make_card(entry: Dictionary) -> Control:
	var slot: int = int(entry["slot"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 220)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# Selection row sits above the thumbnail so bulk actions are obvious.
	var select_row := HBoxContainer.new()
	select_row.add_theme_constant_override("separation", 6)
	vb.add_child(select_row)
	var select_cb := CheckBox.new()
	select_cb.text = "Select"
	select_cb.button_pressed = _selected_slots.has(slot)
	select_cb.toggled.connect(func(on: bool): _set_slot_selected(slot, on))
	select_row.add_child(select_cb)
	_slot_checkboxes[slot] = select_cb

	# Thumbnail (or placeholder if none yet).
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0, 140)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumb_path: String = String(entry.get("thumbnail_path", ""))
	if thumb_path != "" and FileAccess.file_exists(thumb_path):
		var img := Image.load_from_file(thumb_path)
		if img != null:
			thumb.texture = ImageTexture.create_from_image(img)
	if thumb.texture == null:
		# Placeholder: dim color rect behind a "(no preview)" label.
		var ph := ColorRect.new()
		ph.color = Color(0.10, 0.12, 0.18, 1.0)
		ph.custom_minimum_size = Vector2(0, 140)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.queue_free()
		vb.add_child(ph)
	else:
		vb.add_child(thumb)

	# Title row: editable name + small action buttons.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vb.add_child(title_row)
	var name_edit := LineEdit.new()
	name_edit.text = String(entry.get("name", "Tank %d" % slot))
	name_edit.placeholder_text = "Tank name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 32)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.caret_blink = true
	name_edit.focus_entered.connect(func(): name_edit.select_all())
	name_edit.text_submitted.connect(func(new_name: String):
		_commit_tank_rename(slot, new_name, name_edit))
	name_edit.focus_exited.connect(func():
		_commit_tank_rename(slot, name_edit.text, name_edit))
	title_row.add_child(name_edit)
	var dup_btn := Button.new()
	dup_btn.text = "⧉"
	dup_btn.tooltip_text = "Duplicate"
	dup_btn.custom_minimum_size = Vector2(36, 36)
	dup_btn.pressed.connect(func(): _on_duplicate(slot))
	title_row.add_child(dup_btn)
	var del_btn := Button.new()
	del_btn.text = "🗑"
	del_btn.tooltip_text = "Delete"
	del_btn.custom_minimum_size = Vector2(36, 36)
	del_btn.pressed.connect(func(): _on_delete_confirm([slot], ["%s" % String(entry.get("name", "this tank"))]))
	title_row.add_child(del_btn)

	# Subtitle: accumulated runtime + last opened.
	var sub := Label.new()
	sub.text = _format_subtitle(entry)
	sub.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 1))
	sub.add_theme_font_size_override("font_size", 12)
	vb.add_child(sub)

	# Big "Open tank" button.
	var open_btn := Button.new()
	open_btn.text = "Open tank"
	open_btn.custom_minimum_size = Vector2(0, 44)
	open_btn.add_theme_font_size_override("font_size", 15)
	open_btn.pressed.connect(func(): _on_open(slot))
	vb.add_child(open_btn)

	return card


func _commit_tank_rename(slot: int, new_name: String, field: LineEdit) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	var meta: Dictionary = saves.get_tank_meta(slot)
	var old_name: String = String(meta.get("name", ""))
	var trimmed: String = new_name.strip_edges()
	if trimmed == "":
		trimmed = "Tank %d" % slot
	if trimmed == old_name:
		field.text = old_name if old_name != "" else trimmed
		return
	var saved: String = saves.rename_tank(slot, trimmed)
	field.text = saved


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
	var eco: String = ""
	var day_l: String = String(entry.get("sim_day_label", ""))
	var cycle_l: String = String(entry.get("cycle_label", ""))
	if day_l != "" and cycle_l != "":
		eco = " · %s · %s" % [day_l, cycle_l]
	elif cycle_l != "":
		eco = " · %s" % cycle_l
	var amb: String = String(entry.get("ambient_hint", ""))
	if amb != "":
		eco += " · %s" % amb
	return "Ran for %s · last opened %s%s" % [run_str, when_str, eco]


func _fmt_duration(seconds: int) -> String:
	if seconds < 60: return "%ds" % seconds
	if seconds < 3600: return "%dm" % int(seconds / 60.0)
	if seconds < 86400:
		var h: int = int(seconds / 3600.0)
		var m: int = int((seconds % 3600) / 60.0)
		return "%dh %dm" % [h, m] if m > 0 else "%dh" % h
	return "%dd" % int(seconds / 86400.0)


# ---- Actions ----

func _on_new_pressed() -> void:
	# On mobile, ask the orientation first so the scenario picker (and the
	# tank that ends up rendered) can size itself appropriately. Desktop
	# users skip this step — windowed desktop has flexible aspect ratios
	# and the existing landscape default works for both.
	if _is_mobile():
		_show_orientation_picker()
		return
	_open_scenario_picker()


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _open_scenario_picker() -> void:
	# Open the scenario picker first. The picker emits `scenario_chosen`
	# with the picked config dict; we then mint a fresh slot, apply the
	# scenario overrides to TankConfig, and open the tank.
	var picker: ScenarioPicker = ScenarioPicker.new()
	picker.name = "ScenarioPicker"
	add_child(picker)
	picker.scenario_chosen.connect(_on_scenario_chosen)
	picker.canceled.connect(func(): pass)


# Mobile-only step before the scenario picker. Three options: Auto (let
# screen orientation pick), Portrait (force tall cylinder), Landscape
# (force wide box). Writes TankConfig.new_tank_fit which is what
# apply_screen_fitted_dimensions() reads when minting a new tank.
func _show_orientation_picker() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 400
	add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200
	panel.offset_top = -180
	panel.offset_right = 200
	panel.offset_bottom = 180
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Tank orientation"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	PanelTheme.as_serif(title, PanelTheme.SIZE_SECTION, true)
	vb.add_child(title)
	var body := Label.new()
	body.text = "Pick the shape that fits how you hold the phone. You can change this later in Settings → Tank."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	vb.add_child(body)
	var make_choice := func(label: String, fit: String, desc: String) -> Button:
		var b := Button.new()
		b.text = "%s — %s" % [label, desc]
		b.custom_minimum_size = Vector2(0, 56)
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
	vb.add_child(make_choice.call("Portrait", "round",
		"tall cylindrical tank, top-to-bottom view"))
	vb.add_child(make_choice.call("Landscape", "rect",
		"wide rectangular tank, classic side view"))
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): overlay.queue_free())
	vb.add_child(cancel)


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
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 400
	add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_top = -100
	panel.offset_right = 220
	panel.offset_bottom = 100
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Take a guided tour?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := Label.new()
	body.text = "Walk through aquascaping and stocking step by step, or jump straight into your new tank."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(func():
		_set_walkthrough_offer_seen()
		overlay.queue_free()
		_finish_new_tank(_pending_scenario))
	row.add_child(skip)
	var yes := Button.new()
	yes.text = "Guided tour"
	yes.pressed.connect(func():
		_set_walkthrough_offer_seen()
		overlay.queue_free()
		_finish_new_tank(_pending_scenario, true))
	row.add_child(yes)


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
	cfg.save_to_disk()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_open(slot: int) -> void:
	_open_slot(slot)


func _open_slot(slot: int) -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		return
	cfg.switch_to_slot(slot)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_duplicate(slot: int) -> void:
	var saves := get_node_or_null("/root/TankSaves")
	if saves == null:
		return
	saves.duplicate_tank(slot)
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
