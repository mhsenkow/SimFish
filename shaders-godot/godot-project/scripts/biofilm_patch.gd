# Biofilm patch — pale slime on hardscape (driftwood + rocks).
#
# Distinct from:
#   - The driftwood biofilm shader tint (world.gd's _apply_biofilm_tints),
#     which is a static color shift on the wood voxels themselves.
#   - Algae (algae.gd), which is green and substrate-borne.
#
# These are PHYSICAL voxel patches anchored to hardscape that grow over
# time and get grazed down by snails + shrimp. Real planted-tank biofilm
# is one of the most under-appreciated food sources for the cleanup crew
# — it's where most of the substrate carbon turnover actually happens.
#
# Visual: a small lattice of 4–6 thin pale voxels (slight yellow-white)
# sitting just above the hardscape surface. Slow micro-sway. Despawns
# when fully grazed or after MAX_AGE.

class_name BiofilmPatch
extends Node3D


const VOXEL_SIZE: float = 0.05
const SHEET_COUNT_MIN: int = 4
const SHEET_COUNT_MAX: int = 6
const MAX_AGE_S: float = 240.0
const WAVE_FREQ: float = 0.9
const WAVE_AMP: float = 0.025
const WAVE_INTERVAL: float = 0.1

var sim: Node = null
var _age: float = 0.0
var _phase: float = 0.0
var _wave_accum: float = 0.0
# Each sheet is a per-instance entry in a single MultiMesh batch — one
# draw call for the whole patch. We mirror the original per-sheet sway by
# rewriting each handle's transform with its phase-offset rotation each
# frame; the per-sheet base position + size live in the parallel
# _sheet_origins array because VoxelBatch.Handle only carries the local
# origin used at add() time.
var _batch: VoxelBatch = null
var _sheets: Array[VoxelBatch.Handle] = []
var _sheet_origins: Array[Vector3] = []
var _sheet_size: Vector3 = Vector3.ZERO
var _dead: bool = false


func _ready() -> void:
	add_to_group("biofilm_patches")
	_phase = randf() * TAU
	var count: int = randi_range(SHEET_COUNT_MIN, SHEET_COUNT_MAX)
	# Pale palette — biofilm in real tanks is off-white with a hint of
	# yellow or pink depending on the bacterial / archaeal species mix.
	var palette: Array[Color] = [
		Color8(238, 232, 218),
		Color8(225, 220, 200),
		Color8(232, 225, 210),
	]
	# Flat sheet-like shape — wider than tall. Same size for every sheet
	# in the patch, so the per-instance basis just bakes this scale + the
	# wave rotation; no per-sheet BoxMesh allocation.
	_sheet_size = Vector3(VOXEL_SIZE * 0.5, VOXEL_SIZE * 0.15, VOXEL_SIZE * 0.5)
	_batch = VoxelBatch.new(self, VoxelMat.make_voxel_mm(),
		mini(maxi(count, SHEET_COUNT_MAX), 16))
	for i in count:
		var ang: float = float(i) / float(count) * TAU + randf_range(-0.18, 0.18)
		var radius: float = randf_range(VOXEL_SIZE * 0.4, VOXEL_SIZE * 1.1)
		var origin: Vector3 = Vector3(
			cos(ang) * radius,
			VOXEL_SIZE * 0.08,
			sin(ang) * radius)
		_sheet_origins.append(origin)
		var col: Color = VoxelMat.boost_life_color(palette[i % palette.size()])
		_sheets.append(_batch.add(_make_sheet_xform(origin, 0.0), col))
	_batch.flush()


func _make_sheet_xform(origin: Vector3, roll: float) -> Transform3D:
	# Per-sheet basis: roll around Z (the original wave axis), then scale
	# to the flat-sheet size. Order matters — rotate first so the sheet
	# tips along its long axis instead of skewing.
	var b: Basis = Basis(Vector3(0, 0, 1), roll).scaled(_sheet_size)
	return Transform3D(b, origin)


func _process(dt: float) -> void:
	if _dead:
		return
	var sdt: float = dt
	if sim != null:
		sdt *= float(sim.time_scale)
		if sdt <= 0.0:
			return
	_age += sdt
	_wave_accum += sdt
	if _wave_accum < WAVE_INTERVAL:
		return
	var adt: float = _wave_accum
	_wave_accum = 0.0
	_phase += adt * WAVE_FREQ
	# Tiny lateral sway in current flow — each sheet phase-offset by its
	# index so the patch reads as multiple things waving slightly out of
	# sync, not a single flat surface rocking together.
	for i in _sheets.size():
		var h: VoxelBatch.Handle = _sheets[i]
		if h == null or not h.alive:
			continue
		var roll: float = sin(_phase + float(i) * 0.7) * WAVE_AMP
		h.set_transform(_make_sheet_xform(_sheet_origins[i], roll))
	if _age >= MAX_AGE_S:
		_dead = true


# Reduce one sheet from the patch. Called by grazing shrimp / snails.
# Returns true if a sheet was actually removed.
func graze_one() -> bool:
	for i in _sheets.size():
		var h: VoxelBatch.Handle = _sheets[i]
		if h != null and h.alive:
			h.hide()
			var any_left: bool = false
			for u in _sheets:
				if u != null and u.alive:
					any_left = true
					break
			if not any_left:
				_dead = true
			return true
	return false


# How much food is left in this patch — used by the grazer AI as a
# tie-breaker between nearby patches.
func food_value() -> int:
	var n: int = 0
	for h in _sheets:
		if h != null and h.alive:
			n += 1
	return n


func is_dead() -> bool:
	return _dead


func mark_dead() -> void:
	_dead = true


func to_save_dict() -> Dictionary:
	return {
		"pos": SaveHelpers.vec3_to_array(global_position),
		"age": _age,
		"sheet_count": _sheets.size(),
	}


func apply_save_dict(d: Dictionary) -> void:
	_age = float(d.get("age", 0.0))
