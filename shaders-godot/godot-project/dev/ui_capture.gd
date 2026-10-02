# UI capture + layout audit — every panel and HUD state, the way the game builds it.
#
# WHY THIS EXISTS. The HUD, the rail, the side panels, the modals and the
# follow-thought strip are placed by a dozen hand-written anchor blocks in
# main.gd plus each panel's own constructor. Nothing checks them against each
# other, so two panels can dock into the same rect, a strip can grow under a
# side panel, or a toast stack can sit on top of the say box, and the only way
# anyone finds out is by opening things in the right order. This harness opens
# them in every order worth trying, photographs each state, and MEASURES it.
#
#   cd shaders-godot/godot-project
#   UI_CAPTURE_OUT=/abs/dir Godot --path . res://dev/ui_capture.tscn 2>&1 | grep ui_capture
#
# NOT --headless: the dummy renderer produces no image. It opens a window,
# walks the states (a minute or two) and quits itself.
#
# BOOT is exactly dev/visual_capture.gd's: TankConfig.capture_mode (config
# saves suspended, SaveManager load/save of the active slot blocked, so no save
# slot is read or written), reset_to_defaults, AestheticsRuntime first-launch
# defaults, one named scenario, the render forced live (the window never takes
# focus), and process_priority 1000 so the harness runs after main.gd. The
# first-run onboarding "seen" flags are set so a tutorial card does not sit on
# top of every state.
#
# STATES (see STATES below): each is a list of steps. A step is a main.gd
# method name plus arguments, called through main's OWN open/toggle functions
# (_ui_toggle_side, _toggle_mind_panel, _toggle_rail_flyout ...) so the capture
# shows the placement code the player gets. "@var:<name>" in an argument is
# replaced by main.get(<name>). Pseudo-steps: @follow (follow a random fish),
# @strip (fill the follow-thought strip with a long thought + keeper history,
# i.e. expand it), @toasts (push three notification toasts + a status and a
# feed toast), @notifs (fill the notifications list). A main.gd method that no
# longer exists is skipped with one warning — the rest of the run continues.
#
# Between states everything is closed again (main's own Escape chain, then
# UiPanelManager.close_all and each panel's close function) and toasts are
# cleared, so a state shows only what its steps opened.
#
# PASSES: every state is shot at two window sizes. The project stretches a
# fixed 1536x864 viewport (stretch/mode=viewport, aspect keep), so a smaller
# WINDOW alone only letterboxes the same layout. The narrow pass therefore also
# sets content_scale_size to 900x600 so the layout itself is narrow — the
# stress case for anything placed with literals (UI_CAPTURE_NARROW_LOGICAL=0
# for window-only).
#
# MEASUREMENTS, per state, printed as "[ui_capture] ..." lines and written in
# full to <out>/report.json:
#   - every visible element: the Controls main.gd layers over the render,
#     descended through non-drawing containers and full-screen layers until
#     something that draws (panel, button, label ...). Full-screen ColorRect /
#     TextureRect (scrims, the render display) are ignored. Each element
#     belongs to a GROUP = its first non-full-screen ancestor under main,
#     i.e. one panel / one HUD block.
#   - OVERLAP: pairwise intersections >= 4x4 px between elements of DIFFERENT
#     groups (parent/child never counts), aggregated per group pair; "intra"
#     overlaps inside one group are reported too. After the baseline, only
#     overlaps that the baseline does not already have are printed (new=1).
#   - OFFSCREEN: groups whose union rect leaves the viewport, px per side.
#   - PANEL: for each group the state opened (absent from the baseline): rect,
#     effective z, script, stylebox corner radius + content margins, every
#     close-like button and WHERE in the panel it sits (top-right, bottom-
#     right ...), whether it scrolls, whether keyboard/gamepad focus landed
#     inside it.
#   - ESC: a real Escape key event is sent up to 4 times; how many presses it
#     took to close what the state opened, and what never closed.
#
# OUTPUT (<out> = UI_CAPTURE_OUT, default user://ui_capture):
#   <pass>/<NN>_<state>.png   full frame, HUD included
#   sheet_<pass>_<k>.png      contact sheets, 3x4 captioned thumbnails
#   report_<pass>.json/.txt   the measurements (one pair per pass, so the two
#                             passes can run as separate invocations)
#
# Groups main.gd creates without a name (@Label@2993 ...) are labelled by the
# main.gd member variable that holds them ("$_follow_label") when one does.
#
# Environment:
#   UI_CAPTURE_OUT             output dir (absolute, or user://)
#   UI_CAPTURE_STATES          comma list of state ids (baseline always runs)
#   UI_CAPTURE_PASSES          comma list of pass ids (1152x648,900x600,
#                              enlarged_text,pseudolocale,controller)
#   UI_CAPTURE_SETTLE          frames before the first state (default 360;
#                              also at least UI_CAPTURE_SETTLE_S seconds, def. 25)
#   UI_CAPTURE_SCENARIO        scenario id (default beginner_sandbox)
#   UI_CAPTURE_NARROW_LOGICAL  0 = narrow pass resizes the window only
#   UI_CAPTURE_DIFFICULT=1     shorthand: only #008 difficult passes + key states

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")
const AestheticsScript = preload("res://scripts/aesthetics_runtime.gd")
const Readiness = preload("res://scripts/capture_readiness.gd")

