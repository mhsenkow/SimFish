extends SceneTree

# The tank has a light model, and it reaches everything (VISUAL_DIRECTIONS #1).
#
# Every spatial shader in this project is `render_mode unshaded` — a deliberate
# choice, because the palette quantizer needs direct control of the colour that
# reaches it. The consequence is that Godot's lights do nothing, and the
# analytic cone in shaders/beam_cone.gdshaderinc is the ONLY light model the
# tank has.
#
# Two things had gone wrong with it, and neither was visible as a bug:
#
#   1. It was included by 2 shaders out of 15. Fauna, hardscape, substrate and
#      the room were lit by four hard-coded face constants, so a fish under the
#      driftwood rendered exactly as bright as one in open water.
#   2. Its out-of-cone floor was 1.0 unless the player raised room_darkness, so
#      even the two shaders that did include it multiplied by one.
#
# Sixteen lights in world.gd and 343 lines of LightingRig, producing no
# photons. The coverage assertion below is the one that would have caught it:
# it reads the shader sources and fails if a surface that renders tank content
# does not sample the cone.

const LightingRigScript = preload("res://scripts/lighting_rig.gd")

const INCLUDE_LINE: String = 'res://shaders/beam_cone.gdshaderinc'

# Shaders that draw solid tank or room content and therefore must be lit.
const MUST_BE_LIT: Array[String] = [
	"voxel", "voxel_mm", "voxel_fauna_mm",
	"foliage", "foliage_mm", "foliage_senescent_mm",
	"substrate_opaque", "substrate_caustic",
]

