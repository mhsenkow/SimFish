# Aquascape mode: terrain sculpt, hardscape placement, voxel building, unified undo.
class_name AquascapeController
extends RefCounted

const INVALID_HIT: Vector3 = Vector3(INF, INF, INF)
const PAINT_INTERVAL: float = 0.08
const UNDO_MAX: int = 96

const INVALID_GRID: Vector3i = Vector3i(99999, 99999, 99999)

const ObjectMeshes := preload("res://scripts/aquascape_object_meshes.gd")

const AQUASCAPE_TERRAIN_TOOLS: Array[String] = [
	"aquasoil", "sand", "gravel", "peat", "dirt",
	"lava_rock", "white_sand", "dark_soil", "clay", "crushed_coral",
]
const AQUASCAPE_TOOLS: Array[String] = [
	"aquasoil", "sand", "gravel", "peat", "stone", "wood", "dig", "trim",
	"smooth", "raise", "block", "eraser", "line", "box", "fill", "grad",
	"paste", "object", "eyedropper", "select",
]

signal mode_changed(active: bool)

var is_active: bool = false
var tool: String = "aquasoil"
var brush_radius: int = 1

var _host: Node
var _camera: Camera3D
var _world: Node3D
var _palette: PanelContainer
var _tool_buttons: Dictionary = {}
var _preview: MeshInstance3D
var _placed: Array[Node3D] = []
var _undo_stack: Array = []
var _redo_stack: Array = []
var _build_grid: AquascapeBuildGrid
var snap_grid: bool = true
var build_plane_y: float = 3.0
var build_color: Color = Color8(130, 125, 135)
var build_color_b: Color = Color8(85, 140, 180)
var build_finish: String = "matte"
var castle_towers: int = 4
var castle_height: int = 7
var selected_object_id: String = "castle"
var show_composition: bool = false
var gravity_mode: bool = true
var _last_substrate_tool: String = "aquasoil"
var _selected_build_cell: Vector3i = INVALID_GRID
var mirror_x: bool = false
var mirror_z: bool = false
var hollow_box: bool = false
var hide_fauna_layers: bool = false
var ortho_move: bool = false
var gumball_enabled: bool = true
var _click_anchor: Vector3i = INVALID_GRID
var _clipboard: Array = []
var _object_category: String = "All"
var wood_form: String = "drift"
var trim_mode: String = "all"
var brush_shape: String = "cube"
var build_scale: float = 1.0
var stamp_mode: bool = false
var lights_on_build: bool = false
var show_iwagumi: bool = false
var show_depth_zones: bool = false
var _ab_snapshot: Array = []
var _multi_select: Array[Node3D] = []
var _craft_label: Label = null
var _import_queue: Array = []
var _import_busy: bool = false
var _object_panel: ScrollContainer = null
var _object_row: HBoxContainer = null
var _cat_row: HBoxContainer = null
var _budget_label: Label = null
var _toggle_buttons: Dictionary = {}
var _finish_buttons: Dictionary = {}
var _color_swatches: Array[Button] = []
var _color_values: Array[Color] = []
var _color_b_swatches: Array[Button] = []
var _color_b_values: Array[Color] = []
var _coord_label: Label = null
var _status_label: Label = null
var _selection_label: Label = null
var _axis_handles: Dictionary = {}
var _gumball_axis: int = 0
var _gumball_axis_start: float = 0.0
var _gumball_nodes_start: Array = []
var _stroke_batch: Array = []
var _stroke_active: bool = false
var _composition_guide: Node3D = null
var _placement_gizmo: Node3D = null
var _saved_time_scale: float = 1.0
var _paused_sim_for_aquascape: bool = false
var _wood_drag: Node3D
var _wood_drag_y_offset: float = 0.0
var _wood_drag_last_hit: Vector3 = INVALID_HIT
var _drag_cluster: Array[Node3D] = []
var _paint_cooldown: float = 0.0
var _mesh_rebuild_cooldown: float = 0.0
const MESH_REBUILD_INTERVAL: float = 0.12


func setup(host: Node, camera: Camera3D, world: Node3D, palette: PanelContainer) -> void:
	_host = host
	_camera = camera
	_world = world
	_palette = palette
	_build_grid = AquascapeBuildGrid.new()
	var hs := _hardscape_node()
	_build_grid.setup(hs if hs != null else world, world)
	_build_grid.build_scale = build_scale
	if _world != null and _world.has_method("register_player_build_grid"):
		_world.register_player_build_grid(_build_grid)
	if _world != null and _world.get("WATER_HEIGHT") != null:
		build_plane_y = float(_world.WATER_HEIGHT) * 0.45
	_build_palette()


func toggle() -> void:
	is_active = not is_active
	var sim: Node = _host.get("_sim") if _host != null else null
	if is_active:
		_paused_sim_for_aquascape = false
		if sim != null:
			var cur: float = float(sim.time_scale)
			if cur > 0.0:
				TimeAuthority.set_base_scale(cur)
				_saved_time_scale = cur
				if _host != null and _host.has_method("_push_time_pause"):
					_host.call("_push_time_pause", "aquascape")
				else:
					sim.time_scale = 0.0
				_paused_sim_for_aquascape = true
		if _host != null and _host.has_method("clear_follow"):
			_host.call("clear_follow")
		_ensure_preview()
		if _palette != null:
			_palette.visible = true
		_refresh_tool_buttons()
		_maybe_show_builder_onboarding()
		refresh_build_appearance()
	else:
		if _composition_guide != null:
			_composition_guide.visible = false
		if _placement_gizmo != null:
			_placement_gizmo.visible = false
		if sim != null and _paused_sim_for_aquascape:
			if _host != null and _host.has_method("_pop_time_pause"):
				_host.call("_pop_time_pause", "aquascape")
			else:
				sim.time_scale = _saved_time_scale
		_paused_sim_for_aquascape = false
		if _preview != null:
			_preview.visible = false
		if _palette != null:
			_palette.visible = false
		set_hide_fauna_layers(false)
		_set_build_lights(false)
		refresh_build_appearance()
	var mobile: Node = _host.get("_mobile_hud") if _host != null else null
	if mobile != null and mobile.has_method("set_aquascape_mode"):
		mobile.set_aquascape_mode(is_active)
	if _host != null and _host.has_method("_sync_aquascape_chrome"):
		_host.call("_sync_aquascape_chrome", is_active)
	mode_changed.emit(is_active)


func set_tool(key: String) -> void:
	if not is_active:
		return
	tool = key
	if _is_substrate_paint_tool(key):
		_last_substrate_tool = key
	_click_anchor = INVALID_GRID
	_refresh_tool_buttons()
	if _host != null and _host.has_method("_render_header"):
		_host.call("_render_header")


func _is_substrate_paint_tool(key: String) -> bool:
	return key in AQUASCAPE_TERRAIN_TOOLS or TerrainVoxelGrid.tool_is_terrain(key)


func _active_substrate_tool() -> String:
	if _is_substrate_paint_tool(tool):
		return tool
	return _last_substrate_tool


func _snap_xz(x: float, z: float) -> Vector2:
	if not snap_grid:
		return Vector2(x, z)
	var cell: float = TerrainVoxelGrid.CELL_SIZE
	return Vector2(
		floorf(x / cell) * cell + cell * 0.5,
		floorf(z / cell) * cell + cell * 0.5,
	)


func adjust_brush(delta: int) -> void:
	brush_radius = clampi(brush_radius + delta, 1, 4)


func cycle_tool(dir: int) -> void:
	if not is_active or AQUASCAPE_TOOLS.is_empty():
		return
	var idx: int = AQUASCAPE_TOOLS.find(tool)
	if idx < 0:
		idx = 0
	var n: int = AQUASCAPE_TOOLS.size()
	idx = (idx + dir) % n
	if idx < 0:
		idx += n
	set_tool(AQUASCAPE_TOOLS[idx])


func tick_paint_cooldown(dt: float) -> void:
	if _paint_cooldown > 0.0:
		_paint_cooldown = maxf(0.0, _paint_cooldown - dt)
	if _mesh_rebuild_cooldown > 0.0:
		_mesh_rebuild_cooldown = maxf(0.0, _mesh_rebuild_cooldown - dt)


func can_paint() -> bool:
	return _paint_cooldown <= 0.0


# Drag-paint while holding LMB. Object repeats only in stamp mode; click-only tools
# never stream placements during a drag (AQUASCAPING_CRAFT #76).
func allows_drag_paint() -> bool:
	match tool:
		"object":
			return stamp_mode
		"fill", "grad", "paste", "eyedropper", "select", "line", "box":
			return false
		_:
			return true


func mark_painted() -> void:
	_paint_cooldown = PAINT_INTERVAL


func update_preview(mouse_pos: Vector2) -> void:
	if _preview == null or _camera == null or _world == null:
		return
	if tool in ["block", "eraser", "object", "eyedropper", "line", "box", "paste"]:
		var g: Vector3i = _target_build_cell(mouse_pos)
		if g == Vector3i(99999, 99999, 99999):
			_preview.visible = false
			return
		if _build_grid.has_cell(g) and tool != "eraser":
			_preview.visible = false
			return
		_preview.visible = true
		var wp: Vector3 = _library_object_surface_point(mouse_pos) \
			if tool == "object" else _build_grid.grid_to_world(g)
		if wp == INVALID_HIT:
			_preview.visible = false
			return
		var overlaps_solid: bool = _preview_overlaps_solid(g)
		if overlaps_solid and tool != "object":
			wp.y += TerrainVoxelGrid.CELL_SIZE * 0.08
		if tool == "object":
			var fp: Vector3 = ObjectMeshes.footprint(
				selected_object_id, _object_mesh_params())
			_preview.scale = fp * 0.92
		else:
			_preview.scale = Vector3.ONE * 0.92
		if _preview.material_override is StandardMaterial3D:
			var pm: StandardMaterial3D = _preview.material_override as StandardMaterial3D
			var c: Color = build_color if tool != "eraser" else Color8(220, 90, 90)
			if tool == "object":
				c = Color8(180, 220, 255)
			if not _build_grid.is_in_bounds(g):
				pm.albedo_color = Color8(255, 60, 60, 0.55)
				pm.emission = Color8(255, 90, 90)
			elif overlaps_solid:
				# Hovering over terrain or an existing block — lift the ghost so
				# it reads as a cursor, not a hole in the substrate.
				pm.albedo_color = Color8(255, 220, 120, 0.55)
				pm.emission = Color8(255, 230, 150)
			else:
				pm.albedo_color = Color(c.r, c.g, c.b, 0.45)
				pm.emission = c.lightened(0.35)
			pm.emission_energy_multiplier = 0.85
		_preview.global_position = wp
		_refresh_budget_label()
		return
	var hit: Vector3 = project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		_preview.visible = false
		return
	_preview.visible = true
	_preview.scale = Vector3.ONE
	var snapped_xz: Vector2 = _snap_xz(hit.x, hit.z)
	hit.x = snapped_xz.x
	hit.z = snapped_xz.y
	if tool == "dig":
		var top_y: float = column_top_y(hit.x, hit.z)
		hit.y = top_y - TerrainVoxelGrid.CELL_SIZE * 0.5
	else:
		var top_y: float = column_top_y(hit.x, hit.z)
		var replace_cap: bool = false
		if _world != null and _world.get("terrain_grid") != null:
			var tg: TerrainVoxelGrid = _world.terrain_grid
			if tg.has_method("would_replace_bed_cap"):
				replace_cap = tg.would_replace_bed_cap(hit.x, hit.z)
		if replace_cap:
			hit.y = top_y - TerrainVoxelGrid.CELL_SIZE * 0.5
		else:
			hit.y = top_y + TerrainVoxelGrid.CELL_SIZE * 0.5
	if _preview.material_override is StandardMaterial3D:
		var pm: StandardMaterial3D = _preview.material_override as StandardMaterial3D
		var c: Color = _preview_color_for_tool()
		pm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		pm.albedo_color = Color(c.r, c.g, c.b, 1.0)
		pm.emission = c.lightened(0.2)
	_preview.global_position = hit


