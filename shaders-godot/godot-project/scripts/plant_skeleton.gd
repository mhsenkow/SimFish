# Articulated stem skeleton for base-Plant stem species.
#
# A real stem plant is a chain of internodes joined at nodes, and each node
# carries a leaf (or a pair / whorl) with a dormant axillary bud in its axil.
# This class is the pure-data model of that chain. It does not own geometry:
# Plant asks it where the next node goes, which bud to release, how far the
# stem is currently bent toward the lamp, and how it should respond to flow.
# Plant still bakes voxels exactly as before, so biomass (== nodes grown) and
# every ecology path stay untouched.
#
# Cost model: everything here runs at growth time or at the plant's ~2 Hz
# tropism cadence. Nothing is per frame, nothing is per voxel. The motion
# itself lives in foliage_mm.gdshader (`chain_bend` + the per-instance flex
# weight already stored in MultiMesh custom data).
#
#   Apex growth    — grow_internode(): the new direction is the previous
#                    direction pulled toward the tropism desire (light + up +
#                    flow) by the stem's compliance, with the tilt bounded so
#                    a tall stem curves instead of drifting out of the tank.
#   Surface trail  — grow_trail_node(): once the apex meets the waterline the
#                    stem turns and runs along it, the way Rotala/Ludwigia do.
#   Apical dominance — pick_released_bud(): buds stay dormant within a
#                    distance of the apex that shrinks with nutrients, grows
#                    with shade, and collapses once the apex is lost/trailing.
#   Phototropism   — step_bend(): the grown stem slowly bows toward the lamp
#                    (time constant ~minutes), bounded by stem height.
#   Sway           — chain_sway(): bounded per-plant chain parameters for the
#                    shader, from stem height, age stiffness and local flow.
class_name PlantSkeleton
extends RefCounted

const VERSION: int = 1

const FLAG_TRAIL: int = 1
const FLAG_BUD_RELEASED: int = 2

# Apex tilt caps (radians from vertical). Bright tanks grow nearly upright;
# shaded stems lean harder for the light.
const MAX_TILT_BRIGHT: float = 0.10
const MAX_TILT_SHADE: float = 0.34
# Phototropic rest bend: tip deflection as a fraction of stem height, and an
# absolute ceiling so a very tall tank cannot fold a stem over.
const REST_BEND_HEIGHT_FRAC: float = 0.085
const REST_BEND_MAX: float = 1.2
const BEND_TIME_CONSTANT_S: float = 55.0
# Flow lean ceiling, as a fraction of height.
const FLOW_LEAN_HEIGHT_FRAC: float = 0.06
const FLOW_LEAN_MAX: float = 0.8
const TRAIL_MAX_NODES: int = 6
const SIDE_SHOOT_CAP: int = 6
const MIN_BUD_SPACING: int = 3

var node_pos: PackedVector3Array = PackedVector3Array()
var node_dir: PackedVector3Array = PackedVector3Array()
var node_birth: PackedFloat32Array = PackedFloat32Array()
var node_flags: PackedByteArray = PackedByteArray()
var apex_present: bool = true
var trail_heading: Vector2 = Vector2.ZERO
var rest_bend: Vector2 = Vector2.ZERO
var side_shoot_nodes: PackedInt32Array = PackedInt32Array()
# Positions recorded by a save, consumed in order while init() regrows the
# plant, so a reloaded stem keeps the exact curve it grew with.
var _replay_pos: PackedVector3Array = PackedVector3Array()
var _replay_trail: PackedVector3Array = PackedVector3Array()


func reset() -> void:
	node_pos.clear()
	node_dir.clear()
	node_birth.clear()
	node_flags.clear()
	side_shoot_nodes.clear()
	apex_present = true
	trail_heading = Vector2.ZERO
	rest_bend = Vector2.ZERO


func node_count() -> int:
	return node_pos.size()


func trail_count() -> int:
	var n: int = 0
	for f in node_flags:
		if f & FLAG_TRAIL:
			n += 1
	return n


func vertical_count() -> int:
	return node_count() - trail_count()


func is_trailing() -> bool:
	return not node_flags.is_empty() and (node_flags[node_flags.size() - 1] & FLAG_TRAIL) != 0


func apex_dir() -> Vector3:
	if node_dir.is_empty():
		return Vector3.UP
	return node_dir[node_dir.size() - 1]


func apex_pos() -> Vector3:
	if node_pos.is_empty():
		return Vector3.ZERO
	return node_pos[node_pos.size() - 1]


