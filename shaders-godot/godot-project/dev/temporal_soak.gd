# Temporal soak — does the tank still feel good after 1 min, 5 min, 1 h,
# 6 h and a day of being left running?
#
#   scripts/dev_run.sh --path shaders-godot/godot-project --headless res://dev/temporal_soak.tscn
#
# Drives the real game (main.tscn) through its own fast-forward path
# (sim.time_scale, the same thing the 16x button does), so fish swim, eat,
# breed and poop on the per-frame path the player sees. At each checkpoint it
# drops to 1x and times real frames, then records the ecology: who is alive,
# what was born and died since the last checkpoint, chemistry, algae, waste,
# soil. Checkpoints are in *player* time at 1x (a day of play = 240 sim days
# at the default 6-minute light cycle).
#
# Headless, so frame times are CPU-only (sim, fish, HUD scripts); GPU cost is
# not measured. "achieved_rate" is the sim-seconds per wall-second the
# fast-forward actually reached: a falling rate is the slowdown itself, since
# the sim drops time once a frame's tick budget is spent.
#
# Environment:
#   TEMPORAL_SCENARIO     scenario id (default walstad)
#   TEMPORAL_CHECKPOINTS  comma list of player-seconds (default 60,300,3600,21600,86400)
#   TEMPORAL_SPEED        fast-forward time_scale (default 16)
#   TEMPORAL_FRAMES       frames timed at 1x per checkpoint (default 240)
#   TEMPORAL_TURBO        1 = fast-forward by stepping sim._tick directly for up
#                         to ~45 ms per frame instead of sim.time_scale. The
#                         game's own path drops time once a frame's tick budget
#                         is spent, so a slow tick caps it near 1x; turbo keeps
#                         every tick (fish still get real frames between).
#   TEMPORAL_OUT          JSON report path (default user://temporal_soak.json)

extends Node

const ScenarioPickerScript = preload("res://scripts/scenario_picker.gd")

const SETTLE_FRAMES: int = 30

var _main: Node = null
var _sim: Node = null
var _world: Node = null
var _cfg: Node = null
var _checkpoints: Array[float] = []
var _speed: float = 16.0
var _measure_frames: int = 240
var _out: String = "user://temporal_soak.json"
var _scenario: String = "walstad"
var _turbo: bool = false
const TURBO_FRAME_USEC: int = 45000

var _next_cp: int = 0
var _phase: int = 0  # 0 boot, 1 fast-forward, 2 settle at 1x, 3 measure at 1x
var _phase_frames: int = 0
var _frame_ms: Array[float] = []
var _tick_ms: Array[float] = []
var _proc_ms: Array[float] = []
var _phys_ms: Array[float] = []
var _last_usec: int = 0
var _boot_frames: int = 0
var _ff_wall_start: int = 0
var _ff_sim_start: float = 0.0
var _rows: Array = []
# Births/deaths by instance id, sampled each second of wall time.
var _seen: Dictionary = {}
var _alive: Dictionary = {}
var _born: Dictionary = {}
var _died: Dictionary = {}
# instance id -> last census snapshot, so a vanished fish can be classified.
var _last_seen: Dictionary = {}
var _death_causes: Dictionary = {}
# Same classification for the cleanup crew ("shrimp:old_age", "snail:starvation").
var _crew_seen: Dictionary = {}
var _crew_causes: Dictionary = {}
var _census_acc: float = 0.0
var _wall_start: int = 0
# Templates start with an established tank_age_s; checkpoints count from boot.
var _age0: float = 0.0


func _ready() -> void:
	_cfg = get_node_or_null("/root/TankConfig")
	if _cfg == null:
		push_error("[temporal] TankConfig autoload missing")
		get_tree().quit(1)
		return
	var saves := get_node_or_null("/root/TankSaves")
	if saves != null and saves.has_method("has_state_for_active_slot") \
			and bool(saves.call("has_state_for_active_slot")):
		push_error("[temporal] active save slot holds a tank; run through scripts/dev_run.sh")
		get_tree().quit(2)
		return
	_cfg.set("capture_mode", true)
	if _cfg.has_method("reset_to_defaults"):
		_cfg.reset_to_defaults()
	_scenario = _env("TEMPORAL_SCENARIO", _scenario)
	for sc in ScenarioPickerScript.SCENARIOS:
		if String(sc.get("id", "")) == _scenario:
			ScenarioPickerScript.apply_scenario(sc, _cfg)
	for part in _env("TEMPORAL_CHECKPOINTS", "60,300,3600,21600,86400").split(",", false):
		_checkpoints.append(part.to_float())
	_speed = _env("TEMPORAL_SPEED", "16").to_float()
	_measure_frames = _env("TEMPORAL_FRAMES", "240").to_int()
	_out = _env("TEMPORAL_OUT", _out)
	_turbo = _env("TEMPORAL_TURBO", "0") == "1"
	process_priority = 1000
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	_wall_start = Time.get_ticks_msec()
	print("[temporal] scenario=", _scenario, " checkpoints=", _checkpoints, " speed=", _speed)