func begin_drag(pos: Vector2) -> bool:
	# Paint / sculpt tools must not steal the first click for hardscape drag.
	if tool in [
		"object", "block", "eraser", "fill", "grad", "line", "box", "paste",
		"eyedropper", "trim", "select", "dig", "smooth", "raise",
	] or tool in AQUASCAPE_TERRAIN_TOOLS or TerrainVoxelGrid.tool_is_terrain(tool):
		return false
	if _multi_select.size() > 1:
		_wood_drag = null
		_drag_cluster = _multi_select.duplicate()
		_wood_drag_last_hit = project_to_substrate(pos)
		return true
	if _multi_select.size() == 1 and is_instance_valid(_multi_select[0]):
		_wood_drag = _multi_select[0]
		_drag_cluster.clear()
		_wood_drag_y_offset = _wood_drag.global_position.y - _substrate_top_y()
		_wood_drag_last_hit = project_to_substrate(pos)
		return true
	var picked: Node3D = _pick_hardscape_piece(pos)
	if picked != null:
		_wood_drag = picked
		_drag_cluster.clear()
		_wood_drag_y_offset = picked.global_position.y - _substrate_top_y()
		_wood_drag_last_hit = project_to_substrate(pos)
		return true
	var hit: Vector3 = project_to_substrate(pos)
	if hit != INVALID_HIT:
		var cluster: Array[Node3D] = _gather_procedural_cluster(hit)
		if not cluster.is_empty():
			_wood_drag = null
			_drag_cluster = cluster
			_wood_drag_last_hit = hit
			return true
	return false


func end_drag() -> void:
	_wood_drag = null
	_drag_cluster.clear()
	_wood_drag_last_hit = INVALID_HIT
	end_gumball_drag()
	_sync_placement_gizmo()


func has_selection() -> bool:
	if _selected_build_cell != INVALID_GRID and _build_grid.has_cell(_selected_build_cell):
		return true
	if _multi_select.size() > 0:
		return true
	if _wood_drag != null and is_instance_valid(_wood_drag):
		return true
	return not _drag_cluster.is_empty()


func clear_selection() -> void:
	_selected_build_cell = INVALID_GRID
	_multi_select.clear()
	_wood_drag = null
	_drag_cluster.clear()
	_click_anchor = INVALID_GRID
	end_gumball_drag()
	_sync_placement_gizmo()
	if _selection_label != null:
		_selection_label.text = "Nothing selected — Select tool or Shift+click"


func begin_gumball_drag(mouse_pos: Vector2) -> bool:
	if not gumball_enabled or not has_selection():
		return false
	var axis: int = _pick_gumball_axis(mouse_pos)
	if axis == 0:
		return false
	_gumball_axis = axis
	_gumball_nodes_start.clear()
	for n in _selection_nodes():
		if is_instance_valid(n):
			_gumball_nodes_start.append({"node": n, "pos": n.global_position})
	var pivot: Vector3 = _selection_pivot()
	_gumball_axis_start = _axis_scalar_at_mouse(axis, pivot, mouse_pos)
	return true


func drag_gumball(mouse_pos: Vector2) -> void:
	if _gumball_axis == 0 or _gumball_nodes_start.is_empty():
		return
	var pivot: Vector3 = _gumball_nodes_start[0]["pos"] as Vector3
	for entry in _gumball_nodes_start:
		pivot = (pivot + (entry["pos"] as Vector3)) * 0.5
	var cur: float = _axis_scalar_at_mouse(_gumball_axis, pivot, mouse_pos)
	var delta_scalar: float = cur - _gumball_axis_start
	var delta: Vector3 = _axis_vector(_gumball_axis) * delta_scalar
	for entry in _gumball_nodes_start:
		var n: Node3D = entry["node"] as Node3D
		if is_instance_valid(n):
			n.global_position = (entry["pos"] as Vector3) + delta
	_sync_placement_gizmo()


func end_gumball_drag() -> void:
	_gumball_axis = 0
	_gumball_nodes_start.clear()


func nudge_selection(delta: Vector3) -> void:
	var nodes: Array[Node3D] = _selection_nodes()
	if nodes.is_empty():
		return
	for n in nodes:
		if is_instance_valid(n):
			n.global_position += delta
	_haptic(8)
	_sync_placement_gizmo()


func snap_camera(view: String) -> void:
	if _host == null:
		return
	if view == "top":
		if _host.has_method("_aquascape_camera_snap"):
			_host.call("_aquascape_camera_snap", view)
		if _host.has_method("apply_camera_preset"):
			_host.call("apply_camera_preset", "top")
		if _host.has_method("apply_camera_projection"):
			_host.call("apply_camera_projection", "top_down_ortho")
	else:
		if _host.has_method("apply_camera_projection"):
			_host.call("apply_camera_projection", "perspective")
		if _host.has_method("_aquascape_camera_snap"):
			_host.call("_aquascape_camera_snap", view)


func update_workbench(mouse_pos: Vector2) -> void:
	update_preview(mouse_pos)
	if _coord_label == null and _status_label == null:
		return
	var world_pt: Vector3 = _workbench_world_point(mouse_pos)
	if _coord_label != null:
		if world_pt == INVALID_HIT:
			_coord_label.text = "X —  Y —  Z —"
		else:
			_coord_label.text = "X %.2f  Y %.2f  Z %.2f" % [world_pt.x, world_pt.y, world_pt.z]
	if _status_label != null:
		var parts: PackedStringArray = []
		parts.append("Tool %s" % tool)
		if tool in ["sand", "gravel", "dig", "aquasoil", "peat"] or tool in AQUASCAPE_TERRAIN_TOOLS:
			parts.append("r%d" % brush_radius)
			if tool in ["sand", "gravel"]:
				parts.append("settles")
		if tool == "smooth":
			parts.append("r%d shave+fill" % brush_radius)
			parts.append("refills surface material")
		elif tool == "raise":
			parts.append("r%d add %s" % [brush_radius, _active_substrate_tool()])
		elif tool == "object":
			var obj: Dictionary = AquascapeObjectLibrary.get_object(selected_object_id)
			parts.append(String(obj.get("name", selected_object_id)))
			if stamp_mode:
				parts.append("stamp drag")
		elif tool in ["block", "line", "box", "fill", "grad", "paste", "eraser", "object"]:
			if tool == "eraser":
				parts.append("r%d" % brush_radius)
			if not gravity_mode:
				parts.append("plane y=%.1f" % build_plane_y)
				parts.append("Shift+scroll plane")
			else:
				parts.append("surface snap")
			var g: Vector3i = _target_build_cell(mouse_pos)
			if g != INVALID_GRID:
				parts.append("cell %d,%d,%d" % [g.x, g.y, g.z])
				if _preview_overlaps_solid(g):
					parts.append("ghost cursor")
		var snaps: PackedStringArray = []
		if snap_grid:
			snaps.append("grid")
		if ortho_move:
			snaps.append("ortho")
		if gumball_enabled:
			snaps.append("gumball")
		if not snaps.is_empty():
			parts.append(", ".join(snaps))
		_status_label.text = " · ".join(parts)
	if _selection_label != null:
		var nodes: Array[Node3D] = _selection_nodes()
		if nodes.is_empty():
			if _selected_build_cell != INVALID_GRID and _build_grid.has_cell(_selected_build_cell):
				_selection_label.text = "Build voxel %d,%d,%d · Erase or Pick color" % [
					_selected_build_cell.x, _selected_build_cell.y, _selected_build_cell.z]
			else:
				_selection_label.text = "Nothing selected — Select tool or Shift+click"
		else:
			var p: Vector3 = _selection_pivot()
			_selection_label.text = "%d selected · pivot %.2f, %.2f, %.2f · Q/E rotate" % [
				nodes.size(), p.x, p.y, p.z]


func _workbench_world_point(mouse_pos: Vector2) -> Vector3:
	if tool in ["block", "eraser", "line", "box", "fill", "grad", "paste", "object"]:
		var g: Vector3i = _target_build_cell(mouse_pos)
		if g != INVALID_GRID:
			return _build_grid.grid_to_world(g)
	var hit: Vector3 = project_to_substrate(mouse_pos)
	return hit


func _selection_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in _multi_select:
		if is_instance_valid(n):
			out.append(n)
	if out.is_empty() and _wood_drag != null and is_instance_valid(_wood_drag):
		out.append(_wood_drag)
	if out.is_empty():
		for n in _drag_cluster:
			if is_instance_valid(n):
				out.append(n)
	return out


func _selection_pivot() -> Vector3:
	var nodes: Array[Node3D] = _selection_nodes()
	if nodes.is_empty():
		return Vector3.ZERO
	var pivot: Vector3 = nodes[0].global_position
	for n in nodes:
		pivot = (pivot + n.global_position) * 0.5
	return pivot


func _axis_vector(axis: int) -> Vector3:
	match axis:
		1: return Vector3.RIGHT
		2: return Vector3.UP
		3: return Vector3.FORWARD
	return Vector3.ZERO


func _axis_scalar_at_mouse(axis: int, pivot: Vector3, mouse_pos: Vector2) -> float:
	var ray: Dictionary = _camera_ray(mouse_pos)
	if ray.is_empty():
		return 0.0
	var axis_dir: Vector3 = _axis_vector(axis)
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z.normalized()
	var plane_normal: Vector3 = cam_fwd.cross(axis_dir)
	if plane_normal.length_squared() < 0.0001:
		plane_normal = axis_dir.cross(Vector3.UP)
	if plane_normal.length_squared() < 0.0001:
		plane_normal = Vector3.UP
	plane_normal = plane_normal.normalized()
	var denom: float = plane_normal.dot(ray.dir)
	if absf(denom) < 0.0001:
		return pivot.dot(axis_dir)
	var t: float = plane_normal.dot(pivot - ray.origin) / denom
	var pt: Vector3 = ray.origin + ray.dir * t
	return pt.dot(axis_dir)


func _pick_gumball_axis(mouse_pos: Vector2) -> int:
	if _placement_gizmo == null or not _placement_gizmo.visible:
		return 0
	var ray: Dictionary = _camera_ray(mouse_pos)
	if ray.is_empty():
		return 0
	var pivot: Vector3 = _selection_pivot()
	var best_axis: int = 0
	var best_dist: float = 0.35
	for axis_name in ["x", "y", "z"]:
		var handle: Node3D = _axis_handles.get(axis_name, null) as Node3D
		if handle == null:
			continue
		var end: Vector3 = handle.global_position
		var d: float = _ray_segment_distance(ray.origin, ray.dir, pivot, end)
		if d < best_dist:
			best_dist = d
			best_axis = 1 if axis_name == "x" else (2 if axis_name == "y" else 3)
	return best_axis


