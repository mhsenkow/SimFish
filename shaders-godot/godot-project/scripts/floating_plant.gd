# Floating surface plant (duckweed / frogbit / salvinia / water lettuce).
#
# A parametric surface plant that sits at the waterline. Replaces the old
# flat-box "floater" decoration with four recognisable morphs and a heritable
# genome so the player can design custom floating species in the Creature
# Creator and so propagation can pass traits to offspring.
#
# These are NOT rooted Plant instances - they live in World._floaters, drift
# on the surface, photosynthesise (World feeds a count to SimDriver's O2
# model), shade the tank below (suppressing algae), and get grazed by
# herbivorous / surface-feeding fish.

extends Node3D
class_name FloatingPlant

const MORPHS: Array[String] = ["duckweed", "frogbit", "salvinia", "water_lettuce", "red_root"]

# ---- Genome ----
var morph: String = "duckweed"
var leaf_size: float = 0.3
var leaf_count: int = 4
var root_length: float = 0.4
var base_color: Color = Color8(70, 130, 60)
var tip_color: Color = Color8(120, 180, 90)
var spread_rate: float = 1.0     # multiplier on propagation likelihood
# Red Root Floater (Phyllanthus fluitans) signature trait — roots redden
# under bright light + low nitrogen. Other floaters keep root_color as the
# darkened base color.
var redroot_response: float = 0.0  # 0..1, how strongly roots redden under light

# Per-instance drift phase (set by World).
var id: String = ""


func init_genome(g: Dictionary) -> void:
	morph = String(g.get("morph", morph))
	leaf_size = clampf(float(g.get("leaf_size", leaf_size)), 0.12, 0.7)
	leaf_count = clampi(int(g.get("leaf_count", leaf_count)), 1, 9)
	root_length = clampf(float(g.get("root_length", root_length)), 0.05, 1.4)
	base_color = _to_color(g.get("base_color", base_color))
	tip_color = _to_color(g.get("tip_color", tip_color))
	spread_rate = clampf(float(g.get("spread_rate", spread_rate)), 0.2, 2.5)
	redroot_response = clampf(float(g.get("redroot_response", redroot_response)), 0.0, 1.0)
	# Red Root Floater preset — when the morph is "red_root", coerce
	# trait defaults to RRF signatures: small cordate leaves, longish
	# bright-red roots, redroot_response = 1.0.
	if morph == "red_root":
		if redroot_response < 0.5:
			redroot_response = 1.0
		root_length = clampf(maxf(root_length, 0.6), 0.1, 1.4)
	_build()


# Per-tick update — currently used to react to light by reddening RRF roots.
# Called from world (every floater) at ~5 Hz cadence. Cheap; only modulates
# root material color when redroot_response > 0.
func tick_light_response(daylight: float) -> void:
	if redroot_response <= 0.0:
		return
	# Compute the target root tint: dark green when redroot_response is 0,
	# bright red when high light × high redroot_response.
	var redness: float = clampf(redroot_response * daylight, 0.0, 1.0)
	var dark_root: Color = base_color.darkened(0.35)
	var red_root: Color = Color(0.78, 0.28, 0.30)
	var target: Color = dark_root.lerp(red_root, redness * 0.85)
	# Apply to any child node tagged with "root" in its name. We tag
	# during build so this is just a name walk + material recolor.
	for c in get_children():
		if c is MeshInstance3D and String(c.name).begins_with("root"):
			var mi: MeshInstance3D = c
			if mi.material_override is ShaderMaterial:
				# Cheap re-tint: replace the foliage material with a fresh
				# one rather than fishing into uniform values.
				mi.material_override = VoxelMat.make_foliage(target)


func get_genome() -> Dictionary:
	return {
		"organism_type": "plant",
		"floating": true,
		"species": "floating_" + morph,
		"plant_name": _morph_label(),
		"morph": morph,
		"leaf_size": leaf_size,
		"leaf_count": leaf_count,
		"root_length": root_length,
		"base_color": base_color,
		"tip_color": tip_color,
		"spread_rate": spread_rate,
	}


func _morph_label() -> String:
	match morph:
		"frogbit": return "Frogbit"
		"salvinia": return "Salvinia"
		"water_lettuce": return "Water lettuce"
		"red_root": return "Red Root Floater"
		_: return "Duckweed"


# ---- Mesh construction ----

func _build() -> void:
	for c in get_children():
		c.queue_free()
	match morph:
		"frogbit": _build_frogbit()
		"salvinia": _build_salvinia()
		"water_lettuce": _build_water_lettuce()
		"red_root": _build_red_root()
		_: _build_duckweed()


