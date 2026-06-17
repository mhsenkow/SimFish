# Floating surface plant (Floaters v2).
#
# Per-clump ecology: vitality, budding, turions, grazing API, shade radius,
# root biofilm, flowering, and eight morphs. Lives in World._floaters — not
# rooted Plant instances.

extends Node3D
class_name FloatingPlant

const MORPHS: Array[String] = [
	"duckweed", "frogbit", "salvinia", "water_lettuce", "red_root",
	"azolla", "water_hyacinth", "water_spangle",
]

enum BudStage { NONE, SWELL, DETACH }
enum FlowerStage { NONE, BUD, OPEN }

const STATE_VERSION: int = 2

# ---- Genome (FloaterGenome schema) ----
var morph: String = "duckweed"
var leaf_size: float = 0.3
var leaf_count: int = 4
var root_length: float = 0.4
var base_color: Color = Color8(70, 130, 60)
var tip_color: Color = Color8(120, 180, 90)
var spread_rate: float = 1.0
var redroot_response: float = 0.0
var palatability: float = 0.82
var root_biofilm_rate: float = 0.018
var shade_radius: float = 0.35
var co2_independence: float = 0.85
var nitrogen_fixer: float = 0.0
var temp_min: float = 0.38
var temp_max: float = 0.78
var generation: int = 0
var parent_lineage: String = "Founders"
var species_id: String = ""
var plant_name: String = ""
var quilted: bool = false
var wavy: bool = false
var underside_tone: Variant = null
var spin_rate: float = 0.0

# ---- Per-clump runtime ----
var id: String = ""
var vitality: float = 1.0
var age_s: float = 0.0
var root_biofilm: float = 0.0
var root_length_current: float = 0.4
var bud_timer: float = 0.0
var bud_stage: int = BudStage.NONE
var turion_buried: bool = false
var turion_age_s: float = 0.0
var flower_stage: int = FlowerStage.NONE
var linked_parent_id: String = ""
var tether_timer: float = 0.0
var chain_siblings: int = 0
var _pending_bud: Dictionary = {}
var _low_light_ticks: int = 0
var _turion_recovery_ticks: int = 0
var _neighbor_density: float = 0.0
var _decay_sink: float = 0.0
var _visual_dirty: bool = true
var _light_response_t: float = 0.0
var _roots_lod_hidden: bool = false


func init_genome(g: Dictionary) -> void:
	var e: Dictionary = FloaterGenome.enrich(g)
	FloaterGenome.apply_to_floater(self, e)
	if morph == "red_root" and redroot_response < 0.5:
		redroot_response = 1.0
		root_length = clampf(maxf(root_length, 0.6), 0.1, 1.4)
	if morph in ["frogbit", "water_lettuce", "water_hyacinth"]:
		spin_rate = randf_range(0.15, 0.45)
	root_length_current = root_length
	vitality = float(e.get("vitality_max", 1.0))
	age_s = float(g.get("age_s", 0.0))
	if g.has("vitality"):
		vitality = clampf(float(g.vitality), 0.0, 1.0)
	if g.has("root_biofilm"):
		root_biofilm = clampf(float(g.root_biofilm), 0.0, 1.0)
	if g.has("root_length_current"):
		root_length_current = float(g.root_length_current)
	if g.has("bud_stage"):
		bud_stage = int(g.bud_stage)
	if g.has("flower_stage"):
		flower_stage = int(g.flower_stage)
	if g.has("turion_buried"):
		turion_buried = bool(g.turion_buried)
	if g.has("linked_parent_id"):
		linked_parent_id = String(g.linked_parent_id)
	if g.has("generation"):
		generation = int(g.generation)
	if id == "":
		id = "%d_%d" % [Time.get_ticks_msec(), randi()]
	_build()


func get_genome() -> Dictionary:
	return FloaterGenome.from_floater(self)


