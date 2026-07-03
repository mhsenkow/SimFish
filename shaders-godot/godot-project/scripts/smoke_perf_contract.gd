extends SceneTree

# PERFORMANCE_UNTHROTTLED #100 — automated 150-fish contract receipt (headless).

const SimDriver = preload("res://scripts/sim_driver.gd")
const _MindTickScript = preload("res://scripts/mind_tick.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var ms50: float = _measure_sim_tick_ms(root, 50)
	var ms150: float = _measure_sim_tick_ms(root, 150)
	if ms150 > ms50 * 4.5:
		failed.append("150-fish tick within 4.5× 50-fish baseline (%.1f vs %.1f ms)" % [ms150, ms50])
	if ms150 > 490.0:
		failed.append("150-fish tick under CI ceiling (%.1f ms)" % ms150)
	PerfGovernor.record_ledger(100, int(ms150 * 1000.0), int(ms50 * 1000.0))
	var hz: float = _MindTickScript.achieved_hz_per_fish()
	if hz < 0.0:
		failed.append("mind Hz stats available")
	if failed.is_empty():
		print("[smoke] perf_contract OK (150-fish %.1f ms, 50-fish %.1f ms, %.1f Hz/fish)" % [
			ms150, ms50, hz])
		quit(0)
	for e in failed:
		push_error("[smoke] perf_contract FAIL: %s" % e)
	quit(1)


static func _measure_sim_tick_ms(tree_root: Node, n_fish: int) -> float:
	var cfg: Node = tree_root.get_node_or_null("/root/TankConfig")
	var prev_brain: Variant = null
	if cfg != null and cfg.get("mind_brain_threads") != null:
		prev_brain = cfg.mind_brain_threads
		cfg.mind_brain_threads = false
	var sim: SimDriver = SimDriver.new()
	tree_root.add_child(sim)
	for i in n_fish:
		var fish: Fish = Fish.new()
		tree_root.add_child(fish)
		fish.id = "contract_%d_%d" % [n_fish, i]
		fish.position = Vector3(
			randf_range(-6.0, 6.0), randf_range(2.0, 6.0), randf_range(-3.0, 3.0))
		fish.maturity = Fish.MATURITY_ADULT
		sim.register_fish(fish)
	for _w in 12:
		sim._tick(SimDriver.SIM_DT)
	var total_usec: int = 0
	const SAMPLES: int = 8
	for _s in SAMPLES:
		var t0: int = Time.get_ticks_usec()
		sim._tick(SimDriver.SIM_DT)
		total_usec += Time.get_ticks_usec() - t0
	sim.queue_free()
	if prev_brain != null and cfg != null:
		cfg.mind_brain_threads = prev_brain
	return float(total_usec) / float(SAMPLES) / 1000.0
