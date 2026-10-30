# Motion clip capture (CREATURE_MOTION_700 #98 #99 #118).
#
#   MOTION_CLIP_SPECIES=guppy MOTION_CLIP_MANOEUVRE=dart \
#     scripts/dev_run.sh --path shaders-godot/godot-project res://dev/motion_clip.tscn
#   python3 tools/motion_clip_compose.py gif <out dir>
#
# One creature on the motion-lab stage (dev/motion_lab_stage.gd) doing a
# scripted manoeuvre at a fixed sim step, written as PNG frames plus a
# per-frame motion.csv of every pivot channel (rotation and scale of bank,
# head, body, tail, dorsal, pectorals, legs, shell...), with heading, yaw,
# speed, bank, phases, burst / startle timers and head / tail tip positions.
# The same seed, species and manoeuvre before and after a change give two
# frame directories that tools/motion_clip_compose.py lays side by side (#99).
#
# Environment:
#   MOTION_CLIP_SPECIES    kind key: a SPECIES_LIBRARY fish, shrimp:caridean,
#                          shrimp:crab, shrimp:lobster, shrimp:mantis,
#                          snail:turbo (default guppy)
#   MOTION_CLIP_MANOEUVRE  cruise_turn (the swimming_capture sine-yaw run,
#                          then a slow-down), figure8, circle, straight,
#                          hover, or an action on a straight run: dart,
#                          startle, gulp, display, court, die, flip
#                          (default cruise_turn)
#   MOTION_CLIP_SECONDS    clip length (default 4)
#   MOTION_CLIP_FPS        frames per sim second (default 30)
#   MOTION_CLIP_ACTION_AT  seconds before the action fires (default 1.0)
#   MOTION_CLIP_PACE       pace as a fraction of max speed (default 0.35)
#   MOTION_CLIP_VIEW       side | top | front | three (default three)
#   MOTION_CLIP_BODY_FRAME 1 = cameras turn with the heading (default 1)
#   MOTION_CLIP_SIZE       per-view pixels, WxH (default 384x256)
#   MOTION_CLIP_OVERLAY    1 = draw the MotionDebugOverlay onion skins / path
#   MOTION_CLIP_SEED       global seed (default 20261030)
#   MOTION_CLIP_OUT        output dir (default $GODOT_DEV_OUT_ROOT/motion_clip/
#                          <species>_<manoeuvre>, else user://motion_clip/...)
#
# Headless (--headless, dummy renderer) still writes motion.csv and meta.json;
# frames need a real renderer, so run it windowed for PNGs.
extends Node

const StageScript := preload("res://dev/motion_lab_stage.gd")
const ACTIONS: PackedStringArray = ["dart", "startle", "gulp", "display", "court", "die", "flip"]

var _stage: StageScript = null
var _views: Array = []


func _ready() -> void:
	_capture.call_deferred()


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key).strip_edges()
	return fallback if v.is_empty() else v


