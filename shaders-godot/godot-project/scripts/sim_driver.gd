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

# Filter intake world-space position. Set by world._build_filter_aerator()
# when the "filter" aeration profile is active; remains Vector3.ZERO for
# disk / stick / none. Microfauna and waste particles read it to drift
# toward the intake and despawn there, closing the "tiny life sucked in
# by the filter" loop that real planted tanks always have.
var filter_intake_pos: Vector3 = Vector3.ZERO

# Bloom intensity 0..1 (smoothed). Driven by the algae step each tick;
# world.gd reads it to lerp the water material toward green. Smoothing
# keeps the water tint from flickering on per-tick nutrient noise.
var bloom_intensity: float = 0.0

# Count of fish with snail_predator genome flag, refreshed each tick.
# snail.gd reads it: when 0 (no snail-hunter in tank), snail breeding
# accelerates — the visible "no predators, snail boom" rebound dynamic.
# Plant biomass exposed at the same cadence so other systems don't
# have to iterate plants[] themselves.
var snail_predator_count: int = 0
# Live adult+baby snail count, refreshed each tick from the baby-snail scan
# loop. Used by the O2 model for snail respiration (cheap: avoids a second
# walk of snails_root just for the oxygen step).
var snail_count: int = 0
var total_plant_biomass: int = 0
var plant_growth_budget: int = 0
var _pearling_slots_used: int = 0
const PEARLING_MAX_SLOTS: int = 22
# All live snail nodes, rebuilt once per _tick from the "snails" group. Lets the
# same-tick overlap pass reuse the list instead of re-walking snails_root and
# string-comparing each child's script path.
var _live_snails: Array = []
# Cached autoloads / scene nodes — resolved lazily, reused thereafter. The
# per-tick "/root/TankConfig" lookup and per-event "AmbientAudio" tree walk were
# pure overhead since neither node ever moves.
var _cfg_cache: Node = null
var _ambient_audio_cache: Node = null

var _accum: float = 0.0
var _stats_timer: float = 0.0
var _extinction_timer: float = 0.0
var _auto_feed_timer: float = 0.0
var _has_logged_sterile_dissolve: bool = false
var _eco_engineering_timer: float = 0.8
var _overlap_resolve_timer: float = 0.0
# Ecosystem diary — Walstad cycle headlines beyond first-death milestones.
var _diary_pulse_t: float = 240.0
var _diary_bloom_phase: int = 0          # 0 calm 1 rising 2 peak 3 crash
var _diary_o2_stressed: bool = false
var _diary_milestone_shrimp: int = 0
var _diary_milestone_fish: int = 0
var _diary_milestone_gen: int = 0
var _diary_last_morph_distinct: int = 0
var _logged_fish_extinct: bool = false
var _logged_shrimp_extinct: bool = false
var _logged_snail_extinct: bool = false
var _logged_plant_extinct: bool = false

# Rare rescue when a lineage is nearly gone — never repopulate from zero.
const RESILIENCE_INTERVAL_S: float = 24.0
const RESILIENCE_BANK_REFRESH_S: float = 7.0
const RESILIENCE_FISH_FLOOR: int = 2
const RESILIENCE_SHRIMP_FLOOR: int = 2
const RESILIENCE_SNAIL_FLOOR: int = 2
const RESILIENCE_PLANT_FLOOR: int = 4
const RESILIENCE_PLANT_BIOMASS_FLOOR: int = 40
const RESILIENCE_MAX_SNAIL_EGGS: int = 4
const RESILIENCE_RESCUE_CHANCE: float = 0.12
const RESILIENCE_WIND_SEED_CHANCE: float = 0.05
var _resilience_timer: float = 4.0
var _resilience_bank_timer: float = 1.0
var _resilience_bank: Dictionary = {
	"fish": {},
	"shrimp": {},
	"snail": {},
	"plant": {},
}
const LIBRARY_ANALYSIS_REFRESH_S: float = 8.0
var _library_analysis_timer: float = 0.5
var _library_analysis_cache: Dictionary = {
	"fish": {},
	"shrimp": {},
	"snail": {},
	"plant": {},
}
const EVO_BURST_INTERVAL_S: float = 24.0
const EVO_BURST_CLUSTER_MIN: int = 2
const EVO_BURST_CLUSTER_MAX: int = 5
var _evo_burst_timer: float = 10.0

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
var water_chemistry: WaterChemistry = WaterChemistry.new()
var _terrain_sync_timer: float = 0.0
const TERRAIN_SYNC_INTERVAL_S: float = 6.0
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
const O2_PHOTO_FLOATER: float = 0.0006    # surface floating plants (duckweed etc.)
const O2_RESPIRE_FISH: float = 0.0040
const O2_RESPIRE_SHRIMP: float = 0.0020
const O2_RESPIRE_SNAIL: float = 0.0011
const O2_PASSIVE_SURFACE_GAS: float = 0.015   # tank breathing on its own
const O2_TARGET_NATURAL: float = 0.55         # passive only ever drifts to this
const ECO_ENGINEERING_INTERVAL: float = 1.2
const ECO_MAX_FISH_SAMPLES: int = 10
const ECO_MAX_SHRIMP_SAMPLES: int = 14
const ECO_MAX_SNAIL_SAMPLES: int = 12
const OVERLAP_RESOLVE_INTERVAL: float = 0.45


func register_fish(f: Fish) -> void:
	fish.append(f)
	f.sim = self
	_record_organism_discovery(f.get_saved_genome())


func register_shrimp(s: Shrimp) -> void:
	shrimp.append(s)
	s.sim = self
	_record_organism_discovery(s.get_saved_genome())


func register_snail(sn: Node) -> void:
	if sn == null or not is_instance_valid(sn):
		return
	if not sn.has_method("get_saved_genome"):
		return
	_record_organism_discovery(sn.get_saved_genome())


# Bind snails_root to the populated Snails container (not a queued-free stub).
func ensure_snails_root() -> Node3D:
	if snails_root != null and is_instance_valid(snails_root):
		return snails_root
	var w: Node = get_parent()
	if w == null:
		return null
	var best: Node3D = null
	var best_n: int = -1
	if w.has_method("_find_snails_container"):
		best = w._find_snails_container()
	else:
		for child in w.get_children():
			if child.name == "Snails" and is_instance_valid(child):
				var n: int = child.get_child_count()
				if n > best_n:
					best_n = n
					best = child as Node3D
	snails_root = best
	return snails_root


# Shrimp in Fauna but missing from the sim array still render but read as 0
# in the HUD. Re-attach orphans so stats, AI, and saves stay consistent.
func _reconcile_shrimp_registry() -> void:
	if fauna_root == null:
		return
	var seen: Dictionary = {}
	for s in shrimp:
		if is_instance_valid(s):
			seen[s.get_instance_id()] = true
	for child in fauna_root.get_children():
		if child is Shrimp and is_instance_valid(child):
			var sid: int = child.get_instance_id()
			if seen.has(sid):
				continue
			var sh: Shrimp = child as Shrimp
			shrimp.append(sh)
			sh.sim = self
			seen[sid] = true


# Backfill the species library from everything currently alive. Snails are
# built before clear_tank() in world._ready, and load_state skips per-entity
# registration — call this after stocking finishes.
func sync_species_discoveries() -> void:
	for f in fish:
		if is_instance_valid(f):
			_record_organism_discovery(f.get_saved_genome(), true)
	for s in shrimp:
		if is_instance_valid(s):
			_record_organism_discovery(s.get_saved_genome(), true)
	if snails_root != null:
		for sn in snails_root.get_children():
			if is_instance_valid(sn) and sn.has_method("get_saved_genome"):
				_record_organism_discovery(sn.get_saved_genome(), true)
	for p in plants:
		if is_instance_valid(p) and p.has_method("get_plant_genome"):
			_record_organism_discovery(p.get_plant_genome(), true)


# Notify the SpeciesLibrary autoload that an organism entered the world.
func _record_organism_discovery(g: Dictionary, silent: bool = false) -> void:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null:
		return
	if g.is_empty():
		return
	var gen: int = int(g.get("generation", 0))
	var species_id: String = String(g.get("species", ""))
	var source: String = "evolved"
	var subspecies_id: String = String(g.get("subspecies_id", species_id))
	if species_id.begins_with("stranger_"):
		source = "store"
	elif gen == 0:
		source = "founder"
	elif species_id != "" and subspecies_id != "" and subspecies_id != species_id:
		source = "speciated"
	lib.record_discovery(g, source, silent)


func register_plant(p: Plant) -> void:
	plants.append(p)
	if p.has_method("get_plant_genome"):
		_record_organism_discovery(p.get_plant_genome())


func try_consume_plant_growth() -> bool:
	if plant_growth_budget <= 0:
		return false
	plant_growth_budget -= 1
	return true


# Returns 0..1 dampening so dense tanks don't turn into a bubble blizzard.
# Plants tick in order; later plants get softer pearling once the cap fills.
func try_claim_pearling_slot(pearl_factor: float) -> float:
	if pearl_factor < 0.10:
		return 0.0
	if _pearling_slots_used >= PEARLING_MAX_SLOTS:
		return 0.0
	_pearling_slots_used += 1
	var fill: float = float(_pearling_slots_used) / float(PEARLING_MAX_SLOTS)
	return clampf(1.05 - fill * 0.75, 0.22, 1.0) * clampf(pearl_factor * 1.15, 0.0, 1.0)


func register_waste(w: WasteParticle) -> void:
	waste.append(w)


func register_egg(e: FishEgg) -> void:
	eggs.append(e)


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


# Cached TankConfig autoload accessor. The autoload never moves, so the per-tick
# "/root/TankConfig" path lookups this replaces were pure overhead.
func _cfg() -> Node:
	if _cfg_cache == null or not is_instance_valid(_cfg_cache):
		_cfg_cache = get_node_or_null("/root/TankConfig")
	return _cfg_cache


# Cached AmbientAudio node accessor (sibling under the running scene). Replaces a
# get_tree().current_scene + get_node_or_null tree walk on every food/death event.
func _ambient_audio() -> Node:
	if _ambient_audio_cache == null or not is_instance_valid(_ambient_audio_cache):
		var scene := get_tree().current_scene
		if scene != null:
			_ambient_audio_cache = scene.get_node_or_null("AmbientAudio")
	return _ambient_audio_cache


