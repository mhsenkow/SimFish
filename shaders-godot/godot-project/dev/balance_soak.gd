# Headless long-run ecology soak test (scene entry — autoloads load before scripts compile).
#
# Run:
#   godot --headless --path shaders-godot/godot-project res://dev/balance_soak.tscn
#
# Env:
#   BALANCE_DAYS=5          sim-days per case (default 3)
#   BALANCE_MODE=presets    presets (default) | scenarios | all
#   BALANCE_PRESET=reef     run a single preset slug (presets mode)
#   BALANCE_SCENARIO=walstad run a single scenario id (scenarios mode)
#   BALANCE_SEED=0xCAFE     RNG seed (default 0xBA1A4CE)
#   BALANCE_VERBOSE=1       print per-sample lines

extends Node

const DEFAULT_TICK_DT: float = 0.5
const SAMPLE_INTERVAL_S: float = 216.0  # sample 4× per sim-day (catches dawn O2 trough)
const SOAK_TIME_SCALE: float = 64.0

const CASES: Array[Dictionary] = [
	{"preset": "classic_community", "substrate": "aquasoil", "label": "Classic community"},
	{"preset": "community", "substrate": "aquasoil", "label": "Community (balanced)"},
	{"preset": "tetra_school", "substrate": "aquasoil", "label": "Tetra school"},
	{"preset": "iwagumi_school", "substrate": "sand", "label": "Iwagumi school"},
	{"preset": "reef", "substrate": "ocean_sand", "label": "Reef (saltwater)", "is_reef": true},
	{"preset": "polyp_lab", "substrate": "eco_complete", "label": "Polyp lab (fishless)", "fishless": true},
]


class BalanceSample:
	var sim_day: float
	var o2: float
	var stability: float
	var fish: int
	var shrimp: int
	var plant_biomass: int
	var floater_cov: float
	var floater_n: int
	var bleach: float
	var nh3: float
	var no2: float
	var no3: float
	var bloom: float


class BalanceReport:
	var preset: String
	var label: String
	var duration_s: float
	var samples: Array[BalanceSample] = []
	var initial_fauna: int = 0
	var initial_biomass: int = 0
	var failures: PackedStringArray = []

	func min_o2() -> float:
		var m: float = 99.0
		for s in samples:
			m = minf(m, s.o2)
		return m if m < 99.0 else 0.0

	func mean_o2() -> float:
		if samples.is_empty():
			return 0.0
		var sum: float = 0.0
		for s in samples:
			sum += s.o2
		return sum / float(samples.size())

	func max_bleach() -> float:
		var m: float = 0.0
		for s in samples:
			m = maxf(m, s.bleach)
		return m

	func final_fauna() -> int:
		if samples.is_empty():
			return 0
		return samples[-1].fish + samples[-1].shrimp

	func low_o2_fraction(threshold: float) -> float:
		if samples.is_empty():
			return 1.0
		var n: int = 0
		for s in samples:
			if s.o2 < threshold:
				n += 1
		return float(n) / float(samples.size())

	func evaluate(case: Dictionary) -> void:
		var is_reef: bool = bool(case.get("is_reef", false))
		var fishless: bool = bool(case.get("fishless", false))
		var o2_floor: float = 0.30 if is_reef else 0.28
		if min_o2() < o2_floor:
			failures.append(
				"O2 floor %.2f < %.2f (mean %.2f)" % [min_o2(), o2_floor, mean_o2()])
		if low_o2_fraction(o2_floor + 0.05) > 0.45:
			failures.append(
				"O2 below %.2f for %.0f%% of samples" % [
					o2_floor + 0.05, low_o2_fraction(o2_floor + 0.05) * 100.0])
		if not fishless and initial_fauna >= 8:
			if final_fauna() < int(maxf(4.0, float(initial_fauna) * 0.35)):
				failures.append(
					"fauna collapse %d -> %d (started %d)" % [
						initial_fauna, final_fauna(), initial_fauna])
		if initial_biomass > 40 and not samples.is_empty():
			if samples[-1].plant_biomass < int(float(initial_biomass) * 0.12):
				failures.append(
					"plant biomass collapse %d -> %d" % [initial_biomass, samples[-1].plant_biomass])
		if is_reef and max_bleach() > 0.72:
			failures.append("reef bleach peak %.2f > 0.72" % max_bleach())
		var high_mat: int = 0
		for s in samples:
			if s.sim_day >= 1.0 and s.floater_cov > 0.92:
				high_mat += 1
		if samples.size() > 10 and float(high_mat) / float(samples.size()) > 0.35:
			failures.append("floater mat >92%% coverage too often (%d/%d samples)" % [
				high_mat, samples.size()])
		var crash_n: int = 0
		for s in samples:
			if s.sim_day >= 1.5 and s.stability < 0.28:
				crash_n += 1
		if samples.size() > 10 and float(crash_n) / float(samples.size()) > 0.40:
			failures.append("stability crash (<0.28) on %.0f%% of late samples" % [
				float(crash_n) / float(samples.size()) * 100.0])


