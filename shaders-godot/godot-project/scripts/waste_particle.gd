# Detritus particle. Spawned by every creature in the tank: fish drop the
# largest particles, shrimp drop medium ones (lighter color because they eat
# plants), snails drop tiny pellets. All fall to the substrate, deposit their
# nutrient_value there, and persist briefly before despawning.
#
# Other creatures can claim a waste particle as food via SimDriver._claim_waste.
# When claimed, the particle is consumed (no nutrient deposit) and the eater
# gains its nutrient_value as energy/food.

extends Node3D
class_name WasteParticle

const FALL_SPEED: float = 0.6
const MAX_LIFE: float = 30.0
const KIND_FISH: int = 0
const KIND_SHRIMP: int = 1
const KIND_SNAIL: int = 2
const KIND_FOOD: int = 3

# Player-dropped food variants (only meaningful when kind == KIND_FOOD).
const FOOD_SUB_FLAKE: int = 0   # floats on surface — top feeders rush
const FOOD_SUB_PELLET: int = 1  # sinks to substrate — bottom feeders
const FOOD_SUB_WORM: int = 2    # mid-water wriggle — carnivores frenzy
const FOOD_SUB_WAFER: int = 3   # slow sink — herbivores / algae grazers

var nutrient_value: float = 0.2
var substrate_top_y: float = 1.6
var kind: int = KIND_FISH
var food_subtype: int = FOOD_SUB_PELLET
var voxel_size: float = 0.12
var settled: bool = false
var _life: float = 0.0
var _settle_timer: float = 0.0


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"nutrient_value": nutrient_value,
		"substrate_top_y": substrate_top_y,
		"kind": kind,
		"food_subtype": food_subtype,
		"settled": settled,
		"life": _life,
		"settle_timer": _settle_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	# init() builds the visual + sets kind/value; we re-call it then patch
	# the dynamic settle state.
	init(float(d.get("nutrient_value", 0.2)),
		float(d.get("substrate_top_y", 1.6)),
		int(d.get("kind", KIND_FISH)),
		int(d.get("food_subtype", FOOD_SUB_PELLET)))
	settled = not not d.get("settled", false)
	_life = float(d.get("life", 0.0))
	_settle_timer = float(d.get("settle_timer", 0.0))


func init(value: float, top_y: float, particle_kind: int = KIND_FISH,
		subtype: int = FOOD_SUB_PELLET) -> void:
	nutrient_value = value
	substrate_top_y = top_y
	kind = particle_kind
	food_subtype = subtype
	var color: Color
	match kind:
		KIND_SHRIMP:
			voxel_size = 0.08
			color = Color8(95, 80, 50)  # olive-brown, plant-fed
		KIND_SNAIL:
			voxel_size = 0.05
			color = Color8(40, 32, 22)  # tiny dark pellet
		KIND_FOOD:
			match food_subtype:
				FOOD_SUB_FLAKE:
					voxel_size = 0.09
					color = Color8(255, 228, 130)
				FOOD_SUB_WORM:
					voxel_size = 0.11
					color = Color8(175, 55, 48)
				FOOD_SUB_WAFER:
					voxel_size = 0.19
					color = Color8(88, 138, 72)
				_:
					voxel_size = 0.16
					color = Color8(210, 150, 90)  # sinking pellet
		_:
			voxel_size = 0.12
			color = Color8(60, 45, 30)  # standard fish brown
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(voxel_size, voxel_size, voxel_size))
	mi.material_override = VoxelMat.make(color)
	add_child(mi)


