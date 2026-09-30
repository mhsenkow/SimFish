extends SceneTree
# TankSizing contract: templates sit on one scale, stocking/plant fill grow
# with the tank from the size a template was authored at, and the hero
# camera radius frames height as well as width.

const TankSizing := preload("res://scripts/tank_sizing.gd")
const Picker := preload("res://scripts/scenario_picker.gd")


class FakeCfg:
	extends RefCounted
	var tank_shape: String = "box"
	var tank_half_w: float = 8.0
	var tank_half_d: float = 4.0
	var tank_height: float = 7.0
	var stocking_ref_dims: Vector3 = Vector3.ZERO


func _initialize() -> void:
	var t := TestSupport.Suite.new("smoke_tank_sizing")
	var cfg := FakeCfg.new()

	# --- No reference size = no scaling (old saves, template-less tanks) ---
	t.approx(TankSizing.stocking_scale(cfg), 1.0, "no ref dims -> stocking x1", 0.0001)
	t.approx(TankSizing.plant_fill_scale(cfg), 1.0, "no ref dims -> plants x1", 0.0001)
	t.approx(TankSizing.stocking_scale(null), 1.0, "null cfg -> stocking x1", 0.0001)

	# --- Same size as authored = unchanged ---
	cfg.stocking_ref_dims = Vector3(8.0, 4.0, 7.0)
	t.approx(TankSizing.stocking_scale(cfg), 1.0, "authored size -> stocking x1", 0.0001)

	# --- 1.25x linear -> volume^(2/3) and floor-area growth ---
	cfg.tank_half_w = 10.0
	cfg.tank_half_d = 5.0
	cfg.tank_height = 8.75
	t.approx(TankSizing.stocking_scale(cfg), 1.5625, "1.25x linear -> 1.5625x stock", 0.001)
	t.approx(TankSizing.plant_fill_scale(cfg), 1.5625, "1.25x linear -> 1.5625x plants", 0.001)
	t.equals(TankSizing.scale_count(14, 1.5625), 22, "a school of 14 grows to 22")
	t.equals(TankSizing.scale_count(1, 1.8), 1, "a single betta stays single")
	t.equals(TankSizing.scale_count(2, 1.8), 2, "a pair stays a pair")
	t.equals(TankSizing.scale_count(0, 1.8), 0, "zero stays zero")

	# --- Clamped both ways ---
	cfg.tank_half_w = 40.0
	t.check(TankSizing.stocking_scale(cfg) <= TankSizing.STOCK_SCALE_MAX + 0.0001, "stock scale capped")
	cfg.tank_half_w = 1.0
	t.check(TankSizing.stocking_scale(cfg) >= TankSizing.STOCK_SCALE_MIN - 0.0001, "stock scale floored")

	# --- Palette scaling covers implicit 1.0 keys ---
	var pal: Dictionary = TankSizing.scaled_palette({"valli": 0.5}, 2.0)
	t.approx(float(pal["valli"]), 1.0, "explicit palette key scales", 0.0001)
	t.approx(float(pal["carpet"]), 2.0, "missing palette key scales from 1.0", 0.0001)

	# --- Camera fit: calibrated, monotonic, height-aware ---
	var base: float = TankSizing.fit_radius(8.0, 4.0, 7.0, 55.0, 16.0 / 9.0, -0.42, 0.18)
	t.in_range(base, 14.0, 17.0, "classic 8x4x7 box keeps ~the old 15.5 hero radius")
	var tall: float = TankSizing.fit_radius(6.0, 4.0, 22.0, 55.0, 16.0 / 9.0, -0.42, 0.18)
	var short: float = TankSizing.fit_radius(6.0, 4.0, 7.0, 55.0, 16.0 / 9.0, -0.42, 0.18)
	t.check(tall > short * 1.5, "a tall tank pulls the camera back (%.1f vs %.1f)" % [tall, short])
	var portrait: float = TankSizing.fit_radius(8.0, 4.0, 7.0, 55.0, 9.0 / 16.0, -0.42, 0.18)
	t.check(portrait > base, "a portrait viewport needs more distance for the same width")

	# --- Every template: on one scale, authored ref smaller, fits the camera ---
	for sc in Picker.SCENARIOS:
		var config: Dictionary = sc.get("config", {})
		var sid: String = String(sc.get("id", "?"))
		t.check(config.has("stocking_ref_dims"), "%s records its authored size" % sid)
		var ref: Vector3 = config.get("stocking_ref_dims", Vector3.ZERO)
		var hw: float = float(config["tank_half_w"])
		var hd: float = float(config["tank_half_d"])
		var h: float = float(config["tank_height"])
		var lin: float = pow((hw * hd * h) / maxf(0.001, ref.x * ref.y * ref.z), 1.0 / 3.0)
		t.in_range(lin, 1.15, 1.35, "%s grew ~SIZE_SCALE (%.2fx)" % [sid, lin])
		var r: float = TankSizing.fit_radius(hw, hd, h, 50.0, 16.0 / 9.0, -0.42, 0.18)
		t.in_range(r, CameraController.MIN_RADIUS, CameraController.MAX_RADIUS,
			"%s hero radius fits the orbit range (%.1f)" % [sid, r])
		t.check(h * 0.36 <= CameraController.TARGET_MAX.y,
			"%s optical centre is inside the target clamp" % sid)
	var cap: String = TankSizing.size_caption("box", 12.5, 7.0, 10.0)
	t.check(cap.begins_with("25 x 14 x 10") and cap.contains("gal"), "size caption reads '%s'" % cap)

	# --- Picker size step: apply_scenario rescales the glass, keeps the ref ---
	var cfg_node: Node = load("res://scripts/tank_config.gd").new()
	var walstad: Dictionary = {}
	for sc in Picker.SCENARIOS:
		if String(sc.get("id", "")) == "walstad":
			walstad = sc.duplicate(true)
	t.check(not walstad.is_empty(), "walstad template exists")
	walstad["size_scale"] = 1.2
	Picker.apply_scenario(walstad, cfg_node)
	t.approx(float(cfg_node.get("tank_half_w")), 15.0, "Large walstad is 1.2x wide", 0.01)
	t.approx(float(cfg_node.get("tank_height")), 12.0, "Large walstad is 1.2x tall", 0.01)
	var kept: Vector3 = cfg_node.get("stocking_ref_dims")
	t.check(kept.is_equal_approx(Vector3(10.0, 5.5, 8.0)), "authored ref survives the size step")
	t.check(TankSizing.stocking_scale(cfg_node) > 1.8 - 0.001, "Large walstad stocks at the cap")
	var iwagumi: Dictionary = {}
	for sc in Picker.SCENARIOS:
		if String(sc.get("id", "")) == "iwagumi":
			iwagumi = sc.duplicate(true)
	iwagumi["size_scale"] = 1.4
	Picker.apply_scenario(iwagumi, cfg_node)
	t.check(float(cfg_node.get("tank_half_w")) * 2.0 <= TankSizing.W_MAX + 0.001,
		"Grand iwagumi stays inside the width slider")
	cfg_node.free()

	quit(t.finish())