func _ray_segment_distance(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.0001:
		return origin.distance_to(a)
	var t: float = clampf((origin - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	var w: Vector3 = origin - closest
	var proj: float = w.dot(dir)
	return (w - dir * proj).length()


func drag_hardscape(mouse_pos: Vector2) -> void:
	var has_single: bool = _wood_drag != null and is_instance_valid(_wood_drag)
	if not has_single and _drag_cluster.is_empty():
		return
	var hit: Vector3 = project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		return
	if _wood_drag_last_hit == INVALID_HIT:
		_wood_drag_last_hit = hit
	var d: Vector3 = hit - _wood_drag_last_hit
	_wood_drag_last_hit = hit
	var dxz: Vector3 = Vector3(d.x, 0.0, d.z)
	if ortho_move and dxz.length_squared() > 0.0001:
		if absf(dxz.x) >= absf(dxz.z):
			dxz.z = 0.0
		else:
			dxz.x = 0.0
	if has_single:
		var np: Vector3 = _wood_drag.global_position + dxz
		np.y = column_top_y(np.x, np.z, _wood_drag) + _wood_drag_y_offset
		_wood_drag.global_position = np
	else:
		for v in _drag_cluster:
			if is_instance_valid(v):
				v.global_position += dxz


func place(mouse_pos: Vector2) -> void:
	if _world == null:
		return
	var hit: Vector3 = project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		return
	var snapped_xz: Vector2 = _snap_xz(hit.x, hit.z)
	hit.x = snapped_xz.x
	hit.z = snapped_xz.y
	if tool == "dig":
		_dig(hit)
		return
	if tool == "trim":
		_trim_at(hit)
		return
	if tool == "block":
		_place_build_voxel(mouse_pos)
		return
	if tool == "eraser":
		_erase_build_voxel(mouse_pos)
		return
	if tool == "object":
		_place_library_object(mouse_pos)
		return
	if tool == "eyedropper":
		_eyedrop_build_color(mouse_pos)
		return
	if tool == "line":
		_handle_line_click(mouse_pos)
		return
	if tool == "box":
		_handle_box_click(mouse_pos)
		return
	if tool == "paste":
		_paste_clipboard(mouse_pos)
		return
	if tool == "fill":
		_flood_fill_at(mouse_pos)
		return
	if tool == "grad":
		_gradient_fill_at(mouse_pos)
		return
	if tool == "select":
		_select_hardscape(mouse_pos)
		return
	if tool in AQUASCAPE_TERRAIN_TOOLS or TerrainVoxelGrid.tool_is_terrain(tool) \
			or tool in ["raise", "smooth"]:
		_place_terrain(hit)
		return
	var top_y: float = column_top_y(hit.x, hit.z)
	if tool == "wood":
		_place_log(Vector3(hit.x, top_y, hit.z))
		return
	_place_stone(hit, top_y)


func undo() -> void:
	if not is_active or _undo_stack.is_empty():
		return
	var rec: Dictionary = _undo_stack.pop_back()
	_apply_undo_record(rec, true)
	_redo_stack.append(rec)
	if _redo_stack.size() > UNDO_MAX:
		_redo_stack.pop_front()
	_haptic(15)


func redo() -> void:
	if not is_active or _redo_stack.is_empty():
		return
	var rec: Dictionary = _redo_stack.pop_back()
	_apply_redo_record(rec)
	_undo_stack.append(rec)
	_haptic(12)


func _apply_undo_record(rec: Dictionary, _is_undo: bool) -> void:
	match String(rec.get("kind", "")):
		"terrain_cell":
			if _world.has_method("terrain_restore_cell"):
				_world.terrain_restore_cell(rec.get("payload", {}))
			_rebuild_substrate_mesh(true)
		"terrain_brush":
			for cell in rec.get("cells", []):
				if _world.has_method("terrain_restore_cell"):
					_world.terrain_restore_cell(cell)
			_rebuild_substrate_mesh(true)
		"hardscape":
			var node: Node = rec.get("node") as Node
			if is_instance_valid(node):
				_placed.erase(node)
				node.queue_free()
		"plant_trim":
			var plant: Plant = rec.get("plant") as Plant
			var snap: Dictionary = rec.get("snapshot", {})
			if is_instance_valid(plant) and not snap.is_empty():
				plant.apply_save_dict(snap)
		"build_place":
			var g: Vector3i = rec.get("grid", Vector3i.ZERO)
			_build_grid.remove_cell(g)
		"build_remove":
			var prev: Dictionary = rec.get("prev", {})
			var g2: Vector3i = prev.get("grid", Vector3i.ZERO)
			_build_grid.place_cell(g2, prev.get("color", build_color), String(prev.get("finish", "matte")))
		"build_stroke":
			for sub in rec.get("subs", []):
				_apply_undo_record(sub, true)
		"build_object":
			for sub in rec.get("cells", []):
				_build_grid.remove_cell(sub.get("grid", Vector3i.ZERO))
		_:
			pass


func _apply_redo_record(rec: Dictionary) -> void:
	match String(rec.get("kind", "")):
		"build_place":
			var g: Vector3i = rec.get("grid", Vector3i.ZERO)
			_build_grid.place_cell(g, rec.get("color", build_color), String(rec.get("finish", "matte")))
		"build_remove":
			_build_grid.remove_cell(rec.get("grid", Vector3i.ZERO))
		"build_stroke":
			for sub in rec.get("subs", []):
				_apply_redo_record(sub)
		"build_object":
			var origin: Vector3 = rec.get("origin", Vector3.ZERO)
			var oid: String = String(rec.get("object_id", ""))
			var params: Dictionary = rec.get("params", {})
			_place_object_mesh(origin, oid, params, false)
		_:
			pass


func to_save_arr() -> Array:
	var out: Array = []
	for v in _placed:
		if not is_instance_valid(v):
			continue
		var t: String = String(v.get_meta("aquascape_tool", ""))
		if v.has_meta("aquascape_object_id"):
			var params: Dictionary = {}
			if v.has_meta("aquascape_object_params"):
				params = v.get_meta("aquascape_object_params")
			out.append({
				"kind": "library_object",
				"tool": t,
				"object_id": String(v.get_meta("aquascape_object_id")),
				"pos": SaveHelpers.vec3_to_array(v.global_position),
				"params": params,
			})
			continue
		if v is MeshInstance3D:
			var mi: MeshInstance3D = v
			var bm: BoxMesh = mi.mesh as BoxMesh
			var color: Color = Color.WHITE
			if mi.material_override is BaseMaterial3D:
				color = (mi.material_override as BaseMaterial3D).albedo_color
			out.append({
				"kind": "voxel",
				"tool": t,
				"pos": SaveHelpers.vec3_to_array(mi.global_position),
				"size": SaveHelpers.vec3_to_array(bm.size if bm != null else Vector3.ONE),
				"color": SaveHelpers.color_to_array(color),
			})
		else:
			var segs: Array = []
			for child in v.get_children():
				if not (child is MeshInstance3D):
					continue
				var seg: MeshInstance3D = child
				var seg_bm: BoxMesh = seg.mesh as BoxMesh
				var seg_color: Color = Color.WHITE
				if seg.material_override is BaseMaterial3D:
					seg_color = (seg.material_override as BaseMaterial3D).albedo_color
				segs.append({
					"offset": SaveHelpers.vec3_to_array(seg.position),
					"size": SaveHelpers.vec3_to_array(seg_bm.size if seg_bm != null else Vector3.ONE),
					"color": SaveHelpers.color_to_array(seg_color),
				})
			out.append({
				"kind": "log",
				"tool": t,
				"pos": SaveHelpers.vec3_to_array(v.global_position),
				"segments": segs,
			})
	out.append_array(_build_grid.to_save_arr())
	out.append({
		"kind": "build_meta",
		"gravity_mode": gravity_mode,
		"build_plane_y": build_plane_y,
	})
	return out


func restore_from_save(arr: Array) -> void:
	if _world == null:
		return
	if _build_grid != null:
		_build_grid.clear()
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	var hardscape := _world.get_node_or_null("Hardscape")
	if hardscape == null:
		hardscape = _world
	var build_entries: Array = []
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var kind: String = String(entry.get("kind", ""))
		if kind == "build_voxel" or kind == "build_meta":
			build_entries.append(entry)
			continue
		var t: String = String(entry.get("tool", ""))
		var pos: Vector3 = SaveHelpers.array_to_vec3(entry.get("pos", []), Vector3.ZERO)
		if kind == "library_object":
			var oid: String = String(entry.get("object_id", ""))
			var params: Dictionary = entry.get("params", {})
			var obj_node: Node3D = ObjectMeshes.spawn(oid, params)
			hardscape.add_child(obj_node)
			obj_node.global_position = pos
			obj_node.set_meta("aquascape_tool", "object")
			obj_node.set_meta("aquascape_object_id", oid)
			if not params.is_empty():
				obj_node.set_meta("aquascape_object_params", params)
			_placed.append(obj_node)
			var fp: Vector3 = ObjectMeshes.footprint(oid, params)
			if _world.has_method("_mark_hardscape_occupancy"):
				_world._mark_hardscape_occupancy(pos, fp)
		elif kind == "voxel":
			var size: Vector3 = SaveHelpers.array_to_vec3(entry.get("size", []), Vector3(0.5, 0.5, 0.5))
			var color: Color = SaveHelpers.array_to_color(entry.get("color", []), Color.WHITE)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			if voxel_mat_script != null:
				mi.material_override = voxel_mat_script.make(color)
			else:
				var sm := StandardMaterial3D.new()
				sm.albedo_color = color
				mi.material_override = sm
			hardscape.add_child(mi)
			mi.global_position = pos
			mi.set_meta("aquascape_tool", t)
			_placed.append(mi)
			if _world.has_method("_mark_hardscape_occupancy"):
				_world._mark_hardscape_occupancy(pos, size)
		elif kind == "log":
			var log_node := Node3D.new()
			log_node.name = "AquaLog"
			hardscape.add_child(log_node)
			log_node.global_position = pos
			for seg_entry in entry.get("segments", []):
				if not (seg_entry is Dictionary):
					continue
				var seg := MeshInstance3D.new()
				var seg_bm := BoxMesh.new()
				seg_bm.size = SaveHelpers.array_to_vec3(seg_entry.get("size", []), Vector3(0.7, 0.6, 0.7))
				seg.mesh = seg_bm
				var c: Color = SaveHelpers.array_to_color(seg_entry.get("color", []), Color.WHITE)
				if voxel_mat_script != null:
					seg.material_override = voxel_mat_script.make(c)
				else:
					var sm := StandardMaterial3D.new()
					sm.albedo_color = c
					seg.material_override = sm
				log_node.add_child(seg)
				seg.position = SaveHelpers.array_to_vec3(seg_entry.get("offset", []), Vector3.ZERO)
			log_node.set_meta("aquascape_tool", t)
			_placed.append(log_node)
	for meta in build_entries:
		if String(meta.get("kind", "")) == "build_meta":
			gravity_mode = bool(meta.get("gravity_mode", true))
			build_plane_y = float(meta.get("build_plane_y", build_plane_y))
			if _build_grid != null:
				_build_grid.set_gravity_mode(gravity_mode)
	if _build_grid != null:
		_build_grid.restore_from_save(build_entries)
	refresh_build_appearance()


func refresh_build_appearance() -> void:
	if _build_grid != null and _build_grid.has_method("refresh_voxel_appearance"):
		_build_grid.refresh_voxel_appearance()
	if _world != null and _world.has_method("rebuild_substrate_mesh"):
		_world.rebuild_substrate_mesh()


func project_to_substrate(mouse_pos: Vector2) -> Vector3:
	if _camera == null:
		return INVALID_HIT
	var sv_pos: Vector2 = _host.call("_window_mouse_to_viewport", mouse_pos)
	var origin: Vector3 = _camera.project_ray_origin(sv_pos)
	var dir: Vector3 = _camera.project_ray_normal(sv_pos)
	var plane_y: float = float(_world.get("SUBSTRATE_DEPTH")) if _world != null else 1.6
	if dir.y > -0.01:
		return INVALID_HIT
	var t: float = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return INVALID_HIT
	var hit: Vector3 = origin + dir * t
	if _world.has_method("is_inside_tank"):
		if not _world.is_inside_tank(hit.x, hit.z, 0.3):
			return INVALID_HIT
	if _world.has_method("column_surface_y"):
		hit.y = _world.column_surface_y(hit.x, hit.z)
	return hit


func column_top_y(x: float, z: float, exclude: Node = null) -> float:
	var top: float = float(_world.get("SUBSTRATE_DEPTH")) if _world != null else 1.6
	if _world.has_method("column_surface_y"):
		top = _world.column_surface_y(x, z)
	var hs: Node3D = _hardscape_node()
	if hs != null:
		top = _scan_column_top(hs, x, z, exclude, top)
	for v in _placed:
		if not is_instance_valid(v) or v == exclude:
			continue
		if v.get_parent() == hs:
			continue
		var gp: Vector3 = v.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var size_y: float = 0.5
			if v is MeshInstance3D:
				var bm := (v as MeshInstance3D).mesh as BoxMesh
				if bm != null:
					size_y = bm.size.y
			top = maxf(top, gp.y + size_y * 0.5)
	if _build_grid != null and _build_grid.has_method("column_top_y_at"):
		top = maxf(top, _build_grid.column_top_y_at(x, z))
	return top


func _place_terrain(hit: Vector3) -> void:
	var fill_tool: String = _active_substrate_tool()
	if tool == "smooth" and _world.has_method("terrain_smooth_brush"):
		if _world.get("terrain_grid") != null:
			var tg: TerrainVoxelGrid = _world.terrain_grid
			fill_tool = TerrainVoxelGrid.tool_from_material(tg.surface_material_at(hit.x, hit.z))
		var cells: Array = _world.terrain_smooth_brush(hit.x, hit.z, brush_radius, fill_tool)
		if not cells.is_empty():
			_push_undo({"kind": "terrain_brush", "cells": cells, "label": "smooth"})
			_rebuild_substrate_mesh(true)
			_haptic(10)
		return
	if tool == "raise" and _world.has_method("terrain_raise_brush"):
		var raised: Array = _world.terrain_raise_brush(hit.x, hit.z, brush_radius, fill_tool)
		if not raised.is_empty():
			_push_undo({"kind": "terrain_brush", "cells": raised, "label": "raise"})
			_rebuild_substrate_mesh(true)
			_haptic(10)
		return
	if brush_radius <= 1:
		if _world.has_method("terrain_place_tool"):
			var terrain_undo: Dictionary = _world.terrain_place_tool(hit.x, hit.z, tool)
			if not terrain_undo.is_empty():
				_push_undo({"kind": "terrain_cell", "payload": terrain_undo, "label": tool})
				_rebuild_substrate_mesh(false)
				_haptic(8)
	else:
		if _world.has_method("terrain_place_brush"):
			var cells: Array = _world.terrain_place_brush(
				hit.x, hit.z, brush_radius, tool)
			if not cells.is_empty():
				_push_undo({"kind": "terrain_brush", "cells": cells, "label": "%s brush" % tool})
				_rebuild_substrate_mesh(false)
				_haptic(8)


func _dig(hit: Vector3) -> void:
	var terrain_top: float = hit.y
	if _world.has_method("column_surface_y"):
		terrain_top = _world.column_surface_y(hit.x, hit.z)
	var hs: Node3D = _hardscape_node()
	var acc: Dictionary = {"node": null, "y": -INF}
	if hs != null:
		_scan_top_voxel(hs, hit.x, hit.z, acc)
	var best: Node = acc["node"]
	var hs_top_y: float = float(acc["y"])
	if best != null and hs_top_y > terrain_top + 0.05:
		_push_undo({"kind": "hardscape", "node": best, "label": "hardscape"})
		_placed.erase(best)
		best.queue_free()
		_haptic(12)
		return
	if brush_radius <= 1:
		if _world.has_method("terrain_dig"):
			var terrain_undo: Dictionary = _world.terrain_dig(hit.x, hit.z)
			if terrain_undo.is_empty() or int(terrain_undo.get("mat", TerrainVoxelGrid.CellMaterial.EMPTY)) \
					== TerrainVoxelGrid.CellMaterial.EMPTY:
				return
			_push_undo({"kind": "terrain_cell", "payload": terrain_undo, "label": "dig"})
			_rebuild_substrate_mesh(false)
			_haptic(12)
	elif _world.has_method("terrain_dig_brush"):
		var cells: Array = _world.terrain_dig_brush(hit.x, hit.z, brush_radius)
		if not cells.is_empty():
			_push_undo({"kind": "terrain_brush", "cells": cells, "label": "dig brush"})
			_rebuild_substrate_mesh(false)
			_haptic(12)


func _trim_at(hit: Vector3) -> void:
	var sim: Node = _host.get("_sim") if _host != null else null
	if sim == null:
		return
	var best: Plant = null
	var best_d2: float = 2.25
	for p in sim.plants:
		if not is_instance_valid(p):
			continue
		var pp: Vector3 = p.global_position
		var d2: float = Vector2(pp.x - hit.x, pp.z - hit.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = p
	if best == null or not best.has_method("trim_for_aquascape"):
		return
	var amount: float = 0.25 if trim_mode == "all" else 0.18
	var snap: Dictionary = best.trim_for_aquascape(amount, trim_mode)
	if snap.is_empty():
		return
	_push_undo({"kind": "plant_trim", "plant": best, "snapshot": snap, "label": "trim"})
	_haptic(10)


func _place_stone(hit: Vector3, top_y: float) -> void:
	var palette: Array[Color] = [
		Color8(85, 85, 96), Color8(75, 70, 78),
		Color8(105, 100, 92), Color8(60, 60, 70),
	]
	var color: Color = palette[randi() % palette.size()]
	var presets: Array[Vector3] = [
		Vector3(0.9, 0.9, 0.9), Vector3(1.2, 0.5, 0.8),
		Vector3(0.7, 1.0, 0.7), Vector3(1.4, 0.9, 0.6),
	]
	var voxel_size: Vector3 = presets[mini(brush_radius - 1, presets.size() - 1)]
	hit.y = top_y + voxel_size.y * 0.5
	var hs := _hardscape_node()
	if brush_radius >= 3:
		_place_stone_cluster(hit, color, hs)
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = voxel_size
	mi.mesh = bm
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	if voxel_mat_script != null:
		mi.material_override = voxel_mat_script.make(color)
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		mi.material_override = sm
	hs.add_child(mi)
	mi.global_position = hit
	mi.set_meta("aquascape_tool", "stone")
	_placed.append(mi)
	_push_undo({"kind": "hardscape", "node": mi, "label": "stone"})
	if _world.has_method("_mark_hardscape_occupancy"):
		_world._mark_hardscape_occupancy(hit, voxel_size)
	_haptic(8)


func _place_log(base: Vector3) -> void:
	var hardscape := _world.get_node_or_null("Hardscape")
	if hardscape == null:
		hardscape = _world
	var log_node := Node3D.new()
	log_node.name = "AquaLog"
	hardscape.add_child(log_node)
	log_node.global_position = base + Vector3(0, 0.35, 0)
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	var n_segments: int = 5
	var curve_sign: float = 1.0
	var forward: Vector3 = Vector3(1, 0, 0)
	match wood_form:
		"spider":
			n_segments = 7
			curve_sign = 1.4
			forward = Vector3(0.7, 0, 0.7)
		"stump":
			n_segments = 3
			curve_sign = 0.2
		"root":
			n_segments = 6
			curve_sign = -1.2
			forward = Vector3(-0.5, 0, 0.8)
	var dark := Color8(58, 38, 22)
	var mid := Color8(78, 52, 32)
	var light := Color8(98, 70, 46)
	var palette: Array[Color] = [dark, mid, light, mid, dark]
	for i in n_segments:
		var t: float = float(i) / float(maxi(1, n_segments - 1))
		var perp: Vector3 = Vector3(-forward.z, 0, forward.x) * curve_sign
		var offset: Vector3 = forward * (i - n_segments * 0.5) * 0.6 \
			+ perp * sin(t * PI) * 0.35
		offset.y = sin(t * PI) * 0.2
		var seg := MeshInstance3D.new()
		var seg_bm := BoxMesh.new()
		var s: float = 0.7 + randf_range(-0.1, 0.1)
		seg_bm.size = Vector3(s, s * 0.85, s)
		seg.mesh = seg_bm
		var c: Color = palette[i % palette.size()]
		if voxel_mat_script != null:
			seg.material_override = voxel_mat_script.make(c)
		else:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = c
			seg.material_override = sm
		log_node.add_child(seg)
		seg.position = offset
	log_node.set_meta("aquascape_tool", "wood")
	_placed.append(log_node)
	_push_undo({"kind": "hardscape", "node": log_node, "label": "wood"})
	_haptic(8)


func begin_stroke() -> void:
	if tool in ["block", "eraser", "line", "box"]:
		_stroke_active = true
		_stroke_batch.clear()


func end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if _stroke_batch.is_empty():
		return
	var batch: Dictionary = {"kind": "build_stroke", "subs": _stroke_batch.duplicate(true), "label": tool}
	_redo_stack.clear()
	_undo_stack.append(batch)
	if _undo_stack.size() > UNDO_MAX:
		_undo_stack.pop_front()
	_stroke_batch.clear()


func _push_undo(rec: Dictionary) -> void:
	if _stroke_active and String(rec.get("kind", "")).begins_with("build_"):
		_stroke_batch.append(rec)
		return
	_redo_stack.clear()
	_undo_stack.append(rec)
	if _undo_stack.size() > UNDO_MAX:
		_undo_stack.pop_front()


func _rebuild_substrate_mesh(force: bool) -> void:
	if not _world.has_method("rebuild_substrate_mesh"):
		return
	if force:
		_world.rebuild_substrate_mesh()
		_mesh_rebuild_cooldown = 0.0
		return
	if _mesh_rebuild_cooldown > 0.0:
		return
	_mesh_rebuild_cooldown = MESH_REBUILD_INTERVAL
	_world.rebuild_substrate_mesh()


func _build_palette() -> void:
	if _palette == null:
		return
	for c in _palette.get_children():
		c.queue_free()
	_tool_buttons.clear()
	_toggle_buttons.clear()
	_finish_buttons.clear()
	_color_swatches.clear()
	_color_values.clear()
	_color_b_swatches.clear()
	_color_b_values.clear()
	_object_row = null
	_cat_row = null
	PanelTheme.apply_aquascape_toolbar_chrome(_palette)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 6)
	outer.add_theme_constant_override("margin_right", 6)
	outer.add_theme_constant_override("margin_top", 4)
	outer.add_theme_constant_override("margin_bottom", 4)
	_palette.add_child(outer)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	outer.add_child(root)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	root.add_child(header_row)
	var header := PanelTheme.as_serif(Label.new(), PanelTheme.SIZE_SECTION, true)
	header.text = "Workbench"
	header.add_theme_color_override("font_color", Color8(255, 220, 80))
	header_row.add_child(header)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)
	_budget_label = Label.new()
	PanelTheme.as_mono(_budget_label, PanelTheme.SIZE_CAPTION)
	_budget_label.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	header_row.add_child(_budget_label)

	root.add_child(PanelTheme.make_section("Snaps"))
	var snap_row := HBoxContainer.new()
	snap_row.add_theme_constant_override("separation", 3)
	root.add_child(snap_row)
	snap_row.add_child(_make_toggle_button("snap", "Grid", func(on): snap_grid = on, func(): return snap_grid))
	snap_row.add_child(_make_toggle_button("ortho", "Ortho", func(on): ortho_move = on, func(): return ortho_move))
	snap_row.add_child(_make_toggle_button("gumball", "Gumball", func(on): gumball_enabled = on, func(): return gumball_enabled))
	snap_row.add_child(_make_toggle_button("mir_x", "Mir X", func(on): mirror_x = on, func(): return mirror_x))
	snap_row.add_child(_make_toggle_button("mir_z", "Mir Z", func(on): mirror_z = on, func(): return mirror_z))

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 108)
	root.add_child(tabs)

	_build_terrain_tab(_new_palette_tab(tabs, "Terrain"))
	_build_build_tab(_new_palette_tab(tabs, "Build"))
	_build_objects_tab(_new_palette_tab(tabs, "Objects"))
	_build_tools_tab(_new_palette_tab(tabs, "Tools"))

	var hint := Label.new()
	hint.text = "1–4 views · [ ] brush · arrows nudge · Q/E rotate"
	PanelTheme.as_mono(hint, PanelTheme.SIZE_CAPTION)
	hint.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	root.add_child(hint)
	_coord_label = Label.new()
	PanelTheme.as_mono(_coord_label, PanelTheme.SIZE_CAPTION)
	_coord_label.add_theme_color_override("font_color", PanelTheme.VALUE_FG)
	_coord_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_coord_label)
	_status_label = Label.new()
	PanelTheme.as_mono(_status_label, PanelTheme.SIZE_CAPTION)
	_status_label.add_theme_color_override("font_color", PanelTheme.DIM_FG)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)
	_selection_label = Label.new()
	PanelTheme.as_mono(_selection_label, PanelTheme.SIZE_CAPTION)
	_selection_label.add_theme_color_override("font_color", Color8(180, 220, 200))
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_selection_label)
	_craft_label = Label.new()
	PanelTheme.as_mono(_craft_label, PanelTheme.SIZE_CAPTION)
	_craft_label.add_theme_color_override("font_color", Color8(180, 220, 200))
	_craft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_label.max_lines_visible = 2
	root.add_child(_craft_label)
	_refresh_budget_label()
	_refresh_craft_readout()
	_refresh_tool_buttons()