const DEFAULT_OUT_DIR: String = "user://ui_capture"
const DEFAULT_SCENARIO: String = "beginner_sandbox"
# Cosmetic settle AFTER World.build_complete (HOLISTIC #004).
const DEFAULT_SETTLE: int = 90
# Waits are "at least N frames AND at least S seconds": a capture window never
# has focus and can run at single-digit fps, where a frame count alone is
# shorter than the panels' 0.16 s fade.
const STATE_SETTLE: Array = [4, 0.45]
const ESC_SETTLE: Array = [3, 0.3]
const RESET_SETTLE: Array = [2, 0.15]
const RESIZE_SETTLE: Array = [10, 1.0]
const DEFAULT_SETTLE_S: float = 4.0
const READY_TIMEOUT_S: float = 45.0
const DAY_PHASE: float = 0.25
const THUMB_W: int = 384
const CAPTION_H: int = 20
const SHEET_COLS: int = 3
const SHEET_ROWS: int = 4
const MAX_DEPTH: int = 4
const MIN_OVERLAP_PX: float = 4.0
const CLOSE_TEXTS: PackedStringArray = ["Close", "×", "✕", "✖", "X", "x", "Done",
	"Cancel", "Back", "Dismiss", "Got it", "Hide"]
const SEEN_FLAGS: PackedStringArray = ["tutorial_seen", "walkthrough_completed",
	"ai_onboarding_seen", "guardian_voice_explainer_seen", "guardian_mind_info_seen"]

const PASSES: Array[Dictionary] = [
	{"id": "1152x648", "window": Vector2i(1152, 648), "logical": Vector2i(0, 0)},
	{"id": "900x600", "window": Vector2i(900, 600), "logical": Vector2i(900, 600)},
	# HOLISTIC #008 — difficult content / a11y passes (navigable + primary visible).
	{"id": "enlarged_text", "window": Vector2i(1152, 648), "logical": Vector2i(0, 0),
		"ui_font_scale": 1.5},
	{"id": "pseudolocale", "window": Vector2i(1152, 648), "logical": Vector2i(0, 0),
		"locale": "qps"},
	{"id": "controller", "window": Vector2i(1152, 648), "logical": Vector2i(0, 0),
		"controller_only": true},
]

const STATES: Array[Dictionary] = [
	{"id": "baseline", "steps": []},
	{"id": "rail_create", "steps": [["_toggle_rail_flyout", "create", "@var:_rail_create_btn"]]},
	{"id": "rail_world", "steps": [["_toggle_rail_flyout", "world", "@var:_rail_world_btn"]]},
	{"id": "rail_look", "steps": [["_toggle_rail_flyout", "appearance", "@var:_rail_appearance_btn"]]},
	{"id": "rail_system", "steps": [["_toggle_rail_flyout", "system", "@var:_rail_system_btn"]]},
	{"id": "settings", "steps": [["_ui_toggle_side", "settings"]]},
	{"id": "render", "steps": [["_ui_toggle_side", "render"]]},
	{"id": "sound", "steps": [["_ui_toggle_side", "sound"]]},
	{"id": "light", "steps": [["_toggle_light_panel"]]},
	{"id": "notifications", "steps": [["@notifs"], ["_toggle_notifications_panel"]]},
	{"id": "toasts", "steps": [["@toasts"]]},
	{"id": "residents", "steps": [["_toggle_residents_panel"]]},
	{"id": "mind", "steps": [["_toggle_mind_panel"]]},
	{"id": "chronicle", "steps": [["_toggle_chronicle_panel"]]},
	{"id": "camera_views", "steps": [["_toggle_camera_views_panel"]]},
	{"id": "follow_strip", "steps": [["@follow"], ["@strip"]]},
	{"id": "library", "steps": [["_ui_toggle_modal", "library"]]},
	{"id": "creator", "steps": [["_ui_toggle_modal", "creator"]]},
	{"id": "adopt", "steps": [["_ui_toggle_modal", "adopt"]]},
	{"id": "vessel_picker", "steps": [["_toggle_vessel_picker"]]},
	{"id": "cheat_sheet", "steps": [["_toggle_cheat_sheet"]]},
	{"id": "gamepad_menu", "steps": [["_open_gamepad_menu"]]},
	{"id": "chip_water", "steps": [["_show_water_chemistry_popup", Color.WHITE]]},
	{"id": "chip_story", "steps": [["_show_story_popup", Color.WHITE]]},
	{"id": "chip_alert", "steps": [["_show_alert_guidance_popup", Color.WHITE]]},
	# HOLISTIC #008 — long creature names stress the residents list + strip.
	{"id": "long_names", "steps": [["@long_names"], ["_toggle_residents_panel"]]},
	{"id": "controller_path", "steps": [["_open_gamepad_menu"]]},
	# Combinations — the "overlap when they expand" cases.
	{"id": "residents+mind", "steps": [["_toggle_residents_panel"], ["_toggle_mind_panel"]]},
	{"id": "mind+chronicle", "steps": [["_toggle_mind_panel"], ["_toggle_chronicle_panel"]]},
	{"id": "residents+strip+toasts", "steps": [["_toggle_residents_panel"], ["@follow"], ["@strip"], ["@toasts"]]},
	{"id": "mind+strip", "steps": [["_toggle_mind_panel"], ["@strip"]]},
	{"id": "chronicle+strip+toasts", "steps": [["@follow"], ["_toggle_chronicle_panel"], ["@strip"], ["@toasts"]]},
	{"id": "settings+residents", "steps": [["_toggle_residents_panel"], ["_ui_toggle_side", "settings"]]},
	{"id": "camera+residents", "steps": [["_toggle_residents_panel"], ["_toggle_camera_views_panel"]]},
	{"id": "notifications+toasts", "steps": [["@notifs"], ["_toggle_notifications_panel"], ["@toasts"]]},
	{"id": "light+strip+toasts", "steps": [["_toggle_light_panel"], ["@follow"], ["@strip"], ["@toasts"]]},
	{"id": "library+toasts", "steps": [["_ui_toggle_modal", "library"], ["@toasts"]]},
	{"id": "rail_system+residents", "steps": [["_toggle_residents_panel"], ["_toggle_rail_flyout", "system", "@var:_rail_system_btn"]]},
	{"id": "chip_water+residents", "steps": [["_toggle_residents_panel"], ["_show_water_chemistry_popup", Color.WHITE]]},
]

