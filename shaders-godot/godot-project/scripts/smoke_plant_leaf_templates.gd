extends SceneTree

# PLANT_SYSTEMS_50 #23 — data-only leaf template cache.
#
# The contract this pins:
#   * a template is immutable data (transform / box size / color recipe), so
#     a repeated equivalent leaf build hits the cache instead of allocating a
#     throwaway MeshInstance3D tree;
#   * the cache key covers every geometry-affecting input, and quantizes the
#     continuous ones so a bed of plants can't mint an unbounded number of
#     entries;
#   * per-leaf color variation is NOT cached — variegation still rolls per
#     individual at bake time;
#   * a plant baking through the template path lands the same handle count
#     and the same instance transforms as the old node-builder path.

const PlantScript := preload("res://scripts/plant.gd")

const RAMP: Array = [
	Color8(28, 48, 24), Color8(40, 70, 32), Color8(56, 96, 44),
	Color8(74, 122, 56), Color8(96, 148, 68), Color8(122, 174, 84),
]

# Voxel count each form yields at the parameters in _params_for(), measured
# against the pre-template node builders.
const EXPECTED_VOXELS := {
	"paddle": 9, "ribbon": 9, "lance": 6, "needle": 5, "oval": 8,
	"lobed": 14, "spade": 14, "cordate": 22, "pinnate": 27,
	"fingered": 13, "four_leaf": 5,
}


