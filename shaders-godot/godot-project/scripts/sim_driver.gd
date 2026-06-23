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
signal eco_event(kind: String, text: String, severity: int)

# Residents registry: fired as living creatures (fish/shrimp/snail/clam) enter
# and leave the tank, so UI can keep a live roster without polling. Removal is
# driven off each creature's tree_exiting (the node is still valid then), so no
# per-creature death code needs to change.
signal creature_added(creature: Node)
signal creature_removed(creature: Node)
# Fired when the player's favorite set changes (star toggled, or restored on load).
signal favorites_changed()

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
var plant_fragments: Array = []
var waste: Array[WasteParticle] = []
var eggs: Array[FishEgg] = []
var algae: Array = []   # Algae nodes; untyped so the script loads even if
						# the Algae class hasn't reimported into the global
						# registry yet on a fresh project scan.
var clams: Array = []   # Clam filter feeders. Untyped for the same reason
						# as algae — the class is new, untyped avoids load
						# order brittleness on fresh project scans.
var substrate: SubstrateGrid = null
var snails_root: Node3D = null   # set by world so SimDriver can scan snail children
var algae_root: Node3D = null    # container for algae voxels
var clams_root: Node3D = null    # bivalve filter feeders on the substrate
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

# ---- Player feed-tap memory ----
# Each ⌘+LMB drop records the position; the fish food finder reads this
# to bias its search toward recently-fed spots, simulating real fish
# learning to congregate where pellets habitually land. Entries expire
# after FEED_MEMORY_TTL seconds so old habit-spots fade.
const FEED_MEMORY_TTL: float = 30.0
const FEED_MEMORY_CAP: int = 5

# Global waste-particle cap. Each WasteParticle is a Node3D + animation;
# once a tank has many plants + no cleanup crew, decay byproducts can
# accumulate into thousands of particles, killing framerate AND visually
# reading as a constant rain of falling stuff. Cap at 240 — above that,
# decay spawns silently drop (food always still lands).
const WASTE_CAP: int = 240
# Each entry: {pos: Vector3, t: float (seconds since recorded)}
var _feed_memory: Array = []

# ---- Feed-time anticipation ----
# Wall-clock minute-of-day of every feed drop, capped to 30 entries (covers
# ~a month of once-daily feeds). The anticipation gate fires when at least
# 3 historical drops sit within ±5 minutes of the current minute-of-day —
# a robust "the player usually feeds around now" signal that doesn't fire
# on a single coincidence. Persists in save_state so the pattern survives
# across sessions.
const FEED_TIME_HISTORY_CAP: int = 30
const FEED_ANTICIPATION_WINDOW_MIN: int = 5
const FEED_ANTICIPATION_THRESHOLD: int = 3
var _feed_time_history: Array = []  # ints, minute-of-day (0..1439)

# ---- Player glance ("look at the glass") ----
# main.gd pushes the camera's world position once per frame; we compute a
# nearby "interest point" inside the tank and a 0..1 proximity scalar.
# Bold fish (personality.boldness > 0.6) bias their wander toward this
# point — the result is the real-aquarium moment of fish drifting over
# when you walk up to the glass.
var _player_glance_point: Vector3 = Vector3.ZERO
var _player_glance_strength: float = 0.0
var _player_glance_hold_s: float = 0.0
var _player_glance_last_pos: Vector3 = Vector3.ZERO

# ---- Schooling pulse ----
# Tank-wide phase that all fish sample to modulate their school tightness.
# Reads on screen as the school "breathing" — synchronized expand/contract
# every ~30 sim-seconds. Costs one float increment per tick and one sin()
# per fish per tick.
var _school_pulse_phase: float = 0.0
const SCHOOL_PULSE_PERIOD: float = 28.0

# ---- Mourning ----
# When a named fish dies, school-mates of the same species near the death
# point slow down and tighten cohesion for ~60s. Each entry is
# {species, position, until_unix}. Pruned in _tick when expired.
const MOURNING_DURATION_S: int = 60
const MOURNING_RADIUS: float = 6.0
var _mourning_events: Array = []


func record_feed_drop(world_pos: Vector3, food_subtype: int = WasteParticle.FOOD_SUB_PELLET) -> void:
	_feed_memory.append({"pos": world_pos, "t": 0.0, "subtype": food_subtype})
	while _feed_memory.size() > FEED_MEMORY_CAP:
		_feed_memory.pop_front()
	# Also record the wall-clock minute-of-day for anticipation tracking.
	# Dedup the same minute so a player who drops 5 pellets in a row only
	# counts as one "feeding event" — pattern matters, frequency doesn't.
	var t: Dictionary = Time.get_time_dict_from_system()
	var mod: int = int(t.get("hour", 0)) * 60 + int(t.get("minute", 0))
	var new_minute: bool = _feed_time_history.is_empty() or int(_feed_time_history[-1]) != mod
	if new_minute:
		_feed_time_history.append(mod)
		while _feed_time_history.size() > FEED_TIME_HISTORY_CAP:
			_feed_time_history.pop_front()
	# Music hook: food drop triggers a build → drop arc on the trance bed.
	# Only fire once per minute so a flurry of pellets doesn't keep restarting it.
	if new_minute:
		var audio := _ambient_audio()
		if audio != null and audio.has_method("play_feeding_event"):
			audio.play_feeding_event()
	var w_feed: Node = get_parent()
	if w_feed != null and w_feed.has_method("scatter_floaters_at") \
			and world_pos.y > w_feed.WATER_HEIGHT - 0.5:
		w_feed.scatter_floaters_at(world_pos, 1.6, 1.1)


# True when the current wall-clock minute is close to a minute the player
# has historically fed at (≥ FEED_ANTICIPATION_THRESHOLD matches within
# ±FEED_ANTICIPATION_WINDOW_MIN minutes). Cheap to call per fish — O(30).
func feed_anticipation_active() -> bool:
	if _feed_time_history.size() < FEED_ANTICIPATION_THRESHOLD:
		return false
	var t: Dictionary = Time.get_time_dict_from_system()
	var now_mod: int = int(t.get("hour", 0)) * 60 + int(t.get("minute", 0))
	var matches: int = 0
	for m_v in _feed_time_history:
		var m: int = int(m_v)
		# Wrap-around distance on a 24h clock.
		var d: int = absi(m - now_mod)
		if d > 720:
			d = 1440 - d
		if d <= FEED_ANTICIPATION_WINDOW_MIN:
			matches += 1
			if matches >= FEED_ANTICIPATION_THRESHOLD:
				return true
	return false


# Called by main.gd._process with the camera's world position. We compute
# a glance point INSIDE the tank near the camera (so fish can swim toward
# it without diving through the wall) and a 0..1 proximity strength. The
# strength rises further when the camera holds still — proxy for "the
# player has been staring at the tank, the fish notice."
func update_player_glance(camera_pos: Vector3) -> void:
	var w: Node = get_parent()
	if w == null:
		_player_glance_strength = 0.0
		return
	var hw: float = float(w.get("TANK_HALF_W") if w.get("TANK_HALF_W") != null else 8.0)
	var hd: float = float(w.get("TANK_HALF_D") if w.get("TANK_HALF_D") != null else 4.0)
	var hh: float = float(w.get("TANK_HEIGHT") if w.get("TANK_HEIGHT") != null else 7.0)
	# Project camera into tank-space and clamp to the inner volume. The
	# clamped point is where bold fish will swim toward.
	var inner: Vector3 = Vector3(
		clampf(camera_pos.x, -hw + 0.5, hw - 0.5),
		clampf(camera_pos.y, 0.4, hh - 0.4),
		clampf(camera_pos.z, -hd + 0.5, hd - 0.5),
	)
	_player_glance_point = inner
	# Distance from camera to the clamped inner point measures how close
	# the player has their face to the glass. Threshold = 2 × the tank's
	# largest half-dim; outside that the strength is zero.
	var dist: float = camera_pos.distance_to(inner)
	var threshold: float = maxf(hw, hd) * 2.2
	var raw: float = clampf(1.0 - dist / threshold, 0.0, 1.0)
	# Hold bonus — when the camera barely moves, strength climbs toward 1.
	var moved: float = camera_pos.distance_to(_player_glance_last_pos)
	if moved < 0.05:
		_player_glance_hold_s = minf(_player_glance_hold_s + 0.016, 6.0)
	else:
		_player_glance_hold_s = 0.0
	_player_glance_last_pos = camera_pos
	var hold_bonus: float = clampf(_player_glance_hold_s / 3.0, 0.0, 0.4)
	_player_glance_strength = clampf(raw * (0.6 + hold_bonus), 0.0, 1.0)


func get_player_glance() -> Dictionary:
	return {
		"point": _player_glance_point,
		"strength": _player_glance_strength,
	}


# Read the user's CO2 dosing config (0..1). Plants compare against their
# own co2_demand to compute growth + color + pearling response. The
# config is in TankConfig (set via the settings panel); we wrap it here
# so plants can query a single owner instead of touching TankConfig direct.
func co2_level() -> float:
	return dissolved_co2_level()


func dissolved_co2_level() -> float:
	if water_chemistry != null:
		return water_chemistry.dissolved_co2_level()
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 0.35
	var v: Variant = cfg.get("co2_level")
	if v == null:
		return 0.35
	return clampf(float(v), 0.0, 1.0)


func spawn_plant_fragment(at: Vector3, genome: Dictionary, ramp: Array,
		units: int, velocity: Vector3) -> void:
	var frag := PlantFragment.new()
	if plants_root != null:
		plants_root.add_child(frag)
	else:
		add_child(frag)
	frag.init(at, genome, ramp, units, velocity)
	plant_fragments.append(frag)


# Light spectrum 0..1 (cool→warm). Used by plant red intensification:
# warm-leaning bulbs boost red plants further, cool-leaning bulbs dampen
# them. Same plumbing pattern as co2_level — single read, cached implicitly
# by the per-tick caller.
func light_spectrum() -> float:
	var cfg: Node = get_node_or_null("/root/TankConfig")
	if cfg == null:
		return 0.5
	var v: Variant = cfg.get("light_spectrum")
	if v == null:
		return 0.5
	return clampf(float(v), 0.0, 1.0)


# Shift+click glass tap — brief attract pulse so bold fish drift toward the ripple.
func pulse_glass_tap(world_pos: Vector3) -> void:
	_player_glance_point = world_pos
	_player_glance_strength = 1.0
	_player_glance_hold_s = 3.0


# Sample the tank-wide schooling pulse phase. Returns -1..1, sin-shaped.
# Fish.gd multiplies their school tightness by (1.0 + this * 0.15) so the
# tank visibly breathes in unison. Phase ticks in _tick.
func school_pulse() -> float:
	return sin(_school_pulse_phase)


# Raw phase (radians) for tail-wag lock among conspecific schoolers.
func school_pulse_phase() -> float:
	return _school_pulse_phase


# Append a mourning event (called when a named fish dies). Pruned in _tick.
func _record_mourning(species_id: String, pos: Vector3, weight: float = 1.0) -> void:
	if species_id == "":
		return
	# Weighted mourning (#90): a favorited / long-lived / alpha individual's
	# death mourns harder and longer than a random fry's.
	var dur: int = int(MOURNING_DURATION_S * clampf(weight, 1.0, 2.5))
	_mourning_events.append({
		"species": species_id,
		"position": pos,
		"until_unix": int(Time.get_unix_time_from_system()) + dur,
		"weight": clampf(weight, 1.0, 2.5),
	})
	# Cap so a long crash doesn't grow this unbounded.
	while _mourning_events.size() > 20:
		_mourning_events.pop_front()


# Return 0..1 mourning intensity for a fish of the given species at the
# given position. Fish.gd reads this in tick and uses it to dampen its
# top speed and tighten schooling cohesion — the school visibly slows
# around a recent death. O(active mournings); typically 0..2 entries.
func mourning_intensity_for(species_id: String, pos: Vector3) -> float:
	if _mourning_events.is_empty():
		return 0.0
	var now: int = int(Time.get_unix_time_from_system())
	var strongest: float = 0.0
	for entry in _mourning_events:
		var e: Dictionary = entry
		if String(e.get("species", "")) != species_id:
			continue
		var until: int = int(e.get("until_unix", 0))
		if until <= now:
			continue
		var ep: Vector3 = e.get("position", Vector3.ZERO)
		var d: float = ep.distance_to(pos)
		if d > MOURNING_RADIUS:
			continue
		# Distance + time falloff. Recent + close = ~1.0, far + about to
		# expire = ~0. Time normalisation goes (until - now) / DURATION.
		var ew: float = float(e.get("weight", 1.0))
		var eff_dur: float = float(MOURNING_DURATION_S) * ew
		var time_w: float = clampf(float(until - now) / eff_dur, 0.0, 1.0)
		var dist_w: float = 1.0 - d / (MOURNING_RADIUS * ew)
		if dist_w <= 0.0:
			continue
		strongest = maxf(strongest, time_w * dist_w * minf(ew, 1.4))
	return strongest


# Build the personalized epitaph for a named fish death. Reads bio dict so
# the story log says "Mira passed peacefully — 47 meals, 8 children, 3
# fights won" instead of the generic "First natural death — a tetra…".
# Returns "" if the fish lacks a name; caller falls back to the generic
# message in that case.
func _epitaph_for_fish(actor: Node) -> String:
	if actor == null or actor.get("fish_name") == null:
		return ""
	var fname: String = String(actor.fish_name)
	if fname == "":
		return ""
	var species_id: String = String(actor.species) if actor.get("species") != null else "fish"
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s, a %s, has passed" % [fname, species_id])
	var bio_v: Variant = actor.get("bio")
	if bio_v is Dictionary:
		var bio_d: Dictionary = bio_v
		var meals: int = int(bio_d.get("meals_eaten", 0))
		var kids: int = int(bio_d.get("offspring", 0))
		var fights: int = int(bio_d.get("fights_won", 0))
		var stats: PackedStringArray = PackedStringArray()
		if meals > 0: stats.append("%d meals" % meals)
		if kids > 0: stats.append("%d children" % kids)
		if fights > 0: stats.append("%d fights won" % fights)
		if stats.size() > 0:
			parts.append(" — " + ", ".join(stats))
	parts.append(".")
	return "".join(parts)


# Return {offset: Vector3, strength: float} where offset points from
# `pos` toward the average of active feed memories within `radius`, and
# strength is 0..1 (higher = more / fresher memories). Used by fish.gd
# to bias the food finder. No allocations when memory is empty.
func recent_feed_spot_bias(pos: Vector3, radius: float) -> Dictionary:
	if _feed_memory.is_empty():
		return {"offset": Vector3.ZERO, "strength": 0.0}
	var sum: Vector3 = Vector3.ZERO
	var weight_total: float = 0.0
	var r2: float = radius * radius
	for entry in _feed_memory:
		var e: Dictionary = entry
		var p: Vector3 = e.get("pos", Vector3.ZERO)
		var t: float = float(e.get("t", 0.0))
		if t >= FEED_MEMORY_TTL:
			continue
		var d2: float = pos.distance_squared_to(p)
		if d2 > r2:
			continue
		# Weight = freshness × proximity. Both 0..1.
		var freshness: float = 1.0 - t / FEED_MEMORY_TTL
		var prox: float = 1.0 - sqrt(d2) / radius
		var w: float = freshness * prox
		sum += (p - pos) * w
		weight_total += w
	if weight_total <= 0.0001:
		return {"offset": Vector3.ZERO, "strength": 0.0}
	return {
		"offset": sum / weight_total,
		"strength": clampf(weight_total / float(FEED_MEMORY_CAP), 0.0, 1.0),
	}
# Live adult+baby snail count, refreshed each tick from the baby-snail scan
# loop. Used by the O2 model for snail respiration (cheap: avoids a second
# walk of snails_root just for the oxygen step).
var snail_count: int = 0
var total_plant_biomass: int = 0
# Health-weighted biomass: melting / etiolating / bleaching plants count for
# little, so a plant crash compounds into an O2 crisis (#29). Updated each tick
# alongside total_plant_biomass.
var total_photosynthetic_biomass: float = 0.0

# ---- Carrying-capacity model ----
# Plants are the bottleneck for sustainable fish stocking — they oxygenate
# the water, soak ammonia/nitrate, and provide cover for fry. We expose a
# soft cap derived from plant biomass + an aeration bonus + a tank-volume
# multiplier. The cap is "soft" in that breeding doesn't hard-stop at the
# threshold — instead every fish over the cap accumulates background
# stress proportional to the overshoot, which throttles breeding via the
# existing stress-blocks-courtship gate. The HUD also shows the
# current/cap ratio so the player gets a visible warning before the
# tank crashes.
const CARRYING_CAPACITY_PLANT_DIVISOR: float = 18.0
const CARRYING_CAPACITY_AERATION_BONUS: int = 3
const CARRYING_CAPACITY_MIN: int = 6
const CARRYING_CAPACITY_MAX: int = 80


# Return the world-space position of the closest driftwood voxel to
# `pos`, or Vector3.ZERO if none / world has no driftwood. Used by
# wood-grazer fish (bristlenose pleco) to bias toward the log when
# they're hungry. Cheap — walks world._driftwood_voxels which is bounded
# to a few hundred voxels at most. Throttled to once a second per fish
# via the caller's gating.
func nearest_driftwood_pos(pos: Vector3) -> Vector3:
	var w: Node = get_parent()
	if w == null:
		return Vector3.ZERO
	var dw_v: Variant = w.get("_driftwood_voxels")
	if not (dw_v is Array):
		return Vector3.ZERO
	var dw: Array = dw_v
	if dw.is_empty():
		return Vector3.ZERO
	var best: Vector3 = Vector3.ZERO
	var best_d2: float = 1e9
	for v in dw:
		if v == null or not is_instance_valid(v):
			continue
		var d2: float = (v.global_position - pos).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = v.global_position
	return best


