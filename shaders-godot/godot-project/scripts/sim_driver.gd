# Central simulation ticker.
#
# Runs at a fixed rate (SIM_HZ) independent of the render rate. Each tick:
#   1. Gather neighbor lists (O(N^2) - fine for N <= 60 fish)
#   2. Tick every fish, collect events (waste, breed, die)
#   3. Tick every plant against the substrate grid
#   4. Tick every waste particle
#   5. Tick the substrate grid (diffuse + decay)
#   6. Resolve events: spawn fry, spawn waste, free dead fish
#
# Also tracks an autosave-able snapshot of the population stats and exposes
# a few signals for HUD/debug overlays.

extends Node
class_name SimDriver

signal stats_changed(stats: Dictionary)

const SIM_HZ: float = 10.0
const SIM_DT: float = 1.0 / SIM_HZ

# Time scale: 0=paused, 1=real-time, 4 / 16 = accelerated. Affects both the
# sim tick AND every creature's per-frame motion (each script multiplies its
# delta by sim.time_scale).
var time_scale: float = 1.0
# Day/night cycle: progresses 0..1 over DAY_LENGTH_S then wraps. 0=dawn,
# 0.25=midday, 0.5=dusk, 0.75=midnight.
var day_phase: float = 0.25  # start at midday
const DAY_LENGTH_S: float = 360.0  # 6-minute full cycle
# Deterministic seed shown in HUD. World reads this on init.
var tank_seed: int = 0xCAFEF155

var fish: Array[Fish] = []
var shrimp: Array[Shrimp] = []
var plants: Array[Plant] = []
var waste: Array[WasteParticle] = []
var eggs: Array[FishEgg] = []
var algae: Array = []   # Algae nodes; untyped so the script loads even if
						# the Algae class hasn't reimported into the global
						# registry yet on a fresh project scan.
var substrate: SubstrateGrid = null
var snails_root: Node3D = null   # set by world so SimDriver can scan snail children
var algae_root: Node3D = null    # container for algae voxels
var world_bounds: AABB = AABB(Vector3(-8, 1.6, -4), Vector3(16, 5, 8))
var substrate_top_y: float = 1.6

# Layout-related: where to parent new spawns.
var fauna_root: Node3D = null
var waste_root: Node3D = null
var plants_root: Node3D = null

var _accum: float = 0.0
var _stats_timer: float = 0.0


func register_fish(f: Fish) -> void:
	fish.append(f)
	f.sim = self


func register_plant(p: Plant) -> void:
	plants.append(p)


func register_waste(w: WasteParticle) -> void:
	waste.append(w)


func register_egg(e: FishEgg) -> void:
	eggs.append(e)


func register_shrimp(s: Shrimp) -> void:
	shrimp.append(s)
	s.sim = self


func _physics_process(dt: float) -> void:
	# Scale incoming delta by time_scale so pause/fast-forward work uniformly.
	var sdt: float = dt * time_scale
	_accum += sdt
	day_phase = fposmod(day_phase + sdt / DAY_LENGTH_S, 1.0)
	while _accum >= SIM_DT:
		_accum -= SIM_DT
		_tick(SIM_DT)
	_stats_timer += sdt
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		_emit_stats()


# Day/night light multiplier 0..1. Cosine over the cycle so it's a smooth
# bell. day_phase 0.25 = peak (midday), 0.75 = trough (midnight).
func daylight() -> float:
	return 0.5 + 0.5 * cos((day_phase - 0.25) * TAU)