# Shaders deliberately outside the model, each for a stated reason. Listed so
# the exemption is a decision on the record rather than an omission.
const EXEMPT: Dictionary = {
	"water": "the medium itself — has its own depth/absorption model",
	"glass": "a transparent interface, not a surface",
	"glass_panel": "UI blur",
	"bubble": "billboard, self-lit",
	"caustics": "additive light, not a surface receiving it",
	"god_ray": "additive light, not a surface receiving it",
	"surface_ripple": "additive surface film",
	"voxel_translucent": "blended sheet with no meaningful normal",
	"tank_preview": "2D picker thumbnail",
	"circle_mask": "2D mask",
	"list_edge_fade": "2D fade",
	"palette_quantize": "post pass",
	"palette_quantize_potato": "post pass",
}


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_light_model")

	# --- The cone shapes a normally-lit room ---
	var lit: Vector4 = LightingRigScript.cone_tint(Color.WHITE, 0.0, 1.0)
	t.approx(lit.w, LightingRigScript.CONE_SHAPING_FLOOR,
		"at room_darkness 0 the cone still shapes", 0.001)
	t.check(lit.w < 0.999,
		"out-of-cone floor must be under 1.0 at default settings — at 1.0 the "
			+ "only light model in the project multiplies by one")
	t.check(lit.w > LightingRigScript.CONE_AMBIENT_FLOOR,
		"a lit room must not be as dark outside the cone as a blacked-out one")

	# --- …and the opt-out still exists ---
	var flat: Vector4 = LightingRigScript.cone_tint(Color.WHITE, 0.0, 0.0)
	t.approx(flat.w, 1.0, "light_shaping 0 restores the flat behaviour", 0.001)

	# --- Darkness still owns the bottom end ---
	var dark: Vector4 = LightingRigScript.cone_tint(Color.WHITE, 1.0, 1.0)
	t.approx(dark.w, LightingRigScript.CONE_AMBIENT_FLOOR,
		"full room darkness reaches the ambient floor", 0.001)
	t.check(dark.w < lit.w, "darkness deepens the unlit half")
	# Monotonic in darkness — no preset should find a brighter spot mid-range.
	var prev: float = 2.0
	for i in 11:
		var d: float = float(i) / 10.0
		var amb: float = LightingRigScript.cone_tint(Color.WHITE, d, 1.0).w
		t.check(amb <= prev + 0.0001,
			"ambient must fall monotonically with darkness (at %.1f)" % d)
		prev = amb

	# --- Colour passes through untouched ---
	var tinted: Vector4 = LightingRigScript.cone_tint(Color(0.9, 0.6, 0.3), 0.4, 1.0)
	t.approx(tinted.x, 0.9, "cone tint carries r", 0.001)
	t.approx(tinted.y, 0.6, "cone tint carries g", 0.001)
	t.approx(tinted.z, 0.3, "cone tint carries b", 0.001)

	# --- A bar fixture is a segment, not its leftmost spot ---
	var bar: Array = [
		Vector3(-4.0, 8.0, 0.0), Vector3(-1.33, 8.0, 0.0),
		Vector3(1.33, 8.0, 0.0), Vector3(4.0, 8.0, 0.0),
	]
	var seg: Dictionary = LightingRigScript.beam_segment(bar)
	t.check(bool(seg["is_line"]), "four spaced spots make a line light")
	t.check((seg["origin"] as Vector3).is_equal_approx(Vector3(0.0, 8.0, 0.0)),
		"line origin is the midpoint, got %s" % str(seg["origin"]))
	t.approx((seg["axis"] as Vector3).x, 4.0, "axis is the half-extent", 0.001)
	t.approx((seg["axis"] as Vector3).length(), 4.0, "axis has no stray y/z", 0.001)

	# --- A single-spot fixture collapses to a point ---
	var point: Dictionary = LightingRigScript.beam_segment([Vector3(2.0, 9.0, -1.0)])
	t.check(not bool(point["is_line"]), "one spot is not a line")
	t.check((point["axis"] as Vector3).is_zero_approx(), "point light has no axis")
	t.check((point["origin"] as Vector3).is_equal_approx(Vector3(2.0, 9.0, -1.0)),
		"point origin is the spot itself")

	# Two spots a couple of centimetres apart are a point, not a line.
	var tight: Dictionary = LightingRigScript.beam_segment(
		[Vector3(0.0, 8.0, 0.0), Vector3(0.05, 8.0, 0.0)])
	t.check(not bool(tight["is_line"]), "a 5cm span is not a bar")
	t.check(LightingRigScript.beam_segment([]).is_empty() == false,
		"empty input returns a usable dictionary")
	t.check(not bool(LightingRigScript.beam_segment([])["is_line"]),
		"empty input is not a line")

	# --- Coverage: every lit surface samples the cone ---
	for name_s in MUST_BE_LIT:
		var path: String = "res://shaders/%s.gdshader" % name_s
		var src: String = _read(path)
		t.check(src != "", "shader %s exists" % name_s)
		if src == "":
			continue
		t.check(src.contains(INCLUDE_LINE),
			"%s must include beam_cone.gdshaderinc — an unshaded surface that "
				% name_s + "does not sample the cone is not lit by anything")
		t.check(src.contains("iaq_beam_light"),
			"%s includes the cone but never calls it" % name_s)

	# --- Every spatial shader is either lit or explicitly exempt ---
	# Catches the next shader someone adds without deciding which it is.
	var dir := DirAccess.open("res://shaders")
	t.check(dir != null, "shaders dir is readable")
	if dir != null:
		var unclassified: Array[String] = []
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if fn.ends_with(".gdshader"):
				var stem: String = fn.get_basename()
				var src: String = _read("res://shaders/%s" % fn)
				if src.contains("shader_type spatial") \
						and stem not in MUST_BE_LIT and not EXEMPT.has(stem):
					unclassified.append(stem)
			fn = dir.get_next()
		dir.list_dir_end()
		t.check(unclassified.is_empty(),
			"spatial shaders neither lit nor exempt: %s — add to MUST_BE_LIT "
				% str(unclassified) + "or to EXEMPT with a reason")

	quit(t.finish())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s
