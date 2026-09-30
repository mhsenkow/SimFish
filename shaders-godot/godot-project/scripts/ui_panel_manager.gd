# Central panel open/close policy.
#
# Every HUD panel lives in ONE HudLayout region and registers here:
#
#     _ui_panels.register(id, control, HudLayout.LEFT_COLUMN)
#     _ui_panels.register(id, control, HudLayout.CENTRE_MODAL, Vector2(w, h))
#
# A region holds one panel at a time: when a registered control becomes
# visible — through open(), transition_panel(), or a bare `visible = true` —
# every other open panel in that region is closed, and when the regions say
# both columns cannot fit (COLUMNS_EXCLUSIVE) the opposite column closes too.
# Visibility is WATCHED, not reported, so a panel that hides itself with
# `visible = false` (Adopt's own Close did, skipping notify_modal_closed and
# leaving the scrim up) still releases its slot. relayout(regions) places
# every registered control into its rect with its region's z band; close_top()
# is the Escape order (newest open panel first).
#
# The legacy side/modal ids below keep their bespoke open/close paths; they
# are registered like everything else so exclusivity and Escape cover them.
class_name UiPanelManager
extends RefCounted

const PANEL_MIND := "mind"
const PANEL_CHRONICLE := "chronicle"
const PANEL_RESIDENTS := "residents"
const PANEL_CAMERA_VIEWS := "camera_views"
const MODAL_VESSEL := "vessel_picker"
const _SIDE_IDS: Array[String] = ["settings", "render", "sound", "light", "notifications"]
const _MODAL_IDS: Array[String] = ["library", "creator", "adopt"]

const SIDE_SETTINGS := "settings"
const SIDE_RENDER := "render"
const SIDE_SOUND := "sound"
const SIDE_LIGHT := "light"
const SIDE_NOTIFICATIONS := "notifications"

const MODAL_LIBRARY := "library"
const MODAL_CREATOR := "creator"
const MODAL_ADOPT := "adopt"

var _main: Node = null
var _backdrop: ColorRect = null
var _open_side: String = ""
var _open_modal: String = ""
# id -> {"control": Control, "region": String, "size": Vector2, "close": Callable}
var _entries: Dictionary = {}
var _regions: Dictionary = {}
# Open order, newest last — Escape closes from the end.
var _order: Array[String] = []


# Register (or re-register) a panel into a HudLayout region. Idempotent:
# main calls it from every _apply_panel_layout so lazily built panels join
# as soon as they exist. `modal_size` is the preferred size in CENTRE_MODAL
# (clamped to the region); `close_fn` replaces the default fade-out close.
func register(id: String, control: Control, region: String,
		modal_size: Vector2 = Vector2.ZERO, close_fn: Callable = Callable()) -> void:
	if control == null or not is_instance_valid(control):
		return
	var prev: Variant = (_entries.get(id, {}) as Dictionary).get("control", null)
	_entries[id] = {"control": control, "region": region, "size": modal_size,
		"close": close_fn}
	control.z_index = PanelTheme.z_for_region(region)
	if not (prev is Control) or prev != control:
		control.visibility_changed.connect(_on_entry_visibility.bind(id))
		if control.visible:
			_mark_open(id)
	if not _regions.is_empty():
		_place(id)


func region_of(id: String) -> String:
	return String((_entries.get(id, {}) as Dictionary).get("region", ""))


func control_of(id: String) -> Control:
	var c: Variant = (_entries.get(id, {}) as Dictionary).get("control", null)
	if is_instance_valid(c) and c is Control:
		return c as Control
	return null


func is_open(id: String) -> bool:
	var c: Control = control_of(id)
	return c != null and PanelTheme.is_panel_open(c)


# Newest open panel in a region, or "".
func open_in(region: String) -> String:
	for i in range(_order.size() - 1, -1, -1):
		var id: String = _order[i]
		if region_of(id) == region and is_open(id):
			return id
	return ""


func is_region_open(region: String) -> bool:
	return open_in(region) != ""


func open(id: String) -> void:
	var c: Control = control_of(id)
	if c == null:
		return
	_prepare_open()
	PanelTheme.transition_panel(c, true)
	# Already visible (re-open inside a fade-out) emits no visibility_changed.
	_mark_open(id)


func close(id: String) -> void:
	var e: Dictionary = _entries.get(id, {}) as Dictionary
	if e.is_empty():
		return
	if id in _SIDE_IDS:
		_close_side(id)
		if _open_side == id:
			_open_side = ""
		return
	if id in _MODAL_IDS:
		if _open_modal == id:
			close_modal()
		else:
			_close_modal_id(id)
		return
	var fn: Callable = e.get("close", Callable())
	if fn.is_valid():
		fn.call()
	else:
		var c: Control = control_of(id)
		if c != null:
			PanelTheme.transition_panel(c, false)