func _initialize() -> void:
	await process_frame
	var failed: Array[String] = []
	var host := Node3D.new()
	host.name = "LeafTemplateHost"
	root.add_child(host)

	# ---- Repeated equivalent builds hit the cache ---------------------------
	LeafShapes.reset_template_cache()
	var first: Array = LeafShapes.get_leaf_template("spade", {
		"length": 5, "width": 3, "quilted": false, "wavy": false})
	var again: Array = LeafShapes.get_leaf_template("spade", {
		"length": 5, "width": 3, "quilted": false, "wavy": false})
	_assert(failed, not first.is_empty(), "spade template builds voxels")
	_assert(failed, first == again, "an equivalent request returns the same Array")
	var stats: Dictionary = LeafShapes.template_cache_stats()
	_assert(failed, int(stats.misses) == 1 and int(stats.hits) == 1,
		"second equivalent build is a hit (%d miss / %d hit)"
			% [int(stats.misses), int(stats.hits)])
	# A geometry-affecting input must key a distinct entry.
	LeafShapes.get_leaf_template("spade", {
		"length": 6, "width": 3, "quilted": false, "wavy": false})
	LeafShapes.get_leaf_template("spade", {
		"length": 5, "width": 3, "quilted": true, "wavy": false})
	LeafShapes.get_leaf_template("spade", {
		"length": 5, "width": 3, "quilted": false, "wavy": true})
	_assert(failed, int(LeafShapes.template_cache_stats().size) == 4,
		"length / quilted / wavy each key their own template (%d entries)"
			% int(LeafShapes.template_cache_stats().size))

	# ---- Continuous inputs quantize instead of exploding --------------------
	LeafShapes.reset_template_cache()
	for i in 500:
		LeafShapes.get_leaf_template("ribbon", {
			"length": 8, "sway_seed": randf() * TAU, "wavy": false})
	var ribbon_stats: Dictionary = LeafShapes.template_cache_stats()
	_assert(failed, int(ribbon_stats.size) <= LeafShapes.TEMPLATE_SWAY_BUCKETS,
		"500 random sway seeds fold into at most %d buckets (got %d)"
			% [LeafShapes.TEMPLATE_SWAY_BUCKETS, int(ribbon_stats.size)])
	_assert(failed, int(ribbon_stats.hits) > 400,
		"most of those 500 builds are cache hits (%d)" % int(ribbon_stats.hits))
	# Out-of-range integers clamp rather than key an entry per value.
	var huge: Dictionary = LeafShapes.normalize_template_params(
		"paddle", {"length": 9999, "width": 9999, "flatten": 12.0})
	_assert(failed, int(huge.length) == LeafShapes.TEMPLATE_MAX_LENGTH
			and int(huge.width) == LeafShapes.TEMPLATE_MAX_WIDTH
			and float(huge.flatten) <= 1.0,
		"absurd dimensions clamp onto the grid")

	# ---- The cache stays bounded --------------------------------------------
	LeafShapes.reset_template_cache()
	for i in LeafShapes.TEMPLATE_CACHE_LIMIT * 2:
		LeafShapes.get_leaf_template("paddle", {
			"length": 1 + i % LeafShapes.TEMPLATE_MAX_LENGTH,
			"width": 1 + int(i / 24.0) % LeafShapes.TEMPLATE_MAX_WIDTH,
			"flatten": 0.05 + float(i % 19) * 0.05,
			"quilted": i % 2 == 0, "wavy": i % 3 == 0})
	var bounded: Dictionary = LeafShapes.template_cache_stats()
	_assert(failed, int(bounded.size) <= LeafShapes.TEMPLATE_CACHE_LIMIT,
		"cache never exceeds its limit (%d/%d)"
			% [int(bounded.size), LeafShapes.TEMPLATE_CACHE_LIMIT])
	_assert(failed, int(bounded.evictions) > 0, "the limit actually evicts")
	_assert(failed, int(bounded.voxels) > 0, "stats report resident voxel count")
	LeafShapes.reset_template_cache()
	var cleared: Dictionary = LeafShapes.template_cache_stats()
	_assert(failed, int(cleared.size) == 0 and int(cleared.hits) == 0
			and int(cleared.misses) == 0 and int(cleared.voxels) == 0,
		"reset clears entries and metrics")

	# ---- Templates are data, not nodes --------------------------------------
	var tpl: Array = LeafShapes.get_leaf_template("pinnate",
		{"length": 5, "quilted": false})
	var all_data: bool = true
	for v in tpl:
		if v is Node or not (v is LeafShapes.LeafVoxel):
			all_data = false
	_assert(failed, all_data and not tpl.is_empty(),
		"pinnate template holds LeafVoxel data, never Nodes")
	var v0: LeafShapes.LeafVoxel = tpl[0]
	_assert(failed, v0.size.length() > 0.0
			and v0.xform.basis.is_equal_approx(Basis()),
		"a descriptor carries box dimensions and a local transform")
	_assert(failed, v0.base_color(RAMP, 0.5, {}).a > 0.0,
		"a descriptor resolves a material base color")

	# ---- Per-leaf color variation is not baked into the cache ---------------
	var varieg_mods: Dictionary = {"variegation": 0.9}
	var seen: Dictionary = {}
	for i in 24:
		seen[str(tpl[1].base_color(RAMP, 0.4, varieg_mods).to_html())] = true
	_assert(failed, seen.size() > 1,
		"variegation still rolls per bake off a shared template (%d colors)"
			% seen.size())
	_assert(failed, tpl[1].base_color(RAMP, 0.1, {})
			!= tpl[1].base_color(RAMP, 0.9, {}),
		"leaf age still drives color off a shared template")

	# ---- Template path == node path, per representative form ----------------
	# EXPECTED_VOXELS pins the silhouette of each form at the parameters in
	# _params_for(), so a template rewrite can't quietly drop or duplicate
	# voxels while both bake paths agree with each other.
	for form in EXPECTED_VOXELS:
		_check_form_parity(failed, host, form)
		var tpl_form: Array = LeafShapes.get_leaf_template(form, _params_for(form))
		_assert(failed, tpl_form.size() == int(EXPECTED_VOXELS[form]),
			"%s template holds %d voxels (got %d)"
				% [form, int(EXPECTED_VOXELS[form]), tpl_form.size()])

	# ---- A grown plant baked through templates behaves ----------------------
	for form in ["paddle", "ribbon", "lance", "needle", "spade", "cordate",
			"pinnate", "fingered", "oval", "lobed"]:
		var p: Plant = _make(host, {"leaf_form": form, "max_height": 10,
			"asymmetry_seed": 8123})
		for i in 8:
			p._grow_one()
		var groups: int = 0
		var handles: int = 0
		for g in p._leaf_groups:
			groups += 1
			for h in g:
				handles += 1
				if h == null or not (h as VoxelBatch.Handle).transform.is_finite():
					handles = -99999
		_assert(failed, groups > 0 and handles > 0,
			"%s bakes finite leaf handles through the template path (%d/%d)"
				% [form, groups, handles])
		p.free()

	if failed.is_empty():
		print("[smoke] plant_leaf_templates OK")
		quit(0)
	else:
		for f in failed:
			push_error("[smoke] FAIL: %s" % f)
		print("[smoke] plant_leaf_templates FAILED (%d)" % failed.size())
		quit(1)


