# Shared stage for the motion lab, motion clips and motion stills
# (CREATURE_MOTION_700 #94 #98 #105 #118).
#
# A neutral-grey box "tank" with no World, no sim and no saves: the node is
# its own tank stub (clamp_xyz_in_tank, boundary info), a LabSim child named
# SimDriver stands in for the sim, and creatures are the real fish.gd /
# shrimp.gd / snail.gd built the way the Library preview and
# smoke_snail_motion build them. Nothing here reads or writes TankSaves.
#
# Fish and crustaceans are steered along scripted paths (figure-eight, circle,
# straight runs, hover) instead of running their brains, so a manoeuvre is
# repeatable; the pose code that turns that steering into motion is the
# game's own (_motion_substep for fish, _process for shrimp and snails).
# Snails keep their own crawl logic.
extends Node3D

const SPACING: float = 4.0
const FISH_Y: float = 2.4
const LOOKAHEAD_MIN: float = 0.45
const PATHS: PackedStringArray = ["figure8", "circle", "straight", "hover"]
# Drive path that leaves target_velocity to the caller (motion clips).
const EXTERNAL: String = "external"

# The tank stub API fish.gd, shrimp.gd and snail.gd read from their world.
var SUBSTRATE_DEPTH: float = 0.0
var WATER_HEIGHT: float = 5.0
var TANK_SHAPE: String = "box"
var half_x: float = 60.0
var half_z: float = 3.0

var sim: LabSim = null
var fauna_root: Node3D = null
var snails_root: Node3D = null
var lab_time: float = 0.0
# creature instance id -> drive state (path, pace, theta, anchor, override)
var _drive: Dictionary = {}
var _builder: Object = null


class LabSim extends Node:
	var time_scale: float = 1.0
	var fish: Array = []
	var shrimp: Array = []
	var waste: Array = []
	var algae: Array = []
	var plants: Array = []
	var snail_predator_count: int = 0
	var water_chemistry: Variant = null
	var substrate: Variant = null
	var dissolved_o2: float = 0.95
	var total_plant_biomass: float = 300.0
	var substrate_top_y: float = 0.0
	var day_phase: float = 0.3
	var creature_visible: bool = true

	func daylight() -> float:
		return 1.0

	func is_creature_visible_to_camera(_creature: Node3D) -> bool:
		return creature_visible


func _ready() -> void:
	sim = LabSim.new()
	sim.name = "SimDriver"
	sim.substrate_top_y = SUBSTRATE_DEPTH
	add_child(sim)
	fauna_root = Node3D.new()
	fauna_root.name = "Fauna"
	add_child(fauna_root)
	snails_root = Node3D.new()
	snails_root.name = "Snails"
	add_child(snails_root)
	_build_backdrop()


func _exit_tree() -> void:
	if _builder != null and is_instance_valid(_builder):
		_builder.free()
	_builder = null


# ---- Tank stub -------------------------------------------------------------

func clamp_xyz_in_tank(p: Vector3, margin: float = 0.25, body_radius: float = 0.0) -> Vector3:
	var m: float = margin + maxf(0.0, body_radius)
	return Vector3(clampf(p.x, -half_x + m, half_x - m),
		clampf(p.y, SUBSTRATE_DEPTH, WATER_HEIGHT - m),
		clampf(p.z, -half_z + m, half_z - m))


