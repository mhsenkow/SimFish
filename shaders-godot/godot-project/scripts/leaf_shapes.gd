# Leaf shape builders for different plant forms.
#
# Each function returns an Array of MeshInstance3D nodes representing a single
# leaf, positioned in local space ready to be parented to a plant node.
# Leaf shapes are the key visual differentiator between plant species:
#
#   paddle  — wide, flat, pointed oval (Cryptocoryne, Amazon Sword)
#   ribbon  — long, narrow, tapered tip (Vallisneria, Sagittaria)
#   lance   — medium width, pointed both ends (Ludwigia, Rotala)
#   needle  — very thin, grass-like (Eleocharis, Hairgrass)
#   oval    — short, rounded (Anubias, Bucephalandra)
#   round   — circular pad (lily pads, floating leaves)
#   lobed   — irregular edges (Java Fern, Bolbitis)
#
# The voxel aesthetic is preserved: leaves are built from BoxMesh voxels
# arranged to approximate the shape. Dither volume comes from the palette
# quantize shader, not from transparency here.

extends RefCounted
class_name LeafShapes

const VOXEL_SIZE: float = 0.32


# ---- Paddle leaf (rosette plants: Crypts, Swords) ----
# A flat, 2-3 voxel wide, 4-7 voxel tall pointed oval. Wider in the middle,
# tapering at both ends. The midrib (center column) is slightly darker.
static func build_paddle(length: int, ramp: Array, age_frac: float,
		width: int = 2, flatten: float = 0.55) -> Array:
	var nodes: Array = []
	for i in length:
		var t: float = float(i) / float(maxi(1, length - 1))
		# Width profile: diamond shape, widest at 40% of length.
		var profile: float = 1.0 - absf(t - 0.4) / 0.6
		profile = clampf(profile, 0.2, 1.0)
		var row_width: int = maxi(1, int(float(width) * profile))
		@warning_ignore("integer_division")
		var row_half: int = row_width / 2
		for dx in range(-row_half, row_half + 1):
			var is_midrib: bool = (dx == 0)
			var color: Color = _leaf_color(ramp, t, age_frac, is_midrib)
			var mi := MeshInstance3D.new()
			var sx: float = VOXEL_SIZE * 0.9
			var sy: float = VOXEL_SIZE * 0.9
			var sz: float = VOXEL_SIZE * flatten
			# Tip voxels are smaller.
			if i == length - 1:
				sx *= 0.6
				sz *= 0.6
			mi.mesh = VoxelMat.get_box(Vector3(sx, sy, sz))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				float(dx) * VOXEL_SIZE * 0.75,
				float(i) * VOXEL_SIZE * 0.85,
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Ribbon leaf (blade plants: Vallisneria, Sagittaria) ----
# Long, single-voxel wide strip with a slightly wider base and tapered tip.
# Gentle sinusoidal curve along its length for natural flowing look.
static func build_ribbon(length: int, ramp: Array, age_frac: float,
		sway_seed: float = 0.0) -> Array:
	var nodes: Array = []
	for i in length:
		var t: float = float(i) / float(maxi(1, length - 1))
		var color: Color = _leaf_color(ramp, t, age_frac, i < 2)
		var mi := MeshInstance3D.new()
		# Slight width taper: base is 1.0, tip is 0.5.
		var width_factor: float = 1.0 - t * 0.5
		# Very tip is thin.
		if i >= length - 2:
			width_factor *= 0.6
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * width_factor,
			VOXEL_SIZE * 1.0,
			VOXEL_SIZE * 0.4,
		))
		mi.material_override = VoxelMat.make_foliage(color)
		# Gentle S-curve along the blade.
		var curve_x: float = sin(t * PI + sway_seed) * VOXEL_SIZE * 0.4
		mi.position = Vector3(
			curve_x,
			float(i) * VOXEL_SIZE * 0.9,
			0.0,
		)
		nodes.append(mi)
	return nodes


# ---- Lance leaf (stem plants: Ludwigia, Rotala) ----
# Medium length, pointed at both ends, 2 voxels wide in the middle.
# These come in pairs (decussate phyllotaxis: each pair rotated 90°).
static func build_lance_pair(ramp: Array, age_frac: float,
		pair_index: int = 0) -> Array:
	var nodes: Array = []
	var leaf_len: int = 3
	var yaw_offset: float = float(pair_index % 2) * PI * 0.5
	for side in [-1, 1]:
		for i in leaf_len:
			var t: float = float(i) / float(leaf_len - 1)
			var color: Color = _leaf_color(ramp, t, age_frac, i == 0)
			var mi := MeshInstance3D.new()
			# Width profile: widest in the middle.
			var w: float = 0.7 if i == 1 else 0.45
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * w,
				VOXEL_SIZE * 0.45,
				VOXEL_SIZE * 0.35,
			))
			mi.material_override = VoxelMat.make_foliage(color)
			# Leaves angle outward from the stem.
			var angle: float = float(side) * 0.7 + yaw_offset
			var dist: float = float(i) * VOXEL_SIZE * 0.65
			mi.position = Vector3(
				cos(angle) * dist,
				sin(angle) * dist * 0.3,
				sin(angle) * dist,
			)
			nodes.append(mi)
	return nodes


