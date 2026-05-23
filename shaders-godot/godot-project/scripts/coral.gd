# Coral. A photosynthetic sessile organism that grows like a plant but
# in coral-specific shapes. Inherits Plant for free decay / grazing /
# growth-tick / substrate-consumption + voxel tracking; overrides only
# the body-building part of _grow_one().
#
# Four shape templates, selected at spawn via `coral_form`:
#
#   "dome"        Brain / boulder coral. A hemisphere of polyp voxels
#                 stacked in golden-angle phyllotaxis. The classic
#                 "round lump on the reef" silhouette.
#
#   "branching"   Staghorn / Acropora. A vertical stem that spawns
#                 short angled side-branches every few voxels. Pale
#                 zooxanthellae tips appear on the youngest segments.
#
#   "feathery"    Soft / sea-fan coral. Tall vertical stalk with thin
#                 lateral feather voxels at every node. Sways more
#                 strongly than the stiff stony corals.
#
#   "plate"       Table coral. A short stem capped by a wide flat disc
#                 of polyp voxels arranged in a phyllotaxis pattern.
#
# Corals don't extend roots (they cement directly to substrate), don't
# emit Vallisneria-style runners, and never flower; the plant tick's
# growth/decay/grazing/pearling paths still apply.

extends Plant
class_name Coral

const GOLDEN_ANGLE: float = 2.39996322972865332

@export var coral_form: String = "dome"
# Bright tip color for staghorn-style corals (zooxanthellae glow on the
# newest polyps). Defaults to pale cream; species presets override per
# coral type.
@export var tip_color: Color = Color8(255, 245, 215)


func _build_initial_roots() -> void:
	# No-op: corals cement to the substrate, they don't extend roots.
	pass


func _save_kind() -> String:
	return "coral"


func to_save_dict() -> Dictionary:
	var d: Dictionary = super.to_save_dict()
	d["coral_form"] = coral_form
	d["tip_color"] = SaveHelpers.color_to_array(tip_color)
	return d


func apply_save_dict(d: Dictionary) -> void:
	coral_form = String(d.get("coral_form", coral_form))
	tip_color = SaveHelpers.array_to_color(d.get("tip_color", []), tip_color)
	super.apply_save_dict(d)


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	match coral_form:
		"branching":
			_grow_branching()
		"feathery":
			_grow_feathery()
		"plate":
			_grow_plate()
		_:
			_grow_dome()
	current_height += 1
	return true


# ---- Dome / brain coral ----
# Voxels stacked in a low hemisphere using phyllotaxis. The first few
# build a tight center cluster; later voxels spread outward + slightly
# upward so the result is a rounded mound rather than a column.
func _grow_dome() -> void:
	var idx: int = current_height
	var theta: float = float(idx) * GOLDEN_ANGLE
	var rel: float = float(idx) / float(maxi(1, max_height - 1))
	# Radius grows as sqrt(idx) (sunflower-head distribution) and is
	# capped so the dome stays compact.
	var r: float = minf(VOXEL_SIZE * 0.22 * sqrt(float(idx) + 1.0), VOXEL_SIZE * 1.8)
	# Y rises gently with rel - new polyps sit on top of the dome.
	var y: float = VOXEL_SIZE * (0.25 + rel * 0.85) * sqrt(1.0 - minf(rel, 0.95))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	# Newer voxels (high idx) read as the lighter polyp color, older are darker.
	var c: Color = ramp[clampi(int(rel * (ramp.size() - 1)), 0, ramp.size() - 1)]
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.42,
		VOXEL_SIZE * 0.32,
		VOXEL_SIZE * 0.42,
	))
	mi.material_override = VoxelMat.make(c)
	mi.position = Vector3(cos(theta) * r, y, sin(theta) * r)
	add_child(mi)
	voxels.append(mi)


# ---- Branching staghorn ----
# Builds a vertical stem with periodic angled side-branches. Each branch
# is a short chain of voxels rotating away from the main stem axis.
# Tips of the youngest segments use tip_color (zooxanthellae glow).
const BRANCH_INTERVAL: int = 3
const BRANCH_LENGTH: int = 3


func _grow_branching() -> void:
	var idx: int = current_height
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var stem_color: Color = ramp[clampi(2 + (idx / 4), 0, ramp.size() - 1)]
	# Main stem voxel. Slightly thicker at the base, taper toward the top.
	var taper: float = clampf(1.0 - float(idx) / float(maxi(1, max_height)) * 0.45, 0.4, 1.0)
	var stem := MeshInstance3D.new()
	stem.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.5 * taper,
		VOXEL_SIZE * 0.85,
		VOXEL_SIZE * 0.5 * taper,
	))
	stem.material_override = VoxelMat.make(stem_color)
	stem.position = Vector3(0.0, idx * VOXEL_SIZE * 0.85, 0.0)
	add_child(stem)
	voxels.append(stem)
	# Side branch every BRANCH_INTERVAL voxels along the stem.
	if idx >= 2 and idx % BRANCH_INTERVAL == 0:
		_spawn_side_branch(idx, ramp)
	# Glowing tip voxel on the topmost segment.
	if idx == max_height - 1:
		var tip := MeshInstance3D.new()
		tip.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.32))
		tip.material_override = VoxelMat.make(tip_color)
		tip.position = Vector3(0.0, idx * VOXEL_SIZE * 0.85 + VOXEL_SIZE * 0.4, 0.0)
		add_child(tip)
		voxels.append(tip)