func _tick(dt: float) -> void:
	# 1. Prune invalid refs (queue_freed nodes).
	fish = fish.filter(func(f): return is_instance_valid(f))
	shrimp = shrimp.filter(func(s): return is_instance_valid(s))
	plants = plants.filter(func(p): return is_instance_valid(p))
	waste = waste.filter(func(w): return is_instance_valid(w))
	eggs = eggs.filter(func(e): return is_instance_valid(e))

	# 2. Substrate field.
	if substrate != null:
		substrate.tick(dt)

	# 3. Plants.
	for p in plants:
		p.tick(dt, substrate)

	# 4. Fish: gather neighbors, tick, collect events.
	var events: Array[Dictionary] = []
	# Pre-collect fry list and baby snails for predator AI.
	var fry_list: Array = []
	for f in fish:
		if f.maturity == Fish.MATURITY_FRY:
			fry_list.append(f)
	var baby_shrimp_list: Array = []
	for s in shrimp:
		if s.maturity == Shrimp.MATURITY_FRY:
			baby_shrimp_list.append(s)
	var baby_snail_list: Array = []
	if snails_root != null:
		for c in snails_root.get_children():
			if c.get("is_baby") == true:
				baby_snail_list.append(c)

	for f in fish:
		var neighbors: Array = []
		for g in fish:
			if g == f: continue
			if g.position.distance_squared_to(f.position) < 9.0:
				neighbors.append(g)
		var ev: Dictionary = f.tick(dt, neighbors, plants, waste, baby_shrimp_list, world_bounds)
		if ev.size() > 0:
			ev["actor"] = f
			ev["actor_kind"] = "fish"
			events.append(ev)

	# 4b. Shrimp.
	for s in shrimp:
		var sn: Array = []
		for o in shrimp:
			if o == s: continue
			if o.position.distance_squared_to(s.position) < 4.0:
				sn.append(o)
		var ev: Dictionary = s.tick(dt, plants, waste, fry_list, baby_snail_list,
			sn, world_bounds)
		if ev.size() > 0:
			ev["actor"] = s
			ev["actor_kind"] = "shrimp"
			events.append(ev)

	# 5. Waste.
	var dead_waste: Array[WasteParticle] = []
	for w in waste:
		if w.tick(dt, substrate):
			dead_waste.append(w)
	for w in dead_waste:
		w.queue_free()

	# 6. Eggs - tick incubation, hatch when ready.
	var hatched: Array[FishEgg] = []
	for e in eggs:
		if e.tick(dt):
			hatched.append(e)
	for e in hatched:
		_hatch(e)
		e.queue_free()

	# 6b. Algae - bloom if conditions favor (high nutrients + low plant biomass),
	# decay otherwise. Tracking is sparse to keep voxel count reasonable.
	var n_total: float = 0.0
	if substrate != null:
		n_total = substrate.total_above_baseline()
	var plant_biomass: int = 0
	for p in plants:
		if is_instance_valid(p):
			plant_biomass += p.biomass()
	var bloom_favor: bool = n_total > 4.0 and plant_biomass < 350
	# Cap algae count so it doesn't explode.
	if bloom_favor and algae.size() < 60 and algae_root != null and randf() < 0.2:
		var a := Algae.new()
		algae_root.add_child(a)
		a.global_position = Vector3(
			randf_range(-7.5, 7.5),
			randf_range(2.2, 5.5),
			randf_range(-3.5, 3.5),
		)
		var palette: Array[Color] = [
			Color8(120, 165, 60),
			Color8(95, 145, 70),
			Color8(140, 180, 80),
		]
		a.init(palette[randi() % palette.size()])
		algae.append(a)
	# Tick existing algae.
	var dead_algae: Array = []
	for a in algae:
		if not is_instance_valid(a):
			continue
		if a.tick(dt, bloom_favor):
			dead_algae.append(a)
	for a in dead_algae:
		algae.erase(a)
		a.queue_free()

	# 7. Resolve events from fish + shrimp.
	for ev in events:
		var actor: Node3D = ev.get("actor", null)
		var actor_kind: String = ev.get("actor_kind", "fish")
		if actor == null or not is_instance_valid(actor):
			continue

		# Waste emission - kind depends on who pooped.
		if ev.has("waste_at"):
			var kind_const: int = WasteParticle.KIND_FISH
			if actor_kind == "shrimp":
				kind_const = WasteParticle.KIND_SHRIMP
			_spawn_waste(ev["waste_at"], ev.get("waste_amount", 0.2), kind_const)

		# Fish breeding -> eggs.
		if ev.has("lay_egg_with"):
			var partner_f: Fish = ev["lay_egg_with"]
			if is_instance_valid(partner_f):
				_lay_eggs(actor as Fish, partner_f)

		# Shrimp release fry (after gravidity period). Genome was pre-computed
		# at fertilization time and stashed on the female; we just spawn the
		# babies now using it.
		if ev.has("release_fry"):
			var brood_genome: Dictionary = ev["release_fry"]
			if brood_genome.size() > 0:
				_release_shrimp_brood(actor as Shrimp, brood_genome)

		# Consume a waste particle (food). The eater absorbs most of the value,
		# but excretes a smaller metabolic waste at its own position. This
		# keeps the nutrient cycle closing - half-life waste descends until
		# the leftover falls below 0.04 and is lost as background heat.
		if ev.has("eat_waste"):
			var w: WasteParticle = ev["eat_waste"]
			if is_instance_valid(w):
				var leftover: float = w.nutrient_value * 0.4
				waste.erase(w)
				w.queue_free()
				if leftover > 0.04:
					var new_kind: int = WasteParticle.KIND_FISH
					if actor_kind == "shrimp":
						new_kind = WasteParticle.KIND_SHRIMP
					_spawn_waste(actor.global_position + Vector3(0, -0.1, 0),
						leftover, new_kind)

		# Predation - remove the prey.
		if ev.has("kill_prey"):
			var prey: Node = ev["kill_prey"]
			if is_instance_valid(prey):
				if prey is Fish:
					fish.erase(prey)
				elif prey is Shrimp:
					shrimp.erase(prey)
				# baby snail is a Node3D under snails_root - no explicit array
				prey.queue_free()

		if ev.get("die", false):
			# On death, drop a single waste particle worth a bit of nutrient,
			# then free the fish/shrimp. Closes the biomass -> substrate loop.
			var k: int = WasteParticle.KIND_FISH if actor_kind == "fish" else WasteParticle.KIND_SHRIMP
			_spawn_waste(actor.position, 0.4 if actor_kind == "fish" else 0.25, k)
			actor.queue_free()