var _world_script: Script
var _sim_day_s: float = 864.0
var _verbose: bool = false
var _days: float = 3.0
var _seed: int = 0xBA1A4CE
var _tick_dt: float = DEFAULT_TICK_DT
var _only_preset: String = ""
var _only_scenario: String = ""
var _mode: String = "presets"


func _scenario_cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sc in ScenarioPicker.SCENARIOS:
		if bool(sc.get("is_wildcard", false)):
			continue
		var config: Dictionary = sc.get("config", {})
		var preset: String = String(config.get("tank_preset", ""))
		var stocking: Dictionary = TankConfig.TANK_PRESETS.get(preset, {}).get("stocking", {})
		var fish_n: int = 0
		for k in stocking.keys():
			if String(k) != "shrimp":
				fish_n += int(stocking[k])
		out.append({
			"scenario_id": String(sc.id),
			"label": String(sc.name),
			"scenario": sc,
			"preset": preset,
			"is_reef": String(config.get("substrate_type", "")) == "ocean_sand",
			"fishless": fish_n == 0,
		})
	return out


func _cases_for_mode() -> Array[Dictionary]:
	match _mode:
		"scenarios":
			return _scenario_cases()
		"all":
			var merged: Array[Dictionary] = []
			merged.append_array(CASES)
			merged.append_array(_scenario_cases())
			return merged
		_:
			return CASES


func _ready() -> void:
	_world_script = load("res://scripts/world.gd")
	_sim_day_s = WaterChemistry.SIM_DAY_S
	_read_env()
	await get_tree().process_frame
	var cfg := get_node_or_null("/root/TankConfig")
	var saves := get_node_or_null("/root/TankSaves")
	if cfg == null:
		push_error("[balance] TankConfig autoload missing")
		get_tree().quit(1)
		return
	var failed: Array[String] = []
	var ran: int = 0
	for case in _cases_for_mode():
		var preset: String = String(case.get("preset", case.get("scenario_id", "")))
		if _only_preset != "" and preset != _only_preset:
			continue
		if _only_scenario != "" and String(case.get("scenario_id", "")) != _only_scenario:
			continue
		ran += 1
		print("[balance] --- %s (%s) %.1f sim-days seed=%d ---" % [
			case.label, preset, _days, _seed])
		var report: BalanceReport = await _run_case(cfg, saves, case)
		var case_key: String = String(case.get("scenario_id", case.get("preset", preset)))
		if report.failures.is_empty():
			var end_day: float = 0.0
			if not report.samples.is_empty():
				end_day = report.samples[-1].sim_day
			print("[balance] PASS %s | age %.1f->%.1f d n=%d O2 min/mean=%.2f/%.2f fauna %d->%d bio %d->%d floaters %.0f%% bleach %.2f" % [
				case_key,
				report.samples[0].sim_day if not report.samples.is_empty() else 0.0,
				end_day,
				report.samples.size(),
				report.min_o2(),
				report.mean_o2(),
				report.initial_fauna,
				report.final_fauna(),
				report.initial_biomass,
				report.samples[-1].plant_biomass if not report.samples.is_empty() else 0,
				(report.samples[-1].floater_cov * 100.0) if not report.samples.is_empty() else 0.0,
				report.max_bleach(),
			])
		else:
			for f in report.failures:
				push_error("[balance] FAIL %s: %s" % [case_key, f])
			failed.append(case_key)
	if ran == 0:
		push_error("[balance] no cases matched mode=%s preset=%s scenario=%s" % [
			_mode, _only_preset, _only_scenario])
		get_tree().quit(1)
		return
	if failed.is_empty():
		print("[balance] OK — %d case(s) stable for %.1f sim-days each" % [ran, _days])
		get_tree().quit(0)
	else:
		print("[balance] FAILED presets: %s" % ", ".join(failed))
		get_tree().quit(1)