# ---- Spatial hash grid for neighbor lookups ----
# Cell size chosen to match the fish neighbor radius (3.0 units) so each
# query only needs to check the 9 surrounding cells in 2D (Y is ignored
# for cell assignment since the tank is shallow). Rebuilt every tick from
# scratch — the insert is O(N), and queries are O(neighbors) instead of
# the previous O(N²) brute-force scan.
const SPATIAL_CELL_SIZE: float = 3.0
# Neighbor-cell offsets, hoisted to a constant so _spatial_query (called once
# per fish + once per shrimp every tick) doesn't allocate two [-1,0,1] array
# literals on every single call.
const _CELL_OFFSETS: Array[int] = [-1, 0, 1]
var _spatial_grid: Dictionary = {}  # Vector2i → Array[Node3D]


func _spatial_rebuild(entities: Array) -> void:
	_spatial_grid.clear()
	for e in entities:
		if not is_instance_valid(e):
			continue
		if e.get("_dying") == true:
			continue
		var cell := Vector2i(
			int(floor(e.position.x / SPATIAL_CELL_SIZE)),
			int(floor(e.position.z / SPATIAL_CELL_SIZE)),
		)
		if _spatial_grid.has(cell):
			_spatial_grid[cell].append(e)
		else:
			_spatial_grid[cell] = [e]


func _spatial_query(pos: Vector3, radius_sq: float, exclude: Node3D = null) -> Array:
	var result: Array = []
	var cx: int = int(floor(pos.x / SPATIAL_CELL_SIZE))
	var cz: int = int(floor(pos.z / SPATIAL_CELL_SIZE))
	for dx in _CELL_OFFSETS:
		for dz in _CELL_OFFSETS:
			var cell := Vector2i(cx + dx, cz + dz)
			var bucket: Array = _spatial_grid.get(cell, [])
			for e in bucket:
				if e == exclude:
					continue
				if e.position.distance_squared_to(pos) < radius_sq:
					result.append(e)
	return result


func _push_apart_pair(a: Node3D, b: Node3D, min_dist: float,
		push_frac: float = 0.5, y_weight: float = 0.55) -> void:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return
	var pa: Vector3 = a.global_position
	var pb: Vector3 = b.global_position
	var diff: Vector3 = pa - pb
	diff.y *= y_weight
	var d2: float = diff.length_squared()
	var min_d2: float = min_dist * min_dist
	if d2 >= min_d2:
		return
	var dir: Vector3
	if d2 < 1e-6:
		var ang: float = randf() * TAU
		dir = Vector3(cos(ang), 0.0, sin(ang))
	else:
		dir = diff / sqrt(d2)
	var penetration: float = min_dist - sqrt(maxf(d2, 1e-6))
	var push: Vector3 = dir * penetration * push_frac
	pa += push
	pb -= push
	if pa.is_finite():
		a.global_position = pa
	if pb.is_finite():
		b.global_position = pb


func _clamp_entity_to_bounds(e: Node3D, margin: float = 0.22,
		substrate_margin: float = 0.06) -> void:
	if e == null or not is_instance_valid(e):
		return
	var p: Vector3 = e.global_position
	var w: Node = get_parent()
	if w != null and w.has_method("clamp_xyz_in_tank"):
		e.global_position = w.clamp_xyz_in_tank(p, margin)
		return
	if w != null and w.has_method("clamp_xz_in_tank"):
		var xz: Vector2 = w.clamp_xz_in_tank(p.x, p.z, margin)
		p.x = xz.x
		p.z = xz.y
	else:
		p.x = clampf(p.x, world_bounds.position.x + margin, world_bounds.end.x - margin)
		p.z = clampf(p.z, world_bounds.position.z + margin, world_bounds.end.z - margin)
	p.y = clampf(p.y, maxf(substrate_top_y + substrate_margin, world_bounds.position.y + margin),
		world_bounds.end.y - margin)
	e.global_position = p


func _resolve_entity_group_overlaps(group: Array, min_dist: float,
		group_limit: int = 120) -> void:
	var n: int = mini(group.size(), group_limit)
	for i in n:
		var a: Node3D = group[i] as Node3D
		if a == null or not is_instance_valid(a):
			continue
		for j in range(i + 1, n):
			var b: Node3D = group[j] as Node3D
			if b == null or not is_instance_valid(b):
				continue
			_push_apart_pair(a, b, min_dist, 0.5, 0.6)


func _resolve_cross_overlaps(primary: Array, other: Array, min_dist: float,
		primary_limit: int = 140, other_limit: int = 140) -> void:
	var n1: int = mini(primary.size(), primary_limit)
	var n2: int = mini(other.size(), other_limit)
	for i in n1:
		var a: Node3D = primary[i] as Node3D
		if a == null or not is_instance_valid(a):
			continue
		for j in n2:
			var b: Node3D = other[j] as Node3D
			if b == null or not is_instance_valid(b):
				continue
			_push_apart_pair(a, b, min_dist, 0.34, 0.45)


func _resolve_hardscape_overlaps(group: Array, min_dist: float,
		entity_limit: int = 140, hardscape_limit: int = 220) -> void:
	if hardscape_root == null or not is_instance_valid(hardscape_root):
		return
	var hardscape_children: Array = hardscape_root.get_children()
	var hn: int = mini(hardscape_children.size(), hardscape_limit)
	if hn <= 0:
		return
	var en: int = mini(group.size(), entity_limit)
	for i in en:
		var e: Node3D = group[i] as Node3D
		if e == null or not is_instance_valid(e):
			continue
		# Sample a subset of hardscape voxels — full O(n*m) against every
		# driftwood cube was contributing to GPU fence stalls on macOS.
		var step: int = maxi(1, int(ceil(float(hn) / 48.0)))
		for j in range(0, hn, step):
			var h: Node3D = hardscape_children[j] as Node3D
			if h == null or not is_instance_valid(h):
				continue
			var pe: Vector3 = e.global_position
			var ph: Vector3 = h.global_position
			var diff: Vector3 = pe - ph
			diff.y *= 0.35
			var d2: float = diff.length_squared()
			if d2 >= min_dist * min_dist:
				continue
			var dir: Vector3
			if d2 > 1e-6:
				dir = diff.normalized()
			else:
				var seed := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
				if seed.length_squared() < 1e-6:
					seed = Vector3(1.0, 0.0, 0.0)
				dir = seed.normalized()
			pe += dir * (min_dist - sqrt(maxf(d2, 1e-6))) * 0.55
			if pe.is_finite():
				e.global_position = pe
		_clamp_entity_to_bounds(e)


func _resolve_soft_overlaps() -> void:
	# Soft collision-fiction pass:
	# - prevents obvious interpenetration between schooling entities
	# - keeps small fauna from sitting inside hardscape voxels
	# - remains gentle so movement still feels biological (not physics-rigid)
	var live_fish: Array = []
	for f in fish:
		if is_instance_valid(f) and f.get("_dying") != true:
			live_fish.append(f)
	var live_shrimp: Array = []
	for s in shrimp:
		if is_instance_valid(s) and s.get("_dying") != true:
			live_shrimp.append(s)
	# Reuse the snail list built this tick in _tick — same frame, refs still
	# valid (queue_free is deferred to frame end), so no need to re-walk and
	# re-filter snails_root here.
	var live_snails: Array = _live_snails

	_resolve_entity_group_overlaps(live_fish, 0.30, 90)
	_resolve_entity_group_overlaps(live_shrimp, 0.16, 120)
	_resolve_entity_group_overlaps(live_snails, 0.20, 80)
	_resolve_cross_overlaps(live_fish, live_shrimp, 0.19, 90, 120)
	_resolve_cross_overlaps(live_shrimp, live_snails, 0.16, 120, 80)

	_resolve_hardscape_overlaps(live_fish, 0.30, 60, 120)
	_resolve_hardscape_overlaps(live_shrimp, 0.20, 80, 120)
	_resolve_hardscape_overlaps(live_snails, 0.18, 50, 120)

# In-place removal of invalidated refs. Iterates backward and uses
# remove_at() so we never allocate a new Array — eliminates the GC
# pressure of the old Array.filter() approach.
static func _prune_invalid(arr: Array) -> void:
	for i in range(arr.size() - 1, -1, -1):
		if not is_instance_valid(arr[i]):
			arr.remove_at(i)


func _prune_non_finite_positions(arr: Array) -> void:
	for i in range(arr.size() - 1, -1, -1):
		var n: Node3D = arr[i] as Node3D
		if n == null or not is_instance_valid(n):
			arr.remove_at(i)
			continue
		if not n.global_position.is_finite():
			n.queue_free()
			arr.remove_at(i)


