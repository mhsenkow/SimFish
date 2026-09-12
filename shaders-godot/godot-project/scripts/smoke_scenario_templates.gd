extends SceneTree

# Base-template contract (scenario_picker.gd SCENARIOS).
#
# WHY. These are hand-maintained dictionaries and every mistake in them is
# SILENT. Two templates shipped with vessel_preset ids that do not exist in
# VESSEL_PRESETS ("reef_cube", "nano_cube"); apply_vessel_preset() sets the
# name, finds no such preset, and returns having applied NO dimensions - so
# those tanks quietly inherited whatever size the previous tank had. Nothing
# logged, nothing crashed. Same class of failure for an out-of-range camera
# or a dimension past the Settings sliders: it just clamps and the template
# is not the tank the author described.

const Picker := preload("res://scripts/scenario_picker.gd")
const Cfg := preload("res://scripts/tank_config.gd")

# Settings → Tank sliders (settings_panel.gd). Values are FULL dimensions;
# the config stores half-width and half-depth.
const W_MIN := 4.0
const W_MAX := 24.0
const D_MIN := 2.0
const D_MAX := 14.0
const H_MIN := 4.0
const H_MAX := 20.0
# CameraController bounds.
const RADIUS_MIN := 4.0
const RADIUS_MAX := 55.0
const PITCH_ABS_MAX := 1.45

const CAMERA_KEYS: Array[String] = [
	"camera_yaw", "camera_pitch", "camera_radius", "camera_target_y",
	"camera_fov",
]
const REQUIRED: Array[String] = [
	"tank_preset", "tank_shape", "tank_half_w", "tank_half_d", "tank_height",
	"water_surface_fraction", "substrate_depth_fraction", "cycle_start_mode",
	"vessel_preset",
]


func _init() -> void:
	var t := TestSupport.Suite.new("scenario_templates")

	var scenarios: Array = Picker.SCENARIOS
	t.check(scenarios.size() >= 16, "all templates present, got %d" % scenarios.size())

	var cfg_probe := Cfg.new()
	var seen_cameras: Dictionary = {}
	var ids: Dictionary = {}

	for sc in scenarios:
		var sid: String = String(sc.get("id", "?"))
		var config: Dictionary = sc.get("config", {})
		t.check(not ids.has(sid), "template id is unique: %s" % sid)
		ids[sid] = true

		# --- every template fully specifies its tank ---------------------
		for key in REQUIRED:
			t.check(config.has(key), "%s declares %s" % [sid, key])

		# --- a named vessel must actually exist --------------------------
		# This is the bug that shipped.
		var vp: String = String(config.get("vessel_preset", "custom"))
		t.check(vp == "custom" or Cfg.VESSEL_PRESETS.has(vp),
			"%s vessel_preset '%s' exists in VESSEL_PRESETS" % [sid, vp])

		# --- every config key must be a real TankConfig property ---------
		for key in config.keys():
			t.check(String(key) in cfg_probe,
				"%s config key '%s' is a real TankConfig property" % [sid, key])

		# --- dimensions inside the Settings sliders ----------------------
		var w: float = float(config.get("tank_half_w", 0.0)) * 2.0
		var d: float = float(config.get("tank_half_d", 0.0)) * 2.0
		var h: float = float(config.get("tank_height", 0.0))
		t.in_range(w, W_MIN, W_MAX, "%s width fits the slider" % sid)
		t.in_range(d, D_MIN, D_MAX, "%s depth fits the slider" % sid)
		t.in_range(h, H_MIN, H_MAX, "%s height fits the slider" % sid)

		# --- regular shapes must be square in plan -----------------------
		var shape: String = String(config.get("tank_shape", "box"))
		if shape in ["cube", "sphere", "cylinder", "hex"]:
			t.approx(float(config["tank_half_w"]), float(config["tank_half_d"]),
				"%s is a %s so its footprint is square" % [sid, shape], 0.001)

		# --- water line sane ---------------------------------------------
		var wsf: float = float(config.get("water_surface_fraction", 0.0))
		t.in_range(wsf, 0.80, 0.99, "%s water surface fraction sane" % sid)
		var sdf: float = float(config.get("substrate_depth_fraction", 0.0))
		t.in_range(sdf, 0.05, 0.45, "%s substrate depth sane" % sid)
		t.check(sdf < wsf, "%s substrate sits below the water line" % sid)

		# --- camera present, in range, and DISTINCT ----------------------
		for key in CAMERA_KEYS:
			t.check(config.has(key), "%s sets %s" % [sid, key])
		t.in_range(float(config.get("camera_radius", 0.0)),
			RADIUS_MIN, RADIUS_MAX, "%s camera radius in range" % sid)
		t.in_range(float(config.get("camera_pitch", 99.0)),
			-PITCH_ABS_MAX, PITCH_ABS_MAX, "%s camera pitch in range" % sid)
		t.in_range(float(config.get("camera_fov", 0.0)), 20.0, 90.0,
			"%s camera fov sane" % sid)
		# The camera must actually frame the tank rather than sit inside it.
		var span: float = maxf(w, d)
		t.check(float(config.get("camera_radius", 0.0)) > span * 0.5,
			"%s camera is outside the glass (radius %.1f vs span %.1f)"
			% [sid, float(config.get("camera_radius", 0.0)), span])
		# And it must be looking at water, not at the lid or the stand.
		t.in_range(float(config.get("camera_target_y", -1.0)), 0.5, h,
			"%s camera target is inside the tank" % sid)

		var fingerprint: String = "%.2f|%.2f|%.1f|%.1f|%.1f" % [
			float(config.get("camera_yaw", 0.0)),
			float(config.get("camera_pitch", 0.0)),
			float(config.get("camera_radius", 0.0)),
			float(config.get("camera_target_y", 0.0)),
			float(config.get("camera_fov", 0.0))]
		t.check(not seen_cameras.has(fingerprint),
			"%s has its own camera (clashes with %s)"
			% [sid, String(seen_cameras.get(fingerprint, ""))])
		seen_cameras[fingerprint] = sid

		# --- referenced tank preset exists -------------------------------
		var tp: String = String(config.get("tank_preset", ""))
		t.check(Cfg.TANK_PRESETS.has(tp),
			"%s tank_preset '%s' exists" % [sid, tp])

		# --- starts playable ---------------------------------------------
		t.equals(String(config.get("cycle_start_mode", "")), "established",
			"%s starts on an established cycle" % sid)

	cfg_probe.free()
	quit(t.finish())