# Per-clump sim step (10 Hz from World._floater_growth_step).
func tick(dt: float, world: Node, sim: Node) -> void:
	var dl: float = 1.0
	if sim != null and sim.has_method("daylight"):
		dl = float(sim.daylight())
	var warmth: float = 0.55
	if world != null and world.has_method("surface_warmth_at"):
		warmth = float(world.surface_warmth_at(global_position))
	elif world != null and world.has_method("effective_warmth_at"):
		warmth = float(world.effective_warmth_at(global_position))
	if turion_buried:
		visible = false
		turion_age_s += dt
		# Dormant turions wait out a bad spell; they resurface when light returns.
		if dl > 0.45 and warmth >= temp_min - 0.04:
			_turion_recovery_ticks += 1
		else:
			_turion_recovery_ticks = maxi(0, _turion_recovery_ticks - 2)
		if _turion_recovery_ticks > 12:
			turion_buried = false
			turion_age_s = 0.0
			visible = true
			vitality = maxf(vitality, 0.5)
			_turion_recovery_ticks = 0
			_low_light_ticks = 0
			_visual_dirty = true
			_update_root_lod()
		elif turion_age_s > 90.0:
			# Long-buried turions dissolve — keeps invisible clumps from piling up.
			vitality = 0.0
		return
	age_s += dt
	var nutrients: float = 0.6
	var nitrate: float = 0.5
	if sim != null:
		if sim.get("water_chemistry") != null:
			nitrate = clampf(float(sim.water_chemistry.nitrate), 0.0, 3.0) / 3.0
		# Nutrient supply: floaters draw dissolved nitrate (which they strip)
		# plus a little from a bloom, over a healthy floor. Previously this was
		# driven purely by bloom_intensity, so once plants/grazers suppressed
		# the bloom the floaters slowly starved + collapsed — keep a floor so a
		# clean, well-lit tank still supports a stable surface mat.
		nutrients = 0.5 + 0.25 * nitrate \
			+ 0.25 * clampf(float(sim.get("bloom_intensity")), 0.0, 1.0)
	# Temperature dieback (#18) — only when meaningfully out of range.
	if warmth < temp_min:
		vitality -= dt * 0.035 * (temp_min - warmth) / maxf(0.06, temp_min)
	elif warmth > temp_max:
		vitality -= dt * 0.035 * (warmth - temp_max) / maxf(0.06, 1.0 - temp_max)
	# Light + nutrients drive vitality (#11). Gain is strong enough that a
	# decently-lit floater nets positive across a day; baseline respiration is
	# gentle so a single dark night doesn't crash a healthy mat.
	var light_gain: float = dl * nutrients * (0.5 + co2_independence * 0.5)
	vitality += dt * (light_gain * 0.085 - 0.009)
	# Self-shading (#16) — deeply stacked floaters slow each other, but crowding
	# only NUDGES vitality down (it shouldn't spiral a clump to death + cull at
	# the glass edge where they pile up).
	if _neighbor_density > 0.55:
		vitality -= dt * (_neighbor_density - 0.55) * 0.04
	vitality = clampf(vitality, 0.0, 1.0)
	# Root plasticity (#19)
	var root_target: float = lerpf(root_length * 0.6, root_length * 1.25, 1.0 - nitrate)
	root_length_current = lerpf(root_length_current, root_target, dt * 0.12)
	# Root biofilm (#33)
	root_biofilm = clampf(root_biofilm + root_biofilm_rate * dt * (0.4 + nitrate * 0.6), 0.0, 1.0)
	# Budding (#12-13)
	_tick_budding(dt, dl, nutrients)
	# Turion sink (#14) — requires SUSTAINED low light + cold, not a single
	# dark frame, so turions only form after a real adverse spell. Recovers
	# twice as fast as it accrues so a brief cloudy patch doesn't sink the mat.
	if dl < 0.2 and warmth < temp_min + 0.05 and vitality < 0.35:
		_low_light_ticks += 1
	else:
		_low_light_ticks = maxi(0, _low_light_ticks - 2)
	if _low_light_ticks > 18 and not turion_buried:  # ~54s sustained adverse spell
		_request_turion(world)
		_low_light_ticks = 0
	# Flowering (#42)
	_tick_flowering(dl)
	# Size variety (#48)
	if age_s < 120.0:
		var grow: float = lerpf(0.88, 1.0, age_s / 120.0)
		scale = Vector3.ONE * grow
	# Decay visual (#49)
	if vitality < 0.25:
		_decay_sink = lerpf(_decay_sink, 0.02, dt * 2.0)
		rotation.x = lerpf(rotation.x, 0.25, dt)
	else:
		_decay_sink = lerpf(_decay_sink, 0.0, dt * 3.0)
	position.y += _decay_sink * dt * -1.0
	_apply_vitality_visual(dl, world)
	_light_response_t += dt
	if _visual_dirty or _light_response_t >= 6.0:
		_light_response_t = 0.0
		tick_light_response(dl, world)
	# Allelopathy at root tips (#25)
	if world != null and sim != null and sim.get("substrate") != null and root_length_current > 0.2:
		var tips: Array = root_world_positions()
		for tp in tips:
			sim.substrate.add_allelochemical_at(tp, dt * 0.015)