func is_inside_tank_volume(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= half_x - margin and absf(z) <= half_z - margin \
		and y >= SUBSTRATE_DEPTH - 0.001 and y <= WATER_HEIGHT


func tank_lateral_boundary_info(p: Vector3, margin: float = 0.25) -> Dictionary:
	var walls: Array = [
		[Vector3.RIGHT, p.x + half_x], [Vector3.LEFT, half_x - p.x],
		[Vector3.BACK, p.z + half_z], [Vector3.FORWARD, half_z - p.z]]
	var best: Array = walls[0]
	for w in walls:
		if float(w[1]) < float(best[1]):
			best = w
	return {"inward": best[0], "clearance": float(best[1]) - margin}


# ---- Backdrop --------------------------------------------------------------

func _build_backdrop() -> void:
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.46, 0.48, 0.50)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.9)
	e.ambient_light_energy = 0.75
	e.glow_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = e
	add_child(env_node)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 0.8
	key.transform = Transform3D(Basis().rotated(Vector3.RIGHT, -0.8).rotated(Vector3.UP, -0.5), Vector3.ZERO)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.8, 0.85, 1.0)
	fill.light_energy = 0.35
	fill.transform = Transform3D(Basis().rotated(Vector3.RIGHT, 0.3).rotated(Vector3.UP, 2.4), Vector3.ZERO)
	add_child(fill)
	# Reference grids: 0.25 u on the floor and the back wall, 1 u bolder. A
	# grid is how translation timing (slow in / out) is read by eye.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, null)
	var minor := Color(0.40, 0.42, 0.44)
	var major := Color(0.33, 0.35, 0.37)
	var grid_step: float = 0.25
	var nx: int = int(half_x / grid_step)
	for i in range(-nx, nx + 1):
		var x: float = float(i) * grid_step
		var col: Color = major if i % 4 == 0 else minor
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(x, SUBSTRATE_DEPTH + 0.001, -half_z))
		im.surface_add_vertex(Vector3(x, SUBSTRATE_DEPTH + 0.001, half_z))
		im.surface_add_vertex(Vector3(x, SUBSTRATE_DEPTH, -half_z + 0.001))
		im.surface_add_vertex(Vector3(x, WATER_HEIGHT, -half_z + 0.001))
	var nz: int = int(half_z / grid_step)
	for i in range(-nz, nz + 1):
		var z: float = float(i) * grid_step
		im.surface_set_color(major if i % 4 == 0 else minor)
		im.surface_add_vertex(Vector3(-half_x, SUBSTRATE_DEPTH + 0.001, z))
		im.surface_add_vertex(Vector3(half_x, SUBSTRATE_DEPTH + 0.001, z))
	var ny: int = int((WATER_HEIGHT - SUBSTRATE_DEPTH) / grid_step)
	for i in range(0, ny + 1):
		var y: float = SUBSTRATE_DEPTH + float(i) * grid_step
		im.surface_set_color(major if i % 4 == 0 else minor)
		im.surface_add_vertex(Vector3(-half_x, y, -half_z + 0.001))
		im.surface_add_vertex(Vector3(half_x, y, -half_z + 0.001))
	im.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = im
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.vertex_color_use_as_albedo = true
	grid.material_override = gm
	add_child(grid)


# ---- Creature catalogue ----------------------------------------------------

# Every creature the lab can build: all SPECIES_LIBRARY fish, the four
# crustacean body plans and a snail. {key, label, type, genome}.
func kinds() -> Array:
	var out: Array = []
	var cfg: Node = get_node_or_null("/root/TankConfig")
	var lib: Dictionary = {}
	if cfg != null and cfg.get("SPECIES_LIBRARY") is Dictionary:
		lib = cfg.get("SPECIES_LIBRARY")
	for sp in lib.keys():
		var entry: Dictionary = lib[sp]
		out.append({"key": String(sp), "label": String(entry.get("label", sp)), "type": "fish",
			"genome": (entry.get("genome", {}) as Dictionary).duplicate(true)})
	var real: Dictionary = (load("res://scripts/real_species_fauna.gd") as Script).call("by_id")
	var crust: Array = [["caridean", "cherry_shrimp"], ["crab", "fiddler_crab"],
		["lobster", "crayfish"], ["mantis", "mantis_shrimp"]]
	for pair in crust:
		var g: Dictionary = {}
		var ent: Variant = real.get(pair[1], {})
		if ent is Dictionary:
			g = ((ent as Dictionary).get("genome", {}) as Dictionary).duplicate(true)
		g["body_shape"] = pair[0]
		out.append({"key": "shrimp:" + String(pair[0]), "label": "%s (%s)" % [pair[0], pair[1]],
			"type": "shrimp", "genome": g})
	out.append({"key": "snail:turbo", "label": "snail (turbo)", "type": "snail",
		"genome": {"shell_shape": "turbo"}})
	return out


func kind_by_key(key: String) -> Dictionary:
	for k in kinds():
		if String(k["key"]) == key:
			return k
	return {}


static func type_of(c: Node) -> String:
	if c is Fish:
		return "fish"
	if c is Shrimp:
		return "shrimp"
	if c != null and c.get("shell_shape") != null:
		return "snail"
	return "other"


