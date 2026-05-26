# A fish egg. Sits where it was laid (plants or substrate), incubates for
# some seconds, then hatches into a fry that inherits the parents' genome.
#
# Visible as a small pale cluster of voxels. Adds slight wobble during the
# last 20% of incubation as the fry inside develops.

extends Node3D
class_name FishEgg

const VOXEL_SIZE: float = 0.10
const INCUBATION_S: float = 30.0  # seconds to hatch (sim time)

var genome: Dictionary = {}
var species: String = "glassdart"
var _age: float = 0.0
var _wobble_pivot: Node3D = null
# Egg tint derived from the parents' base_color. Lightened + desaturated so
# eggs look translucent with a species-specific hue: glassdart → pinkish,
# mudsifter → peachy, angelfish → ivory. Falls back to a generic pale-orange
# when the genome carries no base_color.
var _egg_tint: Color = Color8(240, 215, 160)
var _egg_tint_alt: Color = Color8(220, 190, 130)


func init(genome_dict: Dictionary) -> void:
	genome = genome_dict
	species = genome.get("species", species)
	# Derive egg tint from the parents' base_color: lighten by 40% and
	# desaturate toward a warm translucent look so the species identity
	# shows through. E.g. scarlet glassdart → pink-ish eggs.
	var parent_color = genome.get("base_color", null)
	if parent_color != null and parent_color is Color:
		var c: Color = parent_color as Color
		var light: Color = c.lightened(0.45)
		_egg_tint = light.lerp(Color8(240, 215, 160), 0.35)
		_egg_tint_alt = light.lerp(Color8(220, 190, 130), 0.40)
	_build_visual()


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	# Genome may contain Color values — convert to arrays for JSON.
	var g: Dictionary = genome.duplicate(true)
	for key in ["base_color", "accent_color", "tail_color"]:
		if g.has(key) and g[key] is Color:
			g[key] = SaveHelpers.color_to_array(g[key])
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"species": species,
		"genome": g,
		"age": _age,
	}


func apply_save_dict(d: Dictionary) -> void:
	species = String(d.get("species", species))
	var g: Dictionary = d.get("genome", {})
	for key in ["base_color", "accent_color", "tail_color"]:
		if g.has(key) and g[key] is Array:
			g[key] = SaveHelpers.array_to_color(g[key])
	init(g)
	_age = float(d.get("age", 0.0))


func _build_visual() -> void:
	# A cluster of 3-5 tiny eggs, tinted per species.
	_wobble_pivot = Node3D.new()
	add_child(_wobble_pivot)
	var positions: Array[Vector3] = [
		Vector3(0, 0, 0),
		Vector3(VOXEL_SIZE * 0.9, VOXEL_SIZE * 0.1, 0),
		Vector3(-VOXEL_SIZE * 0.8, VOXEL_SIZE * 0.05, VOXEL_SIZE * 0.4),
		Vector3(VOXEL_SIZE * 0.3, VOXEL_SIZE * 0.8, -VOXEL_SIZE * 0.4),
	]
	for i in positions.size():
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE))
		mi.position = positions[i]
		mi.material_override = VoxelMat.make(_egg_tint if (i & 1) == 0 else _egg_tint_alt)
		_wobble_pivot.add_child(mi)


# Called by SimDriver each tick. Returns true when the egg should hatch.
func tick(dt: float) -> bool:
	_age += dt
	# Wobble in the last few seconds before hatching.
	if _wobble_pivot != null and _age > INCUBATION_S * 0.7:
		var wobble_t := (_age - INCUBATION_S * 0.7) / (INCUBATION_S * 0.3)
		_wobble_pivot.rotation.z = sin(_age * 8.0) * 0.1 * wobble_t
	return _age >= INCUBATION_S


func is_ready_to_hatch() -> bool:
	return _age >= INCUBATION_S
