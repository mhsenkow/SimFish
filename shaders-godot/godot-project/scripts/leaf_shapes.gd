# Leaf shape builders for different plant forms.
#
# Each function returns an Array of MeshInstance3D nodes representing a single
# leaf, positioned in local space ready to be parented to a plant node.
# Leaf shapes are the key visual differentiator between plant species:
#
#   paddle      — wide, flat, pointed oval (Cryptocoryne, Amazon Sword)
#   ribbon      — long, narrow, tapered tip (Vallisneria, Sagittaria)
#   lance       — medium width, pointed both ends (Ludwigia, Rotala)
#   needle      — very thin, grass-like (Eleocharis, Hairgrass)
#   oval        — short, rounded (Anubias, Bucephalandra)
#   round       — circular pad (lily pads, floating leaves)
#   lobed       — irregular edges (Java Fern, Bolbitis)
#   spade       — broad rounded-spade (Anubias barteri, A. coffeefolia)
#   cordate     — heart-shaped (Red Root Floater, Limnobium)
#   pinnate     — fern-divided / lobed (Hygrophila pinnatifida, Bolbitis)
#   starburst   — radial rosette (Eriocaulon, Blyxa)
#   four_leaf   — Marsilea-style four-leaf clover
#   fingered    — branched / trident-lobed (Java Fern Windelov, Trident)
#   downy       — crinkled-curly mini-rosette (Pogostemon helferi)
#
# === Textural modifiers ===
# All builders accept an optional `modifiers` Dictionary with:
#   variegation: float  — 0..1, chance per voxel of renders white/cream
#   quilted: bool       — small per-voxel vertical jitter (Anubias coffeefolia)
#   wavy: bool          — sine offset along leaf width (Crypt wendtii ruffled)
#   tone_under: Color   — undercolor used at extreme leaf positions
#
# The voxel aesthetic is preserved: leaves are built from BoxMesh voxels
# arranged to approximate the shape. Dither volume comes from the palette
# quantize shader, not from transparency here.

extends RefCounted
class_name LeafShapes

const VOXEL_SIZE: float = 0.32

# ---- Texture modifier helpers ----
# Apply variegation chance + tone_under venation + iridescent sheen overlay.
# tone_under_v can be a Color (used near leaf tip) or null (skip).
# iridescence in 0..1 — Bucephalandra purple/teal grazing-angle shift.
static func _modify_color(base: Color, t: float, varieg: float,
		tone_under_v: Variant, iridescence: float = 0.0) -> Color:
	var c: Color = base
	if varieg > 0.0 and randf() < varieg:
		c = Color(
			randf_range(0.88, 0.96),
			randf_range(0.92, 0.98),
			randf_range(0.88, 0.95),
		)
	if tone_under_v is Color and t > 0.85:
		var k: float = (t - 0.85) / 0.15
		c = c.lerp(tone_under_v, k * 0.35)
	if iridescence > 0.0:
		c = iridescent_shift(c, t, iridescence)
	return c


# Apply quilted texture: tiny vertical jitter on the voxel position.
static func _quilt_offset(quilted: bool, idx: int) -> float:
	if not quilted:
		return 0.0
	# Deterministic per-voxel based on idx so the bumps don't shimmer.
	var phase: float = float(idx % 7) * 0.9 + float(idx % 3) * 0.3
	return sin(phase) * VOXEL_SIZE * 0.08


# Apply wavy edge: lateral offset on a leaf's edge voxel only.
static func _wave_x_offset(wavy: bool, dx: int, row: int) -> float:
	if not wavy or dx == 0:
		return 0.0
	return sin(float(row) * 0.6 + float(dx) * 0.5) * VOXEL_SIZE * 0.18


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
		var row_half: int = int(row_width / 2.0)
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
		var row_half: int = int(row_width / 2.0)
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