func fish_carrying_capacity() -> int:
	var w_volume_mult: float = 1.0
	var w: Node = get_parent()
	if w != null:
		# Scale gently with tank volume. Tiny scenarios (polyp jar) get a
		# proportionally lower cap; big show tanks get a little more.
		var hw: Variant = w.get("TANK_HALF_W")
		var hd: Variant = w.get("TANK_HALF_D")
		var h: Variant = w.get("TANK_HEIGHT")
		if hw != null and hd != null and h != null:
			var ref_vol: float = 8.0 * 4.0 * 7.0 * 4.0  # the default-tank volume
			var live_vol: float = float(hw) * float(hd) * float(h) * 4.0
			w_volume_mult = clampf(live_vol / ref_vol, 0.4, 1.6)
	var biomass_cap: int = int(float(total_plant_biomass) / CARRYING_CAPACITY_PLANT_DIVISOR)
	var aeration_bonus: int = 0
	match aeration_fixture:
		"filter":
			aeration_bonus = CARRYING_CAPACITY_AERATION_BONUS + 2
		"disk":
			aeration_bonus = CARRYING_CAPACITY_AERATION_BONUS
		"stick":
			aeration_bonus = CARRYING_CAPACITY_AERATION_BONUS - 1
		_:
			aeration_bonus = 0
	var raw: float = (float(biomass_cap) + float(aeration_bonus)) * w_volume_mult
	return clampi(int(round(raw)), CARRYING_CAPACITY_MIN, CARRYING_CAPACITY_MAX)


# Lagged carrying capacity (#35): the tank doesn't respond instantly to a
# plant crash. _cap_smooth trails fish_carrying_capacity() so a sudden loss of
# plants gives the fish a grace period before stocking pressure ramps —
# delayed density-dependent feedback, the way a real tank's bioload lags its
# biofiltration.
var _cap_smooth: float = -1.0


func _tick_carrying_capacity(dt: float) -> void:
	var target: float = float(fish_carrying_capacity())
	if _cap_smooth < 0.0:
		_cap_smooth = target
	else:
		# ~30 s time constant; capacity drops are felt gently, gains arrive
		# only as fast as plants actually regrow anyway.
		_cap_smooth = lerpf(_cap_smooth, target, clampf(dt / 30.0, 0.0, 1.0))


func fish_carrying_capacity_smoothed() -> int:
	if _cap_smooth < 0.0:
		return fish_carrying_capacity()
	return maxi(CARRYING_CAPACITY_MIN, int(round(_cap_smooth)))


# Returns the live fish count / capacity ratio. Above 1.0 = over-stocked
# and fish are accumulating stress at the rate (ratio - 1.0) * 0.06/s.
func fish_stocking_ratio() -> float:
	var cap: int = fish_carrying_capacity_smoothed()
	if cap <= 0:
		return 0.0
	return float(fish.size()) / float(cap)


# Long-arc bookkeeping: maturation milestones, tank legacy, stability curve,
# equipment aging, anniversary reflections. Runs every tick but does its heavy
# work on slow cadences.
func _tick_long_arc(dt: float) -> void:
	# Equipment aging (#77): filter media matures over the first sim-days
	# (better biofiltration) then slowly clogs until the player rinses it.
	if aeration_fixture == "filter":
		_filter_media_age_s += dt
		_filter_clog = clampf(_filter_clog + dt * 0.0000045, 0.0, 0.5)
	# Stability curve (#76): how steady the tank's chemistry is. 1.0 = serene,
	# 0 = crashing. Smoothed so it reads as a slow-settling line.
	_stability_sample_t -= dt
	if _stability_sample_t <= 0.0:
		_stability_sample_t = 1.0
		var inst: float = 1.0
		if water_chemistry != null:
			inst -= clampf(float(water_chemistry.toxic_ammonia) * 4.0, 0.0, 0.5)
			inst -= clampf(float(water_chemistry.nitrite) * 1.2, 0.0, 0.3)
		inst -= clampf(absf(dissolved_o2 - 0.65) * 1.2, 0.0, 0.3)
		inst -= clampf(bloom_intensity * 0.4, 0.0, 0.25)
		stability = lerpf(stability, clampf(inst, 0.0, 1.0), 0.08)
		# Crash legacy (#75): record when the tank dips into a real crash so the
		# anniversary can recall "survived 2 crashes."
		if stability < 0.30 and not _crash_latch:
			_crash_latch = true
			tank_legacy["crashes"] = int(tank_legacy.get("crashes", 0)) + 1
		elif stability > 0.55:
			_crash_latch = false
	# Slow cadence: legacy peaks + day milestones + anniversary.
	_long_arc_t -= dt
	if _long_arc_t <= 0.0:
		_long_arc_t = 5.0
		tank_legacy["peak_fish"] = maxi(int(tank_legacy.get("peak_fish", 0)), fish.size())
		tank_legacy["peak_shrimp"] = maxi(int(tank_legacy.get("peak_shrimp", 0)), shrimp.size())
		tank_legacy["peak_biomass"] = maxi(int(tank_legacy.get("peak_biomass", 0)), total_plant_biomass)
		_check_maturation_milestones()


# Gentle care nudges (#91/#92): when the tank drifts toward imbalance, surface
# ONE soft, optional suggestion framed as the tank asking for help — never a
# failure popup, and never repeated back-to-back. Every problem has a visible
# tell; this names it kindly and suggests a care action that matters (#93).
func _tick_care_nudge(dt: float) -> void:
	_nudge_timer -= dt
	if _nudge_timer > 0.0:
		return
	_nudge_timer = 75.0
	if water_chemistry == null:
		return
	var msg: String = ""
	var key: String = ""
	if float(water_chemistry.toxic_ammonia) > 0.06:
		key = "nh3"
		msg = "Ammonia is stressing the fish — ease off feeding while the biofilter catches up."
	elif dissolved_o2 < 0.42:
		key = "o2"
		msg = "The fish are gulping near the surface — more plants, fewer fish, or a water change would help."
	elif float(water_chemistry.nitrate) > 1.1:
		key = "no3"
		msg = "Nitrate is climbing — a partial water change or some floating plants would freshen it."
	elif bloom_intensity > 0.55:
		key = "bloom"
		msg = "Algae is taking hold — more plants or floating cover will starve it out."
	elif _filter_clog > 0.35:
		key = "clog"
		msg = "The filter flow is dropping — a quick rinse would restore it."
	if msg == "" or key == _last_nudge:
		# Don't repeat the same nudge twice in a row; let it breathe.
		if msg == "":
			_last_nudge = ""
		return
	_last_nudge = key
	# Severity 1 = gentle. Don't spam the permanent story log with nudges.
	emit_eco_event("care", msg, 1, false)


# Maturation milestones (#71) + anniversary reflection (#80).
func _check_maturation_milestones() -> void:
	if _is_saltwater_tank():
		return
	var day: int = int(sim_day())
	var beats: Dictionary = {
		30: "Day 30: the biofilm has matured — the tank runs itself now.",
		60: "Day 60: the soil has mellowed; growth steadies into old-growth calm.",
		90: "Day 90: a settled, self-sustaining little world.",
	}
	for d in beats.keys():
		if day >= int(d) and not _milestone_flags.has(d):
			_milestone_flags[d] = true
			log_story_event(String(beats[d]))
	# Closing-loop message (#100): the quiet payoff. Once the tank is genuinely
	# established and serene, name the Walstad metaphor the whole thing is for —
	# a small complete world where waste becomes food, death becomes soil, and
	# light becomes growth, keeping itself alive.
	if not _milestone_flags.has("closing_loop") \
			and water_chemistry != null \
			and water_chemistry.cycle_phase >= WaterChemistry.CyclePhase.ESTABLISHED \
			and stability > 0.7 and total_plant_biomass > 120:
		_milestone_flags["closing_loop"] = true
		log_story_event("The loop has closed — waste becomes food, death becomes soil, light becomes growth. The tank keeps itself alive now.")
	# Anniversary reflection every 30 days past 90.
	if day >= 120 and day % 30 == 0:
		var key: String = "anniv_%d" % day
		if not _milestone_flags.has(key):
			_milestone_flags[key] = true
			tank_legacy["anniversaries"] = int(tank_legacy.get("anniversaries", 0)) + 1
			log_story_event(anniversary_line())


# A quiet "this tank has lived" reflection (#80).
func anniversary_line() -> String:
	var day: int = maxi(1, int(sim_day()))
	return "This tank has been alive %d days — peak of %d fish, %d shrimp; survived %d crash(es)." % [
		day, int(tank_legacy.get("peak_fish", 0)),
		int(tank_legacy.get("peak_shrimp", 0)),
		int(tank_legacy.get("crashes", 0))]


# Filter biofiltration + flow efficiency from media maturity − clogging (#77).
func equipment_efficiency() -> float:
	if aeration_fixture != "filter":
		return 1.0
	var mature: float = clampf(_filter_media_age_s / (WaterChemistry.SIM_DAY_S * 3.0), 0.0, 1.0)
	return clampf(0.85 + mature * 0.25 - _filter_clog, 0.6, 1.1)


# Player maintenance: rinse the filter (#77) — restores flow, costs a little
# bacteria (you rinse some biofilm away).
func rinse_filter() -> void:
	_filter_clog = 0.0
	if water_chemistry != null:
		water_chemistry.bacteria_colony = maxf(0.04, float(water_chemistry.bacteria_colony) - 0.08)
	log_story_event("Filter rinsed — flow restored.")


# Player maintenance: water change (#93/#8) — dilutes nitrate, refreshes
# minerals. Surfaced via the care-nudge path.
func do_water_change(fraction: float = 0.35) -> void:
	if water_chemistry != null and water_chemistry.has_method("apply_water_change"):
		water_chemistry.apply_water_change(fraction)
	log_story_event("Water change — nitrate diluted, minerals refreshed.")
var plant_growth_budget: int = 0
var _pearling_slots_used: int = 0
const PEARLING_MAX_SLOTS: int = 22
# Scaled by adaptive quality in main.gd (1.0 = full budget, 0 = off).
var pearling_budget_scale: float = 1.0
# All live snail nodes, rebuilt once per _tick from the "snails" group. Lets the
# same-tick overlap pass reuse the list instead of re-walking snails_root and
# string-comparing each child's script path.
var _live_snails: Array = []
# Cached autoloads / scene nodes — resolved lazily, reused thereafter. The
# per-tick "/root/TankConfig" lookup and per-event "AmbientAudio" tree walk were
# pure overhead since neither node ever moves.
var _cfg_cache: Node = null
var _ambient_audio_cache: Node = null
# Cached active 3D camera for off-frustum brain-skip. Refreshed lazily when
# null/invalid. The camera is parented under SubViewport/World so we walk
# down from the running scene to find it once and reuse the reference.
var _cam_cache: Camera3D = null
# Alternates 0/1 each sim tick; off-frustum fish only run their brain when
# (instance_id % 2) == this phase, halving brain cost for entities the
# player can't see. Position integration still runs every render frame so
# fish stay where they should when the camera swings back to them.
var _off_frustum_phase: int = 0

var _accum: float = 0.0
var _stats_timer: float = 0.0
var _extinction_timer: float = 0.0
var _auto_feed_timer: float = 0.0
# Natural food pulse (#50): occasional "something fell in" surface event that
# the whole web reacts to — keeps the tank pulsing instead of flat-lining at
# equilibrium.
var _food_pulse_timer: float = 150.0

# ---- Long arc & time (H8) ----
# Maturation milestones (#71), tank legacy (#75), stability curve (#76),
# equipment aging (#77), anniversary reflection (#80).
var _milestone_flags: Dictionary = {}
var tank_legacy: Dictionary = {
	"peak_fish": 0, "peak_shrimp": 0, "peak_biomass": 0,
	"crashes": 0, "anniversaries": 0,
}
var stability: float = 1.0
var _stability_sample_t: float = 0.0
var _long_arc_t: float = 0.0
# Filter media matures (better biofiltration) then slowly clogs until rinsed.
var _filter_media_age_s: float = 0.0
var _filter_clog: float = 0.0
var _crash_latch: bool = false
# Gentle care nudges (#91/#92): the tank asks for help softly, never nags.
var _nudge_timer: float = 90.0
var _last_nudge: String = ""
var _has_logged_sterile_dissolve: bool = false
var _eco_engineering_timer: float = 0.8
var _overlap_resolve_timer: float = 0.0
var _bounds_enforce_timer: float = 0.0
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

# ---- Residents: favorites (player-pinned individuals) ----
# Set of creature ids (id -> true) the player has starred. Persisted in
# state.json as a top-level "favorites" array. Ids are minted on demand the
# first time a creature is favorited (see toggle_favorite), so a starred fish
# keeps its star across save/load even though most ids are minted lazily.
var favorite_ids: Dictionary = {}
# The one "primary" favorite the HUD can quick-jump to. Defaults to the first
# starred creature; persisted alongside favorites.
var primary_favorite_id: String = ""


func mint_id() -> String:
	var s: String = "e_" + str(_next_entity_id)
	_next_entity_id += 1
	return s


func sim_day() -> float:
	return tank_age_s / WaterChemistry.SIM_DAY_S


func sim_day_label() -> String:
	return "Day %d" % maxi(1, int(sim_day()) + 1)


func hud_ecology_mode() -> String:
	if _is_saltwater_tank():
		return "reef"
	if water_chemistry == null:
		return "established"
	return WaterChemistry.hud_mode(water_chemistry.cycle_phase, sim_day(), false)


func _is_saltwater_tank() -> bool:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or not cfg.has_method("current_substrate_profile"):
		return false
	return not not cfg.current_substrate_profile().get("is_saltwater", false)


func emit_eco_event(kind: String, text: String, severity: int = 1,
		log_story: bool = true) -> void:
	eco_event.emit(kind, text, severity)
	if log_story:
		log_story_event(text, true)


func apply_cycle_start_from_config() -> void:
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg == null or water_chemistry == null:
		return
	var mode: String = String(cfg.get("cycle_start_mode") if cfg.get("cycle_start_mode") != null else "fresh")
	if _is_saltwater_tank():
		water_chemistry.apply_reef_start()
		tank_age_s = WaterChemistry.SIM_DAY_S * 21.0
		dissolved_o2 = 0.90
	elif mode == "established":
		water_chemistry.apply_established_start()
		tank_age_s = WaterChemistry.SIM_DAY_S * 14.0
		dissolved_o2 = 0.88
	else:
		water_chemistry.apply_fresh_start()
		tank_age_s = 0.0
		dissolved_o2 = 0.85


func _record_trophic_produced(amount: float) -> void:
	if amount <= 0.0:
		return
	trophic_ledger["produced"] = float(trophic_ledger.get("produced", 0.0)) + amount
	_trophic_hour_produced += amount


func _record_trophic_consumed(consumed_nv: float, leftover: float) -> void:
	trophic_ledger["consumed"] = float(trophic_ledger.get("consumed", 0.0)) + consumed_nv
	if leftover > 0.04:
		trophic_ledger["produced"] = float(trophic_ledger.get("produced", 0.0)) + leftover
		_trophic_hour_produced += leftover
	else:
		trophic_ledger["lost"] = float(trophic_ledger.get("lost", 0.0)) + consumed_nv
	var recycled: float = consumed_nv - maxf(leftover, 0.0)
	_trophic_hour_recycled += maxf(0.0, recycled * 0.4)


func _record_trophic_deposited(amount: float) -> void:
	if amount <= 0.0:
		return
	trophic_ledger["deposited"] = float(trophic_ledger.get("deposited", 0.0)) + amount
	_trophic_hour_recycled += amount


func _refresh_tank_vitals(bloom_pressure: float, n_total: float, plant_biomass: int) -> void:
	var recycle_denom: float = maxf(0.001, float(trophic_ledger.get("consumed", 0.0)))
	var recycle_pct: float = clampf(
		(float(trophic_ledger.get("deposited", 0.0)) + _trophic_hour_recycled) / recycle_denom,
		0.0, 1.0)
	tank_vitals = {
		"o2": dissolved_o2,
		"nh3": water_chemistry.ammonia if water_chemistry != null else 0.0,
		"no2": water_chemistry.nitrite if water_chemistry != null else 0.0,
		"no3": water_chemistry.nitrate if water_chemistry != null else 0.0,
		"n_total": n_total,
		"bloom_pressure": bloom_pressure,
		"bloom_intensity": bloom_intensity,
		"cycle_phase": water_chemistry.cycle_phase if water_chemistry != null else 0,
		"cycle_label": _cycle_label_for_hud(),
		"bacteria_colony": water_chemistry.bacteria_colony if water_chemistry != null else 0.0,
		"alkalinity_proxy": water_chemistry.alkalinity_proxy if water_chemistry != null else 8.0,
		"reef_nutrients": water_chemistry.reef_nutrients if water_chemistry != null else 0.0,
		"is_saltwater": _is_saltwater_tank(),
		"tank_age_s": tank_age_s,
		"sim_day": sim_day(),
		"sim_day_label": sim_day_label(),
		"hud_mode": hud_ecology_mode(),
		"carrying_capacity": fish_carrying_capacity(),
		"stocking_ratio": fish_stocking_ratio(),
		"trophic_recycle_pct": recycle_pct,
		"trophic_recycle_hour_pct": clampf(
			_trophic_hour_recycled / maxf(0.001, _trophic_hour_produced), 0.0, 1.0),
		"waste_particles": waste.size(),
		"plant_biomass": plant_biomass,
		"floater_coverage": _floater_coverage(),
		"reef_bleach_level": _max_reef_bleach(),
		"ph": water_chemistry.ph if water_chemistry != null else 7.2,
		"dissolved_co2": water_chemistry.dissolved_co2 if water_chemistry != null else 0.4,
		"kh": water_chemistry.kh if water_chemistry != null else 4.0,
		"gh": water_chemistry.gh if water_chemistry != null else 6.0,
		"iron": water_chemistry.iron if water_chemistry != null else 0.7,
		"toxic_nh3": water_chemistry.toxic_ammonia if water_chemistry != null else 0.0,
		"stability": stability,
		"filter_clog": _filter_clog,
	}


