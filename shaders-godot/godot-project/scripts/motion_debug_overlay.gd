# Debug draw for fauna motion tuning. Toggle from main.gd with Shift+M.
#
# Always (when on): per-fish depth bands (cyan preferred_y, green home_y, gold
# home band, red wall push), as before.
#
# For one subject (CREATURE_MOTION_700 #81-#84) - main.gd's followed creature,
# else the fish nearest the screen centre, or `subject` when a tool sets it:
#   #81 onion skins: the last 30 head (cyan) and tail-tip (orange) positions,
#       sampled at a fixed rate, so clumped dots are slow in / slow out and
#       even spacing is mechanical motion;
#   #82 a 10 s speed graph with bout / burst / startle / motion-event markers;
#   #83 the body-centre path coloured by curvature (green straight ->
#       magenta tight) with curvature breaks (kinks, snaps) flagged by red
#       ticks, and the head path beside it in pale cyan. Curvature is taken
#       on the centre path: the head tip carries the body wave, whose bend
#       would read as a break every half beat;
#   #84 the tail tip in the creature's own frame, from above and from the
#       side: a healthy swimmer draws a flattened arc / figure-eight.
#
# Cheap when off: processing stops, the mesh and HUD are released and nothing
# is sampled. Graphs are drawn by draw_graphs(), so the motion lab can put
# them in its own panel (show_hud = false) instead of the in-game HUD.
extends Node3D
class_name MotionDebugOverlay

const SAMPLE_HZ: float = 30.0
const HISTORY_S: float = 10.0
const ONION_COUNT: int = 30
const TAIL_TRACE_S: float = 2.0
# Curvature is measured on a path decimated to this spacing (units), so a
# near-stationary creature's sub-millimetre jitter doesn't read as tight arcs.
const CURVATURE_MIN_STEP: float = 0.02
# Jump in curvature (1/units) between neighbouring path samples that counts
# as a break in the arc.
const CURVATURE_BREAK: float = 3.0
# |curvature| at which the path colour saturates (radius ~0.17 units).
const CURVATURE_SCALE: float = 6.0
const SUBJECT_REFRESH_S: float = 0.5
const MAX_BAND_FISH: int = 48

enum Mark { NONE, BOUT, BURST, STARTLE, EVENT }
const MARK_COLORS: Dictionary = {
	Mark.BOUT: Color(0.55, 0.75, 1.0, 0.8),
	Mark.BURST: Color(1.0, 0.55, 0.15, 0.95),
	Mark.STARTLE: Color(1.0, 0.25, 0.25, 0.95),
	Mark.EVENT: Color(0.85, 0.5, 1.0, 0.9),
}

var enabled: bool = false
var sim: Node = null
# Explicit subject (motion lab, probes). Null: follow main.gd's selection.
var subject: Node3D = null
var draw_depth_bands: bool = true
# In-game 2D graphs on a CanvasLayer. The motion lab draws them itself.
var show_hud: bool = true
# When true the owner calls advance(sim_dt) itself (the motion lab, whose
# clock is not the sim's); otherwise _process samples at sim time.
var external_clock: bool = false

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _hud_layer: CanvasLayer = null
var _hud: Control = null
var _history: MotionPoseHistory = MotionPoseHistory.new(int(SAMPLE_HZ * HISTORY_S))
# Parallel to _history: the body centre, the tail tip in the subject's own
# frame, and a marker.
var _roots: PackedVector3Array = PackedVector3Array()
var _local_tails: PackedVector3Array = PackedVector3Array()
var _marks: PackedInt32Array = PackedInt32Array()
var _current: Node3D = null
var _refresh_t: float = 0.0
var _sample_acc: float = 0.0
var _clock: float = 0.0
var _last_bout: int = -1
var _last_burst: float = 0.0
var _last_startle: float = 0.0
var _last_event_ms: int = 0
var _metrics_t: float = 0.0
var _metrics_text: String = ""

# instance id -> Vector2(head tip z in head-pivot space, tail tip z in tail-pivot space)
static var _tip_cache: Dictionary = {}


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "Lines"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = true
	_mesh.material_override = _mat
	set_process(enabled)