# Called by SimDriver each tick. Returns true if the particle should be removed.
func tick(dt: float, substrate: SubstrateGrid) -> bool:
	_life += dt
	if _life >= MAX_LIFE:
		return true
	var w: Node = get_tree().current_scene.get_node_or_null("SubViewport/World")
	if not settled:
		var floor_y: float = substrate_top_y
		if w != null and w.has_method("column_surface_y"):
			floor_y = w.column_surface_y(position.x, position.z)
		var can_fall: bool = true
		var fall_rate: float = FALL_SPEED
		if kind == KIND_FOOD:
			match food_subtype:
				FOOD_SUB_FLAKE:
					if _life < 16.0:
						can_fall = false
						position.y += sin(_life * 4.2) * 0.02 * dt
						position.x += sin(_life * 1.6 + position.z) * 0.06 * dt
						position.z += cos(_life * 1.3 + position.x) * 0.06 * dt
				FOOD_SUB_WORM:
					if _life < 12.0:
						can_fall = false
						fall_rate = FALL_SPEED * 0.25
						position.y += sin(_life * 6.0) * 0.03 * dt
						position.x += sin(_life * 3.1) * 0.09 * dt
						position.z += cos(_life * 2.4) * 0.09 * dt
				FOOD_SUB_WAFER:
					if _life < 6.0:
						can_fall = false
						position.y += sin(_life * 2.0) * 0.012 * dt
					fall_rate = FALL_SPEED * 0.32
				_:
					if _life < 3.0:
						can_fall = false
						position.y += sin(_life * 3.0) * 0.015 * dt
						position.x += sin(_life * 1.2) * 0.04 * dt
						position.z += cos(_life * 0.9) * 0.04 * dt

		if can_fall:
			position.y -= fall_rate * dt
			# Detritus drifts laterally on a synthesised flow field rather
			# than only the legacy single-axis sine. The drift is the sum
			# of three components, all space-parameterised so different
			# particles in the tank follow visibly different paths:
			#   1. A slow XZ vortex tied to position (a particle near
			#      origin spirals tighter than one at the corners).
			#   2. A noise wander seeded by _life × position so particles
			#      released at the same place still diverge over time.
			#   3. A pull toward the filter intake when one is published
			#      by SimDriver — closer particles get tugged harder.
			var swirl_t: float = _life * 1.1
			var px: float = position.x
			var pz: float = position.z
			var swirl: Vector2 = Vector2(
				sin(swirl_t + pz * 0.55) * 0.085,
				cos(swirl_t * 0.83 - px * 0.55) * 0.085)
			var wander: Vector2 = Vector2(
				sin(_life * 2.3 + px * 0.4) * 0.04,
				sin(_life * 1.9 + pz * 0.4 + 1.3) * 0.04)
			var intake_pull: Vector2 = Vector2.ZERO
			if w != null:
				var sim_n: Variant = w.get("sim")
				if sim_n != null:
					var intake_pos_v: Variant = sim_n.get("filter_intake_pos")
					if intake_pos_v != null and intake_pos_v is Vector3:
						var dx: float = (intake_pos_v as Vector3).x - position.x
						var dz: float = (intake_pos_v as Vector3).z - position.z
						var d2: float = dx * dx + dz * dz
						# Pull strength falls off with distance² and saturates
						# so a particle right next to the intake doesn't
						# teleport into it.
						var pull_k: float = 0.18 / (1.0 + d2 * 0.6)
						intake_pull = Vector2(dx, dz) * pull_k
			position.x += (swirl.x + wander.x + intake_pull.x) * dt
			position.z += (swirl.y + wander.y + intake_pull.y) * dt

		if position.y <= floor_y + voxel_size * 0.5:
			position.y = floor_y + voxel_size * 0.5
			settled = true
			var deposit: float = nutrient_value
			if substrate != null:
				var n_total: float = substrate.total_above_baseline()
				if n_total > 6.0:
					deposit *= 0.55
			substrate.add_at(position, deposit)
			# Visible mulm: tiny chance to add a permanent dark voxel at this
			# spot. The world node provides add_mulm_voxel; cheap and capped.
			if randf() < 0.17 and w != null and w.has_method("add_mulm_voxel"):
				w.add_mulm_voxel(global_position)
	else:
		_settle_timer += dt
		if _settle_timer > 4.0:
			return true
	if w != null and w.has_method("clamp_xyz_in_tank"):
		global_position = w.clamp_xyz_in_tank(global_position, 0.18, voxel_size * 0.5)
	return false