# Bake one leaf twice into the same plant — once from the shared template,
# once from the public node builder — and require identical handle counts and
# instance transforms. Colors are compared loosely: the node path reads its
# albedo back out of VoxelMat's snapped material cache, so it lands within one
# cache-quantization step of the template path's exact boosted color.
func _check_form_parity(failed: Array[String], host: Node3D, form: String) -> void:
	var p: Plant = _make(host, {"leaf_form": "column", "max_height": 8})
	var mods: Dictionary = {"variegation": 0.0, "quilted": true, "wavy": true,
		"tone_under": Color8(90, 60, 40), "iridescence": 0.3}
	var age: float = 0.42
	var holder := Node3D.new()
	holder.position = Vector3(0.4, 1.1, -0.3)
	holder.rotation = Vector3(0.2, 1.1, 0.0)

	var params: Dictionary = _params_for(form)
	var tpl: Array = LeafShapes.get_leaf_template(form, params)
	var from_tpl: Array = p._bake_leaf_template(
		holder.transform, tpl, RAMP, age, mods)
	var from_nodes: Array = p._bake_leaf(holder, _nodes_for(form, params, age, mods))

	var ok: bool = from_tpl.size() == from_nodes.size() and not from_tpl.is_empty()
	if not ok:
		failed.append("%s: handle count matches (%d template / %d node)"
			% [form, from_tpl.size(), from_nodes.size()])
	else:
		var worst_pos: float = 0.0
		var worst_basis: float = 0.0
		var worst_col: float = 0.0
		for i in from_tpl.size():
			var a: VoxelBatch.Handle = from_tpl[i]
			var b: VoxelBatch.Handle = from_nodes[i]
			worst_pos = maxf(worst_pos, a.transform.origin.distance_to(b.transform.origin))
			for axis in 3:
				worst_basis = maxf(worst_basis,
					(a.transform.basis[axis] - b.transform.basis[axis]).length())
			worst_col = maxf(worst_col, maxf(absf(a.base_color.r - b.base_color.r),
				maxf(absf(a.base_color.g - b.base_color.g),
					absf(a.base_color.b - b.base_color.b))))
		if worst_pos > 0.0001:
			failed.append("%s: instance origins match (worst %.5f)" % [form, worst_pos])
		if worst_basis > 0.0001:
			failed.append("%s: instance scale/rotation matches (worst %.5f)"
				% [form, worst_basis])
		if worst_col > 0.05:
			failed.append("%s: base colors agree within the material cache snap"
				% form + " (worst %.3f)" % worst_col)
	holder.free()
	p.free()


# Geometry parameters per form, deliberately chosen to be already on the
# cache grid so the node path can be built from the very same numbers.
func _params_for(form: String) -> Dictionary:
	var p: Dictionary = {}
	match form:
		"paddle":
			p = {"length": 5, "width": 3, "flatten": 0.5,
				"quilted": true, "wavy": true}
		"ribbon":
			p = {"length": 9, "sway_seed": TAU / 24.0 * 7.0, "wavy": true}
		"lance":
			p = {"pair_index": 1}
		"needle":
			p = {"length": 5}
		"lobed":
			p = {"length": 6}
		"spade":
			p = {"length": 6, "width": 3, "quilted": true, "wavy": true}
		"cordate":
			p = {"quilted": true, "wavy": true}
		"pinnate":
			p = {"length": 5, "quilted": true}
		"fingered":
			p = {"length": 7, "fingers": 3, "quilted": true}
	return p


func _nodes_for(form: String, params: Dictionary, age: float,
		mods: Dictionary) -> Array:
	var nodes: Array = []
	match form:
		"paddle":
			nodes = LeafShapes.build_paddle(params.length, RAMP, age,
				params.width, params.flatten, mods)
		"ribbon":
			nodes = LeafShapes.build_ribbon(params.length, RAMP, age,
				params.sway_seed, mods)
		"lance":
			nodes = LeafShapes.build_lance_pair(RAMP, age, params.pair_index, mods)
		"needle":
			nodes = LeafShapes.build_needle(params.length, RAMP, age)
		"oval":
			nodes = LeafShapes.build_oval(RAMP, age)
		"lobed":
			nodes = LeafShapes.build_lobed(params.length, RAMP, age)
		"spade":
			nodes = LeafShapes.build_spade(RAMP, age, params.length,
				params.width, mods)
		"cordate":
			nodes = LeafShapes.build_cordate(RAMP, age, mods)
		"pinnate":
			nodes = LeafShapes.build_pinnate(params.length, RAMP, age, mods)
		"fingered":
			nodes = LeafShapes.build_fingered(params.length, RAMP, age,
				params.fingers, mods)
		"four_leaf":
			nodes = LeafShapes.build_four_leaf(RAMP, age, mods)
	return nodes


func _make(host: Node3D, params: Dictionary) -> Plant:
	var p: Plant = PlantScript.new()
	host.add_child(p)
	p.init(1, params)
	return p


func _assert(failed: Array[String], cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
