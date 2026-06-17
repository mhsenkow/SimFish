# Coral. A photosynthetic sessile organism that grows like a plant but
# in coral-specific shapes. Inherits Plant for free decay / grazing /
# growth-tick / substrate-consumption + voxel tracking; overrides only
# the body-building part of _grow_one().
#
# Form registry: world._spawn_initial_corals uses coral_form strings
# "dome", "branching", "anemone", "clam", "sponge" on this class.
# Freshwater filter clams live in clam.gd separately — do not confuse
# reef "clam" sessile forms here with those bivalves.
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

# Freshwater sessile analogs (hydra, sponge, marimo, riccia) reuse Coral
# geometry but are not reef zooxanthellae hosts — no bleaching mechanics.
const FRESHWATER_FORMS: Array[String] = [
	"hydra_fresh", "sponge_fresh", "marimo", "riccia",
]


func is_reef_coral() -> bool:
	return coral_form not in FRESHWATER_FORMS


# L-system branching state for staghorn fern coral
var _fern_tips: Array = []
# Precalculated positions for the Gyroid reaction-diffusion brain coral dome
var _brain_positions: Array[Vector3] = []
var _anemone_tentacles: Array[Node3D] = []
var _anemone_tip_voxels: Array[Node3D] = []
var _hydra_tentacles: Array[Node3D] = []
var _clam_shell_parts: Array[Node3D] = []
var _sessile_phase: float = 0.0
var _topology_seed: float = 0.0

# Polyp tips — bright voxels at the growing edge of each form. We pulse
# them open/closed in _process so the coral has the rhythmic respiration
# you see on a real reef (zooxanthellae extending tentacles, retracting
# at rest). One entry per tip voxel; we read the original albedo + scale
# from each entry so the pulse rides on top of grow-time appearance.
var _polyp_tips: Array = []  # Array[{node, phase, base_scale, base_albedo}]

# Bleaching — when warmth runs too hot or O2 crashes, zooxanthellae are
# expelled and the coral pales toward bone white. Recovers if conditions
# return to safe within a few minutes. Cosmetic + growth penalty; doesn't
# kill the coral outright (plant decay handles real death).
var _bleach_level: float = 0.0
var _last_bleach_applied: float = 0.0
var _bleach_event_band: int = -1
var _bleach_recovery_logged: bool = false
# Tentacle / polyp extension state. 1.0 = corals actively feeding, fully
# extended; 0.0 = retracted (stressed, bleached, or low-O2). Lerps toward
# the target derived in tick() so the visual extension/retraction reads
# as a slow biological response rather than an instant pose change.
var _feeding_extension: float = 0.5
var _base_growth_rate: float = 0.0


func _build_initial_roots() -> void:
	# No-op: corals cement to the substrate, they don't extend roots.
	pass


func _save_kind() -> String:
	return "coral"


func to_save_dict() -> Dictionary:
	var d: Dictionary = super.to_save_dict()
	d["coral_form"] = coral_form
	d["tip_color"] = SaveHelpers.color_to_array(tip_color)
	d["bleach_level"] = _bleach_level
	return d


func apply_save_dict(d: Dictionary) -> void:
	coral_form = String(d.get("coral_form", coral_form))
	tip_color = SaveHelpers.array_to_color(d.get("tip_color", []), tip_color)
	_bleach_level = clampf(float(d.get("bleach_level", 0.0)), 0.0, 1.0)
	super.apply_save_dict(d)


func _ready() -> void:
	super._ready()
	_sessile_phase = randf() * TAU
	_topology_seed = randf() * TAU
	uses_flowering = false
	emergent_growth = true
	_base_growth_rate = growth_rate


func _register_polyp_tip(node: MeshInstance3D, base_scale: float = 1.0) -> void:
	# Track a voxel as a respirating polyp tip. Phase staggered by index
	# so a colony doesn't pulse in unison.
	if node == null:
		return
	var entry: Dictionary = {
		"node": node,
		"phase": float(_polyp_tips.size()) * 0.41 + randf() * 0.6,
		"base_scale": base_scale,
	}
	_polyp_tips.append(entry)


func _spawn_canopy_propagule() -> void:
	if _seeds_cast_this_cycle >= 2 or randf() > 0.45:
		return
	if _cast_seed():
		_seeds_cast_this_cycle += 1


func _grow_one() -> bool:
	if current_height >= max_height:
		return false
	if emergent_growth and _at_surface_cap():
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
		"anemone":
			_grow_anemone()
		"sponge":
			_grow_sponge(false)
		"sponge_fresh":
			_grow_sponge(true)
		"clam":
			_grow_clam()
		"hydra_fresh":
			_grow_hydra_fresh()
		"marimo":
			_grow_marimo()
		"riccia":
			_grow_riccia()
		_:
			_grow_dome()
	if generation >= 2 and randf() < clampf(0.08 + float(generation) * 0.015, 0.08, 0.25):
		_add_architecture_accent()
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
	# Top half of the dome reads as live polyp surface — pulse those.
	if rel > 0.55:
		_register_polyp_tip(mi)