func _new_palette_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	return vbox


func _add_palette_section(parent: VBoxContainer, title: String) -> HBoxContainer:
	parent.add_child(PanelTheme.make_spacer(2))
	parent.add_child(PanelTheme.make_section(title))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	return row


func _build_terrain_tab(parent: VBoxContainer) -> void:
	var mats := _add_palette_section(parent, "Substrate")
	for def in [
		{"key": "aquasoil", "label": "Soil", "tip": "Rich nutrients · medium bleed · plant soil"},
		{"key": "sand", "label": "Sand", "tip": "Fine grains · settles with gravity · low nutrients"},
		{"key": "gravel", "label": "Gravel", "tip": "Drainage cap · blocks nutrient bleed · inert"},
		{"key": "peat", "label": "Peat", "tip": "Dark & rich · tannins · high nutrients"},
		{"key": "lava_rock", "label": "Lava", "tip": "Inert porous rock · low nutrients"},
		{"key": "white_sand", "label": "White", "tip": "Bright sand · settles · low nutrients"},
		{"key": "dark_soil", "label": "Dark", "tip": "Deep soil · high nutrients · medium bleed"},
		{"key": "clay", "label": "Clay", "tip": "Heavy clay · moderate nutrients"},
		{"key": "crushed_coral", "label": "Coral", "tip": "Reef sand · alkaline · low plant food"},
	]:
		mats.add_child(_make_tool_button(String(def["key"]), String(def["label"]), String(def["tip"])))
	var hard := _add_palette_section(parent, "Hardscape")
	for def in [
		{"key": "stone", "label": "Rock", "tip": "Free-place stone on surface · brush size changes shape"},
		{"key": "wood", "label": "Wood", "tip": "Driftwood cluster · pick form in Objects tab"},
	]:
		hard.add_child(_make_tool_button(String(def["key"]), String(def["label"]), String(def["tip"])))
	var sculpt := _add_palette_section(parent, "Sculpt")
	for def in [
		{"key": "dig", "label": "Dig", "tip": "Remove substrate · brush widens hole"},
		{"key": "trim", "label": "Trim", "tip": "Trim nearby plants only (not voxels)"},
		{"key": "smooth", "label": "Smooth", "tip": "Shave bumps then refill with surface material"},
		{"key": "raise", "label": "Raise", "tip": "Stack a layer using last substrate picked above"},
	]:
		sculpt.add_child(_make_tool_button(String(def["key"]), String(def["label"]), String(def["tip"])))
	sculpt.add_child(_make_action_button("Slope", apply_back_slope, "Apply back-to-front slope"))
	var opts := _add_palette_section(parent, "Guides")
	opts.add_child(_make_toggle_button("grid", "⅓ Grid", func(on):
		show_composition = on
		_sync_composition_guide(), func(): return show_composition))
	opts.add_child(_make_toggle_button("iwg", "Iwagumi", func(on):
		show_iwagumi = on
		_sync_composition_guide(), func(): return show_iwagumi))
	opts.add_child(_make_toggle_button("depth", "Depth", func(on):
		show_depth_zones = on
		_sync_composition_guide(), func(): return show_depth_zones))


