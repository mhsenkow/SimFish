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
# Cached per-egg-cell materials so the hatch pulse-glow can lift their
# albedo each tick. The base color is what _build_visual originally set;
# we lerp between base and a near-white "embryo light" tint as hatch
# approaches. Cleared in _build_visual + repopulated as it builds.
var _egg_materials: Array[ShaderMaterial] = []
var _egg_base_colors: Array[Color] = []
# Egg tint derived from the parents' base_color. Lightened + desaturated so
# eggs look translucent with a species-specific hue: glassdart → pinkish,
# mudsifter → peachy, angelfish → ivory. Falls back to a generic pale-orange
# when the genome carries no base_color.
var _egg_tint: Color = Color8(240, 215, 160)
var _egg_tint_alt: Color = Color8(220, 190, 130)
var viable: bool = true


func init(genome_dict: Dictionary) -> void:
	genome = genome_dict
	species = genome.get("species", species)
	viable = not not genome.get("viable", true)
	# Derive egg tint from the parents' base_color: lighten by 40% and
	# desaturate toward a warm translucent look so the species identity
	# shows through. E.g. scarlet glassdart → pink-ish eggs.
	var parent_color = genome.get("base_color", null)
	if parent_color != null and parent_color is Color:
		var c: Color = parent_color as Color
		var light: Color = c.lightened(0.45)
		_egg_tint = light.lerp(Color8(240, 215, 160), 0.35)
		_egg_tint_alt = light.lerp(Color8(220, 190, 130), 0.40)
	
	if not viable:
		_egg_tint = _egg_tint.lerp(Color(0.85, 0.85, 0.85), 0.5)
		_egg_tint.a = 0.45
		_egg_tint_alt = _egg_tint_alt.lerp(Color(0.80, 0.80, 0.80), 0.5)
		_egg_tint_alt.a = 0.45
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
	_egg_materials.clear()
	_egg_base_colors.clear()
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
		var base_col: Color = _egg_tint if (i & 1) == 0 else _egg_tint_alt
		# Duplicate the shared cached material so the pulse-glow path can
		# write per-egg albedo each tick without bleeding into other eggs
		# of the same species.
		var mat: ShaderMaterial = VoxelMat.make_fauna(base_col).duplicate()
		mi.material_override = mat
		_egg_materials.append(mat)
		_egg_base_colors.append(mat.get_shader_parameter("albedo"))
		_wobble_pivot.add_child(mi)


# Called by SimDriver each tick. Returns true when the egg should hatch.
func tick(dt: float) -> bool:
	_age += dt
	# Wobble in the last few seconds before hatching.
	if _wobble_pivot != null and _age > INCUBATION_S * 0.7:
		var wobble_t := (_age - INCUBATION_S * 0.7) / (INCUBATION_S * 0.3)
		_wobble_pivot.rotation.z = sin(_age * 8.0) * 0.1 * wobble_t
	# Hatch pulse-glow. Egg albedo lifts toward an embryo-light cream as
	# incubation completes; pulse frequency also climbs so a near-hatch
	# egg visibly flickers. Only viable eggs glow — dead eggs stay dull
	# so the player reads "this clutch isn't going to develop."
	if viable and _egg_materials.size() > 0:
		var hatch_t: float = clampf(_age / INCUBATION_S, 0.0, 1.0)
		# Glow eases in over the second half so early incubation looks
		# inert and the last 15s reads as "actively quickening." Quartic
		# ramp emphasises the final stretch.
		var glow_ramp: float = pow(clampf((hatch_t - 0.45) / 0.55, 0.0, 1.0), 1.6)
		# Pulse frequency rises with hatch progress — slow heartbeat at
		# mid-incubation, faster flutter at hatch. Plus a small phase per
		# egg-cell index so the cluster reads as multiple things glowing
		# slightly out of step.
		var pulse_freq: float = lerpf(1.6, 5.2, hatch_t)
		var glow_strength: float = glow_ramp * 0.45
		for i in _egg_materials.size():
			var mat: ShaderMaterial = _egg_materials[i]
			if mat == null:
				continue
			var phase: float = float(i) * 0.9
			var pulse: float = 0.5 + 0.5 * sin(_age * pulse_freq + phase)
			var lift: float = glow_strength * (0.55 + 0.45 * pulse)
			# Lerp toward an embryo-cream — keeps the species hue intact
			# but the pixel reads as emissive against the dither.
			var base_c: Color = _egg_base_colors[i]
			var target: Color = base_c.lightened(0.55)
			mat.set_shader_parameter("albedo", base_c.lerp(target, lift))
	return _age >= INCUBATION_S


func is_ready_to_hatch() -> bool:
	return _age >= INCUBATION_S


func dissolve() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# Shrink the eggs.
	tween.tween_property(self, "scale", Vector3.ZERO, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# Fade out each mesh's material override.
	for child in _wobble_pivot.get_children():
		if child is MeshInstance3D:
			var mat: Material = child.material_override
			if mat is ShaderMaterial:
				# Duplicate so we don't fade the cached material
				var d_mat: ShaderMaterial = mat.duplicate()
				child.material_override = d_mat
				var orig_color: Color = d_mat.get_shader_parameter("albedo")
				var target_color := Color(orig_color.r, orig_color.g, orig_color.b, 0.0)
				tween.tween_property(d_mat, "shader_parameter/albedo", target_color, 3.0)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