var _main: Node = null
var _cfg: Node = null
var _out: String = DEFAULT_OUT_DIR
var _settle: int = DEFAULT_SETTLE
var _only_states: PackedStringArray = PackedStringArray()
var _only_passes: PackedStringArray = PackedStringArray()
var _narrow_logical: bool = true
var _warned: Dictionary = {}
var _report: Dictionary = {"passes": []}
var _caption_vp: SubViewport = null
var _caption_label: Label = null
var _default_content_scale: Vector2i = Vector2i.ZERO
var _toast_serial: int = 0
var _settle_s: float = DEFAULT_SETTLE_S
var _var_names: Dictionary = {}     # instance id -> main.gd member name
var _group_nodes: Dictionary = {}   # group label -> Control
var _pass_lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_cfg = get_node_or_null("/root/TankConfig")
	if _cfg == null:
		push_error("[ui_capture] TankConfig autoload missing")
		get_tree().quit(1)
		return
	_cfg.set("capture_mode", true)
	if _cfg.has_method("reset_to_defaults"):
		_cfg.call("reset_to_defaults")
	_cfg.set("duotone_mode", "none")
	_cfg.set("colorblind_palette", "none")
	_cfg.set("beauty_defaults_applied", false)
	AestheticsScript.apply_first_launch_defaults(_cfg)
	_apply_scenario(_env("UI_CAPTURE_SCENARIO", DEFAULT_SCENARIO))
	for flag in SEEN_FLAGS:
		if _cfg.get(flag) != null:
			_cfg.set(flag, true)
	if _cfg.get("walkthrough_pending") != null:
		_cfg.set("walkthrough_pending", false)
	_settle = maxi(30, _env("UI_CAPTURE_SETTLE", str(DEFAULT_SETTLE)).to_int())
	_settle_s = maxf(1.0, _env("UI_CAPTURE_SETTLE_S", str(DEFAULT_SETTLE_S)).to_float())
	_only_states = _env("UI_CAPTURE_STATES", "").split(",", false)
	_only_passes = _env("UI_CAPTURE_PASSES", "").split(",", false)
	if _env("UI_CAPTURE_DIFFICULT", "") == "1":
		if _only_passes.is_empty():
			_only_passes = PackedStringArray(["enlarged_text", "pseudolocale", "controller"])
		if _only_states.is_empty():
			_only_states = PackedStringArray([
				"baseline", "settings", "residents", "long_names", "controller_path", "gamepad_menu"])
	_narrow_logical = _env("UI_CAPTURE_NARROW_LOGICAL", "1") != "0"
	_out = _env("UI_CAPTURE_OUT", DEFAULT_OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	process_priority = 1000
	_default_content_scale = get_window().content_scale_size
	_build_caption()
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[ui_capture] booting; settle=", _settle, " states=", STATES.size(), " out=",
		ProjectSettings.globalize_path(_out))
	_run.call_deferred()


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key)
	return fallback if v.strip_edges().is_empty() else v.strip_edges()


func _apply_scenario(id: String) -> void:
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == id:
			ScenarioPickerScript.apply_scenario(sc, _cfg)
			print("[ui_capture] scenario=", id)
			return
	push_warning("[ui_capture] unknown scenario '%s' — using config defaults" % id)


func _process(_dt: float) -> void:
	if _main == null:
		return
	# Same trap as visual_capture: an unfocused window pauses the sim and
	# freezes both SubViewports, so every shot would be one stale frame.
	if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
		_main.call("_on_focus_in")
	for key in ["sub_viewport", "_post_viewport"]:
		var vp: Variant = _main.get(key)
		if vp is SubViewport and (vp as SubViewport).render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var sim: Variant = _main.get("_sim")
	if sim is Node and (sim as Node).get("day_phase") != null:
		(sim as Node).set("day_phase", DAY_PHASE)
	# A capture run is nothing but idle time; past the idle threshold main.gd
	# starts the screensaver tour and fades the HUD.
	_main.set("_hud_idle_seconds", 0.0)


