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
const TankSizing := preload("res://scripts/tank_sizing.gd")
const W_MIN := TankSizing.W_MIN
const W_MAX := TankSizing.W_MAX
const D_MIN := TankSizing.D_MIN
const D_MAX := TankSizing.D_MAX
const H_MIN := TankSizing.H_MIN
const H_MAX := TankSizing.H_MAX
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
# Long / far-camera tanks: authored radius + half-span exceeds the legacy
# MeshInstance LOD floor of 22 (HOLISTIC #040 / Iwagumi flash).
const LONG_CAMERA_IDS: Array[String] = [
	"iwagumi", "dutch_competition", "hex_jungle",
]
const LEGACY_MI_LOD_END := 22.0
# Keys handled by apply_scenario hooks rather than cfg.set (not TankConfig fields).
const APPLY_HOOK_KEYS: Array[String] = [
	"vessel_preset", "lighting_preset", "film_stock",
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
			if String(key) in APPLY_HOOK_KEYS:
				continue
			t.check(String(key) in cfg_probe,
				"%s config key '%s' is a real TankConfig property" % [sid, key])
		if config.has("film_stock"):
			var stock: String = String(config["film_stock"])
			t.check(Cfg.FILM_STOCKS.has(stock),
				"%s film_stock '%s' exists in FILM_STOCKS" % [sid, stock])
		if config.has("lighting_preset"):
			var light: String = String(config["lighting_preset"])
			t.check(Cfg.LIGHTING_PRESETS.has(light),
				"%s lighting_preset '%s' exists" % [sid, light])

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

		# --- long tanks must not rely on MeshInstance LOD @ 22 -----------
		if sid in LONG_CAMERA_IDS:
			var half_span: float = maxf(
				float(config.get("tank_half_w", 0.0)),
				float(config.get("tank_half_d", 0.0)))
			var far_corner: float = float(config.get("camera_radius", 0.0)) + half_span
			t.check(far_corner > LEGACY_MI_LOD_END,
				"%s far corner %.1f exceeds legacy MI LOD %.0f (flash class)"
				% [sid, far_corner, LEGACY_MI_LOD_END])

	# Aquarium fauna never distance-culls MeshInstances; pond still does.
	TopdownMotion.pond_active = false
	t.approx(Fish.mesh_lod_range_end(), 0.0,
		"aquarium MeshInstance LOD disabled (never cull)")
	TopdownMotion.pond_active = true
	t.check(Fish.mesh_lod_range_end() > LEGACY_MI_LOD_END,
		"pond MeshInstance LOD still distance-culls detail")
	TopdownMotion.pond_active = false

	cfg_probe.free()
	quit(t.finish())