# ---- Spawning --------------------------------------------------------------

func spawn(kind: Dictionary, anchor: Vector3) -> Node3D:
	var c: Node3D = null
	match String(kind.get("type", "fish")):
		"shrimp":
			c = _spawn_shrimp(kind, anchor)
		"snail":
			c = _spawn_snail(kind, anchor)
		_:
			c = _spawn_fish(kind, anchor)
	if c == null:
		return null
	c.set_meta("lab_kind", String(kind.get("key", "")))
	c.set_meta("lab_anchor", anchor)
	disable_lod(c)
	_drive[c.get_instance_id()] = {"path": "figure8", "pace": 0.35, "theta": 0.0,
		"anchor": anchor, "override": {}, "end": 1.0, "natural_bouts": true}
	return c


func _spawn_fish(kind: Dictionary, anchor: Vector3) -> Fish:
	var g: Dictionary = (kind.get("genome", {}) as Dictionary).duplicate(true)
	g["sex"] = 0
	g["mixed_morphs"] = false
	g.erase("preferred_y_frac")
	var f := Fish.new()
	f.id = "motion_lab:%s" % String(kind.get("key", "fish"))
	fauna_root.add_child(f)
	f.position = anchor
	f.maturity = Fish.MATURITY_ADULT
	f.init_genome(g)
	f.set_process(false)
	f.set_physics_process(false)
	f.position = anchor
	f.basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	# Set after init_genome: with a world in reach the voxels would go into a
	# shared species batch instead of the pivots the lab measures.
	f.sim = sim
	f.heading = Vector3.FORWARD
	f.target_velocity = Vector3.ZERO
	f.speed = 0.0
	f._last_yaw = 0.0
	f.home_y = anchor.y
	f._hover_depth = anchor.y
	f._spawn_settle_remaining = 0.0
	f._wag_freq_jitter = 1.0
	f._motor_phase = 0.3
	f._swim_phase = 0.3
	f.hunger = 0.3
	f.stress = 0.0
	return f


func _spawn_shrimp(kind: Dictionary, anchor: Vector3) -> Shrimp:
	var g: Dictionary = (kind.get("genome", {}) as Dictionary).duplicate(true)
	g["substrate_top_y"] = SUBSTRATE_DEPTH
	g["sex"] = 1
	var s := Shrimp.new()
	fauna_root.add_child(s)
	var p := Vector3(anchor.x, SUBSTRATE_DEPTH + 0.05, anchor.z)
	s.position = p
	s.maturity = Shrimp.MATURITY_ADULT
	s.init_genome(g)
	s.set_process(false)
	s.set_physics_process(false)
	s.position = p
	s.sim = sim
	s.velocity = Vector3.ZERO
	s.speed = 0.0
	s.heading = Vector3.FORWARD
	return s


func _spawn_snail(kind: Dictionary, anchor: Vector3) -> Node3D:
	if _builder == null:
		# The real builder, never added to the tree (smoke_snail_motion does
		# the same). Loaded at runtime: world.gd names autoloads.
		_builder = (load("res://scripts/world.gd") as GDScript).new()
	var sn: Node3D = (load("res://scripts/snail.gd") as GDScript).new()
	sn.position = Vector3(anchor.x, SUBSTRATE_DEPTH + 0.1, anchor.z)
	sn.set("wall_normal", Vector3.UP)
	sn.set("shell_shape", String((kind.get("genome", {}) as Dictionary).get("shell_shape", "turbo")))
	snails_root.add_child(sn)
	_builder.call("_build_snail_body", sn)
	sn.set_process(false)
	sn.set_physics_process(false)
	sn.set("_direction", Vector2(1.0, 0.25).normalized())
	sn.set("_facing", Vector2(1.0, 0.25).normalized())
	sn.set("_paused", false)
	sn.set("_crawl_speed_smoothed", 0.11)
	if sn.has_method("_sync_initial_orientation"):
		sn.call("_sync_initial_orientation", false)
	return sn