func _build_caption() -> void:
	_caption_vp = SubViewport.new()
	_caption_vp.size = Vector2i(THUMB_W, CAPTION_H)
	_caption_vp.transparent_bg = false
	_caption_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_caption_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.13)
	bg.size = Vector2(THUMB_W, CAPTION_H)
	_caption_vp.add_child(bg)
	_caption_label = Label.new()
	_caption_label.position = Vector2(4, 0)
	_caption_label.add_theme_font_size_override("font_size", 13)
	_caption_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_caption_vp.add_child(_caption_label)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _wait(spec: Array) -> void:
	var t0: int = Time.get_ticks_msec()
	var n: int = int(spec[0])
	var ms: int = int(float(spec[1]) * 1000.0)
	var k: int = 0
	while k < n or Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
		k += 1


func _log(line: String) -> void:
	var s: String = "[ui_capture] " + line
	print(s)
	_pass_lines.append(s)


# ---- main.gd access ----------------------------------------------------------

func _call(method: String, args: Array = []) -> Variant:
	if _main == null or not _main.has_method(method):
		if not _warned.has(method):
			_warned[method] = true
			_log("WARN missing main.%s — step skipped" % method)
		return null
	return _main.callv(method, args)


func _hide_var(key: String) -> void:
	var v: Variant = _main.get(key)
	if v is CanvasItem and is_instance_valid(v) and (v as CanvasItem).visible:
		(v as CanvasItem).visible = false


func _do_step(step: Array) -> void:
	var method: String = String(step[0])
	var args: Array = []
	for a in step.slice(1):
		if a is String and String(a).begins_with("@var:"):
			args.append(_main.get(String(a).substr(5)))
		else:
			args.append(a)
	match method:
		"@follow":
			_call("follow_random_fish")
		"@strip":
			await _expand_strip()
		"@toasts":
			_push_toasts()
		"@notifs":
			_push_notifs()
		"@long_names":
			_apply_long_creature_names()
		_:
			_call(method, args)


func _apply_long_creature_names() -> void:
	# HOLISTIC #008 — stress layout with intentionally long display names.
	var long_name: String = "Alexandrina-of-the-Moonlit-Vallisneria-Curtain-XXVIII"
	var sim: Variant = _main.get("_sim")
	if not (sim is Node):
		_log("WARN no _sim for @long_names")
		return
	var n: int = 0
	for f in (sim as Node).get("fish"):
		if f != null and is_instance_valid(f) and f.get("fish_name") != null:
			f.set("fish_name", "%s-%d" % [long_name, n])
			n += 1
	var shrimp_list: Variant = (sim as Node).get("shrimp")
	if shrimp_list is Array:
		for s in shrimp_list:
			if s != null and is_instance_valid(s) and s.get("shrimp_name") != null:
				s.set("shrimp_name", "Shrimp-%s-%d" % [long_name, n])
				n += 1
	_log("long_names applied to %d creatures" % n)

func _expand_strip() -> void:
	var strip: Variant = _main.get("_follow_thought_strip")
	if not (strip is Control):
		_log("WARN no _follow_thought_strip — @strip skipped")
		return
	var body: Variant = _main.get("_follow_thought_strip_body")
	if body is Label:
		(body as Label).text = ("The light is warmer on this side of the wood, and the " +
			"snails have been at the glass again. I keep coming back to the same patch of " +
			"moss; something about it feels like the start of a place to stay.")
		(body as Label).visible = true
	var hist: Variant = _main.get("_keeper_history_label")
	if hist is Label:
		(hist as Label).text = "you: how are you today?\nit: hungry, mostly.\nyou: soon."
		(hist as Label).visible = true
	(strip as Control).visible = true
	(strip as Control).modulate.a = 1.0
	# Line counts need a layout pass before main can size the strip from them.
	await _frames(3)
	_call("_layout_follow_thought_strip")


func _push_toasts() -> void:
	for _k in 3:
		_toast_serial += 1
		_call("_push_notification", ["system", "info", "UI capture toast %d" % _toast_serial,
			"A toast body long enough to wrap onto a second line in the stack.", true])
	_call("_show_status_toast", ["Status toast from ui_capture"])
	_call("_show_feed_toast", ["Feed toast from ui_capture"])


func _push_notifs() -> void:
	var sev: PackedStringArray = ["info", "important", "critical", "info", "info"]
	for k in sev.size():
		_toast_serial += 1
		_call("_push_notification", ["system", sev[k], "Notification %d" % _toast_serial,
			"Something happened in the tank that the keeper may want to know about.", false])


func _reset() -> void:
	for _i in 12:
		var r: Variant = _call("_dismiss_blocking_overlays")
		if not bool(r):
			break
	var uip: Variant = _main.get("_ui_panels")
	if uip is Object and (uip as Object).has_method("close_all"):
		(uip as Object).call("close_all")
	for m in ["_close_rail_flyout", "_close_chip_popups", "_close_residents_panel",
			"_close_camera_views_panel", "_close_gamepad_menu", "_close_light_panel",
			"_close_notifications_panel"]:
		_call(m)
	_hide_var("_mind_panel")
	_hide_var("_chronicle_panel")
	var vpk: Variant = _main.get("_vessel_picker")
	if vpk is Control and is_instance_valid(vpk) and (vpk as Control).visible:
		_call("_toggle_vessel_picker")
	var cs: Variant = _main.get("_cheat_sheet")
	if cs is Control and is_instance_valid(cs) and (cs as Control).is_visible_in_tree():
		_call("_toggle_cheat_sheet")
	_call("clear_follow")
	var layer: Variant = _main.get("_notifications_toast_layer")
	if layer is Node and is_instance_valid(layer):
		for ch in (layer as Node).get_children():
			ch.queue_free()
	_main.set("_notification_toast_active", 0)
	var recent: Variant = _main.get("_toast_recent_keys")
	if recent is Dictionary:
		(recent as Dictionary).clear()
	for key in ["_status_toast", "_feed_toast_panel", "_discovery_toast"]:
		_hide_var(key)
	var body: Variant = _main.get("_follow_thought_strip_body")
	if body is Label:
		(body as Label).text = ""
	_hide_var("_keeper_history_label")
	await _wait(RESET_SETTLE)


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	Input.parse_input_event(up)