# ---- Spade leaf (Anubias barteri, A. coffeefolia, sword-form epiphytes) ----
# Broad rounded-spade shape, 3-4 wide × 4-5 tall, plumper than oval, with
# a noticeable tip taper. Optional quilted texture for coffeefolia.
static func build_spade(ramp: Array, age_frac: float, length: int = 5,
		width: int = 3, mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var quilted: bool = bool(mods.get("quilted", false))
	var wavy: bool = bool(mods.get("wavy", false))
	var tone_under_v: Variant = mods.get("tone_under", null)
	for row in length:
		var t: float = float(row) / float(maxi(1, length - 1))
		# Spade profile: narrow at base, wide at 60% height, taper to point.
		var profile: float
		if t < 0.20:
			profile = 0.45 + t * 1.75
		elif t < 0.65:
			profile = 0.85 + (t - 0.20) * 0.35
		else:
			profile = 1.05 - (t - 0.65) * 2.4
		var row_width: int = clampi(int(float(width) * profile), 1, width + 1)
		var row_half: int = int(row_width / 2.0)
		for dx in range(-row_half, row_half + 1):
			var is_midrib: bool = (dx == 0)
			var base: Color = _leaf_color(ramp, t, age_frac, is_midrib)
			var color: Color = _modify_color(base, t, varieg, tone_under_v, iridescence)
			var mi := MeshInstance3D.new()
			var sy: float = VOXEL_SIZE * 0.4
			# Tip and base voxels slightly smaller for rounded silhouette.
			if row == length - 1 or row == 0:
				sy *= 0.7
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.95, sy, VOXEL_SIZE * 0.85))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				float(dx) * VOXEL_SIZE * 0.7 + _wave_x_offset(wavy, dx, row),
				float(row) * VOXEL_SIZE * 0.72 + _quilt_offset(quilted, row * 3 + dx),
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Cordate (heart) leaf (Red Root Floater, Limnobium) ----
# Heart shape with a notch at the base. 4 voxels wide × 3-4 tall.
static func build_cordate(ramp: Array, age_frac: float,
		mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var quilted: bool = bool(mods.get("quilted", false))
	var wavy: bool = bool(mods.get("wavy", false))
	var tone_under_v: Variant = mods.get("tone_under", null)
	# Pattern: 1 = voxel, 0 = empty. Heart shape laid out top-down.
	var pattern: Array = [
		[0, 1, 1, 1, 1, 0],  # top (widest)
		[1, 1, 1, 1, 1, 1],
		[1, 1, 1, 1, 1, 1],
		[0, 1, 1, 1, 1, 0],
		[0, 0, 1, 0, 1, 0],  # base notch
	]
	for row in pattern.size():
		for col in pattern[row].size():
			if pattern[row][col] == 0:
				continue
			var t: float = float(row) / float(pattern.size() - 1)
			var col_centered: int = col - 3
			var is_midrib: bool = (col == 2 or col == 3)
			var base: Color = _leaf_color(ramp, t, age_frac, is_midrib)
			var color: Color = _modify_color(base, t, varieg, tone_under_v, iridescence)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.85,
				VOXEL_SIZE * 0.35,
				VOXEL_SIZE * 0.85,
			))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				float(col_centered) * VOXEL_SIZE * 0.7
					+ _wave_x_offset(wavy, col_centered, row),
				float(pattern.size() - 1 - row) * VOXEL_SIZE * 0.55
					+ _quilt_offset(quilted, row * 3 + col),
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Pinnate / fern-divided leaf (Hygrophila pinnatifida, Bolbitis) ----
# A central rachis with paired leaflets branching off. Each leaflet shrinks
# toward the tip, giving the distinct fern silhouette.
static func build_pinnate(length: int, ramp: Array, age_frac: float,
		mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var quilted: bool = bool(mods.get("quilted", false))
	var tone_under_v: Variant = mods.get("tone_under", null)
	for i in length:
		var t: float = float(i) / float(maxi(1, length - 1))
		var rachis_color: Color = _leaf_color(ramp, t, age_frac, true)
		# Central rachis (midrib).
		var stem := MeshInstance3D.new()
		stem.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.32))
		stem.material_override = VoxelMat.make_foliage(rachis_color)
		stem.position = Vector3(0.0, float(i) * VOXEL_SIZE * 0.75
			+ _quilt_offset(quilted, i), 0.0)
		nodes.append(stem)
		# Leaflets: paired, length tapers toward the tip.
		var leaflet_len: int = clampi(3 - int(t * 2.0), 1, 3)
		for side in [-1, 1]:
			for j in leaflet_len:
				var leaflet := MeshInstance3D.new()
				var c: Color = _modify_color(
					_leaf_color(ramp, t, age_frac, j == 0), t, varieg, tone_under_v, iridescence)
				leaflet.mesh = VoxelMat.get_box(Vector3(
					VOXEL_SIZE * 0.55,
					VOXEL_SIZE * 0.35,
					VOXEL_SIZE * 0.45,
				))
				leaflet.material_override = VoxelMat.make_foliage(c)
				leaflet.position = Vector3(
					float(side) * (VOXEL_SIZE * 0.55 + float(j) * VOXEL_SIZE * 0.55),
					float(i) * VOXEL_SIZE * 0.75,
					0.0,
				)
				nodes.append(leaflet)
	return nodes