func _exit_tree() -> void:
	# The HUD lives on the root viewport, not under this node.
	if _hud_layer != null:
		_hud_layer.queue_free()
		_hud_layer = null
		_hud = null


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(on: bool) -> void:
	enabled = on
	set_process(on)
	clear_history()
	if not on:
		if _mesh != null:
			_mesh.mesh = null
		if _hud_layer != null:
			_hud_layer.queue_free()
			_hud_layer = null
			_hud = null
	elif show_hud:
		_ensure_hud()


func clear_history() -> void:
	_history.clear()
	_roots.clear()
	_local_tails.clear()
	_marks.clear()
	_sample_acc = 0.0
	_last_bout = -1
	_last_burst = 0.0
	_last_startle = 0.0
	_last_event_ms = Time.get_ticks_msec()
	_metrics_text = ""


func current_subject() -> Node3D:
	return _current if is_instance_valid(_current) else null


func _process(delta: float) -> void:
	if not enabled:
		return
	if not external_clock:
		var ts: float = 1.0
		if sim != null and sim.get("time_scale") != null:
			ts = float(sim.get("time_scale"))
		advance(delta * maxf(ts, 0.0))
	_refresh_t -= delta
	_metrics_t -= delta
	_rebuild_mesh()
	if _hud != null:
		_hud.queue_redraw()


# Advance the sampling clock by sim_dt and record samples at SAMPLE_HZ.
func advance(sim_dt: float) -> void:
	if not enabled:
		return
	_resolve_subject()
	if _current == null or sim_dt <= 0.0:
		return
	_sample_acc += sim_dt
	var step: float = 1.0 / SAMPLE_HZ
	var n: int = 0
	while _sample_acc >= step and n < 4:
		_sample_acc -= step
		_clock += step
		_sample(_current)
		n += 1
	if _sample_acc > step:
		_sample_acc = 0.0


func _resolve_subject() -> void:
	var want: Node3D = null
	if is_instance_valid(subject):
		want = subject
	elif _refresh_t > 0.0 and is_instance_valid(_current) and not _is_dead(_current):
		return
	else:
		_refresh_t = SUBJECT_REFRESH_S
		want = _auto_subject()
	if want != _current:
		_current = want
		clear_history()


func _is_dead(c: Node) -> bool:
	return c.get("_dying") == true or c.is_queued_for_deletion()


func _auto_subject() -> Node3D:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene != null:
		var followed: Variant = scene.get("_follow_target")
		if followed is Node3D and is_instance_valid(followed):
			return followed as Node3D
	if sim == null:
		return null
	var fish_v: Variant = sim.get("fish")
	if not (fish_v is Array):
		return null
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5 if cam != null else Vector2.ZERO
	var best: Node3D = null
	var best_d: float = INF
	for f in fish_v as Array:
		if not is_instance_valid(f) or not (f is Node3D) or _is_dead(f):
			continue
		var n3: Node3D = f
		var d: float
		if cam != null:
			if cam.is_position_behind(n3.global_position):
				continue
			d = cam.unproject_position(n3.global_position).distance_squared_to(centre)
		else:
			d = n3.global_position.length_squared()
		if d < best_d:
			best_d = d
			best = n3
	return best


func _sample(c: Node3D) -> void:
	var head: Vector3 = head_tip_world(c)
	var tail: Vector3 = tail_tip_world(c)
	var spd: float = creature_speed(c)
	if c.get("speed") == null and c.get("velocity") == null and not _roots.is_empty():
		# Snails and worms keep no speed field: use the sampled displacement.
		spd = _roots[_roots.size() - 1].distance_to(c.global_position) * SAMPLE_HZ
	_history.push(_clock, head, tail, spd, creature_yaw(c))
	_roots.append(c.global_position)
	_local_tails.append(c.global_transform.affine_inverse() * tail)
	var mark: int = Mark.NONE
	var bout_v: Variant = c.get("_bout_kind")
	if bout_v != null:
		var bk: int = int(bout_v)
		if _last_bout >= 0 and bk != _last_bout:
			mark = Mark.BOUT
		_last_bout = bk
	var burst_v: Variant = c.get("burst_remaining")
	if burst_v != null:
		var b: float = float(burst_v)
		if b > _last_burst + 0.05:
			mark = Mark.BURST
		_last_burst = b
	var startle_v: Variant = c.get("_startle_remaining")
	if startle_v != null:
		var s: float = float(startle_v)
		if s > _last_startle + 0.05:
			mark = Mark.STARTLE
		_last_startle = s
	var sid: int = c.get_instance_id()
	var newest: int = _last_event_ms
	for ev in MotionEvents.recent():
		var t_ms: int = int(ev.get("time_ms", 0))
		if t_ms > _last_event_ms and int(ev.get("source_id", 0)) == sid:
			mark = Mark.EVENT
			newest = maxi(newest, t_ms)
	_last_event_ms = maxi(newest, _last_event_ms)
	_marks.append(mark)
	var cap: int = _history.capacity
	while _roots.size() > cap:
		_roots.remove_at(0)
	while _local_tails.size() > cap:
		_local_tails.remove_at(0)
	while _marks.size() > cap:
		_marks.remove_at(0)