# ---- Needle leaf (carpet plants: Hairgrass, Eleocharis) ----
# Very thin single-voxel blade, barely wider than a stem.
static func build_needle(length: int, ramp: Array, age_frac: float) -> Array:
	var nodes: Array = []
	for i in length:
		var t: float = float(i) / float(maxi(1, length - 1))
		var color: Color = _leaf_color(ramp, t, age_frac, false)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.3,
			VOXEL_SIZE * 0.8,
			VOXEL_SIZE * 0.3,
		))
		mi.material_override = VoxelMat.make_foliage(color)
		mi.position = Vector3(0, float(i) * VOXEL_SIZE * 0.75, 0)
		nodes.append(mi)
	return nodes


# ---- Oval leaf (Anubias, Bucephalandra) ----
# Short, wide, rounded. 3 voxels wide, 3-4 tall. Thick and waxy-looking.
static func build_oval(ramp: Array, age_frac: float) -> Array:
	var nodes: Array = []
	# 3x4 grid with rounded corners (skip corners).
	var pattern: Array = [
		[0, 1, 0],
		[1, 1, 1],
		[1, 1, 1],
		[0, 1, 0],
	]
	for row in pattern.size():
		for col in pattern[row].size():
			if pattern[row][col] == 0:
				continue
			var t: float = float(row) / float(pattern.size() - 1)
			var is_mid: bool = (col == 1)
			var color: Color = _leaf_color(ramp, t, age_frac, is_mid)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.85,
				VOXEL_SIZE * 0.4,
				VOXEL_SIZE * 0.8,
			))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				(float(col) - 1.0) * VOXEL_SIZE * 0.7,
				float(row) * VOXEL_SIZE * 0.65,
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Lobed leaf (Java Fern, Bolbitis) ----
# Irregular, wider than lance, with indentations that suggest lobes.
static func build_lobed(length: int, ramp: Array, age_frac: float) -> Array:
	var nodes: Array = []
	for i in length:
		var t: float = float(i) / float(maxi(1, length - 1))
		# Width oscillates to create lobe effect.
		var lobe: float = 1.0 + sin(float(i) * 1.8) * 0.4
		var row_width: int = maxi(1, int(2.0 * lobe))
		@warning_ignore("integer_division")
		var row_half: int = row_width / 2
		for dx in range(-row_half, row_half + 1):
			var is_midrib: bool = (dx == 0)
			var color: Color = _leaf_color(ramp, t, age_frac, is_midrib)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.8,
				VOXEL_SIZE * 0.9,
				VOXEL_SIZE * 0.45,
			))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				float(dx) * VOXEL_SIZE * 0.7,
				float(i) * VOXEL_SIZE * 0.8,
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Root system ----
# Downward-branching root voxels anchoring the plant into the substrate.
static func build_roots(count: int, ramp: Array, depth: float = 1.0) -> Array:
	var nodes: Array = []
	var root_color: Color = ramp[0] if ramp.size() > 0 else Color8(60, 45, 30)
	var root_light: Color = ramp[1] if ramp.size() > 1 else Color8(80, 60, 40)
	for i in count:
		# Each root goes down and slightly outward.
		var angle: float = float(i) / float(maxi(1, count)) * TAU
		var r_len: int = maxi(2, int(depth / VOXEL_SIZE))
		for j in r_len:
			var t: float = float(j) / float(r_len)
			var spread: float = t * VOXEL_SIZE * 1.5
			var mi := MeshInstance3D.new()
			# Roots taper: thicker near the base.
			var taper: float = 1.0 - t * 0.5
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.25 * taper,
				VOXEL_SIZE * 0.7,
				VOXEL_SIZE * 0.25 * taper,
			))
			mi.material_override = VoxelMat.make(
				root_color.lerp(root_light, t * 0.3))
			mi.position = Vector3(
				cos(angle) * spread,
				-float(j) * VOXEL_SIZE * 0.6,
				sin(angle) * spread,
			)
			nodes.append(mi)
	return nodes


# ---- Runner stolon ----
# Horizontal root connecting parent to daughter plant position.
static func build_runner(start: Vector3, end: Vector3, color: Color) -> Array:
	var nodes: Array = []
	var dir: Vector3 = end - start
	var dist: float = dir.length()
	if dist < 0.01:
		return nodes
	var steps: int = maxi(2, int(dist / (VOXEL_SIZE * 0.6)))
	for i in steps:
		var t: float = float(i) / float(steps - 1)
		var pos: Vector3 = start.lerp(end, t)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.2, VOXEL_SIZE * 0.15, VOXEL_SIZE * 0.2))
		mi.material_override = VoxelMat.make(color)
		mi.position = pos
		nodes.append(mi)
	return nodes


