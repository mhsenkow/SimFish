# A shrimp. Walks on substrate, climbs plants to nibble their tips, hunts
# detritus and the occasional tiny prey (baby snail / fry).
#
# Movement model is simpler than the fish: shrimp use a directional velocity
# but they're "weighted" - they sink to the substrate when not actively climbing.
# A shrimp targeting a plant gets a strong upward velocity component; once it
# stops climbing, mild gravity pulls it back down.
#
# Food web role:
#   - Detritivore: claims waste particles as food
#   - Herbivore: nibbles tips of tall plants
#   - Opportunistic predator: occasionally catches fry / baby snails
#   - Excretes shrimp-grade waste particles (lighter, smaller than fish)
#
# Life cycle: berried adult → fry (small, vulnerable) → juvenile → adult →
# senescent → dies. Fry can be eaten by fish or other adult shrimp.

extends Node3D
class_name Shrimp

const MATURITY_FRY := 0
const MATURITY_JUVENILE := 1
const MATURITY_ADULT := 2
const MATURITY_SENESCENT := 3

enum Mode { WANDER, FORAGE_WASTE, CLIMB, NIBBLE, HUNT, COURT, REST }

# ---- Genome (set at spawn) ----
var species: String = "shrimp"
var base_color: Color = Color8(180, 90, 70)         # neocaridina red default
var accent_color: Color = Color8(245, 220, 200)     # belly cream
var adult_voxel_scale: float = 0.10                 # smaller than fish
var max_age_s: float = 360.0                        # ~6 minutes lifespan
var max_speed: float = 0.85
var max_turn_rate: float = 4.0                      # nimble
var sex: int = 0

# ---- Lineage ----
var generation: int = 0

# ---- State ----
var age: float = 0.0
var hunger: float = 0.3
var energy: float = 1.0
var maturity: int = MATURITY_FRY
var velocity: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD
var speed: float = 0.0
var current_mode: Mode = Mode.WANDER
var breed_cooldown: float = 0.0

# Climbing target. When non-null, shrimp moves toward this plant and ascends.
var climb_target: Plant = null
var climb_remaining_time: float = 0.0  # countdown before giving up
const CLIMB_GIVE_UP_TIME: float = 18.0  # if can't reach, give up

# Courtship + gravidity (berried-female mechanic).
var partner: Shrimp = null
var court_timer: float = 0.0
const COURT_DURATION: float = 4.0
const GRAVIDITY_DURATION: float = 25.0
var clutch_size: int = 3
# is_gravid: true on females after a completed courtship - they carry the
# egg cluster visibly under their tail for GRAVIDITY_DURATION seconds before
# releasing fry. Real cherry shrimp call this "berried".
var is_gravid: bool = false
var gravid_timer: float = 0.0
var gravid_partner_genome: Dictionary = {}  # cached mate genome at fertilization
var _egg_cluster: Node3D = null
# Tracks how many successful broods this individual has had. Used for
# breeding-partner bias - successful breeders are more attractive (cheap
# stand-in for true sexual selection).
var breed_count: int = 0

# Internal substrate-top reference set by SimDriver via init.
var substrate_top_y: float = 1.6

# Shrimp size growth from feeding. Same mechanic as Fish.growth_factor:
# well-fed adults grow above baseline; chronically hungry shrink. Used for
# cannibalism size comparison.
var growth_factor: float = 1.0
const MAX_GROWTH: float = 1.5
const SHRIMP_POPULATION_CAP: int = 28


func effective_size() -> float:
	return adult_voxel_scale * _maturity_scale() * growth_factor

# Animation
var _swim_phase: float = 0.0
var _tail_pivot: Node3D = null
var _antenna_pivot: Node3D = null
var _bank_pivot: Node3D = null
var _last_yaw: float = 0.0
var _bank: float = 0.0

# Refs
var sim: Node = null


# ---- Setup ----