func set_neighbor_density(d: float) -> void:
	_neighbor_density = clampf(d, 0.0, 1.0)
	_update_root_lod()


func is_surface_active() -> bool:
	return not turion_buried and vitality > 0.02


func _update_root_lod() -> void:
	# Dense mats + tiny morphs don't need hanging root columns — they read as
	# white pillars and cost a draw call each.
	var hide: bool = turion_buried
	if not hide:
		if morph in ["duckweed", "azolla"]:
			hide = _neighbor_density > 0.12
		else:
			hide = _neighbor_density > 0.42
	if hide == _roots_lod_hidden:
		return
	_roots_lod_hidden = hide
	for c in get_children():
		if c is MeshInstance3D and String(c.name).begins_with("root"):
			(c as MeshInstance3D).visible = not hide


func _tick_budding(dt: float, dl: float, nutrients: float) -> void:
	if bud_stage == BudStage.DETACH:
		return
	if vitality < 0.45 or dl < 0.3:
		return
	bud_timer += dt
	match bud_stage:
		BudStage.NONE:
			if bud_timer > 8.0 / spread_rate and randf() < dt * spread_rate * nutrients * dl:
				bud_stage = BudStage.SWELL
				bud_timer = 0.0
				_visual_dirty = true
		BudStage.SWELL:
			if bud_timer > 2.5:
				bud_stage = BudStage.DETACH
				var ang: float = randf() * TAU
				var r: float = leaf_size * (0.55 if morph == "duckweed" else 0.85)
				_pending_bud = {
					"genome": get_genome(),
					"offset": Vector3(cos(ang) * r, 0.0, sin(ang) * r),
					"parent_id": id,
					"chain": mini(chain_siblings + 1, 3),
				}
				bud_timer = 0.0
				bud_stage = BudStage.NONE


func consume_pending_bud() -> Dictionary:
	var out: Dictionary = _pending_bud.duplicate(true)
	_pending_bud.clear()
	return out


func has_pending_bud() -> bool:
	return not _pending_bud.is_empty()


func _request_turion(world: Node) -> void:
	turion_buried = true
	turion_age_s = 0.0
	visible = false
	_update_root_lod()
	if world == null:
		return
	var sim: Node = world.get("sim")
	if sim != null and sim.get("substrate") != null:
		sim.substrate.add_seed_bank_at(global_position + Vector3(0, -0.5, 0), 0.4)


func _tick_flowering(dl: float) -> void:
	if morph not in ["frogbit", "water_lettuce", "water_hyacinth"]:
		return
	if vitality > 0.7 and dl > 0.65:
		if flower_stage == FlowerStage.NONE and randf() < 0.002:
			flower_stage = FlowerStage.BUD
			_visual_dirty = true
		elif flower_stage == FlowerStage.BUD and randf() < 0.004:
			flower_stage = FlowerStage.OPEN
			_visual_dirty = true
	elif dl < 0.2:
		flower_stage = FlowerStage.NONE


func tick_light_response(daylight: float, world: Node = null) -> void:
	# Tannin tint (#28)
	var tannin: float = 0.0
	if world != null and world.get("tannins") != null:
		tannin = clampf(float(world.tannins), 0.0, 1.0)
	var leaf_tint: Color = base_color.lerp(Color8(45, 75, 55), tannin * 0.35)
	for c in get_children():
		if c is MeshInstance3D and String(c.name).begins_with("leaf"):
			var mi: MeshInstance3D = c
			if mi.material_override is ShaderMaterial:
				var col: Color = leaf_tint
				if redroot_response > 0.0 and String(c.name).begins_with("root"):
					var redness: float = clampf(redroot_response * daylight, 0.0, 1.0)
					col = base_color.darkened(0.35).lerp(Color(0.78, 0.28, 0.30), redness * 0.85)
				else:
					col = _edge_center_color(mi.position, leaf_tint)
				mi.material_override = VoxelMat.make_foliage(col)
		elif c is MeshInstance3D and String(c.name).begins_with("root"):
			var mi2: MeshInstance3D = c
			if mi2.material_override is ShaderMaterial:
				var redness2: float = clampf(redroot_response * daylight, 0.0, 1.0) if redroot_response > 0.0 else 0.0
				var root_col: Color = base_color.darkened(0.35).lerp(Color(0.78, 0.28, 0.30), redness2 * 0.85)
				var mat: ShaderMaterial = VoxelMat.make_foliage(root_col)
				mat.set_shader_parameter("sss_strength", 0.35)
				mi2.material_override = mat