func _tick(dt: float) -> void:
	ensure_snails_root()
	# 1. Prune invalid refs (queue_freed nodes) — in-place, no allocation.
	_prune_invalid(fish)
	_prune_invalid(shrimp)
	_prune_invalid(plants)
	_prune_invalid(waste)
	_prune_invalid(eggs)
	_prune_non_finite_positions(fish)
	_prune_non_finite_positions(shrimp)
	_library_analysis_timer = maxf(0.0, _library_analysis_timer - dt)
	if _library_analysis_timer <= 0.0:
		_library_analysis_timer = LIBRARY_ANALYSIS_REFRESH_S
		_refresh_library_analysis_cache()

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
	#     snail respiration    -(n_snails * RESPIRE_SNAIL)
	#
	# Clamped 0..1.2 so plant blooms during the day can briefly push the tank
	# slightly supersaturated, which fish "notice" only when they need it.
	var inject: float = aeration_air_rate * O2_INJECT_PER_RATE \
		+ aeration_flow_rate * O2_FLOW_BONUS_PER_RATE
	# Surface floating plants photosynthesise too (read live count from World).
	var floater_n: int = 0
	var w_o2: Node = get_parent()
	if w_o2 != null and w_o2.has_method("floater_count"):
		floater_n = w_o2.floater_count()
	var photo: float = daylight() * (float(plants.size()) * O2_PHOTO_PER_PLANT \
		+ float(floater_n) * O2_PHOTO_FLOATER)
	var respire: float = float(fish.size()) * O2_RESPIRE_FISH \
		+ float(shrimp.size()) * O2_RESPIRE_SHRIMP \
		+ float(snail_count) * O2_RESPIRE_SNAIL
	# Drift toward the natural target if there's no equipment.
	var drift: float = O2_PASSIVE_SURFACE_GAS * (O2_TARGET_NATURAL - dissolved_o2)
	dissolved_o2 = clampf(dissolved_o2 + (inject + photo + drift - respire) * dt,
		0.0, 1.2)

	# 2. Substrate field + periodic 3D terrain nutrient sync.
	if substrate != null:
		substrate.tick(dt)
	_terrain_sync_timer += dt
	if _terrain_sync_timer >= TERRAIN_SYNC_INTERVAL_S:
		_terrain_sync_timer = 0.0
		var w_sync: Node = get_parent()
		if w_sync != null and w_sync.has_method("sync_terrain_nutrients"):
			w_sync.sync_terrain_nutrients()

	# 3. Plants — cap GPU-heavy growth steps per tick (Metal fence safety).
	plant_growth_budget = clampi(28 + plants.size() / 12, 28, 96)
	_pearling_slots_used = 0
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
	var snail_n: int = 0
	# Rebuild the shared live-snail list once here; the same-tick overlap pass
	# reuses it instead of re-walking snails_root.
	_live_snails.clear()
	if snails_root != null:
		for c in snails_root.get_children():
			# queue_free is deferred — children freed on the previous tick can
			# still appear here. Filter so predator AI doesn't lock onto a ghost.
			if not is_instance_valid(c):
				continue
			# Fast group check instead of comparing each child's script path.
			if not c.is_in_group("snails"):
				continue
			snail_n += 1
			_live_snails.append(c)
			if c.get("is_baby") == true:
				baby_snail_list.append(c)
	snail_count = snail_n

	# Build spatial hash grid from all live (non-dying) fish. One O(N)
	# insert pass replaces the old O(N²) nested neighbor loop.
	_spatial_rebuild(fish)

	for f in fish:
		if not is_instance_valid(f):
			continue
		# Dying fish are inert: skip the tick entirely so the death pose
		# isn't fought by the brain, and skip them from any other fish's
		# neighbor list so schoolers don't cluster around the sinking
		# corpse and predators don't try to eat it mid-death.
		if f.get("_dying") == true:
			continue
		# Spatial query: 9 cells checked instead of all fish. Radius² = 9.0
		var neighbors: Array = _spatial_query(f.position, 9.0, f)
		var ev: Dictionary = f.tick(dt, neighbors, plants, algae, waste, baby_shrimp_list, world_bounds)
		if ev.size() > 0:
			ev["actor"] = f
			ev["actor_kind"] = "fish"
			events.append(ev)

	# 4b. Shrimp — rebuild grid with shrimp entities.
	_spatial_rebuild(shrimp)

	for s in shrimp:
		if not is_instance_valid(s):
			continue
		# Skip dying shrimp from the brain tick + neighbor lists (matches the
		# fish loop above — corpses shouldn't drive courtship or schooling).
		if s.get("_dying") == true:
			continue
		# Spatial query: radius² = 4.0 (2.0 unit radius for shrimp)
		var sn: Array = _spatial_query(s.position, 4.0, s)
		var ev: Dictionary = s.tick(dt, plants, algae, waste, fry_list, baby_snail_list,
			sn, world_bounds)
		if ev.size() > 0:
			ev["actor"] = s
			ev["actor_kind"] = "shrimp"
			events.append(ev)

	# 4c. Soft overlap pass every ~0.2 sim-seconds. Keeps fish/shrimp/snails
	# from visibly occupying the same space while preserving organic motion.
	_overlap_resolve_timer = maxf(0.0, _overlap_resolve_timer - dt)
	if _overlap_resolve_timer <= 0.0:
		_overlap_resolve_timer = OVERLAP_RESOLVE_INTERVAL
		ensure_snails_root()
		_resolve_soft_overlaps()

	# 5. Waste.
	var dead_waste: Array[WasteParticle] = []
	for w in waste:
		if w.tick(dt, substrate):
			dead_waste.append(w)
	for w in dead_waste:
		w.queue_free()

	# 6. Eggs - tick incubation, hatch when ready.
	var hatched: Array[FishEgg] = []
	var non_viable: Array[FishEgg] = []
	for e in eggs:
		if e.tick(dt):
			if e.viable:
				hatched.append(e)
			else:
				non_viable.append(e)
	for e in hatched:
		_hatch(e)
		eggs.erase(e)
		e.queue_free()
	for e in non_viable:
		eggs.erase(e)
		e.dissolve()
		if not _has_logged_sterile_dissolve:
			_has_logged_sterile_dissolve = true
			log_story_event("Non-viable eggs dissolved — genetic incompatibility")

	_run_resilience_seed(dt)
	_run_evolution_burst(dt)
	_run_ecosystem_diary(dt)

	# 6a. Auto-Respawn Fauna if completely empty
	var cfg = _cfg()
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

	# 6c. Algae bloom dynamics.
	#
	# Real planted tanks cycle: nutrients spike from over-feeding or new
	# substrate → algae bloom → green water → plants outcompete and
	# nutrients drop → bloom crashes → balance returns. We model this as
	# a continuous `bloom_pressure` (0..1) instead of a binary flag so:
	#   - spawn rate ramps gradually (no on/off pop-in)
	#   - cap rises during high pressure (a real bloom can carpet a tank)
	#   - water tint can lerp toward green proportionally
	#   - crash phase (high biomass, low nutrients) accelerates die-off
	# `bloom_intensity` is published on sim so world.gd's _process can
	# tint the water material to match.
	var n_total: float = 0.0
	if substrate != null:
		n_total = substrate.total_above_baseline()
	var plant_biomass: int = 0
	for p in plants:
		if is_instance_valid(p):
			plant_biomass += p.biomass()
	total_plant_biomass = plant_biomass
	_apply_ecosystem_engineering(dt)
	# Refresh snail-predator count for snail.gd's rebound logic. Cheap
	# (iterating fish is already done elsewhere; here we just count flags).
	var sp_count: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if bool(f.get("snail_predator")):
			sp_count += 1
	snail_predator_count = sp_count
	# Nutrient pressure: 0 at <=2.0 N, 1.0 at >=8.0 N; blend nitrate from N-cycle.
	var n_pressure: float = clampf((n_total - 2.0) / 6.0, 0.0, 1.0)
	var nitrate_p: float = clampf(water_chemistry.nitrate / 1.5, 0.0, 1.0)
	n_pressure = clampf(n_pressure * 0.65 + nitrate_p * 0.35, 0.0, 1.0)
	# Plant-shortage pressure: 0 when biomass >=450 (mature planted tank),
	# 1.0 when biomass <=150 (sparse / cycling tank).
	var plant_shortage: float = clampf((450.0 - float(plant_biomass)) / 300.0, 0.0, 1.0)
	# Combined bloom pressure. Multiplicative: needs BOTH high nutrients AND
	# low plant biomass to bloom. Either factor at 0 zeroes the bloom.
	var bloom_pressure: float = n_pressure * plant_shortage
	bloom_intensity = lerpf(bloom_intensity, bloom_pressure, clampf(dt * 0.25, 0.0, 1.0))
	var waste_nh3: float = float(waste.size()) * 0.0004
	water_chemistry.tick(dt, self, get_parent(), plant_biomass, waste_nh3)
	var bloom_favor: bool = bloom_pressure > 0.35  # for algae.tick's pressure-curve

	var w_shade: Node = get_parent()
	# Soft crowding: dense algae patches spawn less often instead of hitting
	# a hard population ceiling.
	var algae_capacity: float = 80.0
	if w_shade != null and w_shade.has_method("algae_carrying_capacity"):
		algae_capacity = float(w_shade.algae_carrying_capacity())
	var algae_crowding: float = clampf(float(algae.size()) / algae_capacity, 0.0, 1.0)
	# Algae floor: always keep at least 3 clusters drifting so the cory /
	# algae_grazer food chain has something to graze even in a "clean"
	# tank. Without this baseline, the moment algae crashes the grazers
	# starve and the food web stalls.
	const ALGAE_FLOOR: int = 3
	var below_floor: bool = algae.size() < ALGAE_FLOOR

	# Spawn-rate ramps from 5% (baseline trickle) up to ~45% per-tick when
	# the bloom is full. Plus a force-spawn when we're below the floor.
	var spawn_chance: float = 0.05 + bloom_pressure * 0.40
	# Surface floating plants shade the water column and soak up the same
	# nutrients algae want, so a duckweed mat strongly suppresses algae blooms
	# (the real Walstad "float plants to beat algae" trick).
	if w_shade != null and w_shade.has_method("floater_coverage"):
		spawn_chance *= (1.0 - float(w_shade.floater_coverage()) * 0.7)
	spawn_chance *= (1.0 - algae_crowding * 0.88)
	if (below_floor or randf() < spawn_chance) and algae_root != null:
		var a := Algae.new()
		algae_root.add_child(a)
		# Spawn position uses the world's tank-aware sampler so algae stay
		# inside hex/triangle/cube tanks instead of clipping through walls.
		# Y is anchored near the substrate (0.3-1.2 above) where algae
		# would actually grow in a real tank AND where algae_grazer
		# corydoras can reach them.
		var spawn_x: float = 0.0
		var spawn_z: float = 0.0
		var w := get_parent()
		if w != null and w.has_method("sample_xz_in_tank"):
			var xz: Vector2 = w.sample_xz_in_tank(0.5)
			spawn_x = xz.x
			spawn_z = xz.y
		else:
			spawn_x = randf_range(world_bounds.position.x + 0.5,
				world_bounds.end.x - 0.5)
			spawn_z = randf_range(world_bounds.position.z + 0.5,
				world_bounds.end.z - 0.5)
		var apos := Vector3(spawn_x, substrate_top_y + randf_range(0.3, 1.2), spawn_z)
		if w != null and w.has_method("column_surface_y"):
			apos.y = w.column_surface_y(spawn_x, spawn_z) + randf_range(0.3, 1.2)
		if w != null and w.has_method("clamp_xyz_in_tank"):
			apos = w.clamp_xyz_in_tank(apos, 0.35)
		a.global_position = apos
		var palette: Array[Color] = [
			Color8(120, 165, 60),
			Color8(95, 145, 70),
			Color8(140, 180, 80),
		]
		a.init(palette[randi() % palette.size()])
		algae.append(a)
	# Tick existing algae. Crash phase: when plants are healthy (biomass
	# high) AND nutrients have dropped (n_total low), algae die faster.
	# This is the visible "plants outcompete the bloom" payoff that closes
	# the cycle — without it the bloom would just plateau.
	var crash: bool = plant_biomass > 380 and n_total < 3.5
	var dead_algae: Array = []
	for a in algae:
		if not is_instance_valid(a):
			continue
		if a.tick(dt, bloom_favor):
			dead_algae.append(a)
		elif crash and randf() < dt * 0.12:
			# Accelerated die-off during the crash window.
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

		# Fish release livebearer fry (after gestation period).
		if ev.has("release_livebearer_fry"):
			var brood_genome: Dictionary = ev["release_livebearer_fry"]
			if brood_genome.size() > 0:
				_release_livebearer_fry(actor as Fish, brood_genome)

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
				_play_ambient_event("eat")
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
				if prey is Fish or prey is Shrimp:
					_play_ambient_event("death")
				else:
					_play_ambient_event("eat")
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
				_play_ambient_event("eat")
				_spawn_waste(snail.global_position, 0.18, WasteParticle.KIND_FISH)
				snail.queue_free()

		# Specialist grazing - corydoras / algae_grazer cropping algae clusters.
		# Algae shrink (or get removed entirely) when consumed; drop a tiny
		# waste particle so the consumed nutrients re-enter the substrate.
		if ev.has("eat_algae"):
			var alga = ev["eat_algae"]
			if is_instance_valid(alga) and not consumed.has(alga):
				consumed[alga] = true
				_play_ambient_event("eat")
				algae.erase(alga)
				_spawn_waste(alga.global_position, 0.08, WasteParticle.KIND_FISH)
				alga.queue_free()

		if ev.get("die", false):
			if not consumed.has(actor):
				consumed[actor] = true
				_play_ambient_event("death")
				if actor.has_method("start_dying"):
					actor.start_dying()
				else:
					# Fallback for entities without a death animation (snails,
					# etc.) — old behavior: spawn waste + free immediately.
					var k: int = WasteParticle.KIND_FISH if actor_kind == "fish" else WasteParticle.KIND_SHRIMP
					_spawn_waste(actor.position, 0.4 if actor_kind == "fish" else 0.25, k)
					actor.queue_free()
				if not _logged_first_death:
					_logged_first_death = true
					var species_name: String = "creature"
					if actor.has_method("get") and actor.get("species") != null:
						species_name = String(actor.species)
					log_story_event("First natural death — a %s reached the end of its lifespan." % species_name)


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


