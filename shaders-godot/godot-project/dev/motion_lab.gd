# Motion lab (CREATURE_MOTION_700 #94 #95 #113 #114 #218 #219, stills for #105).
#
#   scripts/dev_run.sh --path shaders-godot/godot-project res://dev/motion_lab.tscn
#
# One creature per species (every SPECIES_LIBRARY fish, caridean shrimp, crab,
# lobster, mantis shrimp and a snail) on a neutral grey stage with a 0.25 u
# reference grid, seen through three orthographic views of the selected one
# (side, top, front; body frame by default so the flank stays in profile).
#
#   time      0.1x / 0.25x / 0.5x / 1x / 2x, pause, single-frame step (1/60 s)
#   scrub     while paused, drag back through the last ~10 s of poses
#   actions   dart, startle, gulp, display (livebearers), court, die; shrimp
#             flip; snail eye retract and clamp - through the same fields the
#             game uses (burst_remaining, _startle_remaining, _lb_display_t,
#             _courtship_flare, start_dying, _escape_remaining, ...)
#   poses     (#218) lock a named PoseLibrary pose and edit channel sliders;
#             Save pose writes a species override into poses.json (with a
#             user:// / out-dir backup)
#   overlay   MotionDebugOverlay on the selected creature: onion skins,
#             curvature-coloured head path, speed graph, tail-tip trace
#   tuning    MotionSpring.TISSUE presets as sliders with a live step
#             response; "Save tuning" writes JSON beside the run output and
#             prints the GDScript line to paste (TISSUE is a const)
#   reload    "Reload motion data" calls FishMotionProfiles.reload_data() and
#             MotionPoseLibrary.reload_data() when those scripts exist
#
# Keys: Space pause, . or Right step a frame, 1-5 time scale, [ ] creature.
#
# Unattended (for checks): MOTION_LAB_SELECT=<kind key, e.g. guppy or
# shrimp:crab>, MOTION_LAB_TIME_SCALE=0.25, MOTION_LAB_ACTIONS="1.5:dart,3:startle"
# (lab seconds), MOTION_LAB_QUIT_AFTER=<real seconds> saves a window
# screenshot to MOTION_LAB_SCREENSHOT (default <out>/motion_lab/lab.png) and
# quits.
#
# Stills mode (#105): MOTION_LAB_STILLS=<dir> renders side|top|front strips
# of MOTION_LAB_STILL_SPECIES (default guppy,betta,corydoras,shrimp:crab) at
# MOTION_LAB_STILL_PHASES (fractions of a beat, default 0,0.25,0.5,0.75) and
# quits. Needs a real renderer (not --headless).
#
# Pose contact sheet (#219): MOTION_LAB_POSE_SHEET=<dir> tiles every fish
# species × every required pose (side view) into pose_contact_sheet.png.
# MOTION_LAB_POSE_SHEET_SPECIES / _POSES optional CSV filters. Needs a real
# renderer (not --headless).
#
# Save safety: no World, no SimDriver, no TankSaves. TankConfig.capture_mode
# is set anyway. Run it through dev_run.sh like every other dev scene.
extends Control

const StageScript := preload("res://dev/motion_lab_stage.gd")
const PROFILES_PATH: String = "res://scripts/fish_motion_profiles.gd"
const POSES_PATH: String = "res://scripts/motion_pose_library.gd"
const SCRUB_CAP: int = 600
const STEP_DT: float = 1.0 / 60.0
const TIME_SCALES: Array = [0.1, 0.25, 0.5, 1.0, 2.0]
const VIEWS: PackedStringArray = ["side", "top", "front"]

var _stage: StageScript = null
var _kinds: Array = []
var _creatures: Array = []
var _sel: int = 0
var _world: World3D = null
var _views: Array = []          # [{vp: SubViewport, cam: Camera3D, view: String}]
var _overlay: MotionDebugOverlay = null
var _time_scale: float = 1.0
var _paused: bool = false
var _step_requests: int = 0
var _body_frame: bool = true
var _follow: bool = true
var _animate_all: bool = false
var _scrub: Array = []
var _scrub_index: int = -1
var _tuning: Dictionary = {}
var _tissue: String = "fin"
var _out_dir: String = ""
var _auto_actions: Array = []    # [[lab seconds, action]]
var _quit_after: float = -1.0
var _real_t: float = 0.0

var _ui_species: OptionButton = null
var _ui_path: OptionButton = null
var _ui_pace: HSlider = null
var _ui_scrub: HSlider = null
var _ui_pause: Button = null
var _ui_scale_label: Label = null
var _ui_actions: HFlowContainer = null
var _ui_info: Label = null
var _ui_status: Label = null
var _ui_bouts: CheckBox = null
var _ui_tissue: OptionButton = null
var _ui_spring: Array = []      # [HSlider f, HSlider zeta, HSlider r]
var _graphs: Control = null
var _ui_pose: OptionButton = null
var _ui_pose_sliders: Dictionary = {}  # channel -> HSlider
var _ui_pose_lock: CheckBox = null
var _pose_edit: Dictionary = {}
var _pose_name: String = "cruise"