func init_genome(genome: Dictionary) -> void:
	species = genome.get("species", species)
	base_color = genome.get("base_color", base_color)
	accent_color = genome.get("accent_color", accent_color)
	adult_voxel_scale = genome.get("adult_voxel_scale", adult_voxel_scale)
	max_age_s = genome.get("max_age_s", max_age_s)
	max_speed = genome.get("max_speed", max_speed)
	sex = genome.get("sex", randi() % 2)
	substrate_top_y = genome.get("substrate_top_y", substrate_top_y)
	scale = Vector3.ONE * _maturity_scale()
	_build_body()
	# Start each shrimp facing a random horizontal direction.
	var theta: float = randf() * TAU
	heading = Vector3(sin(theta), 0.0, -cos(theta))
	_last_yaw = atan2(heading.x, -heading.z)
	# Start with random hunger so they don't all forage at once.
	hunger = randf_range(0.2, 0.5)
	# Make sure babies start at substrate level.
	position.y = substrate_top_y + 0.1


func _maturity_scale() -> float:
	match maturity:
		MATURITY_FRY:        return 0.40
		MATURITY_JUVENILE:   return 0.70
		MATURITY_ADULT:      return 1.0
		MATURITY_SENESCENT:  return 0.95
		_: return 1.0


func _build_body() -> void:
	# Voxel shrimp facing -Z. Components:
	#   - Carapace (front body): 2 stacked voxels with eyes on sides
	#   - Mid segment: thickest
	#   - Tail segments: 2 voxels arching upward (the classic shrimp curl)
	#   - Antennae: thin voxels projecting forward (animated to twitch)
	#   - Legs (visual only): tiny voxels under the body
	var v: float = adult_voxel_scale
	var mat_body := VoxelMat.make(base_color)
	var mat_belly := VoxelMat.make(accent_color)
	var mat_eye := VoxelMat.make(Color8(11, 11, 14))
	var mat_dark := VoxelMat.make(base_color.darkened(0.3))
	var mat_antenna := VoxelMat.make(base_color.darkened(0.15))

	_bank_pivot = Node3D.new()
	_bank_pivot.name = "BankPivot"
	add_child(_bank_pivot)

	# Carapace - front segment.
	_voxel(_bank_pivot, Vector3(0, v * 0.3, -v * 0.8), Vector3(v * 0.9, v * 0.9, v * 0.9), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.3, -v * 0.8), Vector3(v * 0.7, v * 0.3, v * 0.7), mat_belly)
	# Eyes (small dark dots on the sides of the carapace).
	_voxel(_bank_pivot, Vector3(v * 0.4, v * 0.3, -v * 1.1), Vector3(v * 0.18, v * 0.18, v * 0.18), mat_eye)
	_voxel(_bank_pivot, Vector3(-v * 0.4, v * 0.3, -v * 1.1), Vector3(v * 0.18, v * 0.18, v * 0.18), mat_eye)

	# Antennae - thin voxels jutting forward. We'll animate the pivot.
	_antenna_pivot = Node3D.new()
	_antenna_pivot.name = "Antennae"
	_antenna_pivot.position = Vector3(0, v * 0.3, -v * 1.2)
	_bank_pivot.add_child(_antenna_pivot)
	_voxel(_antenna_pivot, Vector3(v * 0.2, v * 0.1, -v * 0.4), Vector3(v * 0.06, v * 0.06, v * 0.9), mat_antenna)
	_voxel(_antenna_pivot, Vector3(-v * 0.2, v * 0.1, -v * 0.4), Vector3(v * 0.06, v * 0.06, v * 0.9), mat_antenna)

	# Mid segment (thickest part of carapace).
	_voxel(_bank_pivot, Vector3(0, v * 0.3, 0), Vector3(v * 1.1, v * 1.0, v * 0.9), mat_body)
	_voxel(_bank_pivot, Vector3(0, -v * 0.4, 0), Vector3(v * 0.9, v * 0.25, v * 0.7), mat_belly)

	# Tail segments (curl upward and back).
	_tail_pivot = Node3D.new()
	_tail_pivot.name = "TailPivot"
	_tail_pivot.position = Vector3(0, v * 0.4, v * 0.6)
	_bank_pivot.add_child(_tail_pivot)
	_voxel(_tail_pivot, Vector3(0, 0, 0), Vector3(v * 0.8, v * 0.7, v * 0.6), mat_body)
	_voxel(_tail_pivot, Vector3(0, v * 0.3, v * 0.5), Vector3(v * 0.6, v * 0.5, v * 0.5), mat_body)
	# Tail fan (flat).
	_voxel(_tail_pivot, Vector3(0, v * 0.5, v * 1.0), Vector3(v * 0.7, v * 0.2, v * 0.3), mat_dark)

	# Legs (small dark voxels under the body - visual interest only).
	for i in 3:
		var xside: float = 0.5 - randf() * 0.3
		var zoff: float = -0.4 + i * 0.4
		_voxel(_bank_pivot, Vector3(xside * v, -v * 0.4, zoff * v),
			   Vector3(v * 0.1, v * 0.3, v * 0.1), mat_dark)
		_voxel(_bank_pivot, Vector3(-xside * v, -v * 0.4, zoff * v),
			   Vector3(v * 0.1, v * 0.3, v * 0.1), mat_dark)