func _read_env() -> void:
	var days_env: String = OS.get_environment("BALANCE_DAYS")
	if days_env != "" and days_env.is_valid_float():
		_days = maxf(1.0, float(days_env))
	var dt_env: String = OS.get_environment("BALANCE_TICK_DT")
	if dt_env != "" and dt_env.is_valid_float():
		_tick_dt = maxf(0.1, float(dt_env))
	_only_preset = OS.get_environment("BALANCE_PRESET")
	_only_scenario = OS.get_environment("BALANCE_SCENARIO")
	var mode_env: String = OS.get_environment("BALANCE_MODE")
	if mode_env != "":
		_mode = mode_env
	var seed_env: String = OS.get_environment("BALANCE_SEED")
	if seed_env != "":
		_seed = seed_env.hash() if not seed_env.is_valid_int() else int(seed_env)
	_verbose = OS.get_environment("BALANCE_VERBOSE") == "1"


func _run_case(cfg: Node, saves: Node, case: Dictionary) -> BalanceReport:
	var report := BalanceReport.new()
	report.preset = String(case.get("scenario_id", case.get("preset", "")))
	report.label = String(case.label)
	report.duration_s = _days * _sim_day_s

	if saves != null and saves.has_method("clear_active_state"):
		saves.clear_active_state()
	cfg.reset_to_defaults()
	if case.has("scenario"):
		ScenarioPicker.apply_scenario(case.scenario, cfg)
	else:
		cfg.tank_preset = String(case.preset)
		cfg.substrate_type = String(case.get("substrate", "aquasoil"))
		var cycle_override: String = OS.get_environment("BALANCE_CYCLE")
		if cycle_override != "":
			cfg.cycle_start_mode = cycle_override
		else:
			cfg.cycle_start_mode = "established"
		cfg.start_matured = (cfg.cycle_start_mode == "established")
		cfg.aeration_type = "disk"
		cfg.aeration_strength = 0.6
		if bool(case.get("is_reef", false)):
			cfg.light_warmth = 0.52
	cfg.auto_respawn_fauna = true
	cfg.auto_feed_fauna = false
	cfg.day_cycle_enabled = true
	cfg.day_length_s = 360.0

	var world: Node3D = _world_script.new() as Node3D
	world.name = "BalanceWorld_" + report.preset
	get_tree().root.add_child(world)
	# Don't advance ecology while async stocking is still running.
	if world.sim != null:
		world.sim.set_physics_process(false)

	var ready: bool = await _wait_world_ready(world, 1200)
	if not ready:
		report.failures.append("world failed to finish stocking within frame budget")
		world.queue_free()
		await get_tree().process_frame
		return report

	var sim: Node = world.sim
	seed(_seed)
	sim.tank_seed = _seed

	report.initial_fauna = sim.fish.size() + sim.shrimp.size()
	for p in sim.plants:
		if is_instance_valid(p) and p.has_method("biomass"):
			report.initial_biomass += int(p.biomass())

	_soak(world, sim, report)
	print("[balance] soaked %s to sim-day %.2f (%d samples)" % [
		report.preset, report.samples[-1].sim_day if not report.samples.is_empty() else 0.0,
		report.samples.size()])
	world.queue_free()
	await get_tree().process_frame
	report.evaluate(case)
	return report


