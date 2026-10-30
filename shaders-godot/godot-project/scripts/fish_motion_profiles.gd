class_name FishMotionProfiles
extends RefCounted

# Per-locomotion body-wave constants as data (CREATURE_MOTION_700 #63). They
# used to be a match block inside Fish._motion_substep, so tuning meant
# editing the pose code. The defaults below are those values exactly;
# res://data/motion/locomotion_profiles.json, if present, overrides any of
# them per type (phases in multiples of π), and reload_data() re-reads it so the
# motion lab can tune live (#113).
#
# Fields: tail_amp, body_amp, body_phase, head_amp, head_phase (radians,
# measured from the tail's sin(phase)), pec_amp, pec_freq_base and
# pec_freq_speed (pectoral rate = base + speed · per_speed).

const DATA_PATH: String = "res://data/motion/locomotion_profiles.json"

const DEFAULTS: Dictionary = {
	# Body-caudal schoolers: tail and mid-body counter-wag.
	"subcarangiform": {"tail_amp": 0.35, "body_amp": 0.10, "body_phase": PI,
		"head_amp": 0.0, "head_phase": 0.0, "pec_amp": 0.45,
		"pec_freq_base": 4.5, "pec_freq_speed": 3.0},
	# Eel / loach: whole-body travelling wave, head leading.
	"anguilliform": {"tail_amp": 0.55, "body_amp": 0.40, "body_phase": -0.55 * PI,
		"head_amp": 0.30, "head_phase": -1.1 * PI, "pec_amp": 0.20,
		"pec_freq_base": 4.5, "pec_freq_speed": 3.0},
	# Boxfish / puffer: rigid body, the tail oscillates, pectorals steer.
	"ostraciiform": {"tail_amp": 0.42, "body_amp": 0.02, "body_phase": PI,
		"head_amp": 0.0, "head_phase": 0.0, "pec_amp": 0.80,
		"pec_freq_base": 4.5, "pec_freq_speed": 3.0},
	# Tang / angelfish: pectorals are the thrust, the tail is subdued.
	"labriform": {"tail_amp": 0.18, "body_amp": 0.04, "body_phase": PI,
		"head_amp": 0.0, "head_phase": 0.0, "pec_amp": 1.05,
		"pec_freq_base": 5.5, "pec_freq_speed": 4.5},
	# Tuna cruiser: stiff body, narrow fast tail.
	"thunniform": {"tail_amp": 0.25, "body_amp": 0.03, "body_phase": PI,
		"head_amp": 0.0, "head_phase": 0.0, "pec_amp": 0.30,
		"pec_freq_base": 4.5, "pec_freq_speed": 3.0},
}

static var _profiles: Dictionary = {}
static var _loaded: bool = false


static func get_profile(locomotion_type: String) -> Dictionary:
	if not _loaded:
		reload_data()
	return _profiles.get(locomotion_type, _profiles["subcarangiform"])


# Defaults, then any JSON overrides. Returns the number of overridden types.
static func reload_data() -> int:
	_profiles = {}
	for k in DEFAULTS:
		_profiles[k] = (DEFAULTS[k] as Dictionary).duplicate()
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (parsed is Dictionary):
		push_warning("FishMotionProfiles: %s is not a JSON object; using defaults" % DATA_PATH)
		return 0
	var n: int = 0
	var data: Dictionary = parsed
	for type_name in data:
		var over: Variant = data[type_name]
		if not (over is Dictionary) or String(type_name).begins_with("_"):
			continue
		var base: Dictionary = (_profiles.get(type_name, DEFAULTS["subcarangiform"]) as Dictionary).duplicate()
		for field in over:
			var key: String = String(field)
			var v: float = float(over[field])
			if key.ends_with("_pi"):
				key = key.trim_suffix("_pi")
				v *= PI
			if base.has(key):
				base[key] = v
		_profiles[type_name] = base
		n += 1
	return n
