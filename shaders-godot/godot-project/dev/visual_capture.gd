# Visual regression capture — the SHIPPED look, measured.
#
# VISUAL_DIRECTIONS #20.
#
# WHY THIS EXISTS. dev/capture.tscn and dev/capture_pass.tscn both build their
# own scene tree around world.gd and never instantiate main.gd. Everything
# main.gd drives per frame — palette tint, day phase, night blend, health
# grade, murk, the water column globals, biotope palette selection, the whole
# post-uniform chain — is therefore left at shader defaults. Run today, they
# render frames that look nothing like the game: capture.tscn puts the camera
# partway inside the substrate, capture_pass.tscn renders a desaturated grey
# box. Both were presumably accurate when written, and the visual idea docs
# have been grading themselves against them ever since.
#
# So this harness instantiates res://main.tscn, the actual game, and drives it.
#
#   Godot --path . res://dev/visual_capture.tscn
#
# NOT --headless: the dummy renderer produces no image. This opens a window
# for a few seconds and quits itself.
#
# Output lands in user://visual_capture/ (printed on exit):
#   <angle>.png       the frame, HUD hidden
#   metrics.txt       one FrameMetrics line per angle, diffable between commits
#
# DETERMINISM. The frame has to be comparable between commits or the numbers
# mean nothing, so before main.tscn is instantiated the harness:
#   - sets TankConfig.capture_mode, which suspends config saves and blocks
#     SaveManager.try_load/save_active (the player's tank must neither be read
#     nor written by a capture),
#   - resets TankConfig to script defaults and applies one named scenario,
#   - leaves SimDriver.tank_seed at its fixed default (0xCAFEF155) — with the
#     save load blocked, nothing perturbs it.
# The remaining variance is particle phase and the wall clock, both cosmetic.
#
# Environment overrides:
#   VISUAL_CAPTURE_SCENARIO   scenario id (default beginner_sandbox)
#   VISUAL_CAPTURE_SETTLE     frames to settle before the first shot (default 480)
#   VISUAL_CAPTURE_HUD        1 to keep the HUD in frame (default: hidden)
#   VISUAL_CAPTURE_DAY_PHASE  0..1 clock to pin (default 0.25 = midday)
#   VISUAL_CAPTURE_VERBOSE    1 to print the camera position per angle

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")
# Preloaded rather than reached by class_name: dev/ scenes are run straight
# from the CLI, where a class added since the last editor import is not yet in
# the global class cache. Same pattern as tank_config.gd's Aesthetics preload.
const Metrics = preload("res://scripts/frame_metrics.gd")
const AestheticsScript = preload("res://scripts/aesthetics_runtime.gd")
const Composition = preload("res://scripts/scape_composition.gd")

const OUT_DIR: String = "user://visual_capture"
const DEFAULT_SCENARIO: String = "beginner_sandbox"
# Frames before the first shot. With the render live (see _force_live_render)
# the sim actually ticks, so the tank is built and planted well before this;
# the number is set by how long the staged cosmetic passes take to converge,
# not by the ecology.
const DEFAULT_SETTLE: int = 480
# Frames to let the camera settle after a move. The orbit camera is applied
# immediately but plant sway, particles and the 10 Hz cosmetic tick are not.
const ANGLE_SETTLE: int = 30
# Sim clock to hold. 0 = dawn, 0.25 = midday (SimDriver.day_phase). The room
# lights, the fixture, the palette night blend and the god rays all key off
# this, so a capture that does not pin it measures a different hour every run
# — which is how an early version of this harness produced a warm daylit room
# at one settle length and a black one at another.
const DEFAULT_DAY_PHASE: float = 0.25

# Named angles, as orbit state rather than transforms, so they survive a
# change to the camera rig. Kept few: a capture set nobody looks at is worse
# than no capture set.
const ANGLES: Array[Dictionary] = [
	{"name": "hero", "yaw": -0.35, "pitch": 0.16, "radius": 20.0, "target_y": 3.4},
	{"name": "front", "yaw": 0.0, "pitch": 0.10, "radius": 19.0, "target_y": 3.2},
	{"name": "close", "yaw": -0.35, "pitch": 0.06, "radius": 9.5, "target_y": 3.0},
	# Looks down ON the water. The hero angles see the surface nearly edge-on,
	# so nothing that happens ON it — the specular under the fixture, the
	# meniscus, floaters — is assessable from them.
	{"name": "surface", "yaw": -0.20, "pitch": 0.62, "radius": 14.0, "target_y": 5.4},
]