func _wait_world_ready(world: Node3D, max_frames: int) -> bool:
	for _i in max_frames:
		await get_tree().process_frame
		if not is_instance_valid(world):
			return false
		if not world.is_node_ready():
			continue
		var sim: Node = world.get("sim")
		if sim == null:
			continue
		var has_flora: bool = sim.plants.size() > 0
		var has_fauna: bool = sim.fish.size() > 0 or sim.shrimp.size() > 0
		if has_flora or has_fauna:
			for _j in 10:
				await get_tree().process_frame
			return true
	return false


func _soak(world: Node3D, sim: Node, report: BalanceReport) -> void:
	var target_age: float = float(sim.tank_age_s) + report.duration_s
	var sample_next: float = float(sim.tank_age_s) + SAMPLE_INTERVAL_S
	var floater_accum: float = 0.0
	var cfg := get_node_or_null("/root/TankConfig")
	var cycle_len: float = 360.0
	if cfg != null:
		cycle_len = maxf(15.0, float(cfg.day_length_s))
	var is_salt: bool = false
	if world.get("_active_substrate_profile") != null:
		is_salt = bool(world._active_substrate_profile.get("is_saltwater", false))
	var tick_n: int = 0
	_record_sample(sim, world, float(sim.tank_age_s), report)
	while float(sim.tank_age_s) < target_age:
		sim.day_phase = fposmod(float(sim.day_phase) + _tick_dt / cycle_len, 1.0)
		sim._tick(_tick_dt)
		floater_accum += _tick_dt
		if floater_accum >= 3.0:
			floater_accum = 0.0
			if world.has_method("_floater_growth_step"):
				world._floater_growth_step()
			if world.has_method("_drift_floaters"):
				world._drift_floaters(minf(_tick_dt, 0.1))
		if is_salt:
			var rt: float = float(world.get("_coral_recruit_timer"))
			rt = maxf(0.0, rt - _tick_dt)
			world.set("_coral_recruit_timer", rt)
			if rt <= 0.0:
				world.set("_coral_recruit_timer", randf_range(22.0, 42.0))
				if world.has_method("_maybe_recruit_coral"):
					world._maybe_recruit_coral()
		if float(sim.tank_age_s) >= sample_next:
			_record_sample(sim, world, float(sim.tank_age_s), report)
			sample_next += SAMPLE_INTERVAL_S
		tick_n += 1
		if tick_n % 8000 == 0:
			await get_tree().process_frame
	_record_sample(sim, world, float(sim.tank_age_s), report)


func _record_sample(sim: Node, world: Node3D, age_s: float, report: BalanceReport) -> void:
	var s := BalanceSample.new()
	s.sim_day = age_s / _sim_day_s
	s.o2 = float(sim.dissolved_o2)
	s.stability = float(sim.stability)
	s.fish = sim.fish.size()
	s.shrimp = sim.shrimp.size()
	s.plant_biomass = 0
	for p in sim.plants:
		if is_instance_valid(p) and p.has_method("biomass"):
			s.plant_biomass += int(p.biomass())
	s.floater_cov = world.floater_coverage() if world.has_method("floater_coverage") else 0.0
	s.floater_n = world.floater_count() if world.has_method("floater_count") else 0
	s.bleach = float(sim._max_reef_bleach()) if sim.has_method("_max_reef_bleach") else 0.0
	if sim.water_chemistry != null:
		s.nh3 = float(sim.water_chemistry.ammonia)
		s.no2 = float(sim.water_chemistry.nitrite)
		s.no3 = float(sim.water_chemistry.nitrate)
	s.bloom = float(sim.bloom_intensity)
	report.samples.append(s)
	if _verbose:
		print("  d=%.2f O2=%.2f stab=%.2f fish=%d shrimp=%d bio=%d fl=%.0f%% bleach=%.2f" % [
			s.sim_day, s.o2, s.stability, s.fish, s.shrimp, s.plant_biomass,
			s.floater_cov * 100.0, s.bleach])