# ---- Marimo moss ball ----
# A spherical algae colony (real Aegagropila linnaei). Voxels distribute
# over a near-perfect sphere using golden-angle spiral mapping. Tiny —
# adult marimo are 3–5 cm across in real life — so we cap max_height
# low to keep the ball compact. Almost immortal in real tanks: high
# nutrient-uptake rate, very slow growth, no flowering, no seeding.
func _grow_marimo() -> void:
	var idx: int = current_height
	# Golden-angle Fibonacci sphere — produces an even point distribution
	# over the unit sphere as `idx` grows. Each voxel sits at a different
	# spherical coordinate.
	var n: float = float(maxi(1, max_height))
	var t: float = (float(idx) + 0.5) / n
	# y maps from 1 to -1 over the population.
	var y: float = 1.0 - 2.0 * t
	var r_ring: float = sqrt(maxf(0.0, 1.0 - y * y))
	var theta: float = float(idx) * GOLDEN_ANGLE
	var R: float = VOXEL_SIZE * 0.65
	var px: float = cos(theta) * r_ring * R
	var pz: float = sin(theta) * r_ring * R
	var py: float = y * R + R * 0.95  # lift the ball so it sits on the substrate
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	# Tight band of greens — marimo are a single uniform mossy green
	# without the brighter tip color. Pick from the middle of the ramp.
	var col: Color = ramp[clampi(2 + (idx % 3), 0, ramp.size() - 1)]
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.34, VOXEL_SIZE * 0.34, VOXEL_SIZE * 0.34))
	mi.material_override = VoxelMat.make_foliage(col)
	mi.position = Vector3(px, py, pz)
	add_child(mi)
	voxels.append(mi)
	# Every voxel reads as a polyp surface — pulse the whole sphere
	# subtly so it visibly breathes.
	if rng_chance_for_polyp_register(idx):
		_register_polyp_tip(mi)


# Sparse polyp-tip registration for marimo so the whole ball doesn't
# pulse in lockstep — only a fraction of the voxels respire visibly.
func rng_chance_for_polyp_register(idx: int) -> bool:
	return (idx % 5) == 0


# ---- Riccia (pearling carpet) ----
# A bright lime-green liverwort carpet that produces dramatic O2
# pearling under bright light. Real Riccia fluitans forms dense
# carpets attached to substrate or driftwood; bubbles cling to it.
# We force-enable the inherited Plant pearling system so every riccia
# patch actually pearls (the default 1-in-8 eligible rate would make
# this read as a regular carpet).
func _grow_riccia() -> void:
	# Phyllotaxis distribution on a flat-ish dome — the carpet is wider
	# than tall, and bunches up in the middle.
	var idx: int = current_height
	var theta: float = float(idx) * GOLDEN_ANGLE
	var r: float = minf(VOXEL_SIZE * 0.26 * sqrt(float(idx) + 1.0), VOXEL_SIZE * 1.4)
	# Mostly flat — y only varies by a tiny amount.
	var y: float = VOXEL_SIZE * (0.18 + sin(float(idx) * 0.7) * 0.04)
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	# Vivid lime — riccia is one of the brightest greens in a planted
	# tank. Pick from the top of the ramp.
	var col: Color = ramp[clampi(3 + (idx % 3), 0, ramp.size() - 1)]
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(Vector3(
		VOXEL_SIZE * 0.30, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.30))
	mi.material_override = VoxelMat.make_foliage(col)
	mi.position = Vector3(cos(theta) * r, y, sin(theta) * r)
	add_child(mi)
	voxels.append(mi)
	# Every voxel is a live pearling site — riccia is famous for
	# producing dramatic O2 bubble columns.
	_register_polyp_tip(mi)
	# Force pearling on every riccia carpet. Plant.gd defaults
	# `_pearling_eligible` to (instance_id % 8 == 0); we override to
	# true so riccia visibly bubbles even in small populations.
	_pearling_eligible = true


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
	# Outer Gyroid ridges = live polyp surface — pulse the outer shell.
	if rel > 0.55:
		_register_polyp_tip(mi)


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
		var base_ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
		base_vox.material_override = VoxelMat.make_foliage(base_ramp[0])
		base_vox.position = Vector3.ZERO
		add_child(base_vox)
		voxels.append(base_vox)
		return

	# Pop the oldest active tip to grow it
	var tip: Dictionary = _fern_tips.pop_front()
	var new_pos: Vector3 = tip.pos + tip.dir * VOXEL_SIZE * 0.75
	
	# Determine color based on generation
	var grow_ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var c: Color = grow_ramp[clampi(1 + tip.gen, 0, grow_ramp.size() - 1)]
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
	# Highest-gen tip voxels are the youngest fronds with active polyps.
	if tip.gen >= 2:
		_register_polyp_tip(mi)
	
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
	var stem_color: Color = ramp[clampi(2 + int(idx / 4.0), 0, ramp.size() - 1)]
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
		_register_polyp_tip(tip)