func _build_build_tab(parent: VBoxContainer) -> void:
	var voxel := _add_palette_section(parent, "Voxel tools")
	for def in [
		{"key": "block", "label": "Block", "tip": "Place voxel blocks"},
		{"key": "line", "label": "Line", "tip": "Draw a line of voxels"},
		{"key": "box", "label": "Box", "tip": "Draw a box of voxels"},
		{"key": "fill", "label": "Fill", "tip": "Flood fill voxels"},
		{"key": "grad", "label": "Grad", "tip": "Gradient fill"},
		{"key": "eraser", "label": "Erase", "tip": "Erase voxels"},
		{"key": "paste", "label": "Paste", "tip": "Paste clipboard"},
		{"key": "select", "label": "Select", "tip": "Select hardscape to move or rotate"},
		{"key": "eyedropper", "label": "Pick", "tip": "Pick color / material"},
	]:
		voxel.add_child(_make_tool_button(String(def["key"]), String(def["label"]), String(def["tip"])))
	var color_row := _add_palette_section(parent, "Color")
	for i in mini(8, AquascapeObjectLibrary.BUILD_PALETTE.size()):
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(22, 22)
		sw.tooltip_text = "Build color %d" % (i + 1)
		var col: Color = AquascapeObjectLibrary.BUILD_PALETTE[i]
		sw.modulate = col
		sw.pressed.connect(func(c = col):
			build_color = c
			_refresh_tool_buttons())
		color_row.add_child(sw)
		_color_swatches.append(sw)
		_color_values.append(col)
	var grad_row := _add_palette_section(parent, "Grad B")
	for i in mini(8, AquascapeObjectLibrary.BUILD_PALETTE.size()):
		var swb := Button.new()
		swb.custom_minimum_size = Vector2(22, 22)
		swb.tooltip_text = "Gradient end color %d" % (i + 1)
		var colb: Color = AquascapeObjectLibrary.BUILD_PALETTE[i]
		swb.modulate = colb
		swb.pressed.connect(func(c = colb):
			build_color_b = c
			_refresh_tool_buttons())
		grad_row.add_child(swb)
		_color_b_swatches.append(swb)
		_color_b_values.append(colb)
	var finish_row := _add_palette_section(parent, "Finish")
	for fin in ["matte", "glass", "glow", "metal", "caustic"]:
		var fb := _make_action_button(fin.capitalize(), func(f = fin):
			build_finish = f
			_refresh_tool_buttons(), fin)
		finish_row.add_child(fb)
		_finish_buttons[fin] = fb
	var mods := _add_palette_section(parent, "Modifiers")
	mods.add_child(_make_toggle_button("grav", "Surface", func(on):
		gravity_mode = on
		_build_grid.set_gravity_mode(on), func(): return gravity_mode))
	mods.add_child(_make_toggle_button("shell", "Shell", func(on): hollow_box = on, func(): return hollow_box))
	mods.add_child(_make_choice_button("scale_half", "Half", func():
		build_scale = 0.5
		_build_grid.build_scale = 0.5, func(): return is_equal_approx(build_scale, 0.5)))
	mods.add_child(_make_choice_button("scale_1", "1×", func():
		build_scale = 1.0
		_build_grid.build_scale = 1.0, func(): return is_equal_approx(build_scale, 1.0)))
	mods.add_child(_make_choice_button("scale_2", "2×", func():
		build_scale = 2.0
		_build_grid.build_scale = 2.0, func(): return is_equal_approx(build_scale, 2.0)))
	for bs in ["cube", "sphere", "disc"]:
		mods.add_child(_make_choice_button(
			"shape_%s" % bs,
			bs.capitalize(),
			func(s = bs): brush_shape = s,
			func(s = bs): return brush_shape == s))


func _build_objects_tab(parent: VBoxContainer) -> void:
	var wood := _add_palette_section(parent, "Wood form")
	for wf in ["drift", "spider", "stump", "root"]:
		wood.add_child(_make_action_button(wf.capitalize(), func(f = wf):
			wood_form = f
			set_tool("wood"), wf + " wood silhouette"))
	parent.add_child(PanelTheme.make_section("Library"))
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 4)
	parent.add_child(_cat_row)
	for cat in ["All"] + AquascapeObjectLibrary.CATEGORIES:
		var cb := _make_action_button(cat, func(c = cat):
			_object_category = c
			_refresh_object_buttons()
			_refresh_category_buttons(_cat_row, c), cat + " objects")
		cb.set_meta("category", cat)
		_cat_row.add_child(cb)
	var scroll := ScrollContainer.new()
	_object_panel = scroll
	scroll.custom_minimum_size = Vector2(0, 56)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	_object_row = HBoxContainer.new()
	_object_row.add_theme_constant_override("separation", 4)
	scroll.add_child(_object_row)
	_refresh_object_buttons()
	_refresh_category_buttons(_cat_row, _object_category)
	var castle := _add_palette_section(parent, "Castle")
	castle.add_child(_make_choice_button("t4", "4 towers", func(): castle_towers = 4, func(): return castle_towers == 4))
	castle.add_child(_make_choice_button("t6", "6 towers", func(): castle_towers = 6, func(): return castle_towers == 6))
	castle.add_child(_make_choice_button("h7", "Height 7", func(): castle_height = 7, func(): return castle_height == 7))
	castle.add_child(_make_choice_button("h9", "Height 9", func(): castle_height = 9, func(): return castle_height == 9))
	var trim := _add_palette_section(parent, "Trim mode")
	for tm in ["all", "top", "sides", "mow"]:
		trim.add_child(_make_choice_button(
			"trim_%s" % tm,
			tm.capitalize(),
			func(m = tm):
				trim_mode = m
				set_tool("trim"),
			func(t = tm): return trim_mode == t))


func _build_tools_tab(parent: VBoxContainer) -> void:
	var actions := _add_palette_section(parent, "Actions")
	for bdef in [
		{"t": "Ruin", "fn": func(): ruinify_at(_host.get_viewport().get_mouse_position() if _host else Vector2.ZERO), "tip": "Weather selected build"},
		{"t": "Life", "fn": preview_life, "tip": "Preview epiphyte anchors"},
		{"t": "A/B", "fn": snapshot_ab_compare, "tip": "Compare before/after"},
		{"t": "Photo", "fn": export_scape_photo, "tip": "Export scape photo"},
		{"t": "Top cam", "fn": func():
			if _host:
				_host.call("_aquascape_camera_snap", "top"), "tip": "Snap camera to top-down"},
		{"t": "Library", "fn": open_my_builds_panel, "tip": "My saved builds"},
		{"t": "Gallery", "fn": open_showcase_gallery, "tip": "Community showcase"},
	]:
		actions.add_child(_make_action_button(String(bdef["t"]), bdef["fn"], String(bdef["tip"])))
	actions.add_child(_make_toggle_button("stamp", "Stamp", func(on): stamp_mode = on, func(): return stamp_mode))
	actions.add_child(_make_toggle_button("lights", "Lights", func(on): _set_build_lights(on), func(): return lights_on_build))
	var bp := _add_palette_section(parent, "Blueprints")
	bp.add_child(_make_action_button("Save", _save_blueprint_prompt, "Save blueprint to clipboard"))
	bp.add_child(_make_action_button("Import", _import_blueprint_prompt, "Import blueprint"))
	bp.add_child(_make_action_button("Copy", copy_build, "Copy selected build"))
	var theme_row := _add_palette_section(parent, "Recolor theme")
	for th in ["zen", "coral", "obsidian", "fantasy"]:
		theme_row.add_child(_make_action_button(th.capitalize(), func(t = th):
			recolor_build_theme(t), th + " palette"))
	var kits := _add_palette_section(parent, "Themed kits")
	for kit_id in AquascapeObjectLibrary.themed_kit_ids():
		kits.add_child(_make_action_button(String(kit_id).capitalize(), func(k = kit_id):
			_stamp_themed_kit(k), "Stamp " + String(kit_id) + " kit"))
	var view := _add_palette_section(parent, "View")
	view.add_child(_make_toggle_button("hide_life", "Hide life", func(on):
		set_hide_fauna_layers(on), func(): return hide_fauna_layers))