static func _env(key: String, fallback: String) -> String:
	var v: String = OS.get_environment(key).strip_edges()
	return fallback if v.is_empty() else v


func _player_seconds() -> float:
	# Player time at 1x == sim time, since the light cycle and every rate
	# are expressed in sim seconds.
	return float(_sim.get("tank_age_s")) - _age0


func _process(dt: float) -> void:
	if _main == null:
		return
	if bool(_main.get("_focus_paused")) and _main.has_method("_on_focus_in"):
		_main.call("_on_focus_in")
	_main.set("_hud_idle_seconds", 0.0)
	if _sim == null:
		_boot_frames += 1
		var s: Variant = _main.get("_sim")
		var w: Variant = _main.get("world")
		if s is Node and w is Node and bool(w.get("build_complete")):
			_sim = s
			_world = w
			_age0 = float(_sim.get("tank_age_s"))
			_census()
			_begin_ff()
		elif _boot_frames > 6000:
			push_error("[temporal] world never finished building")
			get_tree().quit(1)
		return
	_census_acc += dt
	if _census_acc >= 1.0:
		_census_acc = 0.0
		_census()
	match _phase:
		1:
			if _turbo:
				var before: float = _player_seconds()
				_turbo_step()
				# Per-frame motion (fish/shrimp _process) scales by time_scale;
				# match it to the sim time this frame consumed so animals can
				# still reach food at the accelerated rate.
				_sim.set("time_scale", clampf((_player_seconds() - before) / maxf(dt, 0.001), 0.25, 16.0))
			if _player_seconds() >= _checkpoints[_next_cp]:
				_sim.set_physics_process(true)
				_sim.set("time_scale", 1.0)
				_phase = 2
				_phase_frames = 0
		2:
			_phase_frames += 1
			if _phase_frames >= SETTLE_FRAMES:
				_phase = 3
				_phase_frames = 0
				_frame_ms.clear()
				_tick_ms.clear()
				_proc_ms.clear()
				_phys_ms.clear()
				_last_usec = Time.get_ticks_usec()
				_sim.set("_tick_profile_enabled", true)
				var prof: Variant = _sim.get("tick_profile")
				if prof is Dictionary:
					prof.clear()
		3:
			var now: int = Time.get_ticks_usec()
			_frame_ms.append(float(now - _last_usec) / 1000.0)
			_last_usec = now
			_tick_ms.append(float(int(_sim.get("_last_tick_usec"))) / 1000.0)
			_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			_phase_frames += 1
			if _phase_frames >= _measure_frames:
				_record()
				_next_cp += 1
				if _next_cp >= _checkpoints.size():
					_finish()
					return
				_begin_ff()


# Same accounting as SimDriver._physics_process: day phase consumes exactly
# the time the ecology ticks.
func _turbo_step() -> void:
	var start: int = Time.get_ticks_usec()
	var cycle_len: float = maxf(15.0, float(_cfg.get("day_length_s")))
	var dt: float = SimDriver.SIM_DT
	while Time.get_ticks_usec() - start < TURBO_FRAME_USEC:
		if bool(_cfg.get("day_cycle_enabled")):
			_sim.day_phase = fposmod(float(_sim.day_phase) + dt / cycle_len, 1.0)
		_sim._rebuild_fish_query_grid()
		_sim._tick(dt)
		_sim._stats_timer += dt
		if _sim._stats_timer >= 1.0:
			_sim._stats_timer = 0.0
			_sim._emit_stats()
		if _player_seconds() >= _checkpoints[_next_cp]:
			return


func _begin_ff() -> void:
	_phase = 1
	if _turbo:
		_sim.set_physics_process(false)
	else:
		_sim.set("time_scale", _speed)
	_ff_wall_start = Time.get_ticks_usec()
	_ff_sim_start = _player_seconds()
	_sim.set("_tick_profile_enabled", false)