# Tank LOD ranges hide fauna batches at lab camera distances.
static func disable_lod(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			var gi: GeometryInstance3D = n
			gi.visibility_range_begin = 0.0
			gi.visibility_range_end = 0.0
			gi.visibility_range_end_margin = 0.0
		for ch in n.get_children():
			stack.push_back(ch)


func drive_state(c: Node) -> Dictionary:
	return _drive.get(c.get_instance_id(), {})


func forget(c: Node) -> void:
	_drive.erase(c.get_instance_id())


static func body_length(c: Node) -> float:
	if c is Fish:
		var f: Fish = c
		return f.adult_voxel_scale * 5.5 * f.body_elongation * maxf(f.scale.x, 0.1)
	if c is Shrimp:
		var s: Shrimp = c
		return s.adult_voxel_scale * 5.0 * s.body_length_factor * maxf(s.scale.x, 0.1) * 1.4
	return 0.35


# Orthographic camera size that frames a creature with room for its motion.
static func view_size(c: Node) -> float:
	if c is Fish:
		return body_length(c) * 2.4
	if c is Shrimp:
		return body_length(c) * 1.3
	return 0.9


# ---- Stepping --------------------------------------------------------------

# Advance one creature by sim dt: scripted steering, then the game's pose code.
# Returns false once the creature is gone (death sequence finished).
func step(c: Node3D, dt: float) -> bool:
	if not is_instance_valid(c) or c.is_queued_for_deletion():
		return false
	if dt <= 0.0:
		return true
	if c is Fish:
		_step_fish(c as Fish, dt)
	elif c is Shrimp:
		_drive_shrimp(c as Shrimp, dt)
		(c as Shrimp)._process(dt)
	else:
		c.call("_process", dt)
	return is_instance_valid(c) and not c.is_queued_for_deletion()


func _step_fish(f: Fish, dt: float) -> void:
	if f._dying:
		f._animate_death(dt)
		return
	_drive_fish(f, dt)
	# Timers the brain tick (Fish.tick) normally runs down.
	f.burst_remaining = maxf(0.0, f.burst_remaining - dt)
	f._startle_remaining = maxf(0.0, f._startle_remaining - dt)
	f._lb_display_t = maxf(0.0, f._lb_display_t - dt)
	if f._mouth_gape > 0.0:
		f._mouth_gape = maxf(0.0, f._mouth_gape - dt * 5.5)
	if f._courtship_flare:
		f._courtship_intensity = minf(1.0, f._courtship_intensity + dt / 3.0)
	# Same substep split as Fish._process; the pose is written once per frame.
	var n_steps: int = clampi(int(ceil(dt / 0.028)), 1, 20)
	var sub: float = dt / float(n_steps)
	for i in n_steps:
		f._motion_substep(sub, dt if i == n_steps - 1 else 0.0)
	f._apply_posture_overlays(dt)
	f._tick_gill_flush(dt)


func _carrot(st: Dictionary, theta: float) -> Vector3:
	var a: Vector3 = st["anchor"]
	var r: float = float(st.get("radius", 1.1))
	match String(st["path"]):
		"circle":
			return a + Vector3(cos(theta) * r, 0.0, sin(theta) * r * 0.8)
		"figure8":
			return a + Vector3(sin(theta) * r * 1.3, sin(theta * 2.0) * 0.12, sin(theta) * cos(theta) * r * 1.4)
	return a


func _path_target(c: Node3D, st: Dictionary, look: float) -> Vector3:
	var pos: Vector3 = c.global_position
	var a: Vector3 = st["anchor"]
	match String(st["path"]):
		"hover":
			return a
		"straight":
			var end_s: float = float(st.get("end", 1.0))
			var goal: Vector3 = a + Vector3(1.8 * end_s, 0.0, 0.0)
			if Vector2(goal.x - pos.x, goal.z - pos.z).length() < 0.35:
				st["end"] = -end_s
				goal = a + Vector3(-1.8 * end_s, 0.0, 0.0)
			return goal
	var theta: float = float(st["theta"])
	var guard: int = 0
	while _carrot(st, theta).distance_to(pos) < look and guard < 96:
		theta += 0.04
		guard += 1
	st["theta"] = theta
	return _carrot(st, theta)


func _drive_fish(f: Fish, dt: float) -> void:
	var st: Dictionary = drive_state(f)
	if st.is_empty():
		return
	var anchor: Vector3 = st["anchor"]
	var pace: float = float(st["pace"]) * f.max_speed
	var look: float = maxf(LOOKAHEAD_MIN, body_length(f) * 1.6)
	if not bool(st.get("natural_bouts", true)) and not f._courtship_flare:
		f.current_mode = Fish.Mode.FLEE
	elif not f._courtship_flare:
		f.current_mode = Fish.Mode.CRUISE
	var ov: Dictionary = st["override"]
	if ov.is_empty() and String(st["path"]) == EXTERNAL:
		return
	if not ov.is_empty():
		ov["t"] = float(ov["t"]) - dt
		var kind: String = String(ov["kind"])
		if float(ov["t"]) <= 0.0:
			if kind == "gulp":
				f.home_y = anchor.y
				f._hover_depth = anchor.y
			st["override"] = {}
		else:
			match kind:
				"dart", "startle":
					f.target_velocity = (ov["dir"] as Vector3) * f.max_speed * float(ov["mult"])
					return
				"gulp":
					var up: bool = float(ov["t"]) > float(ov["sink_at"])
					var goal_y: float = (WATER_HEIGHT - 0.22) if up else anchor.y
					if up and f.global_position.y > WATER_HEIGHT - 0.4 and not bool(ov.get("gaped", false)):
						f._trigger_mouth_gape()
						ov["gaped"] = true
					var to: Vector3 = Vector3(anchor.x - f.global_position.x, goal_y - f.global_position.y,
						anchor.z - f.global_position.z) * Vector3(0.3, 1.0, 0.3)
					f.target_velocity = to.normalized() * pace * 1.2 if to.length_squared() > 1e-4 else Vector3.ZERO
					return
				"display":
					pace *= 0.3
	var goal: Vector3 = _path_target(f, st, look)
	var d: Vector3 = goal - f.global_position
	var dist: float = d.length()
	var spd: float = pace
	if String(st["path"]) == "hover":
		spd = pace * clampf(dist / 0.6, 0.0, 1.0)
	f.target_velocity = d / dist * spd if dist > 1e-4 else Vector3.ZERO


func _drive_shrimp(s: Shrimp, dt: float) -> void:
	var st: Dictionary = drive_state(s)
	if st.is_empty() or s._dying:
		return
	var pace: float = float(st["pace"]) * s.max_speed
	var ov: Dictionary = st["override"]
	if ov.is_empty() and String(st["path"]) == EXTERNAL:
		return
	var tv: Vector3
	if not ov.is_empty():
		ov["t"] = float(ov["t"]) - dt
		if float(ov["t"]) <= 0.0:
			st["override"] = {}
		tv = (ov["dir"] as Vector3) * s.max_speed * 1.8
	else:
		st["radius"] = 0.7
		var goal: Vector3 = _path_target(s, st, maxf(0.3, body_length(s)))
		goal.y = SUBSTRATE_DEPTH + 0.05
		var d: Vector3 = goal - s.global_position
		d.y = 0.0
		var dist: float = d.length()
		var spd: float = pace if String(st["path"]) != "hover" else pace * clampf(dist / 0.4, 0.0, 1.0)
		tv = d / dist * spd if dist > 1e-4 else Vector3.ZERO
	s._prev_target_velocity = tv
	s._target_velocity = tv


# ---- Actions ---------------------------------------------------------------

func actions_for(c: Node) -> PackedStringArray:
	if c is Fish:
		var acts := PackedStringArray(["dart", "startle", "gulp", "court", "die"])
		if (c as Fish).is_livebearer:
			acts.insert(3, "display")
		return acts
	if c is Shrimp:
		return PackedStringArray(["flip", "die"])
	return PackedStringArray(["retract eyes", "clamp"])


# Trigger an action through the fields the game itself uses. Returns false
# when the creature has no such action.
func trigger(c: Node3D, action: String) -> bool:
	if not is_instance_valid(c):
		return false
	var st: Dictionary = drive_state(c)
	if c is Fish:
		var f: Fish = c
		var fwd: Vector3 = MotionDebugOverlay.creature_heading(f)
		match action:
			"dart":
				f.burst_remaining = 0.55
				st["override"] = {"kind": "dart", "t": 0.55, "mult": 1.7,
					"dir": fwd.rotated(Vector3.UP, 0.35).normalized()}
			"startle":
				var away: Vector3 = fwd.rotated(Vector3.UP, 1.9 if randf() < 0.5 else -1.9)
				away.y = 0.0
				away = away.normalized()
				f._startle_remaining = 0.6
				f._startle_heading = away
				f.burst_remaining = maxf(f.burst_remaining, 0.45)
				st["override"] = {"kind": "startle", "t": 0.6, "mult": 1.9, "dir": away}
			"gulp":
				f.home_y = WATER_HEIGHT - 0.3
				f._hover_depth = f.home_y
				st["override"] = {"kind": "gulp", "t": 3.2, "sink_at": 1.4, "gaped": false}
			"display":
				f._lb_display_t = 1.6
				f._lb_side = 1.0 if randf() < 0.5 else -1.0
				st["override"] = {"kind": "display", "t": 1.6}
			"court":
				f._courtship_flare = not f._courtship_flare
				if f._courtship_flare:
					f.current_mode = Fish.Mode.COURT
				else:
					f._courtship_intensity = 0.0
					f.current_mode = Fish.Mode.CRUISE
			"die":
				f.start_dying()
			_:
				return false
		return true
	if c is Shrimp:
		var s: Shrimp = c
		match action:
			"flip":
				var back: Vector3 = -MotionDebugOverlay.creature_heading(s)
				back.y = 0.0
				s._escape_remaining = 0.45
				st["override"] = {"kind": "flip", "t": 0.45, "dir": back.normalized()}
			"die":
				s.start_dying()
			_:
				return false
		return true
	match action:
		"retract eyes":
			c.set("_eye_retract_remaining", 0.8)
		"clamp":
			c.set("_clamped", true)
			c.set("_clamp_grace_remaining", 2.5)
		_:
			return false
	return true


# ---- Pose channels ---------------------------------------------------------

const PIVOT_FIELDS: PackedStringArray = [
	"_bank_pivot", "_head_pivot", "_body_mid_pivot", "_tail_pivot", "_dorsal_pivot",
	"_pec_left_pivot", "_pec_right_pivot", "_antenna_pivot", "_body", "_shell_pivot",
	"_foot_pivot", "_eye_stalks", "_operculum_pivot",
]


# Every animated pivot on a creature, name -> Node3D (legs included).
static func pivot_nodes(c: Node) -> Dictionary:
	var out: Dictionary = {}
	for field in PIVOT_FIELDS:
		var p: Variant = c.get(field)
		if p is Node3D and is_instance_valid(p):
			out[field.trim_prefix("_")] = p
	var legs: Variant = c.get("_leg_pivots")
	if legs is Array:
		for entry in legs as Array:
			if entry is Dictionary:
				var n: Variant = (entry as Dictionary).get("node")
				if n is Node3D and is_instance_valid(n):
					out["leg_" + String((n as Node3D).name)] = n
	return out


# Place an orthographic camera on a creature. view: side | top | front.
# body_frame turns the rig with the creature's heading (yaw only, so bank and
# pitch stay visible); otherwise side looks down -Z, top down -Y, front -X.
static func place_camera(cam: Camera3D, c: Node3D, view: String, body_frame: bool, size: float,
		focus: Vector3) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(size, 0.2)
	cam.near = 0.05
	cam.far = 40.0
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	if body_frame and c != null:
		var h: Vector3 = MotionDebugOverlay.creature_heading(c)
		h.y = 0.0
		if h.length_squared() > 1e-6:
			fwd = h.normalized()
			right = fwd.cross(Vector3.UP).normalized()
	var dist: float = 8.0
	match view:
		"top":
			var up_v: Vector3 = fwd if body_frame else Vector3.FORWARD
			cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, up_v), focus + Vector3.UP * dist)
		"front":
			var eye: Vector3 = focus + (fwd if body_frame else Vector3.RIGHT) * dist
			cam.global_transform = Transform3D(Basis.looking_at(focus - eye, Vector3.UP), eye)
		_:
			var eye2: Vector3 = focus + (right if body_frame else Vector3.BACK) * dist
			cam.global_transform = Transform3D(Basis.looking_at(focus - eye2, Vector3.UP), eye2)
