extends Node3D
class_name WasteParticleBatch

# PERFORMANCE_REALTIME #72 — one MultiMesh draw for all waste/food particles.

const SLOT_NONE: int = -1
const CAP: int = 240

var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _free_slots: Array[int] = []
var _slot_owner: Array[WasteParticle] = []
var _xforms: Array[Transform3D] = []
var _colors: PackedColorArray = PackedColorArray()
var _dirty: bool = false


func _init() -> void:
	_build_mesh()


func _ready() -> void:
	if _mm == null:
		_build_mesh()


func _build_mesh() -> void:
	if _mm != null:
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = VoxelMat.get_box(Vector3.ONE)
	_mm.instance_count = CAP
	_mm.visible_instance_count = CAP
	_slot_owner.resize(CAP)
	_xforms.resize(CAP)
	_colors.resize(CAP)
	for i in CAP:
		var hidden := _hidden_transform()
		_xforms[i] = hidden
		_colors[i] = Color.WHITE
		_mm.set_instance_transform(i, hidden)
		_mm.set_instance_color(i, Color.WHITE)
		_free_slots.append(i)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "WasteMM"
	_mmi.multimesh = _mm
	_mmi.material_override = VoxelMat.make_voxel_mm()
	_mmi.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	add_child(_mmi)


static func _hidden_transform() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)


func claim_slot(w: WasteParticle) -> int:
	if _free_slots.is_empty() or w == null:
		return SLOT_NONE
	var slot: int = _free_slots.pop_back()
	_slot_owner[slot] = w
	return slot


func release_slot(slot: int) -> void:
	if slot < 0 or slot >= CAP:
		return
	_slot_owner[slot] = null
	var hidden := _hidden_transform()
	_xforms[slot] = hidden
	_colors[slot] = Color.WHITE
	_mm.set_instance_transform(slot, hidden)
	_dirty = true
	_free_slots.append(slot)


func sync_slot(slot: int, world_pos: Vector3, size: float, color: Color) -> void:
	if slot < 0 or slot >= CAP or _mm == null:
		return
	var s: float = maxf(size, 0.001)
	var xform := Transform3D(Basis().scaled(Vector3(s, s, s)), world_pos)
	_xforms[slot] = xform
	_colors[slot] = color
	_mm.set_instance_transform(slot, xform)
	_mm.set_instance_color(slot, color)
	_dirty = true


func flush_blit() -> void:
	if not _dirty or _mm == null:
		return
	var xforms_arr: Array = []
	xforms_arr.assign(_xforms)
	MultiMeshBufferBlit.upload(_mm, xforms_arr, _colors, PackedColorArray(), CAP, false)
	_dirty = false


func mesh_instance_count() -> int:
	return 1 if _mmi != null else 0
