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
var hardscape_root: Node3D = null  # driftwood + stones the fry hide against
var world_bounds: AABB = AABB(Vector3(-8, 1.6, -4), Vector3(16, 5, 8))
var substrate_top_y: float = 1.6

# Layout-related: where to parent new spawns.
var fauna_root: Node3D = null
var waste_root: Node3D = null
var plants_root: Node3D = null
var world: Node = null

var _accum: float = 0.0
var _stats_timer: float = 0.0
var _extinction_timer: float = 0.0
var _auto_feed_timer: float = 0.0

# ---- Save/load: stable per-entity IDs ----
# instance_id() is not stable across sessions, so anything that needs a
# saveable cross-reference (Fish.partner, Shrimp.partner, fish.target_plant,
# brooding parents) gets a string id minted here. The counter advances on
# every mint and is persisted in state.json so reloading doesn't recycle
# ids that point to still-alive entities.
var _next_entity_id: int = 1


func mint_id() -> String:
	var s: String = "e_" + str(_next_entity_id)
	_next_entity_id += 1
	return s


# Total real-world seconds this tank has been running with focus. Persisted
# in tanks/<slot>/meta.cfg and shown on the menu card. Ticked per real
# frame (NOT scaled by time_scale — this measures user attention).
var elapsed_runtime_s: float = 0.0