func _voxel(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


# ---- Brain (10 Hz tick) ----

func tick(dt: float, plants: Array, waste: Array, fry_array: Array, baby_snails: Array,
		  neighbors: Array, world_bounds: AABB) -> Dictionary:
	var events: Dictionary = {}

	age += dt
	hunger = clampf(hunger + dt * 0.011, 0.0, 1.0)
	energy = clampf(energy - dt * 0.004, 0.0, 1.0)
	breed_cooldown = maxf(0.0, breed_cooldown - dt)

	# Gravidity: if carrying eggs, count down and release fry when ready.
	if is_gravid:
		gravid_timer += dt
		if gravid_timer >= GRAVIDITY_DURATION:
			events["release_fry"] = gravid_partner_genome
			is_gravid = false
			gravid_timer = 0.0
			gravid_partner_genome = {}

	_update_maturity()

	# Death conditions.
	if maturity == MATURITY_SENESCENT and age >= max_age_s * 1.1:
		events["die"] = true
		return events
	if hunger >= 1.0 and energy < 0.1:
		events["die"] = true
		return events

	var target_velocity := Vector3.ZERO
	current_mode = Mode.WANDER

	# Tier 1: wall avoidance always adds.
	target_velocity += _wall_avoid(world_bounds) * 1.5

	# Tier 2: already paired - keep courting.
	if partner != null:
		if not is_instance_valid(partner) or partner.maturity != MATURITY_ADULT:
			partner = null
			court_timer = 0.0
		else:
			current_mode = Mode.COURT
			var to_p: Vector3 = partner.position - position
			var dist: float = to_p.length()
			# Walk alongside on substrate.
			var side := to_p.cross(Vector3.UP).normalized() * 0.25
			var ct: Vector3 = partner.position + side
			target_velocity += (ct - position).normalized() * max_speed * 0.7
			court_timer += dt
			if dist < 0.8 and court_timer >= COURT_DURATION:
				# Pick the female of the pair to become gravid. We compute
				# the offspring genome NOW (combining both parents) and stash
				# it on the female to release as fry once gravidity completes.
				var female: Shrimp = self if sex == 1 else partner
				var male: Shrimp = partner if sex == 1 else self
				female.is_gravid = true
				female.gravid_timer = 0.0
				female.gravid_partner_genome = female.produce_offspring_genome(male)
				breed_cooldown = 60.0
				energy = maxf(0.0, energy - 0.30)
				partner.breed_cooldown = 60.0
				partner.energy = maxf(0.0, partner.energy - 0.30)
				breed_count += 1
				partner.breed_count += 1
				partner.partner = null
				partner = null
				court_timer = 0.0
			_apply_target(target_velocity)
			return events

	# Tier 2.5: CANNIBALISM. Only kicks in when the population is crowded
	# (>=22 shrimp). Below that, adults spare the fry so the colony can
	# build up. Above the threshold, hungry adults will eat young to keep
	# numbers in check - real cherry-shrimp self-thin this way.
	var shrimp_pop: int = sim.shrimp.size() if sim != null else 0
	if maturity == MATURITY_ADULT and hunger > 0.5 and shrimp_pop >= 22 \
			and randf() < 0.08 and sim != null:
		var my_size: float = effective_size()
		var fry_prey: Shrimp = null
		var best_d2: float = 1.0
		for s in sim.shrimp:
			if not is_instance_valid(s) or s == self:
				continue
			if s.maturity != MATURITY_FRY:
				continue
			# Cannibalism more likely when crowded.
			var d2: float = s.position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				fry_prey = s
		if fry_prey != null:
			current_mode = Mode.HUNT
			var to_p: Vector3 = fry_prey.position - position
			if to_p.length() < 0.3:
				events["kill_prey"] = fry_prey
				hunger = maxf(0.0, hunger - 0.35)
				energy = minf(1.0, energy + 0.12)
				events["waste_at"] = position + Vector3(0, -0.05, 0)
				events["waste_amount"] = 0.10
			else:
				target_velocity += to_p.normalized() * max_speed * 1.2
				_apply_target(target_velocity)
				return events

	# Tier 3: rare predation on baby SNAILS only. Real shrimp don't usually
	# catch fish fry - they're too slow - so we leave fish-fry hunting out
	# of shrimp's repertoire entirely. Otherwise shrimp eat fish fry faster
	# than fish can recruit and the school crashes.
	if maturity == MATURITY_ADULT and hunger > 0.7 and randf() < 0.02:
		var prey_pos: Vector3 = Vector3.INF
		var prey_ref: Node3D = null
		var best_d2: float = 1.2 * 1.2
		for s in baby_snails:
			if not is_instance_valid(s):
				continue
			var d2: float = (s as Node3D).global_position.distance_squared_to(position)
			if d2 < best_d2:
				best_d2 = d2
				prey_pos = (s as Node3D).global_position
				prey_ref = s
		if prey_ref != null:
			current_mode = Mode.HUNT
			var to_prey: Vector3 = prey_pos - position
			if to_prey.length() < 0.4:
				events["kill_prey"] = prey_ref
				hunger = maxf(0.0, hunger - 0.45)
				energy = minf(1.0, energy + 0.15)
				events["waste_at"] = position + Vector3(0, -0.05, 0)
				events["waste_amount"] = 0.12
			else:
				target_velocity += to_prey.normalized() * max_speed * 1.3
				_apply_target(target_velocity)
				return events

	# Tier 4: seek breeding partner. Shrimp are happy to breed even when
	# moderately hungry as long as they have energy reserves AND the global
	# population is below cap.
	var current_pop: int = sim.shrimp.size() if sim != null else 0
	if maturity == MATURITY_ADULT and breed_cooldown <= 0.0 and partner == null \
			and hunger < 0.6 and energy > 0.5 and current_pop < SHRIMP_POPULATION_CAP:
		for n in neighbors:
			if not (n is Shrimp):
				continue
			var s: Shrimp = n
			if s == self or s.species != species:
				continue
			if s.sex == sex or s.maturity != MATURITY_ADULT \
					or s.breed_cooldown > 0.0 or s.partner != null:
				continue
			if s.hunger > 0.6 or s.energy < 0.45:
				continue
			partner = s
			s.partner = self
			court_timer = 0.0
			s.court_timer = 0.0
			break

	# Tier 5: claim nearby waste. The actual eat is resolved by SimDriver.
	var best_w: WasteParticle = null
	var best_w_d2: float = 4.0
	for w in waste:
		if not is_instance_valid(w):
			continue
		var d2: float = (w as Node3D).global_position.distance_squared_to(position)
		if d2 < best_w_d2:
			best_w_d2 = d2
			best_w = w
	if best_w != null:
		current_mode = Mode.FORAGE_WASTE
		var to_w: Vector3 = best_w.global_position - position
		if to_w.length() < 0.3:
			events["eat_waste"] = best_w
			hunger = maxf(0.0, hunger - 0.30)
		else:
			target_velocity += to_w.normalized() * max_speed * 0.9
			_apply_target(target_velocity)
			return events

	# Tier 6: PLANTS - shrimp are primary consumers and aggressive grazers.
	# They eat plant tips (climbing) AND graze low foliage they pass on the
	# substrate. Drop the rare-probability gate; instead the climb-vs-graze
	# choice is based on which plant is closest.
	if hunger > 0.3:
		# First: a quick grazing pass for plants right next to us on the floor.
		# Cheaper than climbing - shrimp munch any short plant they pass over.
		for p in plants:
			if not is_instance_valid(p) or p.biomass() <= 0:
				continue
			var pp: Vector3 = p.global_position
			if absf(pp.y - position.y) > 0.6: continue   # only floor-level plants
			var d2: float = pp.distance_squared_to(position)
			if d2 < 0.35 * 0.35:
				var taken: int = p.nibble(1)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.22 * float(taken))
					energy = minf(1.0, energy + 0.04)
					events["waste_at"] = position + Vector3(0, -0.05, 0)
					events["waste_amount"] = 0.10 * float(taken)
					_apply_target(target_velocity)
					return events

		# Then: pick a tall plant to climb if we have no current target.
		if climb_target == null:
			var best_p: Plant = null
			var best_p_d2: float = 12.0
			for p in plants:
				if not is_instance_valid(p) or p.biomass() < 6:
					continue
				var d2: float = p.global_position.distance_squared_to(position)
				if d2 < best_p_d2:
					best_p_d2 = d2
					best_p = p
			if best_p != null:
				climb_target = best_p
				climb_remaining_time = CLIMB_GIVE_UP_TIME

	if climb_target != null:
		if not is_instance_valid(climb_target) or climb_target.biomass() <= 0:
			climb_target = null
		else:
			climb_remaining_time -= dt
			current_mode = Mode.CLIMB
			var top: Vector3 = climb_target.global_position
			top.y = climb_target.top_world_y()
			var to_top: Vector3 = top - position
			if to_top.length() < 0.45:
				current_mode = Mode.NIBBLE
				# Eat 2 voxels per visit - more visible chomp.
				var taken: int = climb_target.nibble(2)
				if taken > 0:
					hunger = maxf(0.0, hunger - 0.22 * float(taken))
					energy = minf(1.0, energy + 0.05)
					events["waste_at"] = position + Vector3(0, -0.05, 0)
					events["waste_amount"] = 0.10 * float(taken)
				climb_target = null
			else:
				target_velocity += to_top.normalized() * max_speed * 1.0
			if climb_remaining_time <= 0.0:
				climb_target = null

	# Default: wander on substrate.
	if current_mode == Mode.WANDER:
		# Cheap wander: drift along heading with mild randomness.
		var wander_dir: Vector3 = heading + Vector3(
			randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)
		)
		wander_dir.y = 0.0
		target_velocity += wander_dir.normalized() * max_speed * 0.4

	# Night-time dampening - shrimp also slow at night.
	if sim != null:
		var dl: float = float(sim.daylight())
		var night_factor: float = 0.35 + 0.65 * dl
		target_velocity *= night_factor

	# Size growth from feeding (mirrors Fish.growth_factor logic).
	if maturity == MATURITY_ADULT:
		if hunger < 0.35:
			growth_factor = minf(growth_factor + 0.0007 * dt, MAX_GROWTH)
		elif hunger > 0.7:
			growth_factor = maxf(growth_factor - 0.0004 * dt, 0.7)

	_apply_target(target_velocity)
	return events