func _cycle_label_for_hud() -> String:
	if _is_saltwater_tank():
		return WaterChemistry.reef_phase_label()
	if water_chemistry == null:
		return ""
	return WaterChemistry.phase_label(water_chemistry.cycle_phase)


func _floater_coverage() -> float:
	var w: Node = get_parent()
	if w != null and w.has_method("floater_coverage"):
		return float(w.floater_coverage())
	return 0.0


func _floater_count() -> int:
	var w: Node = get_parent()
	if w != null and w.has_method("floater_count"):
		return int(w.floater_count())
	return 0


# Nitrate strip + Azolla N-fixation (#23, #24).
func _tick_floater_nutrients(dt: float) -> void:
	if water_chemistry == null:
		return
	var w: Node = get_parent()
	if w == null or not w.has_method("floater_count"):
		return
	var floaters: Array = w.get("_floaters") if w.get("_floaters") != null else []
	var consume: float = 0.0
	var fix: float = 0.0
	for f in floaters:
		if not is_instance_valid(f) or not (f is FloatingPlant):
			continue
		var fp: FloatingPlant = f
		if fp.turion_buried:
			continue
		# Floaters as algae insurance (#55): fast surface growth makes them
		# strong nitrate sponges, so a duckweed mat is the canonical emergency
		# fix for a nutrient-driven bloom (with the O2-choke + shade tradeoff
		# modeled elsewhere).
		var demand: float = fp.biomass() * 0.0032
		if fp.nitrogen_fixer > 0.1:
			fix += fp.nitrogen_fixer * demand * 0.35
		else:
			consume += demand
	water_chemistry.nitrate = maxf(0.0, water_chemistry.nitrate - consume * dt)
	water_chemistry.nitrate = clampf(water_chemistry.nitrate + fix * dt, 0.0, 3.0)


func _tank_warmth_sample() -> float:
	var w: Node = get_parent()
	if w != null and w.has_method("effective_warmth_at"):
		return float(w.effective_warmth_at(Vector3.ZERO))
	var cfg := get_node_or_null("/root/TankConfig")
	if cfg != null and cfg.get("light_warmth") != null:
		return float(cfg.light_warmth)
	return 0.55


func _max_reef_bleach() -> float:
	if not _is_saltwater_tank():
		return 0.0
	var peak: float = 0.0
	for p in plants:
		if not is_instance_valid(p):
			continue
		if p.has_method("is_reef_coral") and not p.is_reef_coral():
			continue
		if p.get("_bleach_level") != null:
			peak = maxf(peak, float(p._bleach_level))
	return peak


# Total real-world seconds this tank has been running with focus. Persisted
# in tanks/<slot>/meta.cfg and shown on the menu card. Ticked per real
# frame (NOT scaled by time_scale — this measures user attention).
var elapsed_runtime_s: float = 0.0
# Sim-time age (scaled by time_scale via tick dt). Drives cycle labels,
# HUD modes, and story diary day prefixes — distinct from elapsed_runtime_s
# which measures real wall-clock session time for the menu card.
var tank_age_s: float = 0.0

# Unified snapshot refreshed each sim tick — fauna, plants, algae, and HUD
# read the same values so chemistry and behaviour never disagree.
var tank_vitals: Dictionary = {}

# Rolling trophic accounting (nutrient units, not ppm).
var trophic_ledger: Dictionary = {
	"produced": 0.0,
	"consumed": 0.0,
	"deposited": 0.0,
	"lost": 0.0,
}
var _trophic_hour_timer: float = 0.0
var _trophic_hour_produced: float = 0.0
var _trophic_hour_recycled: float = 0.0

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
#
# v0.1.69 retune: the prior values left mature planted tanks at chronic
# low-O2 because the photosynthesis terms were too weak vs. respiration.
# Real Walstad tanks (no equipment, dense plants) sit comfortably at
# 80–95 % daytime O2 without any aeration; that's the target steady
# state with these constants.
const O2_INJECT_PER_RATE: float = 0.20    # disk at strength=1 -> 0.20/s peak input
const O2_FLOW_BONUS_PER_RATE: float = 0.08
const O2_PHOTO_PER_PLANT: float = 0.0014  # was 0.0008; biomass + count scalar
const O2_PHOTO_FLOATER: float = 0.0016    # was 0.0012; surface contact + photo, the Walstad MVP
const O2_PHOTO_BIOMASS_MULT: float = 0.0110  # dense Walstad biomass must carry daytime O₂
const O2_PHOTO_PLANTS_MULT: float = 0.68  # stem count matters for pearling / gas exchange
const O2_RESPIRE_FISH: float = 0.0030     # was 0.0040; gentler fish breathing
const O2_RESPIRE_SHRIMP: float = 0.0016   # was 0.0020
const O2_RESPIRE_SNAIL: float = 0.0009    # was 0.0011
const O2_PASSIVE_SURFACE_GAS: float = 0.022   # was 0.015; faster boundary exchange
const O2_TARGET_NATURAL: float = 0.65         # was 0.55; healthier ambient
# Night exchange boost + lower fauna respiration model "sleeping tank" behavior:
# plants stop photosynthesizing after dusk, but fish/shrimp also settle down and
# the water column tends to stay calmer/cooler. This prevents nightly O2 crashes
# that can trigger perpetual panic loops in otherwise healthy tanks.
const O2_NIGHT_SURFACE_BONUS: float = 0.014
const O2_FISH_NIGHT_RESP_SCALE: float = 0.65
const O2_SHRIMP_NIGHT_RESP_SCALE: float = 0.78
const O2_RESPIRE_PLANT: float = 0.0011
const O2_AERATION_FLOOR_BASE: float = 0.24  # air stone prevents total anoxia
const ECO_ENGINEERING_INTERVAL: float = 1.2
const ECO_MAX_FISH_SAMPLES: int = 10
const ECO_MAX_SHRIMP_SAMPLES: int = 14
const ECO_MAX_SNAIL_SAMPLES: int = 12
const OVERLAP_RESOLVE_INTERVAL: float = 0.45
const BOUNDS_ENFORCE_INTERVAL: float = 0.22
const NUTRIENT_STRIP_INTERVAL: float = 0.5
var _nutrient_strip_t: float = 0.0
var _waste_pool: Array[WasteParticle] = []
const WASTE_POOL_CAP: int = 64


func register_fish(f: Fish) -> void:
	fish.append(f)
	f.sim = self
	if f.has_method("_reclamp_territory_to_tank"):
		f._reclamp_territory_to_tank()
	_record_organism_discovery(f.get_saved_genome())
	_register_resident(f)


func register_shrimp(s: Shrimp) -> void:
	shrimp.append(s)
	s.sim = self
	_clamp_entity_to_bounds(s, 0.20, 0.04)
	_record_organism_discovery(s.get_saved_genome())
	_register_resident(s)


func register_snail(sn: Node) -> void:
	if sn == null or not is_instance_valid(sn):
		return
	if not sn.has_method("get_saved_genome"):
		return
	if sn is Node3D and sn.has_method("_reclamp_to_footprint"):
		sn.call("_reclamp_to_footprint")
	elif sn is Node3D:
		_clamp_entity_to_bounds(sn as Node3D, 0.28, 0.06, 0.10)
	_record_organism_discovery(sn.get_saved_genome())
	_register_resident(sn)


func register_clam(c: Node) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.sim = self
	clams.append(c)
	if c is Node3D:
		_clamp_entity_to_bounds(c as Node3D, 0.28, 0.04, 0.06)
	if c.has_method("get_saved_genome"):
		_record_organism_discovery(c.get_saved_genome())


# ---- Residents registry ----
# A "resident" is a followable, nameable individual: fish, shrimp, adult snail
# (snail.gd), or clam. Trumpet snails and other microfauna are environmental and
# excluded. living_creatures() is the canonical roster (UI populates from it on
# open); creature_added/removed cover live deltas during a session.
func _is_roster_creature(c: Node) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if c is Fish or c is Shrimp:
		return true
	var scr: Script = c.get_script()
	var p: String = scr.resource_path if scr != null else ""
	return p.ends_with("snail.gd") or p.ends_with("clam.gd")


# Snapshot of every living resident, deduped and validity-filtered.
func living_creatures() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for f in fish:
		if is_instance_valid(f):
			out.append(f)
			seen[f.get_instance_id()] = true
	for s in shrimp:
		if is_instance_valid(s):
			out.append(s)
			seen[s.get_instance_id()] = true
	for cl in clams:
		if is_instance_valid(cl) and (cl as Node).get("id") != null:
			out.append(cl)
			seen[(cl as Node).get_instance_id()] = true
	if snails_root != null and is_instance_valid(snails_root):
		for sn in snails_root.get_children():
			if not is_instance_valid(sn) or seen.has(sn.get_instance_id()):
				continue
			var scr: Script = sn.get_script()
			var p: String = scr.resource_path if scr != null else ""
			if p.ends_with("snail.gd"):
				out.append(sn)
	return out


# Hook a creature into the registry: wire its tree_exiting once and announce it.
# Called from register_* (live spawns/store/breeding).
func _register_resident(c: Node) -> void:
	if not _is_roster_creature(c):
		return
	_track_creature(c)
	creature_added.emit(c)


# Connect tree_exiting so creature_removed fires while the node is still valid.
# Idempotent via a meta flag. Used by both _register_resident and (for
# save-loaded creatures, which bypass register_*) track_all_living().
func _track_creature(c: Node) -> void:
	if c == null or not is_instance_valid(c):
		return
	if c.has_meta("_resident_tracked"):
		return
	c.set_meta("_resident_tracked", true)
	c.tree_exiting.connect(_on_creature_exiting.bind(c))


func _on_creature_exiting(c: Node) -> void:
	if c != null and is_instance_valid(c):
		creature_removed.emit(c)


# Ensure tree_exiting is wired for every currently-living creature. load_state
# spawns creatures without calling register_*, so call this after a load.
func track_all_living() -> void:
	for c in living_creatures():
		_track_creature(c)


# ---- Favorites ----
# Mint an id on demand and return it (favorites need a stable key). Returns ""
# if the node can't carry an id.
func ensure_id(c: Node) -> String:
	if c == null or not is_instance_valid(c) or c.get("id") == null:
		return ""
	if String(c.id) == "":
		c.id = mint_id()
	return String(c.id)


func is_favorite(c: Node) -> bool:
	if c == null or not is_instance_valid(c) or c.get("id") == null:
		return false
	var cid: String = String(c.id)
	return cid != "" and favorite_ids.has(cid)


# Toggle a creature's favorite flag. Returns the new state (true = favorited).
func toggle_favorite(c: Node) -> bool:
	var cid: String = ensure_id(c)
	if cid == "":
		return false
	if favorite_ids.has(cid):
		favorite_ids.erase(cid)
		if primary_favorite_id == cid:
			primary_favorite_id = ""
	else:
		favorite_ids[cid] = true
		if primary_favorite_id == "":
			primary_favorite_id = cid
		_note_ai_event("creature_favorited", "%s is now a favorite" % _creature_name_for(c))
	favorites_changed.emit()
	return favorite_ids.has(cid)


# Pin a creature as THE primary favorite (also stars it).
func set_primary_favorite(c: Node) -> void:
	var cid: String = ensure_id(c)
	if cid == "":
		return
	favorite_ids[cid] = true
	primary_favorite_id = cid
	favorites_changed.emit()


# The primary favorite if alive, else the first living favorite, else null.
func primary_favorite_creature() -> Node:
	var favs: Array = favorite_creatures()
	if primary_favorite_id != "":
		for c in favs:
			if (c as Node).get("id") != null and String(c.id) == primary_favorite_id:
				return c
	return favs[0] if not favs.is_empty() else null


func _creature_name_for(c: Node) -> String:
	if c == null or not is_instance_valid(c):
		return "A creature"
	for k in ["fish_name", "shrimp_name", "snail_name", "clam_name"]:
		if c.get(k) != null and String(c.get(k)) != "":
			return String(c.get(k))
	return "A creature"


# Feed a notable moment to the AI chronicle (no-op when AI/chronicle is off).
func _note_ai_event(kind: String, summary: String) -> void:
	var ai := get_node_or_null("/root/AIDirector")
	if ai != null and ai.has_method("note_event") \
			and bool(ai.get("enabled")) and bool(ai.get("chronicle_enabled")):
		ai.note_event(kind, summary)


# Living creatures the player has starred (for cycling scope + in-tank halos).
func favorite_creatures() -> Array:
	var out: Array = []
	if favorite_ids.is_empty():
		return out
	for c in living_creatures():
		if (c as Node).get("id") != null and favorite_ids.has(String(c.id)):
			out.append(c)
	return out


# Drop favorite ids that no longer resolve to a living creature (e.g. a starred
# fish that died). Called at save time so the persisted set stays bounded.
func _prune_dead_favorites() -> void:
	if favorite_ids.is_empty():
		return
	var live_ids: Dictionary = {}
	for c in living_creatures():
		if (c as Node).get("id") != null and String(c.id) != "":
			live_ids[String(c.id)] = true
	for fid in favorite_ids.keys():
		if not live_ids.has(fid):
			favorite_ids.erase(fid)
	if primary_favorite_id != "" and not live_ids.has(primary_favorite_id):
		primary_favorite_id = ""


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
	if pearl_factor < 0.10 or pearling_budget_scale <= 0.0:
		return 0.0
	var slot_cap: int = maxi(1, int(round(float(PEARLING_MAX_SLOTS) * pearling_budget_scale)))
	if _pearling_slots_used >= slot_cap:
		return 0.0
	_pearling_slots_used += 1
	var fill: float = float(_pearling_slots_used) / float(slot_cap)
	return clampf(1.05 - fill * 0.75, 0.22, 1.0) * clampf(pearl_factor * 1.15, 0.0, 1.0)


func register_waste(w: WasteParticle) -> void:
	waste.append(w)


func register_egg(e: FishEgg) -> void:
	eggs.append(e)


func _physics_process(dt: float) -> void:
	# Fish positions for snail predator scans — 10 Hz is enough for 0.3 s scan cadence.
	_fish_grid_t += dt
	if _fish_grid_t >= FISH_GRID_REBUILD_S:
		_fish_grid_t = 0.0
		_rebuild_fish_query_grid()
	# Real-time runtime accumulator (unscaled — measures how long the user
	# has had this tank open with focus). Used by the menu's "ran for X" line.
	elapsed_runtime_s += dt
	# Home-screen widget data export. Cheap: write a small JSON file every
	# WIDGET_EXPORT_INTERVAL_S so an Android AppWidget can read the current
	# tank state without IPC-ing into the running game. No-op on desktop.
	_widget_export_timer += dt
	if _widget_export_timer >= WIDGET_EXPORT_INTERVAL_S:
		_widget_export_timer = 0.0
		_export_widget_state()
	# Scale incoming delta by time_scale so pause/fast-forward work uniformly.
	var sdt: float = dt * time_scale
	_accum += sdt
	# Clamp the accumulator to prevent a "spiral of death" on slow frames: at
	# time_scale=16 a single 100ms hitch enqueues 1.6s = 16 ticks; if any of
	# those ticks then runs slower than its share of real time, _accum grows
	# faster than it drains and the game-loop locks. Cap at 4 ticks (0.4s of
	# sim work) so we drop sim-time on a hitch instead of freezing the render.
	_accum = minf(_accum, SIM_DT * 4.0)
	# Day phase only advances if the user hasn't frozen the cycle in the
	# Light panel. The rest of the sim keeps ticking either way. Cycle
	# length is also slider-driven (TankConfig.day_length_s); the constant
	# DAY_LENGTH_S is now just a fallback when no cfg is mounted (tests).
	var cfg_tc := get_node_or_null("/root/TankConfig")
	if cfg_tc == null or bool(cfg_tc.day_cycle_enabled):
		var cycle_len: float = DAY_LENGTH_S
		if cfg_tc != null:
			cycle_len = maxf(15.0, float(cfg_tc.day_length_s))
		day_phase = fposmod(day_phase + sdt / cycle_len, 1.0)
	while _accum >= SIM_DT:
		_accum -= SIM_DT
		_tick(SIM_DT)
	_stats_timer += sdt
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		_emit_stats()
		_push_swim_activity()


# Day/night light multiplier 0..1. Cosine over the cycle so it's a smooth
# bell. day_phase 0.25 = peak (midday), 0.75 = trough (midnight).
func daylight() -> float:
	var raw: float = 0.5 + 0.5 * cos((day_phase - 0.25) * TAU)
	# Smooth dawn/dusk ramp (photoperiod crossfade ~30 sim-seconds at 1×).
	return raw * raw * (3.0 - 2.0 * raw)


# Cached TankConfig autoload accessor. The autoload never moves, so the per-tick
# "/root/TankConfig" path lookups this replaces were pure overhead.
func _cfg() -> Node:
	if _cfg_cache == null or not is_instance_valid(_cfg_cache):
		_cfg_cache = get_node_or_null("/root/TankConfig")
	return _cfg_cache