func _capture() -> void:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg != null:
		cfg.set("capture_mode", true)
		cfg.set("music_enabled", false)
		cfg.set("music_sync_fish", false)
	var species: String = _env("MOTION_CLIP_SPECIES", "guppy")
	var manoeuvre: String = _env("MOTION_CLIP_MANOEUVRE", "cruise_turn")
	var seconds: float = _env("MOTION_CLIP_SECONDS", "4").to_float()
	var fps: float = maxf(1.0, _env("MOTION_CLIP_FPS", "30").to_float())
	var action_at: float = _env("MOTION_CLIP_ACTION_AT", "1.0").to_float()
	var pace: float = _env("MOTION_CLIP_PACE", "0.35").to_float()
	var view_mode: String = _env("MOTION_CLIP_VIEW", "three")
	var body_frame: bool = _env("MOTION_CLIP_BODY_FRAME", "1") == "1"
	var size_parts: PackedStringArray = _env("MOTION_CLIP_SIZE", "384x256").split("x")
	var vp_size := Vector2i(384, 256)
	if size_parts.size() == 2:
		vp_size = Vector2i(maxi(32, size_parts[0].to_int()), maxi(32, size_parts[1].to_int()))
	var seed_v: int = _env("MOTION_CLIP_SEED", "20261030").to_int()
	var out: String = OS.get_environment("MOTION_CLIP_OUT").strip_edges()
	if out.is_empty():
		var root: String = OS.get_environment("GODOT_DEV_OUT_ROOT").strip_edges()
		var leaf: String = "%s_%s" % [species.replace(":", "_"), manoeuvre]
		out = root.path_join("motion_clip").path_join(leaf) if not root.is_empty() \
			else "user://motion_clip/" + leaf
	var out_abs: String = ProjectSettings.globalize_path(out) if out.contains("://") else out
	DirAccess.make_dir_recursive_absolute(out_abs)
	var render: bool = DisplayServer.get_name() != "headless"

	var world := World3D.new()
	var names: PackedStringArray = PackedStringArray(["side", "top", "front"]) if view_mode == "three" \
		else PackedStringArray([view_mode])
	for v in names:
		var vp := SubViewport.new()
		vp.world_3d = world
		vp.size = vp_size
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if render else SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := Camera3D.new()
		cam.current = true
		vp.add_child(cam)
		_views.append({"vp": vp, "cam": cam, "view": v})
	_stage = StageScript.new()
	(_views[0]["vp"] as SubViewport).add_child(_stage)
	await get_tree().process_frame

	seed(seed_v)
	var kind: Dictionary = _stage.kind_by_key(species)
	if kind.is_empty():
		push_error("[motion_clip] unknown species " + species)
		get_tree().quit(2)
		return
	var anchor := Vector3(0.0, StageScript.FISH_Y, 0.0)
	var c: Node3D = _stage.spawn(kind, anchor)
	if c == null:
		push_error("[motion_clip] could not build " + species)
		get_tree().quit(1)
		return
	var st: Dictionary = _stage.drive_state(c)
	st["pace"] = pace
	st["natural_bouts"] = false
	var action: String = ""
	if manoeuvre == "cruise_turn":
		st["path"] = StageScript.EXTERNAL
	elif manoeuvre in StageScript.PATHS:
		st["path"] = manoeuvre
	elif manoeuvre in ACTIONS:
		st["path"] = "straight"
		action = manoeuvre
	else:
		push_error("[motion_clip] unknown manoeuvre " + manoeuvre)
		get_tree().quit(2)
		return
	var overlay: MotionDebugOverlay = null
	if _env("MOTION_CLIP_OVERLAY", "0") == "1":
		overlay = MotionDebugOverlay.new()
		overlay.show_hud = false
		overlay.draw_depth_bands = false
		overlay.external_clock = true
		_stage.add_child(overlay)
		overlay.sim = _stage.sim
		overlay.set_enabled(true)
		overlay.subject = c

	var pivots: Dictionary = StageScript.pivot_nodes(c)
	var pivot_names: Array = pivots.keys()
	pivot_names.sort()
	var header := PackedStringArray(["frame", "t", "x", "y", "z", "yaw", "speed", "bank",
		"swim_phase", "motor_phase", "tail_activity", "burst", "startle", "action",
		"head_x", "head_y", "head_z", "tail_x", "tail_y", "tail_z",
		"tail_local_x", "tail_local_y", "tail_local_z"])
	for pn in pivot_names:
		for ch in ["rx", "ry", "rz", "sx", "sy", "sz"]:
			header.append("%s_%s" % [pn, ch])
	var rows := PackedStringArray([",".join(header)])
	var frames: int = maxi(1, int(round(seconds * fps)))
	var dt: float = 1.0 / fps
	var fired: bool = false
	var written: int = 0
	var size_len: float = StageScript.view_size(c)
	for i in frames:
		var t: float = float(i) * dt
		if manoeuvre == "cruise_turn" and c is Fish:
			var f: Fish = c
			var yaw: float = sin(t * 0.8) * 1.2
			# The swimming_capture run: 0.48 u/s, then 0.12 u/s for the glide-out.
			var spd: float = (0.48 if t < seconds * 0.62 else 0.12) * (pace / 0.35)
			f.target_velocity = Vector3(sin(yaw), 0.0, -cos(yaw)) * spd
		var fired_now: bool = false
		if not action.is_empty() and not fired and t >= action_at:
			fired = true
			fired_now = _stage.trigger(c, action)
		if not _stage.step(c, dt):
			print("[motion_clip] creature finished (death) at frame ", i)
			break
		if overlay != null:
			overlay.advance(dt)
		rows.append(_row(i, t, c, pivots, pivot_names, action if fired_now else ""))
		if render:
			for v in _views:
				StageScript.place_camera(v["cam"], c, String(v["view"]), body_frame, size_len, c.global_position)
			await RenderingServer.frame_post_draw
			_compose().save_png(out_abs.path_join("frame_%04d.png" % i))
			written += 1
	var f_csv := FileAccess.open(out_abs.path_join("motion.csv"), FileAccess.WRITE)
	f_csv.store_string("\n".join(rows) + "\n")
	f_csv.close()
	var meta: Dictionary = {"species": species, "manoeuvre": manoeuvre, "seconds": seconds,
		"fps": fps, "seed": seed_v, "views": names, "body_frame": body_frame,
		"action": action, "action_at": action_at, "pace": pace,
		"frames": written, "rows": rows.size() - 1,
		"build": String(ProjectSettings.get_setting("application/config/version", ""))}
	var f_meta := FileAccess.open(out_abs.path_join("meta.json"), FileAccess.WRITE)
	f_meta.store_string(JSON.stringify(meta, "\t") + "\n")
	f_meta.close()
	print("[motion_clip] %s %s: %d frames, %d csv rows -> %s" % [species, manoeuvre, written,
		rows.size() - 1, out_abs])
	if not render:
		print("[motion_clip] headless: no frames rendered (dummy renderer); motion.csv only")
	get_tree().quit(0)