func _release_livebearer_fry(mother: Fish, brood_genome: Dictionary) -> void:
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
	_play_ambient_event("birth")


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
		_play_ambient_event("birth")
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
	# Story log: first egg event for the session is a milestone worth
	# recording. Subsequent spawns are routine and don't need to bloat
	# the log.
	if not _logged_first_egg:
		_logged_first_egg = true
		log_story_event("First eggs laid — a %s pair spawned %d eggs." % [
			a.species, n])

	# Pair-bonding/guarding species enter brooding mode: parents hover near
	# the nest and chase intruders. Hover species get full 90s duration;
	# other species with guards_clutch genome get 45s light brooding duration.
	var a_guards = a.get("guards_clutch") == true or a.swim_pattern == "hover"
	var b_guards = b.get("guards_clutch") == true or b.swim_pattern == "hover"
	if a_guards:
		a.brooding_at = lay_at
		a.brooding_remaining = Fish.BROODING_DURATION if a.swim_pattern == "hover" else Fish.BROODING_DURATION_LIGHT
	if b_guards:
		b.brooding_at = lay_at
		b.brooding_remaining = Fish.BROODING_DURATION if b.swim_pattern == "hover" else Fish.BROODING_DURATION_LIGHT

	_play_ambient_event("spawn")


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
	_play_ambient_event("birth")
	if not _logged_first_hatch:
		_logged_first_hatch = true
		log_story_event("First fry hatched — a baby %s entered the tank." % e.species)


# Helper - look up the audio node and emit a specific musical event.
func _play_ambient_event(event_name: String, intensity: float = -1.0) -> void:
	var audio := _ambient_audio()
	if audio != null and audio.has_method("play_aquarium_event"):
		audio.play_aquarium_event(event_name, intensity)


func _apply_ecosystem_engineering(dt: float) -> void:
	# Creature movement reshapes the substrate mosaic:
	# - fish stir upper substrate (slight depletion + nearby redeposit),
	# - shrimp/snails enrich local cells with detrital pellets.
	# The resulting nutrient map biases seedling/coral settlement sites.
	if substrate == null:
		return
	_eco_engineering_timer = maxf(0.0, _eco_engineering_timer - dt)
	if _eco_engineering_timer > 0.0:
		return
	_eco_engineering_timer = ECO_ENGINEERING_INTERVAL

	var fish_n: int = 0
	for f in fish:
		if fish_n >= ECO_MAX_FISH_SAMPLES:
			break
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		var p: Vector3 = f.position
		# Fish stir the top layer while foraging: tiny local drawdown...
		substrate.consume_at(Vector3(p.x, substrate_top_y, p.z), 0.0016)
		# ...and nearby redeposition plume (keeps mass in the neighborhood).
		var plume: Vector3 = Vector3(
			p.x + randf_range(-0.75, 0.75),
			substrate_top_y,
			p.z + randf_range(-0.75, 0.75))
		substrate.add_at(plume, 0.0012)
		fish_n += 1

	var shrimp_n: int = 0
	for s in shrimp:
		if shrimp_n >= ECO_MAX_SHRIMP_SAMPLES:
			break
		if not is_instance_valid(s):
			continue
		if s.get("_dying") == true:
			continue
		var sp: Vector3 = s.position
		substrate.add_at(Vector3(sp.x, substrate_top_y, sp.z), 0.0018)
		shrimp_n += 1

	var sn_root: Node3D = ensure_snails_root()
	if sn_root == null:
		return
	var snail_n: int = 0
	for n in sn_root.get_children():
		if snail_n >= ECO_MAX_SNAIL_SAMPLES:
			break
		if not is_instance_valid(n):
			continue
		if not n.is_in_group("snails"):
			continue
		var np: Vector3 = (n as Node3D).global_position
		substrate.add_at(Vector3(np.x, substrate_top_y, np.z), 0.0015)
		snail_n += 1


func _count_live_fish() -> int:
	var n: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		n += 1
	return n


func _count_live_shrimp() -> int:
	var n: int = 0
	for s in shrimp:
		if not is_instance_valid(s):
			continue
		if s.get("_dying") == true:
			continue
		n += 1
	return n


func _count_snails_and_eggs() -> Dictionary:
	var snails: int = 0
	var eggs_n: int = 0
	var root: Node3D = ensure_snails_root()
	if root == null:
		return {"snails": 0, "eggs": 0}
	for c in root.get_children():
		if not is_instance_valid(c):
			continue
		if c.is_in_group("snails"):
			snails += 1
		else:
			var script: Script = c.get_script()
			if script != null and script.resource_path.ends_with("snail_egg.gd"):
				eggs_n += 1
	return {"snails": snails, "eggs": eggs_n}


func _refresh_library_analysis_cache() -> void:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null or not lib.has_method("analyze_organism"):
		return
	_library_analysis_cache["fish"] = lib.analyze_organism("fish", true)
	_library_analysis_cache["shrimp"] = lib.analyze_organism("shrimp", true)
	_library_analysis_cache["snail"] = lib.analyze_organism("snail", true)
	_library_analysis_cache["plant"] = lib.analyze_organism("plant", true)


func _library_analysis(organism_type: String) -> Dictionary:
	var d: Variant = _library_analysis_cache.get(organism_type, {})
	if d is Dictionary:
		return d
	return {}


func _analysis_strength(d: Dictionary) -> float:
	var n: int = int(d.get("entry_count", 0))
	return clampf(float(n) / 12.0, 0.0, 1.0)


func _apply_library_guided_fish_tuning(g: Dictionary) -> Dictionary:
	var a: Dictionary = _library_analysis("fish")
	if int(a.get("entry_count", 0)) <= 0:
		return g
	var k: float = _analysis_strength(a)
	g["body_elongation"] = clampf(
		lerpf(float(g.get("body_elongation", 1.0)), float(a.get("avg_elongation", 1.0)), 0.20 + k * 0.25)
			+ randf_range(-0.07, 0.07),
		0.5, 2.0)
	g["body_depth_factor"] = clampf(
		lerpf(float(g.get("body_depth_factor", 1.0)), float(a.get("avg_depth", 1.0)), 0.20 + k * 0.25)
			+ randf_range(-0.06, 0.06),
		0.5, 2.0)
	g["head_proportion"] = clampf(
		lerpf(float(g.get("head_proportion", 1.0)), float(a.get("avg_head", 1.0)), 0.16 + k * 0.20)
			+ randf_range(-0.06, 0.06),
		0.5, 2.0)
	g["fin_length_factor"] = clampf(
		lerpf(float(g.get("fin_length_factor", 1.0)), float(a.get("avg_fin_length", 1.0)), 0.15 + k * 0.22)
			+ randf_range(-0.08, 0.08),
		0.5, 2.5)
	g["max_speed"] = clampf(
		lerpf(float(g.get("max_speed", 1.2)), float(a.get("avg_speed", 1.2)), 0.18 + k * 0.24)
			+ randf_range(-0.08, 0.08),
		0.55, 3.0)
	g["jaw_claw_size"] = clampf(
		lerpf(float(g.get("jaw_claw_size", 0.0)), float(a.get("avg_jaw_claw_size", 0.0)), 0.18 + k * 0.24)
			+ randf_range(-0.10, 0.12),
		0.0, 1.2)
	g["size_potential"] = clampf(
		lerpf(float(g.get("size_potential", 1.0)), float(a.get("avg_size_potential", 1.0)), 0.20 + k * 0.22)
			+ randf_range(-0.09, 0.10),
		0.6, 2.4)
	var pred_bias: float = clampf(
		(float(a.get("snail_predator_ratio", 0.0)) + float(a.get("shrimp_predator_ratio", 0.0))) * 0.5,
		0.0, 1.0)
	if randf() < 0.22 + pred_bias * 0.38:
		g["snail_predator"] = bool(g.get("snail_predator", false)) or randf() < float(a.get("snail_predator_ratio", 0.0))
	if randf() < 0.22 + pred_bias * 0.38:
		g["shrimp_predator"] = bool(g.get("shrimp_predator", false)) or randf() < float(a.get("shrimp_predator_ratio", 0.0))
	if randf() < 0.10 + float(a.get("armor_ratio", 0.0)) * 0.35:
		g["armor_plates"] = bool(g.get("armor_plates", false)) or randf() < float(a.get("armor_ratio", 0.0))
	if randf() < 0.10 + float(a.get("barbels_ratio", 0.0)) * 0.30:
		g["has_barbels"] = bool(g.get("has_barbels", false)) or randf() < float(a.get("barbels_ratio", 0.0))
	var dom_shape: String = String(a.get("dominant_body_shape", ""))
	if dom_shape != "" and randf() < 0.15 + k * 0.22:
		g["body_shape"] = dom_shape
	return g