# ---- Starburst rosette (Eriocaulon, Blyxa) ----
# Many narrow blades radiating from a central crown.
static func build_starburst(blades: int, blade_len: int, ramp: Array,
		age_frac: float, mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var tone_under_v: Variant = mods.get("tone_under", null)
	for b in blades:
		var angle: float = float(b) / float(maxi(1, blades)) * TAU
		var tilt: float = randf_range(0.15, 0.45) * PI * 0.5
		for j in blade_len:
			var t: float = float(j) / float(maxi(1, blade_len - 1))
			var c: Color = _modify_color(
				_leaf_color(ramp, t, age_frac, false), t, varieg, tone_under_v, iridescence)
			var mi := MeshInstance3D.new()
			var w: float = (1.0 - t * 0.6) * VOXEL_SIZE * 0.3
			mi.mesh = VoxelMat.get_box(Vector3(w, VOXEL_SIZE * 0.65, w))
			mi.material_override = VoxelMat.make_foliage(c)
			var r: float = float(j) * VOXEL_SIZE * 0.55
			mi.position = Vector3(
				cos(angle) * r * cos(tilt),
				sin(tilt) * r,
				sin(angle) * r * cos(tilt),
			)
			nodes.append(mi)
	return nodes


# ---- Four-leaf clover (Marsilea hirsuta) ----
static func build_four_leaf(ramp: Array, age_frac: float,
		mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var tone_under_v: Variant = mods.get("tone_under", null)
	# Tiny vertical stem.
	var stem := MeshInstance3D.new()
	stem.mesh = VoxelMat.get_box(Vector3(VOXEL_SIZE * 0.25, VOXEL_SIZE * 0.6, VOXEL_SIZE * 0.25))
	stem.material_override = VoxelMat.make_foliage(_leaf_color(ramp, 0.0, age_frac, true))
	stem.position = Vector3.ZERO
	nodes.append(stem)
	# Four leaflets at 90° offsets.
	for i in 4:
		var angle: float = float(i) * PI * 0.5
		var leaflet := MeshInstance3D.new()
		var c: Color = _modify_color(
			_leaf_color(ramp, 1.0, age_frac, false), 1.0, varieg, tone_under_v, iridescence)
		leaflet.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.55, VOXEL_SIZE * 0.3, VOXEL_SIZE * 0.55))
		leaflet.material_override = VoxelMat.make_foliage(c)
		leaflet.position = Vector3(
			cos(angle) * VOXEL_SIZE * 0.55,
			VOXEL_SIZE * 0.55,
			sin(angle) * VOXEL_SIZE * 0.55,
		)
		nodes.append(leaflet)
	return nodes


# ---- Fingered / Windelov tips (Java fern Windelov, Trident, Bolbitis) ----
static func build_fingered(length: int, ramp: Array, age_frac: float,
		fingers: int = 3, mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var quilted: bool = bool(mods.get("quilted", false))
	var tone_under_v: Variant = mods.get("tone_under", null)
	var base_len: int = int(length * 0.65)
	for i in base_len:
		var t: float = float(i) / float(maxi(1, length - 1))
		var c: Color = _modify_color(
			_leaf_color(ramp, t, age_frac, true), t, varieg, tone_under_v, iridescence)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(
			VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.4))
		mi.material_override = VoxelMat.make_foliage(c)
		mi.position = Vector3(0, float(i) * VOXEL_SIZE * 0.78
			+ _quilt_offset(quilted, i), 0)
		nodes.append(mi)
	var tip_start_y: float = float(base_len) * VOXEL_SIZE * 0.78
	for f in fingers:
		var rel: float = float(f) / float(maxi(1, fingers - 1)) - 0.5
		var fang: float = rel * 0.9
		var finger_len: int = length - base_len
		for j in finger_len:
			var t2: float = float(base_len + j) / float(maxi(1, length - 1))
			var c2: Color = _modify_color(
				_leaf_color(ramp, t2, age_frac, false), t2, varieg, tone_under_v, iridescence)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.7, VOXEL_SIZE * 0.32))
			mi.material_override = VoxelMat.make_foliage(c2)
			var r: float = float(j) * VOXEL_SIZE * 0.7
			mi.position = Vector3(
				sin(fang) * r,
				tip_start_y + cos(fang) * r,
				0.0,
			)
			nodes.append(mi)
	return nodes