func _ready() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.set("capture_mode", true)
	seed(20261030)
	_out_dir = OS.get_environment("GODOT_DEV_OUT_ROOT")
	_out_dir = _out_dir.path_join("motion_lab") if not _out_dir.is_empty() else "user://motion_lab"
	for k in MotionSpring.TISSUE:
		_tuning[k] = (MotionSpring.TISSUE[k] as Array).duplicate()
	var sheet: String = OS.get_environment("MOTION_LAB_POSE_SHEET").strip_edges()
	if not sheet.is_empty():
		_run_pose_sheet.call_deferred(sheet)
		return
	var stills: String = OS.get_environment("MOTION_LAB_STILLS").strip_edges()
	if not stills.is_empty():
		_run_stills.call_deferred(stills)
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_spawn_all()
	_select(0)
	_read_unattended_env()


func _read_unattended_env() -> void:
	var want: String = OS.get_environment("MOTION_LAB_SELECT").strip_edges()
	if not want.is_empty():
		for i in _kinds.size():
			if String(_kinds[i]["key"]) == want:
				_select(i)
	var ts: String = OS.get_environment("MOTION_LAB_TIME_SCALE").strip_edges()
	if not ts.is_empty():
		_set_time_scale(ts.to_float())
	for part in OS.get_environment("MOTION_LAB_ACTIONS").split(",", false):
		var kv: PackedStringArray = part.split(":")
		if kv.size() == 2:
			_auto_actions.append([kv[0].to_float(), kv[1].strip_edges()])
	var q: String = OS.get_environment("MOTION_LAB_QUIT_AFTER").strip_edges()
	if not q.is_empty():
		_quit_after = q.to_float()


