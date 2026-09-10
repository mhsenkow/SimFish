extends SceneTree

const PlantScript := preload("res://scripts/plant.gd")

func _initialize() -> void:
	await process_frame
	var p: Plant = PlantScript.new()
	root.add_child(p)
	p.init(0, {
		"bulb_photoperiod_min": 0.4, "bulb_photoperiod_max": 0.7,
		"bulb_temp_min": 0.45, "bulb_temp_max": 0.65,
		"bulb_max_dormancy_s": 300.0,
	})
	p._dormant_timer = 150.0
	var rich: float = SubstrateGrid.NUTRIENT_BASELINE + 0.2
	if p._bulb_wake_allowed(0.2, 0.55, rich):
		return _fail("photoperiod gate ignored")
	if not p._bulb_wake_allowed(0.5, 0.55, rich):
		return _fail("valid wake window rejected")
	p._dormant_timer = 301.0
	if not p._bulb_wake_allowed(0.0, 0.0, 0.0):
		return _fail("maximum dormancy safety valve failed")
	var legacy: Plant = PlantScript.new()
	root.add_child(legacy)
	legacy.init(0, {})
	legacy._dormant_timer = 120.0
	if not legacy._bulb_wake_allowed(0.0, 0.0, rich):
		return _fail("legacy rich-substrate fallback changed")
	print("SMOKE_PLANT_GROWTH_37_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