func toggle(id: String) -> void:
	if is_open(id):
		close(id)
	else:
		open(id)


# Escape: close the most recently opened panel that is still open.
func close_top() -> bool:
	for i in range(_order.size() - 1, -1, -1):
		var id: String = _order[i]
		if is_open(id):
			close(id)
			return true
	return false


# Place every registered panel into `regions` (HudLayout.regions()).
func relayout(regions: Dictionary) -> void:
	_regions = regions
	for id in _entries.keys():
		if control_of(String(id)) != null:
			_place(String(id))
	if bool(_regions.get(HudLayout.COLUMNS_EXCLUSIVE, false)):
		var l: String = open_in(HudLayout.LEFT_COLUMN)
		var r: String = open_in(HudLayout.RIGHT_COLUMN)
		if l != "" and r != "":
			close(l if _order.find(l) < _order.find(r) else r)


func _place(id: String) -> void:
	var e: Dictionary = _entries.get(id, {}) as Dictionary
	var c: Control = control_of(id)
	if c == null or not _regions.has(e.get("region", "")):
		return
	var region: String = String(e["region"])
	var r: Rect2 = _regions[region]
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rect: Rect2 = r
	if region == HudLayout.CENTRE_MODAL:
		var want: Vector2 = e.get("size", Vector2.ZERO)
		rect = HudLayout.centred_in(r, want if want != Vector2.ZERO else r.size)
	# A panel's own floor must not beat its region: clamp it and let the
	# panel's scroll body take up the difference.
	c.custom_minimum_size = c.custom_minimum_size.min(rect.size)
	HudLayout.place(c, rect, region == HudLayout.RIGHT_COLUMN)


func _mark_open(id: String) -> void:
	_order.erase(id)
	_order.append(id)
	var region: String = region_of(id)
	var cols: Array[String] = [HudLayout.LEFT_COLUMN, HudLayout.RIGHT_COLUMN]
	var excl: bool = bool(_regions.get(HudLayout.COLUMNS_EXCLUSIVE, false))
	for other in _entries.keys():
		var oid: String = String(other)
		if oid == id or not is_open(oid):
			continue
		var oreg: String = region_of(oid)
		var clash: bool = oreg == region \
			or (excl and region in cols and oreg in cols)
		if clash:
			close(oid)
	if id in _SIDE_IDS:
		_open_side = id
	elif region == HudLayout.CENTRE_MODAL:
		_open_modal = id
	_sync_backdrop()
	if not _regions.is_empty():
		_place(id)


func _on_entry_visibility(id: String) -> void:
	var c: Control = control_of(id)
	if c == null:
		return
	if c.visible:
		if _order.is_empty() or _order[_order.size() - 1] != id:
			_mark_open(id)
	else:
		_order.erase(id)
		if _open_side == id:
			_open_side = ""
		if _open_modal == id:
			_open_modal = ""
	_sync_backdrop()
	if _main != null and _main.has_method("_on_ui_regions_changed"):
		_main.call("_on_ui_regions_changed")


func _sync_backdrop() -> void:
	var any_modal: bool = false
	for id in _entries.keys():
		var c: Control = control_of(String(id))
		if c != null and c.visible and region_of(String(id)) == HudLayout.CENTRE_MODAL:
			any_modal = true
	if any_modal:
		_set_backdrop(true)
	elif _open_modal == "":
		_set_backdrop(false)


func setup(main: Node) -> void:
	_main = main


func _prepare_open() -> void:
	if _main != null and _main.has_method("_prepare_panel_open"):
		_main.call("_prepare_panel_open")


func ensure_backdrop() -> void:
	if _main == null:
		return
	if _backdrop != null and is_instance_valid(_backdrop):
		return
	_backdrop = ColorRect.new()
	_backdrop.name = "ModalBackdrop"
	_backdrop.color = Color(0, 0, 0, 0.55)
	_backdrop.anchor_right = 1.0
	_backdrop.anchor_bottom = 1.0
	_backdrop.visible = false
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.z_index = PanelTheme.Z_MODAL_SCRIM
	_backdrop.gui_input.connect(_on_backdrop_input)
	_main.add_child(_backdrop)
	_main.move_child(_backdrop, 0)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_modal()
		if _main != null and _main.has_method("_sync_rail_toggles"):
			_main.call("_sync_rail_toggles")


func is_modal_open() -> bool:
	return _open_modal != ""