func _apply_library_guided_shrimp_tuning(g: Dictionary) -> Dictionary:
	var a: Dictionary = _library_analysis("shrimp")
	if int(a.get("entry_count", 0)) <= 0:
		return g
	var k: float = _analysis_strength(a)
	g["defense_spines"] = clampf(
		lerpf(float(g.get("defense_spines", 0.0)), float(a.get("avg_spines", 0.0)), 0.18 + k * 0.25)
			+ randf_range(-0.07, 0.08),
		0.0, 1.0)
	g["toxin_level"] = clampf(
		lerpf(float(g.get("toxin_level", 0.0)), float(a.get("avg_toxin", 0.0)), 0.18 + k * 0.25)
			+ randf_range(-0.06, 0.08),
		0.0, 1.0)
	g["adult_voxel_scale"] = clampf(
		lerpf(float(g.get("adult_voxel_scale", 0.10)), float(a.get("avg_size", 0.10)), 0.15 + k * 0.20)
			+ randf_range(-0.008, 0.010),
		0.07, 0.30)
	g["max_speed"] = clampf(
		lerpf(float(g.get("max_speed", 0.85)), float(a.get("avg_speed", 0.85)), 0.16 + k * 0.20)
			+ randf_range(-0.05, 0.06),
		0.45, 1.55)
	g["claw_size"] = clampf(
		lerpf(float(g.get("claw_size", 0.25)), float(a.get("avg_claw_size", 0.25)), 0.20 + k * 0.24)
			+ randf_range(-0.10, 0.14),
		0.0, 1.2)
	g["body_length_factor"] = clampf(
		lerpf(float(g.get("body_length_factor", 1.0)), float(a.get("avg_length_factor", 1.0)), 0.18 + k * 0.22)
			+ randf_range(-0.10, 0.12),
		0.75, 1.7)
	if randf() < 0.10 + float(a.get("cleaner_ratio", 0.0)) * 0.28:
		g["is_cleaner"] = bool(g.get("is_cleaner", false)) or randf() < float(a.get("cleaner_ratio", 0.0))
	return g


func _apply_library_guided_snail_tuning(g: Dictionary) -> Dictionary:
	var a: Dictionary = _library_analysis("snail")
	if int(a.get("entry_count", 0)) <= 0:
		return g
	var k: float = _analysis_strength(a)
	g["shell_size"] = clampf(
		lerpf(float(g.get("shell_size", 1.0)), float(a.get("avg_shell_size", 1.0)), 0.18 + k * 0.24)
			+ randf_range(-0.05, 0.06),
		0.65, 1.6)
	g["shell_spines"] = clampf(
		lerpf(float(g.get("shell_spines", 0.0)), float(a.get("avg_spines", 0.0)), 0.20 + k * 0.24)
			+ randf_range(-0.08, 0.09),
		0.0, 1.0)
	g["toxin_level"] = clampf(
		lerpf(float(g.get("toxin_level", 0.0)), float(a.get("avg_toxin", 0.0)), 0.18 + k * 0.24)
			+ randf_range(-0.06, 0.08),
		0.0, 1.0)
	var dom_shape: String = String(a.get("dominant_shell_shape", ""))
	if dom_shape != "" and randf() < 0.18 + k * 0.26:
		g["shell_shape"] = dom_shape
	return g


func _apply_library_guided_plant_tuning(seed: Dictionary) -> Dictionary:
	var a: Dictionary = _library_analysis("plant")
	if int(a.get("entry_count", 0)) <= 0:
		return seed
	var out: Dictionary = seed.duplicate(true)
	var cfg: Dictionary = out.get("seed_config", {}).duplicate(true)
	var k: float = _analysis_strength(a)
	cfg["max_height"] = clampi(int(round(
		lerpf(float(cfg.get("max_height", 14)), float(a.get("avg_height", 14.0)), 0.14 + k * 0.22)
		+ randf_range(-2.0, 2.5))), 6, 48)
	cfg["growth_rate"] = clampf(
		lerpf(float(cfg.get("growth_rate", 0.18)), float(a.get("avg_growth_rate", 0.18)), 0.18 + k * 0.24)
			+ randf_range(-0.03, 0.035),
		0.06, 0.62)
	cfg["sway_amplitude"] = clampf(
		lerpf(float(cfg.get("sway_amplitude", 0.22)), float(a.get("avg_sway", 0.22)), 0.14 + k * 0.20)
			+ randf_range(-0.03, 0.04),
		0.02, 0.90)
	cfg["leaf_length"] = clampi(int(round(
		lerpf(float(cfg.get("leaf_length", 4)), float(a.get("avg_leaf_length", 4.0)), 0.18 + k * 0.22)
		+ randf_range(-1.0, 1.2))), 2, 16)
	cfg["max_roots"] = clampi(int(round(
		lerpf(float(cfg.get("max_roots", 6)), float(a.get("avg_max_roots", 6.0)), 0.16 + k * 0.18)
		+ randf_range(-1.0, 1.0))), 3, 16)
	var dom_form: String = String(a.get("dominant_leaf_form", ""))
	if dom_form != "" and randf() < 0.16 + k * 0.24:
		cfg["leaf_form"] = dom_form
	out["seed_config"] = cfg
	return out


func _score_fish_resilience(f: Fish) -> float:
	var hunger_score: float = 1.0 - clampf(float(f.hunger), 0.0, 1.0)
	var energy_score: float = clampf(float(f.energy), 0.0, 1.0)
	var age_score: float = 0.0
	if float(f.max_age_s) > 0.0:
		age_score = clampf(float(f.age) / float(f.max_age_s), 0.0, 1.0)
	var mg: float = maxf(1.0, f.max_growth)
	var growth_score: float = clampf(f.growth_factor / mg, 0.0, 1.0)
	return hunger_score * 0.34 + energy_score * 0.34 + age_score * 0.18 + growth_score * 0.14


func _score_shrimp_resilience(s: Shrimp) -> float:
	var hunger_score: float = 1.0 - clampf(float(s.hunger), 0.0, 1.0)
	var energy_score: float = clampf(float(s.energy), 0.0, 1.0)
	var age_score: float = 0.0
	if float(s.max_age_s) > 0.0:
		age_score = clampf(float(s.age) / float(s.max_age_s), 0.0, 1.0)
	var growth_score: float = clampf(float(s.growth_factor) / maxf(1.0, float(Shrimp.MAX_GROWTH)), 0.0, 1.0)
	return hunger_score * 0.36 + energy_score * 0.30 + age_score * 0.18 + growth_score * 0.16


func _pick_elite_fish() -> Fish:
	var best: Fish = null
	var best_score: float = -INF
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true or f.maturity != Fish.MATURITY_ADULT:
			continue
		var score: float = _score_fish_resilience(f)
		if score > best_score:
			best_score = score
			best = f
	return best


func _pick_elite_shrimp() -> Shrimp:
	var best: Shrimp = null
	var best_score: float = -INF
	for s in shrimp:
		if not is_instance_valid(s):
			continue
		if s.get("_dying") == true or s.maturity != Shrimp.MATURITY_ADULT:
			continue
		var score: float = _score_shrimp_resilience(s)
		if score > best_score:
			best_score = score
			best = s
	return best


func _pick_elite_plant() -> Plant:
	var best: Plant = null
	var best_score: float = -INF
	for p in plants:
		if not is_instance_valid(p):
			continue
		var score: float = float(p.biomass()) + float(p.generation) * 4.0
		if score > best_score:
			best_score = score
			best = p
	return best


func _pick_random_adult_fish() -> Fish:
	var adults: Array[Fish] = []
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true or f.maturity != Fish.MATURITY_ADULT:
			continue
		adults.append(f)
	if adults.is_empty():
		return null
	return adults[randi() % adults.size()]


func _pick_random_adult_shrimp() -> Shrimp:
	var adults: Array[Shrimp] = []
	for s in shrimp:
		if not is_instance_valid(s):
			continue
		if s.get("_dying") == true or s.maturity != Shrimp.MATURITY_ADULT:
			continue
		adults.append(s)
	if adults.is_empty():
		return null
	return adults[randi() % adults.size()]


func _pick_elite_snail() -> Node3D:
	var best: Node3D = null
	var best_age: float = -INF
	var root: Node3D = ensure_snails_root()
	if root == null:
		return null
	for s in root.get_children():
		if not is_instance_valid(s):
			continue
		if not s.is_in_group("snails"):
			continue
		if s.get("is_baby") == true:
			continue
		var age: float = float(s.get("_age")) if s.get("_age") != null else 0.0
		if age > best_age:
			best_age = age
			best = s as Node3D
	return best


func _mutate_color(c: Color, amt: float) -> Color:
	return c.lerp(Color(randf(), randf(), randf()), amt)