# Last vertical (non-trailing) node — where the stem meets the waterline.
func last_vertical_index() -> int:
	for i in range(node_flags.size() - 1, -1, -1):
		if (node_flags[i] & FLAG_TRAIL) == 0:
			return i
	return -1


func has_replay() -> bool:
	return not _replay_pos.is_empty()


func replay_trail_count() -> int:
	return _replay_trail.size()


# Next replayed vertical position, or null when there is none left.
func peek_replay() -> Variant:
	var i: int = vertical_count()
	if i < _replay_pos.size():
		return _replay_pos[i]
	return null


# Place the next vertical internode. `y` is the builder's node height (the
# voxel builders own vertical spacing); the skeleton owns the lateral path.
# Returns the node's plant-local lateral offset (x, z).
func grow_internode(desire: Vector3, length: float, compliance: float,
		max_tilt: float, reach: float, y: float, birth_t: float,
		initial_lean: Vector2 = Vector2.ZERO) -> Vector2:
	var replay: Variant = peek_replay()
	var prev_pos: Vector3 = apex_pos()
	var prev_dir: Vector3 = apex_dir()
	if node_dir.is_empty() and initial_lean.length_squared() > 1e-8:
		prev_dir = Vector3(initial_lean.x, 1.0, initial_lean.y).normalized()
	var d: Vector3
	var lateral: Vector2
	if replay is Vector3:
		var rp: Vector3 = replay
		lateral = Vector2(rp.x, rp.z)
		var step := Vector3(rp.x - prev_pos.x, maxf(rp.y - prev_pos.y, 0.05), rp.z - prev_pos.z)
		d = step.normalized()
	else:
		var want: Vector3 = desire.normalized() if desire.length_squared() > 1e-8 else Vector3.UP
		d = prev_dir.lerp(want, clampf(compliance, 0.0, 1.0))
		if d.length_squared() < 1e-8:
			d = Vector3.UP
		d = d.normalized()
		# Gravitropism: a stem never grows downward.
		d.y = maxf(d.y, 0.2)
		var prev_lat := Vector2(prev_pos.x, prev_pos.z)
		# Soft reach budget: the tilt allowance fades as the stem approaches
		# its lateral reach, and past 70% of it the apex steers back.
		var reach_used: float = prev_lat.length() / maxf(reach, 0.01)
		var tilt_cap: float = maxf(max_tilt, 0.0) * clampf(1.0 - reach_used * reach_used, 0.15, 1.0)
		var h := Vector2(d.x, d.z)
		if reach_used > 0.7 and prev_lat.length_squared() > 1e-8:
			var inward: Vector2 = -prev_lat.normalized()
			h += inward * (reach_used - 0.7) * 0.6
		var tilt: float = atan2(h.length(), d.y)
		if tilt > tilt_cap and h.length_squared() > 1e-10:
			h = h.normalized() * tan(tilt_cap) * d.y
		d = Vector3(h.x, d.y, h.y).normalized()
		lateral = prev_lat + Vector2(d.x, d.z) * length
	node_pos.append(Vector3(lateral.x, y, lateral.y))
	node_dir.append(d)
	node_birth.append(birth_t)
	node_flags.append(0)
	return lateral


# Continue the stem horizontally just under the waterline.
func grow_trail_node(surface_local_y: float, length: float, birth_t: float,
		fallback_heading: Vector2) -> Vector3:
	var i: int = trail_count()
	var pos: Vector3
	if i < _replay_trail.size():
		pos = _replay_trail[i]
	else:
		if trail_heading.length_squared() < 1e-6:
			var lat := Vector2(apex_pos().x, apex_pos().z)
			trail_heading = lat.normalized() if lat.length() > 0.05 else fallback_heading
			if trail_heading.length_squared() < 1e-6:
				trail_heading = Vector2.RIGHT
			trail_heading = trail_heading.normalized()
		# A slight meander so a trailing run is not ruler-straight.
		var wobble: float = sin(float(i) * 1.7 + float(node_count()) * 0.37) * 0.22
		var heading: Vector2 = trail_heading.rotated(wobble)
		var base: Vector3 = apex_pos()
		pos = Vector3(base.x + heading.x * length, surface_local_y, base.z + heading.y * length)
	var d: Vector3 = (pos - apex_pos())
	node_pos.append(pos)
	node_dir.append(d.normalized() if d.length_squared() > 1e-8 else Vector3.RIGHT)
	node_birth.append(birth_t)
	node_flags.append(FLAG_TRAIL)
	return pos


