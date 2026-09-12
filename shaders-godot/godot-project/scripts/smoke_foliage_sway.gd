extends SceneTree

# Foliage sway contract, incl. the distance fade (flower/motion pass).
#
# WHY THIS EXISTS. Shader edits had no gate at all: a renamed or dropped
# uniform does not fail any script check, and Godot happily renders with a
# silently-default value. The symptom is a visual regression nobody catches
# until a screenshot looks wrong.
#
# The distance fade specifically: the tank renders into a 512x288 buffer with
# pixel snapping, so a plant at range covers only a few pixels. Full
# world-space sway made those pixels jump between positions rather than read
# as motion — "at distance they move too much". Sway now ramps down past
# sway_fade_start so far foliage settles.

const FOLIAGE := "res://shaders/foliage.gdshader"
const FOLIAGE_MM := "res://shaders/foliage_mm.gdshader"

# Every shader that sways must fade with distance, or far foliage jitters.
const SWAY_SHADERS: Array[String] = [FOLIAGE, FOLIAGE_MM]

const FADE_UNIFORMS: Array[String] = [
	"sway_fade_start", "sway_fade_end", "sway_fade_floor",
]


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_foliage_sway")

	for path in SWAY_SHADERS:
		var sh: Shader = load(path) as Shader
		if not t.check(sh != null, "%s must load as a Shader" % path):
			continue

		# Uniform presence. A ShaderMaterial reports the real, compiled
		# uniform list, so this catches a rename or a compile failure that
		# drops everything.
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var names: Dictionary = {}
		for u in sh.get_shader_uniform_list():
			names[String(u.get("name", ""))] = true
		t.check(names.size() > 5,
			"%s exposed only %d uniforms — likely a compile failure"
				% [path, names.size()])
		t.check(names.has("sway_amplitude"), "%s must expose sway_amplitude" % path)
		for u_name in FADE_UNIFORMS:
			t.check(names.has(u_name), "%s must expose %s" % [path, u_name])

		# Defaults must describe a real ramp: start < end, floor in [0,0.5].
		# A floor of 1.0 would mean "no fade", i.e. the bug reintroduced.
		var start: float = _default(sh, "sway_fade_start")
		var stop: float = _default(sh, "sway_fade_end")
		var floor_v: float = _default(sh, "sway_fade_floor")
		t.check(start > 0.0, "%s sway_fade_start must be positive (got %.2f)" % [path, start])
		t.check(stop > start,
			"%s sway_fade_end (%.2f) must exceed sway_fade_start (%.2f)"
				% [path, stop, start])
		t.in_range(floor_v, 0.0, 0.5,
			"%s sway_fade_floor must damp meaningfully (got %.2f)" % [path, floor_v])

		# The fade must actually be APPLIED, not just declared. Source check,
		# because a declared-but-unused uniform is exactly the silent failure
		# this suite is for.
		var src: String = FileAccess.get_file_as_string(path)
		t.check(not src.is_empty(), "%s source readable" % path)
		t.check(src.contains("dist_fade"), "%s must compute dist_fade" % path)
		t.check(src.contains("sway_amplitude") and src.contains("* dist_fade"),
			"%s must multiply sway by dist_fade" % path)
		t.check(src.contains("smoothstep(sway_fade_start, sway_fade_end"),
			"%s must ramp between start and end" % path)
		# Flutter is the high-frequency term — the worst pixel-jitter
		# offender at range, so it must fade too.
		var flutter_faded: bool = src.contains("flutter_amplitude * dist_fade")
		t.check(flutter_faded, "%s must fade flutter with distance too" % path)

	# Gusts only exist on the multimesh path; a gust that ignores distance
	# would make far plants lurch even with sway damped.
	var mm_src: String = FileAccess.get_file_as_string(FOLIAGE_MM)
	t.check(mm_src.contains("gust_response") and mm_src.contains("0.11 * dist_fade"),
		"foliage_mm must fade gust push with distance")

	# --- The ramp maths, mirrored, so the intent is pinned ---
	# smoothstep(start, end, d): 0 below start, 1 above end.
	var s0: float = _default(load(FOLIAGE) as Shader, "sway_fade_start")
	var s1: float = _default(load(FOLIAGE) as Shader, "sway_fade_end")
	var fl: float = _default(load(FOLIAGE) as Shader, "sway_fade_floor")
	t.approx(_fade(0.0, s0, s1, fl), 1.0, "close foliage keeps full sway")
	t.approx(_fade(s0 * 0.5, s0, s1, fl), 1.0, "inside fade_start keeps full sway")
	t.approx(_fade(s1 * 2.0, s0, s1, fl), fl, "far foliage damps to the floor")
	t.check(_fade((s0 + s1) * 0.5, s0, s1, fl) < 1.0,
		"mid-range must be partially damped")
	t.check(_fade((s0 + s1) * 0.5, s0, s1, fl) > fl,
		"mid-range must not already be at the floor")
	# Monotonic: motion must only ever decrease with distance.
	var prev: float = 2.0
	for i in 24:
		var d: float = float(i) * (s1 * 1.5 / 24.0)
		var f: float = _fade(d, s0, s1, fl)
		t.check(f <= prev + 0.0001,
			"fade must decrease monotonically (d=%.2f gave %.4f after %.4f)"
				% [d, f, prev])
		prev = f

	quit(t.finish())


# Mirror of the shader's mix(1.0, floor, smoothstep(start, end, d)).
func _fade(dist: float, start: float, stop: float, floor_v: float) -> float:
	return lerpf(1.0, floor_v, smoothstep(start, stop, dist))


# Shader exposes no numeric-default accessor, so read the literal from source.
func _default(sh: Shader, uniform_name: String) -> float:
	var src: String = FileAccess.get_file_as_string(sh.resource_path)
	for line in src.split("\n"):
		if not line.begins_with("uniform "):
			continue
		if not line.contains(uniform_name):
			continue
		var eq: int = line.find("=")
		if eq < 0:
			continue
		var rhs: String = line.substr(eq + 1).replace(";", "").strip_edges()
		if rhs.is_valid_float():
			return float(rhs)
	return 0.0
