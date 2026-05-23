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

var nutrient_value: float = 0.2
var substrate_top_y: float = 1.6
var kind: int = KIND_FISH
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
		"settled": settled,
		"life": _life,
		"settle_timer": _settle_timer,
	}


func apply_save_dict(d: Dictionary) -> void:
	# init() builds the visual + sets kind/value; we re-call it then patch
	# the dynamic settle state.
	init(float(d.get("nutrient_value", 0.2)),
		float(d.get("substrate_top_y", 1.6)),
		int(d.get("kind", KIND_FISH)))
	settled = bool(d.get("settled", false))
	_life = float(d.get("life", 0.0))
	_settle_timer = float(d.get("settle_timer", 0.0))


func init(value: float, top_y: float, particle_kind: int = KIND_FISH) -> void:
	nutrient_value = value
	substrate_top_y = top_y
	kind = particle_kind
	var color: Color
	match kind:
		KIND_SHRIMP:
			voxel_size = 0.08
			color = Color8(95, 80, 50)  # olive-brown, plant-fed
		KIND_SNAIL:
			voxel_size = 0.05
			color = Color8(40, 32, 22)  # tiny dark pellet
		KIND_FOOD:
			voxel_size = 0.16
			color = Color8(210, 150, 90)  # fish food pellet
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
	if not settled:
		var can_fall: bool = true
		if kind == KIND_FOOD and _life < 8.0:
			can_fall = false
			# Bob gently on the surface
			position.y += sin(_life * 3.0) * 0.015 * dt
			position.x += sin(_life * 1.2) * 0.04 * dt
			position.z += cos(_life * 0.9) * 0.04 * dt
			
		if can_fall:
			position.y -= FALL_SPEED * dt
			position.x += sin(_life * 1.7) * 0.04 * dt
			
		if position.y <= substrate_top_y + voxel_size * 0.5:
			position.y = substrate_top_y + voxel_size * 0.5
			settled = true
			substrate.add_at(position, nutrient_value)
			# Visible mulm: tiny chance to add a permanent dark voxel at this
			# spot. The world node provides add_mulm_voxel; cheap and capped.
			if randf() < 0.10:
				var w := get_tree().current_scene.get_node_or_null("SubViewport/World")
				if w != null and w.has_method("add_mulm_voxel"):
					w.add_mulm_voxel(global_position)
	else:
		_settle_timer += dt
		if _settle_timer > 4.0:
			return true
	return false