# Drop vertical nodes above `max_y` (eaten / trimmed / decayed) and trailing
# nodes beyond `alive_trail`. Any loss at the tip removes the apex.
func truncate(max_y: float, alive_trail: int) -> int:
	var removed: int = 0
	var keep_trail: int = maxi(alive_trail, 0)
	var seen_trail: int = 0
	var keep_pos := PackedVector3Array()
	var keep_dir := PackedVector3Array()
	var keep_birth := PackedFloat32Array()
	var keep_flags := PackedByteArray()
	for i in node_pos.size():
		var f: int = node_flags[i]
		var drop: bool = false
		if f & FLAG_TRAIL:
			seen_trail += 1
			drop = seen_trail > keep_trail
		else:
			drop = node_pos[i].y > max_y + 0.05
		if drop:
			removed += 1
			continue
		keep_pos.append(node_pos[i])
		keep_dir.append(node_dir[i])
		keep_birth.append(node_birth[i])
		keep_flags.append(f)
	if removed > 0:
		node_pos = keep_pos
		node_dir = keep_dir
		node_birth = keep_birth
		node_flags = keep_flags
		apex_present = false
		var kept_shoots := PackedInt32Array()
		for s in side_shoot_nodes:
			if s < node_pos.size():
				kept_shoots.append(s)
		side_shoot_nodes = kept_shoots
	return removed


# Called when growth resumes at the tip after a loss.
func restore_apex() -> void:
	apex_present = true