func _spawn_waste(at: Vector3, amount: float, kind: int = 0) -> void:
	if waste_root == null:
		return
	var w := WasteParticle.new()
	waste_root.add_child(w)
	w.global_position = at
	w.init(amount, substrate_top_y, kind)
	register_waste(w)


func _release_shrimp_brood(mother: Shrimp, brood_genome: Dictionary) -> void:
	# Release fry from the gravid mother. Each baby gets a fresh genome
	# derived from the cached brood_genome - the offspring traits were
	# pre-computed at fertilization. We re-randomize sex per baby and add
	# small per-baby color jitter so siblings are clearly siblings but not
	# identical clones.
	if fauna_root == null:
		return
	var n: int = mini(mother.clutch_size, 4)
	for i in n:
		var g: Dictionary = brood_genome.duplicate(true)
		g["sex"] = randi() % 2
		# Tiny per-baby color jitter so the litter isn't identical.
		if g.has("base_color"):
			g["base_color"] = (g["base_color"] as Color).lerp(
				Color(randf(), randf(), randf()), 0.05)
		var baby := Shrimp.new()
		fauna_root.add_child(baby)
		baby.global_position = mother.global_position + Vector3(
			randf_range(-0.2, 0.2), randf_range(0.0, 0.05), randf_range(-0.2, 0.2)
		)
		baby.init_genome(g)
		baby.age = 0.0
		baby.maturity = Shrimp.MATURITY_FRY
		register_shrimp(baby)


