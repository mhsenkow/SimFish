extends SceneTree

# Pins the generative architecture contract for plants.
#
# Three things make a bed of one species read as grown rather than stamped:
#   * leaves are set around the stem by a real divergence angle, not a
#     `current_height % 2` flip between two planes;
#   * each individual carries its own phase, so neighbours do not align;
#   * leaf size answers the light the plant actually got, and its position
#     along the stem.
# Plus the growth mode that is not "get taller": an epiphyte creeps along
# its host.

const PlantScript := preload("res://scripts/plant.gd")


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	host.name = "PlantArchHost"
	root.add_child(host)

	# ---- Divergence angles ---------------------------------------------------
	var spiral: Plant = _make(host, {"leaf_form": "spade", "asymmetry_seed": 1234})
	_assert(failed, spiral.phyllotaxis == Plant.PHYLLO_SPIRAL,
		"stem plants default to the spiral (got %s)" % spiral.phyllotaxis)
	# Successive nodes must advance by the golden angle, never repeat a plane.
	var d0: float = _wrap(spiral._phyllotaxis_yaw(1) - spiral._phyllotaxis_yaw(0))
	var d1: float = _wrap(spiral._phyllotaxis_yaw(2) - spiral._phyllotaxis_yaw(1))
	_assert(failed, absf(d0 - d1) < 0.001, "spiral divergence is constant")
	_assert(failed, absf(absf(d0) - Plant.GOLDEN_ANGLE) < 0.01
			or absf(absf(d0) - (TAU - Plant.GOLDEN_ANGLE)) < 0.01,
		"spiral divergence is the golden angle (got %.3f)" % d0)
	# Over a stem's worth of nodes the spiral must not revisit a direction.
	var buckets: Dictionary = {}
	for n in 16:
		buckets[int(_wrap0(spiral._phyllotaxis_yaw(n)) / TAU * 12.0)] = true
	_assert(failed, buckets.size() >= 10,
		"16 spiral nodes spread around the stem (%d/12 sectors)" % buckets.size())

	var whorled: Plant = _make(host, {"leaf_form": "spade", "whorled_leaves": true,
		"whorl_count": 3, "asymmetry_seed": 99})
	_assert(failed, whorled.phyllotaxis == Plant.PHYLLO_WHORLED,
		"whorled_leaves selects the whorled arrangement")
	# Three leaves per node, evenly spaced.
	var w0: float = _wrap(whorled._phyllotaxis_yaw(1) - whorled._phyllotaxis_yaw(0))
	_assert(failed, absf(absf(w0) - TAU / 3.0) < 0.01,
		"whorl of 3 spaces leaves 120 degrees apart (got %.3f)" % w0)

	var ribbon: Plant = _make(host, {"leaf_form": "ribbon"})
	_assert(failed, ribbon.phyllotaxis == Plant.PHYLLO_DISTICHOUS,
		"ribbon (Vallisneria-like) is two-ranked")
	var r0: float = _wrap(ribbon._phyllotaxis_yaw(1) - ribbon._phyllotaxis_yaw(0))
	_assert(failed, absf(absf(r0) - PI) < 0.01, "distichous alternates 180 degrees")

	# An explicit genome value must win over the derivation.
	var forced: Plant = _make(host, {"leaf_form": "ribbon",
		"phyllotaxis": Plant.PHYLLO_DECUSSATE})
	_assert(failed, forced.phyllotaxis == Plant.PHYLLO_DECUSSATE,
		"explicit phyllotaxis overrides the derived default")
	# Decussate: opposite pairs, each pair a quarter turn on from the last.
	_assert(failed, absf(absf(_wrap(forced._phyllotaxis_yaw(1)
			- forced._phyllotaxis_yaw(0))) - PI) < 0.01, "decussate pairs are opposite")
	_assert(failed, absf(absf(_wrap(forced._phyllotaxis_yaw(2)
			- forced._phyllotaxis_yaw(0))) - PI * 0.5) < 0.01,
		"decussate rotates 90 degrees between pairs")

	# ---- Per-individual phase ------------------------------------------------
	var phases: Dictionary = {}
	for i in 40:
		var p: Plant = _make(host, {"leaf_form": "spade", "asymmetry_seed": 1000 + i * 37})
		phases[snappedf(p._phyllotaxis_phase(), 0.01)] = true
		# The lean direction must vary too — every plant used to bow along +X.
		p.free()
	_assert(failed, phases.size() >= 30,
		"individuals get distinct phases (%d/40 distinct)" % phases.size())
	var lean_a: Vector2 = spiral._lean_dir()
	var lean_b: Vector2 = whorled._lean_dir()
	_assert(failed, lean_a.distance_to(lean_b) > 0.05,
		"two plants lean in different directions")
	_assert(failed, absf(lean_a.length() - 1.0) < 0.001, "lean direction is a unit vector")

	# ---- Light plasticity ----------------------------------------------------
	var sun: Plant = _make(host, {"leaf_form": "spade"})
	sun._light_avg = 0.60
	var shade: Plant = _make(host, {"leaf_form": "spade"})
	shade._light_avg = 0.02
	_assert(failed, shade._shade_size_mult() > sun._shade_size_mult(),
		"shade leaves grow larger than sun leaves")
	_assert(failed, shade._shade_pitch() < sun._shade_pitch(),
		"shade leaves are held flatter")
	_assert(failed, is_equal_approx(sun._shade_size_mult(), 1.0),
		"full light leaves the leaf at its genome size")
	_assert(failed, shade._shade_size_mult() < 1.4, "shade response stays bounded")

	# ---- Size gradient along the stem ----------------------------------------
	var base_sz: float = sun._node_size_gradient(0.0)
	var mid_sz: float = sun._node_size_gradient(0.62)
	var tip_sz: float = sun._node_size_gradient(1.0)
	_assert(failed, mid_sz > base_sz and mid_sz > tip_sz,
		"largest leaves sit mid-stem (%.2f base / %.2f mid / %.2f tip)"
			% [base_sz, mid_sz, tip_sz])
	_assert(failed, base_sz > 0.5 and tip_sz > 0.5, "gradient never collapses a leaf")

	# ---- Node jitter is deterministic and small ------------------------------
	_assert(failed, is_equal_approx(spiral._node_jitter(5, 0.1), spiral._node_jitter(5, 0.1)),
		"node jitter is stable for a node")
	_assert(failed, not is_equal_approx(spiral._node_jitter(5, 0.1), spiral._node_jitter(6, 0.1)),
		"node jitter differs between nodes")
	_assert(failed, absf(spiral._node_jitter(5, 0.1)) <= 0.1001, "node jitter respects its bound")

	# ---- Leaf mosaic: twist toward the lamp ----------------------------------
	# With no light resolved (headless) the leaf keeps its divergence angle.
	_assert(failed, is_equal_approx(spiral._leaf_yaw(3, 0.0),
			spiral._phyllotaxis_yaw(3)),
		"no light source -> pure divergence angle")
	# With a lamp, every leaf turns part-way toward it but the arrangement
	# must survive: nodes still differ from one another.
	spiral._light_yaw_cache = 1.0
	var y3: float = spiral._leaf_yaw(3, 0.0)
	var y4: float = spiral._leaf_yaw(4, 0.0)
	_assert(failed, not is_equal_approx(y3, spiral._phyllotaxis_yaw(3)),
		"a lamp twists the leaf off its divergence angle")
	_assert(failed, absf(_wrap(y3 - y4)) > 0.5,
		"the twist does not collapse the arrangement into one plane")
	# The twist must be partial, never a full snap to the lamp.
	_assert(failed, absf(_wrap(y3 - 1.0)) > 0.2,
		"leaves lean toward the light rather than all facing it")
	spiral._light_yaw_cache = NAN

	# ---- Epiphytes creep instead of climbing ---------------------------------
	var epi: Plant = _make(host, {"leaf_form": "paddle", "is_epiphyte": true,
		"max_height": 9, "asymmetry_seed": 20260909})
	var seg0: int = epi._rhizome_segments
	_assert(failed, seg0 > 0, "epiphyte builds a rhizome at spawn")
	var attach0: int = epi._rhizome_attach_points.size()
	for i in 12:
		epi._grow_one()
	_assert(failed, epi._rhizome_segments > seg0,
		"growth extends the rhizome along the host (%d -> %d)" % [seg0, epi._rhizome_segments])
	_assert(failed, epi._rhizome_attach_points.size() > attach0,
		"new rhizome segments become leaf attachment points")
	# The runner must curve, not march in a straight line.
	var pts: PackedVector3Array = epi._rhizome_attach_points
	if pts.size() >= 3:
		var a: Vector3 = (pts[1] - pts[0]).normalized()
		var b: Vector3 = (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		_assert(failed, a.dot(b) < 0.9999, "the rhizome curves as it creeps")
	# The curl must be guaranteed for EVERY seed, not just lucky ones — a
	# symmetric jitter alone used to land on ~0 and draw a straight runner.
	var straightest: float = 999.0
	for i in 200:
		var e2: Plant = _make(host, {"leaf_form": "paddle", "is_epiphyte": true,
			"max_height": 6, "asymmetry_seed": 77 + i * 1013})
		straightest = minf(straightest, absf(e2._rhizome_curl()))
		e2.free()
	_assert(failed, straightest >= Plant.RHIZOME_CURL_MIN - 0.0001,
		"every individual curls at least the minimum (worst %.4f)" % straightest)
	# And it must stop somewhere.
	for i in 200:
		epi._extend_rhizome()
	_assert(failed, epi._rhizome_segments <= Plant.RHIZOME_MAX_SEGMENTS,
		"rhizome length is capped")

	# ---- Column form: tapered, wandering, individually leaning ---------------
	# _recalc_height() reads the node index back out of local_y / VOXEL_SIZE,
	# so the column's Y spacing must stay exactly one voxel per node however
	# much its X/Z wander.
	var col: Plant = _make(host, {"leaf_form": "column", "max_height": 12,
		"asymmetry_seed": 4242})
	for i in 8:
		col._grow_one()
	var ys: Array[float] = []
	var xs: Dictionary = {}
	var widths: Dictionary = {}
	for h in col.voxels:
		if h == null or not h.alive:
			continue
		ys.append(h.local_pos.y)
		xs[snappedf(h.local_pos.x, 0.005)] = true
		widths[snappedf(h.transform.basis.x.length(), 0.005)] = true
	ys.sort()
	var spacing_ok: bool = true
	for i in range(1, ys.size()):
		if absf((ys[i] - ys[i - 1]) - Plant.VOXEL_SIZE) > 0.001:
			spacing_ok = false
	_assert(failed, ys.size() >= 6 and spacing_ok,
		"column keeps exactly one voxel of Y per node (recalc_height depends on it)")
	_assert(failed, xs.size() >= 4,
		"column wanders instead of stacking on one axis (%d distinct x)" % xs.size())
	_assert(failed, widths.size() >= 2,
		"column tapers toward the tip (%d thickness steps)" % widths.size())
	_assert(failed, widths.size() <= 4,
		"taper is quantised so the box-mesh cache stays small")

	# ---- Inheritance ---------------------------------------------------------
	var g: Dictionary = PlantGenome.from_plant(spiral)
	_assert(failed, g.has("phyllotaxis") and g.has("whorl_count"),
		"arrangement round-trips through the genome")
	var kid: Dictionary = PlantGenome.duplicate_mutate(g, 1)
	_assert(failed, int(kid.asymmetry_seed) != int(g.asymmetry_seed),
		"offspring get their own asymmetry phase, not a clone of the parent's")
	# Constants must agree across the two files that hold them.
	_assert(failed, PlantGenome.DEFAULTS_PHYLLO_SPIRAL == Plant.PHYLLO_SPIRAL
			and PlantGenome.DEFAULTS_PHYLLO_WHORLED == Plant.PHYLLO_WHORLED
			and PlantGenome.DEFAULTS_PHYLLO_DISTICHOUS == Plant.PHYLLO_DISTICHOUS
			and PlantGenome.DEFAULTS_PHYLLO_DECUSSATE == Plant.PHYLLO_DECUSSATE,
		"PlantGenome and Plant agree on the arrangement names")

	# ---- Habit flowering gates + sway personality (#29/#33/#41) --------------
	var carpet: Plant = _make(host, {"leaf_form": "needle", "is_carpet": true})
	_assert(failed, not carpet.uses_flowering,
		"carpets stay leafy (no tip flowering)")
	carpet._begin_flowering()
	_assert(failed, carpet.flower_stage == Plant.FlowerStage.NONE,
		"_begin_flowering respects uses_flowering=false")

	var crypt: Plant = _make(host, {"leaf_form": "paddle"})
	_assert(failed, crypt.uses_flowering and not crypt.emergent_growth,
		"crypts/swords flower as spathes, not emergents")
	_assert(failed, crypt._resolve_flower_silhouette() == "crypt",
		"paddle silhouette is crypt spathe")

	var stem: Plant = _make(host, {"leaf_form": "lance", "max_height": 12})
	_assert(failed, stem._resolve_flower_silhouette() == "crypt",
		"stem blooms stay small spathe, not tip daisy")

	var cattail: Plant = _make(host, {"leaf_form": "ribbon", "species_id": "cattail"})
	_assert(failed, cattail._resolve_flower_silhouette() == "spike",
		"cattail silhouette is spike")

	# Sway personality spreads by habit — swords calmer tip mult than ribbons.
	var sword: Plant = _make(host, {"leaf_form": "paddle", "sway_amplitude": 0.25})
	var ribbon_p: Plant = _make(host, {"leaf_form": "ribbon", "sway_amplitude": 0.25,
		"max_height": 14})
	sword._ensure_foliage_batch()
	ribbon_p._ensure_foliage_batch()
	sword._apply_sway_personality()
	ribbon_p._apply_sway_personality()
	var sword_tip: float = float(sword._foliage_mat.get_shader_parameter("tip_sway_mult"))
	var ribbon_tip: float = float(ribbon_p._foliage_mat.get_shader_parameter("tip_sway_mult"))
	_assert(failed, ribbon_tip > sword_tip,
		"ribbon tip sway exceeds stiff sword (%.2f vs %.2f)" % [ribbon_tip, sword_tip])
	var carpet2: Plant = _make(host, {"leaf_form": "needle", "is_carpet": true})
	carpet2._ensure_foliage_batch()
	carpet2._apply_sway_personality()
	var carpet_flutter: float = float(carpet2._foliage_mat.get_shader_parameter("flutter_amplitude"))
	var carpet_speed: float = float(carpet2._foliage_mat.get_shader_parameter("flutter_speed"))
	_assert(failed, carpet_flutter > 0.02 and carpet_speed >= 3.5,
		"carpets get lawn shimmer (flutter %.3f @ %.1f)" % [carpet_flutter, carpet_speed])

	# Flower mats are calm — buds must not use full foliage sway.
	var bud_nodes: Array = LeafShapes.build_bud(Color8(80, 140, 70))
	_assert(failed, not bud_nodes.is_empty(), "bud builds voxels")
	var bud_mat: ShaderMaterial = (bud_nodes[0] as MeshInstance3D).material_override as ShaderMaterial
	_assert(failed, bud_mat != null, "bud has a shader material")
	var bud_amp: float = float(bud_mat.get_shader_parameter("sway_amplitude"))
	_assert(failed, bud_amp <= 0.0001,
		"bud flower mat has zero sway (got %.3f)" % bud_amp)
	_assert(failed, float(bud_mat.get_shader_parameter("motion_lock")) > 0.5,
		"bud flower mat locks vertex motion")
	for n in bud_nodes:
		if is_instance_valid(n):
			(n as Node).free()

	# Tip bloom snaps onto the real stem tip (not the plant origin axis).
	var tip_plant: Plant = _make(host, {"leaf_form": "column", "max_height": 10,
		"asymmetry_seed": 4242})
	for i in 6:
		tip_plant._grow_one()
	tip_plant._health_smooth = 1.0
	tip_plant.uses_flowering = true
	tip_plant._begin_flowering()
	_assert(failed, tip_plant._flower_node != null and is_instance_valid(tip_plant._flower_node),
		"flower node exists after begin")
	var expected: Vector3 = tip_plant._tip_bloom_local_pos()
	tip_plant._stabilize_flower_against_lean()
	_assert(failed, tip_plant._flower_node.position.distance_to(expected) < 0.001,
		"flower snaps to tip bloom local pos")
	_assert(failed, tip_plant._flower_node.position.length() > 0.01
			or tip_plant.voxels.is_empty(),
		"tip bloom leaves the origin when the stem has wandered")
	# Compact open flower — petals stay near the pistil.
	var open_nodes: Array = LeafShapes.build_flower(Color8(230, 130, 200), Color8(245, 220, 90), 5, 1.0)
	var max_spread: float = 0.0
	for n2 in open_nodes:
		if n2 is Node3D and is_instance_valid(n2):
			max_spread = maxf(max_spread, Vector2((n2 as Node3D).position.x, (n2 as Node3D).position.z).length())
	_assert(failed, max_spread <= Plant.VOXEL_SIZE * 0.45,
		"open flower petals hug the tip (spread %.3f)" % max_spread)
	for n3 in open_nodes:
		if is_instance_valid(n3):
			(n3 as Node).free()

	if failed.is_empty():
		print("[smoke] plant_architecture OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] plant_architecture FAILED (%d)" % failed.size())
		quit(1)


func _make(host: Node3D, params: Dictionary) -> Plant:
	var p: Plant = PlantScript.new()
	host.add_child(p)
	p.init(1, params)
	return p


# Signed angle in (-PI, PI].
func _wrap(a: float) -> float:
	return wrapf(a, -PI, PI)


# Unsigned angle in [0, TAU).
func _wrap0(a: float) -> float:
	return fposmod(a, TAU)


func _assert(failed: Array[String], cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