func _edge_center_color(local_pos: Vector3, base: Color) -> Color:
	# Seasonal edge bronze (#50) — center bronze, edge green
	var edge: float = clampf(local_pos.length() / maxf(leaf_size, 0.1), 0.0, 1.0)
	var bronze: Color = tip_color.lerp(Color8(140, 95, 45), 0.55)
	return bronze.lerp(base, edge * (1.0 - _neighbor_density * 0.5))


func _apply_vitality_visual(dl: float, _world: Node) -> void:
	if not _visual_dirty and vitality > 0.25:
		return
	_visual_dirty = false
	var health: float = clampf(vitality, 0.0, 1.0)
	var brown: Color = Color8(95, 70, 40)
	var tint: Color = base_color.lerp(brown, (1.0 - health) * 0.65)
	scale = Vector3.ONE * lerpf(0.75, 1.0, health) * lerpf(0.88, 1.0, minf(age_s / 120.0, 1.0))
	if _visual_dirty or vitality < 0.3:
		_recolor_leaves(tint, dl)


func _recolor_leaves(tint: Color, _dl: float) -> void:
	for c in get_children():
		if c is MeshInstance3D and String(c.name).begins_with("leaf"):
			(c as MeshInstance3D).material_override = VoxelMat.make_foliage(
				_edge_center_color(c.position, tint))


# ---- Interaction API ----

func nibble(amount: int) -> int:
	if turion_buried or vitality <= 0.05:
		return 0
	var pal: float = graze_palatability()
	if randf() > pal:
		return 0
	var taken: int = mini(amount, maxi(1, int(leaf_count * vitality)))
	vitality -= float(taken) * 0.08
	leaf_count = maxi(1, leaf_count - taken)
	if vitality < 0.08 or leaf_count <= 0:
		vitality = 0.0
	_visual_dirty = true
	return taken


func biomass() -> float:
	return float(leaf_count) * leaf_size * vitality


func graze_palatability() -> float:
	return clampf(palatability * vitality, 0.05, 1.0)


func effective_shade_radius() -> float:
	return shade_radius * lerpf(0.7, 1.15, leaf_size / 0.5)


func root_world_positions() -> Array:
	var out: Array = []
	var n: int = 3
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var rx: float = cos(ang) * leaf_size * 0.2
		var rz: float = sin(ang) * leaf_size * 0.2
		out.append(global_position + Vector3(rx, -root_length_current * 0.5, rz))
	return out


func is_fry_cover() -> bool:
	return root_length_current > 0.4 and morph in ["frogbit", "water_lettuce", "red_root", "water_hyacinth"]


func surface_sink() -> float:
	return _decay_sink


func should_remove() -> bool:
	return vitality <= 0.02


# ---- Mesh construction ----

func _build() -> void:
	for c in get_children():
		c.queue_free()
	match morph:
		"frogbit": _build_frogbit()
		"salvinia": _build_salvinia()
		"water_lettuce": _build_water_lettuce()
		"red_root": _build_red_root()
		"azolla": _build_azolla()
		"water_hyacinth": _build_water_hyacinth()
		"water_spangle": _build_water_spangle()
		_: _build_duckweed()
	if flower_stage != FlowerStage.NONE:
		_add_flower_voxel()
	_visual_dirty = true
	_update_root_lod()


func _ring_color(i: int, n: int) -> Color:
	return base_color.lerp(tip_color, float(i) / float(maxi(1, n - 1)))


func _leaf_jitter(sz: Vector3) -> Vector3:
	if not quilted and not wavy:
		return sz
	return Vector3(
		sz.x * randf_range(0.92, 1.08),
		sz.y,
		sz.z * randf_range(0.92, 1.08),
	)