# ---- measurement -------------------------------------------------------------

func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


static func _draws(c: Control) -> bool:
	return c is PanelContainer or c is Panel or c is TextureRect or c is BaseButton \
		or c is Label or c is LineEdit or c is RichTextLabel or c is TextEdit \
		or c is ColorRect or c is Range or c is ItemList or c is Tree \
		or c is ScrollContainer or c is TabContainer or c is NinePatchRect \
		or c is SubViewportContainer


func _refresh_var_names() -> void:
	_var_names.clear()
	for prop in _main.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var v: Variant = _main.get(String(prop["name"]))
		if v is Node and is_instance_valid(v):
			_var_names[(v as Node).get_instance_id()] = String(prop["name"])


func _collect() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_refresh_var_names()
	var vp: Vector2 = _vp_size()
	for child in _main.get_children():
		if child is Control:
			_consider(child as Control, 0, "", vp, out)
		elif child is CanvasLayer and (child as CanvasLayer).visible:
			for ch in child.get_children():
				if ch is Control:
					_consider(ch as Control, 0, "", vp, out)
	return out


func _consider(c: Control, depth: int, group: String, vp: Vector2, out: Array[Dictionary]) -> void:
	if not c.is_visible_in_tree() or c.modulate.a < 0.05:
		return
	var r: Rect2 = c.get_global_rect()
	var full: bool = r.size.x >= vp.x * 0.9 and r.size.y >= vp.y * 0.85
	if full:
		# A scrim, the render display, or a full-rect layer holding real UI.
		if c is ColorRect or c is TextureRect or c is SubViewportContainer:
			return
		for ch in c.get_children():
			if ch is Control:
				_consider(ch as Control, depth, "", vp, out)
		return
	var g: String = group
	if g == "":
		g = String(_main.get_path_to(c))
		if String(c.name).begins_with("@"):
			var anc: Node = c
			while anc != null and anc != _main:
				if _var_names.has(anc.get_instance_id()):
					g = "$" + String(_var_names[anc.get_instance_id()]) \
						+ ("" if anc == c else "/" + String(anc.get_path_to(c)))
					break
				anc = anc.get_parent()
		_group_nodes[g] = c
	if not _draws(c) and c.get_script() == null and not c.get_children().any(
			func(ch: Node) -> bool: return ch is Control):
		return  # an empty layout box draws nothing
	if not _draws(c) and depth < MAX_DEPTH and c.get_child_count() > 0:
		for ch in c.get_children():
			if ch is Control:
				_consider(ch as Control, depth + 1, g, vp, out)
		return
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	out.append({"path": String(_main.get_path_to(c)), "group": g, "rect": r,
		"cls": c.get_class(), "z": _eff_z(c)})


static func _eff_z(c: CanvasItem) -> int:
	var z: int = c.z_index
	var n: Node = c
	while n is CanvasItem and (n as CanvasItem).z_as_relative:
		n = n.get_parent()
		if n is CanvasItem:
			z += (n as CanvasItem).z_index
		else:
			break
	return z


static func _rect_arr(r: Rect2) -> Array:
	return [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]


static func _rect_str(r: Rect2) -> String:
	return "%d,%d,%dx%d" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]


static func _group_rects(els: Array[Dictionary]) -> Dictionary:
	var g: Dictionary = {}
	for e in els:
		var key: String = String(e["group"])
		var r: Rect2 = e["rect"]
		g[key] = (g[key] as Rect2).merge(r) if g.has(key) else r
	return g


func _overlaps(els: Array[Dictionary]) -> Dictionary:
	var agg: Dictionary = {}
	for i in els.size():
		var a: Dictionary = els[i]
		var ra: Rect2 = a["rect"]
		for j in range(i + 1, els.size()):
			var b: Dictionary = els[j]
			var rb: Rect2 = b["rect"]
			if not ra.intersects(rb):
				continue
			var inter: Rect2 = ra.intersection(rb)
			if inter.size.x < MIN_OVERLAP_PX or inter.size.y < MIN_OVERLAP_PX:
				continue
			var pa: String = String(a["path"])
			var pb: String = String(b["path"])
			if pa.begins_with(pb + "/") or pb.begins_with(pa + "/"):
				continue
			var ga: String = String(a["group"])
			var gb: String = String(b["group"])
			var kind: String = "intra" if ga == gb else "inter"
			var lo: String = ga if ga < gb else gb
			var hi: String = gb if ga < gb else ga
			var key: String = "%s|%s|%s" % [kind, lo, hi]
			if agg.has(key):
				var d: Dictionary = agg[key]
				d["n"] = int(d["n"]) + 1
				d["rect"] = (d["rect"] as Rect2).merge(inter)
			else:
				agg[key] = {"kind": kind, "a": lo, "b": hi, "n": 1, "rect": inter,
					"example": "%s x %s" % [pa, pb]}
	return agg