# ---- Creature geometry helpers (shared with the motion lab and probes) -----

static func creature_speed(c: Node) -> float:
	var v: Variant = c.get("speed")
	if v != null:
		return float(v)
	var vel: Variant = c.get("velocity")
	return (vel as Vector3).length() if vel is Vector3 else 0.0


static func creature_heading(c: Node3D) -> Vector3:
	var h: Variant = c.get("heading")
	if h is Vector3 and (h as Vector3).length_squared() > 1e-6:
		return (h as Vector3).normalized()
	if c.get("wall_normal") != null and c.get("shell_shape") != null:
		# Glass snail: the body is built head-first along +X (snail.gd MODEL_YAW).
		var body: Node3D = _pivot(c, "_body")
		return (body if body != null else c).global_transform.basis.x.normalized()
	return -c.global_transform.basis.z.normalized()


static func creature_yaw(c: Node3D) -> float:
	var h: Vector3 = creature_heading(c)
	return atan2(h.x, -h.z)


static func _pivot(c: Node, field: String) -> Node3D:
	var p: Variant = c.get(field)
	return p as Node3D if p is Node3D and is_instance_valid(p) else null


# Union AABB of every visual under pivot, in the pivot's own space. Empty
# when the voxels live in a shared species batch instead of under the pivot.
static func pivot_local_aabb(pivot: Node3D) -> AABB:
	var inv: Transform3D = pivot.global_transform.affine_inverse()
	var out := AABB()
	var have: bool = false
	var stack: Array = pivot.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is VisualInstance3D):
			continue
		var vi: VisualInstance3D = n
		var box: AABB = vi.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		var x: Transform3D = inv * vi.global_transform
		var b2: AABB = x * box
		out = b2 if not have else out.merge(b2)
		have = true
	return out if have else AABB()


static func _tips(c: Node3D) -> Vector2:
	var id: int = c.get_instance_id()
	if _tip_cache.has(id):
		return _tip_cache[id]
	if _tip_cache.size() > 512:
		_tip_cache.clear()
	var v: float = float(c.get("adult_voxel_scale")) if c.get("adult_voxel_scale") != null else 0.15
	var hp: float = float(c.get("head_proportion")) if c.get("head_proportion") != null else 1.0
	var fl: float = float(c.get("fin_length_factor")) if c.get("fin_length_factor") != null else 1.0
	# Fallbacks from fish.gd's build: head block at -2.5v plus the muzzle,
	# caudal fin out to about (1.1 + 0.9 fl) v behind the tail pivot.
	var head_z: float = -(2.5 + 0.62 * hp) * v
	var tail_z: float = (1.1 + 0.9 * fl) * v
	var hp_node: Node3D = _pivot(c, "_head_pivot")
	if hp_node != null:
		var hb: AABB = pivot_local_aabb(hp_node)
		if hb.size != Vector3.ZERO:
			head_z = hb.position.z
	var tp_node: Node3D = _pivot(c, "_tail_pivot")
	if tp_node != null:
		var tb: AABB = pivot_local_aabb(tp_node)
		if tb.size != Vector3.ZERO:
			tail_z = tb.end.z
	var out := Vector2(head_z, tail_z)
	_tip_cache[id] = out
	return out