func is_side_open() -> bool:
	return _open_side != ""


func is_any_panel_open() -> bool:
	return is_modal_open() or is_side_open()


func close_side_panels() -> void:
	_close_side(SIDE_SETTINGS)
	_close_side(SIDE_RENDER)
	_close_side(SIDE_SOUND)
	_close_side(SIDE_LIGHT)
	_close_side(SIDE_NOTIFICATIONS)
	_open_side = ""
	# The rest of the right column (Camera views) is a side panel too.
	for id in _entries.keys():
		var sid: String = String(id)
		if not (sid in _SIDE_IDS) and region_of(sid) == HudLayout.RIGHT_COLUMN \
				and is_open(sid):
			close(sid)


func close_modal() -> void:
	var was: String = _open_modal
	_open_modal = ""
	if was != "":
		_close_modal_id(was)
	# Any other modal-region panel (vessel picker) goes with it.
	for id in _entries.keys():
		var mid: String = String(id)
		if mid != was and region_of(mid) == HudLayout.CENTRE_MODAL and is_open(mid):
			close(mid)
	_set_backdrop(false)


func _close_modal_id(id: String) -> void:
	match id:
		MODAL_LIBRARY:
			_close_library()
		MODAL_CREATOR:
			_close_creator()
		MODAL_ADOPT:
			_hide_panel(_main.get("adopt_panel"))
		_:
			if not (id in _MODAL_IDS) and _entries.has(id):
				close(id)


func close_all() -> void:
	close_side_panels()
	close_modal()
	for id in _entries.keys():
		if is_open(String(id)):
			close(String(id))


func toggle_side(id: String) -> void:
	if _open_side == id:
		_close_side(id)
		_open_side = ""
	else:
		open_side(id)


func open_side(id: String) -> void:
	_prepare_open()
	close_modal()
	for sid in [SIDE_SETTINGS, SIDE_RENDER, SIDE_SOUND, SIDE_LIGHT, SIDE_NOTIFICATIONS]:
		if sid != id:
			_close_side(sid)
	_open_side = id
	match id:
		SIDE_SETTINGS:
			_toggle_settings()
		SIDE_RENDER:
			_toggle_render()
		SIDE_SOUND:
			_toggle_sound()
		SIDE_LIGHT:
			if _main.has_method("_open_light_panel_exclusive"):
				_main.call("_open_light_panel_exclusive")
		SIDE_NOTIFICATIONS:
			if _main.has_method("_open_notifications_panel_exclusive"):
				_main.call("_open_notifications_panel_exclusive")
	_grab_couch_focus_in_open_panel()


func toggle_modal(id: String) -> void:
	if _open_modal == id:
		close_modal()
	else:
		open_modal(id)


func open_modal(id: String) -> void:
	_prepare_open()
	close_side_panels()
	if _open_modal != "" and _open_modal != id:
		close_modal()
	_open_modal = id
	ensure_backdrop()
	_set_backdrop(true)
	match id:
		MODAL_LIBRARY:
			var lp: Variant = _main.get("library_panel")
			if lp != null and lp.has_method("open"):
				lp.open()
			elif lp != null:
				_show_panel(lp)
			if lp != null:
				lp.z_index = PanelTheme.Z_MENU_MODAL
		MODAL_CREATOR:
			var cp: Variant = _main.get("creature_creator_panel")
			if cp != null and cp.has_method("open"):
				cp.open()
			if cp != null:
				cp.z_index = PanelTheme.Z_MENU_MODAL
		MODAL_ADOPT:
			var sp: Variant = _main.get("adopt_panel")
			if sp != null:
				# Through transition_panel, not a bare `visible = true`: the
				# store closes via _hide_panel(), so a re-open inside the
				# out-tween has to cancel that tween or its completion
				# callback hides the panel again a frame later.
				PanelTheme.transition_panel(sp, true)
				sp.z_index = PanelTheme.Z_MENU_MODAL
				if sp.has_method("_regenerate"):
					sp._regenerate()
	_grab_couch_focus_in_open_panel()


func notify_side_closed(id: String) -> void:
	if _open_side == id:
		_open_side = ""


func notify_modal_closed(id: String) -> void:
	if _open_modal == id:
		_open_modal = ""
		_set_backdrop(false)


func _toggle_settings() -> void:
	var panel: Variant = _main.get("settings_panel")
	if panel == null:
		return
	if panel.has_method("toggle"):
		panel.toggle()
		return
	if panel.has_method("_pull_from_config"):
		PanelTheme.transition_panel(panel, true)
		panel._pull_from_config()


