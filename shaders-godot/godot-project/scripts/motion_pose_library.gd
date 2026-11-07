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
# Editable channels for the motion-lab pose editor (#218). Ranges are [min, max, step].
const CHANNELS: PackedStringArray = [
	"fin_carriage", "caudal_spread", "dorsal_raise", "anal_raise",
	"pec_forward", "pec_spread", "head_pitch", "body_arch", "roll",
	"breath", "opercula", "jaw", "colour",
]
const CHANNEL_RANGE: Dictionary = {
	"fin_carriage": [-1.0, 1.0, 0.02],
	"caudal_spread": [0.5, 1.6, 0.02],
	"dorsal_raise": [-0.5, 1.0, 0.02],
	"anal_raise": [-0.5, 1.0, 0.02],
	"pec_forward": [-0.5, 1.0, 0.02],
	"pec_spread": [-0.5, 1.0, 0.02],
	"head_pitch": [-1.0, 1.0, 0.02],
	"body_arch": [-0.5, 1.0, 0.02],
	"roll": [-1.0, 1.0, 0.02],
	"breath": [0.0, 2.5, 0.05],
	"opercula": [0.0, 1.0, 0.02],
	"jaw": [0.0, 1.0, 0.02],
	"colour": [0.0, 1.0, 0.02],
}

static var _data: Dictionary = {}
static var _loaded: bool = false
# "species|pose" -> resolved channels (no "_" metadata). Read-only: the per-
# frame pose layer (FishPoseRuntime.tick) used to rebuild every pose with three
# merges and a filter copy, four poses per fish per frame.
static var _resolved: Dictionary = {}


static func reload_data() -> bool:
	_data = {}
	_resolved = {}
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


# Channels of a resolved pose, cached. The returned dictionary is shared:
# never write to it (get_pose returns a private copy for callers that edit).
static func resolved_channels(species: String, pose: String) -> Dictionary:
	if not _loaded:
		reload_data()
	var key: String = species + "|" + pose
	var hit: Variant = _resolved.get(key)
	if hit != null:
		return hit
	var c: Dictionary = _channels_only(get_pose(species, pose))
	_resolved[key] = c
	return c


# Same result as mix() for channel-only inputs (resolved_channels / earlier
# mix_channels output), without re-filtering both sides every call.
static func mix_channels(from: Dictionary, to: Dictionary, w: float) -> Dictionary:
	var out: Dictionary = from.duplicate()
	var cw: float = clampf(w, 0.0, 1.0)
	for k in to:
		out[k] = lerpf(float(from.get(k, to[k])), float(to[k]), cw)
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


static func list_poses(species: String = "_default") -> PackedStringArray:
	if not _loaded:
		reload_data()
	var names: Dictionary = {}
	for table_key in ["_default", species]:
		var table: Variant = _data.get(table_key, {})
		if not (table is Dictionary):
			continue
		for k in table as Dictionary:
			var ks: String = String(k)
			if ks.begins_with("_"):
				continue
			names[ks] = true
	var out := PackedStringArray(names.keys())
	out.sort()
	return out


# #218: write a species override (or _default) into the in-memory library.
static func upsert_pose(species: String, pose: String, channels: Dictionary) -> void:
	if not _loaded:
		reload_data()
	if species.is_empty() or pose.is_empty():
		return
	if not (_data.get(species) is Dictionary):
		_data[species] = {}
	var table: Dictionary = _data[species]
	var cleaned: Dictionary = _channels_only(channels)
	# Preserve blend metadata when the caller includes it.
	for meta_k in ["_in", "_out", "_ease"]:
		if channels.has(meta_k):
			cleaned[meta_k] = channels[meta_k]
	table[pose] = cleaned
	_resolved = {}


# Persist the library to the first writable path in `paths`.
# Default: shipped DATA_PATH. Lab save passes [DATA_PATH, backup]; tests pass
# a user:// path only so the shipped file is never touched.
static func save_data(paths: Variant = null) -> String:
	if not _loaded:
		reload_data()
	var targets := PackedStringArray()
	if paths is PackedStringArray:
		targets = paths
	elif paths is Array:
		for p in paths:
			targets.append(String(p))
	elif paths is String and not String(paths).is_empty():
		targets.append(String(paths))
	else:
		targets.append(DATA_PATH)
	var payload: String = JSON.stringify(_data, "\t")
	for path in targets:
		var base: String = path.get_base_dir()
		if path.begins_with("user://") or path.begins_with("res://"):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
		else:
			DirAccess.make_dir_recursive_absolute(base)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(payload)
		f.close()
		return path
	return ""


# #219: tile cell images into one contact sheet (rows × cols).
static func compose_contact_sheet(cells: Array, cols: int, pad: int = 2,
		bg: Color = Color(0.08, 0.09, 0.11)) -> Image:
	if cells.is_empty() or cols <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var cell_w: int = 1
	var cell_h: int = 1
	for c in cells:
		if c is Image:
			cell_w = maxi(cell_w, (c as Image).get_width())
			cell_h = maxi(cell_h, (c as Image).get_height())
	var rows: int = int(ceil(float(cells.size()) / float(cols)))
	var out_w: int = cols * cell_w + (cols - 1) * pad
	var out_h: int = rows * cell_h + (rows - 1) * pad
	var out := Image.create(maxi(out_w, 1), maxi(out_h, 1), false, Image.FORMAT_RGBA8)
	out.fill(bg)
	for i in cells.size():
		var im: Image = cells[i] as Image
		if im == null:
			continue
		im.convert(Image.FORMAT_RGBA8)
		var col: int = i % cols
		@warning_ignore("integer_division")
		var row: int = i / cols
		var x: int = col * (cell_w + pad)
		var y: int = row * (cell_h + pad)
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, y))
	return out


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
