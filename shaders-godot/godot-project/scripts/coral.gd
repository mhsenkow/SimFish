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

# L-system branching state for staghorn fern coral
var _fern_tips: Array = []
# Precalculated positions for the Gyroid reaction-diffusion brain coral dome
var _brain_positions: Array[Vector3] = []



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
		"brain":
			_grow_brain()
		"staghorn_fern":
			_grow_staghorn_fern()
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
	mi.material_override = VoxelMat.make_foliage(c)
	mi.position = Vector3(cos(theta) * r, y, sin(theta) * r)
	add_child(mi)
	voxels.append(mi)


# ---- Brain coral with reaction-diffusion style folds ----
# Generates convoluted, wavy lobes like reaction-diffusion minimal surfaces (Gyroids).
# Scans a hemispherical bounding volume and selects coordinates that intersect
# the Gyroid zero-isosurface, sorting them bottom-up and center-outward for organic growth.
func _generate_brain_positions() -> void:
	_brain_positions.clear()
	
	# Determine radius of the hemisphere based on max_height
	var R: float = VOXEL_SIZE * 0.35 * sqrt(float(max_height) * 2.2)
	R = clampf(R, VOXEL_SIZE * 1.2, VOXEL_SIZE * 2.8)
	
	# Scan a 3D grid in steps matching the voxel scale
	var step := VOXEL_SIZE * 0.36
	var bound := int(ceil(R / step)) + 1
	
	# Frequency of the Gyroid waves (adjusted to fit within R)
	var freq := 6.5 / R
	
	var candidates: Array[Vector3] = []
	for ix in range(-bound, bound + 1):
		for iy in range(0, bound + 1):
			for iz in range(-bound, bound + 1):
				var pos := Vector3(ix * step, iy * step, iz * step)
				var dist := pos.length()
				
				# Must be within the dome radius
				if dist > R or dist < VOXEL_SIZE * 0.15:
					continue
				
				# Gyroid equation: sin(x)*cos(y) + sin(y)*cos(z) + sin(z)*cos(x)
				var val := sin(pos.x * freq) * cos(pos.y * freq) + \
						   sin(pos.y * freq) * cos(pos.z * freq) + \
						   sin(pos.z * freq) * cos(pos.x * freq)
				
				# absf(val) < threshold creates beautiful maze-like ridges
				if absf(val) < 0.38:
					candidates.append(pos)
					
	# Sort candidates so the coral grows organically:
	# 1. Height (Y) ascending (bottom-up growth)
	# 2. Distance from center ascending (center-outward growth)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var ay_snapped := snappedf(a.y, 0.02)
		var by_snapped := snappedf(b.y, 0.02)
		if not is_equal_approx(ay_snapped, by_snapped):
			return ay_snapped < by_snapped
		return a.length_squared() < b.length_squared()
	)
	
	_brain_positions = candidates
	
	# Adjust max_height to match the generated candidate list so that
	# grazing/growth scales accurately with the physical voxel counts.
	max_height = candidates.size()


func _grow_brain() -> void:
	if _brain_positions.is_empty():
		_generate_brain_positions()
		
	var idx: int = current_height
	if idx >= _brain_positions.size():
		return
		
	var pos: Vector3 = _brain_positions[idx]
	var rel: float = float(idx) / float(maxi(1, _brain_positions.size() - 1))
	
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var c: Color = ramp[clampi(int(rel * (ramp.size() - 1)), 0, ramp.size() - 1)]
	
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.42,
		VOXEL_SIZE * 0.32,
		VOXEL_SIZE * 0.42
	))
	mi.material_override = VoxelMat.make_foliage(c)
	mi.position = pos
	add_child(mi)
	voxels.append(mi)


# ---- Staghorn Fern Coral ----
# Grows flat in the X-Y plane using a bifurcating L-system.
# Older branches are thicker; young tip branches are thin and use tip_color.
func _grow_staghorn_fern() -> void:
	if _fern_tips.is_empty():
		# Spawn base trunk and initialize the first tip
		_fern_tips.append({
			"pos": Vector3.ZERO,
			"dir": Vector3.UP,
			"length": 0,
			"gen": 0
		})
		
		var base_vox := MeshInstance3D.new()
		base_vox.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.55))
		var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
		base_vox.material_override = VoxelMat.make_foliage(ramp[0])
		base_vox.position = Vector3.ZERO
		add_child(base_vox)
		voxels.append(base_vox)
		return

	# Pop the oldest active tip to grow it
	var tip: Dictionary = _fern_tips.pop_front()
	var new_pos: Vector3 = tip.pos + tip.dir * VOXEL_SIZE * 0.75
	
	# Determine color based on generation
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var c: Color = ramp[clampi(1 + tip.gen, 0, ramp.size() - 1)]
	if tip.gen >= 2:
		c = tip_color
		
	# Spawn voxel. Thickness tapers as generation increases
	var thickness: float = clampf(0.5 - tip.gen * 0.12, 0.2, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * thickness, VOXEL_SIZE * 0.75, VOXEL_SIZE * thickness))
	mi.material_override = VoxelMat.make_foliage(c)
	mi.position = new_pos
	
	add_child(mi)
	
	# Align the voxel mesh with its growth direction
	if tip.dir != Vector3.UP:
		mi.look_at(new_pos + tip.dir, Vector3.UP)
		mi.rotate_x(PI * 0.5)
		
	voxels.append(mi)
	
	# Increment tip length
	tip.length += 1
	
	# Decide if we branch or continue
	var branch_length := 3
	if tip.length >= branch_length:
		if tip.gen < 3: # max 3 levels of branching
			# Bifurcate: split in two directions in the XY plane
			var angle := 0.55
			var tip_dir: Vector3 = tip.dir
			var dir_left := tip_dir.rotated(Vector3(0, 0, 1), angle).normalized()
			var dir_right := tip_dir.rotated(Vector3(0, 0, 1), -angle).normalized()
			
			_fern_tips.append({
				"pos": new_pos,
				"dir": dir_left,
				"length": 0,
				"gen": tip.gen + 1
			})
			_fern_tips.append({
				"pos": new_pos,
				"dir": dir_right,
				"length": 0,
				"gen": tip.gen + 1
			})
		# If gen is at max, this tip stops growing (dies)
	else:
		# Continue tip
		tip.pos = new_pos
		_fern_tips.append(tip)



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
	stem.material_override = VoxelMat.make_foliage(stem_color)
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
		tip.material_override = VoxelMat.make_foliage(tip_color)
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
		bv.material_override = VoxelMat.make_foliage(c)
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
	stalk.material_override = VoxelMat.make_foliage(stalk_color)
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
		fv.material_override = VoxelMat.make_foliage(feather_color)
		fv.position = Vector3(
			fx * VOXEL_SIZE * 0.4,
			idx * VOXEL_SIZE * 0.85,
			fz * VOXEL_SIZE * 0.4,
		)
		add_child(fv)
		# Rotate so the feather points outward along XZ.
		fv.look_at(fv.position + Vector3(fx, 0.0, fz), Vector3.UP)
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
		stem.material_override = VoxelMat.make_foliage(ramp[1])
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
	p.material_override = VoxelMat.make_foliage(c)
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