func _make_tool_button(key: String, label: String, tip: String = "") -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tip
	btn.pressed.connect(func(): set_tool(key))
	PanelTheme.style_compact_tool_button(btn, key == tool)
	_tool_buttons[key] = btn
	return btn


func _make_action_button(label: String, fn: Callable, tip: String = "") -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tip
	btn.pressed.connect(fn)
	PanelTheme.style_compact_tool_button(btn, false)
	return btn


func _make_toggle_button(key: String, label: String, apply_fn: Callable, read_fn: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func():
		apply_fn.call(not read_fn.call())
		_refresh_tool_buttons())
	_toggle_buttons[key] = btn
	PanelTheme.style_compact_tool_button(btn, read_fn.call())
	return btn


func _make_choice_button(key: String, label: String, apply_fn: Callable, read_fn: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func():
		apply_fn.call()
		_refresh_tool_buttons())
	_toggle_buttons[key] = btn
	PanelTheme.style_compact_tool_button(btn, read_fn.call())
	return btn


func _refresh_category_buttons(cat_row: HBoxContainer, active: String) -> void:
	for cb in cat_row.get_children():
		if cb is Button:
			var cat: String = String(cb.get_meta("category", ""))
			PanelTheme.style_compact_tool_button(cb as Button, cat == active)


func _refresh_object_buttons() -> void:
	if _object_row == null:
		return
	for c in _object_row.get_children():
		c.queue_free()
	var objects: Array = AquascapeObjectLibrary.all_objects()
	for o in objects:
		if _object_category != "All" and String(o.get("category", "")) != _object_category:
			continue
		var ob := Button.new()
		ob.text = String(o.get("icon", "?"))
		ob.tooltip_text = "%s — click bed to place 3D prop" % String(o.get("name", ""))
		var oid: String = String(o.get("id", ""))
		ob.pressed.connect(func():
			selected_object_id = oid
			set_tool("object"))
		PanelTheme.style_compact_tool_button(ob, tool == "object" and selected_object_id == oid)
		_object_row.add_child(ob)


func _make_toggle(label: String, fn: Callable) -> Button:
	return _make_action_button(label, fn)


func _refresh_tool_buttons() -> void:
	for k in _tool_buttons.keys():
		var btn: Button = _tool_buttons[k]
		if btn == null:
			continue
		PanelTheme.style_compact_tool_button(btn, k == tool)
	for k in _toggle_buttons.keys():
		var tbtn: Button = _toggle_buttons[k]
		if tbtn == null:
			continue
		var on: bool = false
		match k:
			"snap":
				on = snap_grid
			"grid":
				on = show_composition
			"mir_x":
				on = mirror_x
			"mir_z":
				on = mirror_z
			"ortho":
				on = ortho_move
			"gumball":
				on = gumball_enabled
			"iwg":
				on = show_iwagumi
			"depth":
				on = show_depth_zones
			"shell":
				on = hollow_box
			"grav":
				on = gravity_mode
			"hide_life":
				on = hide_fauna_layers
			"stamp":
				on = stamp_mode
			"lights":
				on = lights_on_build
			"t4":
				on = castle_towers == 4
			"t6":
				on = castle_towers == 6
			"h7":
				on = castle_height == 7
			"h9":
				on = castle_height == 9
			"scale_half":
				on = is_equal_approx(build_scale, 0.5)
			"scale_1":
				on = is_equal_approx(build_scale, 1.0)
			"scale_2":
				on = is_equal_approx(build_scale, 2.0)
			"trim_all":
				on = trim_mode == "all"
			"trim_top":
				on = trim_mode == "top"
			"trim_sides":
				on = trim_mode == "sides"
			"trim_mow":
				on = trim_mode == "mow"
			"shape_cube":
				on = brush_shape == "cube"
			"shape_sphere":
				on = brush_shape == "sphere"
			"shape_disc":
				on = brush_shape == "disc"
		PanelTheme.style_compact_tool_button(tbtn, on)
		if k == "grav":
			tbtn.text = "Surface" if gravity_mode else "Plane"
	for fin in _finish_buttons.keys():
		var fb: Button = _finish_buttons[fin]
		if fb != null:
			PanelTheme.style_compact_tool_button(fb, fin == build_finish)
	for i in _color_swatches.size():
		var sw: Button = _color_swatches[i]
		if sw == null:
			continue
		var col: Color = _color_values[i]
		var picked: bool = build_color.is_equal_approx(col)
		sw.add_theme_stylebox_override("normal", _color_swatch_style(picked))
	for i in _color_b_swatches.size():
		var swb: Button = _color_b_swatches[i]
		if swb == null:
			continue
		var colb: Color = _color_b_values[i]
		var picked_b: bool = build_color_b.is_equal_approx(colb)
		swb.add_theme_stylebox_override("normal", _color_swatch_style(picked_b))
	_refresh_object_buttons()
	if _cat_row != null:
		_refresh_category_buttons(_cat_row, _object_category)


func _color_swatch_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.15, 0.45)
	s.border_color = Color8(255, 220, 80) if active else Color(0.35, 0.45, 0.6, 0.35)
	s.border_width_left = 2 if active else 1
	s.border_width_top = 2 if active else 1
	s.border_width_right = 2 if active else 1
	s.border_width_bottom = 2 if active else 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_bottom_right = 4
	return s


func _ensure_preview() -> void:
	if _preview != null:
		_preview.visible = true
		return
	_preview = MeshInstance3D.new()
	_preview.name = "AquascapePreview"
	var bm := BoxMesh.new()
	bm.size = Vector3(TerrainVoxelGrid.CELL_SIZE, TerrainVoxelGrid.CELL_SIZE, TerrainVoxelGrid.CELL_SIZE)
	_preview.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.6, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.4)
	mat.emission_energy_multiplier = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	_preview.material_override = mat
	_preview.scale = Vector3.ONE * 0.92
	_world.add_child(_preview)


func _preview_overlaps_solid(g: Vector3i) -> bool:
	if _build_grid.has_cell(g):
		return true
	var wp: Vector3 = _build_grid.grid_to_world(g)
	if _world != null and _world.has_method("column_surface_y"):
		var surface_y: float = _world.column_surface_y(wp.x, wp.z)
		var cell_bottom: float = wp.y - TerrainVoxelGrid.CELL_SIZE * 0.5
		if cell_bottom <= surface_y + 0.04:
			return true
	return false


func _preview_color_for_tool() -> Color:
	match tool:
		"aquasoil", "dirt":
			return Color8(120, 85, 56)
		"sand":
			return Color8(225, 215, 185)
		"gravel":
			return Color8(125, 125, 135)
		"peat":
			return Color8(40, 32, 26)
		"stone":
			return Color8(120, 120, 130)
		"wood":
			return Color8(95, 65, 35)
		"trim":
			return Color8(100, 200, 120)
		"dig":
			return Color8(220, 90, 90)
	return Color(1, 1, 0.6, 0.35)


func _hardscape_node() -> Node3D:
	if _world == null:
		return null
	var hs: Node = _world.get_node_or_null("Hardscape")
	return (hs as Node3D) if hs != null else _world


func _pick_hardscape_piece(mouse_pos: Vector2) -> Node3D:
	if _camera == null:
		return null
	var sv_pos: Vector2 = _host.call("_window_mouse_to_viewport", mouse_pos)
	var origin: Vector3 = _camera.project_ray_origin(sv_pos)
	var dir: Vector3 = _camera.project_ray_normal(sv_pos)
	var best: Node3D = null
	var best_t: float = 1e9
	for v in _placed:
		if not is_instance_valid(v):
			continue
		if String(v.get_meta("aquascape_tool", "")) in AQUASCAPE_TERRAIN_TOOLS:
			continue
		var radius: float = 1.6 if String(v.get_meta("aquascape_tool", "")) == "wood" else 0.9
		if String(v.get_meta("aquascape_tool", "")) == "object":
			var oid: String = String(v.get_meta("aquascape_object_id", "boulder"))
			var params: Dictionary = v.get_meta("aquascape_object_params") if v.has_meta("aquascape_object_params") else {}
			radius = maxf(ObjectMeshes.footprint(oid, params).x, 0.8) * 0.55
		var to_c: Vector3 = v.global_position - origin
		var t: float = to_c.dot(dir)
		if t < 0.0:
			continue
		var closest: Vector3 = origin + dir * t
		var perp_sq: float = (closest - v.global_position).length_squared()
		if perp_sq < radius * radius and t < best_t:
			best_t = t
			best = v
	return best