func _spawn_side_branch(idx: int, ramp: Array) -> void:
	var theta: float = randf() * TAU
	var dx: float = cos(theta)
	var dz: float = sin(theta)
	# Branch tilts upward slightly so it angles away from the stem.
	var dy_step: float = 0.5
	var base_y: float = idx * VOXEL_SIZE * 0.85
	for j in BRANCH_LENGTH:
		var t: float = float(j + 1) / float(BRANCH_LENGTH)
		var c: Color = ramp[clampi(1 + j, 0, ramp.size() - 1)]
		# Branch tip color = glowing polyp.
		if j == BRANCH_LENGTH - 1:
			c = tip_color
		var bv := MeshInstance3D.new()
		bv.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.32))
		bv.material_override = VoxelMat.make(c)
		bv.position = Vector3(
			dx * VOXEL_SIZE * 0.55 * float(j + 1),
			base_y + dy_step * VOXEL_SIZE * float(j + 1) * 0.55,
			dz * VOXEL_SIZE * 0.55 * float(j + 1),
		)
		add_child(bv)
		voxels.append(bv)


# ---- Feathery / soft coral ----
# Tall stalk with paired lateral feather voxels at every node, creating a
# fern-like silhouette. Stalk is thin so the feathers dominate.
func _grow_feathery() -> void:
	var idx: int = current_height
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var rel: float = float(idx) / float(maxi(1, max_height - 1))
	var stalk_color: Color = ramp[clampi(2, 0, ramp.size() - 1)]
	var feather_color: Color = ramp[clampi(int(3.0 + rel * 2.0), 0, ramp.size() - 1)]
	# Stalk voxel.
	var stalk := MeshInstance3D.new()
	stalk.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.22))
	stalk.material_override = VoxelMat.make(stalk_color)
	stalk.position = Vector3(0.0, idx * VOXEL_SIZE * 0.85, 0.0)
	add_child(stalk)
	voxels.append(stalk)
	# Two feathers, opposite each other, rotating around the stalk by
	# golden angle so each node points a different direction.
	var theta: float = float(idx) * GOLDEN_ANGLE
	for side in [1.0, -1.0]:
		var fx: float = cos(theta) * side
		var fz: float = sin(theta) * side
		var fv := MeshInstance3D.new()
		fv.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.18))
		fv.material_override = VoxelMat.make(feather_color)
		fv.position = Vector3(
			fx * VOXEL_SIZE * 0.4,
			idx * VOXEL_SIZE * 0.85,
			fz * VOXEL_SIZE * 0.4,
		)
		# Rotate so the feather points outward along XZ.
		fv.look_at(fv.position + Vector3(fx, 0.0, fz), Vector3.UP)
		add_child(fv)
		voxels.append(fv)


# ---- Plate / table coral ----
# Short stem on the first few voxels, then a wide flat disc of polyps in
# phyllotaxis arrangement at the top.
const PLATE_STEM_HEIGHT: int = 3


func _grow_plate() -> void:
	var idx: int = current_height
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	if idx < PLATE_STEM_HEIGHT:
		# Stem voxel.
		var stem := MeshInstance3D.new()
		stem.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.45, VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.45))
		stem.material_override = VoxelMat.make(ramp[1])
		stem.position = Vector3(0.0, idx * VOXEL_SIZE * 0.85, 0.0)
		add_child(stem)
		voxels.append(stem)
		return
	# Polyp on the disc. Phyllotaxis on a flat plane.
	var disc_idx: int = idx - PLATE_STEM_HEIGHT
	var theta: float = float(disc_idx) * GOLDEN_ANGLE
	var r: float = VOXEL_SIZE * 0.32 * sqrt(float(disc_idx) + 1.0)
	var disc_y: float = PLATE_STEM_HEIGHT * VOXEL_SIZE * 0.85
	var c: Color = ramp[clampi(3 + (disc_idx % 3), 0, ramp.size() - 1)]
	var p := MeshInstance3D.new()
	p.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.38, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.38))
	p.material_override = VoxelMat.make(c)
	p.position = Vector3(cos(theta) * r, disc_y, sin(theta) * r)
	add_child(p)
	voxels.append(p)


# Corals don't propagate via runners or seeds (could be modeled as
# fragmentation later, but keep the V1 surface tight).
func _tick_runner(_dt: float) -> void:
	pass


func _tick_seeding(_dt: float) -> void:
	pass


func get_seed_config() -> Dictionary:
	var cfg: Dictionary = super.get_seed_config()
	cfg["coral_form"] = coral_form
	cfg["tip_color"] = tip_color
	return cfg
