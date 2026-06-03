# A freshwater clam / mussel. Sessile bivalve filter feeder.
#
# Behavior model:
#   - Sits on the substrate, hinged shell that opens to feed and closes
#     to rest. Doesn't roam — once spawned, position is fixed.
#   - Feeding cycle: REST (shell closed) → OPENING → FEEDING (siphon
#     extended, drawing nearby waste particles in) → CLOSING → REST.
#   - Filter consumption: every FEED_INTERVAL_S in the FEEDING phase,
#     scans sim.waste within FILTER_RADIUS, consumes the closest one,
#     gains energy, deposits a small nutrient amount to substrate. This
#     closes the detrital loop the same way shrimp do, but in a pool
#     fish + shrimp don't compete for (waste mid-water above the clam).
#   - Lifecycle: BABY (smaller scale, slower feed) → ADULT → SENESCENT
#     (after max_age_s) → dies. On death drops a shell-fragment waste
#     particle.
#
# Realism notes:
#   - Real freshwater clams are obligate filter feeders. They process
#     a few liters of water per day; we compress that to a per-second
#     consumption rate so the player sees waste vanishing nearby.
#   - The "siphon" voxel sits inside the open shell and extends about
#     a quarter-voxel above the shell rim when actively pumping — a
#     readable visual cue for "this thing is alive and doing something."
#   - Closes immediately if surface or local water quality drops, then
#     reopens once conditions are back. Doesn't model that explicitly
#     yet; just times its own rest cycle.

extends Node3D
class_name Clam

const MATURITY_BABY := 0
const MATURITY_ADULT := 1
const MATURITY_SENESCENT := 2

enum Mode { REST, OPENING, FEEDING, CLOSING }

# ---- Genome ----
var shell_color: Color = Color8(160, 142, 110)
var body_color: Color = Color8(220, 180, 165)
var siphon_color: Color = Color8(180, 130, 130)
var max_age_s: float = 240.0
var filter_radius: float = 1.6
var shell_size: float = 1.0  # 0.7..1.4 morphological variation

# ---- Lineage ----
var generation: int = 0
var clam_name: String = ""
var parent_lineage: String = "Founders"
var id: String = ""

# ---- State ----
var age: float = 0.0
var energy: float = 0.75
var maturity: int = MATURITY_BABY
var current_mode: int = Mode.REST
var _mode_t: float = 0.0
var _feed_timer: float = 0.0
var sim: Node = null
# Set the moment _on_death fires so tick() doesn't trigger death side
# effects twice when the sim runs multiple ticks per frame (high
# time_scale). queue_free() is deferred, so the node is still valid until
# end of frame — this flag short-circuits any follow-up tick.
var _dead: bool = false

const BABY_DURATION_S: float = 60.0
const REST_DURATION_S: float = 4.5
const OPENING_DURATION_S: float = 1.0
const FEEDING_DURATION_S: float = 6.0
const CLOSING_DURATION_S: float = 0.8
const FEED_INTERVAL_S: float = 1.4
const FEED_ENERGY_GAIN: float = 0.08
const ENERGY_DECAY_PER_S: float = 0.004

# ---- Visual parts ----
var _shell_upper: MeshInstance3D = null
var _shell_lower: MeshInstance3D = null
var _foot: MeshInstance3D = null
var _siphon: MeshInstance3D = null
var _siphon_base_y: float = 0.0
var _open_amount: float = 0.0  # 0..1, drives shell hinge + siphon extension
var _open_target: float = 0.0


func init_genome(g: Dictionary = {}) -> void:
	if g.has("shell_color") and g["shell_color"] is Color:
		shell_color = g["shell_color"]
	if g.has("body_color") and g["body_color"] is Color:
		body_color = g["body_color"]
	if g.has("siphon_color") and g["siphon_color"] is Color:
		siphon_color = g["siphon_color"]
	max_age_s = float(g.get("max_age_s", max_age_s))
	filter_radius = float(g.get("filter_radius", filter_radius))
	shell_size = clampf(float(g.get("shell_size", shell_size)), 0.6, 1.6)
	generation = int(g.get("generation", generation))
	parent_lineage = String(g.get("parent_lineage", parent_lineage))
	clam_name = String(g.get("clam_name", clam_name))
	if clam_name == "":
		clam_name = "Clam %d" % (randi() % 900 + 100)
	add_to_group("clams")
	_build_body()


