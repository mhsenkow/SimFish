# Aquascape mode: terrain sculpt, hardscape placement, brush, trim, unified undo.
class_name AquascapeController
extends RefCounted

const INVALID_HIT: Vector3 = Vector3(INF, INF, INF)
const PAINT_INTERVAL: float = 0.08
const UNDO_MAX: int = 96

const AQUASCAPE_TOOLS: Array[String] = [
	"aquasoil", "sand", "gravel", "peat", "stone", "wood", "dig", "trim",
]
const AQUASCAPE_TERRAIN_TOOLS: Array[String] = [
	"aquasoil", "sand", "gravel", "peat", "dirt",
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
var _saved_time_scale: float = 1.0
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
	_build_palette()


func toggle() -> void:
	is_active = not is_active
	var sim: Node = _host.get("_sim") if _host != null else null
	if is_active:
		if sim != null:
			_saved_time_scale = float(sim.time_scale)
			sim.time_scale = 0.0
		if _host != null:
			_host.set("_follow_target", null)
		_host.set("_follow_target", null)
		_ensure_preview()
		if _palette != null:
			_palette.visible = true
		_refresh_tool_buttons()
	else:
		if sim != null:
			sim.time_scale = _saved_time_scale
		if _preview != null:
			_preview.visible = false
		if _palette != null:
			_palette.visible = false
	var mobile: Node = _host.get("_mobile_hud") if _host != null else null
	if mobile != null and mobile.has_method("set_aquascape_mode"):
		mobile.set_aquascape_mode(is_active)
	if _host.has_method("_sync_rail_toggles"):
		_host.call("_sync_rail_toggles")
	mode_changed.emit(is_active)


func set_tool(key: String) -> void:
	if not is_active:
		return
	tool = key
	_refresh_tool_buttons()


func adjust_brush(delta: int) -> void:
	brush_radius = clampi(brush_radius + delta, 1, 4)


func tick_paint_cooldown(dt: float) -> void:
	if _paint_cooldown > 0.0:
		_paint_cooldown = maxf(0.0, _paint_cooldown - dt)
	if _mesh_rebuild_cooldown > 0.0:
		_mesh_rebuild_cooldown = maxf(0.0, _mesh_rebuild_cooldown - dt)


func can_paint() -> bool:
	return _paint_cooldown <= 0.0


func mark_painted() -> void:
	_paint_cooldown = PAINT_INTERVAL


func update_preview(mouse_pos: Vector2) -> void:
	if _preview == null or _camera == null or _world == null:
		return
	var hit: Vector3 = project_to_substrate(mouse_pos)
	if hit == INVALID_HIT:
		_preview.visible = false
		return
	_preview.visible = true
	hit.x = floorf(hit.x / TerrainVoxelGrid.CELL_SIZE) * TerrainVoxelGrid.CELL_SIZE \
		+ TerrainVoxelGrid.CELL_SIZE * 0.5
	hit.z = floorf(hit.z / TerrainVoxelGrid.CELL_SIZE) * TerrainVoxelGrid.CELL_SIZE \
		+ TerrainVoxelGrid.CELL_SIZE * 0.5
	if tool == "dig":
		var top_y: float = column_top_y(hit.x, hit.z)
		hit.y = top_y - TerrainVoxelGrid.CELL_SIZE * 0.5
	else:
		var top_y: float = column_top_y(hit.x, hit.z)
		hit.y = top_y + TerrainVoxelGrid.CELL_SIZE * 0.5
	if _preview.material_override is StandardMaterial3D:
		var pm: StandardMaterial3D = _preview.material_override as StandardMaterial3D
		var c: Color = _preview_color_for_tool()
		pm.albedo_color = c
		pm.emission = c.lightened(0.2)
	_preview.global_position = hit


func begin_drag(pos: Vector2) -> bool:
	if tool == "dig":
		return false
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
	hit.x = floorf(hit.x / TerrainVoxelGrid.CELL_SIZE) * TerrainVoxelGrid.CELL_SIZE \
		+ TerrainVoxelGrid.CELL_SIZE * 0.5
	hit.z = floorf(hit.z / TerrainVoxelGrid.CELL_SIZE) * TerrainVoxelGrid.CELL_SIZE \
		+ TerrainVoxelGrid.CELL_SIZE * 0.5
	if tool == "dig":
		_dig(hit)
		return
	if tool == "trim":
		_trim_at(hit)
		return
	if tool in AQUASCAPE_TERRAIN_TOOLS or TerrainVoxelGrid.tool_is_terrain(tool):
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
		_:
			pass
	_haptic(15)


func to_save_arr() -> Array:
	var out: Array = []
	for v in _placed:
		if not is_instance_valid(v):
			continue
		var t: String = String(v.get_meta("aquascape_tool", ""))
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
	return out


func restore_from_save(arr: Array) -> void:
	if _world == null:
		return
	var voxel_mat_script := load("res://scripts/voxel_mat.gd")
	var hardscape := _world.get_node_or_null("Hardscape")
	if hardscape == null:
		hardscape = _world
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var kind: String = String(entry.get("kind", ""))
		var t: String = String(entry.get("tool", ""))
		var pos: Vector3 = SaveHelpers.array_to_vec3(entry.get("pos", []), Vector3.ZERO)
		if kind == "voxel":
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
	return top


func _place_terrain(hit: Vector3) -> void:
	if brush_radius <= 1:
		if _world.has_method("terrain_place_tool"):
			var undo: Dictionary = _world.terrain_place_tool(hit.x, hit.z, tool)
			if not undo.is_empty():
				_push_undo({"kind": "terrain_cell", "payload": undo, "label": tool})
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
			var undo: Dictionary = _world.terrain_dig(hit.x, hit.z)
			if undo.is_empty() or int(undo.get("mat", TerrainVoxelGrid.CellMaterial.EMPTY)) \
					== TerrainVoxelGrid.CellMaterial.EMPTY:
				return
			_push_undo({"kind": "terrain_cell", "payload": undo, "label": "dig"})
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
	var snap: Dictionary = best.trim_for_aquascape(0.25)
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
	var voxel_size: Vector3 = Vector3(0.9, 0.9, 0.9)
	hit.y = top_y + voxel_size.y * 0.5
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
	var hs := _hardscape_node()
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
	var theta: float = randf_range(0.0, TAU)
	var forward: Vector3 = Vector3(cos(theta), 0, sin(theta))
	var curve_sign: float = 1.0 if randf() < 0.5 else -1.0
	var dark := Color8(58, 38, 22)
	var mid := Color8(78, 52, 32)
	var light := Color8(98, 70, 46)
	var palette: Array[Color] = [dark, mid, light, mid, dark]
	var n_segments: int = randi_range(5, 7)
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


func _push_undo(rec: Dictionary) -> void:
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
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	_palette.add_child(hb)
	var header := Label.new()
	header.text = "AQUASCAPE  →"
	header.add_theme_color_override("font_color", Color8(255, 220, 80))
	header.add_theme_font_size_override("font_size", 12)
	hb.add_child(header)
	var defs := [
		{"key": "aquasoil", "label": "1·soil",   "color": Color8(120, 85, 56)},
		{"key": "sand",     "label": "2·sand",   "color": Color8(225, 215, 185)},
		{"key": "gravel",   "label": "3·gravel", "color": Color8(125, 125, 135)},
		{"key": "peat",     "label": "4·peat",   "color": Color8(40, 32, 26)},
		{"key": "stone",    "label": "5·stone",  "color": Color8(120, 120, 130)},
		{"key": "wood",     "label": "6·wood",   "color": Color8(95, 65, 35)},
		{"key": "dig",      "label": "7·dig",    "color": Color8(220, 90, 90)},
		{"key": "trim",     "label": "8·trim",   "color": Color8(100, 200, 120)},
	]
	for def in defs:
		var btn := Button.new()
		btn.text = String(def["label"])
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
		btn.add_theme_font_size_override("font_size", 12)
		var key: String = String(def["key"])
		btn.pressed.connect(func():
			set_tool(key))
		hb.add_child(btn)
		_tool_buttons[key] = btn
	var hint := Label.new()
	hint.text = "  brush [ ] · trim 8 · BACKSPACE undo · B exit"
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	hint.add_theme_font_size_override("font_size", 10)
	hb.add_child(hint)


func _refresh_tool_buttons() -> void:
	for k in _tool_buttons.keys():
		var btn: Button = _tool_buttons[k]
		if btn == null:
			continue
		btn.modulate = Color(1.4, 1.4, 0.7) if k == tool else Color(0.85, 0.85, 0.85)


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
	mat.albedo_color = Color(1, 1, 0.6, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0.4)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview.material_override = mat
	_world.add_child(_preview)


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