# Buds in the axils just below a cut break first — the textbook response to
# pinching a stem. Returns up to `max_n` node indices and marks them used.
func release_buds_below_cut(max_n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var top: int = last_vertical_index()
	var i: int = top
	while i >= 1 and out.size() < max_n and side_shoot_nodes.size() < SIDE_SHOOT_CAP:
		if (node_flags[i] & (FLAG_BUD_RELEASED | FLAG_TRAIL)) == 0:
			_mark_released(i)
			out.append(i)
		i -= 1
		if top - i > 3:
			break
	return out


# Apical dominance. `auxin` 0..1 is the species' dominance strength,
# `nutrient` and `shade` are 0..1, `roll` is a uniform random number supplied
# by the caller (kept out of here so tests are deterministic).
func pick_released_bud(auxin: float, nutrient: float, shade: float, roll: float) -> int:
	if side_shoot_nodes.size() >= SIDE_SHOOT_CAP:
		return -1
	var top: int = last_vertical_index()
	if top < 4:
		return -1
	var apex_suppressing: bool = apex_present and not is_trailing()
	var distance: int
	var chance: float
	if apex_suppressing:
		# Dormancy zone: long under strong auxin or shade, short when rich.
		var zone: float = lerpf(4.0, 13.0, clampf(auxin, 0.0, 1.0))
		zone *= lerpf(1.25, 0.7, clampf(nutrient, 0.0, 1.0))
		zone *= lerpf(1.0, 1.5, clampf(shade, 0.0, 1.0))
		distance = maxi(3, int(round(zone)))
		chance = clampf((nutrient - 0.55) * 0.9, 0.0, 0.35) * (1.0 - shade * 0.7)
	else:
		# Apex lost or lying on the surface: dominance collapses.
		distance = 2
		chance = 0.55
	if roll > chance:
		return -1
	var candidate: int = top - distance
	while candidate >= 1:
		if _bud_available(candidate):
			_mark_released(candidate)
			return candidate
		candidate -= 1
	return -1


func _bud_available(i: int) -> bool:
	if i < 1 or i >= node_flags.size():
		return false
	if node_flags[i] & (FLAG_BUD_RELEASED | FLAG_TRAIL):
		return false
	for s in side_shoot_nodes:
		if absi(s - i) < MIN_BUD_SPACING:
			return false
	return true


func _mark_released(i: int) -> void:
	node_flags[i] = node_flags[i] | FLAG_BUD_RELEASED
	side_shoot_nodes.append(i)


# Phototropic target for the whole stem's tip deflection. `light_xz` points
# toward the lamp in world xz; shaded stems bow further.
static func phototropic_target(light_xz: Vector2, shade: float, stem_height: float) -> Vector2:
	if light_xz.length_squared() < 1e-8 or stem_height <= 0.0:
		return Vector2.ZERO
	var cap: float = minf(stem_height * REST_BEND_HEIGHT_FRAC, REST_BEND_MAX)
	return light_xz.normalized() * cap * lerpf(0.45, 1.0, clampf(shade, 0.0, 1.0))


# Exponential approach toward `target`, time constant BEND_TIME_CONSTANT_S.
func step_bend(target: Vector2, dt: float, stem_height: float) -> Vector2:
	var k: float = 1.0 - exp(-maxf(dt, 0.0) / BEND_TIME_CONSTANT_S)
	rest_bend = rest_bend.lerp(target, k)
	var cap: float = minf(maxf(stem_height, 0.0) * REST_BEND_HEIGHT_FRAC, REST_BEND_MAX)
	rest_bend = rest_bend.limit_length(cap)
	return rest_bend


# Bounded chain parameters for the GPU. `stiffness` 0..1 (woody/old = 1),
# `flow` is the local water velocity (world), `_base_amp` is reserved (the plant sway; the caller scales).
static func chain_sway(stem_height: float, stiffness: float, flow: Vector3,
		_base_amp: float) -> Dictionary:
	var h: float = maxf(stem_height, 0.0)
	var s: float = clampf(stiffness, 0.0, 1.0)
	var compliance: float = lerpf(1.0, 0.35, s)
	var fxz := Vector2(flow.x, flow.z)
	# Drag grows with the square of speed; clamp the input so a pump jet
	# cannot flatten a stem.
	var speed: float = minf(fxz.length(), 0.6)
	var lean_len: float = minf(speed * speed * 3.2 * h * compliance,
		minf(h * FLOW_LEAN_HEIGHT_FRAC, FLOW_LEAN_MAX))
	var lean: Vector2 = fxz.normalized() * lean_len if speed > 1e-4 else Vector2.ZERO
	return {
		"flow_lean": lean,
		# Taller stems swing further at the tip but more slowly.
		"amp_scale": clampf(lerpf(0.8, 1.25, clampf(h / 8.0, 0.0, 1.0)) * compliance, 0.25, 1.3),
		"speed_scale": clampf(lerpf(1.1, 0.7, clampf(h / 10.0, 0.0, 1.0)), 0.6, 1.2),
		# Phase lag base-to-tip in radians: motion travels up the chain.
		"lag": clampf(1.2 + h * 0.25, 1.2, 3.4),
	}


func to_dict() -> Dictionary:
	var pos_out: Array = []
	var trail_out: Array = []
	for i in node_pos.size():
		var p: Vector3 = node_pos[i]
		var packed: Array = [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
		if node_flags[i] & FLAG_TRAIL:
			trail_out.append(packed)
		else:
			pos_out.append(packed)
	var shoots: Array = []
	for s in side_shoot_nodes:
		shoots.append(s)
	return {
		"v": VERSION,
		"pos": pos_out,
		"trail": trail_out,
		"shoots": shoots,
		"apex": apex_present,
		"bend": [snappedf(rest_bend.x, 0.001), snappedf(rest_bend.y, 0.001)],
		"heading": [snappedf(trail_heading.x, 0.001), snappedf(trail_heading.y, 0.001)],
	}


# Load a saved skeleton as replay data. A missing / malformed dictionary is
# the migration path for pre-skeleton saves: the plant simply regrows a
# fresh chain from its saved height.
func load_dict(d: Variant) -> bool:
	reset()
	_replay_pos.clear()
	_replay_trail.clear()
	if not d is Dictionary:
		return false
	var dd: Dictionary = d
	_replay_pos = _read_points(dd.get("pos", []))
	_replay_trail = _read_points(dd.get("trail", []))
	apex_present = bool(dd.get("apex", true))
	rest_bend = _read_vec2(dd.get("bend", [])).limit_length(REST_BEND_MAX)
	trail_heading = _read_vec2(dd.get("heading", []))
	return true


# Side shoots recorded by the save (applied after regrowth by Plant).
static func saved_shoots(d: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if d is Dictionary:
		var raw: Variant = (d as Dictionary).get("shoots", [])
		if raw is Array:
			for v in raw:
				out.append(int(v))
	return out


func end_replay() -> void:
	_replay_pos.clear()
	_replay_trail.clear()


static func _read_points(raw: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not raw is Array:
		return out
	for v in raw:
		if v is Array and (v as Array).size() >= 3:
			var a: Array = v
			out.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	return out


static func _read_vec2(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		var a: Array = raw
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


# Force-release one specific bud (save restore). False if not available.
func release_bud_at(i: int) -> bool:
	if not _bud_available(i) or side_shoot_nodes.size() >= SIDE_SHOOT_CAP:
		return false
	_mark_released(i)
	return true