func _apply_target(t: Vector3) -> void:
	# Cache for physics step in _process.
	_target_velocity = t


var _target_velocity: Vector3 = Vector3.ZERO


# ---- Physics + animation (render rate) ----

func _process(dt: float) -> void:
	if sim != null:
		dt *= sim.time_scale
		if dt <= 0.0:
			return
	# Gravity-like pull when not climbing. Shrimp tend to stick to surfaces.
	if climb_target == null:
		_target_velocity.y -= 1.2 * dt

	# Decompose into heading + speed.
	var target_dir: Vector3 = heading
	var target_spd: float = 0.0
	if _target_velocity.length_squared() > 1e-4:
		target_spd = _target_velocity.length()
		target_dir = _target_velocity.normalized()

	# Bounded turn (shrimp are nimble - higher turn rate than fish).
	var angle: float = heading.angle_to(target_dir)
	if angle > 0.0005:
		var axis: Vector3 = heading.cross(target_dir)
		if axis.length_squared() < 1e-6:
			axis = Vector3.UP
		axis = axis.normalized()
		var turn: float = minf(max_turn_rate * dt, angle)
		heading = heading.rotated(axis, turn).normalized()

	# Linear accel toward target speed.
	speed = move_toward(speed, target_spd, 3.0 * dt)

	velocity = heading * speed
	position += velocity * dt

	# Clamp to substrate. Shrimp can climb up but never sink below substrate top.
	position.y = maxf(position.y, substrate_top_y + 0.05)

	# Face heading (look_at with body built facing -Z).
	if heading.length_squared() > 1e-4:
		var d: Vector3 = heading
		if absf(d.dot(Vector3.UP)) > 0.95:
			d = (d + Vector3(0.0001, 0, 0)).normalized()
		look_at(position + d, Vector3.UP)

	# Banking on yaw rate (shrimp lean into turns less than fish).
	var current_yaw: float = atan2(heading.x, -heading.z)
	var yaw_diff: float = wrapf(current_yaw - _last_yaw, -PI, PI)
	_last_yaw = current_yaw
	var yaw_rate: float = yaw_diff / maxf(dt, 0.0001)
	var bank_target: float = clampf(-yaw_rate * 0.2, -0.4, 0.4)
	_bank = lerpf(_bank, bank_target, clampf(dt * 5.0, 0.0, 1.0))
	if _bank_pivot != null:
		_bank_pivot.rotation.z = _bank

	# Animation: tail flicks + antennae twitch.
	_swim_phase += dt * (3.0 + speed * 4.0)
	if _tail_pivot != null:
		_tail_pivot.rotation.x = sin(_swim_phase) * 0.15
	if _antenna_pivot != null:
		_antenna_pivot.rotation.y = sin(_swim_phase * 1.7) * 0.20
		_antenna_pivot.rotation.x = sin(_swim_phase * 2.1) * 0.10

	# Maturity scale lerps AND growth_factor so well-fed shrimp visibly bulk.
	scale = scale.lerp(Vector3.ONE * _maturity_scale() * growth_factor, dt * 0.5)

	# Berried-female visual: small yellow egg cluster under the tail.
	if is_gravid and _egg_cluster == null:
		_spawn_egg_cluster()
	elif not is_gravid and _egg_cluster != null:
		_egg_cluster.queue_free()
		_egg_cluster = null