func _make_resilience_fish_genome() -> Dictionary:
	var parent: Fish = _pick_elite_fish()
	# Keep lineage diversity: occasionally seed from a non-elite adult too.
	if randf() < 0.35:
		var alt: Fish = _pick_random_adult_fish()
		if alt != null:
			parent = alt
	if parent != null and parent.has_method("produce_offspring_genome"):
		return _apply_library_guided_fish_tuning(parent.produce_offspring_genome(parent))
	return _apply_library_guided_fish_tuning(
		_mutate_bank_genome(_resilience_bank.get("fish", {}), "fish"))


func _make_resilience_shrimp_genome() -> Dictionary:
	var parent: Shrimp = _pick_elite_shrimp()
	if randf() < 0.35:
		var alt: Shrimp = _pick_random_adult_shrimp()
		if alt != null:
			parent = alt
	if parent != null and parent.has_method("produce_offspring_genome"):
		var g: Dictionary = parent.produce_offspring_genome(parent)
		g["defense_spines"] = clampf(float(g.get("defense_spines", 0.0)) + randf_range(-0.06, 0.10), 0.0, 1.0)
		g["toxin_level"] = clampf(float(g.get("toxin_level", 0.0)) + randf_range(-0.05, 0.09), 0.0, 1.0)
		return _apply_library_guided_shrimp_tuning(g)
	return _apply_library_guided_shrimp_tuning(
		_mutate_bank_genome(_resilience_bank.get("shrimp", {}), "shrimp"))


func _make_resilience_snail_genome() -> Dictionary:
	var elite: Node3D = _pick_elite_snail()
	if elite != null and elite.has_method("get_saved_genome"):
		var g: Dictionary = elite.get_saved_genome().duplicate(true)
		g["generation"] = int(g.get("generation", 0)) + 1
		g["shell_color"] = _mutate_color(g.get("shell_color", Color8(135, 44, 176)), 0.12)
		g["shell_size"] = clampf(float(g.get("shell_size", 1.0)) + randf_range(-0.05, 0.07), 0.65, 1.5)
		g["shell_spines"] = clampf(float(g.get("shell_spines", 0.0)) + randf_range(-0.08, 0.10), 0.0, 1.0)
		g["toxin_level"] = clampf(float(g.get("toxin_level", 0.0)) + randf_range(-0.08, 0.08), 0.0, 1.0)
		if randf() < 0.06:
			var shapes: Array = ["turbo", "trochus", "nassarius", "apple"]
			g["shell_shape"] = String(shapes[randi() % shapes.size()])
		g["organism_type"] = "snail"
		return _apply_library_guided_snail_tuning(g)
	return _apply_library_guided_snail_tuning(
		_mutate_bank_genome(_resilience_bank.get("snail", {}), "snail"))


func _make_resilience_plant_seed() -> Dictionary:
	var p: Plant = _pick_elite_plant()
	if p != null and p.has_method("get_seed_config") and p.has_method("get_plant_genome"):
		var g: Dictionary = p.get_plant_genome()
		var ramp: Array = g.get("ramp_override", []).duplicate(true)
		for i in ramp.size():
			ramp[i] = _mutate_color(ramp[i], 0.07)
		var cfg: Dictionary = p.get_seed_config()
		cfg["growth_rate"] = clampf(float(cfg.get("growth_rate", 0.18)) * randf_range(0.96, 1.14), 0.06, 0.45)
		cfg["max_height"] = clampi(int(cfg.get("max_height", 14)) + randi_range(-2, 3), 6, 44)
		return _apply_library_guided_plant_tuning({
			"ramp": ramp, "generation": int(g.get("generation", 0)) + 1, "seed_config": cfg})
	var bank: Dictionary = _resilience_bank.get("plant", {})
	if bank.is_empty():
		return {}
	var ramp_b: Array = bank.get("ramp_override", []).duplicate(true)
	for i in ramp_b.size():
		ramp_b[i] = _mutate_color(ramp_b[i], 0.06)
	var cfg_b: Dictionary = {
		"script": load("res://scripts/plant.gd"),
		"max_height": clampi(int(bank.get("max_height", 14)) + randi_range(-2, 2), 6, 40),
		"growth_rate": clampf(float(bank.get("growth_rate", 0.18)) + randf_range(-0.03, 0.03), 0.06, 0.42),
		"sway_amplitude": clampf(float(bank.get("sway_amplitude", 0.22)) + randf_range(-0.05, 0.05), 0.08, 0.70),
		"leaf_form": String(bank.get("leaf_form", "column")),
		"leaf_length": clampi(int(bank.get("leaf_length", 4)) + randi_range(-1, 1), 2, 14),
		"max_roots": clampi(int(bank.get("max_roots", 6)), 3, 14),
		"generation": int(bank.get("generation", 0)) + 1,
		"parent_lineage": String(bank.get("plant_name", "Reseed")),
		"parent_keys": bank.get("parent_keys", []).duplicate(),
		"plant_name": "",
	}
	return _apply_library_guided_plant_tuning({
		"ramp": ramp_b, "generation": int(bank.get("generation", 0)) + 1, "seed_config": cfg_b})


func _mutate_bank_genome(raw: Dictionary, organism_type: String) -> Dictionary:
	if raw == null or raw.is_empty():
		return {}
	var g: Dictionary = raw.duplicate(true)
	g["organism_type"] = organism_type
	g["generation"] = int(g.get("generation", 0)) + 1
	g["sex"] = randi() % 2
	match organism_type:
		"fish":
			g["base_color"] = _mutate_color(g.get("base_color", Color8(90, 140, 180)), 0.10)
			g["accent_color"] = _mutate_color(g.get("accent_color", Color8(180, 190, 210)), 0.08)
			g["tail_color"] = _mutate_color(g.get("tail_color", g.get("accent_color", Color8(180, 190, 210))), 0.08)
			g["max_age_s"] = clampf(float(g.get("max_age_s", 240.0)) * randf_range(0.95, 1.12), 120.0, 520.0)
			g["max_speed"] = clampf(float(g.get("max_speed", 1.4)) * randf_range(0.95, 1.10), 0.55, 3.0)
			g["jaw_claw_size"] = clampf(float(g.get("jaw_claw_size", 0.0)) + randf_range(-0.10, 0.14), 0.0, 1.2)
			g["size_potential"] = clampf(float(g.get("size_potential", 1.0)) + randf_range(-0.08, 0.12), 0.6, 2.4)
			g = _apply_library_guided_fish_tuning(g)
		"shrimp":
			g["base_color"] = _mutate_color(g.get("base_color", Color8(180, 90, 70)), 0.14)
			g["accent_color"] = _mutate_color(g.get("accent_color", Color8(245, 220, 200)), 0.08)
			g["adult_voxel_scale"] = clampf(float(g.get("adult_voxel_scale", 0.10)) + randf_range(-0.01, 0.015), 0.07, 0.30)
			g["max_age_s"] = clampf(float(g.get("max_age_s", 360.0)) * randf_range(0.95, 1.12), 160.0, 620.0)
			g["max_speed"] = clampf(float(g.get("max_speed", 0.85)) * randf_range(0.95, 1.08), 0.45, 1.45)
			g["claw_size"] = clampf(float(g.get("claw_size", 0.25)) + randf_range(-0.12, 0.16), 0.0, 1.2)
			g["body_length_factor"] = clampf(float(g.get("body_length_factor", 1.0)) + randf_range(-0.12, 0.14), 0.75, 1.7)
			g = _apply_library_guided_shrimp_tuning(g)
		"snail":
			g["shell_color"] = _mutate_color(g.get("shell_color", Color8(135, 44, 176)), 0.10)
			g["shell_size"] = clampf(float(g.get("shell_size", 1.0)) + randf_range(-0.05, 0.08), 0.65, 1.6)
			if randf() < 0.08:
				var shapes: Array = ["turbo", "trochus", "nassarius", "apple"]
				g["shell_shape"] = String(shapes[randi() % shapes.size()])
			g = _apply_library_guided_snail_tuning(g)
	return g


func _update_resilience_bank() -> void:
	var best_fish: Fish = _pick_elite_fish()
	if best_fish != null and best_fish.has_method("get_saved_genome"):
		_resilience_bank["fish"] = best_fish.get_saved_genome().duplicate(true)
	var best_shrimp: Shrimp = _pick_elite_shrimp()
	if best_shrimp != null and best_shrimp.has_method("get_saved_genome"):
		_resilience_bank["shrimp"] = best_shrimp.get_saved_genome().duplicate(true)
	var best_snail: Node3D = _pick_elite_snail()
	if best_snail != null and best_snail.has_method("get_saved_genome"):
		_resilience_bank["snail"] = best_snail.get_saved_genome().duplicate(true)
	var best_plant: Plant = _pick_elite_plant()
	if best_plant != null and best_plant.has_method("get_plant_genome"):
		_resilience_bank["plant"] = best_plant.get_plant_genome().duplicate(true)


func _spawn_resilience_genome(genome: Dictionary, organism_type: String) -> bool:
	if genome.is_empty():
		return false
	var w: Node = get_parent()
	if w == null or not w.has_method("spawn_library_entry"):
		return false
	return bool(w.spawn_library_entry(genome, organism_type))


func _spawn_resilience_plant(seed: Dictionary) -> bool:
	if seed.is_empty():
		return false
	var w: Node = get_parent()
	if w == null or not w.has_method("spawn_seedling"):
		return false
	var xz: Vector2 = Vector2.ZERO
	if w.has_method("sample_xz_in_tank"):
		xz = w.sample_xz_in_tank(0.55)
	var sub_y: float = float(w.get("SUBSTRATE_DEPTH")) if w.get("SUBSTRATE_DEPTH") != null else substrate_top_y
	var pos: Vector3 = Vector3(xz.x, sub_y, xz.y)
	w.spawn_seedling(pos, seed.get("ramp", []), int(seed.get("generation", 1)), seed.get("seed_config", {}))
	return true