# Cached Camera3D accessor. Used to off-frustum-skip the brain tick of
# fish/shrimp the player can't see — the brain AI is the most expensive
# per-entity cost in the sim, and the position integration already runs
# at render rate from the last brain output, so off-screen entities stay
# coherent even if their brain runs at 5 Hz instead of 10.
func _get_camera() -> Camera3D:
	if _cam_cache != null and is_instance_valid(_cam_cache):
		return _cam_cache
	var scene := get_tree().current_scene
	if scene == null:
		return null
	# The camera lives under SubViewport/World/Camera3D in main.tscn but
	# scene structure may evolve — find_child handles both flat and nested
	# layouts. recursive=true so we find it wherever it ended up.
	var found := scene.find_child("Camera3D", true, false)
	if found is Camera3D:
		_cam_cache = found as Camera3D
	return _cam_cache


func is_creature_visible_to_camera(node: Node3D) -> bool:
	var cam := _get_camera()
	if cam == null or node == null:
		return true
	return cam.is_position_in_frustum(node.global_position)


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

# Plant spatial grid — sessile so we only need to rebuild every few
# sim-seconds instead of every tick. Each fish brain does up to 5
# plant-radius scans (shelter, cover, food target, dim-light rest,
# herbivore target), so with 750 plants and 30 fish the old O(plants ×
# fish) per-tick scan was ~225k distance checks/sec; this drops it to
# the cells the fish actually overlaps.
const PLANT_GRID_CELL_SIZE: float = 2.0
const PLANT_GRID_REBUILD_S: float = 0.5
var _plants_grid: Dictionary = {}  # Vector2i → Array[Plant]
var _plants_grid_t: float = 0.0


func _rebuild_plants_grid() -> void:
	_plants_grid.clear()
	for p in plants:
		if not is_instance_valid(p):
			continue
		var cell := Vector2i(
			int(floor(p._world_pos.x / PLANT_GRID_CELL_SIZE)),
			int(floor(p._world_pos.z / PLANT_GRID_CELL_SIZE)))
		if _plants_grid.has(cell):
			_plants_grid[cell].append(p)
		else:
			_plants_grid[cell] = [p]


# Return all plants within max_dist of pos. Caller does the final
# distance check + biomass/state filters; this just narrows the search.
func query_plants_in_radius(pos: Vector3, max_dist: float) -> Array:
	var result: Array = []
	if _plants_grid.is_empty():
		# Cold start: bootstrap once so callers don't see a stall.
		_rebuild_plants_grid()
	var cx: int = int(floor(pos.x / PLANT_GRID_CELL_SIZE))
	var cz: int = int(floor(pos.z / PLANT_GRID_CELL_SIZE))
	var reach: int = maxi(1, int(ceil(max_dist / PLANT_GRID_CELL_SIZE)))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := Vector2i(cx + dx, cz + dz)
			var bucket: Array = _plants_grid.get(cell, [])
			for p in bucket:
				result.append(p)
	return result


const WASTE_GRID_CELL_SIZE: float = 1.5
var _waste_grid: Dictionary = {}  # Vector2i → Array[WasteParticle]


func _rebuild_waste_grid() -> void:
	_waste_grid.clear()
	for w in waste:
		if not is_instance_valid(w):
			continue
		var wp: Vector3 = (w as Node3D).global_position
		var cell := Vector2i(
			int(floor(wp.x / WASTE_GRID_CELL_SIZE)),
			int(floor(wp.z / WASTE_GRID_CELL_SIZE)))
		if _waste_grid.has(cell):
			_waste_grid[cell].append(w)
		else:
			_waste_grid[cell] = [w]


func query_waste_in_radius(pos: Vector3, max_dist: float) -> Array:
	var result: Array = []
	if _waste_grid.is_empty() and not waste.is_empty():
		_rebuild_waste_grid()
	var cx: int = int(floor(pos.x / WASTE_GRID_CELL_SIZE))
	var cz: int = int(floor(pos.z / WASTE_GRID_CELL_SIZE))
	var reach: int = maxi(1, int(ceil(max_dist / WASTE_GRID_CELL_SIZE)))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := Vector2i(cx + dx, cz + dz)
			var bucket: Array = _waste_grid.get(cell, [])
			for w in bucket:
				result.append(w)
	return result


const ALGAE_GRID_CELL_SIZE: float = 1.5
var _algae_grid: Dictionary = {}


func _rebuild_algae_grid() -> void:
	_algae_grid.clear()
	for a in algae:
		if not is_instance_valid(a):
			continue
		var ap: Vector3 = (a as Node3D).global_position
		var cell := Vector2i(
			int(floor(ap.x / ALGAE_GRID_CELL_SIZE)),
			int(floor(ap.z / ALGAE_GRID_CELL_SIZE)))
		if _algae_grid.has(cell):
			_algae_grid[cell].append(a)
		else:
			_algae_grid[cell] = [a]


func query_algae_in_radius(pos: Vector3, max_dist: float) -> Array:
	var result: Array = []
	if _algae_grid.is_empty() and not algae.is_empty():
		_rebuild_algae_grid()
	var cx: int = int(floor(pos.x / ALGAE_GRID_CELL_SIZE))
	var cz: int = int(floor(pos.z / ALGAE_GRID_CELL_SIZE))
	var reach: int = maxi(1, int(ceil(max_dist / ALGAE_GRID_CELL_SIZE)))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := Vector2i(cx + dx, cz + dz)
			var bucket: Array = _algae_grid.get(cell, [])
			for a in bucket:
				result.append(a)
	return result


# Persistent fish grid for render-rate queries (snail predator scans).
var _fish_query_grid: Dictionary = {}
var _fish_grid_t: float = 0.0
const FISH_GRID_REBUILD_S: float = 0.1


func _rebuild_fish_query_grid() -> void:
	_fish_query_grid.clear()
	for f in fish:
		if not is_instance_valid(f) or f.get("_dying") == true:
			continue
		var fp: Vector3 = f.global_position
		var cell := Vector2i(
			int(floor(fp.x / SPATIAL_CELL_SIZE)),
			int(floor(fp.z / SPATIAL_CELL_SIZE)))
		if _fish_query_grid.has(cell):
			_fish_query_grid[cell].append(f)
		else:
			_fish_query_grid[cell] = [f]


func query_fish_in_radius(pos: Vector3, radius_sq: float) -> Array:
	var result: Array = []
	if _fish_query_grid.is_empty() and not fish.is_empty():
		_rebuild_fish_query_grid()
	var cx: int = int(floor(pos.x / SPATIAL_CELL_SIZE))
	var cz: int = int(floor(pos.z / SPATIAL_CELL_SIZE))
	var reach: int = maxi(1, int(ceil(sqrt(radius_sq) / SPATIAL_CELL_SIZE)))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var cell := Vector2i(cx + dx, cz + dz)
			var bucket: Array = _fish_query_grid.get(cell, [])
			for f in bucket:
				if f.global_position.distance_squared_to(pos) < radius_sq:
					result.append(f)
	return result


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
		_substrate_margin: float = 0.06, body_radius: float = 0.0) -> void:
	if e == null or not is_instance_valid(e):
		return
	var w: Node = get_parent()
	if w != null and w.has_method("enforce_entity_in_tank"):
		w.enforce_entity_in_tank(e, margin, body_radius)
		return
	if w != null and w.has_method("clamp_xyz_in_tank"):
		e.global_position = w.clamp_xyz_in_tank(e.global_position, margin, body_radius)


# Keep body position AND territory anchors inside the tank. Clamping position
# alone is not enough — saved home_x/home_z from a box tank still pull fish
# toward coordinates outside a cylinder wall every tick.
func _clamp_fish_territory(f: Fish) -> void:
	if f == null or not is_instance_valid(f):
		return
	if f.has_method("_reclamp_territory_to_tank"):
		f._reclamp_territory_to_tank()
	else:
		_clamp_entity_to_bounds(f, 0.28, 0.06)


func _resolve_entity_group_overlaps(group: Array, min_dist: float,
		group_limit: int = 120, y_weight: float = 0.55) -> void:
	var local_grid: Dictionary = {}
	var n: int = mini(group.size(), group_limit)
	for i in n:
		var e: Node3D = group[i] as Node3D
		if e == null or not is_instance_valid(e):
			continue
		var cell := Vector2i(
			int(floor(e.position.x / SPATIAL_CELL_SIZE)),
			int(floor(e.position.z / SPATIAL_CELL_SIZE)))
		if local_grid.has(cell):
			(local_grid[cell] as Array).append(i)
		else:
			local_grid[cell] = [i]
	var reach: int = maxi(1, int(ceil(min_dist / SPATIAL_CELL_SIZE)))
	for i in n:
		var a: Node3D = group[i] as Node3D
		if a == null or not is_instance_valid(a):
			continue
		var cx: int = int(floor(a.position.x / SPATIAL_CELL_SIZE))
		var cz: int = int(floor(a.position.z / SPATIAL_CELL_SIZE))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var bucket: Array = local_grid.get(Vector2i(cx + dx, cz + dz), [])
				for j in bucket:
					if int(j) <= i:
						continue
					var b: Node3D = group[int(j)] as Node3D
					if b == null or not is_instance_valid(b):
						continue
					_push_apart_pair(a, b, min_dist, 0.5, y_weight)


func _resolve_cross_overlaps(primary: Array, other: Array, min_dist: float,
		primary_limit: int = 140, other_limit: int = 140, y_weight: float = 0.38) -> void:
	var other_grid: Dictionary = {}
	var n2: int = mini(other.size(), other_limit)
	for j in n2:
		var ob: Node3D = other[j] as Node3D
		if ob == null or not is_instance_valid(ob):
			continue
		var cell := Vector2i(
			int(floor(ob.position.x / SPATIAL_CELL_SIZE)),
			int(floor(ob.position.z / SPATIAL_CELL_SIZE)))
		if other_grid.has(cell):
			(other_grid[cell] as Array).append(j)
		else:
			other_grid[cell] = [j]
	var n1: int = mini(primary.size(), primary_limit)
	var reach: int = maxi(1, int(ceil(min_dist / SPATIAL_CELL_SIZE)))
	for i in n1:
		var a: Node3D = primary[i] as Node3D
		if a == null or not is_instance_valid(a):
			continue
		var cx: int = int(floor(a.position.x / SPATIAL_CELL_SIZE))
		var cz: int = int(floor(a.position.z / SPATIAL_CELL_SIZE))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var bucket: Array = other_grid.get(Vector2i(cx + dx, cz + dz), [])
				for j in bucket:
					var b: Node3D = other[int(j)] as Node3D
					if b == null or not is_instance_valid(b):
						continue
					_push_apart_pair(a, b, min_dist, 0.34, y_weight)


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
				var jitter_seed := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
				if jitter_seed.length_squared() < 1e-6:
					jitter_seed = Vector3(1.0, 0.0, 0.0)
				dir = jitter_seed.normalized()
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

	_resolve_entity_group_overlaps(live_fish, 0.30, 90, 0.28)
	_resolve_entity_group_overlaps(live_shrimp, 0.16, 120, 0.42)
	_resolve_entity_group_overlaps(live_snails, 0.20, 80, 0.22)
	_resolve_cross_overlaps(live_fish, live_shrimp, 0.19, 90, 120, 0.30)
	_resolve_cross_overlaps(live_shrimp, live_snails, 0.16, 120, 80, 0.35)

	_resolve_hardscape_overlaps(live_fish, 0.30, 60, 120)
	_resolve_hardscape_overlaps(live_shrimp, 0.20, 80, 120)
	_resolve_hardscape_overlaps(live_snails, 0.18, 50, 120)
	# One clamp pass after all separation — pushing pairs apart can eject
	# fish past curved walls, but clamping inside every pair interaction
	# caused rim-clustering and fought saved home territories.
	for e in live_fish:
		_clamp_fish_territory(e)
	for e in live_shrimp:
		_clamp_entity_to_bounds(e, 0.18, 0.04)
	for e in live_snails:
		if is_instance_valid(e) and e.has_method("_reclamp_to_footprint"):
			e.call("_reclamp_to_footprint")
		else:
			_clamp_entity_to_bounds(e, 0.28, 0.06, 0.10)


func _enforce_all_fauna_in_tank() -> void:
	for f in fish:
		if is_instance_valid(f) and f.get("_dying") != true:
			_clamp_fish_territory(f)
	for s in shrimp:
		if is_instance_valid(s) and s.get("_dying") != true:
			_clamp_entity_to_bounds(s, 0.20, 0.04, 0.14)
	ensure_snails_root()
	if snails_root != null:
		for sn in snails_root.get_children():
			if is_instance_valid(sn) and sn is Node3D:
				if sn.has_method("_reclamp_to_footprint"):
					sn.call("_reclamp_to_footprint")
				else:
					_clamp_entity_to_bounds(sn as Node3D, 0.28, 0.06, 0.10)
	for e in eggs:
		if is_instance_valid(e):
			_clamp_entity_to_bounds(e, 0.20, 0.04)
	for w_part in waste:
		if is_instance_valid(w_part):
			_clamp_entity_to_bounds(w_part, 0.16, 0.03)

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
		if not n.global_position.is_finite() or not n.transform.is_finite():
			n.queue_free()
			arr.remove_at(i)


func _prune_non_finite_snails() -> void:
	ensure_snails_root()
	if snails_root == null or not is_instance_valid(snails_root):
		return
	for i in range(snails_root.get_child_count() - 1, -1, -1):
		var child: Node = snails_root.get_child(i)
		if not is_instance_valid(child):
			continue
		var n: Node3D = child as Node3D
		if n == null:
			child.queue_free()
			continue
		if not n.global_position.is_finite() or not n.transform.is_finite():
			n.queue_free()