func _leaf(pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO,
		underside: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sz: Vector3 = _leaf_jitter(size)
	mi.mesh = VoxelMat.get_box(sz)
	var col: Color = color
	if underside and underside_tone is Color:
		col = (underside_tone as Color).lerp(color, 0.35)
	elif underside:
		col = color.darkened(0.25)
	mi.material_override = VoxelMat.make_foliage(col)
	add_child(mi)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.name = "leaf_%d" % get_child_count()
	# Wet meniscus rim (#45)
	if absf(pos.y) < 0.05:
		var rim := MeshInstance3D.new()
		rim.mesh = VoxelMat.get_box(Vector3(sz.x * 1.02, 0.03, sz.z * 1.02))
		rim.material_override = VoxelMat.make(Color8(200, 235, 245))
		rim.position = pos + Vector3(0, -0.02, 0)
		rim.name = "meniscus"
		add_child(rim)
	return mi


func _root_strands(count: int, length: float, spread: float = 1.0) -> void:
	var root_color: Color = base_color.darkened(0.45)
	for i in count:
		var ang: float = float(i) / float(maxi(1, count)) * TAU
		var rx: float = cos(ang) * leaf_size * 0.18 * spread
		var rz: float = sin(ang) * leaf_size * 0.18 * spread
		var seg_len: float = length * (0.7 + 0.5 * float((i % 3)) / 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMat.get_box(Vector3(0.05, seg_len, 0.05))
		var mat: ShaderMaterial = VoxelMat.make_foliage(root_color)
		mat.set_shader_parameter("sss_strength", 0.42)
		mi.material_override = mat
		mi.name = "root_%d" % i
		add_child(mi)
		mi.position = Vector3(rx, -seg_len * 0.5 - 0.02, rz)


func _build_duckweed() -> void:
	var n: int = clampi(leaf_count, 1, 3)
	var s: float = leaf_size * 0.6
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = 0.0 if n == 1 else s * 0.55
		_leaf(Vector3(cos(ang) * r, 0.0, sin(ang) * r), Vector3(s, 0.06, s), _ring_color(i, n))
	_root_strands(1, root_length_current * 0.5, 0.4)
	if bud_stage == BudStage.SWELL:
		_leaf(Vector3(leaf_size * 0.3, 0.04, 0.0), Vector3(s * 0.5, 0.05, s * 0.5), tip_color)


func _build_frogbit() -> void:
	var n: int = clampi(leaf_count, 5, 8)
	_leaf(Vector3.ZERO, Vector3(leaf_size * 0.55, 0.07, leaf_size * 0.55), tip_color)
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = leaf_size * 0.7
		_leaf(Vector3(cos(ang) * r, 0.02, sin(ang) * r),
			Vector3(leaf_size, 0.08, leaf_size * 0.85), _ring_color(i, n),
			Vector3(0, ang, 0), true)
	_root_strands(4, root_length_current, 1.0)


func _build_salvinia() -> void:
	var pairs: int = clampi(int(round(float(leaf_count) / 2.0)), 2, 4)
	for i in pairs:
		var z: float = (float(i) - float(pairs) * 0.5) * leaf_size * 0.95
		var col: Color = _ring_color(i, pairs)
		for side in [-1.0, 1.0]:
			_leaf(Vector3(side * leaf_size * 0.5, 0.02, z),
				Vector3(leaf_size * 0.95, 0.07, leaf_size * 0.7), col)
			# Water-bead hairs (#43)
			var bump := MeshInstance3D.new()
			bump.mesh = VoxelMat.get_box(Vector3(leaf_size * 0.3, 0.05, leaf_size * 0.3))
			var bmat: ShaderMaterial = VoxelMat.make_foliage(tip_color.lightened(0.25))
			bump.material_override = bmat
			bump.position = Vector3(side * leaf_size * 0.5, 0.08, z)
			bump.name = "bead"
			add_child(bump)
	_root_strands(2, root_length_current * 0.6, 0.5)


func _build_water_lettuce() -> void:
	var n: int = clampi(leaf_count, 5, 8)
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = leaf_size * 0.45
		var leaf := _leaf(Vector3(cos(ang) * r, leaf_size * 0.35, sin(ang) * r),
			Vector3(leaf_size * 0.5, 0.09, leaf_size), _ring_color(i, n), Vector3.ZERO, true)
		leaf.rotation = Vector3(0.0, -ang, 0.55)
	_root_strands(5, root_length_current, 1.3)


func _build_red_root() -> void:
	var n: int = clampi(leaf_count, 2, 5)
	for i in n:
		var ang: float = float(i) / float(n) * TAU + randf_range(-0.2, 0.2)
		var r: float = leaf_size * 0.6
		_leaf(Vector3(cos(ang) * r, 0.0, sin(ang) * r),
			Vector3(leaf_size * 0.9, 0.06, leaf_size * 0.9), _ring_color(i, n))
	var rn: int = 3 + (1 if redroot_response > 0.5 else 0)
	var root_color: Color = base_color.darkened(0.35)
	for i in rn:
		var seg_y: float = -root_length_current * 0.5 - float(i) * root_length_current * 0.18
		var rmi := MeshInstance3D.new()
		rmi.mesh = VoxelMat.get_box(Vector3(0.06, root_length_current * 0.22, 0.06))
		var rmat: ShaderMaterial = VoxelMat.make_foliage(root_color)
		rmat.set_shader_parameter("sss_strength", 0.38)
		rmi.material_override = rmat
		rmi.name = "root_%d" % i
		add_child(rmi)
		rmi.position = Vector3(
			randf_range(-leaf_size * 0.3, leaf_size * 0.3),
			seg_y,
			randf_range(-leaf_size * 0.3, leaf_size * 0.3),
		)


func _build_azolla() -> void:
	var n: int = clampi(leaf_count, 3, 6)
	var s: float = leaf_size * 0.55
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		_leaf(Vector3(cos(ang) * s * 0.4, 0.0, sin(ang) * s * 0.4),
			Vector3(s, 0.05, s * 0.8), Color8(90, 140, 70).lerp(Color8(180, 60, 55), 0.35))
	_root_strands(1, root_length_current * 0.35, 0.3)


func _build_water_hyacinth() -> void:
	var n: int = clampi(leaf_count, 4, 7)
	for i in n:
		var ang: float = float(i) / float(n) * TAU
		var r: float = leaf_size * 0.55
		var leaf := _leaf(Vector3(cos(ang) * r, leaf_size * 0.2, sin(ang) * r),
			Vector3(leaf_size * 0.65, 0.1, leaf_size * 0.55), _ring_color(i, n))
		leaf.rotation = Vector3(0.15, -ang, 0.4)
	_root_strands(6, root_length_current * 1.1, 1.2)
	# Bulbous base
	_leaf(Vector3.ZERO, Vector3(leaf_size * 0.35, leaf_size * 0.25, leaf_size * 0.35), base_color.darkened(0.1))


func _build_water_spangle() -> void:
	var pairs: int = clampi(int(round(float(leaf_count) / 2.0)), 2, 5)
	for i in pairs:
		var z: float = (float(i) - float(pairs) * 0.5) * leaf_size * 0.8
		for side in [-1.0, 1.0]:
			_leaf(Vector3(side * leaf_size * 0.45, 0.01, z),
				Vector3(leaf_size * 0.85, 0.06, leaf_size * 0.55), _ring_color(i, pairs))
	_root_strands(2, root_length_current * 0.45, 0.45)


func _add_flower_voxel() -> void:
	var fi := MeshInstance3D.new()
	var fsz: float = 0.08 if flower_stage == FlowerStage.BUD else 0.12
	fi.mesh = VoxelMat.get_box(Vector3(fsz, fsz * 1.2, fsz))
	fi.material_override = VoxelMat.make_foliage(
		Color8(240, 200, 220) if flower_stage == FlowerStage.OPEN else Color8(180, 140, 90))
	fi.position = Vector3(0, leaf_size * 0.25, 0)
	fi.name = "flower"
	add_child(fi)


# ---- Save / load v2 ----

func to_state() -> Dictionary:
	return {
		"floater_version": STATE_VERSION,
		"id": id,
		"pos": SaveHelpers.vec3_to_array(position),
		"rot_y": rotation.y,
		"morph": morph,
		"leaf_size": leaf_size,
		"leaf_count": leaf_count,
		"root_length": root_length,
		"base_color": SaveHelpers.color_to_array(base_color),
		"tip_color": SaveHelpers.color_to_array(tip_color),
		"spread_rate": spread_rate,
		"redroot_response": redroot_response,
		"palatability": palatability,
		"root_biofilm_rate": root_biofilm_rate,
		"shade_radius": shade_radius,
		"co2_independence": co2_independence,
		"nitrogen_fixer": nitrogen_fixer,
		"temp_min": temp_min,
		"temp_max": temp_max,
		"generation": generation,
		"parent_lineage": parent_lineage,
		"species_id": species_id,
		"plant_name": plant_name,
		"vitality": vitality,
		"age_s": age_s,
		"root_biofilm": root_biofilm,
		"root_length_current": root_length_current,
		"bud_stage": bud_stage,
		"flower_stage": flower_stage,
		"turion_buried": turion_buried,
		"linked_parent_id": linked_parent_id,
		"chain_siblings": chain_siblings,
	}


static func _to_color(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]),
			float(a[3]) if a.size() >= 4 else 1.0)
	return Color8(70, 130, 60)