# ---- Flower bud ----
# Small green sphere-ish cluster that will later open into petals.
static func build_bud(color: Color) -> Array:
	var nodes: Array = []
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.5))
	mi.material_override = VoxelMat.make_foliage(color)
	mi.position = Vector3.ZERO
	nodes.append(mi)
	# Two tiny sepal voxels at the base.
	for dx in [-1, 1]:
		var sepal := MeshInstance3D.new()
		sepal.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.3, VOXEL_SIZE * 0.25, VOXEL_SIZE * 0.3))
		sepal.material_override = VoxelMat.make_foliage(color.darkened(0.3))
		sepal.position = Vector3(float(dx) * VOXEL_SIZE * 0.35, -VOXEL_SIZE * 0.2, 0)
		nodes.append(sepal)
	return nodes


# ---- Open flower ----
# 4-6 petal voxels arranged radially around a center pistil.
# `open_frac` 0..1 controls how far the petals have spread.
static func build_flower(petal_color: Color, center_color: Color,
		n_petals: int = 5, open_frac: float = 1.0) -> Array:
	var nodes: Array = []
	# Center pistil / carpel.
	var center := MeshInstance3D.new()
	center.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.4, VOXEL_SIZE * 0.35, VOXEL_SIZE * 0.4))
	center.material_override = VoxelMat.make_foliage(center_color)
	center.position = Vector3(0, VOXEL_SIZE * 0.1, 0)
	nodes.append(center)
	# Petals fan outward as open_frac increases.
	for i in n_petals:
		var angle: float = float(i) / float(n_petals) * TAU
		var spread: float = open_frac * VOXEL_SIZE * 0.85
		var petal := MeshInstance3D.new()
		petal.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.25, VOXEL_SIZE * 0.5))
		# Slight color variation per petal for organic feel.
		var shade: float = sin(float(i) * 2.3) * 0.08
		var pc: Color = Color(
			clampf(petal_color.r + shade, 0.0, 1.0),
			clampf(petal_color.g + shade, 0.0, 1.0),
			clampf(petal_color.b + shade, 0.0, 1.0),
		)
		petal.material_override = VoxelMat.make_foliage(pc)
		petal.position = Vector3(
			cos(angle) * spread,
			VOXEL_SIZE * 0.05 - open_frac * VOXEL_SIZE * 0.15,
			sin(angle) * spread,
		)
		# Petals tilt outward as they open.
		petal.rotation.z = cos(angle) * open_frac * 0.4
		petal.rotation.x = sin(angle) * open_frac * 0.4
		nodes.append(petal)
	return nodes


static func update_flower(nodes: Array, n_petals: int, open_frac: float) -> void:
	if nodes.size() < n_petals + 1:
		return
	for i in n_petals:
		var angle: float = float(i) / float(n_petals) * TAU
		var spread: float = open_frac * VOXEL_SIZE * 0.85
		var petal: Node3D = nodes[i + 1] # 0 is center
		if is_instance_valid(petal):
			petal.position = Vector3(
				cos(angle) * spread,
				VOXEL_SIZE * 0.05 - open_frac * VOXEL_SIZE * 0.15,
				sin(angle) * spread,
			)
			petal.rotation.z = cos(angle) * open_frac * 0.4
			petal.rotation.x = sin(angle) * open_frac * 0.4


# ---- Seed pod ----
# Darkened, slightly larger than a bud. Precursor to seed release.
static func build_seed_pod(color: Color) -> Array:
	var nodes: Array = []
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.55))
	mi.material_override = VoxelMat.make_foliage(color.darkened(0.35))
	nodes.append(mi)
	return nodes


# ---- Color helpers ----

# Compute leaf voxel color based on position along the leaf (t: 0=base, 1=tip),
# age fraction (0=new, 1=old), and whether this is the midrib.
static func _leaf_color(ramp: Array, t: float, age_frac: float,
		is_midrib: bool) -> Color:
	if ramp.size() < 2:
		return Color8(60, 130, 70)
	# Newer growth is brighter (higher ramp index); older is darker.
	var ramp_t: float = clampf(t * 0.6 + (1.0 - age_frac) * 0.4, 0.0, 1.0)
	var idx_f: float = ramp_t * float(ramp.size() - 1)
	var idx_lo: int = clampi(int(idx_f), 0, ramp.size() - 2)
	var idx_hi: int = idx_lo + 1
	var frac: float = idx_f - float(idx_lo)
	var color: Color = (ramp[idx_lo] as Color).lerp(ramp[idx_hi] as Color, frac)
	# Midrib is slightly darker for visible venation.
	if is_midrib:
		color = color.darkened(0.12)
	# Old leaves darken overall.
	if age_frac > 0.7:
		color = color.darkened((age_frac - 0.7) * 0.3)
	return color


# Compute a stress/deficiency color by lerping toward a stress palette.
static func stress_color(base_color: Color, stress_level: float,
		stress_ramp: Array) -> Color:
	if stress_ramp.is_empty() or stress_level <= 0.0:
		return base_color
	var idx: int = clampi(int(stress_level * float(stress_ramp.size())),
		0, stress_ramp.size() - 1)
	return base_color.lerp(stress_ramp[idx] as Color, clampf(stress_level, 0.0, 0.8))