func _spawn_side_branch(idx: int, ramp: Array) -> void:
	var theta: float = randf() * TAU
	var dx: float = cos(theta)
	var dz: float = sin(theta)
	# Branch tilts upward slightly so it angles away from the stem.
	var dy_step: float = 0.5
	var base_y: float = idx * VOXEL_SIZE * 0.85
	for j in BRANCH_LENGTH:
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
		# Outermost side-branch voxel is the live polyp tip.
		if j == BRANCH_LENGTH - 1:
			_register_polyp_tip(bv)


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
		# Topmost feathers are the actively-feeding polyps.
		if rel > 0.55:
			_register_polyp_tip(fv)


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
	# All disc polyps face up and respire — pulse them.
	_register_polyp_tip(p)


func _make_coral_voxel(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMat.get_box(size)
	mi.material_override = VoxelMat.make_foliage(col)
	mi.position = pos
	add_child(mi)
	voxels.append(mi)
	return mi


func _add_architecture_accent() -> void:
	# Extra lineage ornament modules so mature coral lineages become visibly
	# more elaborate over generations without requiring new genome keys.
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var accent: Color = ramp[ramp.size() - 1]
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ang: float = _topology_seed + float(current_height) * 1.3
	var r: float = VOXEL_SIZE * lerpf(0.30, 1.25, clampf(rel, 0.0, 1.0))
	var base_pos := Vector3(cos(ang) * r, VOXEL_SIZE * (0.25 + rel * 0.95), sin(ang) * r * 0.85)
	match coral_form:
		"plate", "clam":
			_make_coral_voxel(base_pos + Vector3(0, VOXEL_SIZE * 0.05, 0),
				Vector3(VOXEL_SIZE * 0.26, VOXEL_SIZE * 0.06, VOXEL_SIZE * 0.26),
				accent.lightened(0.12))
		"sponge", "sponge_fresh":
			_make_coral_voxel(base_pos,
				Vector3(VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.18),
				accent.lightened(0.06))
		_:
			for x_side in [-1.0, 1.0]:
				_make_coral_voxel(
					base_pos + Vector3(x_side * VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.05, 0),
					Vector3(VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.24, VOXEL_SIZE * 0.10),
					accent.lightened(0.10))


func _grow_anemone() -> void:
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	if current_height < 2:
		_make_coral_voxel(
			Vector3(0.0, current_height * VOXEL_SIZE * 0.35, 0.0),
			Vector3(VOXEL_SIZE * 0.65, VOXEL_SIZE * 0.32, VOXEL_SIZE * 0.65),
			ramp[1])
		return
	var tentacle_count: int = 8
	var ring: float = VOXEL_SIZE * (0.35 + rel * 0.55)
	var y: float = VOXEL_SIZE * (0.55 + rel * 1.35)
	for i in tentacle_count:
		var a: float = float(i) / float(tentacle_count) * TAU + rel * 0.35
		var body: MeshInstance3D = _make_coral_voxel(
			Vector3(cos(a) * ring, y, sin(a) * ring),
			Vector3(VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.52, VOXEL_SIZE * 0.18),
			ramp[clampi(2 + i % 3, 0, ramp.size() - 1)])
		body.set_meta("anemone_phase", float(i) * 0.79 + rel * 0.4)
		body.set_meta("anemone_outward", Vector3(cos(a), 0.0, sin(a)))
		_anemone_tentacles.append(body)
		if rel > 0.72:
			var tip: MeshInstance3D = _make_coral_voxel(
				body.position + Vector3(0.0, VOXEL_SIZE * 0.33, 0.0),
				Vector3(VOXEL_SIZE * 0.14, VOXEL_SIZE * 0.14, VOXEL_SIZE * 0.14),
				tip_color)
			body.set_meta("tip_ref", tip)
			_anemone_tip_voxels.append(tip)


func _grow_hydra_fresh() -> void:
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	if current_height < 2:
		_make_coral_voxel(
			Vector3(0.0, current_height * VOXEL_SIZE * 0.32, 0.0),
			Vector3(VOXEL_SIZE * 0.42, VOXEL_SIZE * 0.36, VOXEL_SIZE * 0.42),
			ramp[1])
		return
	var count: int = 6
	var y: float = VOXEL_SIZE * (0.35 + rel * 1.2)
	for i in count:
		var a: float = float(i) / float(count) * TAU + rel * 0.6
		var tent: MeshInstance3D = _make_coral_voxel(
			Vector3(cos(a) * VOXEL_SIZE * 0.22, y + VOXEL_SIZE * 0.18, sin(a) * VOXEL_SIZE * 0.22),
			Vector3(VOXEL_SIZE * 0.12, VOXEL_SIZE * 0.45, VOXEL_SIZE * 0.12),
			ramp[clampi(3 + (i % 2), 0, ramp.size() - 1)])
		_hydra_tentacles.append(tent)


func _grow_sponge(is_fresh: bool) -> void:
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	var ramp: Array = ramp_override if ramp_override.size() == 6 else PLANT_RAMP
	var radius: float = VOXEL_SIZE * (0.42 + rel * 0.32)
	var y: float = current_height * VOXEL_SIZE * 0.42
	for j in 2:
		var ang: float = _topology_seed + float(current_height * 2 + j) * 1.9
		var offset := Vector3(cos(ang) * radius * 0.45, 0.0, sin(ang) * radius * 0.45)
		_make_coral_voxel(
			Vector3(offset.x, y + j * VOXEL_SIZE * 0.18, offset.z),
			Vector3(VOXEL_SIZE * (0.26 + rel * 0.12), VOXEL_SIZE * 0.46, VOXEL_SIZE * (0.26 + rel * 0.12)),
			ramp[clampi(1 + j + int(rel * 3.0), 0, ramp.size() - 1)])
	# Porous oscula — dark 1-voxel pits on the sponge surface.
	var pit_col: Color = (ramp[0] if ramp.size() > 0 else Color8(40, 55, 48)).darkened(0.42)
	if is_fresh:
		pit_col = pit_col.lightened(0.06)
	if current_height > 2 and current_height % 3 == 0:
		_make_coral_voxel(
			Vector3(0.0, y + VOXEL_SIZE * 0.26, 0.0),
			Vector3(VOXEL_SIZE * 0.12, VOXEL_SIZE * 0.12, VOXEL_SIZE * 0.12),
			pit_col)
	if current_height > 4:
		for k in 2:
			var pit_ang: float = _topology_seed + float(current_height + k) * 2.7
			var pit_r: float = radius * 0.55
			_make_coral_voxel(
				Vector3(cos(pit_ang) * pit_r, y + VOXEL_SIZE * 0.18, sin(pit_ang) * pit_r),
				Vector3(VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.10),
				pit_col.darkened(0.08))


func _grow_clam() -> void:
	var rel: float = float(current_height) / float(maxi(1, max_height - 1))
	if current_height < 1:
		_make_coral_voxel(
			Vector3(0.0, 0.0, 0.0),
			Vector3(VOXEL_SIZE * 0.8, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.65),
			Color8(82, 70, 88))
		return
	var shell_col: Color = (ramp_override if ramp_override.size() == 6 else PLANT_RAMP)[clampi(2 + int(rel * 2.0), 0, 5)]
	var hinge_y: float = VOXEL_SIZE * 0.15
	var upper: MeshInstance3D = _make_coral_voxel(
		Vector3(0.0, hinge_y + VOXEL_SIZE * 0.16, -VOXEL_SIZE * 0.04),
		Vector3(VOXEL_SIZE * 0.72, VOXEL_SIZE * 0.22, VOXEL_SIZE * 0.52),
		shell_col)
	var lower: MeshInstance3D = _make_coral_voxel(
		Vector3(0.0, hinge_y - VOXEL_SIZE * 0.05, VOXEL_SIZE * 0.04),
		Vector3(VOXEL_SIZE * 0.72, VOXEL_SIZE * 0.18, VOXEL_SIZE * 0.52),
		shell_col.darkened(0.18))
	_clam_shell_parts.append(upper)
	_clam_shell_parts.append(lower)
	if rel > 0.45:
		_make_coral_voxel(
			Vector3(0.0, hinge_y + VOXEL_SIZE * 0.06, 0.0),
			Vector3(VOXEL_SIZE * 0.34, VOXEL_SIZE * 0.10, VOXEL_SIZE * 0.24),
			tip_color)


func _process(dt: float) -> void:
	# Stagger updates so dozens of anemone/hydra/clam instances don't all
	# touch transforms on the same frame (macOS Metal fence pressure).
	const ANIM_STEP: int = 2
	var frame: int = Engine.get_process_frames()
	if (frame + get_instance_id()) % ANIM_STEP != 0:
		return
	var sdt: float = dt * float(ANIM_STEP)
	var sim_n: Node = _find_sim()
	if sim_n != null:
		sdt *= float(sim_n.time_scale)
	if sdt <= 0.0:
		return
	_sessile_phase += sdt * (0.8 + sway_amplitude * 1.4)
	_animate_sessile_motion()


func _animate_sessile_motion() -> void:
	# Flow sample for asymmetric ribbon undulation (anemones in particular).
	var flow_bias: float = _get_flow_bias()
	# All three branches below read each list entry into a Variant first
	# and validate it before casting to Node3D. The typed-local assignment
	# `var t: Node3D = _arr[i]` triggers a "previously freed instance"
	# error when grazing/decay has queue_free'd the underlying voxel —
	# Variant carries the stale reference without validating on store, so
	# is_instance_valid + is_queued_for_deletion can filter it cleanly.
	if coral_form == "anemone":
		# Two-axis ribbon wave: each tentacle has its own phase, and the
		# wave amplitude is modulated by flow so the colony lazily drifts
		# downstream. Tips get a small outward lift on top of the rotation
		# so the very ends ribbon visibly rather than swinging as rigid rods.
		for i in _anemone_tentacles.size():
			var t_v: Variant = _anemone_tentacles[i]
			if t_v == null or not (t_v is Node3D) or not is_instance_valid(t_v):
				continue
			var t: Node3D = t_v as Node3D
			if t.is_queued_for_deletion():
				continue
			var tp: float = float(t.get_meta("anemone_phase", float(i) * 0.79))
			# Wave amplitude scales with feeding extension — a fed anemone
			# sweeps wider arcs, a retracted one barely moves. Range
			# (0.06..0.32) gives a clear visual gap between hungry and
			# satiated colonies.
			var ext_amp: float = lerpf(0.06, 0.32, _feeding_extension)
			var wave_x: float = sin(_sessile_phase * 1.8 + tp) * ext_amp
			var wave_z: float = cos(_sessile_phase * 1.4 + tp * 0.85) * (ext_amp * 0.82)
			# Bias the wave downstream with flow — gentle in still water,
			# obvious near the aerator.
			t.rotation.x = wave_x + flow_bias * 0.18
			t.rotation.z = wave_z + flow_bias * 0.12
			# Tips lifted/displaced an extra step so the ribbon end snaps
			# slightly past the base axis (real anemone tip motion).
			if t.has_meta("tip_ref"):
				var tip_var: Variant = t.get_meta("tip_ref")
				if tip_var != null and tip_var is Node3D and is_instance_valid(tip_var):
					var tip: Node3D = tip_var as Node3D
					if not tip.is_queued_for_deletion():
						var lift: float = sin(_sessile_phase * 2.4 + tp * 1.3) * VOXEL_SIZE * 0.06
						tip.position.y = VOXEL_SIZE * 0.33 + lift
	elif coral_form == "hydra_fresh":
		for i in _hydra_tentacles.size():
			var h_v: Variant = _hydra_tentacles[i]
			if h_v == null or not (h_v is Node3D) or not is_instance_valid(h_v):
				continue
			var h: Node3D = h_v as Node3D
			if h.is_queued_for_deletion():
				continue
			h.rotation.x = sin(_sessile_phase * 1.5 + float(i) * 0.7) * 0.28 + flow_bias * 0.16
			h.rotation.z = cos(_sessile_phase * 1.2 + float(i) * 0.6) * 0.22
	elif coral_form == "clam":
		var open_amount: float = 0.18 + 0.16 * (0.5 + 0.5 * sin(_sessile_phase * 0.8))
		for i in _clam_shell_parts.size():
			var p_v: Variant = _clam_shell_parts[i]
			if p_v == null or not (p_v is Node3D) or not is_instance_valid(p_v):
				continue
			var p: Node3D = p_v as Node3D
			if p.is_queued_for_deletion():
				continue
			if i % 2 == 0:
				p.rotation.x = -open_amount
			else:
				p.rotation.x = open_amount * 0.45
	# Polyp tips pulse for every coral form. Cheap: a single sin per tip,
	# scale assignment only. Pulse range is narrow (~0.78..1.08) so the
	# pulse reads as breathing, not bouncing.
	_animate_polyp_tips()
	# Re-paint bleach tint when it changes meaningfully.
	if absf(_bleach_level - _last_bleach_applied) > 0.04:
		_apply_bleach_tint()
		_last_bleach_applied = _bleach_level


func _animate_polyp_tips() -> void:
	if _polyp_tips.is_empty():
		return
	# Bleached polyps retract — pulse amplitude collapses as bleach climbs.
	var amp: float = lerpf(0.15, 0.02, clampf(_bleach_level, 0.0, 1.0))
	# Bioluminescence: coral tips emit a soft glow at night. The voxel
	# materials are unshaded, so we add emission by raising the albedo
	# brightness on the tip mesh. Day-phase fetched from SimDriver: glow
	# peaks during the deep-night window (phase ~0.5..0.95) and fades to
	# nothing at dawn / dusk.
	var night_glow: float = 0.0
	var day_zoox: float = 0.0
	var sim_n: Node = _find_sim()
	if sim_n != null and sim_n.has_method("daylight"):
		var dl: float = float(sim_n.daylight())
		# daylight() is 0 at night, 1 at noon. Strong glow when dl < 0.25.
		night_glow = (1.0 - bleach_glow_dim()) * smoothstep(0.32, 0.05, dl)
		day_zoox = (1.0 - bleach_glow_dim()) * smoothstep(0.22, 0.88, dl)
		var dp: float = fposmod(float(sim_n.day_phase), 1.0)
		var reef_pulse: float = 0.55 + 0.45 * sin(dp * TAU)
		night_glow *= reef_pulse
		if sim_n.get("dissolved_o2") != null:
			night_glow *= clampf(float(sim_n.dissolved_o2) / 0.88, 0.35, 1.0)
			day_zoox *= clampf(float(sim_n.dissolved_o2) / 0.75, 0.45, 1.0)
	# Prune freed polyp tips lazily. Reading the dict entry into a
	# Variant first (not a typed Node3D) avoids the "assign to invalid
	# previously freed instance" error when fish grazing or decay has
	# queue_free'd the underlying voxel — typed assignment validates
	# on store, but Variant just carries the (now-null) reference.
	var live_count: int = 0
	for i in _polyp_tips.size():
		var entry: Dictionary = _polyp_tips[i]
		var n_v: Variant = entry.get("node")
		if n_v == null or not (n_v is Node3D) or not is_instance_valid(n_v):
			entry["node"] = null  # mark stale so we can drop later
			continue
		var n: Node3D = n_v as Node3D
		if n.is_queued_for_deletion():
			entry["node"] = null
			continue
		live_count += 1
		var phase: float = float(entry.get("phase", 0.0))
		# Range ~(1 - amp .. 1 + amp). Slightly squashed on the closed
		# half so the rest pose reads as a recessed polyp.
		var s: float = 1.0 + sin(_sessile_phase * 1.6 + phase) * amp
		# Slow periodic retract — dome / plate polyps snap mostly closed
		# every ~8–12 s so colonies read as actively respiring.
		var retract_env: float = sin(_sessile_phase * 0.42 + phase * 0.15)
		if retract_env < -0.72:
			s *= 0.52
		# Scale-with-glow: glowing polyps swell slightly so a bright pulse
		# also reads as a physical "breath out" rather than only a color
		# change. Bumped by night_glow so this only kicks in after dusk.
		var glow_swell: float = 1.0 + night_glow * 0.10 * (0.5 + 0.5 * sin(_sessile_phase * 1.6 + phase))
		# Feeding extension — actively-feeding polyps swell ~25% larger
		# than retracted ones. Combined with the pulse + glow swell this
		# gives "a hungry coral with shrunken polyps" vs "a fed coral
		# with fat exposed feeding bodies." Phase-offset so a colony
		# extends polyps in a soft wave rather than all simultaneously.
		var feed_swell: float = 1.0 + _feeding_extension * (0.18 + 0.07 * sin(_sessile_phase * 0.8 + phase * 0.5))
		var base_scale: float = float(entry.get("base_scale", 1.0))
		n.scale = Vector3.ONE * (base_scale * s * glow_swell * feed_swell)
		# Apply bioluminescent glow as an albedo lift. Pulse the glow with
		# the same phase so the polyp visibly breathes light.
		if night_glow > 0.01 and n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			var sm: ShaderMaterial = mi.material_override as ShaderMaterial
			if sm != null:
				var base_alb: Color
				if mi.has_meta("base_albedo_glow"):
					var stored: Variant = mi.get_meta("base_albedo_glow")
					base_alb = stored as Color if stored is Color else Color.WHITE
				else:
					base_alb = VoxelMat.read_albedo(sm)
					mi.set_meta("base_albedo_glow", base_alb)
				var glow_pulse: float = 0.5 + 0.5 * sin(_sessile_phase * 1.6 + phase)
				var glow: float = night_glow * (0.6 + 0.4 * glow_pulse)
				# Boost albedo additively toward white; voxel shader is
				# unshaded so this reads as direct emission. Strength bumped
				# from 0.45 to 0.72 to push the source pixel firmly above
				# the palette_quantize bloom_threshold (0.68) so glowing
				# polyps burn through to the day palette at night.
				if not mi.has_meta("glow_mat"):
					var dup: ShaderMaterial = sm.duplicate() as ShaderMaterial
					mi.material_override = dup
					mi.set_meta("glow_mat", true)
				var lit: Color = base_alb.lightened(0.72 * glow)
				(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", lit)
		elif day_zoox > 0.02 and n is MeshInstance3D:
			var mi_day: MeshInstance3D = n as MeshInstance3D
			var sm_day: ShaderMaterial = mi_day.material_override as ShaderMaterial
			if sm_day != null:
				var base_day: Color
				if mi_day.has_meta("base_albedo_glow"):
					var stored_day: Variant = mi_day.get_meta("base_albedo_glow")
					base_day = stored_day as Color if stored_day is Color else VoxelMat.read_albedo(sm_day)
				else:
					base_day = VoxelMat.read_albedo(sm_day)
					mi_day.set_meta("base_albedo_glow", base_day)
				var zoox_pulse: float = 0.55 + 0.45 * sin(_sessile_phase * 0.85 + phase * 0.7)
				var tip_lift: float = day_zoox * zoox_pulse * 0.32
				var zoox_col: Color = base_day.lerp(tip_color, tip_lift)
				if not mi_day.has_meta("glow_mat"):
					var dup_day: ShaderMaterial = sm_day.duplicate() as ShaderMaterial
					mi_day.material_override = dup_day
					mi_day.set_meta("glow_mat", true)
				(mi_day.material_override as ShaderMaterial).set_shader_parameter("albedo", zoox_col)
		elif n is MeshInstance3D:
			var mi2: MeshInstance3D = n as MeshInstance3D
			# Restore base when night ended. Cheap idempotent check.
			if mi2.has_meta("base_albedo_glow") and mi2.has_meta("glow_mat"):
				var sm2: ShaderMaterial = mi2.material_override as ShaderMaterial
				if sm2 != null:
					sm2.set_shader_parameter("albedo", mi2.get_meta("base_albedo_glow"))
	# Compact the list when stale entries pile up — drop everything
	# whose node was nilled above. Runs only when the survivor count
	# falls below ~half so the resize churn stays rare.
	# Bitshift to halve — explicit divide-by-2 with no integer-division warning.
	if live_count > 0 and live_count < (_polyp_tips.size() >> 1):
		var keep: Array = []
		for e in _polyp_tips:
			if e.get("node") != null:
				keep.append(e)
		_polyp_tips = keep


# Bleach lowers the polyp glow proportionally — fully-bleached coral
# can't sustain zooxanthellae, so the night glow goes nearly dark.
func bleach_glow_dim() -> float:
	return clampf(_bleach_level, 0.0, 1.0)


# Pale the coral voxels toward bone-white in proportion to _bleach_level.
# Heaviest on the topmost (youngest) voxels — that's where zooxanthellae
# turnover is fastest and bleaching shows first. Restored from cached
# base_albedo when bleach drops back to safe.
func _apply_bleach_tint() -> void:
	if voxels.is_empty():
		return
	var b: float = clampf(_bleach_level, 0.0, 1.0)
	var pale := Color(0.96, 0.92, 0.86)
	var n: int = voxels.size()
	for i in n:
		# Load via Variant first so a freed entry doesn't blow up the
		# typed assignment on Plant.voxels (Plant.nibble may have just
		# queue_free'd one but not yet pruned the array slot).
		var vx_v: Variant = voxels[i]
		if vx_v == null or not (vx_v is MeshInstance3D) or not is_instance_valid(vx_v):
			continue
		var vx: MeshInstance3D = vx_v as MeshInstance3D
		if vx.is_queued_for_deletion():
			continue
		var sm: ShaderMaterial = vx.material_override as ShaderMaterial
		if sm == null:
			continue
		var orig: Color
		if vx.has_meta("base_albedo_bleach"):
			var stored: Variant = vx.get_meta("base_albedo_bleach")
			orig = stored as Color if stored is Color else Color.WHITE
		else:
			orig = VoxelMat.read_albedo(sm)
			vx.set_meta("base_albedo_bleach", orig)
		# Top quarter of voxels takes the full bleach hit; older base
		# stays closer to its true color.
		var depth_w: float = clampf(float(i) / float(maxi(1, n - 1)), 0.0, 1.0)
		var local_b: float = b * (0.45 + 0.55 * depth_w)
		var target: Color = orig.lerp(pale, local_b)
		if not vx.has_meta("bleach_mat"):
			var dup: ShaderMaterial = sm.duplicate() as ShaderMaterial
			vx.material_override = dup
			vx.set_meta("bleach_mat", true)
		(vx.material_override as ShaderMaterial).set_shader_parameter("albedo", target)


# Mirror the substrate-flow lean Plant computes in its tick, so polyp /
# tentacle motion can bend downstream consistently. Cheap — just reads
# the cached Plant rotation.z.
func _get_flow_bias() -> float:
	return rotation.z / 0.04 if absf(rotation.z) > 0.0001 else 0.0


# ---- Bleaching tick ----
# Runs on top of Plant.tick. Pulls warmth from TankConfig and O2 from sim;
# climbs bleach when either crosses its threshold, decays when both are
# safe. Slows growth in proportion to bleach so a bleached colony visibly
# pauses. Doesn't kill the coral — that's still Plant's normal decay path
# if health drops far enough.
func tick(dt: float, substrate: SubstrateGrid) -> void:
	if _base_growth_rate <= 0.0:
		_base_growth_rate = growth_rate
	# Read environmental stressors.
	var sim_n: Node = _find_sim()
	var o2: float = 0.65
	if sim_n != null and sim_n.get("dissolved_o2") != null:
		o2 = clampf(float(sim_n.dissolved_o2), 0.0, 1.0)
	var warmth: float = 0.5
	if sim_n != null:
		var w: Node = sim_n.get_parent()
		if w != null and w.has_method("effective_warmth_at"):
			warmth = float(w.effective_warmth_at(global_position))
		else:
			var cfg: Node = sim_n.get_node_or_null("/root/TankConfig")
			if cfg != null:
				var wv: Variant = cfg.get("light_warmth")
				if wv != null:
					warmth = clampf(float(wv), 0.0, 1.0)
	var prev_bleach: float = _bleach_level
	if is_reef_coral():
		# Climb when warmth >=0.78 or o2 <=0.35; decay when both safe.
		# Decay is slower than climb — recovering from bleaching is a slow
		# process on a real reef. Both rates are per-second.
		var heat_stress: float = clampf((warmth - 0.78) / 0.20, 0.0, 1.0)
		var hypoxia_stress: float = clampf((0.35 - o2) / 0.25, 0.0, 1.0)
		var stress: float = maxf(heat_stress, hypoxia_stress)
		if stress > 0.0:
			_bleach_level = clampf(_bleach_level + stress * dt * 0.014, 0.0, 1.0)
		else:
			_bleach_level = clampf(_bleach_level - dt * 0.008, 0.0, 1.0)
		_emit_bleach_eco_events(sim_n, prev_bleach)
	elif _bleach_level > 0.0:
		_bleach_level = 0.0
		if absf(_bleach_level - _last_bleach_applied) > 0.01:
			_apply_bleach_tint()
			_last_bleach_applied = _bleach_level
	var reef_growth: float = 1.0
	if is_reef_coral() and sim_n != null and sim_n.get("water_chemistry") != null:
		var wc: WaterChemistry = sim_n.water_chemistry
		reef_growth = clampf(float(wc.reef_nutrients) / 0.55, 0.35, 1.15) \
			* clampf((float(wc.alkalinity_proxy) - 6.8) / 1.4, 0.45, 1.0)
	growth_rate = _base_growth_rate * reef_growth \
		* (lerpf(1.0, 0.3, _bleach_level) if is_reef_coral() else 1.0)
	# Feeding state — drives tentacle / polyp extension in
	# _animate_polyp_tips + _animate_sessile_motion. Real corals only
	# extend tentacles when conditions are good: high oxygen, healthy
	# zooxanthellae (not bleached), and either daytime feeding (photo-
	# synthesis) for symbiont corals OR night-time prey capture for the
	# heterotrophic species. We approximate with a smooth function of
	# O2 + (1 - bleach) and let day vs night both qualify so corals
	# always look alive when healthy.
	var daylight_factor: float = 0.5
	if sim_n != null and sim_n.has_method("daylight"):
		daylight_factor = float(sim_n.daylight())
	# Both day and night extension is full; only twilight transitions
	# pinch slightly. Health × O2 × not-bleached drives the magnitude.
	var dawn_dusk_factor: float = 1.0 - 4.0 * absf(daylight_factor - 0.5) * absf(daylight_factor - 0.5)
	dawn_dusk_factor = clampf(0.55 + dawn_dusk_factor * 0.45, 0.0, 1.0)
	var target_feeding: float = clampf(o2 / 0.85, 0.0, 1.0) \
		* clampf(_health_smooth, 0.0, 1.0) \
		* (1.0 - _bleach_level) \
		* dawn_dusk_factor
	# Night heterotrophic feeding (#45): after dark, corals extend feeding
	# tentacles to capture plankton, drawing down reef nutrients — a real
	# nutrient sink for the reef and a reason the polyps are out at night.
	var night_f: float = 1.0 - daylight_factor
	if night_f > 0.4 and _bleach_level < 0.6:
		target_feeding = maxf(target_feeding,
			clampf(o2 / 0.85, 0.0, 1.0) * (1.0 - _bleach_level) * night_f)
		if sim_n != null and sim_n.water_chemistry != null:
			sim_n.water_chemistry.reef_nutrients = maxf(
				0.08, float(sim_n.water_chemistry.reef_nutrients) - night_f * 0.0008 * dt)
	# Lerp to target slowly — tentacles take seconds to extend / retract,
	# they don't snap like a fish reaction.
	_feeding_extension = lerpf(_feeding_extension, target_feeding, clampf(dt * 0.6, 0.0, 1.0))
	super.tick(dt, substrate)


func _emit_bleach_eco_events(sim_n: Node, prev: float) -> void:
	if not is_reef_coral():
		return
	if sim_n == null or not sim_n.has_method("emit_eco_event"):
		return
	var bands: Array = [0.25, 0.5, 0.75]
	for i in bands.size():
		var thr: float = float(bands[i])
		if prev < thr and _bleach_level >= thr and i > _bleach_event_band:
			_bleach_event_band = i
			match i:
				0:
					sim_n.emit_eco_event("reef", "Coral paling — early bleaching stress.", 1)
				1:
					sim_n.emit_eco_event("reef", "Reef bleaching — colony losing zooxanthellae.", 2)
				2:
					sim_n.emit_eco_event("reef", "Severe bleaching — check warmth and O₂.", 2)
	if _bleach_level < 0.15 and prev >= 0.25 and not _bleach_recovery_logged:
		_bleach_recovery_logged = true
		_bleach_event_band = -1
		sim_n.emit_eco_event("reef", "Corals recovering color — stress easing.", 1)
	elif _bleach_level >= 0.2:
		_bleach_recovery_logged = false


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