# ---- Dissolved-O2 model ----
# Tank-wide normalized scalar where 1.0 ≈ fully saturated, 0.0 = anoxic.
# Filled by the active aeration fixture, replenished modestly by plant
# photosynthesis during daylight, drawn down by fish + shrimp respiration.
# Fish read this to decide whether to gulp at the surface.
var dissolved_o2: float = 0.85
# Rates set by world.gd._spawn_aeration_system() based on the current
# TankConfig. air_rate ~ 0..1 from profile, flow_rate ~ 0..1 surface agitation.
var aeration_air_rate: float = 0.6
var aeration_flow_rate: float = 0.15
var aeration_fixture: String = "disk"
# Tuning constants - in normalized-units per second. Sized so a typical
# community tank with the disk fixture sits around 0.85-0.95 O2 in steady
# state, drops noticeably to 0.4-0.6 if you switch to "none" with a full bio
# load, and recovers within ~1 in-game minute if you turn aeration back on.
const O2_INJECT_PER_RATE: float = 0.20    # disk at strength=1 -> 0.20/s peak input
const O2_FLOW_BONUS_PER_RATE: float = 0.08
const O2_PHOTO_PER_PLANT: float = 0.0008  # multiplied by daylight + biomass term
const O2_RESPIRE_FISH: float = 0.0040
const O2_RESPIRE_SHRIMP: float = 0.0020
const O2_PASSIVE_SURFACE_GAS: float = 0.015   # tank breathing on its own
const O2_TARGET_NATURAL: float = 0.55         # passive only ever drifts to this


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
	# Real-time runtime accumulator (unscaled — measures how long the user
	# has had this tank open with focus). Used by the menu's "ran for X" line.
	elapsed_runtime_s += dt
	# Scale incoming delta by time_scale so pause/fast-forward work uniformly.
	var sdt: float = dt * time_scale
	_accum += sdt
	# Clamp the accumulator to prevent a "spiral of death" on slow frames: at
	# time_scale=16 a single 100ms hitch enqueues 1.6s = 16 ticks; if any of
	# those ticks then runs slower than its share of real time, _accum grows
	# faster than it drains and the game-loop locks. Cap at 4 ticks (0.4s of
	# sim work) so we drop sim-time on a hitch instead of freezing the render.
	_accum = minf(_accum, SIM_DT * 4.0)
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

	# 1b. Tank-wide dissolved-O2 update.
	#
	#   Inputs:
	#     fixture injection    +(air_rate * INJECT) + flow_rate * FLOW_BONUS
	#     plant photosynthesis +(daylight * plants * PHOTO)
	#     passive surface drift to a natural target (so a fully unaerated
	#       tank doesn't go to zero - it settles around O2_TARGET_NATURAL)
	#   Outputs:
	#     fish respiration     -(n_fish * RESPIRE_FISH)
	#     shrimp respiration   -(n_shrimp * RESPIRE_SHRIMP)
	#
	# Clamped 0..1.2 so plant blooms during the day can briefly push the tank
	# slightly supersaturated, which fish "notice" only when they need it.
	var inject: float = aeration_air_rate * O2_INJECT_PER_RATE \
		+ aeration_flow_rate * O2_FLOW_BONUS_PER_RATE
	var photo: float = daylight() * float(plants.size()) * O2_PHOTO_PER_PLANT
	var respire: float = float(fish.size()) * O2_RESPIRE_FISH \
		+ float(shrimp.size()) * O2_RESPIRE_SHRIMP
	# Drift toward the natural target if there's no equipment.
	var drift: float = O2_PASSIVE_SURFACE_GAS * (O2_TARGET_NATURAL - dissolved_o2)
	dissolved_o2 = clampf(dissolved_o2 + (inject + photo + drift - respire) * dt,
		0.0, 1.2)

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
			# queue_free is deferred — children freed on the previous tick can
			# still appear here. Filter so predator AI doesn't lock onto a ghost.
			if not is_instance_valid(c):
				continue
			if c.get("is_baby") == true:
				baby_snail_list.append(c)

	for f in fish:
		if not is_instance_valid(f):
			continue
		var neighbors: Array = []
		for g in fish:
			if g == f: continue
			if not is_instance_valid(g): continue
			if g.position.distance_squared_to(f.position) < 9.0:
				neighbors.append(g)
		var ev: Dictionary = f.tick(dt, neighbors, plants, algae, waste, baby_shrimp_list, world_bounds)
		if ev.size() > 0:
			ev["actor"] = f
			ev["actor_kind"] = "fish"
			events.append(ev)

	# 4b. Shrimp.
	for s in shrimp:
		if not is_instance_valid(s):
			continue
		var sn: Array = []
		for o in shrimp:
			if o == s: continue
			if not is_instance_valid(o): continue
			if o.position.distance_squared_to(s.position) < 4.0:
				sn.append(o)
		var ev: Dictionary = s.tick(dt, plants, algae, waste, fry_list, baby_snail_list,
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

	# 6a. Auto-Respawn Fauna if completely empty
	var cfg = get_node_or_null("/root/TankConfig")
	if cfg != null and cfg.auto_respawn_fauna:
		if fish.is_empty() and shrimp.is_empty() and eggs.is_empty():
			_extinction_timer += dt
			if _extinction_timer >= 5.0:
				_extinction_timer = 0.0
				var w: Node = get_parent()
				if w != null and w.has_method("_respawn_extinct_fauna"):
					w.call("_respawn_extinct_fauna")
		else:
			_extinction_timer = 0.0

	# 6b. Auto-Feed at surface
	if cfg != null and cfg.auto_feed_fauna:
		_auto_feed_timer += dt
		if _auto_feed_timer >= 12.0:
			_auto_feed_timer = 0.0
			var spawn_x: float = 0.0
			var spawn_z: float = 0.0
			var w := get_parent()
			if w != null and w.has_method("sample_xz_in_tank"):
				var xz: Vector2 = w.sample_xz_in_tank(0.5)
				spawn_x = xz.x
				spawn_z = xz.y
			else:
				spawn_x = randf_range(world_bounds.position.x + 0.5, world_bounds.end.x - 0.5)
				spawn_z = randf_range(world_bounds.position.z + 0.5, world_bounds.end.z - 0.5)
			# WATER_HEIGHT may be unset on the parent in unusual tank presets;
			# null-subtract would crash. Fall back to a safe near-surface Y.
			var fy: float = 6.4
			if w != null:
				var water_h = w.get("WATER_HEIGHT")
				if water_h != null:
					fy = float(water_h) - 0.1
			_spawn_waste(Vector3(spawn_x, fy, spawn_z), 0.5, 3) # 3 = KIND_FOOD

	# 6c. Algae - bloom if conditions favor (high nutrients + low plant biomass),
	# decay otherwise. Tracking is sparse to keep voxel count reasonable.
	var n_total: float = 0.0
	if substrate != null:
		n_total = substrate.total_above_baseline()
	var plant_biomass: int = 0
	for p in plants:
		if is_instance_valid(p):
			plant_biomass += p.biomass()
	var bloom_favor: bool = n_total > 4.0 and plant_biomass < 350
	# Algae floor: always keep at least 3 clusters drifting so the cory /
	# algae_grazer food chain has something to graze even in a "clean"
	# tank. Without this baseline, the moment algae crashes the grazers
	# starve and the food web stalls. Force-spawn when below the floor
	# regardless of nutrient state.
	const ALGAE_FLOOR: int = 3
	var below_floor: bool = algae.size() < ALGAE_FLOOR
	var should_bloom: bool = bloom_favor or below_floor
	# Cap algae count so it doesn't explode.
	if should_bloom and algae.size() < 60 and algae_root != null \
			and (below_floor or randf() < 0.2):
		var a := Algae.new()
		algae_root.add_child(a)
		# Spawn position uses the world's tank-aware sampler so algae stay
		# inside hex/triangle/cube tanks instead of clipping through walls.
		# Y is anchored near the substrate (0.3-1.2 above) where algae
		# would actually grow in a real tank AND where algae_grazer
		# corydoras can reach them. The old random Y in (2.2, 5.5) put
		# them mid-water floating uselessly.
		var spawn_x: float = 0.0
		var spawn_z: float = 0.0
		var w := get_parent()
		if w != null and w.has_method("sample_xz_in_tank"):
			var xz: Vector2 = w.sample_xz_in_tank(0.5)
			spawn_x = xz.x
			spawn_z = xz.y
		else:
			# Fallback: clamp to world_bounds. Better than the old hardcoded
			# range, still won't perfectly fit hex/triangle.
			spawn_x = randf_range(world_bounds.position.x + 0.5,
				world_bounds.end.x - 0.5)
			spawn_z = randf_range(world_bounds.position.z + 0.5,
				world_bounds.end.z - 0.5)
		a.global_position = Vector3(spawn_x,
			substrate_top_y + randf_range(0.3, 1.2), spawn_z)
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
	#
	# Targets that get consumed (waste particles, prey, snails, algae) are
	# tracked in a per-tick `consumed` set so two actors racing the same target
	# in the same tick don't both try to erase + queue_free it. Before the set
	# was added, the second consumer would re-call queue_free on an already-
	# freed node (Godot warns / can crash) and double-credit the food value.
	var consumed: Dictionary = {}
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
			if is_instance_valid(w) and not consumed.has(w):
				consumed[w] = true
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
			if is_instance_valid(prey) and not consumed.has(prey):
				consumed[prey] = true
				if prey is Fish:
					fish.erase(prey)
				elif prey is Shrimp:
					shrimp.erase(prey)
				# baby snail is a Node3D under snails_root - no explicit array
				prey.queue_free()

		# Specialist predation - loach + puffer cropping baby snails. Same
		# free-the-node path as kill_prey but emitted by the tier 1.9
		# specialist diet code in fish.gd. We treat the snail's voxel body
		# as biomass returning to the substrate - drop a small waste particle
		# at the snail's last position so the loop closes.
		if ev.has("kill_snail"):
			var snail: Node = ev["kill_snail"]
			if is_instance_valid(snail) and not consumed.has(snail):
				consumed[snail] = true
				_spawn_waste(snail.global_position, 0.18, WasteParticle.KIND_FISH)
				snail.queue_free()

		# Specialist grazing - corydoras / algae_grazer cropping algae clusters.
		# Algae shrink (or get removed entirely) when consumed; drop a tiny
		# waste particle so the consumed nutrients re-enter the substrate.
		if ev.has("eat_algae"):
			var alga = ev["eat_algae"]
			if is_instance_valid(alga) and not consumed.has(alga):
				consumed[alga] = true
				algae.erase(alga)
				_spawn_waste(alga.global_position, 0.08, WasteParticle.KIND_FISH)
				alga.queue_free()

		if ev.get("die", false):
			# On death, drop a single waste particle worth a bit of nutrient,
			# then free the fish/shrimp. Closes the biomass -> substrate loop.
			# Guard with `consumed`: if another actor's kill_prey already freed
			# this actor earlier in the same batch, skip — the queue_free is
			# already pending and we'd otherwise drop a phantom waste particle
			# at a stale position.
			if not consumed.has(actor):
				consumed[actor] = true
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
	# Branch on a.is_livebearer: guppies and platies don't lay eggs - the
	# female releases free-swimming juveniles directly. Everyone else
	# enters the FishEgg incubation pipeline.
	if fauna_root == null:
		return
	var n: int = mini(a.clutch_size, 4)
	var mid: Vector3 = (a.position + b.position) * 0.5

	if a.is_livebearer or b.is_livebearer:
		# Livebearer drop: spawn fry directly at the female's belly. Pick
		# whichever parent flagged the trait as the "mother" (in dimorphic
		# species the larger silvery female is sex == 1).
		var mother: Fish = a if a.sex == 1 else b
		for i in n:
			var g: Dictionary = a.produce_offspring_genome(b)
			var fry := Fish.new()
			fauna_root.add_child(fry)
			fry.global_position = mother.global_position + Vector3(
				randf_range(-0.15, 0.15),
				randf_range(-0.10, 0.05),
				randf_range(-0.15, 0.15),
			)
			fry.init_genome(g)
			fry.maturity = Fish.MATURITY_FRY
			fry.hunger = 0.25
			fry.energy = 0.95
			register_fish(fry)
		# Mother's belly is empty: extra exhaustion + small recovery cooldown.
		mother.energy = maxf(0.0, mother.energy - 0.20)
		_play_ambient(0.65)
		return

	# Egg-layers: choose a plant leaf if available, else drop on substrate.
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

	# Pair-bonding species (currently angelfish via swim_pattern "hover")
	# enter brooding mode: both parents hover near the nest and chase
	# intruders for BROODING_DURATION sim seconds. Fish.tick() reads the
	# brooding fields and overrides its behavior tree while active.
	if a.swim_pattern == "hover" and b.swim_pattern == "hover":
		a.brooding_at = lay_at
		a.brooding_remaining = Fish.BROODING_DURATION
		b.brooding_at = lay_at
		b.brooding_remaining = Fish.BROODING_DURATION

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
	# Track emergent sub-species via fish.morph_label(). A fish whose
	# skeleton genes still match its species template returns plain
	# "species"; a drifted one returns "species sp. <tags>". morph_drifted
	# counts only the second kind, so HUD reads "morphs +N" when N
	# lineages have actually diverged.
	var morphs: Dictionary = {}
	var morph_drifted: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.maturity == Fish.MATURITY_ADULT:
			n_adults += 1
		elif f.maturity == Fish.MATURITY_FRY:
			n_fry += 1
		var ml: String = f.morph_label()
		if ml != f.species:
			# Count distinct drifted labels (not individuals).
			if not morphs.has(ml):
				morph_drifted += 1
		morphs[ml] = int(morphs.get(ml, 0)) + 1
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
	# typed array on SimDriver. Count adults vs babies via the per-snail
	# is_baby flag set by snail.gd.
	var snail_total: int = 0
	var snail_adults: int = 0
	var snail_babies: int = 0
	if snails_root != null:
		for s in snails_root.get_children():
			# Only count nodes that look like snails (have a generation field +
			# is_baby property). Skip stray markers / decoration.
			if s.get("generation") == null:
				continue
			snail_total += 1
			if s.get("is_baby") == true:
				snail_babies += 1
			else:
				snail_adults += 1
			max_gen = maxi(max_gen, int(s.get("generation")))
	var s: Dictionary = {
		"fish_total": fish.size(),
		"fish_adults": n_adults,
		"fish_fry": n_fry,
		"eggs": eggs.size(),
		"shrimp_total": shrimp.size(),
		"shrimp_adults": shrimp_adults,
		"shrimp_fry": shrimp_fry,
		"snails_total": snail_total,
		"snails_adults": snail_adults,
		"snails_babies": snail_babies,
		"algae_clusters": algae.size(),
		"max_generation": max_gen,
		"morph_count": morphs.size(),
		"morph_distinct": morph_drifted,
		"plants_alive": plants.size(),
		"plant_total_biomass": total_biomass,
		"waste_particles": waste.size(),
		"substrate_nutrients_total": substrate.total_above_baseline() if substrate else 0.0,
		"dissolved_o2": dissolved_o2,
		"aeration_fixture": aeration_fixture,
	}
	stats_changed.emit(s)
	print_verbose("[vivarium] ", s)


# ============================================================================
# SAVE / LOAD
# ============================================================================
# save_state() walks every entity, mints ids where missing, and returns a
# JSON-serializable Dictionary. load_state(d) does the inverse, spawning
# entities in dependency order: substrate first, then plants (fish reference
# plants for breeding), then creatures, then transient particles, then
# resolving cross-references in a final pass.

const SAVE_STATE_VERSION: int = 1


func save_state() -> Dictionary:
	# Mint ids for any entity that doesn't have one yet.
	_ensure_ids()
	# Substrate type is included in the sim header so we can detect saltwater
	# ↔ freshwater swaps on load (those produce ecologically incompatible
	# plant lists — corals can't live in freshwater, vice versa). If the
	# loaded value doesn't match TankConfig.substrate_type at load time, the
	# loader bails and lets world.gd do a fresh initial spawn instead.
	var cfg := get_node_or_null("/root/TankConfig")
	var cfg_substrate: String = String(cfg.substrate_type) if cfg != null else ""
	var out: Dictionary = {
		"version": SAVE_STATE_VERSION,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"sim": {
			"time_scale": time_scale,
			"day_phase": day_phase,
			"tank_seed": tank_seed,
			"dissolved_o2": dissolved_o2,
			"aeration_air_rate": aeration_air_rate,
			"aeration_flow_rate": aeration_flow_rate,
			"aeration_fixture": aeration_fixture,
			"elapsed_runtime_s": elapsed_runtime_s,
			"next_entity_id": _next_entity_id,
			"substrate_type": cfg_substrate,
		},
		"substrate": substrate.to_save_dict() if substrate != null else {},
		"plants": [],
		"fish": [],
		"shrimp": [],
		"snails": [],
		"snail_eggs": [],
		"fish_eggs": [],
		"waste": [],
		"algae": [],
	}
	for p in plants:
		if is_instance_valid(p):
			out["plants"].append(p.to_save_dict())
	for f in fish:
		if is_instance_valid(f):
			out["fish"].append(f.to_save_dict())
	for sh in shrimp:
		if is_instance_valid(sh):
			out["shrimp"].append(sh.to_save_dict())
	if snails_root != null:
		for sn in snails_root.get_children():
			if not is_instance_valid(sn):
				continue
			# Snail eggs and adult snails both live under snails_root; tell
			# them apart by script path. snail_egg has its own apply_save_dict
			# but doesn't extend Snail.
			var script: Script = sn.get_script()
			var path: String = script.resource_path if script != null else ""
			if path.ends_with("snail.gd"):
				if sn.has_method("to_save_dict"):
					out["snails"].append(sn.to_save_dict())
			elif path.ends_with("snail_egg.gd"):
				if sn.has_method("to_save_dict"):
					out["snail_eggs"].append(sn.to_save_dict())
	for e in eggs:
		if is_instance_valid(e):
			out["fish_eggs"].append(e.to_save_dict())
	for w in waste:
		if is_instance_valid(w):
			out["waste"].append(w.to_save_dict())
	for a in algae:
		if is_instance_valid(a) and a.has_method("to_save_dict"):
			out["algae"].append(a.to_save_dict())
	return out


# Assign a fresh id to any entity that hasn't been minted yet. Idempotent:
# already-assigned ids are left untouched.
func _ensure_ids() -> void:
	for f in fish:
		if is_instance_valid(f) and String(f.id) == "":
			f.id = mint_id()
	for s in shrimp:
		if is_instance_valid(s) and String(s.id) == "":
			s.id = mint_id()
	for p in plants:
		if is_instance_valid(p) and String(p.id) == "":
			p.id = mint_id()
	if snails_root != null:
		for sn in snails_root.get_children():
			if is_instance_valid(sn) and sn.get("id") != null and String(sn.id) == "":
				sn.id = mint_id()


# Restore the entire sim from a saved Dictionary. world.gd's `loading_from_save`
# branch ensures _spawn_initial_* didn't run, so the scene is currently a
# bare tank (glass, substrate grid, aeration). We populate it.
func load_state(d: Dictionary) -> void:
	if int(d.get("version", 0)) != SAVE_STATE_VERSION:
		push_warning("[vivarium] save version mismatch; got %s, expected %d. Loading anyway." % [d.get("version"), SAVE_STATE_VERSION])

	# 1. SimDriver scalars (these need to be set before entities tick).
	var sim_d: Dictionary = d.get("sim", {})
	day_phase = float(sim_d.get("day_phase", day_phase))
	tank_seed = int(sim_d.get("tank_seed", tank_seed))
	dissolved_o2 = float(sim_d.get("dissolved_o2", dissolved_o2))
	aeration_air_rate = float(sim_d.get("aeration_air_rate", aeration_air_rate))
	aeration_flow_rate = float(sim_d.get("aeration_flow_rate", aeration_flow_rate))
	aeration_fixture = String(sim_d.get("aeration_fixture", aeration_fixture))
	elapsed_runtime_s = float(sim_d.get("elapsed_runtime_s", 0.0))
	_next_entity_id = int(sim_d.get("next_entity_id", _next_entity_id))

	# 2. Substrate (re-init was already done by world; overwrite nutrients).
	if substrate != null and d.has("substrate"):
		substrate.apply_save_dict(d["substrate"])

	# 3. Plants. Build the id→Node map as we go so post-load ref resolution
	# can find them.
	var id_map: Dictionary = {}
	for plant_dict in d.get("plants", []):
		var p: Plant = _spawn_plant_from_dict(plant_dict)
		if p != null:
			plants.append(p)
			id_map[String(p.id)] = p

	# 4. Algae.
	for alga_dict in d.get("algae", []):
		var a: Node = _spawn_algae_from_dict(alga_dict)
		if a != null:
			algae.append(a)

	# 5. Fish.
	for fish_dict in d.get("fish", []):
		var f: Fish = _spawn_fish_from_dict(fish_dict)
		if f != null:
			fish.append(f)
			id_map[String(f.id)] = f

	# 6. Shrimp.
	for sh_dict in d.get("shrimp", []):
		var sh: Shrimp = _spawn_shrimp_from_dict(sh_dict)
		if sh != null:
			shrimp.append(sh)
			id_map[String(sh.id)] = sh

	# 7. Snails + snail eggs (children of snails_root).
	for sn_dict in d.get("snails", []):
		var sn: Node3D = _spawn_snail_from_dict(sn_dict)
		if sn != null:
			id_map[String(sn.id)] = sn
	for se_dict in d.get("snail_eggs", []):
		_spawn_snail_egg_from_dict(se_dict)

	# 8. Fish eggs.
	for egg_dict in d.get("fish_eggs", []):
		var e: FishEgg = _spawn_fish_egg_from_dict(egg_dict)
		if e != null:
			eggs.append(e)

	# 9. Waste.
	for waste_dict in d.get("waste", []):
		var w: WasteParticle = _spawn_waste_from_dict(waste_dict)
		if w != null:
			waste.append(w)

	# 10. Cross-reference pass: resolve partner_id → partner Node refs.
	_resolve_refs(d, id_map)

	# 11. Finally, restore time_scale. We do this LAST because some entity
	# init paths read time_scale and we want them to see a stable state.
	time_scale = float(sim_d.get("time_scale", 1.0))


# ---- Spawn helpers (one per entity type) ----

func _spawn_plant_from_dict(d: Dictionary) -> Plant:
	if plants_root == null:
		return null
	var subclass: String = String(d.get("subclass", "plant"))
	var p: Plant = null
	match subclass:
		"spiral_plant":
			p = SpiralPlant.new()
		"branch_plant":
			p = BranchPlant.new()
		"coral":
			p = Coral.new()
		_:
			p = Plant.new()
	plants_root.add_child(p)
	p.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	p.apply_save_dict(d)
	return p


func _spawn_algae_from_dict(d: Dictionary) -> Node:
	if algae_root == null:
		return null
	var a := Algae.new()
	algae_root.add_child(a)
	a.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	a.apply_save_dict(d)
	return a


func _spawn_fish_from_dict(d: Dictionary) -> Fish:
	if fauna_root == null:
		return null
	var f := Fish.new()
	fauna_root.add_child(f)
	f.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	f.sim = self
	f.apply_save_dict(d)
	return f


func _spawn_shrimp_from_dict(d: Dictionary) -> Shrimp:
	if fauna_root == null:
		return null
	var sh := Shrimp.new()
	fauna_root.add_child(sh)
	sh.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	sh.sim = self
	sh.apply_save_dict(d)
	return sh


func _spawn_snail_from_dict(d: Dictionary) -> Node3D:
	if snails_root == null:
		return null
	var snail_script := load("res://scripts/snail.gd")
	if snail_script == null:
		return null
	var sn: Node3D = snail_script.new()
	snails_root.add_child(sn)
	sn.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	if sn.has_method("apply_save_dict"):
		sn.apply_save_dict(d)
	return sn


func _spawn_snail_egg_from_dict(d: Dictionary) -> Node3D:
	if snails_root == null:
		return null
	var egg_script := load("res://scripts/snail_egg.gd")
	if egg_script == null:
		return null
	var se: Node3D = egg_script.new()
	snails_root.add_child(se)
	se.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	if se.has_method("apply_save_dict"):
		se.apply_save_dict(d)
	return se


func _spawn_fish_egg_from_dict(d: Dictionary) -> FishEgg:
	if fauna_root == null:
		return null
	var e := FishEgg.new()
	fauna_root.add_child(e)
	e.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	e.apply_save_dict(d)
	return e


func _spawn_waste_from_dict(d: Dictionary) -> WasteParticle:
	if waste_root == null:
		return null
	var w := WasteParticle.new()
	waste_root.add_child(w)
	w.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	w.apply_save_dict(d)
	return w


# Second pass — every entity has been spawned and has its id assigned. Now
# walk again and resolve cross-refs (partner_id strings → Node references).
func _resolve_refs(saved: Dictionary, id_map: Dictionary) -> void:
	var fish_saves: Array = saved.get("fish", [])
	for i in mini(fish.size(), fish_saves.size()):
		var f: Fish = fish[i]
		if is_instance_valid(f) and f.has_method("resolve_refs"):
			f.resolve_refs(fish_saves[i], id_map)
	var shrimp_saves: Array = saved.get("shrimp", [])
	for i in mini(shrimp.size(), shrimp_saves.size()):
		var sh: Shrimp = shrimp[i]
		if is_instance_valid(sh) and sh.has_method("resolve_refs"):
			sh.resolve_refs(shrimp_saves[i], id_map)