func _gather_procedural_cluster(hit: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var hs: Node3D = _hardscape_node()
	if hs == null:
		return out
	const CLUSTER_R: float = 1.2
	for child in hs.get_children():
		if not (child is MeshInstance3D) or not is_instance_valid(child):
			continue
		if _placed.has(child):
			continue
		var gp: Vector3 = (child as Node3D).global_position
		if Vector2(gp.x - hit.x, gp.z - hit.z).length() < CLUSTER_R:
			out.append(child)
	return out


func _scan_column_top(node: Node, x: float, z: float, exclude: Node, top: float) -> float:
	if node == exclude:
		return top
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var gp: Vector3 = mi.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var sy: float = 0.5
			var bm := mi.mesh as BoxMesh
			if bm != null:
				sy = bm.size.y
			top = maxf(top, gp.y + sy * 0.5)
	for c in node.get_children():
		top = _scan_column_top(c, x, z, exclude, top)
	return top


func _scan_top_voxel(node: Node, x: float, z: float, acc: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var gp: Vector3 = mi.global_position
		if absf(gp.x - x) < 0.45 and absf(gp.z - z) < 0.45:
			var sy: float = 0.5
			var bm := mi.mesh as BoxMesh
			if bm != null:
				sy = bm.size.y
			var topy: float = gp.y + sy * 0.5
			if topy > float(acc["y"]):
				acc["y"] = topy
				acc["node"] = mi
	for c in node.get_children():
		_scan_top_voxel(c, x, z, acc)


func _substrate_top_y() -> float:
	if _world.has_method("column_surface_y"):
		return _world.column_surface_y(0.0, 0.0)
	return float(_world.get("SUBSTRATE_DEPTH")) if _world != null else 1.6


func _haptic(ms: int) -> void:
	if _host.has_method("_haptic"):
		_host.call("_haptic", ms)


func _camera_ray(mouse_pos: Vector2) -> Dictionary:
	if _camera == null or _host == null:
		return {}
	var sv_pos: Vector2 = _host.call("_window_mouse_to_viewport", mouse_pos)
	return {
		"origin": _camera.project_ray_origin(sv_pos),
		"dir": _camera.project_ray_normal(sv_pos),
	}


func _target_build_cell(mouse_pos: Vector2) -> Vector3i:
	var ray: Dictionary = _camera_ray(mouse_pos)
	if ray.is_empty():
		return Vector3i(99999, 99999, 99999)
	var origin: Vector3 = ray.origin
	var dir: Vector3 = ray.dir
	if not gravity_mode:
		return _build_grid.plane_cell_at_y(origin, dir, build_plane_y)
	var hit: Dictionary = _build_grid.raycast_face(origin, dir)
	if bool(hit.get("hit", false)):
		return _build_grid.adjacent_cell(hit.cell, hit.normal)
	# Snap to bed / stack top when aiming down — same rule as library objects.
	if dir.y < -0.05 and absf(dir.y) > 0.001:
		var t: float = (column_top_y(origin.x, origin.z) - origin.y) / dir.y
		if t > 0.0:
			var surface: Vector3 = origin + dir * t
			var snap_xz: Vector2 = _snap_xz(surface.x, surface.z)
			surface.x = snap_xz.x
			surface.z = snap_xz.y
			var surface_y: float = column_top_y(surface.x, surface.z)
			return _build_grid.snap_cell_on_surface(surface.x, surface.z, surface_y)
	return _build_grid.plane_cell_at_y(origin, dir, build_plane_y)


func _place_build_voxel(mouse_pos: Vector2) -> void:
	if not _build_grid.can_place():
		_notify_build_cap()
		return
	_build_grid.build_scale = build_scale
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	var cells: Array = _build_grid.cells_in_brush(g, maxi(0, brush_radius - 1), brush_shape) \
		if brush_radius > 1 else [g]
	var placed: Array = []
	for c in cells:
		if not _build_grid.is_in_bounds(c) or _build_grid.has_cell(c):
			continue
		placed.append_array(_build_grid.place_many([c], build_color, build_finish, mirror_x, mirror_z))
	for rec in placed:
		_push_undo(rec)
	if not placed.is_empty():
		_haptic(8)
	_refresh_budget_label()


func _erase_build_voxel(mouse_pos: Vector2) -> void:
	var g: Vector3i = INVALID_GRID
	var ray: Dictionary = _camera_ray(mouse_pos)
	if not ray.is_empty():
		var hit: Dictionary = _build_grid.raycast_face(ray.origin, ray.dir)
		if bool(hit.get("hit", false)):
			g = hit.cell
	if g == INVALID_GRID:
		g = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	var cells: Array = _build_grid.cells_in_brush(g, maxi(0, brush_radius - 1), brush_shape) \
		if brush_radius > 1 else [g]
	var erased: bool = false
	for c in cells:
		var prev: Dictionary = _build_grid.remove_cell(c)
		if prev.is_empty():
			continue
		prev["kind"] = "build_remove"
		_push_undo(prev)
		erased = true
	if erased:
		_haptic(10)
		_refresh_budget_label()


func _eyedrop_build_color(mouse_pos: Vector2) -> void:
	var ray: Dictionary = _camera_ray(mouse_pos)
	if ray.is_empty():
		return
	var hit: Dictionary = _build_grid.raycast_face(ray.origin, ray.dir)
	if not bool(hit.get("hit", false)):
		return
	var data: Dictionary = _build_grid.get_cell_data(hit.cell)
	if not data.is_empty():
		build_color = data.get("color", build_color)
		build_finish = String(data.get("finish", build_finish))
		_refresh_tool_buttons()
		set_tool("block")


func _object_mesh_params() -> Dictionary:
	if selected_object_id == "castle":
		return {"towers": castle_towers, "height": castle_height}
	return {}


func _library_object_surface_point(mouse_pos: Vector2) -> Vector3:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return INVALID_HIT
	var cell_wp: Vector3 = _build_grid.grid_to_world(g)
	var snap_xz: Vector2 = _snap_xz(cell_wp.x, cell_wp.z)
	var top_y: float = column_top_y(snap_xz.x, snap_xz.y)
	var fp: Vector3 = ObjectMeshes.footprint(selected_object_id, _object_mesh_params())
	return Vector3(snap_xz.x, top_y + fp.y * 0.5, snap_xz.y)


func _place_library_object(mouse_pos: Vector2) -> void:
	var center: Vector3 = _library_object_surface_point(mouse_pos)
	if center == INVALID_HIT:
		_notify_object_failed("Aim at an open spot on the bed or stack.")
		return
	_place_object_mesh(center, selected_object_id, _object_mesh_params(), true)


func _place_object_mesh(center: Vector3, oid: String, params: Dictionary, push_undo: bool) -> void:
	var hs: Node3D = _hardscape_node()
	if hs == null:
		return
	var node: Node3D = ObjectMeshes.spawn(oid, params)
	if node.get_child_count() == 0:
		_notify_object_failed("Unknown object: %s" % oid)
		node.queue_free()
		return
	hs.add_child(node)
	node.global_position = center
	node.set_meta("aquascape_tool", "object")
	node.set_meta("aquascape_object_id", oid)
	if not params.is_empty():
		node.set_meta("aquascape_object_params", params)
	_placed.append(node)
	var fp: Vector3 = ObjectMeshes.footprint(oid, params)
	if _world.has_method("_mark_hardscape_occupancy"):
		_world._mark_hardscape_occupancy(center, fp)
	if push_undo:
		_push_undo({"kind": "hardscape", "node": node, "label": oid})
	_haptic(12)
	_refresh_craft_readout()


func _notify_object_failed(msg: String) -> void:
	if _host != null and _host.has_method("_push_notification"):
		_host.call("_push_notification", "object_place", "warn", "Could not place", msg, false)


func _refresh_budget_label() -> void:
	if _budget_label == null or _build_grid == null:
		return
	var n: int = _build_grid.voxel_count()
	var cap: int = AquascapeBuildGrid.MAX_VOXELS
	_budget_label.text = "voxels %d / %d" % [n, cap]
	if float(n) / float(cap) > 0.85:
		_budget_label.add_theme_color_override("font_color", Color8(255, 180, 100))
	else:
		_budget_label.add_theme_color_override("font_color", Color8(180, 200, 220))


func adjust_build_plane(delta: float) -> void:
	if _world != null and _world.get("WATER_HEIGHT") != null:
		var wh: float = float(_world.WATER_HEIGHT)
		build_plane_y = clampf(build_plane_y + delta, float(_world.get("SUBSTRATE_DEPTH")) + 0.5, wh - 0.4)


func apply_back_slope() -> void:
	if _world == null or not _world.has_method("terrain_place_brush"):
		return
	var half_d: float = float(_world.get("TANK_HALF_D")) if _world.get("TANK_HALF_D") != null else 2.0
	var all_cells: Array = []
	var z_steps: Array[float] = [-0.55, -0.25, 0.05, 0.35, 0.65]
	for i in z_steps.size():
		var fz: float = z_steps[i]
		var wz: float = fz * half_d * 0.75
		var radius: int = clampi(2 + i, 2, 5)
		if fz < 0.0 and _world.has_method("terrain_dig_brush"):
			all_cells.append_array(_world.terrain_dig_brush(0.0, wz, radius))
		else:
			all_cells.append_array(_world.terrain_place_brush(0.0, wz, radius, "aquasoil"))
	if all_cells.is_empty():
		return
	_push_undo({"kind": "terrain_brush", "cells": all_cells, "label": "back slope"})
	_rebuild_substrate_mesh(true)
	_haptic(14)


func _notify_build_cap() -> void:
	if _host != null and _host.has_method("_push_notification"):
		_host.call(
			"_push_notification",
			"build_cap",
			"warn",
			"Voxel budget full",
			"Remove blocks or erase objects to keep building.",
			false,
		)


func _sync_composition_guide() -> void:
	if _world == null:
		return
	if not show_composition and not show_iwagumi and not show_depth_zones:
		if _composition_guide != null:
			_composition_guide.visible = false
		return
	if _composition_guide == null:
		_composition_guide = Node3D.new()
		_composition_guide.name = "CompositionGuide"
		_world.add_child(_composition_guide)
	var wh: float = float(_world.get("WATER_HEIGHT")) if _world.get("WATER_HEIGHT") != null else 6.5
	var hw: float = float(_world.get("TANK_HALF_W")) if _world.get("TANK_HALF_W") != null else 4.0
	var hd: float = float(_world.get("TANK_HALF_D")) if _world.get("TANK_HALF_D") != null else 2.0
	for c in _composition_guide.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	if show_composition:
		for x_frac in [-1.0 / 3.0, 1.0 / 3.0]:
			_composition_guide.add_child(_guide_line(mat, Vector3(0.02, wh * 0.92, hd * 1.6), Vector3(x_frac * hw * 1.4, wh * 0.46, 0)))
		for z_frac in [-1.0 / 3.0, 1.0 / 3.0]:
			_composition_guide.add_child(_guide_line(mat, Vector3(hw * 1.6, wh * 0.92, 0.02), Vector3(0, wh * 0.46, z_frac * hd * 1.4)))
	if show_iwagumi:
		var tri: Array[Vector3] = [
			Vector3(-hw * 0.35, wh * 0.35, -hd * 0.2),
			Vector3(hw * 0.15, wh * 0.42, hd * 0.25),
			Vector3(-hw * 0.05, wh * 0.38, hd * 0.45),
		]
		for p in tri:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.25, 0.25, 0.25)
			m.mesh = bm
			m.material_override = mat
			m.position = p
			_composition_guide.add_child(m)
	if show_depth_zones:
		for zf in [-0.55, 0.0, 0.55]:
			var band := _guide_line(mat, Vector3(hw * 1.5, 0.02, hd * 0.5), Vector3(0, wh * 0.15, zf * hd))
			_composition_guide.add_child(band)
		var fish_ref := _guide_line(mat, Vector3(0.6, 0.08, 0.3), Vector3(hw * 0.2, wh * 0.4, -hd * 0.5))
		_composition_guide.add_child(fish_ref)
	_composition_guide.visible = true


func _guide_line(mat: Material, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	line.mesh = bm
	line.material_override = mat
	line.position = pos
	return line


func _save_blueprint_prompt() -> void:
	var voxels: Array = _build_grid.export_voxel_list()
	if voxels.is_empty():
		return
	var name: String = "Build %d" % int(Time.get_unix_time_from_system())
	AquascapeBlueprint.add_to_library(name, voxels)
	var code: String = AquascapeBlueprint.encode_voxels(voxels, {"name": name})
	DisplayServer.clipboard_set(code)
	if _host != null and _host.has_method("_push_notification"):
		_host.call("_push_notification", "blueprint", "info", "Blueprint saved", "Code copied to clipboard.", false)


func _import_blueprint_prompt() -> void:
	var parsed: Dictionary = AquascapeBlueprint.decode_voxels(DisplayServer.clipboard_get())
	if parsed.is_empty():
		return
	var voxels: Array = parsed.get("voxels", [])
	var n: int = _build_grid.import_voxel_list(voxels)
	if _host != null and _host.has_method("_push_notification"):
		_host.call("_push_notification", "blueprint", "info", "Blueprint imported", "%d voxels placed." % n, false)
	_refresh_budget_label()


func _handle_line_click(mouse_pos: Vector2) -> void:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	if _click_anchor == INVALID_GRID:
		_click_anchor = g
		return
	var cells: Array = _build_grid.cells_on_line(_click_anchor, g)
	_click_anchor = INVALID_GRID
	_commit_build_cells(cells)


func _handle_box_click(mouse_pos: Vector2) -> void:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	if _click_anchor == INVALID_GRID:
		_click_anchor = g
		return
	var cells: Array = _build_grid.cells_in_box(_click_anchor, g, hollow_box)
	_click_anchor = INVALID_GRID
	_commit_build_cells(cells)


func _commit_build_cells(cells: Array) -> void:
	if cells.is_empty():
		return
	begin_stroke()
	var placed: Array = _build_grid.place_many(
		cells, build_color, build_finish, mirror_x, mirror_z)
	for rec in placed:
		_push_undo(rec)
	end_stroke()
	if not placed.is_empty():
		_haptic(10)
	_refresh_budget_label()


func copy_build() -> void:
	_clipboard = _build_grid.export_voxel_list()
	if _host != null and _host.has_method("_push_notification") and not _clipboard.is_empty():
		_host.call("_push_notification", "build_copy", "info", "Build copied", "%d voxels ready to paste." % _clipboard.size(), false)


func _paste_clipboard(mouse_pos: Vector2) -> void:
	if _clipboard.is_empty():
		return
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	begin_stroke()
	var n: int = 0
	for v in _clipboard:
		if not (v is Dictionary):
			continue
		var pg := Vector3i(
			int(v.get("ix", 0)) + g.x,
			int(v.get("iy", 0)) + g.y,
			int(v.get("iz", 0)) + g.z,
		)
		var placed: Array = _build_grid.place_many(
			[pg],
			SaveHelpers.array_to_color(v.get("color", []), build_color),
			String(v.get("finish", build_finish)),
			mirror_x,
			mirror_z,
		)
		for rec in placed:
			_push_undo(rec)
			n += 1
	end_stroke()
	if n > 0:
		_haptic(12)
	_refresh_budget_label()


func rotate_selected_hardscape(delta_deg: float) -> void:
	var nodes: Array[Node3D] = []
	if _multi_select.size() > 0:
		for n in _multi_select:
			if is_instance_valid(n):
				nodes.append(n)
	elif _wood_drag != null and is_instance_valid(_wood_drag):
		nodes.append(_wood_drag)
	else:
		nodes = _drag_cluster
	if nodes.is_empty():
		for v in _placed:
			if is_instance_valid(v) and String(v.get_meta("aquascape_tool", "")) in ["stone", "wood"]:
				nodes.append(v)
				break
	if nodes.is_empty():
		return
	var pivot: Vector3 = nodes[0].global_position
	for n in nodes:
		if is_instance_valid(n):
			pivot = (pivot + n.global_position) * 0.5
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var offset: Vector3 = n.global_position - pivot
		offset = offset.rotated(Vector3.UP, deg_to_rad(delta_deg))
		n.global_position = pivot + offset
		n.rotate_y(deg_to_rad(delta_deg))
	_haptic(10)
	_sync_placement_gizmo()


func set_hide_fauna_layers(on: bool) -> void:
	hide_fauna_layers = on
	if _host != null and _host.has_method("_set_aquascape_fauna_hidden"):
		_host.call("_set_aquascape_fauna_hidden", on)
	_refresh_tool_buttons()


func _stamp_themed_kit(kit_id: String) -> void:
	if _world == null:
		return
	for oid in AquascapeObjectLibrary.themed_kit_objects(kit_id):
		var x: float = randf_range(-3.0, 3.0)
		var z: float = randf_range(-1.5, 1.5)
		if _world.has_method("is_inside_tank") and not _world.is_inside_tank(x, z, 0.4):
			continue
		var snap_xz: Vector2 = _snap_xz(x, z)
		var surface_y: float = column_top_y(snap_xz.x, snap_xz.y)
		var fp: Vector3 = ObjectMeshes.footprint(oid, {})
		var center := Vector3(snap_xz.x, surface_y + fp.y * 0.5, snap_xz.y)
		_place_object_mesh(center, oid, {}, true)


func _maybe_show_builder_onboarding() -> void:
	if _host == null:
		return
	var onboarding: Node = _host.get("_onboarding")
	if onboarding != null and onboarding.has_method("show_builder_tour"):
		onboarding.show_builder_tour()


func _flood_fill_at(mouse_pos: Vector2) -> void:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	begin_stroke()
	var placed: Array = AquascapeCraft.flood_fill(_build_grid, g, build_color, build_finish, 400)
	for rec in placed:
		_push_undo(rec)
	end_stroke()
	if not placed.is_empty():
		_haptic(12)
	_refresh_budget_label()
	_refresh_craft_readout()


func _gradient_fill_at(mouse_pos: Vector2) -> void:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	begin_stroke()
	var placed: Array = AquascapeCraft.gradient_fill(
		_build_grid, g, build_color, build_color_b, build_finish, 256)
	for rec in placed:
		_push_undo(rec)
	end_stroke()
	if not placed.is_empty():
		_haptic(12)
	_refresh_budget_label()
	_refresh_craft_readout()


func _sync_placement_gizmo() -> void:
	if _world == null or not is_active or not gumball_enabled:
		if _placement_gizmo != null:
			_placement_gizmo.visible = false
		_axis_handles.clear()
		return
	if _placement_gizmo == null:
		_placement_gizmo = Node3D.new()
		_placement_gizmo.name = "BuildPlacementGizmo"
		_world.add_child(_placement_gizmo)
	for c in _placement_gizmo.get_children():
		c.queue_free()
	_axis_handles.clear()
	var nodes: Array[Node3D] = _selection_nodes()
	if nodes.is_empty():
		_placement_gizmo.visible = false
		return
	var pivot: Vector3 = _selection_pivot()
	_placement_gizmo.global_position = pivot
	var axis_len: float = 0.85
	for axis in [
		{"name": "x", "c": Color8(240, 70, 70), "dir": Vector3(axis_len, 0, 0)},
		{"name": "y", "c": Color8(70, 210, 90), "dir": Vector3(0, axis_len, 0)},
		{"name": "z", "c": Color8(80, 130, 240), "dir": Vector3(0, 0, axis_len)},
	]:
		var dir: Vector3 = axis["dir"] as Vector3
		var shaft := MeshInstance3D.new()
		var bm := BoxMesh.new()
		if absf(dir.y) > 0.5:
			bm.size = Vector3(0.06, dir.y, 0.06)
		elif absf(dir.x) > 0.5:
			bm.size = Vector3(dir.x, 0.06, 0.06)
		else:
			bm.size = Vector3(0.06, 0.06, dir.z)
		shaft.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = axis["c"]
		mat.albedo_color.a = 0.85
		mat.emission_enabled = true
		mat.emission = axis["c"]
		mat.emission_energy_multiplier = 0.35
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		shaft.material_override = mat
		shaft.position = dir * 0.5
		_placement_gizmo.add_child(shaft)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		tip.mesh = sm
		tip.material_override = mat.duplicate()
		tip.position = dir
		_placement_gizmo.add_child(tip)
		_axis_handles[axis["name"]] = tip
	var center := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.06
	center.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color8(255, 240, 160)
	cmat.emission_enabled = true
	cmat.emission = Color8(255, 220, 80)
	cmat.emission_energy_multiplier = 0.5
	cmat.no_depth_test = true
	center.material_override = cmat
	_placement_gizmo.add_child(center)
	_placement_gizmo.visible = true


func _select_hardscape(mouse_pos: Vector2) -> void:
	var picked: Node3D = _pick_hardscape_piece(mouse_pos)
	if picked != null:
		_selected_build_cell = INVALID_GRID
		if Input.is_key_pressed(KEY_SHIFT):
			if _multi_select.has(picked):
				_multi_select.erase(picked)
			else:
				_multi_select.append(picked)
		else:
			_multi_select = [picked]
		_wood_drag = picked if _multi_select.size() == 1 else null
		_sync_placement_gizmo()
		return
	var ray: Dictionary = _camera_ray(mouse_pos)
	if not ray.is_empty():
		var hit: Dictionary = _build_grid.raycast_face(ray.origin, ray.dir)
		if bool(hit.get("hit", false)):
			_selected_build_cell = hit.cell
			_multi_select.clear()
			_wood_drag = null
			_sync_placement_gizmo()
			return
	_selected_build_cell = INVALID_GRID
	_multi_select.clear()
	_wood_drag = null
	_sync_placement_gizmo()


func _refresh_craft_readout() -> void:
	if _craft_label == null or _world == null:
		return
	var a: Dictionary = AquascapeCraft.analyze_scape(_world, _build_grid, _placed)
	var tip: String = String(a.get("style", "Nature"))
	if (a.get("tips", []) as Array).size() > 0:
		tip += " · " + String((a.get("tips", []) as Array)[0])
	tip += " · open %.0f%%" % float(a.get("open_water_pct", 0.0))
	tip += " · " + AquascapeCraft.style_palette_hint(String(a.get("style", "Nature")))
	_craft_label.text = tip


func _set_build_lights(on: bool) -> void:
	lights_on_build = on
	if _world == null:
		_refresh_tool_buttons()
		return
	if _world.has_method("begin_screenshot_boost"):
		if on:
			_world.begin_screenshot_boost(999.0)
		else:
			_world.begin_screenshot_boost(0.01)
	_refresh_tool_buttons()


func preview_life(seconds: float = 3.0) -> void:
	var sim: Node = _host.get("_sim") if _host != null else null
	if sim == null:
		return
	sim.time_scale = _saved_time_scale if _saved_time_scale > 0.0 else 1.0
	_paused_sim_for_aquascape = false
	if _host != null and _host.has_method("_push_notification"):
		_host.call("_push_notification", "preview", "info", "Preview life", "Sim running %.0fs…" % seconds, false)


func snapshot_ab_compare() -> void:
	if _ab_snapshot.is_empty():
		_ab_snapshot = _build_grid.export_voxel_list()
		if _host != null and _host.has_method("_push_notification"):
			_host.call("_push_notification", "ab", "info", "A snapshot saved", "Edit, then click again to restore A.", false)
	else:
		_build_grid.import_voxel_list(_ab_snapshot)
		_ab_snapshot.clear()
		_refresh_budget_label()


func ruinify_at(mouse_pos: Vector2) -> void:
	var g: Vector3i = _target_build_cell(mouse_pos)
	if g == INVALID_GRID:
		return
	var removed: Array = AquascapeCraft.ruinify_region(_build_grid, g, 3, 0.4)
	if removed.is_empty():
		return
	begin_stroke()
	for rec in removed:
		_push_undo(rec)
	end_stroke()
	_haptic(14)


func recolor_build_theme(theme: String) -> void:
	var n: int = AquascapeCraft.recolor_build(_build_grid, theme)
	if n > 0:
		_refresh_budget_label()
		_refresh_craft_readout()
		_haptic(10)


func open_my_builds_panel() -> void:
	var lib: Array = AquascapeBlueprint.load_library_merged()
	if lib.is_empty():
		return
	var entry: Dictionary = lib[lib.size() - 1]
	if entry.get("voxels") is Array:
		_build_grid.import_voxel_list(entry["voxels"])
		_refresh_budget_label()


func open_showcase_gallery() -> void:
	var entries: Array = AquascapeBlueprint.showcase_blueprints()
	if entries.is_empty():
		return
	var dlg := AcceptDialog.new()
	dlg.title = "Scape showcase"
	dlg.dialog_text = "Curated builds — tap Import on one to place in your tank."
	dlg.min_size = Vector2(360, 220)
	var box := VBoxContainer.new()
	dlg.add_child(box)
	for e in entries:
		if not (e is Dictionary):
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %s" % [String(e.get("name", "?")), String(e.get("blurb", ""))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var ib := Button.new()
		ib.text = "Import"
		var voxels: Array = e.get("voxels", [])
		ib.pressed.connect(func(v = voxels):
			import_blueprint_async(v, 60)
			dlg.queue_free())
		row.add_child(ib)
		box.add_child(row)
	if _host != null:
		_host.add_child(dlg)
		dlg.popup_centered()


func import_blueprint_async(voxels: Array, batch: int = 80) -> void:
	_import_queue = voxels.duplicate(true)
	if not _import_busy:
		_import_busy = true
		_pump_import(batch)


func _pump_import(batch: int) -> void:
	if _import_queue.is_empty():
		_import_busy = false
		_refresh_budget_label()
		return
	var slice: Array = _import_queue.slice(0, mini(batch, _import_queue.size()))
	_import_queue = _import_queue.slice(mini(batch, _import_queue.size()))
	_build_grid.import_voxel_list(slice)
	if _host != null:
		_host.call_deferred("_aquascape_import_continue")


func continue_import(batch: int = 80) -> void:
	_pump_import(batch)


func camera_snap(mode: String) -> void:
	if _host == null or _camera == null:
		return
	if not _host.has_method("_aquascape_camera_snap"):
		return
	_host.call("_aquascape_camera_snap", mode)


func export_scape_photo() -> void:
	if _host != null and _host.has_method("_take_photo"):
		_host.call("_take_photo")


func adjust_build_plane_public(delta: float) -> void:
	adjust_build_plane(delta)


func _place_stone_cluster(center: Vector3, color: Color, hs: Node3D) -> void:
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	var root := Node3D.new()
	root.name = "StoneCluster"
	hs.add_child(root)
	root.global_position = center
	var offsets: Array[Vector3] = [
		Vector3.ZERO, Vector3(0.35, 0.2, 0), Vector3(-0.3, 0.15, 0.2),
		Vector3(0.1, 0.35, -0.25),
	]
	for off in offsets:
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.45, 0.55) + Vector3.ONE * randf_range(-0.08, 0.08)
		seg.mesh = bm
		if voxel_mat_script != null:
			seg.material_override = voxel_mat_script.make(color.darkened(randf() * 0.15))
		seg.position = off
		root.add_child(seg)
	root.set_meta("aquascape_tool", "stone")
	_placed.append(root)
	_push_undo({"kind": "hardscape", "node": root, "label": "stone cluster"})
	_haptic(8)