# Red Root Floater (Phyllanthus fluitans) — small cordate leaves, signature
# bright-red trailing roots. Reuses the frogbit-style leaf placement with
# slightly smaller leaves and a dedicated root build path.
func _build_red_root() -> void:
	var n: int = clampi(leaf_count, 2, 5)
	for i in n:
		var ang: float = float(i) / float(n) * TAU + randf_range(-0.2, 0.2)
		var r: float = leaf_size * 0.6
		var pos: Vector3 = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var c: Color = _ring_color(i, n)
		var leaf := _leaf(pos, Vector3(leaf_size * 0.9, 0.06, leaf_size * 0.9), c)
		leaf.name = "leaf_%d" % i
	# Root cluster: 3-4 trailing root voxels. Marked "root_*" so the
	# light_response tick can find and recolor them.
	var rn: int = 3 + (1 if redroot_response > 0.5 else 0)
	var root_color: Color = base_color.darkened(0.35)
	for i in rn:
		var seg_y: float = -root_length * 0.5 - float(i) * root_length * 0.18
		var rmi := MeshInstance3D.new()
		rmi.mesh = VoxelMat.get_box(Vector3(0.06, root_length * 0.22, 0.06))
		rmi.material_override = VoxelMat.make_foliage(root_color)
		rmi.name = "root_%d" % i
		add_child(rmi)
		rmi.position = Vector3(
			randf_range(-leaf_size * 0.3, leaf_size * 0.3),
			seg_y,
			randf_range(-leaf_size * 0.3, leaf_size * 0.3),
		)


func _ring_color(i: int, n: int) -> Color:
	return base_color.lerp(tip_color, float(i) / float(maxi(1, n - 1)))


func _leaf(pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.material_override = VoxelMat.make_foliage(color)
	add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	return mi


func _root_strands(count: int, length: float, spread: float = 1.0) -> void:
	var root_color: Color = base_color.darkened(0.45)
	var mat := VoxelMat.make_foliage(root_color)
	for i in count:
		var ang: float = float(i) / float(maxi(1, count)) * TAU
		var rx: float = cos(ang) * leaf_size * 0.18 * spread
		var rz: float = sin(ang) * leaf_size * 0.18 * spread
		var seg_len: float = length * (0.7 + 0.5 * float((i % 3)) / 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(0.05, seg_len, 0.05))
		mi.material_override = mat
		add_child(mi)
		mi.position = Vector3(rx, -seg_len * 0.5 - 0.02, rz)


func _build_duckweed() -> void:
	# Tiny: 1-3 round leaflets sitting flush at the surface, one short root.
	var n: int = clampi(leaf_count, 1, 3)
	var s: float = leaf_size * 0.6
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = 0.0 if n == 1 else s * 0.55
		_leaf(Vector3(cos(ang) * r, 0.0, sin(ang) * r),
			Vector3(s, 0.06, s), _ring_color(i, n))
	_root_strands(1, root_length * 0.5, 0.4)


func _build_frogbit() -> void:
	# Rosette: a small bud surrounded by rounded pads, trailing root strands.
	var n: int = clampi(leaf_count, 5, 8)
	_leaf(Vector3.ZERO, Vector3(leaf_size * 0.55, 0.07, leaf_size * 0.55), tip_color)
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = leaf_size * 0.7
		_leaf(Vector3(cos(ang) * r, 0.02, sin(ang) * r),
			Vector3(leaf_size, 0.08, leaf_size * 0.85), _ring_color(i, n),
			Vector3(0, ang, 0))
	_root_strands(4, root_length, 1.0)


func _build_salvinia() -> void:
	# Paired oval leaves marching along a midrib, with fuzzy bumps on top.
	var pairs: int = clampi(int(round(float(leaf_count) / 2.0)), 2, 4)
	for i in pairs:
		var z: float = (float(i) - float(pairs) * 0.5) * leaf_size * 0.95
		var col: Color = _ring_color(i, pairs)
		for side in [-1.0, 1.0]:
			_leaf(Vector3(side * leaf_size * 0.5, 0.02, z),
				Vector3(leaf_size * 0.95, 0.07, leaf_size * 0.7), col)
			# Fuzzy raised bump (the water-repellent hairs).
			_leaf(Vector3(side * leaf_size * 0.5, 0.07, z),
				Vector3(leaf_size * 0.3, 0.05, leaf_size * 0.3), tip_color)
	_root_strands(2, root_length * 0.6, 0.5)


func _build_water_lettuce() -> void:
	# Upright funnel of leaves angled outward, with a dense hanging root mass.
	var n: int = clampi(leaf_count, 5, 8)
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = leaf_size * 0.45
		var leaf := _leaf(Vector3(cos(ang) * r, leaf_size * 0.35, sin(ang) * r),
			Vector3(leaf_size * 0.5, 0.09, leaf_size), _ring_color(i, n))
		# Tilt each leaf up and out so they form a rosette cup.
		leaf.rotation = Vector3(0.0, -ang, 0.55)
	_root_strands(5, root_length, 1.3)


# ---- Save / load ----

func to_state() -> Dictionary:
	return {
		"id": id,
		"pos": SaveHelpers.vec3_to_array(position),
		"morph": morph,
		"leaf_size": leaf_size,
		"leaf_count": leaf_count,
		"root_length": root_length,
		"base_color": SaveHelpers.color_to_array(base_color),
		"tip_color": SaveHelpers.color_to_array(tip_color),
		"spread_rate": spread_rate,
	}


static func _to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]),
			float(a[3]) if a.size() >= 4 else 1.0)
	return Color8(70, 130, 60)
