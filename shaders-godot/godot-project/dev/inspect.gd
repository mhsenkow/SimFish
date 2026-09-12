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
	if _frame == _settle - 1:
		_apply_hides()
	if _frame < _settle:
		return
	if (_frame - _settle) % 6 != 0:
		return
	var img: Image = sub_viewport.get_texture().get_image()
	img.save_png("res://inspect_%s.png" % SHOTS[_shot][0])
	print("[inspect] saved %s" % SHOTS[_shot][0])
	_shot += 1
	if _shot >= SHOTS.size():
		print("[inspect] done")
		get_tree().quit(0)
		return
	_aim(_shot)


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