func get_saved_genome() -> Dictionary:
	# Mirrors fish/shrimp/snail shape so species_library can fingerprint
	# clams for discovery without a custom case.
	return {
		"organism_type": "clam",
		"species": "clam",
		"clam_name": clam_name,
		"shell_color": shell_color,
		"body_color": body_color,
		"siphon_color": siphon_color,
		"shell_size": shell_size,
		"max_age_s": max_age_s,
		"filter_radius": filter_radius,
		"generation": generation,
		"parent_lineage": parent_lineage,
	}


func _build_body() -> void:
	# Lower shell — flat, slightly broader than the upper half. Sits on
	# the substrate; we offset its origin down by half its height so the
	# pivot at y=0 is the substrate contact plane.
	const VOX: float = 0.32
	var lower_size := Vector3(VOX * 0.85 * shell_size,
		VOX * 0.22 * shell_size, VOX * 0.62 * shell_size)
	_shell_lower = MeshInstance3D.new()
	_shell_lower.mesh = VoxelMat.get_box(lower_size)
	_shell_lower.material_override = VoxelMat.make_fauna(shell_color.darkened(0.18))
	_shell_lower.position = Vector3(0.0, lower_size.y * 0.5, 0.0)
	add_child(_shell_lower)
	# Upper shell — slightly narrower, hinges open from the back edge.
	# Implement the hinge by parenting a Node3D pivot at the back and
	# offsetting the visible mesh forward. That way rotation.x opens the
	# shell like a real hinge instead of pivoting around the shell middle.
	var upper_pivot := Node3D.new()
	upper_pivot.position = Vector3(0.0, lower_size.y * 1.05, -lower_size.z * 0.45)
	add_child(upper_pivot)
	var upper_size := Vector3(VOX * 0.80 * shell_size,
		VOX * 0.24 * shell_size, VOX * 0.58 * shell_size)
	_shell_upper = MeshInstance3D.new()
	_shell_upper.mesh = VoxelMat.get_box(upper_size)
	_shell_upper.material_override = VoxelMat.make_fauna(shell_color)
	_shell_upper.position = Vector3(0.0, upper_size.y * 0.5, upper_size.z * 0.45)
	upper_pivot.add_child(_shell_upper)
	# Foot / mantle — soft body visible between the shells when open.
	_foot = MeshInstance3D.new()
	_foot.mesh = VoxelMat.get_box(Vector3(
		VOX * 0.55 * shell_size, VOX * 0.10 * shell_size, VOX * 0.40 * shell_size))
	_foot.material_override = VoxelMat.make_fauna(body_color)
	_foot.position = Vector3(0.0, lower_size.y + 0.005, 0.0)
	add_child(_foot)
	# Siphon — small tube that extends upward when feeding. Its base
	# position is fixed; we drive its Y in _process based on _open_amount.
	_siphon = MeshInstance3D.new()
	_siphon.mesh = VoxelMat.get_box(Vector3(
		VOX * 0.16 * shell_size, VOX * 0.20 * shell_size, VOX * 0.16 * shell_size))
	_siphon.material_override = VoxelMat.make_fauna(siphon_color)
	_siphon_base_y = lower_size.y + 0.02
	_siphon.position = Vector3(0.0, _siphon_base_y, lower_size.z * 0.18)
	_siphon.visible = false  # only visible when open enough to read
	add_child(_siphon)
	# Babies start visibly smaller.
	scale = Vector3.ONE * (0.55 if maturity == MATURITY_BABY else 1.0)


# Per-tick simulation step. Called by sim_driver every sim tick (~10 Hz).
# Separate from _process which handles visual interpolation at frame rate.
func tick(dt: float, waste_list: Array, substrate: SubstrateGrid) -> void:
	if _dead:
		return
	age += dt
	# Maturity progression.
	if maturity == MATURITY_BABY and age >= BABY_DURATION_S:
		maturity = MATURITY_ADULT
		scale = Vector3.ONE
	if maturity == MATURITY_ADULT and age >= max_age_s * 0.85:
		maturity = MATURITY_SENESCENT
	# Energy slowly decays; feeding refills it.
	energy = clampf(energy - ENERGY_DECAY_PER_S * dt, 0.0, 1.0)
	# Mode machine.
	_mode_t += dt
	match current_mode:
		Mode.REST:
			_open_target = 0.0
			# Adults rest, then open to feed. Senescent clams open
			# half as often (real winding down before death).
			var rest_dur: float = REST_DURATION_S
			if maturity == MATURITY_SENESCENT:
				rest_dur *= 1.8
			if _mode_t >= rest_dur:
				current_mode = Mode.OPENING
				_mode_t = 0.0
		Mode.OPENING:
			_open_target = 1.0
			if _mode_t >= OPENING_DURATION_S:
				current_mode = Mode.FEEDING
				_mode_t = 0.0
				_feed_timer = 0.0
		Mode.FEEDING:
			_open_target = 1.0
			_feed_timer += dt
			if _feed_timer >= FEED_INTERVAL_S:
				_feed_timer = 0.0
				_try_consume_waste(waste_list, substrate)
			if _mode_t >= FEEDING_DURATION_S:
				current_mode = Mode.CLOSING
				_mode_t = 0.0
		Mode.CLOSING:
			_open_target = 0.0
			if _mode_t >= CLOSING_DURATION_S:
				current_mode = Mode.REST
				_mode_t = 0.0
	# Starvation / old age death. Drop a shell-fragment waste so the
	# detrital loop closes.
	if energy <= 0.0 or age >= max_age_s:
		_on_death()