func _run_resilience_seed(dt: float) -> void:
	_resilience_bank_timer = maxf(0.0, _resilience_bank_timer - dt)
	if _resilience_bank_timer <= 0.0:
		_resilience_bank_timer = RESILIENCE_BANK_REFRESH_S
		_update_resilience_bank()

	_resilience_timer = maxf(0.0, _resilience_timer - dt)
	if _resilience_timer > 0.0:
		return

	var fish_live: int = _count_live_fish()
	var shrimp_live: int = _count_live_shrimp()
	var snail_counts: Dictionary = _count_snails_and_eggs()
	var snails_live: int = int(snail_counts.get("snails", 0))
	var snail_eggs: int = int(snail_counts.get("eggs", 0))
	var plant_live: int = plants.size()
	var plant_biomass: int = total_plant_biomass

	var spawned: bool = false
	# Only rescue lineages that still have survivors — no respawn from zero.
	if fish_live > 0 and fish_live <= RESILIENCE_FISH_FLOOR \
			and eggs.size() <= 1 and randf() < RESILIENCE_RESCUE_CHANCE:
		spawned = _spawn_resilience_genome(_make_resilience_fish_genome(), "fish")

	if not spawned:
		if shrimp_live > 0 and shrimp_live <= RESILIENCE_SHRIMP_FLOOR \
				and randf() < RESILIENCE_RESCUE_CHANCE:
			spawned = _spawn_resilience_genome(_make_resilience_shrimp_genome(), "shrimp")

	if not spawned:
		if snails_live > 0 and snails_live <= RESILIENCE_SNAIL_FLOOR \
				and snail_eggs < RESILIENCE_MAX_SNAIL_EGGS \
				and randf() < RESILIENCE_RESCUE_CHANCE:
			spawned = _spawn_resilience_genome(_make_resilience_snail_genome(), "snail")

	if not spawned:
		if plant_live == 0 and randf() < RESILIENCE_WIND_SEED_CHANCE:
			spawned = _spawn_resilience_plant(_make_resilience_plant_seed())
			if spawned:
				log_story_event("Wind-blown spore — a lone plant colonizes bare substrate.")
		elif plant_live > 0 and plant_live < RESILIENCE_PLANT_FLOOR \
				and plant_biomass < RESILIENCE_PLANT_BIOMASS_FLOOR \
				and randf() < RESILIENCE_RESCUE_CHANCE * 1.5:
			spawned = _spawn_resilience_plant(_make_resilience_plant_seed())

	if spawned and fish_live < RESILIENCE_FISH_FLOOR:
		var w: Node = get_parent()
		if w != null:
			var xz: Vector2 = Vector2.ZERO
			if w.has_method("sample_xz_in_tank"):
				xz = w.sample_xz_in_tank(0.45)
			var fy: float = 6.3
			var water_h: Variant = w.get("WATER_HEIGHT")
			if water_h != null:
				fy = float(water_h) - 0.12
			_spawn_waste(Vector3(xz.x, fy, xz.y), 0.22, WasteParticle.KIND_FOOD)

	_resilience_timer = RESILIENCE_INTERVAL_S if spawned else 6.0


func _run_evolution_burst(dt: float) -> void:
	# Visual succession pulse: periodically spawn a clustered burst of mutated
	# plant/coral descendants so morphology turnover is visible on minute scales.
	_evo_burst_timer = maxf(0.0, _evo_burst_timer - dt)
	if _evo_burst_timer > 0.0:
		return
	# Keep cadence dynamic: stronger algae bloom => faster community turnover.
	_evo_burst_timer = EVO_BURST_INTERVAL_S * (0.70 if bloom_intensity > 0.55 else 1.0)
	var seed: Dictionary = _make_resilience_plant_seed()
	if seed.is_empty():
		return
	var w: Node = get_parent()
	if w == null or not w.has_method("spawn_seedling"):
		return
	var is_saltwater: bool = false
	var sw: Variant = w.get("_active_substrate_profile")
	if sw is Dictionary:
		is_saltwater = bool((sw as Dictionary).get("is_saltwater", false))
	var center: Vector2 = Vector2.ZERO
	if w.has_method("_pick_ecology_site"):
		var half_d: float = float(w.get("TANK_HALF_D")) if w.get("TANK_HALF_D") != null else 4.0
		center = w._pick_ecology_site(
			is_saltwater, -half_d * 0.82, half_d * 0.82, 0.35, 0.45)
	elif w.has_method("sample_xz_in_tank"):
		center = w.sample_xz_in_tank(0.45)
	var base_ramp: Array = seed.get("ramp", []).duplicate(true)
	var base_cfg: Dictionary = seed.get("seed_config", {}).duplicate(true)
	var cluster_n: int = randi_range(EVO_BURST_CLUSTER_MIN, EVO_BURST_CLUSTER_MAX)
	for i in cluster_n:
		var child_ramp: Array = base_ramp.duplicate(true)
		for j in child_ramp.size():
			child_ramp[j] = _mutate_color(child_ramp[j], 0.10 + bloom_intensity * 0.06)
		var child_cfg: Dictionary = base_cfg.duplicate(true)
		child_cfg["growth_rate"] = clampf(
			float(child_cfg.get("growth_rate", 0.18)) * randf_range(1.08, 1.34),
			0.08, 0.62)
		child_cfg["max_height"] = clampi(
			int(child_cfg.get("max_height", 14)) + randi_range(-2, 5), 5, 48)
		child_cfg["sway_amplitude"] = clampf(
			float(child_cfg.get("sway_amplitude", 0.18)) + randf_range(0.00, 0.10),
			0.02, 0.80)
		var ang: float = randf() * TAU
		var rad: float = randf_range(0.18, 1.10)
		var p := Vector3(center.x + cos(ang) * rad, substrate_top_y, center.y + sin(ang) * rad)
		w.spawn_seedling(p, child_ramp, int(seed.get("generation", 1)) + 1, child_cfg)


func _run_ecosystem_diary(dt: float) -> void:
	# Headline the Walstad cycles — bloom, crash, booms, busts, and balance.
	_diary_pulse_t = maxf(0.0, _diary_pulse_t - dt)
	var fish_n: int = fish.size()
	var shrimp_n: int = shrimp.size()
	var snail_n: int = snail_count
	var algae_n: int = algae.size()
	var plant_n: int = plants.size()
	var biomass: int = total_plant_biomass
	var n_total: float = substrate.total_above_baseline() if substrate != null else 0.0
	var o2: float = dissolved_o2
	var bloom: float = bloom_intensity
	var morph_d: int = 0
	var morph_seen: Dictionary = {}
	for f in fish:
		if not is_instance_valid(f):
			continue
		var ml: String = f.morph_label()
		if ml != f.species and not morph_seen.has(ml):
			morph_seen[ml] = true
			morph_d += 1

	# --- Extinction headlines (true zeros — no resilience from nothing) ---
	if fish_n == 0 and eggs.is_empty():
		if not _logged_fish_extinct:
			_logged_fish_extinct = true
			log_story_event("Fish extirpated — the tank runs without predators.")
	elif fish_n > 4:
		_logged_fish_extinct = false
	if shrimp_n == 0:
		if not _logged_shrimp_extinct:
			_logged_shrimp_extinct = true
			log_story_event("Shrimp colony collapsed — detritus loop thinning.")
	elif shrimp_n > 8:
		_logged_shrimp_extinct = false
	if snail_n == 0:
		if not _logged_snail_extinct:
			_logged_snail_extinct = true
			log_story_event("Snail grazers gone — algae may surge unchecked.")
	elif snail_n > 6:
		_logged_snail_extinct = false
	if plant_n == 0 and biomass == 0:
		if not _logged_plant_extinct:
			_logged_plant_extinct = true
			log_story_event("Plant cover lost — bare Walstad substrate cycling alone.")
	elif plant_n > 12:
		_logged_plant_extinct = false

	# --- Bloom phase transitions ---
	var phase: int = 0
	if bloom >= 0.52:
		phase = 2
	elif bloom >= 0.22:
		phase = 1
	elif _diary_bloom_phase >= 2 and bloom < 0.14:
		phase = 3
	if phase != _diary_bloom_phase:
		match phase:
			1:
				if _diary_bloom_phase == 0:
					log_story_event("Nutrients climbing — algae bloom beginning (N %.1f, plants %d)." % [n_total, plant_n])
			2:
				log_story_event("Green-water phase — bloom peak (algae %d, intensity %.0f%%)." % [algae_n, bloom * 100.0])
			3:
				log_story_event("Plants outcompeting the bloom — green water clearing (biomass %d)." % biomass)
		if phase != 3:
			_diary_bloom_phase = phase
		else:
			_diary_bloom_phase = 0

	# --- O₂ stress / recovery ---
	if o2 < 0.38 and not _diary_o2_stressed:
		_diary_o2_stressed = true
		log_story_event("Dissolved O₂ dipping — surface gas exchange struggling (%.0f%%)." % (o2 * 100.0))
	elif o2 > 0.62 and _diary_o2_stressed:
		_diary_o2_stressed = false
		log_story_event("O₂ recovering — photosynthesis catching up with respiration.")

	# --- Population milestones (log once per threshold crossed) ---
	for threshold in [25, 50, 100, 200, 400]:
		if shrimp_n >= threshold and _diary_milestone_shrimp < threshold:
			_diary_milestone_shrimp = threshold
			log_story_event("Shrimp colony swelling — %d adults and fry in the water column." % shrimp_n)
	for threshold in [8, 15, 30, 60]:
		if fish_n >= threshold and _diary_milestone_fish < threshold:
			_diary_milestone_fish = threshold
			log_story_event("Fish population at %d — territory and predation shaping the web." % fish_n)

	# --- Generation depth ---
	var max_gen: int = 0
	for f in fish:
		if is_instance_valid(f):
			max_gen = maxi(max_gen, int(f.get("generation")))
	for s in shrimp:
		if is_instance_valid(s):
			max_gen = maxi(max_gen, int(s.get("generation")))
	for threshold in [10, 25, 50, 100, 200]:
		if max_gen >= threshold and _diary_milestone_gen < threshold:
			_diary_milestone_gen = threshold
			log_story_event("Lineages deepening — generation %d reached in the tank." % max_gen)

	# --- New morphs discovered ---
	if morph_d > _diary_last_morph_distinct and _diary_last_morph_distinct > 0:
		log_story_event("New morphs drifting in the gene pool (+%d distinct forms)." % (morph_d - _diary_last_morph_distinct))
	_diary_last_morph_distinct = morph_d

	# --- Periodic Walstad pulse (every ~4 sim-minutes) ---
	if _diary_pulse_t > 0.0:
		return
	_diary_pulse_t = randf_range(210.0, 300.0)
	var pulse: String = _compose_walstad_pulse(
		fish_n, shrimp_n, snail_n, plant_n, algae_n, biomass, n_total, o2, bloom)
	log_story_event(pulse)