var _main: Node = null
var _frame: int = 0
var _settle: int = DEFAULT_SETTLE
var _angle_i: int = 0
var _angle_frame: int = 0
var _armed: bool = false
var _lines: PackedStringArray = PackedStringArray()
var _hud_hidden: bool = false
var _verbose: bool = false
var _day_phase: float = DEFAULT_DAY_PHASE


func _ready() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null:
		push_error("[visual_capture] TankConfig autoload missing")
		get_tree().quit(1)
		return
	cfg.set("capture_mode", true)
	if cfg.has_method("reset_to_defaults"):
		cfg.reset_to_defaults()
	# Duotone replaces the palette wholesale, so a capture taken with it on
	# measures the ramp rather than the biotope palette.
	cfg.set("duotone_mode", "none")
	cfg.set("colorblind_palette", "none")
	# reset_to_defaults() rewinds render_width/height and the curated look back
	# to the raw script defaults (1024x576, no vignette, no creature ink). The
	# shipped first launch does not look like that — AestheticsRuntime applies
	# BEAUTY_DEFAULTS over the top. Re-apply them so a capture measures what a
	# player sees rather than what the variable declarations say.
	cfg.set("beauty_defaults_applied", false)
	AestheticsScript.apply_first_launch_defaults(cfg)
	_apply_scenario(cfg, _env("VISUAL_CAPTURE_SCENARIO", DEFAULT_SCENARIO))
	_verbose = _env("VISUAL_CAPTURE_VERBOSE", "0") == "1"
	_day_phase = clampf(_env("VISUAL_CAPTURE_DAY_PHASE",
		str(DEFAULT_DAY_PHASE)).to_float(), 0.0, 1.0)
	_settle = int(_env("VISUAL_CAPTURE_SETTLE", str(DEFAULT_SETTLE)).to_int())
	if _settle <= 0:
		_settle = DEFAULT_SETTLE
	# main.gd re-applies the camera from its own follow / cinema state inside
	# _process, and a parent's _process runs BEFORE its children's. Run last so
	# the angle the harness sets is the angle that gets rendered.
	process_priority = 1000
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	print("[visual_capture] booting; settle=", _settle, " angles=", ANGLES.size())


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key)
	return fallback if v.strip_edges().is_empty() else v.strip_edges()


func _apply_scenario(cfg: Node, id: String) -> void:
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == id:
			ScenarioPickerScript.apply_scenario(sc, cfg)
			print("[visual_capture] scenario=", id)
			return
	push_warning("[visual_capture] unknown scenario '%s' — using config defaults" % id)


func _process(_dt: float) -> void:
	_frame += 1
	_force_live_render()
	_pin_clock()
	if _frame < _settle:
		return
	if not _armed:
		_armed = true
		if _env("VISUAL_CAPTURE_HUD", "0") != "1":
			_hide_chrome()
		_release_camera_modes()
		_apply_angle(0)
		_angle_frame = 0
		return
	_angle_frame += 1
	# Held every frame, not set once: follow-cam and cinema mode both write the
	# camera from _process, so a one-shot set is a suggestion. The idle counter
	# is reset with it — past SCREENSAVER_IDLE_S (45 s) main.gd re-arms the
	# favourites tour every frame, and a capture run is nothing but idle time.
	_main.set("_hud_idle_seconds", 0.0)
	_apply_angle(_angle_i)
	if _angle_frame < ANGLE_SETTLE:
		return
	_shoot(ANGLES[_angle_i])
	_angle_i += 1
	if _angle_i >= ANGLES.size():
		_finish()
		return
	_apply_angle(_angle_i)
	_angle_frame = 0


# Hide every Control the game layers over the render, without depending on
# main.gd's own photo path — _set_hud_visible_for_photo also draws letterbox
# bars, which would poison the luminance percentiles with pure black.
func _hide_chrome() -> void:
	if _main == null or _hud_hidden:
		return
	_hud_hidden = true
	for child in _main.get_children():
		if child is Control and String(child.name) != "Display":
			(child as Control).visible = false