func _lay_eggs(a: Fish, b: Fish) -> void:
	# Place eggs on a plant if one is nearby (substrate spawners) OR on the
	# substrate directly. Each egg is a separate node that incubates and
	# hatches into a fry.
	if fauna_root == null:
		return
	var n: int = mini(a.clutch_size, 4)
	var mid: Vector3 = (a.position + b.position) * 0.5
	# Find a plant near the spawn site to lay eggs on (more realistic - many
	# species use plant leaves as a substrate). Fall back to dropping eggs
	# onto the tank floor.
	var lay_at: Vector3 = mid
	lay_at.y = maxf(substrate_top_y + 0.15, mid.y - 0.5)
	var best_plant: Plant = null
	var best_d2: float = 16.0
	for p in plants:
		if not is_instance_valid(p) or p.biomass() <= 0:
			continue
		var pp: Vector3 = p.global_position
		pp.y = p.top_world_y()
		var d2: float = pp.distance_squared_to(mid)
		if d2 < best_d2:
			best_d2 = d2
			best_plant = p
	if best_plant != null:
		lay_at = best_plant.global_position
		lay_at.y = best_plant.top_world_y()

	for i in n:
		var g: Dictionary = a.produce_offspring_genome(b)
		var e := FishEgg.new()
		fauna_root.add_child(e)
		e.global_position = lay_at + Vector3(
			randf_range(-0.2, 0.2),
			randf_range(0.0, 0.15),
			randf_range(-0.2, 0.2),
		)
		e.init(g)
		register_egg(e)
	_play_ambient(0.4)  # soft mid-tone for laying


func _hatch(e: FishEgg) -> void:
	if fauna_root == null:
		return
	var fry := Fish.new()
	fry.species = e.species
	fauna_root.add_child(fry)
	fry.global_position = e.global_position + Vector3(0, 0.1, 0)
	fry.init_genome(e.genome)
	# Newborn fry start hungry but with full energy.
	fry.hunger = 0.3
	fry.energy = 1.0
	register_fish(fry)
	_play_ambient(0.7)  # joyful high plink on hatch


# Helper - look up the audio node and emit a plink. Cheap no-op if missing.
func _play_ambient(intensity: float) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var audio := root.get_node_or_null("AmbientAudio")
	if audio != null and audio.has_method("play_event_plink"):
		audio.play_event_plink(intensity)


func _emit_stats() -> void:
	# Re-filter here: _emit_stats runs at 1Hz, independent of the 10Hz _tick
	# filter. Between two _tick calls, the engine may actually delete a
	# queue_freed Fish/Plant; the array still holds the stale ref. Iterating
	# without is_instance_valid causes "previously freed" crashes after long
	# runs with high mortality.
	var total_biomass: int = 0
	var n_adults: int = 0
	var n_fry: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.maturity == Fish.MATURITY_ADULT:
			n_adults += 1
		elif f.maturity == Fish.MATURITY_FRY:
			n_fry += 1
	for p in plants:
		if not is_instance_valid(p):
			continue
		total_biomass += p.biomass()
	var shrimp_adults: int = 0
	var shrimp_fry: int = 0
	var max_gen: int = 0
	for sh in shrimp:
		if not is_instance_valid(sh):
			continue
		if sh.maturity == Shrimp.MATURITY_ADULT:
			shrimp_adults += 1
		elif sh.maturity == Shrimp.MATURITY_FRY:
			shrimp_fry += 1
		max_gen = maxi(max_gen, int(sh.generation))
	for f in fish:
		if is_instance_valid(f):
			max_gen = maxi(max_gen, int(f.generation))
	# Snails: peek at the children of snails_root - they don't live in a
	# typed array on SimDriver.
	if snails_root != null:
		for s in snails_root.get_children():
			var g = s.get("generation")
			if g != null:
				max_gen = maxi(max_gen, int(g))
	var s: Dictionary = {
		"fish_total": fish.size(),
		"fish_adults": n_adults,
		"fish_fry": n_fry,
		"eggs": eggs.size(),
		"shrimp_total": shrimp.size(),
		"shrimp_adults": shrimp_adults,
		"shrimp_fry": shrimp_fry,
		"max_generation": max_gen,
		"plants_alive": plants.size(),
		"plant_total_biomass": total_biomass,
		"waste_particles": waste.size(),
		"substrate_nutrients_total": substrate.total_above_baseline() if substrate else 0.0,
	}
	stats_changed.emit(s)
	print("[vivarium] ", s)