func _spawn_egg_cluster() -> void:
	if _bank_pivot == null:
		return
	_egg_cluster = Node3D.new()
	_egg_cluster.name = "EggCluster"
	# Position under the tail (which sits at z = 0.6v ish in tail_pivot).
	_egg_cluster.position = Vector3(0, -adult_voxel_scale * 0.45, adult_voxel_scale * 0.4)
	_bank_pivot.add_child(_egg_cluster)
	var v: float = adult_voxel_scale
	var c_egg := Color8(245, 220, 110)
	var c_egg_dark := Color8(220, 190, 80)
	var positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(v * 0.18, 0, 0),
		Vector3(-v * 0.18, 0, 0),
		Vector3(0, 0, v * 0.18),
		Vector3(v * 0.10, v * 0.05, v * 0.10),
	]
	for i in positions.size():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(v * 0.16, v * 0.16, v * 0.16)
		mi.mesh = bm
		mi.position = positions[i]
		mi.material_override = VoxelMat.make(c_egg if (i & 1) == 0 else c_egg_dark)
		_egg_cluster.add_child(mi)


func _update_maturity() -> void:
	var t: float = age / max_age_s
	if t < 0.1:
		maturity = MATURITY_FRY
	elif t < 0.3:
		maturity = MATURITY_JUVENILE
	elif t < 0.85:
		maturity = MATURITY_ADULT
	else:
		maturity = MATURITY_SENESCENT


