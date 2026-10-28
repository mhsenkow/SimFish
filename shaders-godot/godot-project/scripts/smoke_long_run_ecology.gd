# Long-run ecology contracts found by dev/temporal_soak.tscn.
#
#   ./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_long_run_ecology.gd
#
# - Soil: the 6 s terrain sync used to overwrite the substrate field, so poop
#   deposits and root drawdown never persisted. Terrain now sets each cell's
#   baseline; deposits survive a sync and relax back toward that cell's level.
# - Mind budget: past MIND_CYCLES_PER_S_BUDGET / DEFAULT_HZ unnamed fish, mind
#   cadence stretches so total cycles/s stop growing with population.
# - Waste: the batched integrator hands landing to WasteParticle.tick, which
#   is the only place that deposits into the soil.

extends SceneTree


func _init() -> void:
	var t := TestSupport.Suite.new("long_run_ecology")
	_soil(t)
	_mind_budget(t)
	_waste_handoff(t)
	_forage(t)
	_night_cost(t)
	_lifespan(t)
	quit(t.finish())


func _soil(t: TestSupport.Suite) -> void:
	var grid := SubstrateGrid.new()
	root.add_child(grid)
	grid.init(3.0, 3.0, 1.0)
	var rich := Vector3(-2.5, 0.0, -2.5)
	var lean := Vector3(2.5, 0.0, 2.5)
	var rc: Vector2i = grid._cell_at(rich)
	var lc: Vector2i = grid._cell_at(lean)
	# First sync snaps the field to the terrain.
	for x in grid.cells_x:
		for z in grid.cells_z:
			grid.set_cell_baseline(x, z, 0.3, true)
	grid.set_cell_baseline(rc.x, rc.y, 1.2, true)
	t.approx(grid.get_at(rich), 1.2, "first sync snaps a cell to its terrain level")
	t.approx(grid.get_at(lean), 0.3, "lean cells start lean")

	# A deposit must survive the next periodic sync.
	grid.add_at(lean, 0.8)
	var after_deposit: float = grid.get_at(lean)
	grid.set_cell_baseline(lc.x, lc.y, 0.3, false)
	t.approx(grid.get_at(lean), after_deposit, "a later sync keeps the deposit")

	# Relaxation goes to the cell's own level, not the global baseline.
	for i in 6000:
		grid.tick(0.1)
	t.in_range(grid.get_at(rich), 1.1, 1.3, "rich soil stays rich over a long run")
	t.in_range(grid.get_at(lean), 0.25, 0.4, "an enriched lean cell relaxes back to lean")

	# Soil aging tapers the leak, so a fully aged cell settles below fresh.
	var fresh: float = grid.get_at(rich)
	grid.soil_age_s = SubstrateGrid.SIM_DAY_S_LOCAL * SubstrateGrid.SOIL_DEPLETION_DAYS
	grid.add_at(rich, 0.01)
	for i in 6000:
		grid.tick(0.1)
	t.check(grid.get_at(rich) < fresh - 0.01,
		"aged soil settles below its fresh level (%.3f vs %.3f)" % [grid.get_at(rich), fresh])
	grid.queue_free()


class _MindFish:
	extends RefCounted
	var id: String = ""
	var is_guardian: bool = false
	var fish_name: String = ""
	@warning_ignore("unused_private_class_variable")  # read/written by MindTick
	var _mind_stagger: float = -1.0
	@warning_ignore("unused_private_class_variable")  # read/written by MindTick
	var _mind_accum: float = 0.0
	@warning_ignore("unused_private_class_variable")  # read/written by MindTick
	var _bid_slow_accum: float = 0.0
	@warning_ignore("unused_private_class_variable")  # read/written by MindTick
	var _bid_slow_due: bool = false
	var _player_watched: bool = false