func _num(c: Node, field: String) -> float:
	var v: Variant = c.get(field)
	return float(v) if v != null else 0.0


func _row(i: int, t: float, c: Node3D, pivots: Dictionary, pivot_names: Array, action: String) -> String:
	var p: Vector3 = c.global_position
	var head: Vector3 = MotionDebugOverlay.head_tip_world(c)
	var tail: Vector3 = MotionDebugOverlay.tail_tip_world(c)
	var tl: Vector3 = c.global_transform.affine_inverse() * tail
	var cols := PackedStringArray([str(i), "%.4f" % t, "%.5f" % p.x, "%.5f" % p.y, "%.5f" % p.z,
		"%.5f" % MotionDebugOverlay.creature_yaw(c), "%.5f" % MotionDebugOverlay.creature_speed(c),
		"%.5f" % _num(c, "_bank"), "%.5f" % _num(c, "_swim_phase"), "%.5f" % _num(c, "_motor_phase"),
		"%.4f" % _num(c, "_fin_tail_activity"), "%.4f" % _num(c, "burst_remaining"),
		"%.4f" % _num(c, "_startle_remaining"), action,
		"%.5f" % head.x, "%.5f" % head.y, "%.5f" % head.z,
		"%.5f" % tail.x, "%.5f" % tail.y, "%.5f" % tail.z,
		"%.5f" % tl.x, "%.5f" % tl.y, "%.5f" % tl.z])
	for pn in pivot_names:
		var n: Variant = pivots[pn]
		if not (n is Node3D) or not is_instance_valid(n):
			for _k in 6:
				cols.append("")
			continue
		var nd: Node3D = n
		var r: Vector3 = nd.rotation
		var s: Vector3 = nd.scale
		cols.append_array(PackedStringArray(["%.5f" % r.x, "%.5f" % r.y, "%.5f" % r.z,
			"%.4f" % s.x, "%.4f" % s.y, "%.4f" % s.z]))
	return ",".join(cols)


func _compose() -> Image:
	if _views.size() == 1:
		return (_views[0]["vp"] as SubViewport).get_texture().get_image()
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
