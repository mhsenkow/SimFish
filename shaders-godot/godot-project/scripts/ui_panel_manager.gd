# Central panel open/close policy: side panels are mutually exclusive;
# modals get a dim backdrop and block tank input.
class_name UiPanelManager
extends RefCounted

const SIDE_SETTINGS := "settings"
const SIDE_RENDER := "render"
const SIDE_SOUND := "sound"
const SIDE_LIGHT := "light"
const SIDE_NOTIFICATIONS := "notifications"

const MODAL_LIBRARY := "library"
const MODAL_CREATOR := "creator"
const MODAL_STORE := "store"

var _main: Node = null
var _backdrop: ColorRect = null
var _open_side: String = ""
var _open_modal: String = ""


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
	_backdrop.z_index = 150
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


func close_side_panels() -> void:
	_close_side(SIDE_SETTINGS)
	_close_side(SIDE_RENDER)
	_close_side(SIDE_SOUND)
	_close_side(SIDE_LIGHT)
	_close_side(SIDE_NOTIFICATIONS)
	_open_side = ""


func close_modal() -> void:
	if _open_modal == "":
		_set_backdrop(false)
		return
	match _open_modal:
		MODAL_LIBRARY:
			_close_library()
		MODAL_CREATOR:
			_close_creator()
		MODAL_STORE:
			_hide_panel(_main.get("fish_store_panel"))
	_open_modal = ""
	_set_backdrop(false)


func close_all() -> void:
	close_side_panels()
	close_modal()


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
				lp.z_index = 200
		MODAL_CREATOR:
			var cp: Variant = _main.get("creature_creator_panel")
			if cp != null and cp.has_method("open"):
				cp.open()
			if cp != null:
				cp.z_index = 200
		MODAL_STORE:
			var sp: Variant = _main.get("fish_store_panel")
			if sp != null:
				sp.visible = true
				sp.mouse_filter = Control.MOUSE_FILTER_STOP
				sp.z_index = 200
				if sp.has_method("_regenerate"):
					sp._regenerate()


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
		panel.visible = true
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel._pull_from_config()


func _toggle_render() -> void:
	var panel: Variant = _main.get("render_panel")
	if panel == null:
		return
	if panel.has_method("toggle"):
		panel.toggle()
		return
	if panel.visible:
		panel.visible = false
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		panel.visible = true
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		if panel.has_method("_pull_from_config"):
			panel._pull_from_config()


func _toggle_sound() -> void:
	var panel: Variant = _main.get("sound_panel")
	if panel == null:
		return
	if panel.has_method("toggle"):
		panel.toggle()
		return
	if panel.visible and panel.has_method("_close"):
		panel._close()
	elif panel.has_method("_pull_from_config"):
		panel.visible = true
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel._pull_from_config()
		if panel.has_method("_refresh_live_readout"):
			panel._refresh_live_readout()


func _show_panel(panel: Variant) -> void:
	if panel == null:
		return
	if panel.has_method("toggle"):
		if not panel.visible:
			panel.visible = true
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			if panel.has_method("_pull_from_config"):
				panel._pull_from_config()
			elif panel.has_method("_regenerate"):
				panel._regenerate()
	else:
		panel.visible = true
		panel.mouse_filter = Control.MOUSE_FILTER_STOP


func _hide_panel(panel: Variant) -> void:
	if panel == null:
		return
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _close_side(id: String) -> void:
	match id:
		SIDE_SETTINGS:
			var panel: Variant = _main.get("settings_panel")
			if panel != null and panel.visible and panel.has_method("toggle"):
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