static func _offscreen(groups: Dictionary, vp: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in groups:
		var r: Rect2 = groups[key]
		var l: float = maxf(0.0, -r.position.x)
		var t: float = maxf(0.0, -r.position.y)
		var rr: float = maxf(0.0, r.end.x - vp.x)
		var b: float = maxf(0.0, r.end.y - vp.y)
		if l > 1.0 or t > 1.0 or rr > 1.0 or b > 1.0:
			out.append({"group": key, "rect": r, "out": [roundi(l), roundi(t), roundi(rr), roundi(b)]})
	return out


func _panel_details(group: String, grect: Rect2) -> Dictionary:
	var node: Control = _group_nodes.get(group, null) as Control
	if node != null and not is_instance_valid(node):
		node = null
	var d: Dictionary = {"group": group, "rect": _rect_arr(grect)}
	if node == null:
		return d
	d["cls"] = node.get_class()
	var scr: Variant = node.get_script()
	d["script"] = (scr as Script).resource_path.get_file() if scr is Script else ""
	d["z"] = _eff_z(node)
	# First PanelContainer at or under the group root carries the chrome.
	var pc: PanelContainer = _first_of(node, "PanelContainer", 3) as PanelContainer
	if pc != null:
		var sb: StyleBox = pc.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			var f: StyleBoxFlat = sb as StyleBoxFlat
			d["corner"] = f.corner_radius_top_left
			d["margins"] = [roundi(f.content_margin_left), roundi(f.content_margin_top),
				roundi(f.content_margin_right), roundi(f.content_margin_bottom)]
			d["bg_a"] = snappedf(f.bg_color.a, 0.01)
		else:
			d["corner"] = -1
	var closes: Array = []
	var buttons: Array[Node] = node.find_children("*", "BaseButton", true, false)
	for bn in buttons:
		var btn: BaseButton = bn as BaseButton
		if not btn.is_visible_in_tree():
			continue
		var txt: String = (btn as Button).text.strip_edges() if btn is Button else ""
		if not (CLOSE_TEXTS.has(txt) or btn.tooltip_text.to_lower().begins_with("close")):
			continue
		var br: Rect2 = btn.get_global_rect()
		var cx: float = (br.get_center().x - grect.position.x) / maxf(1.0, grect.size.x)
		var cy: float = (br.get_center().y - grect.position.y) / maxf(1.0, grect.size.y)
		var zone: String = ("top" if cy < 0.2 else ("bottom" if cy > 0.8 else "mid")) + "-" \
			+ ("left" if cx < 0.34 else ("right" if cx > 0.66 else "center"))
		closes.append("%s@%s(%dx%d)" % [txt if txt != "" else "tooltip:" + btn.tooltip_text,
			zone, roundi(br.size.x), roundi(br.size.y)])
	d["close"] = closes
	d["scroll"] = not node.find_children("*", "ScrollContainer", true, false).is_empty()
	var fo: Control = get_viewport().gui_get_focus_owner()
	d["focus_in"] = fo != null and (fo == node or node.is_ancestor_of(fo))
	var focusable: int = 0
	for bn in buttons:
		if (bn as Control).focus_mode != Control.FOCUS_NONE and (bn as Control).is_visible_in_tree():
			focusable += 1
	d["focusable_buttons"] = focusable
	# HOLISTIC #008 — navigable + primary action visible.
	var primary: Dictionary = _primary_action(node, grect, vp_size_or_default())
	d["navigable"] = focusable > 0 or bool(d.get("focus_in", false)) or primary.get("visible", false)
	d["primary_action"] = primary
	return d


func vp_size_or_default() -> Vector2:
	return _vp_size()


func _primary_action(node: Control, grect: Rect2, vp: Vector2) -> Dictionary:
	# Prefer an obvious non-close action button inside the opened group.
	var buttons: Array[Node] = node.find_children("*", "BaseButton", true, false)
	var best: BaseButton = null
	var best_score: float = -1.0
	for bn in buttons:
		var btn: BaseButton = bn as BaseButton
		if not btn.is_visible_in_tree():
			continue
		var txt: String = (btn as Button).text.strip_edges() if btn is Button else ""
		if CLOSE_TEXTS.has(txt):
			continue
		var br: Rect2 = btn.get_global_rect()
		if br.size.x < 4.0 or br.size.y < 4.0:
			continue
		var onscreen: bool = br.intersects(Rect2(Vector2.ZERO, vp))
		var score: float = br.get_area()
		if txt != "":
			score += 200.0
		if btn.focus_mode != Control.FOCUS_NONE:
			score += 80.0
		if onscreen:
			score += 120.0
		if score > best_score:
			best_score = score
			best = btn
	if best == null:
		return {"visible": grect.intersects(Rect2(Vector2.ZERO, vp)), "label": "", "onscreen": grect.intersects(Rect2(Vector2.ZERO, vp))}
	var r: Rect2 = best.get_global_rect()
	var label: String = ""
	if best is Button:
		label = (best as Button).text.strip_edges()
	else:
		label = String(best.name)
	return {
		"visible": true,
		"label": label,
		"onscreen": r.intersects(Rect2(Vector2.ZERO, vp)),
		"rect": _rect_arr(r),
		"focusable": best.focus_mode != Control.FOCUS_NONE,
	}

static func _first_of(n: Node, cls: String, depth: int) -> Node:
	if n.is_class(cls):
		return n
	if depth <= 0:
		return null
	for ch in n.get_children():
		var f: Node = _first_of(ch, cls, depth - 1)
		if f != null:
			return f
	return null


# ---- run ---------------------------------------------------------------------

func _run() -> void:
	var ready_info: Dictionary = await Readiness.await_world(get_tree(), _main, READY_TIMEOUT_S)
	if not bool(ready_info.get("ok", false)):
		push_error("[ui_capture] %s" % String(ready_info.get("reason", "not ready")))
		get_tree().quit(1)
		return
	print("[ui_capture] world ready stage=%s waited=%.2fs; cosmetic settle=%d/%.1fs" % [
		String(ready_info.get("stage", "")), float(ready_info.get("waited_s", 0.0)), _settle, _settle_s])
	var t0: int = Time.get_ticks_msec()
	var k: int = 0
	while k < _settle or Time.get_ticks_msec() - t0 < int(_settle_s * 1000.0):
		await get_tree().process_frame
		k += 1
	for p in PASSES:
		var pid: String = String(p["id"])
		if not _only_passes.is_empty() and not _only_passes.has(pid):
			continue
		await _apply_pass(p)
		await _run_pass(pid)
	_finish()


func _apply_pass(p: Dictionary) -> void:
	var win: Window = get_window()
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
	win.size = p["window"]
	var logical: Vector2i = p["logical"]
	if logical == Vector2i.ZERO or not _narrow_logical:
		win.content_scale_size = _default_content_scale
	else:
		win.content_scale_size = logical
	# HOLISTIC #008 content modifiers on the pass.
	if _cfg != null:
		_cfg.set("ui_font_scale", float(p.get("ui_font_scale", 1.0)))
		var loc: String = String(p.get("locale", "en"))
		_cfg.set("locale", loc)
		var i18n: Node = get_node_or_null("/root/Localization")
		if i18n != null and i18n.has_method("set_locale"):
			i18n.call("set_locale", loc)
	await _wait(RESIZE_SETTLE)
	_call("_apply_panel_layout")
	# Controller pass: smoke the gamepad menu once so focus paths exist, then
	# reset so each state starts clean (controller_path / gamepad_menu reopen).
	if bool(p.get("controller_only", false)):
		_call("_open_gamepad_menu")
		await _wait(STATE_SETTLE)
		await _reset()
	await _wait(STATE_SETTLE)

func _run_pass(pid: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%s" % [_out, pid]))
	var vp: Vector2 = _vp_size()
	_pass_lines.clear()
	_log("PASS %s window=%s viewport=%dx%d fps=%d rail_dock=%s hud_layout=%s" % [pid,
		str(get_window().size), roundi(vp.x), roundi(vp.y), roundi(Engine.get_frames_per_second()),
		str(_main.get("_rail_dock")), str(_main.get("_hud_layout"))])
	var pass_rec: Dictionary = {"id": pid, "viewport": [roundi(vp.x), roundi(vp.y)], "states": []}
	var base_groups: Dictionary = {}
	var base_overlaps: Dictionary = {}
	var thumbs: Array[Image] = []
	for i in STATES.size():
		var st: Dictionary = STATES[i]
		var sid: String = String(st["id"])
		if i > 0 and not _only_states.is_empty() and not _only_states.has(sid):
			continue
		await _reset()
		_caption_label.text = "%s  %02d  %s" % [pid, i, sid]
		for step in st["steps"]:
			await _do_step(step as Array)
		await _wait(STATE_SETTLE)
		vp = _vp_size()
		var els: Array[Dictionary] = _collect()
		var groups: Dictionary = _group_rects(els)
		var overlaps: Dictionary = _overlaps(els)
		var offs: Array[Dictionary] = _offscreen(groups, vp)
		if sid == "baseline":
			base_groups = groups
			base_overlaps = overlaps
		var opened: Array[String] = []
		for g in groups:
			if not base_groups.has(g):
				opened.append(String(g))
		# Shoot before the Escape test disturbs anything.
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var cap: Image = _caption_vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		cap.convert(Image.FORMAT_RGBA8)
		var fname: String = "%s/%s/%02d_%s.png" % [_out, pid, i, sid.replace("+", "_")]
		img.save_png(fname)
		var th: Image = img.duplicate() as Image
		th.resize(THUMB_W, maxi(1, int(float(img.get_height()) * float(THUMB_W) / float(img.get_width()))),
			Image.INTERPOLATE_BILINEAR)
		var cell: Image = Image.create_empty(THUMB_W, th.get_height() + CAPTION_H, false, Image.FORMAT_RGBA8)
		cell.blit_rect(cap, Rect2i(0, 0, THUMB_W, CAPTION_H), Vector2i.ZERO)
		cell.blit_rect(th, Rect2i(0, 0, THUMB_W, th.get_height()), Vector2i(0, CAPTION_H))
		thumbs.append(cell)
		var panels: Array = []
		for g in opened:
			panels.append(_panel_details(g, groups[g]))
		var esc: Dictionary = await _escape_test(opened)
		# Whatever Escape could not close, toggle shut the way it was opened.
		if not (esc["left"] as Array).is_empty():
			for step in st["steps"]:
				var m: String = String((step as Array)[0])
				if m.begins_with("_toggle_"):
					_call(m)
			await _wait(RESET_SETTLE)
		# ---- record + print ----
		_log("STATE pass=%s state=%s groups=%d opened=%s esc_presses=%d esc_left=%s" % [pid, sid,
			groups.size(), ",".join(opened), int(esc["presses"]), ",".join(esc["left"] as Array)])
		for pd in panels:
			var d: Dictionary = pd
			_log("PANEL pass=%s state=%s group=%s rect=%s z=%s script=%s corner=%s margins=%s close=%s scroll=%s focus_in=%s focusable=%s navigable=%s primary=%s primary_onscreen=%s" % [
				pid, sid, d["group"], str(d["rect"]), str(d.get("z", "")), str(d.get("script", "")),
				str(d.get("corner", "")), str(d.get("margins", "")), str(d.get("close", [])),
				str(d.get("scroll", "")), str(d.get("focus_in", "")), str(d.get("focusable_buttons", "")),
				str(d.get("navigable", "")),
				str((d.get("primary_action", {}) as Dictionary).get("label", "")),
				str((d.get("primary_action", {}) as Dictionary).get("onscreen", ""))])
		var ov_list: Array = []
		for key in overlaps:
			var o: Dictionary = overlaps[key]
			var is_new: bool = sid == "baseline" or not base_overlaps.has(key)
			ov_list.append({"kind": o["kind"], "a": o["a"], "b": o["b"], "n": o["n"],
				"rect": _rect_arr(o["rect"]), "example": o["example"], "new": is_new})
			if is_new:
				_log("OVERLAP pass=%s state=%s kind=%s a=%s b=%s n=%d rect=%s eg=%s" % [pid, sid,
					o["kind"], o["a"], o["b"], int(o["n"]), _rect_str(o["rect"]), o["example"]])
		var off_list: Array = []
		for od in offs:
			var is_new_off: bool = sid == "baseline" or not base_groups.has(od["group"]) \
				or (base_groups[od["group"]] as Rect2) != (od["rect"] as Rect2)
			off_list.append({"group": od["group"], "rect": _rect_arr(od["rect"]), "out_ltrb": od["out"]})
			if is_new_off:
				_log("OFFSCREEN pass=%s state=%s group=%s rect=%s out_ltrb=%s" % [pid, sid,
					od["group"], _rect_str(od["rect"]), str(od["out"])])
		var el_list: Array = []
		for e in els:
			el_list.append({"path": e["path"], "group": e["group"], "cls": e["cls"], "z": e["z"],
				"rect": _rect_arr(e["rect"])})
		var grp_list: Dictionary = {}
		for g in groups:
			grp_list[g] = _rect_arr(groups[g])
		(pass_rec["states"] as Array).append({"id": sid, "shot": fname, "opened": opened,
			"panels": panels, "overlaps": ov_list, "offscreen": off_list, "groups": grp_list,
			"elements": el_list, "escape": esc})
	await _reset()
	_write_sheets(pid, thumbs)
	(_report["passes"] as Array).append(pass_rec)
	var f := FileAccess.open("%s/report_%s.json" % [_out, pid], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(pass_rec, "  "))
		f.close()
	var t := FileAccess.open("%s/report_%s.txt" % [_out, pid], FileAccess.WRITE)
	if t != null:
		t.store_string("\n".join(_pass_lines) + "\n")
		t.close()


func _escape_test(opened: Array[String]) -> Dictionary:
	if opened.is_empty():
		return {"presses": 0, "left": []}
	var left: Array[String] = opened.duplicate()
	var presses: int = 0
	var closed_by_first: int = 0
	while presses < 4 and not left.is_empty():
		await _press_escape()
		presses += 1
		await _wait(ESC_SETTLE)
		var now: Dictionary = _group_rects(_collect())
		var still: Array[String] = []
		for g in left:
			if now.has(g):
				still.append(g)
		if presses == 1:
			closed_by_first = left.size() - still.size()
		left = still
	return {"presses": presses, "closed_by_first": closed_by_first, "left": left}


func _write_sheets(pid: String, thumbs: Array[Image]) -> void:
	if thumbs.is_empty():
		return
	var per: int = SHEET_COLS * SHEET_ROWS
	var cell_h: int = thumbs[0].get_height()
	var pad: int = 4
	var sheets: int = ceili(float(thumbs.size()) / float(per))
	for k in sheets:
		var count: int = mini(per, thumbs.size() - k * per)
		var rows: int = ceili(float(count) / float(SHEET_COLS))
		var sheet: Image = Image.create_empty(SHEET_COLS * (THUMB_W + pad) + pad,
			rows * (cell_h + pad) + pad, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.03, 0.03, 0.05))
		for n in count:
			var cell: Image = thumbs[k * per + n]
			var col: int = n % SHEET_COLS
			var row: int = floori(float(n) / float(SHEET_COLS))
			sheet.blit_rect(cell, Rect2i(0, 0, cell.get_width(), cell.get_height()),
				Vector2i(pad + col * (THUMB_W + pad), pad + row * (cell_h + pad)))
		var path: String = "%s/sheet_%s_%d.png" % [_out, pid, k]
		sheet.save_png(path)
		_log("SHEET %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	_log("DONE passes=%d out=%s" % [(_report["passes"] as Array).size(),
		ProjectSettings.globalize_path(_out)])
	get_tree().quit(0)