func _toggle_render() -> void:
	var panel: Variant = _main.get("render_panel")
	if panel == null:
		return
	if panel.has_method("toggle"):
		panel.toggle()
		return
	if PanelTheme.is_panel_open(panel):
		PanelTheme.transition_panel(panel, false)
	else:
		PanelTheme.transition_panel(panel, true)
		if panel.has_method("_pull_from_config"):
			panel._pull_from_config()


func _toggle_sound() -> void:
	var panel: Variant = _main.get("sound_panel")
	if panel == null:
		return
	if panel.has_method("toggle"):
		panel.toggle()
		return
	if PanelTheme.is_panel_open(panel) and panel.has_method("_close"):
		panel._close()
	elif panel.has_method("_pull_from_config"):
		PanelTheme.transition_panel(panel, true)
		panel._pull_from_config()
		if panel.has_method("_refresh_live_readout"):
			panel._refresh_live_readout()


func _show_panel(panel: Variant) -> void:
	if panel == null:
		return
	if panel.has_method("toggle"):
		if not PanelTheme.is_panel_open(panel):
			PanelTheme.transition_panel(panel, true)
			if panel.has_method("_pull_from_config"):
				panel._pull_from_config()
			elif panel.has_method("_regenerate"):
				panel._regenerate()
	else:
		PanelTheme.transition_panel(panel, true)


func _hide_panel(panel: Variant) -> void:
	if panel == null:
		return
	PanelTheme.transition_panel(panel, false)


func _close_side(id: String) -> void:
	match id:
		SIDE_SETTINGS:
			var panel: Variant = _main.get("settings_panel")
			# is_panel_open(), not .visible — a panel already fading out is
			# still "visible", and toggling it would re-open it.
			if panel != null and PanelTheme.is_panel_open(panel) and panel.has_method("toggle"):
				panel.toggle()
		SIDE_RENDER:
			_hide_panel(_main.get("render_panel"))
		SIDE_SOUND:
			_hide_panel(_main.get("sound_panel"))
		SIDE_LIGHT:
			if _main.has_method("_close_light_panel"):
				_main.call("_close_light_panel")
		SIDE_NOTIFICATIONS:
			if _main.has_method("_close_notifications_panel"):
				_main.call("_close_notifications_panel")


func _close_creator() -> void:
	var cp: Variant = _main.get("creature_creator_panel")
	if cp != null and cp.has_method("close"):
		cp.close()
	else:
		_hide_panel(cp)


func _close_library() -> void:
	var lp: Variant = _main.get("library_panel")
	if lp != null and lp.has_method("close"):
		lp.close()
	else:
		_hide_panel(lp)


func _set_backdrop(on: bool) -> void:
	ensure_backdrop()
	if _backdrop != null:
		_backdrop.visible = on


func _grab_couch_focus_in_open_panel() -> void:
	var panel: Control = _visible_panel_control()
	if panel == null:
		return
	var prefer := PackedStringArray()
	if panel == _main.get("adopt_panel"):
		prefer = PackedStringArray(["ADOPT", "Reroll", "Close"])
	elif panel == _main.get("library_panel"):
		prefer = PackedStringArray(["Close"])
	elif panel == _main.get("_light_panel"):
		prefer = PackedStringArray(["Close", "Reset", "Apply"])
	elif panel == _main.get("_notifications_panel"):
		prefer = PackedStringArray(["Close", "Clear", "Dismiss"])
	elif panel == _main.get("settings_panel"):
		prefer = PackedStringArray(["Close", "Apply", "Save"])
	elif panel == _main.get("render_panel"):
		prefer = PackedStringArray(["Close", "Mac Safe", "Apply"])
	elif panel == _main.get("sound_panel"):
		prefer = PackedStringArray(["Close", "Mute"])
	PanelTheme.schedule_couch_focus(panel, prefer)


func _visible_panel_control() -> Control:
	if _main == null:
		return null
	var candidates: Array = [
		_main.get("settings_panel"),
		_main.get("render_panel"),
		_main.get("sound_panel"),
		_main.get("_light_panel"),
		_main.get("_notifications_panel"),
		_main.get("library_panel"),
		_main.get("creature_creator_panel"),
		_main.get("adopt_panel"),
	]
	for c in candidates:
		if c is Control and (c as Control).visible:
			return c as Control
	return null


func _first_focusable_button(n: Node) -> BaseButton:
	if n is BaseButton:
		var b: BaseButton = n as BaseButton
		if b.focus_mode != Control.FOCUS_NONE and b.visible and not b.disabled:
			return b
	for c in n.get_children():
		var found: BaseButton = _first_focusable_button(c)
		if found != null:
			return found
	return null
