extends Node

# Visual inspection harness. Renders the live World from several angles at
# a resolution high enough to judge shapes, so visual work can be checked
# by looking rather than by assertion.
#
# NB this builds a real World, which reads TankSaves. Always run it against
# a scratch slot with the real ones backed up.

@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display

var _frame: int = 0
var _shot: int = 0
var _settle: int = 220
var _out_prefix: String = "res://inspect_"
# lightdrag=fixture,ox,oz,ax,az : rebuild the fixture, shoot, then walk the
# light there through 40 drag steps (the real world API) and shoot again as
# *_dragged.png - a before/after of what touching the light does.
var _light_drag: PackedStringArray = []
var _light_dragged: bool = false

# name, position, look-at target, fov
const SHOTS: Array = [
	["wide",  Vector3(0.0, 7.0, 19.0),   Vector3(0.0, 5.0, 0.0), 52.0],
	["front", Vector3(2.0, 4.5, 12.0),   Vector3(0.0, 4.2, 0.0), 46.0],
	["macro", Vector3(-1.5, 3.4, 6.2),   Vector3(0.0, 3.2, 0.0), 40.0],
	["top",   Vector3(0.0, 15.0, 7.0),   Vector3(0.0, 3.0, 0.0), 55.0],
]


func _ready() -> void:
	display.texture = sub_viewport.get_texture()
	# Push the palette tints the way main.gd does. Without this the harness
	# renders a desaturated world - the registered defaults multiply
	# saturation and value by the global palette, so an unpushed palette is
	# grey - and every visual judgement made from it would be wrong.
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg != null:
		VoxelMat.apply_global_palette(cfg)
	var arg_settle: int = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("settle="):
			arg_settle = int(a.split("=")[1])
		# out=/abs/dir/prefix_ : write PNGs outside the repo (parallel agents
		# otherwise overwrite each other's res://inspect_*.png).
		if a.begins_with("out="):
			_out_prefix = a.substr(4)
		if a.begins_with("lightdrag="):
			_light_drag = a.substr(10).split(",")
	if arg_settle > 0:
		_settle = arg_settle
	_aim(0)


func _find(n: Node, want: String) -> Node:
	if String(n.name) == want:
		return n
	for c in n.get_children():
		var r: Node = _find(c, want)
		if r != null:
			return r
	return null


func _aim(i: int) -> void:
	var cam: Camera3D = $SubViewport/World/Camera3D
	var s: Array = SHOTS[i]
	cam.position = s[1]
	cam.look_at(s[2], Vector3.UP)
	cam.fov = float(s[3])
	cam.make_current()


func _process(_dt: float) -> void:
	_frame += 1
	# Rebuild the light well before the first shot, so the per-frame
	# daylight sync has already driven its emissive and shaft alpha.
	if _frame == maxi(1, _settle - 60):
		_rebuild_light()
	if _frame == _settle - 1:
		_apply_hides()
	if _frame < _settle:
		return
	if (_frame - _settle) % 6 != 0:
		return
	var img: Image = sub_viewport.get_texture().get_image()
	var shot_name: String = String(SHOTS[_shot][0]) \
		+ ("_dragged" if _light_dragged else "")
	img.save_png("%s%s.png" % [_out_prefix, shot_name])
	print("[inspect] saved %s" % shot_name)
	if _light_drag.size() == 5 and not _light_dragged:
		_light_dragged = true
		_drag_light()
		return
	_shot += 1
	if _shot >= SHOTS.size():
		print("[inspect] done")
		get_tree().quit(0)
		return
	_aim(_shot)


func _rebuild_light() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	var w: Node = get_node("SubViewport/World")
	if cfg == null or _light_drag.size() != 5:
		return
	cfg.set("capture_mode", true)
	cfg.light_fixture = _light_drag[0]
	cfg.light_volumetric = true
	cfg.spot_offset_x = 0.0
	cfg.spot_offset_z = 0.0
	cfg.spot_aim_x = LightingRig.AIM_OFF
	cfg.spot_aim_z = LightingRig.AIM_OFF
	var r: Variant = w.get("_light_fixture_root")
	if r != null and is_instance_valid(r):
		(r as Node).free()
	(w.get("_light_fixture_spots") as Array).clear()
	w.call("_build_light_fixture")
	print("[inspect] light rebuilt as ", _light_drag[0])


func _drag_light() -> void:
	var w: Node = get_node("SubViewport/World")
	var ox: float = float(_light_drag[1])
	var oz: float = float(_light_drag[2])
	var ax: float = float(_light_drag[3])
	var az: float = float(_light_drag[4])
	for i in 41:
		var f: float = float(i) / 40.0
		w.call("set_light_placement", ox * f, oz * f, ax * f, az * f)
	var n: int = 0
	for c in (w.get("_light_fixture_root") as Node).get_children():
		if c.has_meta("beam_spot") and not c.is_queued_for_deletion():
			n += 1
	print("[inspect] light dragged; shafts=%d spots=%d" % [
		n, (w.get("_light_fixture_spots") as Array).size()])


func _apply_hides() -> void:
	# --hide=Name1,Name2 : bisect a visual artifact by removing suspects.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("hide="):
			for want in a.split("=")[1].split(","):
				var root_n: Node = get_node("SubViewport/World")
				var n: Node = root_n if want == "WORLD" else _find(root_n, want)
				if n != null:
					print("[inspect] hiding ", want)
					(n as Node3D).visible = false
				else:
					print("[inspect] NOT FOUND ", want)
	# What height did the plants actually END UP at?
	var w: Node = get_node("SubViewport/World")
	var water: float = float(w.get("WATER_HEIGHT"))
	var pr: Node = w.get_node_or_null("Plants")
	if pr != null:
		var n: int = 0
		var reached: int = 0
		var tops: Array = []
		for c in pr.get_children():
			if c.get("current_height") == null:
				continue
			n += 1
			var top: float = float(c.call("top_world_y")) if c.has_method("top_world_y") else 0.0
			tops.append(top)
			if top >= water - 0.3:
				reached += 1
			if n <= 4:
				print("[inspect] plant %s h=%d/%d top=%.2f water=%.2f pooling=%s" % [
					str(c.get("species_id")), int(c.get("current_height")),
					int(c.get("max_height")), top, water,
					str(int(c.get("life_phase")))])
		tops.sort()
		print("[inspect] %d plants, %d reached the surface, tallest top=%.2f water=%.2f" % [
			n, reached, (tops[-1] if tops.size() > 0 else 0.0), water])

