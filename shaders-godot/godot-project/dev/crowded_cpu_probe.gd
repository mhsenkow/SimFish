extends SceneTree

# Fixed crowded populations, real simulation and stage timings, no renderer.
func _initialize() -> void:
	await process_frame
	var cfg: Node = root.get_node("TankConfig")
	cfg.set("capture_mode", true)
	# Explicit mode: headless previously forced threads on even when this
	# probe requested false. Default true retains the original measured mode.
	var threads: bool = OS.get_environment("CROWDED_PROBE_THREADS") != "0"
	cfg.set("mind_brain_threads", threads)
	var reports: Array = []
	for count in [50, 150, 300]:
		seed(0xF15C)
		var sim := SimDriver.new()
		root.add_child(sim)
		var fixtures: Array[Fish] = []
		for i in count:
			var f := Fish.new()
			root.add_child(f)
			f.id = "crowded_%d_%d" % [count, i]
			f.position = Vector3(randf_range(-6, 6), randf_range(2, 6), randf_range(-3, 3))
			f.maturity = Fish.MATURITY_ADULT
			sim.register_fish(f)
			fixtures.append(f)
		for _w in 12:
			sim._tick(SimDriver.SIM_DT)
		sim.tick_profile.clear()
		Fish.life_profile.clear()
		var times: Array[float] = []
		for _sample in 12:
			var start := Time.get_ticks_usec()
			sim._tick(SimDriver.SIM_DT)
			times.append(float(Time.get_ticks_usec() - start) / 1000.0)
		times.sort()
		var row: Dictionary = {"fish": count, "threads": MindBrainPool.enabled(),
			"p50_ms": times[6], "p95_ms": times[11],
			"stages": _means(sim.tick_profile), "life": _means(Fish.life_profile)}
		reports.append(row)
		print(JSON.stringify(row))
		MindBrainPool.reset_for_test()
		for f in fixtures:
			f.free()
		sim.free()
	var path := OS.get_environment("CROWDED_PROBE_OUT")
	if not path.is_empty():
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(reports, "\t"))
	quit()

func _means(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in profile:
		var value: Vector2i = profile[key]
		result[key] = float(value.x) / maxf(1.0, float(value.y)) / 1000.0
	return result