func _tick(dt: float) -> void:
	tank_age_s += dt
	_tick_carrying_capacity(dt)
	_tick_long_arc(dt)
	_tick_care_nudge(dt)
	_trophic_hour_timer += dt
	if _trophic_hour_timer >= 3600.0:
		_trophic_hour_timer = 0.0
		_trophic_hour_produced = 0.0
		_trophic_hour_recycled = 0.0
	ensure_snails_root()
	# Tank-wide schooling pulse. Phase advance is constant; fish.gd reads
	# school_pulse() each tick to modulate cohesion strength.
	_school_pulse_phase += dt * TAU / SCHOOL_PULSE_PERIOD
	if _school_pulse_phase > TAU * 1000.0:
		_school_pulse_phase = fmod(_school_pulse_phase, TAU)
	# 1. Prune invalid refs (queue_freed nodes) — in-place, no allocation.
	_prune_invalid(fish)
	_prune_invalid(shrimp)
	_prune_invalid(plants)
	_prune_invalid(waste)
	_prune_invalid(eggs)
	_prune_non_finite_positions(fish)
	_prune_non_finite_positions(shrimp)
	_prune_non_finite_snails()
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
	var inject: float = (aeration_air_rate * O2_INJECT_PER_RATE \
		+ aeration_flow_rate * O2_FLOW_BONUS_PER_RATE) * equipment_efficiency()
	# Smart-air solenoid (#30): an optional O2 controller kicks the air pump on
	# when dissolved O2 dips, for players who want a self-stabilizing tank. Off
	# by default so the dawn-trough tension stays intact.
	var cfg_air: Node = _cfg()
	if cfg_air != null and bool(cfg_air.get("smart_air_enabled")) and dissolved_o2 < 0.5:
		inject += (0.5 - dissolved_o2) * 0.45
	# Surface floating plants photosynthesise too (read live count from World).
	var floater_n: int = 0
	var w_o2: Node = get_parent()
	if w_o2 != null and w_o2.has_method("floater_count"):
		floater_n = w_o2.floater_count()
	var dl: float = daylight()
	var night: float = 1.0 - dl
	# Sick-plant O2 dropout (#29): only healthy biomass photosynthesises, so a
	# melting / etiolating planting stops carrying the tank's oxygen.
	var photo_biomass: float = total_photosynthetic_biomass
	if photo_biomass <= 0.0:
		photo_biomass = float(total_plant_biomass)
	var photo: float = dl * (
		photo_biomass * O2_PHOTO_PER_PLANT * O2_PHOTO_BIOMASS_MULT
		+ float(plants.size()) * O2_PHOTO_PER_PLANT * O2_PHOTO_PLANTS_MULT
		+ float(floater_n) * O2_PHOTO_FLOATER)
	var fish_resp_scale: float = lerpf(O2_FISH_NIGHT_RESP_SCALE, 1.0, dl)
	var shrimp_resp_scale: float = lerpf(O2_SHRIMP_NIGHT_RESP_SCALE, 1.0, dl)
	# ~half of plant nighttime demand is buffered in the soil (Walstad closed
	# loop) and does not draw down the water-column O₂ budget.
	var plant_night_resp: float = float(total_plant_biomass) * O2_RESPIRE_PLANT \
		* night * 0.52
	var respire: float = float(fish.size()) * O2_RESPIRE_FISH * fish_resp_scale \
		+ float(shrimp.size()) * O2_RESPIRE_SHRIMP * shrimp_resp_scale \
		+ float(snail_count) * O2_RESPIRE_SNAIL \
		+ plant_night_resp
	# Pre-dawn O2 trough (#21): plant + bacterial respiration has been drawing
	# down O2 all night; the minimum lands just before dawn. day_phase ~0.6→1.0
	# is the deep-dark→dawn window.
	var predawn: float = 0.0
	if day_phase > 0.6 and day_phase < 1.0:
		predawn = clampf((day_phase - 0.6) / 0.4, 0.0, 1.0)
	respire += photo_biomass * O2_RESPIRE_PLANT * predawn * 0.32
	# Bloom-crash overnight sag (#26): an algae bloom oxygenates by day but its
	# decomposition spikes biological oxygen demand at night — the classic
	# "green water killed my fish overnight."
	respire += clampf(bloom_intensity, 0.0, 1.0) * 0.004 * night
	# Warm water holds less O2 (#27): reef / warm tanks run a tighter margin.
	var warmth_o2: float = 0.55
	if w_o2 != null and w_o2.has_method("effective_warmth_at"):
		warmth_o2 = float(w_o2.effective_warmth_at(Vector3.ZERO))
	var warm_penalty: float = clampf((warmth_o2 - 0.55) / 0.45, 0.0, 1.0) * 0.12
	# Drift toward the natural target if there's no equipment.
	var drift_target: float = (O2_TARGET_NATURAL - warm_penalty) + night * 0.10
	var drift_rate: float = O2_PASSIVE_SURFACE_GAS + night * O2_NIGHT_SURFACE_BONUS
	# Filtered tanks agitate the surface, topping up O2 overnight (#25): the
	# dawn dip is gentler than an unfiltered or air-only tank.
	if aeration_fixture == "filter":
		drift_rate += night * 0.022
	# Planted freshwater tanks exchange gas at the surface even when lights
	# are off — emergent growth + filter return keep the dawn dip survivable.
	if not _is_saltwater_tank() and total_plant_biomass > 120:
		var planted: float = clampf(float(total_plant_biomass) / 420.0, 0.0, 1.0)
		drift_target += planted * 0.08
		drift_rate += night * planted * 0.010
	# Coverage O₂ choke (#17): dense mats reduce surface gas exchange.
	if w_o2 != null and w_o2.has_method("floater_coverage"):
		var fc: float = float(w_o2.floater_coverage())
		if fc > 0.75:
			drift_rate *= 1.0 - clampf((fc - 0.75) / 0.25, 0.0, 1.0) * 0.55
	# Surface-film gas choke (#10): an oily surface-scum algae layer physically
	# slows O2 exchange at the air-water interface — neglect literally
	# suffocates the column.
	var surf_scum: int = 0
	for a_scum in algae:
		if is_instance_valid(a_scum) and a_scum.has_method("algae_kind") \
				and a_scum.algae_kind() == Algae.AlgaeKind.SURFACE:
			surf_scum += 1
	if surf_scum > 0:
		drift_rate *= 1.0 - clampf(float(surf_scum) / 9.0, 0.0, 0.30)
	var drift: float = drift_rate * (drift_target - dissolved_o2)
	var o2_floor: float = 0.0
	if inject > 0.02 or aeration_flow_rate > 0.08:
		o2_floor = O2_AERATION_FLOOR_BASE + aeration_air_rate * 0.12 + aeration_flow_rate * 0.08
	# Planted tanks bleed a little O₂ at the surface even when the pump is off.
	if not _is_saltwater_tank() and total_plant_biomass > 80:
		o2_floor = maxf(o2_floor, 0.12 + clampf(float(total_plant_biomass) / 600.0, 0.0, 0.12))
	dissolved_o2 = clampf(dissolved_o2 + (inject + photo + drift - respire) * dt,
		o2_floor, 1.2)

	# 2. Substrate field + periodic 3D terrain nutrient sync.
	if substrate != null:
		substrate.tick(dt)
	_tick_floater_nutrients(dt)
	_terrain_sync_timer += dt
	if _terrain_sync_timer >= TERRAIN_SYNC_INTERVAL_S:
		_terrain_sync_timer = 0.0
		var w_sync: Node = get_parent()
		if w_sync != null and w_sync.has_method("sync_terrain_nutrients"):
			w_sync.sync_terrain_nutrients()

	# 3. Plants — cap GPU-heavy growth steps per tick (Metal fence safety).
	# Walstad balance: more growth budget when cycled + planted; less during spikes.
	var cycle_bonus: float = 1.0
	if water_chemistry.cycle_phase >= WaterChemistry.CyclePhase.CYCLING:
		cycle_bonus = 1.12
	if water_chemistry.cycle_phase >= WaterChemistry.CyclePhase.ESTABLISHED:
		cycle_bonus = 1.28
	cycle_bonus *= 1.0 - clampf(bloom_intensity, 0.0, 1.0) * 0.18
	var biomass_bonus: int = int(float(total_plant_biomass) / 55.0)
	plant_growth_budget = clampi(
		int((28 + int(plants.size() / 12.0) + biomass_bonus) * cycle_bonus),
		24, 110)
	_pearling_slots_used = 0
	var plant_biomass: int = 0
	var photo_bm: float = 0.0
	for p in plants:
		if not is_instance_valid(p):
			continue
		p.tick(dt, substrate)
		var bm: int = p.biomass()
		plant_biomass += bm
		var h_v: Variant = p.get("_health_smooth")
		var hf: float = clampf(float(h_v), 0.0, 1.0) if h_v != null else 1.0
		photo_bm += float(bm) * hf
	total_plant_biomass = plant_biomass
	total_photosynthetic_biomass = photo_bm
	# Plant fragments (stem cuttings rooting).
	var frag_i: int = plant_fragments.size() - 1
	while frag_i >= 0:
		var frag: Variant = plant_fragments[frag_i]
		if not is_instance_valid(frag):
			plant_fragments.remove_at(frag_i)
		else:
			frag.tick(dt, self, get_parent())
			if not is_instance_valid(frag):
				plant_fragments.remove_at(frag_i)
		frag_i -= 1

	# Nutrient competition (#36): plants strip excess substrate nutrients.
	# Throttled to 2 Hz — full-rate halo was ~10k substrate ops/sec in mature
	# planted tanks with negligible visual difference at 10 Hz sim.
	_nutrient_strip_t += dt
	if substrate != null and plant_biomass > 40 and _nutrient_strip_t >= NUTRIENT_STRIP_INTERVAL:
		_nutrient_strip_t = 0.0
		var strip: float = clampf(float(plant_biomass) / 600.0, 0.0, 0.006) \
			* NUTRIENT_STRIP_INTERVAL
		for p in plants:
			if not is_instance_valid(p) or strip <= 0.0:
				continue
			var pp: Vector3 = p.global_position
			substrate.consume_at(pp, strip * p.nutrient_demand * 0.4)
			# Halo: bigger/older plants reach further for nutrients.
			var reach: float = clampf(float(p.biomass()) / 30.0, 0.0, 1.0)
			if reach > 0.25 and not p.get("is_epiphyte"):
				var halo: float = strip * p.nutrient_demand * 0.18 * reach
				substrate.consume_at(pp + Vector3(0.9, 0.0, 0.0), halo)
				substrate.consume_at(pp + Vector3(-0.9, 0.0, 0.0), halo)
				substrate.consume_at(pp + Vector3(0.0, 0.0, 0.9), halo)
				substrate.consume_at(pp + Vector3(0.0, 0.0, -0.9), halo)

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

	# Plant spatial grid — refreshed on a slow cadence since plants are
	# sessile. Fish brains query it via query_plants_in_radius below.
	_plants_grid_t -= dt
	if _plants_grid_t <= 0.0:
		_plants_grid_t = PLANT_GRID_REBUILD_S
		_rebuild_plants_grid()

	# Age feed-tap memories. Entries older than FEED_MEMORY_TTL are
	# pruned so the bias fades naturally between feedings.
	if not _feed_memory.is_empty():
		var keep: Array = []
		for entry in _feed_memory:
			var e: Dictionary = entry
			e["t"] = float(e.get("t", 0.0)) + dt
			if float(e["t"]) < FEED_MEMORY_TTL:
				keep.append(e)
		_feed_memory = keep

	_rebuild_waste_grid()
	_rebuild_algae_grid()

	# Build spatial hash grid from all live (non-dying) fish. One O(N)
	# insert pass replaces the old O(N²) nested neighbor loop.
	_spatial_rebuild(fish)

	# Off-frustum brain throttle. Flip the phase each tick so off-screen
	# fish whose (instance_id % 2) matches run their brain; the other half
	# skip. Net effect: brain ticks at 5 Hz for entities the player can't
	# see, 10 Hz for what they're looking at. Position integration runs at
	# render rate from each fish's current velocity regardless, so off-
	# screen fish keep drifting and remain coherent when the camera pans
	# back to them.
	#
	# IMPORTANT exception: entities near a tank wall always get their full
	# 10 Hz brain so the wall-avoidance reactions don't lag. Throttling on
	# wall approach was causing fish to visibly embed in surfaces before
	# the brain re-issued a heading-away command. world_bounds carries the
	# tank AABB; a fish within 0.6 m of any edge keeps full brain rate.
	_off_frustum_phase = 1 - _off_frustum_phase
	var cam: Camera3D = _get_camera()
	var have_cam: bool = cam != null
	var bounds_min: Vector3 = world_bounds.position
	var bounds_max: Vector3 = world_bounds.position + world_bounds.size
	const WALL_MARGIN: float = 0.6

	for f in fish:
		if not is_instance_valid(f):
			continue
		# Dying fish are inert: skip the tick entirely so the death pose
		# isn't fought by the brain, and skip them from any other fish's
		# neighbor list so schoolers don't cluster around the sinking
		# corpse and predators don't try to eat it mid-death.
		if f.get("_dying") == true:
			continue
		# Off-frustum brain skip. is_position_in_frustum is cheap (4 plane
		# tests). We only skip half the off-screen fish per tick, but we
		# never skip fish near a tank wall — keeping the brain at 10 Hz
		# there avoids wall-stuck artifacts when reflection commands lag.
		if have_cam and not cam.is_position_in_frustum(f.position):
			var near_wall: bool = \
				f.position.x < bounds_min.x + WALL_MARGIN \
				or f.position.x > bounds_max.x - WALL_MARGIN \
				or f.position.y < bounds_min.y + WALL_MARGIN \
				or f.position.y > bounds_max.y - WALL_MARGIN \
				or f.position.z < bounds_min.z + WALL_MARGIN \
				or f.position.z > bounds_max.z - WALL_MARGIN
			if not near_wall and (f.get_instance_id() & 1) != _off_frustum_phase:
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
		# Same off-frustum throttle as fish — shrimp brains do a lot of
		# pheromone-trail and plant-scan work that's wasted when the player
		# can't see them. Same wall-proximity guard so shrimp don't get
		# embedded against a corner with their brain stuck on the wrong
		# pheromone gradient.
		if have_cam and not cam.is_position_in_frustum(s.position):
			var s_near_wall: bool = \
				s.position.x < bounds_min.x + WALL_MARGIN \
				or s.position.x > bounds_max.x - WALL_MARGIN \
				or s.position.y < bounds_min.y + WALL_MARGIN \
				or s.position.y > bounds_max.y - WALL_MARGIN \
				or s.position.z < bounds_min.z + WALL_MARGIN \
				or s.position.z > bounds_max.z - WALL_MARGIN
			if not s_near_wall and (s.get_instance_id() & 1) != _off_frustum_phase:
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

	# 4d. Periodic footprint enforcement — catches stragglers that drifted
	# outside curved walls via saved homes, overlap pushes, or AABB fallbacks.
	_bounds_enforce_timer = maxf(0.0, _bounds_enforce_timer - dt)
	if _bounds_enforce_timer <= 0.0:
		_bounds_enforce_timer = BOUNDS_ENFORCE_INTERVAL
		_enforce_all_fauna_in_tank()

	# 5. Waste.
	var i: int = waste.size() - 1
	while i >= 0:
		var w: WasteParticle = waste[i]
		w.last_deposit_amount = 0.0
		if w.tick(dt, substrate):
			waste.remove_at(i)
			recycle_waste(w)
		elif w.last_deposit_amount > 0.0:
			_record_trophic_deposited(w.last_deposit_amount)
		i -= 1

	# 5b. Clams. Filter feeders that pull waste particles within radius.
	# Runs after the waste-decay step so naturally-aging waste is gone
	# before clams scan; what they consume here drains the live pool.
	# Dead clams (energy 0 or age past max) drop a shell-fragment waste
	# inside their own tick before queue_free'ing themselves.
	var dead_clams: Array = []
	for cl in clams:
		if not is_instance_valid(cl):
			dead_clams.append(cl)
			continue
		cl.tick(dt, waste, substrate)
		if not is_instance_valid(cl):
			# tick() called queue_free on death — clear from our list too.
			dead_clams.append(cl)
	for cl in dead_clams:
		clams.erase(cl)

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

	# 6b. Auto-Feed at surface — user opted in via settings; always drops
	# pellets on schedule. Scale amount down when the tank is already rich so
	# we don't pile on during spikes (absolute total_above_baseline scales
	# with grid size, so use per-cell density for that check).
	if cfg != null and cfg.auto_feed_fauna:
		_auto_feed_timer += dt
		if _auto_feed_timer >= 12.0:
			_auto_feed_timer = 0.0
			var pellet: float = 0.5
			if substrate != null:
				var cell_count: float = float(substrate.cells_x * substrate.cells_z)
				var n_density: float = substrate.total_above_baseline() / maxf(1.0, cell_count)
				if n_density > 0.10 or water_chemistry.ammonia > 0.35:
					pellet = 0.22
			var spawn_x: float = 0.0
			var spawn_z: float = 0.0
			var w := get_parent()
			if w != null and w.has_method("sample_xz_in_tank"):
				var xz: Vector2 = w.sample_xz_in_tank(0.5)
				spawn_x = xz.x
				spawn_z = xz.y
			# WATER_HEIGHT may be unset on the parent in unusual tank presets;
			# null-subtract would crash. Fall back to a safe near-surface Y.
			# Offset 0.55 below meniscus so pellets start within the fish's
			# reachable zone (fish body margin ~0.58) and don't pull the whole
			# school into the ceiling while chasing unreachable food.
			var fy: float = 5.95
			if w != null:
				var water_h = w.get("WATER_HEIGHT")
				if water_h != null:
					fy = float(water_h) - 0.55
			_spawn_waste(Vector3(spawn_x, fy, spawn_z), pellet, WasteParticle.KIND_FOOD)

	# 6b2. Natural food pulse (#50). Skipped during an ammonia spike (don't pile
	# food on a struggling tank) and in saltwater (handled by reef feeding).
	_food_pulse_timer -= dt
	if _food_pulse_timer <= 0.0:
		_food_pulse_timer = randf_range(180.0, 420.0)
		if (water_chemistry == null or water_chemistry.ammonia < 0.4) \
				and not _is_saltwater_tank():
			var wpz: Node = get_parent()
			var fy2: float = 5.95
			if wpz != null:
				var wh: Variant = wpz.get("WATER_HEIGHT")
				if wh != null:
					fy2 = float(wh) - 0.3
			var n_pellets: int = randi_range(3, 6)
			for _pi in n_pellets:
				var px: float = 0.0
				var pz: float = 0.0
				if wpz != null and wpz.has_method("sample_xz_in_tank"):
					var xz2: Vector2 = wpz.sample_xz_in_tank(0.4)
					px = xz2.x
					pz = xz2.y
				_spawn_waste(Vector3(px, fy2, pz), 0.4, WasteParticle.KIND_FOOD)
			log_story_event("Something drifts in at the surface — a brief feeding frenzy.")

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
	# plant_biomass + photo_bm already accumulated during the plant tick loop.
	_apply_ecosystem_engineering(dt)
	# Refresh snail-predator count for snail.gd's rebound logic. Cheap
	# (iterating fish is already done elsewhere; here we just count flags).
	var sp_count: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		if f.get("snail_predator"):
			sp_count += 1
	snail_predator_count = sp_count

	# Carrying-capacity overshoot stress. The cap is plant-biomass-driven
	# (more plants → bigger sustainable population). Every fish over the
	# cap accumulates background stress at a rate proportional to how far
	# the population sits past it. Since the existing breed branch
	# already requires `stress < 0.4`, this throttles reproduction
	# automatically once the tank is over-stocked — without imposing a
	# hard population cap that would feel arbitrary.
	var stocking_ratio: float = fish_stocking_ratio()
	if stocking_ratio > 1.0:
		var overshoot: float = clampf(stocking_ratio - 1.0, 0.0, 1.5)
		for f in fish:
			if not is_instance_valid(f):
				continue
			if f.get("_dying") == true:
				continue
			# Adults feel the squeeze first; fry get a discount so they
			# can grow up before the population pressure pushes them
			# out. Senescent fish basically don't care.
			var mat_v: Variant = f.get("maturity")
			var maturity_w: float = 0.4
			if mat_v != null:
				if int(mat_v) == Fish.MATURITY_ADULT:
					maturity_w = 1.0
				elif int(mat_v) == Fish.MATURITY_JUVENILE:
					maturity_w = 0.65
			f.stress = clampf(float(f.stress) + overshoot * 0.006 * maturity_w, 0.0, 1.0)

	# Nutrient pressure: 0 at <=2.0 N, 1.0 at >=8.0 N; blend nitrate from N-cycle.
	var n_pressure: float = clampf((n_total - 2.0) / 6.0, 0.0, 1.0)
	var nitrate_p: float = clampf(water_chemistry.nitrate / 1.5, 0.0, 1.0)
	n_pressure = clampf(n_pressure * 0.65 + nitrate_p * 0.35, 0.0, 1.0)
	# Plant-shortage pressure: 0 when biomass >=450 (mature planted tank),
	# 1.0 when biomass <=150 (sparse / cycling tank).
	var plant_shortage: float = clampf((450.0 - float(plant_biomass)) / 300.0, 0.0, 1.0)
	var w_shade: Node = get_parent()
	# Combined bloom pressure. Multiplicative: needs BOTH high nutrients AND
	# low plant biomass to bloom. Floaters and snails suppress runaway blooms.
	var bloom_pressure: float = n_pressure * plant_shortage
	if w_shade != null and w_shade.has_method("floater_coverage"):
		bloom_pressure *= 1.0 - float(w_shade.floater_coverage()) * 0.45
	# Grazer cascade (#49): snails, shrimp, and herbivorous fish all crop algae,
	# so adding or removing a grazer guild visibly shifts the bloom — a trophic
	# cascade the player can watch.
	var grazers: float = float(snail_count) + float(shrimp.size()) * 0.5
	bloom_pressure *= 1.0 - clampf(grazers / 24.0, 0.0, 0.42)
	# Plant-health allelopathy (#46): healthy, actively-growing plants release
	# allelochemicals + outcompete algae for nutrients. Suppression tracks plant
	# HEALTH, not just biomass — a melting planting stops fighting algae and the
	# tank greens up.
	if total_plant_biomass > 0:
		var health_ratio: float = clampf(
			total_photosynthetic_biomass / float(total_plant_biomass), 0.0, 1.0)
		bloom_pressure *= 1.0 - health_ratio * 0.30
	# Eco-Complete algae risk (#17): its very rich volcanic substrate runs a
	# higher early bloom floor that tapers over the first ~2 weeks as plants
	# and bacteria take over — matching the "algae risk" warning on the profile.
	var cfg_b: Node = _cfg()
	if cfg_b != null and String(cfg_b.substrate_type) == "eco_complete":
		var young: float = clampf(1.0 - sim_day() / 14.0, 0.0, 1.0)
		bloom_pressure = maxf(bloom_pressure, 0.20 * young)
	bloom_intensity = lerpf(bloom_intensity, bloom_pressure, clampf(dt * 0.25, 0.0, 1.0))
	var waste_nh3: float = float(waste.size()) * 0.0004
	# Walstad coupling: substrate organics mineralize into ammonia. A clean
	# substrate (near baseline) contributes nothing; a mulm-loaded substrate
	# leaks NH3 the way a real tank does when poop and detritus accumulate
	# faster than soil bacteria can process them. This closes the soil →
	# ammonia → bacteria → nitrate → plant loop that makes Walstad tanks
	# work without a filter.
	#
	# The 0.0001/excess-unit coefficient is calibrated so a clean tank
	# (~0 excess) adds nothing, a normal stocked tank (~6 excess) adds
	# ~0.0006 NH3/sec (a tap drip), and an overfed/over-stocked tank
	# (~40 excess) climbs to ~0.004/sec — visible as an ammonia spike.
	var substrate_nh3: float = 0.0
	if substrate != null:
		substrate_nh3 = substrate.total_above_baseline() * 0.0001
	# Fresh-soil ammonia leach (#20): a brand-new fertile substrate off-gasses
	# ammonia on its own for the first days (the authentic new-aquasoil bump),
	# fading as the soil settles. Only fertile substrates do this.
	if substrate != null:
		var leak_frac: float = float(substrate.reservoir_leak_override)
		if leak_frac < 0.0:
			leak_frac = 0.00015
		var soil_young: float = clampf(1.0 - sim_day() / 6.0, 0.0, 1.0)
		substrate_nh3 += soil_young * leak_frac * 14.0
	var pore_no3: float = 0.0
	if substrate != null and substrate.has_method("pore_water_nitrate_leak"):
		pore_no3 = substrate.pore_water_nitrate_leak()
	water_chemistry.tick(dt, self, get_parent(), plant_biomass,
		waste_nh3 + substrate_nh3, pore_no3, _is_saltwater_tank())
	_refresh_tank_vitals(bloom_pressure, n_total, plant_biomass)
	var bloom_favor: bool = bloom_pressure > 0.35  # for algae.tick's pressure-curve

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
		# Pick which niche this clump occupies, biased by tank state:
		#   SURFACE scum thrives where the surface gets bright light and
		#     few floaters are blocking it.
		#   HAIR algae prefers hardscape and high-flow zones.
		#   GSA appears on the glass walls under bright light.
		#   CLUSTER is the default substrate biofilm clump.
		var w := get_parent()
		var floater_cov: float = 0.0
		if w != null and w.has_method("floater_coverage"):
			floater_cov = float(w.floater_coverage())
		var kind: int = Algae.AlgaeKind.CLUSTER
		var pick_kind: float = randf()
		# Young-tank diatom phase (#52): a brand-new tank reliably runs a brown
		# diatom film for the first few days that fades as plants + bacteria
		# establish — the universal new-tank experience.
		if sim_day() < 5.0 and pick_kind < 0.5:
			kind = Algae.AlgaeKind.DIATOM
		# Strong bloom + clear surface → scum thrives at the air-water film.
		elif pick_kind < 0.18 and floater_cov < 0.35:
			kind = Algae.AlgaeKind.SURFACE
		elif pick_kind < 0.35:
			kind = Algae.AlgaeKind.HAIR
		elif pick_kind < 0.58 and plant_biomass < 320:
			# GSA shows up in sparse / cycling tanks where plants aren't
			# outcompeting it yet — slightly more common on neglected glass.
			kind = Algae.AlgaeKind.GSA
		elif pick_kind < 0.68 and bloom_pressure > 0.32:
			# Green dust algae — micro fuzz on interior glass when nutrients
			# run ahead of plant uptake (visible neglect on the walls).
			kind = Algae.AlgaeKind.GDA
		elif pick_kind < 0.72 and filter_intake_pos != Vector3.ZERO \
				and bloom_pressure > 0.25:
			# Black beard algae colonizes high-flow filter outlets.
			kind = Algae.AlgaeKind.BBA
		# Spawn position depends on kind. CLUSTER uses the tank-aware
		# sampler; SURFACE picks the same XZ but pinned to the waterline;
		# HAIR picks a hardscape anchor; GSA pins to a glass wall.
		var spawn_x: float = 0.0
		var spawn_z: float = 0.0
		if w != null and w.has_method("sample_xz_in_tank"):
			var xz: Vector2 = w.sample_xz_in_tank(0.5)
			spawn_x = xz.x
			spawn_z = xz.y
		var apos := Vector3(spawn_x, substrate_top_y + randf_range(0.3, 1.2), spawn_z)
		match kind:
			Algae.AlgaeKind.SURFACE:
				# Pin to the local water-column surface so cylindrical /
				# sphere tanks still place scum at the air-water film.
				var surf_y: float = substrate_top_y + 6.0
				if w != null and w.has_method("column_surface_y"):
					surf_y = w.column_surface_y(spawn_x, spawn_z)
				apos = Vector3(spawn_x, surf_y - 0.05, spawn_z)
			Algae.AlgaeKind.HAIR:
				# Try to anchor near a piece of hardscape; otherwise fall
				# back to a low column position. _rock_voxels live on
				# world.gd; we look it up dynamically since SimDriver
				# doesn't normally touch hardscape internals.
				if w != null:
					var rocks_v: Variant = w.get("_rock_voxels")
					var drift_v: Variant = w.get("_driftwood_voxels")
					var anchors: Array = []
					if rocks_v is Array:
						for rv in (rocks_v as Array):
							if rv != null and is_instance_valid(rv):
								anchors.append(rv)
					if drift_v is Array:
						for dv in (drift_v as Array):
							if dv != null and is_instance_valid(dv):
								anchors.append(dv)
					if not anchors.is_empty():
						var host: MeshInstance3D = anchors[randi() % anchors.size()]
						apos = host.global_position + Vector3(
							randf_range(-0.18, 0.18),
							randf_range(0.18, 0.45),
							randf_range(-0.18, 0.18))
				if w != null and w.has_method("column_surface_y"):
					apos.y = clampf(apos.y, substrate_top_y + 0.1,
						w.column_surface_y(apos.x, apos.z) - 0.1)
			Algae.AlgaeKind.GSA, Algae.AlgaeKind.GDA:
				# Pin to the nearest glass wall. We pick a side at random
				# and snap X or Z to the tank wall half-extent.
				var tc: Node = get_node_or_null("/root/TankConfig")
				var half_w: float = 6.0
				var half_d: float = 4.5
				if tc != null:
					var hwv: Variant = tc.get("tank_half_w")
					var hdv: Variant = tc.get("tank_half_d")
					if hwv != null:
						half_w = float(hwv)
					if hdv != null:
						half_d = float(hdv)
				var side: int = randi() % 4
				var y_lo: float = 0.5 if kind == Algae.AlgaeKind.GSA else 0.35
				var y_hi: float = 4.2 if kind == Algae.AlgaeKind.GSA else 5.6
				if side == 0:
					apos = Vector3(half_w - 0.08,
						substrate_top_y + randf_range(y_lo, y_hi),
						randf_range(-half_d * 0.7, half_d * 0.7))
				elif side == 1:
					apos = Vector3(-(half_w - 0.08),
						substrate_top_y + randf_range(y_lo, y_hi),
						randf_range(-half_d * 0.7, half_d * 0.7))
				elif side == 2:
					apos = Vector3(randf_range(-half_w * 0.7, half_w * 0.7),
						substrate_top_y + randf_range(y_lo, y_hi),
						half_d - 0.08)
				else:
					apos = Vector3(randf_range(-half_w * 0.7, half_w * 0.7),
						substrate_top_y + randf_range(y_lo, y_hi),
						-(half_d - 0.08))
			Algae.AlgaeKind.BBA:
				if filter_intake_pos != Vector3.ZERO:
					apos = filter_intake_pos + Vector3(
						randf_range(-0.14, 0.14),
						randf_range(0.04, 0.38),
						randf_range(-0.14, 0.14))
				else:
					apos.y = substrate_top_y + randf_range(0.2, 0.8)
			_:
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
		# Surface scum has the pale yellow-green of dust biofilm; GSA
		# reads as dark green dots; hair is brighter; cluster stays the
		# normal palette pick.
		var col: Color = palette[randi() % palette.size()]
		match kind:
			Algae.AlgaeKind.SURFACE:
				col = Color8(180, 200, 110)
			Algae.AlgaeKind.GSA:
				col = Color8(60, 105, 50)
			Algae.AlgaeKind.HAIR:
				col = Color8(125, 175, 80)
			Algae.AlgaeKind.GDA:
				col = Color8(145, 195, 95)
			Algae.AlgaeKind.BBA:
				col = Color8(28, 30, 26)  # near-black dark filaments
			Algae.AlgaeKind.DIATOM:
				col = Color8(165, 142, 92)  # tan brown
			Algae.AlgaeKind.CYANO:
				col = Color8(62, 142, 132)  # distinctive blue-green
		a.init(col, kind)
		algae.append(a)
		# Cyano bloom is the smelly-water signal real keepers know — log a
		# one-time story event the first time it appears this session so the
		# player knows what they're looking at.
		if kind == Algae.AlgaeKind.CYANO and not _logged_first_cyano:
			_logged_first_cyano = true
			log_story_event(
				"Blue-green algae (cyanobacteria) has appeared — smells musky and signals nutrient imbalance. Increase aeration, dose less.")
	# Tick existing algae. Crash phase: when plants are healthy (biomass
	# high) AND nutrients have dropped (n_total low), algae die faster.
	# This is the visible "plants outcompete the bloom" payoff that closes
	# the cycle — without it the bloom would just plateau.
	var crash: bool = plant_biomass > 360 and n_total < 4.0
	var ai: int = algae.size() - 1
	while ai >= 0:
		var a: Algae = algae[ai]
		if not is_instance_valid(a):
			algae.remove_at(ai)
			ai -= 1
			continue
		if a.tick(dt, bloom_favor):
			algae.remove_at(ai)
			a.queue_free()
		elif crash and randf() < dt * 0.12:
			algae.remove_at(ai)
			a.queue_free()
		ai -= 1

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

		# Mouthbrooder release — same shape as livebearer release but the
		# event also carries the cached clutch size so a mature brood
		# spawns intact even if the mother's hunger/stress changed mid-incubation.
		if ev.has("release_brooded_fry"):
			var brood_pack: Dictionary = ev["release_brooded_fry"]
			var bg: Dictionary = brood_pack.get("genome", {})
			if bg.size() > 0:
				_release_brooded_fry(actor as Fish, bg, int(brood_pack.get("count", 2)))

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
				_play_ambient_event("eat", -1.0, _node_species(actor))
				var consumed_nv: float = w.nutrient_value
				var leftover: float = consumed_nv * 0.4
				_record_trophic_consumed(consumed_nv, leftover if leftover > 0.04 else 0.0)
				waste.erase(w)
				recycle_waste(w)
				if leftover > 0.04:
					var new_kind: int = WasteParticle.KIND_FISH
					if actor_kind == "shrimp":
						new_kind = WasteParticle.KIND_SHRIMP
					_spawn_waste(actor.global_position + Vector3(0, -0.1, 0),
						leftover, new_kind)
				# Detritivore → biofilm feedback (see snail.gd for the
				# matching call). The fragment the eater drops back into
				# the substrate AND the act of breaking the particle both
				# feed soil bacteria, speeding the N-cycle.
				var w_bio: Node = get_parent()
				if w_bio != null and w_bio.has_method("boost_biofilm"):
					w_bio.boost_biofilm(consumed_nv)

		# Predation - remove the prey.
		if ev.has("kill_prey"):
			var prey: Node = ev["kill_prey"]
			if is_instance_valid(prey) and not consumed.has(prey):
				consumed[prey] = true
				if prey is Fish or prey is Shrimp:
					_play_ambient_death(prey, "predation")
				else:
					_play_ambient_event("eat", -1.0, _node_species(actor))
				# Visual flash at the bite — short bright burst at the
				# prey's last position. The audio event covers the beat;
				# the flash covers the eye. Spawned BEFORE queue_free
				# so we can read prey.global_position safely.
				var prey_pos: Vector3 = (prey as Node3D).global_position
				var av := get_tree().current_scene.get_node_or_null("AquariumVisuals")
				if av != null and av.has_method("spawn_predation_flash"):
					av.call("spawn_predation_flash", prey_pos)
				# Surface-disturbance ripple if the strike happened near
				# the waterline. World caps via spawn_burst_ripple's own
				# tween lifespan, no extra throttle needed.
				var w_node: Node = get_parent()
				if w_node != null and w_node.has_method("spawn_burst_ripple"):
					# Try to find the water surface height — most tanks
					# expose WATER_HEIGHT via the world script. Fall back
					# to a generous threshold otherwise.
					var water_y_v: Variant = w_node.get("WATER_HEIGHT")
					var water_y: float = 6.5 if water_y_v == null else float(water_y_v)
					if prey_pos.y > water_y - 1.2:
						w_node.call("spawn_burst_ripple", prey_pos, 1.3)
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
				_play_ambient_event("eat", -1.0, _node_species(actor))
				_spawn_waste(snail.global_position, 0.18, WasteParticle.KIND_FISH)
				snail.queue_free()

		# Specialist grazing - corydoras / algae_grazer cropping algae clusters.
		# Algae shrink (or get removed entirely) when consumed; drop a tiny
		# waste particle so the consumed nutrients re-enter the substrate.
		if ev.has("eat_algae"):
			var alga = ev["eat_algae"]
			if is_instance_valid(alga) and not consumed.has(alga):
				consumed[alga] = true
				_play_ambient_event("eat", -1.0, _node_species(actor))
				algae.erase(alga)
				_spawn_waste(alga.global_position, 0.08, WasteParticle.KIND_FISH)
				alga.queue_free()

		if ev.get("die", false):
			if not consumed.has(actor):
				consumed[actor] = true
				# Infer the cause so the death note can bend (old age resolves,
				# starvation goes dim). Predation deaths come through kill_prey.
				var death_cause: String = ""
				if actor.get("age") != null and actor.get("max_age_s") != null \
						and float(actor.max_age_s) > 0.0 \
						and float(actor.age) >= float(actor.max_age_s):
					death_cause = "age"
				elif actor.get("hunger") != null and float(actor.hunger) > 0.8:
					death_cause = "starvation"
				_play_ambient_death(actor, death_cause)
				# Death ritual + mourning hook. For named fish we record a
				# mourning event so schoolmates visibly slow down for ~60s,
				# and we log a personalized epitaph using their lifetime
				# bio numbers — the player sees Mira's death as a sentence
				# about Mira, not a generic "a tetra died" line. Generic
				# message still fires on the very first unnamed death so
				# tutorials / first-launch tanks still get a marker line.
				if actor_kind == "fish" and actor.get("fish_name") != null \
						and String(actor.fish_name) != "":
					var species_id: String = String(actor.species) if actor.get("species") != null else ""
					# Weighted mourning (#90): favorited / long-lived individuals
					# leave a deeper, wider ripple through the tank.
					var mourn_w: float = 1.0
					if actor.get("id") != null and favorite_ids.has(String(actor.id)):
						mourn_w += 0.9
					if actor.get("age") != null and actor.get("max_age_s") != null \
							and float(actor.max_age_s) > 0.0 \
							and float(actor.age) / float(actor.max_age_s) > 0.9:
						mourn_w += 0.4
					_record_mourning(species_id, actor.position, mourn_w)
					var epitaph: String = _epitaph_for_fish(actor)
					if epitaph != "":
						log_story_event(epitaph)
						# Visible marker at the death point — re-uses the
						# existing burst ripple shader for a clean
						# "something happened here" pulse.
						var w_node: Node = get_parent()
						if w_node != null and w_node.has_method("spawn_burst_ripple"):
							w_node.spawn_burst_ripple(actor.position)
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

	# Push a tank summary to AIDirector when the LLM is ready for a new
	# intent refresh. The whole call is a single HTTP POST every ~60 s and
	# returns asynchronously; no per-tick latency. Off when AI is disabled
	# or Ollama is unreachable.
	var ai_d: Node = get_node_or_null("/root/AIDirector")
	if ai_d != null and ai_d.has_method("intent_refresh_due") and ai_d.intent_refresh_due():
		ai_d.push_tank_summary(_build_ai_summary())