# Keep the render alive.
#
# THE TRAP THIS EXISTS FOR. A capture run launches a window that never takes
# focus, so main.gd's _on_focus_out fires: it sets sim.time_scale = 0 and
# _sync_viewport_update_mode then sets BOTH SubViewports to UPDATE_DISABLED.
# The window still composites, get_texture().get_image() still returns an
# image, and every angle returns the SAME frozen frame — three camera moves,
# one picture, no error anywhere. Worth knowing before writing any other
# headless-ish capture against this app.
func _force_live_render() -> void:
	if _main == null:
		return
	if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
		_main.call("_on_focus_in")
	for key in ["sub_viewport", "_post_viewport"]:
		var vp: Variant = _main.get(key)
		if vp is SubViewport:
			var sv: SubViewport = vp
			if sv.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
				sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS


# Hold the sim clock. Cheap enough to do every frame, and doing it during the
# settle (not just before the shot) means the lighting has actually converged
# on that hour rather than being snapped to it one frame before the capture.
func _pin_clock() -> void:
	if _main == null:
		return
	var sim: Variant = _main.get("_sim")
	if sim is Node and (sim as Node).get("day_phase") != null:
		(sim as Node).set("day_phase", _day_phase)


# Hand the camera back from whatever the game was doing with it. The idle
# screensaver tour and cinema mode both take ownership after a few seconds of
# no input, and a capture run is nothing but no input.
func _release_camera_modes() -> void:
	if _main == null:
		return
	if _main.has_method("set_cinema_mode"):
		_main.call("set_cinema_mode", false, false)
	if _main.has_method("clear_follow"):
		_main.call("clear_follow")
	if _main.has_method("_release_cinematic_follow"):
		_main.call("_release_cinematic_follow")


func _apply_angle(i: int) -> void:
	var a: Dictionary = ANGLES[i]
	if _main == null:
		return
	_main.set("yaw", float(a["yaw"]))
	_main.set("pitch", float(a["pitch"]))
	_main.set("radius", float(a["radius"]))
	_main.set("target", Vector3(0.0, float(a["target_y"]), 0.0))
	if _main.has_method("_apply_camera"):
		_main.call("_apply_camera")



func _shoot(a: Dictionary) -> void:
	var name_s: String = String(a["name"])
	if _verbose:
		var cam := _main.get_node_or_null("SubViewport/World/Camera3D") as Camera3D
		print("[visual_capture] shoot ", name_s, " i=", _angle_i,
			" main.radius=", _main.get("radius"), " main.yaw=", _main.get("yaw"),
			" cam=", cam.global_position if cam != null else "?")
	if _verbose:
		var sv := _main.get_node_or_null("SubViewport") as SubViewport
		if sv != null:
			var raw: Image = sv.get_texture().get_image()
			raw.save_png("%s/%s_raw.png" % [OUT_DIR, name_s])
			print("[visual_capture]   raw sv size=", sv.size,
				" mode=", sv.render_target_update_mode)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("[visual_capture] no viewport image for angle %s" % name_s)
		return
	var path: String = "%s/%s.png" % [OUT_DIR, name_s]
	img.save_png(path)
	# Measure the internal-resolution truth where we can: the palette contract
	# is a property of the post pass, and the window image is a nearest-neighbour
	# upscale of it, so colour counts survive but sample counts do not. Step 2
	# keeps a 1536x864 read fast without changing any percentile materially.
	var pal_max: float = _palette_max_luma()
	# neighbour stride = the nearest-neighbour upscale factor, so the stipple
	# metric compares RENDER pixels rather than the duplicated window pixels
	# between them (VISUAL_DIRECTIONS #7).
	var report: Dictionary = Metrics.read(img, Rect2i(), 2,
		Metrics.highlight_level_for(pal_max), _upscale_factor(img))
	_lines.append(Metrics.format_report(name_s, report))
	var pal: int = _palette_size()
	for row in Metrics.grade(report, pal):
		_lines.append("  %-16s %-10s %10.3f  %s" % [
			row["name"], row["want"], row["value"],
			"ok" if row["ok"] else "FAIL"])
	print("[visual_capture] ", Metrics.format_report(name_s, report))