# Smooth visual interpolation toward _open_target. Driven by _process so
# the hinge motion runs at frame rate even though the sim mode machine
# is at 10 Hz.
func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	# Throttle a touch with a per-instance phase so dozens of clams don't
	# all touch transforms on the same frame.
	_open_amount = lerpf(_open_amount, _open_target, clampf(dt * 4.0, 0.0, 1.0))
	if _shell_upper != null and is_instance_valid(_shell_upper):
		var pivot: Node3D = _shell_upper.get_parent() as Node3D
		if pivot != null:
			# Opens to ~32° at full feeding.
			pivot.rotation.x = -_open_amount * 0.56
	if _siphon != null and is_instance_valid(_siphon):
		_siphon.visible = _open_amount > 0.25
		# Siphon extends a quarter-voxel above shell rim during feeding.
		_siphon.position.y = _siphon_base_y + _open_amount * 0.10


func _try_consume_waste(waste_list: Array, substrate: SubstrateGrid) -> void:
	if waste_list == null or waste_list.is_empty():
		return
	# Find the closest waste particle inside our filter radius.
	var best: Node3D = null
	var best_d2: float = filter_radius * filter_radius
	var here: Vector3 = global_position
	# Babies have a smaller effective reach.
	if maturity == MATURITY_BABY:
		best_d2 *= 0.45
	for w in waste_list:
		if w == null or not is_instance_valid(w):
			continue
		var d2: float = (w.global_position - here).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = w
	if best == null:
		return
	if sim != null and sim.waste != null:
		sim.waste.erase(best)
	best.queue_free()
	energy = clampf(energy + FEED_ENERGY_GAIN, 0.0, 1.0)
	# Filtered organics return to the substrate as bound nutrients.
	if substrate != null:
		substrate.add_at(here, 0.05)


func _on_death() -> void:
	if _dead:
		return
	_dead = true
	# Drop a generic detrital waste particle (KIND_FISH = 0 reused as the
	# project-wide "neutral detritus" kind, same as Plant does).
	if sim != null and sim.has_method("_spawn_waste"):
		sim._spawn_waste(global_position + Vector3(0, 0.04, 0), 0.08, 0)
	queue_free()


# ---- Save / load ----

func to_save_dict() -> Dictionary:
	return {
		"id": id,
		"pos": SaveHelpers.vec3_to_array(global_position),
		"genome": {
			"shell_color": SaveHelpers.color_to_array(shell_color),
			"body_color": SaveHelpers.color_to_array(body_color),
			"siphon_color": SaveHelpers.color_to_array(siphon_color),
			"shell_size": shell_size,
			"max_age_s": max_age_s,
			"filter_radius": filter_radius,
			"generation": generation,
			"parent_lineage": parent_lineage,
			"clam_name": clam_name,
		},
		"age": age,
		"energy": energy,
		"maturity": int(maturity),
		"current_mode": int(current_mode),
		"mode_t": _mode_t,
	}


func apply_save_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	var g: Dictionary = d.get("genome", {})
	# Decode packed colors back to Color before re-init.
	var g_norm: Dictionary = g.duplicate()
	if g.has("shell_color"):
		g_norm["shell_color"] = SaveHelpers.array_to_color(g["shell_color"], shell_color)
	if g.has("body_color"):
		g_norm["body_color"] = SaveHelpers.array_to_color(g["body_color"], body_color)
	if g.has("siphon_color"):
		g_norm["siphon_color"] = SaveHelpers.array_to_color(g["siphon_color"], siphon_color)
	init_genome(g_norm)
	age = float(d.get("age", 0.0))
	energy = float(d.get("energy", 0.75))
	maturity = int(d.get("maturity", MATURITY_BABY))
	current_mode = int(d.get("current_mode", Mode.REST))
	_mode_t = float(d.get("mode_t", 0.0))
	scale = Vector3.ONE * (0.55 if maturity == MATURITY_BABY else 1.0)