func _census() -> void:
	var now: Dictionary = {}
	for f in _sim.get("fish"):
		if is_instance_valid(f):
			now[f.get_instance_id()] = String(f.get("species"))
			_last_seen[f.get_instance_id()] = {
				"age_frac": float(f.age) / maxf(1.0, float(f.max_age_s)),
				"hunger": float(f.hunger), "energy": float(f.energy),
				"stress": float(f.stress), "eaten": f.get("_dying") != true,
			}
	for id in now:
		if not _seen.has(id):
			_seen[id] = true
			if not _alive.is_empty() or _rows.size() > 0:
				_born[now[id]] = int(_born.get(now[id], 0)) + 1
	for id in _alive:
		if not now.has(id):
			_died[_alive[id]] = int(_died.get(_alive[id], 0)) + 1
			var snap: Dictionary = _last_seen.get(id, {})
			var cause: String = "other"
			if float(snap.get("age_frac", 0.0)) >= 1.2:
				cause = "old_age"
			elif float(snap.get("hunger", 0.0)) >= 0.85 and float(snap.get("energy", 1.0)) < 0.2:
				cause = "starvation"
			elif float(snap.get("stress", 0.0)) > 0.9:
				cause = "stress"
			elif bool(snap.get("eaten", false)):
				cause = "vanished_alive"  # predation or removal mid-swim
			_death_causes[cause] = int(_death_causes.get(cause, 0)) + 1
			_last_seen.erase(id)
	_alive = now
	_census_crew()


func _census_crew() -> void:
	var crew: Array = []
	for s in _sim.get("shrimp"):
		crew.append(["shrimp", s])
	var sroot: Variant = _sim.get("snails_root")
	if sroot is Node:
		for sn in (sroot as Node).get_children():
			if sn.get("hunger") != null:
				crew.append(["snail", sn])
	var now: Dictionary = {}
	for pair in crew:
		if not is_instance_valid(pair[1]):
			continue
		var c: Object = pair[1]
		var id: int = c.get_instance_id()
		now[id] = {
			"kind": pair[0],
			"age_frac": float(c.get("age")) / maxf(1.0, float(c.get("max_age_s"))),
			"hunger": float(c.get("hunger")), "energy": float(c.get("energy")),
		}
	for id in _crew_seen:
		if now.has(id):
			continue
		var snap: Dictionary = _crew_seen[id]
		var cause: String = "eaten_or_other"
		if float(snap.age_frac) >= 0.95:
			cause = "old_age"
		elif float(snap.energy) < 0.15:
			cause = "starvation"
		var key: String = "%s:%s" % [snap.kind, cause]
		_crew_causes[key] = int(_crew_causes.get(key, 0)) + 1
	_crew_seen = now


static func _pct(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var s: Array[float] = values.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(float(s.size()) * q))]


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var t: float = 0.0
	for v in values:
		t += v
	return t / float(values.size())


static func _grid_mean(grid: Variant) -> float:
	if not (grid is Array):
		return -1.0
	var t: float = 0.0
	var n: int = 0
	for col in grid:
		for v in col:
			t += float(v)
			n += 1
	return t / float(n) if n > 0 else -1.0