# Brightest luminance the active palette can produce, blending the day and
# night LUTs the way palette_quantize.gdshader's palette_color() does.
#
# The highlight grade is relative to this. A night palette tops out around 154
# by construction, so an absolute "reach 200" is unreachable at midnight
# however bright the specular is — it would be asking the frame to leave its
# own palette.
func _palette_max_luma() -> float:
	var sm: ShaderMaterial = _quantize_material()
	if sm == null:
		return 255.0
	var day: Texture2D = sm.get_shader_parameter("palette_tex") as Texture2D
	var night: Texture2D = sm.get_shader_parameter("palette_tex_night") as Texture2D
	var blend_v: Variant = sm.get_shader_parameter("palette_night_blend")
	var blend: float = clampf(float(blend_v) if blend_v != null else 0.0, 0.0, 1.0)
	var day_max: float = _tex_max_luma(day)
	var night_max: float = _tex_max_luma(night) if night != null else day_max
	return lerpf(day_max, night_max, blend)


func _tex_max_luma(tex: Texture2D) -> float:
	if tex == null:
		return 255.0
	var img: Image = tex.get_image()
	if img == null:
		return 255.0
	var best: float = 0.0
	for x in img.get_width():
		best = maxf(best, Metrics.luma8(img.get_pixel(x, 0)))
	return best


# main.gd's OWN accessor, not a reimplementation of it.
#
# The quantize material lives on the post viewport's display, and only falls
# back to the visible `Display` node when the post pipeline is absent. Reading
# `Display.material` directly — which is what this did first — silently got a
# material with none of the driven uniforms on it: palette_size fell back to a
# hardcoded 48 (right by luck) and palette_night_blend read null, so a midnight
# capture was graded against the day palette's ceiling.
func _quantize_material() -> ShaderMaterial:
	if _main == null:
		return null
	if _main.has_method("_quantize_material"):
		return _main.call("_quantize_material") as ShaderMaterial
	var disp: Node = _main.get_node_or_null("Display")
	return disp.get("material") as ShaderMaterial if disp != null else null


# How many window pixels one internal render pixel occupies.
func _upscale_factor(img: Image) -> int:
	var sv: Variant = _main.get("sub_viewport") if _main != null else null
	if sv is SubViewport and img != null:
		var iw: int = (sv as SubViewport).size.x
		if iw > 0:
			return clampi(int(round(float(img.get_width()) / float(iw))), 1, 8)
	return 1


func _palette_size() -> int:
	var mat: ShaderMaterial = _quantize_material()
	if mat != null:
		var v: Variant = mat.get_shader_parameter("palette_size")
		if v != null:
			return maxi(int(v), 1)
	return 48


# The scape's use of the water volume (VISUAL_DIRECTIONS #17). Reported once,
# not per angle — composition is a property of the tank, not the camera.
func _composition_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var sim: Variant = _main.get("_sim") if _main != null else null
	var world: Variant = _main.get("world") if _main != null else null
	if not (sim is Node) or not (world is Node3D):
		return out
	var floor_y: float = float(world.get("SUBSTRATE_DEPTH"))
	var surface_y: float = float(world.get("WATER_HEIGHT"))
	var half_w: float = float(world.get("TANK_HALF_W"))
	var voxel: float = float(world.get("VOXEL_SIZE"))
	var hardscape: Array = world.get("_last_contact_ao_points") as Array
	var items: Array = Composition.items_from_scape(
		(sim as Node).get("plants") as Array,
		hardscape if hardscape != null else [], voxel)
	var occ: PackedFloat32Array = Composition.band_occupancy(items, floor_y, surface_y)
	var focal: float = Composition.focal_offset_frac(items, half_w)
	out.append("composition      %s  (%d items, floor %.2f surface %.2f)" % [
		Composition.format_report(occ, focal), items.size(), floor_y, surface_y])
	for row in Composition.grade(occ, focal):
		out.append("  %-16s %-12s %10.3f  %s" % [
			row["name"], row["want"], row["value"],
			"ok" if row["ok"] else "FAIL"])
	return out


func _finish() -> void:
	for line in _composition_lines():
		_lines.append(line)
		print("[visual_capture] ", line)
	var text: String = "\n".join(_lines) + "\n"
	var f := FileAccess.open("%s/metrics.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print("[visual_capture] wrote ", ProjectSettings.globalize_path(OUT_DIR))
	print(text)
	get_tree().quit(0)