func _compose_walstad_pulse(fish_n: int, shrimp_n: int, snail_n: int, plant_n: int,
		algae_n: int, biomass: int, n_total: float, o2: float, bloom: float) -> String:
	# One scannable sentence capturing the tank's current ecological character.
	if bloom > 0.45 and plant_n < 40:
		return "Walstad pulse: cycling tank — bloom %.0f%%, sparse planting, N %.1f." % [bloom * 100.0, n_total]
	if biomass > 1200 and bloom < 0.2:
		return "Walstad pulse: mature jungle — biomass %d, %d plants, O₂ %.0f%%." % [biomass, plant_n, o2 * 100.0]
	if shrimp_n > fish_n * 3 and fish_n < 12:
		return "Walstad pulse: invertebrate-dominated — %d shrimp, %d fish, snails %d." % [shrimp_n, fish_n, snail_n]
	if fish_n > 20 and shrimp_n < fish_n:
		return "Walstad pulse: predator-forward — %d fish hunting %d shrimp." % [fish_n, shrimp_n]
	if algae_n < 5 and snail_n > 20:
		return "Walstad pulse: grazers keeping algae thin — snails %d, algae %d." % [snail_n, algae_n]
	if n_total > 6.0 and bloom > 0.3:
		return "Walstad pulse: nutrient-rich water — N %.1f, algae %d, plants %d." % [n_total, algae_n, plant_n]
	return "Walstad pulse: %d fish, %d shrimp, %d plants, biomass %d, bloom %.0f%%." % [
		fish_n, shrimp_n, plant_n, biomass, bloom * 100.0]


func _emit_stats() -> void:
	# Re-filter here: _emit_stats runs at 1Hz, independent of the 10Hz _tick
	# filter. Between two _tick calls, the engine may actually delete a
	# queue_freed Fish/Plant; the array still holds the stale ref. Iterating
	# without is_instance_valid causes "previously freed" crashes after long
	# runs with high mortality.
	_reconcile_shrimp_registry()
	var snails_container: Node3D = ensure_snails_root()
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
	# Tracked across fish + shrimp + snails. Declared here so the single fish
	# pass below folds in generation (was a second full fish loop).
	var max_gen: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.maturity == Fish.MATURITY_ADULT:
			n_adults += 1
		elif f.maturity == Fish.MATURITY_FRY:
			n_fry += 1
		max_gen = maxi(max_gen, int(f.generation))
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
	var shrimp_total: int = 0
	for sh in shrimp:
		if not is_instance_valid(sh):
			continue
		shrimp_total += 1
		if sh.maturity == Shrimp.MATURITY_ADULT:
			shrimp_adults += 1
		elif sh.maturity == Shrimp.MATURITY_FRY:
			shrimp_fry += 1
		max_gen = maxi(max_gen, int(sh.generation))
	# Snails: peek at the children of snails_root - they don't live in a
	# typed array on SimDriver. Count adults vs babies via the per-snail
	# is_baby flag set by snail.gd.
	var snail_total: int = 0
	var snail_adults: int = 0
	var snail_babies: int = 0
	if snails_container != null:
		for s in snails_container.get_children():
			if not is_instance_valid(s):
				continue
			# Only count nodes that look like snails (have a generation field +
			# is_baby property). Skip stray markers / decoration / egg sacs.
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
		"shrimp_total": shrimp_total,
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
		"ammonia": water_chemistry.ammonia,
		"nitrite": water_chemistry.nitrite,
		"nitrate": water_chemistry.nitrate,
		"cycle_phase": water_chemistry.cycle_phase,
		"cycle_label": WaterChemistry.phase_label(water_chemistry.cycle_phase),
		"aeration_fixture": aeration_fixture,
	}
	# Capture this snapshot into the ring buffer so chip-tap sparklines have
	# a 2-minute history to draw. _emit_stats fires at 1 Hz so HISTORY_LEN
	# entries = HISTORY_LEN seconds of history. Cheap (one append + maybe a
	# pop_front per metric per second).
	_push_history_sample(s)
	stats_changed.emit(s)
	print_verbose("[walstad_loom] ", s)


# ---- Population history ring buffer ----
#
# 120-second rolling window of the headline stat values, sampled at the
# 1 Hz _emit_stats cadence. main.gd reads this when the user taps a chip
# in the top HUD and renders it as a sparkline so you can see boom-bust
# population cycles visually instead of having to remember the last
# value you saw. Keys mirror chip ids where reasonable.
const HISTORY_LEN: int = 120
var population_history: Dictionary = {
	"fish_total": [],
	"shrimp_total": [],
	"snails_total": [],
	"algae_clusters": [],
	"plants_alive": [],
	"plant_total_biomass": [],
	"substrate_nutrients_total": [],
	"dissolved_o2": [],
	"ammonia": [],
	"nitrate": [],
}


func _push_history_sample(stats: Dictionary) -> void:
	for key in population_history.keys():
		var arr: Array = population_history[key]
		arr.append(stats.get(key, 0))
		if arr.size() > HISTORY_LEN:
			arr.pop_front()


# ---- Tank story log ----
#
# Append-only diary of meaningful events: first egg laid, first hatch,
# first death, breeding pair formed, speciation event, algae bloom,
# crash, etc. Each entry is `{"t": sim-seconds, "text": "..."}`. Capped
# at MAX_STORY_EVENTS so a long-running tank doesn't bloat the save.
# Read by main.gd's story dialog (tap "Menu" → "Story") so the player
# can scroll back through the tank's history.
const MAX_STORY_EVENTS: int = 200
var story_events: Array = []
# First-time-only flags so the diary doesn't repeat the same headline
# every time the event fires.
var _logged_first_egg: bool = false
var _logged_first_hatch: bool = false
var _logged_first_death: bool = false


func log_story_event(text: String) -> void:
	# Tag with elapsed runtime so the dialog can render "Day 3 morning"
	# or "12 min ago" labels later. The text itself is kept short —
	# headline-style — so the dialog stays scannable.
	var entry: Dictionary = {
		"t": elapsed_runtime_s,
		"day_phase": day_phase,
		"text": text,
	}
	story_events.append(entry)
	if story_events.size() > MAX_STORY_EVENTS:
		story_events.pop_front()
	# Trigger an ambient plink so the player hears a story beat even if
	# the dialog is closed.
	var amb: Node = _ambient_audio()
	if amb != null and amb.has_method("play_aquarium_event"):
		amb.play_aquarium_event("story", 0.72)


# ============================================================================
# SAVE / LOAD
# ============================================================================
# save_state() walks every entity, mints ids where missing, and returns a
# JSON-serializable Dictionary. load_state(d) does the inverse, spawning
# entities in dependency order: substrate first, then plants (fish reference
# plants for breeding), then creatures, then transient particles, then
# resolving cross-references in a final pass.

const SAVE_STATE_VERSION: int = 2


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
	# Stocking preset goes in the save header too. Substrate alone wasn't
	# enough to invalidate the save on preset change — switching e.g.
	# Community → Tetra School left both at "aquasoil", the compatibility
	# check passed, and load_state restored the old community fish instead
	# of letting the new preset's stocking spawn. TankSaves.is_active_save_compatible
	# now checks this field too.
	var cfg_preset: String = String(cfg.tank_preset) if cfg != null else ""
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
			"tank_preset": cfg_preset,
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
		"discovered_species": _get_discovered_species_for_save(),
	}
	if water_chemistry != null:
		out["water_chemistry"] = water_chemistry.to_save_dict()
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
	# Floating surface plants live on World (not in plants[]). Persist them so
	# custom Creature-Creator floaters survive a reload.
	var w_save: Node = get_parent()
	if w_save != null and w_save.has_method("floaters_to_save"):
		out["floaters"] = w_save.floaters_to_save()
	return out


# Snapshot of SpeciesLibrary.tank_entries for inclusion in state.json. Returns
# an empty array if the autoload isn't available (defensive — see comment on
# _record_species_discovery).
func _get_discovered_species_for_save() -> Array:
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib == null:
		return []
	return lib.get_tank_entries()


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
	var save_ver: int = int(d.get("version", 0))
	if save_ver != SAVE_STATE_VERSION:
		push_warning("[walstad_loom] save version mismatch; got %s, expected %d." % [save_ver, SAVE_STATE_VERSION])

	# 0. Restore species discoveries BEFORE any spawn happens. Spawn helpers
	# in load_state bypass register_fish (no double-recording risk), but we
	# want the library populated before the panel can open during load.
	var lib := get_node_or_null("/root/SpeciesLibrary")
	if lib != null:
		lib.set_tank_entries(d.get("discovered_species", []))

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
	if water_chemistry != null:
		water_chemistry.apply_save_dict(d.get("water_chemistry", {}), save_ver)

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

	# 9b. Floating surface plants (stored on World, not in plants[]).
	var w_load: Node = get_parent()
	if w_load != null and w_load.has_method("restore_floaters"):
		w_load.restore_floaters(d.get("floaters", []))

	# 10. Cross-reference pass: resolve partner_id → partner Node refs.
	_resolve_refs(d, id_map)

	sync_species_discoveries()

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
	var snails_parent: Node3D = ensure_snails_root()
	if snails_parent == null:
		return null
	var snail_script := load("res://scripts/snail.gd")
	if snail_script == null:
		return null
	var sn: Node3D = snail_script.new()
	snails_parent.add_child(sn)
	sn.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	if sn.has_method("apply_save_dict"):
		sn.apply_save_dict(d)
	if sn.has_method("get_saved_genome"):
		_record_organism_discovery(sn.get_saved_genome())
	return sn


func _spawn_snail_egg_from_dict(d: Dictionary) -> Node3D:
	var snails_parent: Node3D = ensure_snails_root()
	if snails_parent == null:
		return null
	var egg_script := load("res://scripts/snail_egg.gd")
	if egg_script == null:
		return null
	var se: Node3D = egg_script.new()
	snails_parent.add_child(se)
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
