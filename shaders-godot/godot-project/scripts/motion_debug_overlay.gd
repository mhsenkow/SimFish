# 3D debug draw for fauna motion tuning (home_y, preferred_y, boundary inward).
# Toggle from main.gd with M when not typing in a text field.
extends Node3D
class_name MotionDebugOverlay

var enabled: bool = false
var sim: Node = null

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Lines"
	add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mesh.material_override = _mat


func toggle() -> void:
	enabled = not enabled
	if not enabled:
		_mesh.mesh = null


func _process(_delta: float) -> void:
	if not enabled or sim == null:
		if _mesh.mesh != null:
			_mesh.mesh = null
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, null)
	var w: Node = sim.get_parent()
	var fish_list: Array = sim.get("fish") if sim.get("fish") != null else []
	var drawn: int = 0
	for f in fish_list:
		if not is_instance_valid(f) or not (f is Fish):
			continue
		if drawn >= 48:
			break
		var gp: Vector3 = f.global_position
		var pref_y: float = float(f.get("preferred_y"))
		var home_y: float = float(f.get("home_y"))
		var home_r: float = float(f.get("home_y_radius"))
		_line_h(im, gp, pref_y, Color(0.2, 0.85, 1.0, 0.9))
		_line_h(im, gp, home_y, Color(0.35, 1.0, 0.45, 0.9))
		_band_h(im, gp, home_y, home_r, Color(1.0, 0.85, 0.2, 0.55))
		if w != null and w.has_method("tank_lateral_boundary_info"):
			var info: Dictionary = w.tank_lateral_boundary_info(gp, 0.42)
			var inward: Vector3 = info.get("inward", Vector3.ZERO)
			inward.y = 0.0
			if inward.length_squared() > 1e-6:
				inward = inward.normalized() * 0.55
				_line_vec(im, gp, gp + inward, Color(1.0, 0.35, 0.35, 0.85))
		drawn += 1
	im.surface_end()
	_mesh.mesh = im


func _line_h(im: ImmediateMesh, gp: Vector3, y: float, col: Color) -> void:
	var a := Vector3(gp.x - 0.35, y, gp.z)
	var b := Vector3(gp.x + 0.35, y, gp.z)
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)


func _band_h(im: ImmediateMesh, gp: Vector3, y: float, r: float, col: Color) -> void:
	_line_h(im, gp, y + r, col)
	_line_h(im, gp, y - r, col.darkened(0.15))


func _line_vec(im: ImmediateMesh, a: Vector3, b: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