func _mind_budget(t: TestSupport.Suite) -> void:
	MindTick.reset_stats_for_test()
	MindTick.apply_ambient_snap({"mind_cadence_hz": MindTick.DEFAULT_HZ, "mind_idle_mult": 1.0})
	var cycles: Array[int] = []
	for n in [10, 80]:
		MindTick.set_eligible_fish(n)
		var fishes: Array = []
		for i in n:
			var f := _MindFish.new()
			f.id = "budget_%d_%d" % [n, i]
			fishes.append(f)
		var runs: int = 0
		for tick in 100:  # 10 s of sim at 10 Hz
			for f in fishes:
				if bool(MindTick.advance(f, null, 0.1).get("run", false)):
					runs += 1
		cycles.append(runs)
	t.in_range(float(cycles[0]) / 10.0, 45.0, 55.0, "10 fish run at the full 5 Hz")
	t.in_range(float(cycles[1]) / 10.0, MindTick.MIND_CYCLES_PER_S_BUDGET * 0.85,
		MindTick.MIND_CYCLES_PER_S_BUDGET * 1.05,
		"80 fish share the tank budget instead of 400 cycles/s")
	var watched := _MindFish.new()
	watched.id = "watched_budget"
	watched.fish_name = "Pip"
	watched._player_watched = true
	var watched_runs: int = 0
	for tick in 100:
		if bool(MindTick.advance(watched, null, 0.1).get("run", false)):
			watched_runs += 1
	t.in_range(float(watched_runs), 45.0, 55.0, "the watched fish keeps the full cadence under budget")
	var named := _MindFish.new()
	named.id = "named_budget"
	named.fish_name = "Bo"
	var named_runs: int = 0
	for tick in 100:
		if bool(MindTick.advance(named, null, 0.1).get("run", false)):
			named_runs += 1
	t.check(named_runs < 20, "a name alone does not exempt a fish from the budget (%d runs)" % named_runs)
	MindTick.reset_stats_for_test()


func _waste_handoff(t: TestSupport.Suite) -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/waste_physics_batch.gd")
	t.check(not src.contains(".settled = true"),
		"the batch must not mark waste settled (that skipped the soil deposit)")
	t.check(src.contains("batch_landed = true"), "the batch hands landing to tick()")
	var wp: String = FileAccess.get_file_as_string("res://scripts/waste_particle.gd")
	t.check(wp.contains("if batch_landed or position.y <="),
		"WasteParticle.tick deposits on a batch landing")


class _ForageFish:
	extends RefCounted
	var hunger: float = 0.2
	var energy: float = 0.9


func _forage(t: TestSupport.Suite) -> void:
	# Full support covers more than the resting drain (0.004-0.006/s).
	var f := _ForageFish.new()
	f.energy = 0.5
	MindDriveSoA.apply_forage_and_reserves(f, 10.0, 1.0)
	t.check(f.energy > 0.5 + 10.0 * 0.006, "full forage outpaces the resting drain")
	var shared := _ForageFish.new()
	shared.energy = 0.5
	MindDriveSoA.apply_forage_and_reserves(shared, 10.0, 0.5)
	t.check(shared.energy < f.energy, "over capacity, each fish forages less")
	# Low reserves make a fish hungry even if it just ate.
	var weak := _ForageFish.new()
	weak.energy = 0.1
	weak.hunger = 0.0
	MindDriveSoA.apply_forage_and_reserves(weak, 0.1, 0.0)
	t.check(weak.hunger >= 0.6, "a fish low on energy is hungry (%.2f)" % weak.hunger)


func _night_cost(t: TestSupport.Suite) -> void:
	var shrimp_src: String = FileAccess.get_file_as_string("res://scripts/shrimp.gd")
	t.check(not shrimp_src.contains("tank_mind_snapshot()"),
		"shrimp must not build the whole-tank mind snapshot per tick")
	var nw: String = FileAccess.get_file_as_string("res://scripts/night_watch.gd")
	t.check(nw.contains("watcher_pick_tick"), "the night watcher is picked once per tick")


func _lifespan(t: TestSupport.Suite) -> void:
	# Authored lifespans (presets, old saves) scale once; lineages never compound.
	var mom := Fish.new()
	root.add_child(mom)
	mom.set_process(false)
	mom.init_genome({"species": "guppy", "sex": 1, "max_age_s": 240.0})
	t.approx(mom.max_age_s, 240.0 * Fish.LIFESPAN_SCALE, "an authored lifespan is scaled on init")
	var dad := Fish.new()
	root.add_child(dad)
	dad.set_process(false)
	dad.init_genome({"species": "guppy", "sex": 0, "max_age_s": 240.0})
	var child_genome: Dictionary = mom.produce_offspring_genome(dad)
	var child := Fish.new()
	root.add_child(child)
	child.set_process(false)
	child.init_genome(child_genome)
	t.in_range(child.max_age_s, 240.0 * Fish.LIFESPAN_SCALE - 101.0,
		240.0 * Fish.LIFESPAN_SCALE + 101.0, "offspring inherit the scaled span without rescaling")
	var replay := Fish.new()
	root.add_child(replay)
	replay.set_process(false)
	replay.init_genome(mom._saved_genome)
	t.approx(replay.max_age_s, mom.max_age_s, "a saved genome replays without rescaling")
	for f in [mom, dad, child, replay]:
		f.queue_free()