# World position of the snout tip. Snails lead with +X (snail.gd MODEL_YAW).
static func head_tip_world(c: Node3D) -> Vector3:
	var hp_node: Node3D = _pivot(c, "_head_pivot")
	if hp_node != null:
		return hp_node.global_transform * Vector3(0.0, 0.0, _tips(c).x)
	var eyes: Node3D = _pivot(c, "_eye_stalks")
	if eyes != null:
		return eyes.global_position
	return c.global_position + creature_heading(c) * 0.1


# World position of the caudal tip (fish) or tail fan (crustaceans).
static func tail_tip_world(c: Node3D) -> Vector3:
	var tp_node: Node3D = _pivot(c, "_tail_pivot")
	if tp_node != null:
		return tp_node.global_transform * Vector3(0.0, 0.0, _tips(c).y)
	return c.global_position - creature_heading(c) * 0.1


static func forget_tips(c: Node) -> void:
	_tip_cache.erase(c.get_instance_id())


# ---- 3D drawing ------------------------------------------------------------

func _rebuild_mesh() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, null)
	var verts: int = 0
	if draw_depth_bands and sim != null:
		verts += _draw_depth_bands(im)
	if _current != null and _history.size() > 1:
		verts += _draw_subject(im)
	if verts == 0:
		# An empty surface is an error; keep one degenerate segment.
		im.surface_set_color(Color(0, 0, 0, 0))
		im.surface_add_vertex(global_position)
		im.surface_add_vertex(global_position)
	im.surface_end()
	_mesh.mesh = im


func _draw_depth_bands(im: ImmediateMesh) -> int:
	var w: Node = sim.get_parent()
	var fish_v: Variant = sim.get("fish")
	if not (fish_v is Array):
		return 0
	var drawn: int = 0
	for f in fish_v as Array:
		if not is_instance_valid(f) or not (f is Fish):
			continue
		if drawn >= MAX_BAND_FISH:
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
	return drawn * 8


func _draw_subject(im: ImmediateMesh) -> int:
	var verts: int = 0
	var heads: PackedVector3Array = _history.ordered_heads()
	var tails: PackedVector3Array = _history.ordered_tails()
	for i in range(1, heads.size()):
		_line_vec(im, heads[i - 1], heads[i], Color(0.7, 0.95, 1.0, 0.45))
		verts += 2
	# #83: centre path coloured by curvature, breaks flagged.
	var path: PackedVector3Array = centre_path()
	if path.size() >= 3:
		var k: PackedFloat32Array = MotionMetrics.curvature(path)
		for i in range(1, path.size() - 1):
			var kk: float = absf(k[i - 1])
			var col: Color = Color(0.35, 1.0, 0.45).lerp(Color(1.0, 0.3, 1.0),
				clampf(kk / CURVATURE_SCALE, 0.0, 1.0))
			_line_vec(im, path[i - 1], path[i], col)
			verts += 2
			if i >= 2 and absf(k[i - 1] - k[i - 2]) > CURVATURE_BREAK:
				_line_vec(im, path[i] + Vector3(0, -0.04, 0), path[i] + Vector3(0, 0.08, 0),
					Color(1.0, 0.1, 0.1, 1.0))
				verts += 2
		_line_vec(im, path[path.size() - 2], path[path.size() - 1], Color(0.35, 1.0, 0.45))
		verts += 2
	# #81: onion skins, newest brightest.
	var n: int = heads.size()
	var first: int = maxi(0, n - ONION_COUNT)
	var dot: float = maxf(0.012, _body_length(_current) * 0.035)
	for i in range(first, n):
		var age: float = float(n - 1 - i) / float(ONION_COUNT)
		var a: float = lerpf(1.0, 0.25, age)
		_cross(im, heads[i], dot, Color(0.3, 0.95, 1.0, a))
		_cross(im, tails[i], dot, Color(1.0, 0.6, 0.15, a))
		verts += 12
	return verts


# The body-centre path decimated for curvature: at least CURVATURE_MIN_STEP
# or a twentieth of a body length between points.
func centre_path() -> PackedVector3Array:
	var step_len: float = CURVATURE_MIN_STEP
	if _current != null:
		step_len = maxf(step_len, _body_length(_current) * 0.05)
	return decimate(_roots, step_len)


