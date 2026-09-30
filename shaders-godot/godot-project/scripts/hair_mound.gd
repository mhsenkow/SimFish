extends Node3D

# Hair-algae mounds: the soft green-olive domes of filament algae that grow
# over the highest hardscape in an old, bright, well-fed tank (the reference
# valli-jungle photos have one on the tallest stone). One foliage_mm
# VoxelBatch per tank - every strand segment is an instance, so a mound is a
# single draw however many strands it has.
#
# Each strand roots just inside a dome over the host top and random-walks
# up and outward in a few thin segments; custom-data alpha is the strand's
# arc position, so foliage_mm's chain sway makes the tips drift while the
# roots stay put. Deterministic from the seed, rebuilt on every load from
# the preset (world.gd `hair_mound_count`) - cosmetic, nothing is saved.

const STRANDS_PER_MOUND: int = 72
const STRAND_WIDTH: float = 0.075

var _batch: VoxelBatch = null
var _mat: ShaderMaterial = null


# `centers` in this node's space (the dome's base centre, on the host top),
# `radii` one dome radius per centre.
func build(centers: Array, radii: Array, seed_value: int) -> void:
	if _batch != null:
		_batch.clear()
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/foliage_mm.gdshader") as Shader
		_mat.set_shader_parameter("chain_sway_amp", 0.05)
		_mat.set_shader_parameter("chain_speed", 0.6)
		_mat.set_shader_parameter("chain_desync", 1.0)
		_mat.set_shader_parameter("sway_phase_offset", float(posmod(seed_value, 997)) * 0.01)
		VoxelMat.register_foliage_mm(_mat)
	if _batch == null:
		_batch = VoxelBatch.new(self, _mat, STRANDS_PER_MOUND * 8 * maxi(centers.size(), 1), true)
	var rng := RandomNumberGenerator.new()
	for m in mini(centers.size(), radii.size()):
		rng.seed = seed_value * 7919 + m * 104729
		_lay_mound(rng, centers[m] as Vector3, float(radii[m]))
	_batch.flush()


func instance_count() -> int:
	return _batch._count if _batch != null else 0


func _lay_mound(rng: RandomNumberGenerator, center: Vector3, radius: float) -> void:
	for s in STRANDS_PER_MOUND:
		var az: float = rng.randf() * TAU
		var el: float = acos(rng.randf_range(0.15, 1.0))
		var n := Vector3(sin(el) * cos(az), cos(el), sin(el) * sin(az))
		var p: Vector3 = center + n * radius * rng.randf_range(0.5, 0.8)
		var d: Vector3 = (n + Vector3.UP * 0.6).normalized()
		var segs: int = rng.randi_range(5, 9)
		var seg_len: float = radius * rng.randf_range(0.10, 0.16)
		var tone: float = rng.randf_range(0.75, 1.15)
		var base: Color = Color(0.22, 0.38, 0.12).lerp(Color(0.40, 0.54, 0.20), rng.randf())
		var phase: float = rng.randf()
		for k in segs:
			d = (d + Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.25),
				rng.randf_range(-0.35, 0.35))).normalized()
			var p2: Vector3 = p + d * seg_len
			var t: float = (float(k) + 0.5) / float(segs)
			var width: float = STRAND_WIDTH * lerpf(1.0, 0.6, t)
			var xv: Vector3 = d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
			var zv: Vector3 = xv.cross(d).normalized()
			var xf := Transform3D(Basis(xv * width, d * seg_len * 1.1, zv * width), (p + p2) * 0.5)
			# Tips lighter and greener. Alpha stays near 1: foliage_mm reads
			# 1 - a as aufwuchs speckle, and a hair mound IS the algae - brown
			# specks on it read as a dead bush.
			var col := Color(base.r * tone, base.g * tone * lerpf(1.0, 1.15, t), base.b * tone, 0.97)
			var h: VoxelBatch.Handle = _batch.add(xf, col)
			h.set_custom_data(Color(0.1, phase, 0.0, t))
			p = p2