func _wall_avoid(b: AABB) -> Vector3:
	var margin := 0.8
	var v := Vector3.ZERO
	if position.x < b.position.x + margin:
		v.x += 1.0
	if position.x > b.position.x + b.size.x - margin:
		v.x -= 1.0
	if position.z < b.position.z + margin:
		v.z += 1.0
	if position.z > b.position.z + b.size.z - margin:
		v.z -= 1.0
	return v


func produce_offspring_genome(other: Shrimp) -> Dictionary:
	# Strong color + size drift so cherry-red colonies slowly diverge into
	# amber, olive, blue, etc. over many generations.
	var mix := 0.5
	var color_muta := 0.2
	var size_muta := 0.08
	var new_size: float = (adult_voxel_scale + other.adult_voxel_scale) * 0.5 \
		+ randf_range(-size_muta, size_muta) * adult_voxel_scale
	new_size = clampf(new_size, adult_voxel_scale * 0.65, adult_voxel_scale * 1.5)
	return {
		"species": species,
		"base_color": base_color.lerp(other.base_color, mix).lerp(
			Color(randf(), randf(), randf()), color_muta),
		"accent_color": accent_color.lerp(other.accent_color, mix).lerp(
			Color(randf(), randf(), randf()), color_muta * 0.5),
		"adult_voxel_scale": new_size,
		"max_age_s": (max_age_s + other.max_age_s) * 0.5 + randf_range(-30.0, 30.0),
		"max_speed": (max_speed + other.max_speed) * 0.5 + randf_range(-0.08, 0.08),
		"sex": randi() % 2,
		"substrate_top_y": substrate_top_y,
		"generation": maxi(generation, other.generation) + 1,
	}