static func decimate(points: PackedVector3Array, min_step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= min_step:
			out.append(p)
	return out


static func _body_length(c: Node) -> float:
	var v: float = float(c.get("adult_voxel_scale")) if c.get("adult_voxel_scale") != null else 0.15
	var el: float = float(c.get("body_elongation")) if c.get("body_elongation") != null else 1.0
	var s: float = (c as Node3D).scale.x if c is Node3D else 1.0
	return v * 5.5 * el * maxf(s, 0.1)


func _cross(im: ImmediateMesh, p: Vector3, r: float, col: Color) -> void:
	_line_vec(im, p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), col)
	_line_vec(im, p - Vector3(0, r, 0), p + Vector3(0, r, 0), col)
	_line_vec(im, p - Vector3(0, 0, r), p + Vector3(0, 0, r), col)


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


# ---- 2D graphs (#82 speed, #84 tail trace) ---------------------------------

func _ensure_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "MotionDebugHud"
	_hud_layer.layer = 90
	# On the root viewport: the world renders into a low-res, palette-
	# quantised viewport that would pixelate the graphs.
	var host: Node = self
	if is_inside_tree():
		host = get_tree().root
	host.add_child.call_deferred(_hud_layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.offset_left = 12.0
	_hud.offset_top = 100.0
	_hud.offset_right = 472.0
	_hud.offset_bottom = 350.0
	_hud_layer.add_child(_hud)
	_hud.draw.connect(func() -> void: draw_graphs(_hud, Rect2(Vector2.ZERO, _hud.size)))


# Draws the subject's speed graph, tail-tip traces and a metric line into
# any CanvasItem (the in-game HUD, or a motion-lab panel).
func draw_graphs(ci: CanvasItem, rect: Rect2) -> void:
	var font: Font = ThemeDB.fallback_font
	ci.draw_rect(rect, Color(0.04, 0.05, 0.07, 0.82))
	var subj: Node3D = current_subject()
	var title: String = "motion: no subject (follow a fish)"
	if subj != null:
		var sp: Variant = subj.get("species")
		var label: String = String(subj.get_meta("lab_kind", String(subj.name)))
		if sp != null:
			label = String(sp)
		title = "motion: %s  %s" % [label,
			String(subj.get("locomotion_type")) if subj.get("locomotion_type") != null else ""]
	ci.draw_string(font, rect.position + Vector2(8, 15), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.9, 0.95, 1.0))
	if subj == null or _history.size() < 2:
		return
	var pad: float = 8.0
	var top: float = 22.0
	var graph_h: float = (rect.size.y - top - 34.0) * 0.55
	var speed_rect := Rect2(rect.position + Vector2(pad, top), Vector2(rect.size.x - pad * 2.0, graph_h))
	_draw_speed(ci, speed_rect, font)
	var trace_top: float = speed_rect.end.y + 6.0
	var trace_h: float = rect.end.y - trace_top - 20.0
	var half_w: float = (rect.size.x - pad * 3.0) * 0.5
	_draw_tail_trace(ci, Rect2(Vector2(rect.position.x + pad, trace_top), Vector2(half_w, trace_h)), font, false)
	_draw_tail_trace(ci, Rect2(Vector2(rect.position.x + pad * 2.0 + half_w, trace_top), Vector2(half_w, trace_h)), font, true)
	if _metrics_t <= 0.0 or _metrics_text.is_empty():
		_metrics_t = 0.25
		_metrics_text = metrics_summary()
	ci.draw_string(font, Vector2(rect.position.x + pad, rect.end.y - 6.0), _metrics_text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - pad * 2.0, 11, Color(0.85, 0.9, 0.8))