func _record() -> void:
	var sim := _sim
	var ff_wall_s: float = float(Time.get_ticks_usec() - _ff_wall_start) / 1000000.0
	var species: Dictionary = {}
	var breed_block: Dictionary = {}
	var hunger_sum: float = 0.0
	var energy_sum: float = 0.0
	var stress_sum: float = 0.0
	var bursting: int = 0
	var maturity: Array = [0, 0, 0, 0]
	for f in sim.get("fish"):
		if is_instance_valid(f):
			var sp: String = String(f.get("species"))
			species[sp] = int(species.get(sp, 0)) + 1
			hunger_sum += float(f.hunger)
			energy_sum += float(f.energy)
			stress_sum += float(f.stress)
			if float(f.burst_remaining) > 0.0:
				bursting += 1
			maturity[clampi(int(f.maturity), 0, 3)] += 1
			if int(f.maturity) == 2:
				var why: String = String(f.breeding_condition_reason())
				if why == "":
					why = "ready"
				breed_block[why] = int(breed_block.get(why, 0)) + 1
	var nf: float = maxf(1.0, float((sim.get("fish") as Array).size()))
	var shrimp_mat: Array = [0, 0, 0, 0]
	var shrimp_energy: float = 0.0
	for sh in sim.get("shrimp"):
		if is_instance_valid(sh):
			shrimp_mat[clampi(int(sh.maturity), 0, 3)] += 1
			shrimp_energy += float(sh.energy)
	var ns: float = maxf(1.0, float((sim.get("shrimp") as Array).size()))
	var snails: int = 0
	var sroot: Variant = sim.get("snails_root")
	if sroot is Node:
		snails = (sroot as Node).get_child_count()
	var biomass: float = 0.0
	for p in sim.get("plants"):
		if is_instance_valid(p) and p.has_method("biomass"):
			biomass += float(p.biomass())
	var chem: Variant = sim.get("water_chemistry")
	var sub: Variant = sim.get("substrate")
	var stages: Dictionary = {}
	var prof: Variant = sim.get("tick_profile")
	if prof is Dictionary:
		for key in prof:
			var v: Vector2i = prof[key]
			stages[key] = snappedf(float(v.x) / maxf(1.0, float(v.y)) / 1000.0, 0.001)
	var row := {
		"checkpoint_s": _checkpoints[_next_cp],
		"sim_age_s": snappedf(_player_seconds(), 0.1),
		"sim_days": snappedf(_player_seconds() / 360.0, 0.01),
		"tank_age_days": snappedf(float(_sim.get("tank_age_s")) / 360.0, 0.01),
		"wall_s": snappedf(float(Time.get_ticks_msec() - _wall_start) / 1000.0, 0.1),
		"achieved_rate": snappedf((_player_seconds() - _ff_sim_start) / maxf(0.001, ff_wall_s), 0.01),
		"frame_ms_mean": snappedf(_mean(_frame_ms), 0.01),
		"frame_ms_p95": snappedf(_pct(_frame_ms, 0.95), 0.01),
		"frame_ms_p99": snappedf(_pct(_frame_ms, 0.99), 0.01),
		"process_ms_mean": snappedf(_mean(_proc_ms), 0.01),
		"physics_ms_mean": snappedf(_mean(_phys_ms), 0.01),
		"tick_ms_mean": snappedf(_mean(_tick_ms), 0.01),
		"tick_ms_p95": snappedf(_pct(_tick_ms, 0.95), 0.01),
		"tick_stages_ms": stages,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"mem_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1),
		"fish": species,
		"fish_total": (sim.get("fish") as Array).size(),
		"born_since_last": _born.duplicate(),
		"died_since_last": _died.duplicate(),
		"death_causes": _death_causes.duplicate(),
		"crew_deaths": _crew_causes.duplicate(),
		"maturity": maturity,
		"adult_breed_block": breed_block,
		"fish_hunger": snappedf(hunger_sum / nf, 0.01),
		"fish_energy": snappedf(energy_sum / nf, 0.01),
		"fish_stress": snappedf(stress_sum / nf, 0.01),
		"fish_bursting": snappedf(float(bursting) / nf, 0.01),
		"fish_cap": int(sim.call("fish_carrying_capacity")),
		"shrimp_maturity": shrimp_mat,
		"shrimp_energy": snappedf(shrimp_energy / ns, 0.01),
		"shrimp": (sim.get("shrimp") as Array).size(),
		"snails": snails,
		"eggs": (sim.get("eggs") as Array).size(),
		"plants": (sim.get("plants") as Array).size(),
		"plant_biomass": snappedf(biomass, 0.1),
		"floaters": int(_world.call("floater_count")) if _world.has_method("floater_count") else -1,
		"floater_cov": snappedf(float(_world.call("floater_coverage")), 0.001) if _world.has_method("floater_coverage") else -1.0,
		"algae": (sim.get("algae") as Array).size(),
		"waste": (sim.get("waste") as Array).size(),
		"bloom": snappedf(float(sim.get("bloom_intensity")), 0.001),
		"o2": snappedf(float(sim.get("dissolved_o2")), 0.001),
		"stability": snappedf(float(sim.get("stability")), 0.001),
		"day_phase": snappedf(float(sim.get("day_phase")), 0.001),
		"daylight": snappedf(float(sim.call("daylight")), 0.001),
	}
	if chem != null:
		row["nh3"] = snappedf(float(chem.ammonia), 0.0001)
		row["no2"] = snappedf(float(chem.nitrite), 0.0001)
		row["no3"] = snappedf(float(chem.nitrate), 0.0001)
		row["bacteria"] = snappedf(float(chem.bacteria_colony), 0.001)
		row["co2"] = snappedf(float(chem.dissolved_co2), 0.001)
		row["ph"] = snappedf(float(chem.ph), 0.01)
		row["cycle_phase"] = int(chem.cycle_phase)
	if sub != null:
		row["soil_nutrients"] = snappedf(_grid_mean(sub.get("nutrients")), 0.001)
		row["soil_mulm"] = snappedf(_grid_mean(sub.get("mulm")), 0.001)
		row["soil_age_mult"] = snappedf(float(sub.get("soil_age_mult")), 0.001)
	_rows.append(row)
	_born.clear()
	_died.clear()
	_death_causes.clear()
	_crew_causes.clear()
	print("[temporal] ", JSON.stringify(row))


func _finish() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"scenario": _scenario, "speed": _speed, "rows": _rows}, "\t"))
		f.close()
	print("[temporal] wrote ", ProjectSettings.globalize_path(_out))
	get_tree().quit(0)