# Home-screen widget snapshot. A flat JSON file at user://widget_state.json
# that an Android AppWidgetProvider plugin can read on each widget refresh.
# Resolves to /data/data/<package>/files/widget_state.json on Android, which
# is readable by the widget code since it runs in the same UID as the game.
# We rewrite every WIDGET_EXPORT_INTERVAL_S to keep the IO load trivial
# (every 30 sim seconds = ~6 KB/min worst case).
const WIDGET_EXPORT_INTERVAL_S: float = 30.0
const WIDGET_EXPORT_PATH: String = "user://widget_state.json"
var _widget_export_timer: float = 0.0


func _export_widget_state() -> void:
	# Only do this on mobile — desktop users don't have a home-screen widget,
	# and the periodic write would just spin the disk for nothing.
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return
	var nh3: float = water_chemistry.ammonia if water_chemistry != null else 0.0
	var no3: float = water_chemistry.nitrate if water_chemistry != null else 0.0
	var phase_int: int = water_chemistry.cycle_phase if water_chemistry != null else 0
	var phase_label: String = WaterChemistry.phase_label(phase_int) if water_chemistry != null else ""
	# Last named birth: scan named fish for the youngest one as a proxy.
	var last_birth_name: String = ""
	var youngest_age: float = 99999.0
	for f in fish:
		if not is_instance_valid(f):
			continue
		var nm: String = String(f.get("fish_name") if f.get("fish_name") != null else "")
		if nm == "":
			continue
		var a: float = float(f.get("age") if f.get("age") != null else 99999.0)
		if a < youngest_age:
			youngest_age = a
			last_birth_name = nm
	var state: Dictionary = {
		"schema": 1,
		"updated_unix": int(Time.get_unix_time_from_system()),
		"fish_count": fish.size(),
		"shrimp_count": shrimp.size(),
		"snail_count": snail_count,
		"plant_count": plants.size(),
		"plant_biomass": total_plant_biomass,
		"o2_pct": int(clampf(dissolved_o2 / 1.2, 0.0, 1.0) * 100),
		"ammonia_ppm": "%.2f" % nh3,
		"nitrate_ppm": "%.2f" % no3,
		"cycle_phase": phase_label,
		"is_daylight": daylight() > 0.5,
		"bloom_intensity": "%.2f" % bloom_intensity,
		"last_named_fish": last_birth_name,
	}
	var f := FileAccess.open(WIDGET_EXPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()


# Build the compact JSON-able summary handed to AIDirector. Kept under
# ~2 KB so a 3B-parameter model can produce a sub-second response. We
# pick up to 6 named fish (highest age * boldness so the most "characterful"
# ones are featured) and one-line aggregate stats.
func _build_ai_summary() -> Dictionary:
	var named: Array = []
	for f in fish:
		if not is_instance_valid(f):
			continue
		if String(f.get("fish_name") if f.get("fish_name") != null else "") == "":
			continue
		var personality_v: Variant = f.get("personality")
		var bold_p: float = 0.5
		if personality_v is Dictionary:
			bold_p = float((personality_v as Dictionary).get("boldness", 0.5))
		named.append({
			"fish": f,
			"score": float(f.age) * (0.5 + bold_p),
		})
	named.sort_custom(func(a: Dictionary, b: Dictionary):
		return float(a["score"]) > float(b["score"]))
	var max_named: int = mini(6, named.size())
	var named_out: Array = []
	for i in range(max_named):
		var f: Node = named[i]["fish"]
		var personality_v: Variant = f.get("personality")
		var traits_s: String = ""
		if personality_v is Dictionary:
			var pd: Dictionary = personality_v
			var top: String = "average"
			var top_val: float = 0.6
			for k in pd.keys():
				if float(pd[k]) > top_val:
					top_val = float(pd[k]); top = String(k)
			traits_s = top
		named_out.append({
			"id": String(f.get("id") if f.get("id") != null else ""),
			"name": String(f.get("fish_name") if f.get("fish_name") != null else ""),
			"trait": traits_s,
			"hunger": int(clampf(float(f.get("hunger") if f.get("hunger") != null else 0.0), 0.0, 1.0) * 100),
			"stress": int(clampf(float(f.get("stress") if f.get("stress") != null else 0.0), 0.0, 1.0) * 100),
		})
	var nh3: float = water_chemistry.ammonia if water_chemistry != null else 0.0
	return {
		"fish_count": fish.size(),
		"shrimp_count": shrimp.size(),
		"snail_count": snail_count,
		"o2_pct": int(clampf(dissolved_o2 / 1.2, 0.0, 1.0) * 100),
		"ammonia": "%.2f" % nh3,
		"day_phase": "%.2f" % day_phase,
		"is_daylight": daylight() > 0.5,
		"named_fish": named_out,
	}


func recycle_waste(w: WasteParticle) -> void:
	if w == null:
		return
	w.prepare_for_pool()
	if _waste_pool.size() < WASTE_POOL_CAP:
		_waste_pool.append(w)
	else:
		w.queue_free()


func _acquire_waste() -> WasteParticle:
	while not _waste_pool.is_empty():
		var w: WasteParticle = _waste_pool.pop_back()
		if is_instance_valid(w):
			w.visible = true
			return w
	var w_new := WasteParticle.new()
	waste_root.add_child(w_new)
	return w_new


func _spawn_waste(at: Vector3, amount: float, kind: int = 0,
		food_subtype: int = WasteParticle.FOOD_SUB_PELLET) -> void:
	if waste_root == null:
		return
	# Global waste cap. Without it, an unattended cycling tank with many
	# plants and no cleanup crew accumulates thousands of waste particles
	# (each one a Node3D + animation), tanking framerate AND giving the
	# visual impression of "things falling forever." When the cap is hit,
	# food (kind=3) always lands (so feeding still works) but decay
	# byproducts (kind 0/1/2) are dropped silently.
	if waste.size() >= WASTE_CAP:
		if kind != WasteParticle.KIND_FOOD:
			return
		# At cap with a food spawn, recycle the oldest decay particle
		# so the cap stays at WASTE_CAP overall.
		for i in range(waste.size()):
			var old: WasteParticle = waste[i] as WasteParticle
			if old != null and old.kind != WasteParticle.KIND_FOOD:
				if is_instance_valid(old):
					recycle_waste(old)
				waste.remove_at(i)
				break
	var w := _acquire_waste()
	w.global_position = at
	w.init(amount, substrate_top_y, kind, food_subtype)
	register_waste(w)
	_record_trophic_produced(amount)


# Player tap-to-feed: spawns a small cluster at the water surface.
func spawn_player_food(world_pos: Vector3, food_subtype: int = WasteParticle.FOOD_SUB_PELLET) -> void:
	var count: int = 4
	var spread: float = 0.18
	var value: float = 0.45
	match food_subtype:
		WasteParticle.FOOD_SUB_FLAKE:
			count = randi_range(7, 10)
			spread = 0.28
			value = 0.32
		WasteParticle.FOOD_SUB_WORM:
			count = randi_range(3, 5)
			spread = 0.22
			value = 0.62
		WasteParticle.FOOD_SUB_WAFER:
			count = randi_range(2, 3)
			spread = 0.14
			value = 0.55
		_:
			count = randi_range(4, 6)
	for i in count:
		var jx: float = randf_range(-spread, spread)
		var jz: float = randf_range(-spread, spread)
		var pos: Vector3 = Vector3(world_pos.x + jx, world_pos.y - 0.02, world_pos.z + jz)
		_spawn_waste(pos, value, WasteParticle.KIND_FOOD, food_subtype)
	record_feed_drop(world_pos, food_subtype)


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
		_clamp_entity_to_bounds(baby, 0.18, 0.04)


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
		fry._reclamp_territory_to_tank()
	# Mother's belly is empty: extra exhaustion + small recovery cooldown.
	mother.energy = maxf(0.0, mother.energy - 0.20)
	_play_ambient_event("birth", -1.0, _node_species(mother))


# Mouthbrooder fry release. Drops a small clutch from the female's
# throat — they swim out around her face for a moment, then disperse.
# Same fry registration path as livebearer drops.
func _release_brooded_fry(mother: Fish, brood_genome: Dictionary, count: int) -> void:
	if fauna_root == null:
		return
	var n: int = clampi(count, 1, 4)
	for i in n:
		var g: Dictionary = brood_genome.duplicate(true)
		g["sex"] = randi() % 2
		if g.has("base_color"):
			g["base_color"] = (g["base_color"] as Color).lerp(
				Color(randf(), randf(), randf()), 0.05)
		var fry := Fish.new()
		fauna_root.add_child(fry)
		# Pop out from in front of the mother's head, slightly spread.
		var fwd: Vector3 = mother.heading * 0.18
		fry.global_position = mother.global_position + fwd + Vector3(
			randf_range(-0.18, 0.18),
			randf_range(-0.05, 0.10),
			randf_range(-0.18, 0.18))
		fry.init_genome(g)
		fry.maturity = Fish.MATURITY_FRY
		fry.hunger = 0.20
		fry.energy = 0.95
		register_fish(fry)
		fry._reclamp_territory_to_tank()
	# Mother bottoms out — caring for a brood is expensive.
	mother.energy = maxf(0.0, mother.energy - 0.25)
	mother.stress = clampf(mother.stress * 0.5, 0.0, 0.5)
	_play_ambient_event("birth", -1.0, _node_species(mother))
	if not _logged_first_hatch:
		_logged_first_hatch = true
		log_story_event("First fry released from mouthbrooding")


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
			fry._reclamp_territory_to_tank()
		# Mother's belly is empty: extra exhaustion + small recovery cooldown.
		mother.energy = maxf(0.0, mother.energy - 0.20)
		_play_ambient_event("birth", -1.0, _node_species(mother))
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
	# Bubble-nest anchoring (#35): labyrinth breeders prefer floater shade.
	var w_lay: Node = get_parent()
	if (a.labyrinth_breather or b.labyrinth_breather) and w_lay != null \
			and w_lay.has_method("query_floaters_in_radius"):
		var near_floaters: Array = w_lay.query_floaters_in_radius(mid, 3.0)
		var best_fp: FloatingPlant = null
		var best_fp_d2: float = 9.0
		for fp in near_floaters:
			if fp is FloatingPlant:
				var d2f: float = fp.position.distance_squared_to(mid)
				if d2f < best_fp_d2:
					best_fp_d2 = d2f
					best_fp = fp
		if best_fp != null:
			lay_at = best_fp.global_position + Vector3(0, -0.12, 0)

	for i in n:
		var g: Dictionary = a.produce_offspring_genome(b)
		var e := FishEgg.new()
		fauna_root.add_child(e)
		e.global_position = lay_at + Vector3(
			randf_range(-0.2, 0.2),
			randf_range(0.0, 0.15),
			randf_range(-0.2, 0.2),
		)
		_clamp_entity_to_bounds(e, 0.22, 0.06)
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

	_play_ambient_event("spawn", -1.0, _node_species(a))


func _hatch(e: FishEgg) -> void:
	if fauna_root == null:
		return
	var fry := Fish.new()
	fry.species = e.species
	fauna_root.add_child(fry)
	fry.global_position = e.global_position + Vector3(0, 0.1, 0)
	fry.init_genome(e.genome)
	fry.maturity = Fish.MATURITY_FRY
	fry.hunger = 0.3
	fry.energy = 1.0
	register_fish(fry)
	fry._reclamp_territory_to_tank()
	_play_ambient_event("birth", -1.0, _node_species(e))
	if not _logged_first_hatch:
		_logged_first_hatch = true
		log_story_event("First fry hatched — a baby %s entered the tank." % e.species)


# Helper - look up the audio node and emit a specific musical event.
# The optional `species` is used by the audio side to pick a per-species pitch
# palette (small bright fish trend up, large predators trend down).
func _play_ambient_event(event_name: String, intensity: float = -1.0, species: String = "") -> void:
	var audio := _ambient_audio()
	if audio != null and audio.has_method("play_aquarium_event"):
		audio.play_aquarium_event(event_name, intensity, species)


# Feed average creature swim speed into the music once per second so the
# shaker / flow layer tracks how ACTIVE the tank is: a feeding frenzy or a
# startled, darting school lifts the groove; a calm tank settles it. The audio
# side (note_swim_activity) only raises the smoothed "flow" toward this value,
# so it decays naturally when the tank quiets — no need to push every frame.
func _push_swim_activity() -> void:
	var audio := _ambient_audio()
	if audio == null or not audio.has_method("note_swim_activity"):
		return
	var total: float = 0.0
	var n: int = 0
	for f in fish:
		if not is_instance_valid(f):
			continue
		var ms: float = float(f.max_speed)
		if ms > 0.01:
			total += clampf(float(f.speed) / ms, 0.0, 1.0)
			n += 1
	for s in shrimp:
		if not is_instance_valid(s):
			continue
		var ms2: float = float(s.max_speed)
		if ms2 > 0.01:
			total += clampf(float(s.speed) / ms2, 0.0, 1.0)
			n += 1
	if n > 0:
		audio.note_swim_activity(clampf(total / float(n), 0.0, 1.0))


# Emit a death musically, colored by the creature's age + cause when the audio
# engine supports the richer path (young deaths read higher/unresolved, old
# deaths resolve to the tonic; starvation/hypoxia bend the chord). Falls back
# to the plain death event on older audio builds.
func _play_ambient_death(node: Node, cause: String = "") -> void:
	var audio := _ambient_audio()
	if audio == null:
		return
	var species: String = _node_species(node)
	var age01: float = -1.0
	if node != null:
		var a: Variant = node.get("age")
		var ma: Variant = node.get("max_age_s")
		if a != null and ma != null and float(ma) > 0.0:
			age01 = clampf(float(a) / float(ma), 0.0, 1.0)
	if audio.has_method("play_aquarium_event_extended"):
		audio.play_aquarium_event_extended("death", species, -1.0, age01, cause)
	elif audio.has_method("play_aquarium_event"):
		audio.play_aquarium_event("death", -1.0, species)


# Cheap species-id reader — safe on any node that may or may not have it.
func _node_species(n: Object) -> String:
	if n == null:
		return ""
	var v: Variant = n.get("species")
	if v == null:
		return ""
	return String(v)


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
	var w: Node = get_parent()

	var fish_n: int = 0
	for f in fish:
		if fish_n >= ECO_MAX_FISH_SAMPLES:
			break
		if not is_instance_valid(f):
			continue
		if f.get("_dying") == true:
			continue
		var p: Vector3 = f.global_position
		if w != null and w.has_method("is_inside_tank") \
				and not w.is_inside_tank(p.x, p.z, 0.35, p.y):
			continue
		substrate.consume_at(Vector3(p.x, substrate_top_y, p.z), 0.0014)
		var plume: Vector3 = Vector3(
			p.x + randf_range(-0.75, 0.75),
			substrate_top_y,
			p.z + randf_range(-0.75, 0.75))
		substrate.add_at(plume, 0.0010)
		# Bioturbation (#16): fish stirring the upper bed vent trapped anaerobic
		# gas, keeping the substrate healthy — the cory/loach mutualism made
		# mechanical. Bottom-dwellers stir hardest.
		if substrate.has_method("release_anaerobic_at"):
			var stir: float = 0.06 if p.y < substrate_top_y + 2.0 else 0.02
			substrate.release_anaerobic_at(Vector3(p.x, substrate_top_y, p.z), stir)
		fish_n += 1

	var shrimp_n: int = 0
	for s in shrimp:
		if shrimp_n >= ECO_MAX_SHRIMP_SAMPLES:
			break
		if not is_instance_valid(s):
			continue
		if s.get("_dying") == true:
			continue
		var sp: Vector3 = s.global_position
		if w != null and w.has_method("is_inside_tank") \
				and not w.is_inside_tank(sp.x, sp.z, 0.35, sp.y):
			continue
		substrate.add_at(Vector3(sp.x, substrate_top_y, sp.z), 0.0016)
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
		if w != null and w.has_method("is_inside_tank") \
				and not w.is_inside_tank(np.x, np.z, 0.35, np.y):
			continue
		substrate.add_at(Vector3(np.x, substrate_top_y, np.z), 0.0013)
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
		g["snail_predator"] = g.get("snail_predator", false) or randf() < float(a.get("snail_predator_ratio", 0.0))
	if randf() < 0.22 + pred_bias * 0.38:
		g["shrimp_predator"] = g.get("shrimp_predator", false) or randf() < float(a.get("shrimp_predator_ratio", 0.0))
	if randf() < 0.10 + float(a.get("armor_ratio", 0.0)) * 0.35:
		g["armor_plates"] = g.get("armor_plates", false) or randf() < float(a.get("armor_ratio", 0.0))
	if randf() < 0.10 + float(a.get("barbels_ratio", 0.0)) * 0.30:
		g["has_barbels"] = g.get("has_barbels", false) or randf() < float(a.get("barbels_ratio", 0.0))
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
		g["is_cleaner"] = g.get("is_cleaner", false) or randf() < float(a.get("cleaner_ratio", 0.0))
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


func _apply_library_guided_plant_tuning(seed_data: Dictionary) -> Dictionary:
	var a: Dictionary = _library_analysis("plant")
	if int(a.get("entry_count", 0)) <= 0:
		return seed_data
	var out: Dictionary = seed_data.duplicate(true)
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


# Bottleneck scar (#38): a lineage rescued from the brink carries the genetic
# cost of inbreeding — reduced fecundity and the occasional minor deformity —
# so a population crash leaves a visible mark even after recovery.
func _apply_bottleneck_scar(genome: Dictionary, organism_type: String) -> Dictionary:
	if genome.is_empty():
		return genome
	var g: Dictionary = genome
	match organism_type:
		"fish":
			g["fecundity"] = clampf(float(g.get("fecundity", 0.6)) * 0.7, 0.0, 1.0)
			if randf() < 0.25:
				g["body_elongation"] = clampf(
					float(g.get("body_elongation", 1.0)) * randf_range(0.85, 1.15), 0.7, 1.6)
		"shrimp":
			g["max_age_s"] = clampf(float(g.get("max_age_s", 360.0)) * 0.9, 120.0, 620.0)
		"snail":
			g["shell_size"] = clampf(float(g.get("shell_size", 1.0)) * randf_range(0.9, 1.0), 0.6, 1.6)
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
	return not not w.spawn_library_entry(genome, organism_type)


func _spawn_resilience_plant(seed_data: Dictionary) -> bool:
	if seed_data.is_empty():
		return false
	var w: Node = get_parent()
	if w == null or not w.has_method("spawn_seedling"):
		return false
	var xz: Vector2 = Vector2.ZERO
	if w.has_method("sample_xz_in_tank"):
		xz = w.sample_xz_in_tank(0.55)
	var sub_y: float = float(w.get("SUBSTRATE_DEPTH")) if w.get("SUBSTRATE_DEPTH") != null else substrate_top_y
	var pos: Vector3 = Vector3(xz.x, sub_y, xz.y)
	w.spawn_seedling(pos, seed_data.get("ramp", []), int(seed_data.get("generation", 1)), seed_data.get("seed_config", {}))
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
		spawned = _spawn_resilience_genome(
			_apply_bottleneck_scar(_make_resilience_fish_genome(), "fish"), "fish")
		if spawned:
			log_story_event("A late-born fry survives the bottleneck — the line holds on.")

	if not spawned:
		if shrimp_live > 0 and shrimp_live <= RESILIENCE_SHRIMP_FLOOR \
				and randf() < RESILIENCE_RESCUE_CHANCE:
			spawned = _spawn_resilience_genome(
				_apply_bottleneck_scar(_make_resilience_shrimp_genome(), "shrimp"), "shrimp")
			if spawned:
				log_story_event("A lone berried shrimp releases her last brood — the colony rebuilds.")

	if not spawned:
		if snails_live > 0 and snails_live <= RESILIENCE_SNAIL_FLOOR \
				and snail_eggs < RESILIENCE_MAX_SNAIL_EGGS \
				and randf() < RESILIENCE_RESCUE_CHANCE:
			spawned = _spawn_resilience_genome(
				_apply_bottleneck_scar(_make_resilience_snail_genome(), "snail"), "snail")
			if spawned:
				log_story_event("A snail egg hitchhiked in on a leaf — a new clutch appears.")

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
	var seed_data: Dictionary = _make_resilience_plant_seed()
	if seed_data.is_empty():
		return
	var w: Node = get_parent()
	if w == null or not w.has_method("spawn_seedling"):
		return
	var is_saltwater: bool = false
	var sw: Variant = w.get("_active_substrate_profile")
	if sw is Dictionary:
		is_saltwater = not not (sw as Dictionary).get("is_saltwater", false)
	var center: Vector2 = Vector2.ZERO
	if w.has_method("_pick_ecology_site"):
		var half_d: float = float(w.get("TANK_HALF_D")) if w.get("TANK_HALF_D") != null else 4.0
		center = w._pick_ecology_site(
			is_saltwater, -half_d * 0.82, half_d * 0.82, 0.35, 0.45)
	elif w.has_method("sample_xz_in_tank"):
		center = w.sample_xz_in_tank(0.45)
	var base_ramp: Array = seed_data.get("ramp", []).duplicate(true)
	var base_cfg: Dictionary = seed_data.get("seed_config", {}).duplicate(true)
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
		w.spawn_seedling(p, child_ramp, int(seed_data.get("generation", 1)) + 1, child_cfg)


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
		"fish_carrying_capacity": fish_carrying_capacity(),
		"fish_stocking_ratio": fish_stocking_ratio(),
		"waste_particles": waste.size(),
		"substrate_nutrients_total": substrate.total_above_baseline() if substrate else 0.0,
		"dissolved_o2": dissolved_o2,
		"ammonia": water_chemistry.ammonia,
		"nitrite": water_chemistry.nitrite,
		"nitrate": water_chemistry.nitrate,
		"cycle_phase": water_chemistry.cycle_phase,
		"cycle_label": _cycle_label_for_hud(),
		"bacteria_colony": water_chemistry.bacteria_colony,
		"alkalinity_proxy": water_chemistry.alkalinity_proxy,
		"reef_nutrients": water_chemistry.reef_nutrients,
		"is_saltwater": _is_saltwater_tank(),
		"effective_warmth": _tank_warmth_sample(),
		"floater_coverage": _floater_coverage(),
		"floater_count": _floater_count(),
		"bloom_intensity": bloom_intensity,
		"bloom_pressure": float(tank_vitals.get("bloom_pressure", bloom_intensity)),
		"tank_age_s": tank_age_s,
		"sim_day": sim_day(),
		"sim_day_label": sim_day_label(),
		"hud_mode": hud_ecology_mode(),
		"trophic_recycle_pct": float(tank_vitals.get("trophic_recycle_pct", 0.0)),
		"trophic_recycle_hour_pct": float(tank_vitals.get("trophic_recycle_hour_pct", 0.0)),
		"cycle_banner": WaterChemistry.phase_banner(water_chemistry.cycle_phase, sim_day()),
		"aeration_fixture": aeration_fixture,
		"reef_bleach_level": _max_reef_bleach(),
		# Living-balance readouts surfaced in the water-detail panel.
		"ph": water_chemistry.ph,
		"dissolved_co2": water_chemistry.dissolved_co2,
		"kh": water_chemistry.kh,
		"gh": water_chemistry.gh,
		"iron": water_chemistry.iron,
		"toxic_nh3": water_chemistry.toxic_ammonia,
		"stability": stability,
		"filter_clog": _filter_clog,
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
	"nitrite": [],
	"nitrate": [],
	"bloom_intensity": [],
	"waste_particles": [],
	"cycle_phase": [],
	# Living-balance history: the stability curve (#76) and the CO2 half of the
	# breathing curve (#22) so chip-tap sparklines can plot them.
	"stability": [],
	"dissolved_co2": [],
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
# One-shot story event flag for cyanobacteria appearance — the iconic "smelly
# water" indicator gets a single contextual log on first sighting.
var _logged_first_cyano: bool = false


func log_story_event(text: String, skip_notification: bool = false) -> void:
	var entry: Dictionary = {
		"t": elapsed_runtime_s,
		"tank_age_s": tank_age_s,
		"sim_day": sim_day_label(),
		"day_phase": day_phase,
		"text": text,
		"skip_notification": skip_notification,
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

const SAVE_STATE_VERSION: int = 5


func save_state() -> Dictionary:
	# Mint ids for any entity that doesn't have one yet.
	_ensure_ids()
	# Drop favorites whose creature is gone so the persisted set stays bounded.
	_prune_dead_favorites()
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
			"tank_age_s": tank_age_s,
			"next_entity_id": _next_entity_id,
			"substrate_type": cfg_substrate,
			"tank_preset": cfg_preset,
			# Feed-time history — persisted so the player's feeding schedule
			# survives across sessions. Without this, anticipation resets to
			# zero on every reload and never builds up.
			"feed_time_history": _feed_time_history.duplicate(),
			# Long-arc state (H8): legacy stats, day milestones, equipment age,
			# stability curve.
			"tank_legacy": tank_legacy.duplicate(true),
			"milestone_flags": _milestone_flags.duplicate(true),
			"filter_media_age_s": _filter_media_age_s,
			"filter_clog": _filter_clog,
			"stability": stability,
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
		"clams": [],
		"discovered_species": _get_discovered_species_for_save(),
		"story_events": story_events.duplicate(true),
		"trophic_ledger": trophic_ledger.duplicate(true),
		# Player-starred individuals (Residents panel). _ensure_ids() above
		# guarantees every favorited creature already has a stable id.
		"favorites": favorite_ids.keys(),
		"primary_favorite": primary_favorite_id,
	}
	if water_chemistry != null:
		out["water_chemistry"] = water_chemistry.to_save_dict()
	for p in plants:
		if is_instance_valid(p):
			out["plants"].append(p.to_save_dict())
	out["plant_fragments"] = []
	for frag in plant_fragments:
		if is_instance_valid(frag) and frag.has_method("to_save_dict"):
			out["plant_fragments"].append(frag.to_save_dict())
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
	for cl in clams:
		if is_instance_valid(cl) and cl.has_method("to_save_dict"):
			out["clams"].append(cl.to_save_dict())
	# Floating surface plants live on World (not in plants[]). Persist them so
	# custom Creature-Creator floaters survive a reload.
	var w_save: Node = get_parent()
	if w_save != null and w_save.has_method("floaters_to_save"):
		out["floaters"] = w_save.floaters_to_save()
	if w_save != null and w_save.has_method("ambient_to_save"):
		out["world_ambient"] = w_save.ambient_to_save()
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
	if save_ver != SAVE_STATE_VERSION and save_ver < SAVE_STATE_VERSION:
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
	var has_tank_age: bool = sim_d.has("tank_age_s")
	if has_tank_age:
		tank_age_s = float(sim_d.get("tank_age_s", 0.0))
	else:
		tank_age_s = 0.0
	_next_entity_id = int(sim_d.get("next_entity_id", _next_entity_id))
	var saved_story: Variant = d.get("story_events", null)
	if saved_story is Array:
		story_events = (saved_story as Array).duplicate(true)
	var saved_trophic: Variant = d.get("trophic_ledger", null)
	if saved_trophic is Dictionary:
		trophic_ledger = (saved_trophic as Dictionary).duplicate(true)
	var saved_fth: Variant = sim_d.get("feed_time_history", null)
	if saved_fth is Array:
		_feed_time_history = (saved_fth as Array).duplicate()
	var saved_legacy: Variant = sim_d.get("tank_legacy", null)
	if saved_legacy is Dictionary:
		tank_legacy = (saved_legacy as Dictionary).duplicate(true)
	var saved_milestones: Variant = sim_d.get("milestone_flags", null)
	if saved_milestones is Dictionary:
		_milestone_flags = (saved_milestones as Dictionary).duplicate(true)
	_filter_media_age_s = float(sim_d.get("filter_media_age_s", 0.0))
	_filter_clog = float(sim_d.get("filter_clog", 0.0))
	stability = float(sim_d.get("stability", 1.0))
	if water_chemistry != null:
		water_chemistry.apply_save_dict(d.get("water_chemistry", {}), save_ver)
	if not has_tank_age and save_ver < SAVE_STATE_VERSION and water_chemistry != null:
		match water_chemistry.cycle_phase:
			WaterChemistry.CyclePhase.ESTABLISHED:
				tank_age_s = WaterChemistry.SIM_DAY_S * 21.0
			WaterChemistry.CyclePhase.NITRITE_SPIKE:
				tank_age_s = WaterChemistry.SIM_DAY_S * 5.0
			WaterChemistry.CyclePhase.AMMONIA_SPIKE:
				tank_age_s = WaterChemistry.SIM_DAY_S * 2.0
			WaterChemistry.CyclePhase.CYCLING:
				tank_age_s = WaterChemistry.SIM_DAY_S * 1.0
			_:
				tank_age_s = 0.0

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

	for frag_dict in d.get("plant_fragments", []):
		var frag := PlantFragment.new()
		if plants_root != null:
			plants_root.add_child(frag)
		frag.apply_save_dict(frag_dict)
		plant_fragments.append(frag)

	# 4. Algae.
	for alga_dict in d.get("algae", []):
		var a: Node = _spawn_algae_from_dict(alga_dict)
		if a != null:
			algae.append(a)

	# 4b. Clams.
	for clam_dict in d.get("clams", []):
		var cl: Node = _spawn_clam_from_dict(clam_dict)
		if cl != null:
			id_map[String(cl.id)] = cl

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
	if w_load != null and w_load.has_method("restore_ambient"):
		w_load.restore_ambient(d.get("world_ambient", {}))
	if save_ver < SAVE_STATE_VERSION and not d.has("world_ambient"):
		if w_load != null and w_load.has_method("backfill_legacy_ambient"):
			w_load.backfill_legacy_ambient(tank_age_s)

	# 10. Cross-reference pass: resolve partner_id → partner Node refs.
	_resolve_refs(d, id_map)

	sync_species_discoveries()

	# Clamp every restored entity — saves from box tanks or pre-clamp builds
	# can land outside curved (cylinder / sphere) walls.
	_clamp_loaded_entities()

	# 11b. Residents: restore favorites and start tracking loaded creatures.
	# load_state spawns creatures without calling register_*, so wire their
	# tree_exiting here; otherwise creature_removed would never fire for them.
	favorite_ids.clear()
	for fid in d.get("favorites", []):
		favorite_ids[String(fid)] = true
	primary_favorite_id = String(d.get("primary_favorite", ""))
	track_all_living()
	favorites_changed.emit()

	# 11. Finally, restore time_scale. We do this LAST because some entity
	# init paths read time_scale and we want them to see a stable state.
	time_scale = float(sim_d.get("time_scale", 1.0))

	# "Previously on the tank" recap. When the gap since the last save is
	# meaningful (≥ 15 min real time) and the AI is enabled+narrating, ask
	# Ollama to compose a one-liner about what changed during the absence.
	# Offline path: log a built-in line so the player at least sees the
	# gap acknowledged ("You were away for 3 hours — the tank kept ticking").
	var saved_unix: int = int(d.get("saved_unix", 0))
	if saved_unix > 0:
		var gap_s: int = int(Time.get_unix_time_from_system()) - saved_unix
		if gap_s >= 900:  # 15 min
			_emit_away_recap(gap_s)


# Compose a "you were away for X" line. Tries Ollama first (when chronicle
# is on); falls back to a built-in human-readable description. Either way
# the result flows into the existing story_events log.
func _emit_away_recap(gap_s: int) -> void:
	var human_gap: String = _format_gap_human(gap_s)
	# Snapshot stats the LLM can talk about: counts of living creatures,
	# how many bio'd fish (proxy for "named individuals"), tank cycle phase.
	var ai_d: Node = get_node_or_null("/root/AIDirector")
	var ai_on: bool = ai_d != null and bool(ai_d.enabled) and bool(ai_d.chronicle_enabled) \
		and int(ai_d.conn_state) == int(ai_d.ConnState.OK)
	if not ai_on:
		# Away summary (#94): the tank lived independently while you were gone —
		# note that it managed (or weathered a scare) so its autonomy reads.
		var tail: String = "The tank kept itself going."
		if int(tank_legacy.get("crashes", 0)) > 0 and stability > 0.5:
			tail = "It weathered a rough patch and steadied itself."
		elif fish.size() > int(tank_legacy.get("peak_fish", 0)) - 1 and fish.size() > 0:
			tail = "Everyone's still here, holding steady."
		log_story_event("You were away for %s. %s" % [human_gap, tail])
		return
	# AIDirector composes the line via its chronicle path (note_event).
	var named: int = 0
	for f in fish:
		if is_instance_valid(f) and f.get("fish_name") != null \
				and String(f.fish_name) != "":
			named += 1
	ai_d.note_event("away_recap", "Player returned after %s. %d fish, %d shrimp, %d named individuals. Water O2 %.0f%%." % [
		human_gap, fish.size(), shrimp.size(), named,
		clampf(dissolved_o2 / 1.2, 0.0, 1.0) * 100.0,
	])
	# Force a flush so the line appears immediately rather than waiting
	# for the next 18 s batch window — the recap reads as stale otherwise.
	if ai_d.has_method("_flush_chronicle"):
		ai_d._flush_chronicle()


static func _format_gap_human(s: int) -> String:
	if s < 3600:
		var m: int = int(round(s / 60.0))
		return "%d minutes" % m
	if s < 86400:
		var h: float = float(s) / 3600.0
		return "%.1f hours" % h
	var d: float = float(s) / 86400.0
	return "%.1f days" % d


func _clamp_loaded_entities() -> void:
	for f in fish:
		if is_instance_valid(f):
			_clamp_fish_territory(f)
	for sh in shrimp:
		if is_instance_valid(sh):
			_clamp_entity_to_bounds(sh, 0.22, 0.04)
	for e in eggs:
		if is_instance_valid(e):
			_clamp_entity_to_bounds(e, 0.22, 0.06)
	for w_part in waste:
		if is_instance_valid(w_part):
			_clamp_entity_to_bounds(w_part, 0.18, 0.04)
	if snails_root != null:
		for sn in snails_root.get_children():
			if is_instance_valid(sn) and sn is Node3D:
				if sn.has_method("_reclamp_to_footprint"):
					sn.call("_reclamp_to_footprint")
				else:
					_clamp_entity_to_bounds(sn as Node3D, 0.28, 0.06, 0.10)
	# Plants / algae: skip — clamping roots on load stacked corals on the
	# rim and made outward growth read as a mass escape. Their tick pass
	# reclamps voxels via _reclamp_voxels_to_footprint().


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


func _spawn_clam_from_dict(d: Dictionary) -> Node:
	if clams_root == null:
		# Fall back to fauna_root so saved clams aren't dropped on load when
		# the world hasn't built the dedicated container yet.
		if fauna_root == null:
			return null
		clams_root = fauna_root
	var cl_script: Script = load("res://scripts/clam.gd")
	if cl_script == null:
		return null
	var cl: Node = cl_script.new()
	clams_root.add_child(cl)
	cl.global_position = SaveHelpers.array_to_vec3(d.get("pos", []), Vector3.ZERO)
	cl.sim = self
	if cl.has_method("apply_save_dict"):
		cl.apply_save_dict(d)
	clams.append(cl)
	return cl


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
	var w := _acquire_waste()
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