func _draw_speed(ci: CanvasItem, r: Rect2, font: Font) -> void:
	ci.draw_rect(r, Color(1, 1, 1, 0.05))
	var speeds: PackedFloat32Array = _history.ordered_speeds()
	var times: PackedFloat32Array = _history.ordered_times()
	var n: int = speeds.size()
	var t_end: float = times[n - 1]
	var t0: float = t_end - HISTORY_S
	var peak: float = 0.05
	for s in speeds:
		peak = maxf(peak, s)
	var ms_v: Variant = _current.get("max_speed")
	if ms_v != null:
		peak = maxf(peak, float(ms_v))
	# Bout / burst / startle / event markers.
	for i in mini(n, _marks.size()):
		var m: int = _marks[i]
		if m == Mark.NONE:
			continue
		var x: float = r.position.x + (times[i] - t0) / HISTORY_S * r.size.x
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), MARK_COLORS.get(m, Color.WHITE), 1.0)
	var pts := PackedVector2Array()
	for i in n:
		var x: float = r.position.x + (times[i] - t0) / HISTORY_S * r.size.x
		var y: float = r.end.y - clampf(speeds[i] / peak, 0.0, 1.0) * r.size.y
		pts.append(Vector2(x, y))
	if pts.size() >= 2:
		ci.draw_polyline(pts, Color(0.4, 1.0, 0.6), 1.5)
	ci.draw_string(font, r.position + Vector2(3, 11), "speed 10 s (max %.2f u/s)  | bout  | burst  | startle  | event" % peak,
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6.0, 10, Color(0.75, 0.8, 0.85))


# Tail tip in the creature's own frame over the last TAIL_TRACE_S. Top view:
# lateral (x) across, fore-aft (z) down. Side view: fore-aft across, up (y) up.
func _draw_tail_trace(ci: CanvasItem, r: Rect2, font: Font, side: bool) -> void:
	ci.draw_rect(r, Color(1, 1, 1, 0.05))
	var n: int = _local_tails.size()
	var keep: int = mini(n, int(TAIL_TRACE_S * SAMPLE_HZ))
	if keep < 2:
		return
	var pts2 := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(n - keep, n):
		var p: Vector3 = _local_tails[i]
		var q := Vector2(p.z, -p.y) if side else Vector2(p.x, p.z)
		pts2.append(q)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	# Equal axis scale so the shape is honest; centred in the box.
	var span: float = maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1e-4)
	var sc: float = (minf(r.size.x, r.size.y) - 14.0) / span
	var mid: Vector2 = (lo + hi) * 0.5
	var c: Vector2 = r.get_center() + Vector2(0, 5)
	var out := PackedVector2Array()
	for q in pts2:
		out.append(c + (q - mid) * sc)
	ci.draw_polyline(out, Color(1.0, 0.65, 0.2), 1.2)
	ci.draw_circle(out[out.size() - 1], 2.5, Color(1.0, 0.9, 0.5))
	var label: String = "tail tip, side (fore-aft x up) %.3f u" if side else "tail tip, top (lateral x fore-aft) %.3f u"
	ci.draw_string(font, r.position + Vector2(3, 11), label % span, HORIZONTAL_ALIGNMENT_LEFT,
		r.size.x - 6.0, 10, Color(0.75, 0.8, 0.85))


# One line of live numbers for the subject: tail-beat Hz, Strouhal estimate,
# curvature breaks and jerk over the history window.
func metrics_summary() -> String:
	var n: int = _history.size()
	if n < 8:
		return ""
	var dt: float = 1.0 / SAMPLE_HZ
	var lat := PackedFloat32Array()
	var start: int = maxi(0, _local_tails.size() - int(4.0 * SAMPLE_HZ))
	for i in range(start, _local_tails.size()):
		lat.append(_local_tails[i].x)
	var hz: float = MotionMetrics.dominant_hz(lat, dt)
	var pc: Dictionary = MotionMetrics.percentiles(lat, [5, 95])
	var s: float = _current.scale.x if _current != null else 1.0
	var amp_pp: float = (float(pc[95]) - float(pc[5])) * s
	var speeds: PackedFloat32Array = _history.ordered_speeds()
	var u: float = MotionMetrics.mean(speeds.slice(maxi(0, speeds.size() - int(4.0 * SAMPLE_HZ))))
	var st: float = MotionMetrics.strouhal(hz, amp_pp, u)
	var breaks: int = MotionMetrics.curvature_breaks(centre_path(), CURVATURE_BREAK)
	var j: Dictionary = MotionMetrics.jerk(_roots, dt)
	return "tail %.2f Hz  A %.3f u  St %.2f  arc breaks %d  jerk mean %.0f p95 %.0f u/s3" % [
		hz, amp_pp, st, breaks, float(j["mean"]), float(j["p95"])]