# ---- Downy / Pogostemon helferi ----
static func build_downy(ramp: Array, age_frac: float,
		mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var tone_under_v: Variant = mods.get("tone_under", null)
	var n: int = 9
	for i in n:
		var angle: float = randf() * TAU
		var r: float = randf_range(0.0, VOXEL_SIZE * 0.6)
		var t: float = randf_range(0.4, 1.0)
		var c: Color = _modify_color(
			_leaf_color(ramp, t, age_frac, false), t, varieg, tone_under_v, iridescence)
		var mi := MeshInstance3D.new()
		var sz: float = VOXEL_SIZE * randf_range(0.35, 0.5)
		mi.mesh = VoxelMat.get_box(Vector3(sz, sz, sz))
		mi.material_override = VoxelMat.make_foliage(c)
		mi.position = Vector3(
			cos(angle) * r,
			randf_range(0.0, VOXEL_SIZE * 0.5),
			sin(angle) * r,
		)
		mi.rotation.z = randf_range(-0.4, 0.4)
		nodes.append(mi)
	return nodes


# ---- Round pad (lily pads, surface floaters) ----
static func build_round_pad(radius: int, ramp: Array, age_frac: float,
		mods: Dictionary = {}) -> Array:
	var nodes: Array = []
	var varieg: float = float(mods.get("variegation", 0.0))
	var iridescence: float = float(mods.get("iridescence", 0.0))
	var tone_under_v: Variant = mods.get("tone_under", null)
	var r2: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > r2:
				continue
			var t: float = sqrt(float(dx * dx + dz * dz)) / float(radius)
			if t > 0.85 and randf() < 0.3:
				continue
			var color: Color = _modify_color(
				_leaf_color(ramp, 1.0 - t, age_frac, false), 1.0 - t, varieg, tone_under_v, iridescence)
			var mi := MeshInstance3D.new()
			mi.mesh = VoxelMat.get_box(Vector3(
				VOXEL_SIZE * 0.85, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.85))
			mi.material_override = VoxelMat.make_foliage(color)
			mi.position = Vector3(
				float(dx) * VOXEL_SIZE * 0.75,
				0.0,
				float(dz) * VOXEL_SIZE * 0.75,
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
			mi.material_override = VoxelMat.make_foliage(
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
		mi.material_override = VoxelMat.make_foliage(color)
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
	# Bronze new-growth tint — Anubias coffeefolia / Crypt brown wendtii
	# read as bronze-purple when leaves first emerge, then green up over
	# their first ~minute. We apply a small lerp toward a bronze target
	# when age_frac is very young (< 0.15).
	if age_frac < 0.15:
		var youth: float = 1.0 - age_frac / 0.15
		var bronze: Color = Color(0.62, 0.40, 0.25)
		color = color.lerp(bronze, youth * 0.22)
	return color


# Apply Bucephalandra-style iridescent sheen — a view-angle independent
# soft purple-blue overlay on the brightest voxels. Done CPU-side at
# build time as a color shift; per-instance shader variants would need
# the multimesh path to carry an extra custom data slot which is overkill
# for the visual we want. Called from _modify_color path when the genome
# carries `iridescence > 0`.
static func iridescent_shift(base: Color, t: float, strength: float) -> Color:
	if strength <= 0.0:
		return base
	# Stronger near the tip (brightest part of the leaf), zero near base.
	var k: float = smoothstep(0.4, 1.0, t) * strength
	# Iridescent target — cool purple/teal with extra value boost.
	var iri: Color = Color(0.45, 0.42, 0.72)
	return base.lerp(iri, k * 0.35)


# Compute a stress/deficiency color by lerping toward a stress palette.
static func stress_color(base_color: Color, stress_level: float,
		stress_ramp: Array) -> Color:
	if stress_ramp.is_empty() or stress_level <= 0.0:
		return base_color
	var idx: int = clampi(int(stress_level * float(stress_ramp.size())),
		0, stress_ramp.size() - 1)
	return base_color.lerp(stress_ramp[idx] as Color, clampf(stress_level, 0.0, 0.8))