func _tick_unattended(delta: float) -> void:
	var c: Node3D = _selected()
	while not _auto_actions.is_empty() and _stage.lab_time >= float(_auto_actions[0][0]):
		var act: String = String(_auto_actions[0][1])
		_auto_actions.pop_front()
		if c != null and _stage.trigger(c, act):
			_set_status("auto action %s at %.2f s" % [act, _stage.lab_time])
	if _quit_after < 0.0:
		return
	_real_t += delta
	if _real_t < _quit_after:
		return
	_quit_after = -1.0
	var shot: String = OS.get_environment("MOTION_LAB_SCREENSHOT").strip_edges()
	if shot.is_empty():
		shot = _out_dir.path_join("lab.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot.get_base_dir()))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(shot)
	_set_status("screenshot " + ProjectSettings.globalize_path(shot))
	get_tree().quit(0)


# ---- Views -----------------------------------------------------------------

func _make_world_views(parent_for: Callable, vp_size: Vector2i) -> void:
	_world = World3D.new()
	_views.clear()
	for v in VIEWS:
		var vp := SubViewport.new()
		vp.world_3d = _world
		vp.size = vp_size
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		parent_for.call(v, vp)
		var cam := Camera3D.new()
		cam.current = true
		vp.add_child(cam)
		_views.append({"vp": vp, "cam": cam, "view": v})
	_stage = StageScript.new()
	_stage.name = "Stage"
	(_views[0]["vp"] as SubViewport).add_child(_stage)


func _update_cameras() -> void:
	var c: Node3D = _selected()
	if c == null:
		return
	var anchor: Vector3 = c.get_meta("lab_anchor", c.global_position)
	var focus: Vector3 = c.global_position if _follow else anchor
	var ortho: float = StageScript.view_size(c)
	for v in _views:
		StageScript.place_camera(v["cam"], c, String(v["view"]), _body_frame, ortho, focus)


# ---- Creatures -------------------------------------------------------------

func _spawn_all() -> void:
	_kinds = _stage.kinds()
	_creatures.clear()
	var n: int = _kinds.size()
	for i in n:
		_creatures.append(_spawn_index(i))
		_ui_species.add_item(String(_kinds[i]["label"]), i)


func _anchor_for(i: int) -> Vector3:
	var x: float = (float(i) - float(_kinds.size() - 1) * 0.5) * StageScript.SPACING
	return Vector3(x, StageScript.FISH_Y, 0.0)


func _spawn_index(i: int) -> Node3D:
	var c: Node3D = _stage.spawn(_kinds[i], _anchor_for(i))
	if c != null and _ui_path != null:
		var st: Dictionary = _stage.drive_state(c)
		st["path"] = StageScript.PATHS[_ui_path.selected]
		st["pace"] = _ui_pace.value
		st["natural_bouts"] = _ui_bouts.button_pressed
	return c


func _selected() -> Node3D:
	if _sel < 0 or _sel >= _creatures.size():
		return null
	var c: Variant = _creatures[_sel]
	return c as Node3D if c is Node3D and is_instance_valid(c) else null


func _select(i: int) -> void:
	if _creatures.is_empty():
		return
	_sel = clampi(i, 0, _creatures.size() - 1)
	if _selected() == null:
		_creatures[_sel] = _spawn_index(_sel)
	if _ui_species.selected != _sel:
		_ui_species.select(_sel)
	_scrub.clear()
	_scrub_index = -1
	if _overlay == null:
		_overlay = MotionDebugOverlay.new()
		_overlay.name = "MotionOverlay"
		_overlay.show_hud = false
		_overlay.draw_depth_bands = false
		_overlay.external_clock = true
		_stage.add_child(_overlay)
		_overlay.sim = _stage.get("sim")
		_overlay.set_enabled(true)
	_overlay.subject = _selected()
	_overlay.clear_history()
	_rebuild_actions()
	_rebuild_pose_list()
	if _ui_pose_lock != null and _ui_pose_lock.button_pressed:
		_pick_pose(_pose_name)
	_set_status("selected %s" % String(_kinds[_sel]["label"]))


func _respawn_selected() -> void:
	var c: Node3D = _selected()
	if c != null:
		_stage.forget(c)
		MotionDebugOverlay.forget_tips(c)
		c.queue_free()
	_creatures[_sel] = _spawn_index(_sel)
	_select(_sel)


# ---- Frame loop ------------------------------------------------------------

func _process(delta: float) -> void:
	if _stage == null or _views.is_empty() or _ui_species == null:
		return
	var sim_dt: float = 0.0
	if _paused:
		if _step_requests > 0:
			_step_requests -= 1
			sim_dt = STEP_DT
	else:
		sim_dt = minf(delta, 0.05) * _time_scale
	if sim_dt > 0.0:
		if _scrub_index >= 0:
			_apply_snapshot(_scrub.back())
			_scrub_index = -1
		for i in _creatures.size():
			if i != _sel and not _animate_all:
				continue
			var c: Variant = _creatures[i]
			if not (c is Node3D) or not is_instance_valid(c):
				continue
			if not _stage.step(c, sim_dt):
				_creatures[i] = null
				if i == _sel:
					_set_status("died - press Respawn")
		_stage.lab_time += sim_dt
		_overlay.advance(sim_dt)
		_record_snapshot()
	_update_cameras()
	_update_info()
	_graphs.queue_redraw()
	_tick_unattended(delta)


func _record_snapshot() -> void:
	var c: Node3D = _selected()
	if c == null:
		return
	var nodes: Dictionary = StageScript.pivot_nodes(c)
	var snap: Dictionary = {"node": c, "xf": c.global_transform, "p": {}}
	for k in nodes:
		var n: Node3D = nodes[k]
		(snap["p"] as Dictionary)[n] = n.transform
	_scrub.append(snap)
	if _scrub.size() > SCRUB_CAP:
		_scrub.pop_front()
	_ui_scrub.max_value = maxf(0.0, float(_scrub.size() - 1))
	_ui_scrub.set_value_no_signal(_ui_scrub.max_value)


func _apply_snapshot(snap: Dictionary) -> void:
	var c: Variant = snap.get("node")
	if not (c is Node3D) or not is_instance_valid(c):
		return
	(c as Node3D).global_transform = snap["xf"]
	var pv: Dictionary = snap["p"]
	for n in pv:
		if is_instance_valid(n):
			(n as Node3D).transform = pv[n]


func _on_scrub(v: float) -> void:
	if not _paused or _scrub.is_empty():
		return
	_scrub_index = clampi(int(v), 0, _scrub.size() - 1)
	_apply_snapshot(_scrub[_scrub_index])
	var back_s: float = float(_scrub.size() - 1 - _scrub_index) * STEP_DT
	_set_status("scrub -%d frames (~%.2f s at 60 fps)" % [_scrub.size() - 1 - _scrub_index, back_s])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_set_paused(not _paused)
		KEY_PERIOD, KEY_RIGHT:
			_step_frame()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_set_time_scale(float(TIME_SCALES[int(k.keycode - KEY_1)]))
		KEY_BRACKETLEFT:
			_select(_sel - 1)
		KEY_BRACKETRIGHT:
			_select(_sel + 1)
		_:
			return
	get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	_paused = p
	_ui_pause.button_pressed = p
	_ui_scrub.editable = p
	if not p and _scrub_index >= 0:
		_apply_snapshot(_scrub.back())
		_scrub_index = -1


func _step_frame() -> void:
	if not _paused:
		_set_paused(true)
	_step_requests += 1


func _set_time_scale(s: float) -> void:
	_time_scale = s
	_ui_scale_label.text = "time %.2fx" % s


# ---- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	var add_view := func(v: String, vp: SubViewport) -> void:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var lbl := Label.new()
		lbl.text = "%s (orthographic)" % v
		cell.add_child(lbl)
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.add_child(svc)
		svc.add_child(vp)
	_make_world_views(add_view, Vector2i(480, 320))
	_graphs = Control.new()
	_graphs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graphs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graphs.draw.connect(_draw_graphs)
	grid.add_child(_graphs)

	_add_label(col, "MOTION LAB", 16)
	_ui_species = OptionButton.new()
	_ui_species.item_selected.connect(func(i: int) -> void: _select(i))
	col.add_child(_ui_species)
	var row := HBoxContainer.new()
	col.add_child(row)
	_ui_path = OptionButton.new()
	for p in StageScript.PATHS:
		_ui_path.add_item(p)
	_ui_path.item_selected.connect(func(_i: int) -> void: _apply_drive_settings())
	row.add_child(_ui_path)
	_ui_bouts = CheckBox.new()
	_ui_bouts.text = "natural bouts"
	_ui_bouts.button_pressed = true
	_ui_bouts.toggled.connect(func(_on: bool) -> void: _apply_drive_settings())
	row.add_child(_ui_bouts)
	_ui_pace = _add_slider(col, "pace (x max speed)", 0.05, 1.5, 0.35, 0.05,
		func(_v: float) -> void: _apply_drive_settings())

	_add_label(col, "Time", 13)
	var trow := HFlowContainer.new()
	col.add_child(trow)
	for s in TIME_SCALES:
		var b := Button.new()
		b.text = "%sx" % str(s)
		var sv: float = float(s)
		b.pressed.connect(func() -> void: _set_time_scale(sv))
		trow.add_child(b)
	var prow := HBoxContainer.new()
	col.add_child(prow)
	_ui_pause = Button.new()
	_ui_pause.text = "Pause"
	_ui_pause.toggle_mode = true
	_ui_pause.toggled.connect(func(on: bool) -> void: _set_paused(on))
	prow.add_child(_ui_pause)
	var step_b := Button.new()
	step_b.text = "Step frame"
	step_b.pressed.connect(_step_frame)
	prow.add_child(step_b)
	_ui_scale_label = Label.new()
	_ui_scale_label.text = "time 1.00x"
	prow.add_child(_ui_scale_label)
	_ui_scrub = _add_slider(col, "scrub (paused)", 0.0, 1.0, 1.0, 1.0, _on_scrub)
	_ui_scrub.editable = false

	_add_label(col, "Actions", 13)
	_ui_actions = HFlowContainer.new()
	col.add_child(_ui_actions)

	_add_label(col, "View", 13)
	var vrow := HFlowContainer.new()
	col.add_child(vrow)
	_add_check(vrow, "body frame", true, func(on: bool) -> void: _body_frame = on)
	_add_check(vrow, "follow", true, func(on: bool) -> void: _follow = on)
	_add_check(vrow, "animate all", false, func(on: bool) -> void: _animate_all = on)
	_add_check(vrow, "overlay", true, func(on: bool) -> void:
		_overlay.set_enabled(on)
		_overlay.subject = _selected())

	_add_label(col, "Tuning: MotionSpring.TISSUE", 13)
	_ui_tissue = OptionButton.new()
	for k in MotionSpring.TISSUE:
		_ui_tissue.add_item(String(k))
	_ui_tissue.item_selected.connect(func(i: int) -> void: _pick_tissue(_ui_tissue.get_item_text(i)))
	col.add_child(_ui_tissue)
	var names: Array = ["f (Hz)", "zeta", "r"]
	var ranges: Array = [[0.2, 12.0, 0.05], [0.0, 2.0, 0.01], [-2.0, 3.0, 0.05]]
	for i in 3:
		var idx: int = i
		var rg: Array = ranges[i]
		var sl: HSlider = _add_slider(col, String(names[i]), float(rg[0]), float(rg[1]), 0.0, float(rg[2]),
			func(v: float) -> void: _on_spring(idx, v))
		_ui_spring.append(sl)
	var srow := HBoxContainer.new()
	col.add_child(srow)
	var save_b := Button.new()
	save_b.text = "Save tuning"
	save_b.pressed.connect(_save_tuning)
	srow.add_child(save_b)
	var reset_b := Button.new()
	reset_b.text = "Reset preset"
	reset_b.pressed.connect(func() -> void:
		_tuning[_tissue] = (MotionSpring.TISSUE[_tissue] as Array).duplicate()
		_pick_tissue(_tissue))
	srow.add_child(reset_b)

	_add_label(col, "Pose editor (#218)", 13)
	_ui_pose_lock = CheckBox.new()
	_ui_pose_lock.text = "lock pose preview"
	_ui_pose_lock.toggled.connect(_on_pose_lock)
	col.add_child(_ui_pose_lock)
	_ui_pose = OptionButton.new()
	_ui_pose.item_selected.connect(func(i: int) -> void: _pick_pose(_ui_pose.get_item_text(i)))
	col.add_child(_ui_pose)
	_rebuild_pose_list()
	for ch in MotionPoseLibrary.CHANNELS:
		var rg: Array = MotionPoseLibrary.CHANNEL_RANGE.get(ch, [-1.0, 1.0, 0.02])
		var channel: String = ch
		var sl: HSlider = _add_slider(col, ch, float(rg[0]), float(rg[1]), 0.0, float(rg[2]),
			func(v: float) -> void: _on_pose_channel(channel, v))
		_ui_pose_sliders[ch] = sl
	var porow := HBoxContainer.new()
	col.add_child(porow)
	var save_pose_b := Button.new()
	save_pose_b.text = "Save pose"
	save_pose_b.pressed.connect(_save_pose)
	porow.add_child(save_pose_b)
	var clear_pose_b := Button.new()
	clear_pose_b.text = "Clear lock"
	clear_pose_b.pressed.connect(func() -> void:
		_ui_pose_lock.button_pressed = false
		_on_pose_lock(false))
	porow.add_child(clear_pose_b)
	var sheet_b := Button.new()
	sheet_b.text = "Write contact sheet"
	sheet_b.pressed.connect(func() -> void:
		_write_pose_sheet_live.call_deferred())
	porow.add_child(sheet_b)

	_add_label(col, "Data", 13)
	var drow := HBoxContainer.new()
	col.add_child(drow)
	var reload_b := Button.new()
	reload_b.text = "Reload motion data"
	reload_b.pressed.connect(_reload_motion_data)
	drow.add_child(reload_b)
	var respawn_b := Button.new()
	respawn_b.text = "Respawn"
	respawn_b.pressed.connect(_respawn_selected)
	drow.add_child(respawn_b)
	_ui_status = Label.new()
	_ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_status.custom_minimum_size = Vector2(280, 0)
	col.add_child(_ui_status)
	_ui_info = Label.new()
	_ui_info.add_theme_font_size_override("font_size", 11)
	_ui_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_info.custom_minimum_size = Vector2(280, 0)
	col.add_child(_ui_info)
	_add_label(col, "Space pause  . step  1-5 speed  [ ] creature", 11)
	_pick_tissue("fin")


func _add_label(parent: Node, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _add_check(parent: Node, text: String, on: bool, cb: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(cb)
	parent.add_child(c)


func _add_slider(parent: Node, text: String, lo: float, hi: float, v: float, step_v: float,
		cb: Callable) -> HSlider:
	var l := _add_label(parent, text, 11)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step_v
	s.value = v
	s.custom_minimum_size = Vector2(260, 18)
	s.value_changed.connect(func(nv: float) -> void:
		l.text = "%s  %.2f" % [text, nv]
		cb.call(nv))
	l.text = "%s  %.2f" % [text, v]
	parent.add_child(s)
	return s


func _apply_drive_settings() -> void:
	for c in _creatures:
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var st: Dictionary = _stage.drive_state(c)
		if st.is_empty():
			continue
		st["path"] = StageScript.PATHS[_ui_path.selected]
		st["pace"] = _ui_pace.value
		st["natural_bouts"] = _ui_bouts.button_pressed


func _rebuild_actions() -> void:
	for ch in _ui_actions.get_children():
		ch.queue_free()
	var c: Node3D = _selected()
	if c == null:
		return
	for a in _stage.actions_for(c):
		var b := Button.new()
		b.text = a
		var act: String = a
		b.pressed.connect(func() -> void:
			var cc: Node3D = _selected()
			if cc != null and _stage.trigger(cc, act):
				_set_status("%s: %s" % [String(_kinds[_sel]["label"]), act]))
		_ui_actions.add_child(b)


func _set_status(t: String) -> void:
	if _ui_status != null:
		_ui_status.text = t
	print("[motion_lab] ", t)


func _update_info() -> void:
	var c: Node3D = _selected()
	if c == null:
		_ui_info.text = "(no creature)"
		return
	var lines := PackedStringArray()
	lines.append("speed %.3f  yaw %.2f" % [MotionDebugOverlay.creature_speed(c), MotionDebugOverlay.creature_yaw(c)])
	if c is Fish:
		var f: Fish = c
		lines.append("%s  %s  mode %d" % [f.species, f.locomotion_type, int(f.current_mode)])
		lines.append("bank %.3f  swim ph %.2f  motor ph %.2f" % [f._bank, fposmod(f._swim_phase, TAU), fposmod(f._motor_phase, TAU)])
		lines.append("burst %.2f  startle %.2f  tail act %.2f  bout %d" % [f.burst_remaining, f._startle_remaining, f._fin_tail_activity, f._bout_kind])
		var prof: Dictionary = _profile_for(f.locomotion_type)
		if not prof.is_empty():
			var parts := PackedStringArray()
			for k in prof:
				parts.append("%s %.2f" % [k, float(prof[k])])
			lines.append("profile: " + ", ".join(parts))
	elif c is Shrimp:
		var s: Shrimp = c
		lines.append("%s  escape %.2f  gait %.2f" % [s.body_shape, s._escape_remaining, s._gait_phase])
	else:
		lines.append("snail  paused %s  clamped %s  blend %.2f" % [str(c.get("_paused")), str(c.get("_clamped")), float(c.get("_blend_t"))])
	var nodes: Dictionary = StageScript.pivot_nodes(c)
	var rots := PackedStringArray()
	for k in nodes:
		if String(k).begins_with("leg_"):
			continue
		var r: Vector3 = (nodes[k] as Node3D).rotation
		rots.append("%s %.2f/%.2f/%.2f" % [k, r.x, r.y, r.z])
	lines.append("pivots (rx/ry/rz): " + "  ".join(rots))
	_ui_info.text = "\n".join(lines)


func _profile_for(loco: String) -> Dictionary:
	if not ResourceLoader.exists(PROFILES_PATH):
		return {}
	var s: Script = load(PROFILES_PATH)
	if s == null or not _has_static(s, "get_profile"):
		return {}
	var p: Variant = s.call("get_profile", loco)
	return p if p is Dictionary else {}


static func _has_static(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false


# Hot reload (#113): FishMotionProfiles / MotionPoseLibrary re-read their
# JSON. Guarded so the lab runs before either script lands.
func _reload_motion_data() -> void:
	var parts := PackedStringArray()
	for path in [PROFILES_PATH, POSES_PATH]:
		if not ResourceLoader.exists(path):
			parts.append("%s missing" % String(path).get_file())
			continue
		var s: Script = load(path)
		if s == null or not _has_static(s, "reload_data"):
			parts.append("%s has no reload_data()" % String(path).get_file())
			continue
		parts.append("%s.reload_data() -> %s" % [String(path).get_file(), str(s.call("reload_data"))])
	_set_status("; ".join(parts))


# ---- Tuning (#114) ---------------------------------------------------------

func _pick_tissue(t: String) -> void:
	_tissue = t
	var p: Array = _tuning.get(t, [2.0, 0.7, 0.0])
	for i in 3:
		(_ui_spring[i] as HSlider).value = float(p[i])


func _on_spring(i: int, v: float) -> void:
	if not _tuning.has(_tissue):
		return
	(_tuning[_tissue] as Array)[i] = v


func _save_tuning() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path: String = _out_dir.path_join("tissue_tuning.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("could not write " + path)
		return
	f.store_string(JSON.stringify(_tuning, "\t"))
	f.close()
	var p: Array = _tuning[_tissue]
	print("[motion_lab] paste into MotionSpring.TISSUE: \"%s\": [%.2f, %.2f, %.2f]," % [_tissue, p[0], p[1], p[2]])
	_set_status("saved " + ProjectSettings.globalize_path(path))


func _draw_graphs() -> void:
	var r := Rect2(Vector2.ZERO, _graphs.size)
	var top := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.62))
	if _overlay != null and _overlay.enabled:
		_overlay.draw_graphs(_graphs, top)
	var sr := Rect2(Vector2(0, top.end.y + 4.0), Vector2(r.size.x, r.size.y - top.size.y - 4.0))
	_draw_spring(sr)


# Step response of the tissue preset being tuned: input steps 0 -> 1 at
# 0.1 s; the curve shows overshoot (zeta), catch-up (f) and anticipation (r<0).
func _draw_spring(r: Rect2) -> void:
	var font: Font = ThemeDB.fallback_font
	_graphs.draw_rect(r, Color(0.04, 0.05, 0.07, 0.82))
	var p: Array = _tuning.get(_tissue, [2.0, 0.7, 0.0])
	var spring := MotionSpring.new(float(p[0]), float(p[1]), float(p[2]), 0.0)
	var dt: float = 1.0 / 120.0
	var span: float = 2.0
	var n: int = int(span / dt)
	var ys := PackedFloat32Array()
	var lo: float = -0.2
	var hi: float = 1.4
	for i in n:
		var x: float = 1.0 if float(i) * dt >= 0.1 else 0.0
		var y: float = spring.step(dt, x)
		ys.append(y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var inner := r.grow(-10.0)
	inner.position.y += 12.0
	inner.size.y -= 12.0
	var to_px := func(i: int, y: float) -> Vector2:
		return Vector2(inner.position.x + float(i) / float(n - 1) * inner.size.x,
			inner.end.y - (y - lo) / (hi - lo) * inner.size.y)
	var one: Vector2 = to_px.call(0, 1.0)
	var zero: Vector2 = to_px.call(0, 0.0)
	_graphs.draw_line(Vector2(inner.position.x, one.y), Vector2(inner.end.x, one.y), Color(1, 1, 1, 0.2))
	_graphs.draw_line(Vector2(inner.position.x, zero.y), Vector2(inner.end.x, zero.y), Color(1, 1, 1, 0.2))
	var pts := PackedVector2Array()
	for i in n:
		pts.append(to_px.call(i, ys[i]))
	_graphs.draw_polyline(pts, Color(0.5, 0.85, 1.0), 1.5)
	var peak: float = 0.0
	for y in ys:
		peak = maxf(peak, y)
	_graphs.draw_string(font, r.position + Vector2(8, 15),
		"spring '%s'  f %.2f Hz  zeta %.2f  r %.2f  step response 2 s  overshoot %.0f%%" % [
			_tissue, p[0], p[1], p[2], maxf(0.0, peak - 1.0) * 100.0],
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0, 11, Color(0.85, 0.9, 1.0))


# ---- Pose editor (#218) ----------------------------------------------------

func _rebuild_pose_list() -> void:
	if _ui_pose == null:
		return
	_ui_pose.clear()
	var species: String = _selected_fish_species()
	MotionPoseLibrary.reload_data()
	var poses: PackedStringArray = MotionPoseLibrary.list_poses(species if not species.is_empty() else "_default")
	var want: String = _pose_name
	var sel: int = 0
	for i in poses.size():
		_ui_pose.add_item(poses[i])
		if poses[i] == want:
			sel = i
	if poses.is_empty():
		_ui_pose.add_item("cruise")
	_ui_pose.select(sel)
	_pose_name = _ui_pose.get_item_text(_ui_pose.selected)
	_load_pose_sliders()


func _selected_fish_species() -> String:
	var c: Node3D = _selected()
	if c is Fish:
		return (c as Fish).species
	if _sel >= 0 and _sel < _kinds.size() and String(_kinds[_sel].get("type", "")) == "fish":
		return String(_kinds[_sel].get("key", ""))
	return ""


func _load_pose_sliders() -> void:
	var species: String = _selected_fish_species()
	if species.is_empty():
		species = "_default"
	_pose_edit = MotionPoseLibrary.get_pose(species, _pose_name)
	for ch in MotionPoseLibrary.CHANNELS:
		if not _ui_pose_sliders.has(ch):
			continue
		var sl: HSlider = _ui_pose_sliders[ch]
		sl.set_value_no_signal(float(_pose_edit.get(ch, 0.0)))


func _pick_pose(pose_name: String) -> void:
	_pose_name = pose_name
	_load_pose_sliders()
	if _ui_pose_lock != null and _ui_pose_lock.button_pressed:
		_apply_pose_preview()


func _on_pose_lock(on: bool) -> void:
	var c: Node3D = _selected()
	if not (c is Fish):
		_set_status("pose editor needs a fish")
		if _ui_pose_lock != null:
			_ui_pose_lock.set_pressed_no_signal(false)
		return
	if on:
		_apply_pose_preview()
		_set_status("pose lock %s / %s" % [(c as Fish).species, _pose_name])
	else:
		FishPoseRuntime.clear_force_pose(c as Fish)
		_set_status("pose lock cleared")


func _on_pose_channel(channel: String, v: float) -> void:
	_pose_edit[channel] = v
	if _ui_pose_lock != null and _ui_pose_lock.button_pressed:
		_apply_pose_preview()


func _apply_pose_preview() -> void:
	var c: Node3D = _selected()
	if not (c is Fish):
		return
	var f: Fish = c
	FishPoseRuntime.force_pose(f, _pose_name)
	FishPoseRuntime.set_edit_channels(f, _pose_edit)
	# One tiny substep so pivots refresh under the lock.
	f._motion_substep(1e-4, 1e-4)


func _save_pose() -> void:
	var species: String = _selected_fish_species()
	if species.is_empty():
		_set_status("select a fish before saving a pose")
		return
	MotionPoseLibrary.upsert_pose(species, _pose_name, _pose_edit)
	var backup: String = _out_dir.path_join("poses_edit.json")
	# Prefer the shipped library; always keep a backup under the run out-dir.
	var wrote: String = MotionPoseLibrary.save_data(PackedStringArray([
		MotionPoseLibrary.DATA_PATH, backup,
	]))
	if wrote.is_empty():
		_set_status("pose save failed (could not write poses.json or backup)")
		return
	_set_status("saved %s/%s → %s" % [species, _pose_name, ProjectSettings.globalize_path(wrote)])
	_apply_pose_preview()


# ---- Pose contact sheet (#219) ---------------------------------------------

func _pose_sheet_species_and_poses() -> Dictionary:
	var species_csv: String = OS.get_environment("MOTION_LAB_POSE_SHEET_SPECIES").strip_edges()
	var poses_csv: String = OS.get_environment("MOTION_LAB_POSE_SHEET_POSES").strip_edges()
	var species_list := PackedStringArray()
	if species_csv.is_empty():
		# Default: a readable review set; full library via MOTION_LAB_POSE_SHEET_SPECIES=all
		if OS.get_environment("MOTION_LAB_POSE_SHEET_SPECIES") == "all" and _stage != null:
			for k in _stage.kinds():
				if String(k.get("type", "")) == "fish":
					species_list.append(String(k.get("key", "")))
		else:
			species_list = PackedStringArray(["guppy", "betta", "corydoras", "angelfish", "pleco"])
	else:
		if species_csv == "all" and _stage != null:
			for k in _stage.kinds():
				if String(k.get("type", "")) == "fish":
					species_list.append(String(k.get("key", "")))
		else:
			for s in species_csv.split(",", false):
				species_list.append(s.strip_edges())
	var pose_list := PackedStringArray()
	if poses_csv.is_empty():
		pose_list = PackedStringArray([
			"cruise", "hover", "alert", "clamped", "display", "threat",
			"sleep", "gulp", "glide", "dead",
		])
	elif poses_csv == "all":
		pose_list = FishPoseRuntime.required_poses()
	else:
		for p in poses_csv.split(",", false):
			pose_list.append(p.strip_edges())
	return {"species": species_list, "poses": pose_list}


func _capture_pose_cells(species_list: PackedStringArray, pose_list: PackedStringArray) -> Dictionary:
	var cells: Array = []
	var labels := PackedStringArray()
	var side_vp: SubViewport = _views[0]["vp"] if not _views.is_empty() else null
	if side_vp == null or _stage == null:
		return {"cells": cells, "labels": labels}
	for sp in species_list:
		var kind: Dictionary = _stage.kind_by_key(sp)
		if kind.is_empty() or String(kind.get("type", "")) != "fish":
			push_warning("[motion_lab] pose sheet skip unknown fish " + sp)
			continue
		seed(20261030)
		var c: Node3D = _stage.spawn(kind, Vector3(0.0, StageScript.FISH_Y, 0.0))
		if c == null or not (c is Fish):
			continue
		var f: Fish = c
		var st: Dictionary = _stage.drive_state(c)
		st["path"] = "straight"
		st["natural_bouts"] = false
		st["pace"] = 0.15
		for _i in 45:
			_stage.step(c, STEP_DT)
		for pose_name in pose_list:
			FishPoseRuntime.force_pose(f, pose_name)
			f.speed = 0.02
			f.target_velocity = Vector3.ZERO
			f._motion_substep(1e-4, 1e-4)
			_update_stills_cameras(c)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var im: Image = side_vp.get_texture().get_image()
			im.convert(Image.FORMAT_RGBA8)
			cells.append(im)
			labels.append("%s/%s" % [sp, pose_name])
			FishPoseRuntime.clear_force_pose(f)
		_stage.forget(c)
		c.queue_free()
		await get_tree().process_frame
	return {"cells": cells, "labels": labels}


func _finish_pose_sheet(dir: String, cells: Array, labels: PackedStringArray, pose_list: PackedStringArray) -> String:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dir) if dir.begins_with("res://") or dir.begins_with("user://") else dir)
	var sheet: Image = MotionPoseLibrary.compose_contact_sheet(cells, maxi(pose_list.size(), 1), 2)
	var out_path: String = dir.path_join("pose_contact_sheet.png")
	sheet.save_png(out_path)
	var idx := FileAccess.open(dir.path_join("pose_contact_sheet.txt"), FileAccess.WRITE)
	if idx != null:
		idx.store_string("pose contact sheet (#219)\ncols=%d poses=%s\n" % [
			pose_list.size(), ",".join(pose_list)])
		idx.store_string("\n".join(labels) + "\n")
		idx.close()
	return out_path


func _write_pose_sheet_live() -> void:
	MotionPoseLibrary.reload_data()
	var cfg: Dictionary = _pose_sheet_species_and_poses()
	var species_list: PackedStringArray = cfg["species"]
	var pose_list: PackedStringArray = cfg["poses"]
	var captured: Dictionary = await _capture_pose_cells(species_list, pose_list)
	var dir: String = _out_dir.path_join("pose_sheet")
	var out_path: String = _finish_pose_sheet(
		dir, captured["cells"] as Array, captured["labels"] as PackedStringArray, pose_list)
	_set_status("pose sheet %d cells → %s" % [(captured["cells"] as Array).size(), out_path])


func _run_pose_sheet(dir: String) -> void:
	var holder := Node.new()
	add_child(holder)
	_make_world_views(func(_v: String, vp: SubViewport) -> void: holder.add_child(vp), Vector2i(160, 120))
	await get_tree().process_frame
	MotionPoseLibrary.reload_data()
	var cfg: Dictionary = _pose_sheet_species_and_poses()
	var species_list: PackedStringArray = cfg["species"]
	var pose_list: PackedStringArray = cfg["poses"]
	var captured: Dictionary = await _capture_pose_cells(species_list, pose_list)
	var out_path: String = _finish_pose_sheet(
		dir, captured["cells"] as Array, captured["labels"] as PackedStringArray, pose_list)
	print("[motion_lab] pose sheet %d cells -> %s" % [(captured["cells"] as Array).size(), out_path])
	get_tree().quit(0 if not (captured["cells"] as Array).is_empty() else 1)


# ---- Stills mode (#105) ----------------------------------------------------

func _run_stills(dir: String) -> void:
	var holder := Node.new()
	add_child(holder)
	_make_world_views(func(_v: String, vp: SubViewport) -> void: holder.add_child(vp), Vector2i(384, 256))
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") or dir.begins_with("user://") else dir)
	var species_csv: String = OS.get_environment("MOTION_LAB_STILL_SPECIES").strip_edges()
	if species_csv.is_empty():
		species_csv = "guppy,betta,corydoras,shrimp:crab"
	var phases_csv: String = OS.get_environment("MOTION_LAB_STILL_PHASES").strip_edges()
	if phases_csv.is_empty():
		phases_csv = "0,0.25,0.5,0.75"
	var written := PackedStringArray()
	var anchor := Vector3(0.0, StageScript.FISH_Y, 0.0)
	for key in species_csv.split(",", false):
		var kind: Dictionary = _stage.kind_by_key(key.strip_edges())
		if kind.is_empty():
			push_warning("[motion_lab] unknown still species " + key)
			continue
		seed(20261030)
		var c: Node3D = _stage.spawn(kind, anchor)
		if c == null:
			continue
		var st: Dictionary = _stage.drive_state(c)
		st["path"] = "straight"
		st["natural_bouts"] = false
		# Fixed-step warm-up to a steady cruise; no rendering in between.
		for _i in 90:
			_stage.step(c, STEP_DT)
		for ph in phases_csv.split(",", false):
			var frac: float = ph.to_float()
			_pose_at_phase(c, frac * TAU)
			_update_stills_cameras(c)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img: Image = _compose_views()
			var file: String = "%s_phase%03d.png" % [key.strip_edges().replace(":", "_"), int(round(frac * 100.0))]
			img.save_png(dir.path_join(file))
			written.append(file)
		_stage.forget(c)
		c.queue_free()
		await get_tree().process_frame
	var idx := FileAccess.open(dir.path_join("stills.txt"), FileAccess.WRITE)
	if idx != null:
		idx.store_string("motion lab stills (side | top | front, body frame)\n" + "\n".join(written) + "\n")
		idx.close()
	print("[motion_lab] wrote %d stills -> %s" % [written.size(), dir])
	get_tree().quit(0 if not written.is_empty() else 1)


func _pose_at_phase(c: Node3D, phase: float) -> void:
	if c is Fish:
		var f: Fish = c
		f._swim_phase = phase
		f._motor_phase = phase
		f._motion_substep(1e-4, 1e-4)
	elif c is Shrimp:
		var s: Shrimp = c
		s._swim_phase = phase
		s._gait_phase = phase
		s._process(1e-4)
	else:
		c.call("_process", 1e-4)


func _update_stills_cameras(c: Node3D) -> void:
	var ortho: float = StageScript.view_size(c)
	for v in _views:
		StageScript.place_camera(v["cam"], c, String(v["view"]), true, ortho, c.global_position)


func _compose_views() -> Image:
	var imgs: Array = []
	var w: int = 0
	var h: int = 0
	for v in _views:
		var im: Image = (v["vp"] as SubViewport).get_texture().get_image()
		im.convert(Image.FORMAT_RGBA8)
		imgs.append(im)
		w += im.get_width() + 2
		h = maxi(h, im.get_height())
	var out := Image.create(maxi(w - 2, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.1, 0.1))
	var x: int = 0
	for im in imgs:
		var i2: Image = im
		out.blit_rect(i2, Rect2i(Vector2i.ZERO, i2.get_size()), Vector2i(x, 0))
		x += i2.get_width() + 2
	return out
