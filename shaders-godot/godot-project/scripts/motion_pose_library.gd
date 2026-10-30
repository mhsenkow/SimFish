class_name MotionPoseLibrary
extends RefCounted

# Key poses as data (CREATURE_MOTION_700 #45, #46, #77). Physics is
# straight-ahead animation; behaviours need recognisable shapes it can settle
# into. A pose is a dictionary of named channels (fin carriage, caudal spread,
# head pitch, body arch, roll...) in radians or scale factors, looked up by
# species with a shared fallback, and every pose blends in and out on its own
# times and curve.
#
# res://data/motion/poses.json holds the library:
#   { "_default": { "cruise": {...}, "rest": {...}, ... },
#     "betta": { "display": {..., "_in": 0.4, "_out": 0.6}, ... } }
# Keys starting with "_" are blend metadata: _in / _out seconds and _ease
# ("smooth", "sine", "expo", "back"). A species inherits every pose it
# doesn't define from _default, and each pose inherits missing channels from
# that species' rest pose (#77), so every layer decays to a defined neutral
# rather than to zero.

const DATA_PATH: String = "res://data/motion/poses.json"
const DEFAULT_IN: float = 0.35
const DEFAULT_OUT: float = 0.6

static var _data: Dictionary = {}
static var _loaded: bool = false


static func reload_data() -> bool:
	_data = {}
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_data = parsed
		return true
	push_warning("MotionPoseLibrary: %s is not a JSON object" % DATA_PATH)
	return false


static func _species_table(species: String) -> Dictionary:
	if not _loaded:
		reload_data()
	return _data.get(species, {}) if _data.get(species) is Dictionary else {}


static func has_pose(species: String, pose: String) -> bool:
	return _species_table(species).has(pose) or _species_table("_default").has(pose)


# The rest pose: what every channel returns to.
static func rest_pose(species: String) -> Dictionary:
	var out: Dictionary = {}
	var d: Variant = _species_table("_default").get("rest", {})
	if d is Dictionary:
		out.merge(d, true)
	var s: Variant = _species_table(species).get("rest", {})
	if s is Dictionary:
		out.merge(s, true)
	return _channels_only(out)


# The pose with species overrides and rest fallbacks resolved.
static func get_pose(species: String, pose: String) -> Dictionary:
	var out: Dictionary = rest_pose(species)
	var d: Variant = _species_table("_default").get(pose, {})
	if d is Dictionary:
		out.merge(d, true)
	var s: Variant = _species_table(species).get(pose, {})
	if s is Dictionary:
		out.merge(s, true)
	return out


static func blend_times(species: String, pose: String) -> Vector2:
	var p: Dictionary = get_pose(species, pose)
	return Vector2(float(p.get("_in", DEFAULT_IN)), float(p.get("_out", DEFAULT_OUT)))


static func _channels_only(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		if not String(k).begins_with("_"):
			out[k] = d[k]
	return out


# Blend one channel set toward another: w = 0 is `from`, 1 is `to`. Channels
# missing on either side keep the side that has them.
static func mix(from: Dictionary, to: Dictionary, w: float) -> Dictionary:
	var out: Dictionary = _channels_only(from)
	for k in _channels_only(to):
		out[k] = lerpf(float(from.get(k, to[k])), float(to[k]), clampf(w, 0.0, 1.0))
	return out


static func ease(kind: String, t: float) -> float:
	match kind:
		"sine": return MotionEase.sine_in_out(t)
		"expo": return MotionEase.expo_out(t)
		"back": return MotionEase.back_out(t)
	return MotionEase.smooth(t)


# Tracks one pose's weight over time with separate in/out times (#46):
# alarm poses snap in and let go slowly; displays ease in.
class Blend:
	extends RefCounted
	var weight: float = 0.0
	var target: float = 0.0
	var in_s: float = DEFAULT_IN
	var out_s: float = DEFAULT_OUT
	var curve: String = "smooth"
	var _t: float = 0.0
	var _from: float = 0.0

	func _init(in_seconds: float = DEFAULT_IN, out_seconds: float = DEFAULT_OUT, ease_kind: String = "smooth") -> void:
		in_s = maxf(in_seconds, 0.001)
		out_s = maxf(out_seconds, 0.001)
		curve = ease_kind

	func set_on(on: bool) -> void:
		var t2: float = 1.0 if on else 0.0
		if is_equal_approx(t2, target):
			return
		target = t2
		_from = weight
		_t = 0.0

	func step(dt: float) -> float:
		if is_equal_approx(weight, target):
			return weight
		var span: float = in_s if target > _from else out_s
		_t = minf(_t + maxf(dt, 0.0) / span, 1.0)
		weight = lerpf(_from, target, MotionPoseLibrary.ease(curve, _t))
		if _t >= 1.0:
			weight = target
		return weight
