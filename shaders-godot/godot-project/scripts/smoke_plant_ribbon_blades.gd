extends SceneTree

# Pins the Vallisneria ribbon-blade contract (Plant._ribbon_blade_segments):
#   * a crown holds a handful of long blades, not one stub per growth step;
#   * a full-size blade is at least two voxels wide at the base, tapers to a
#     narrower tip, twists along its length and is lighter at the tip;
#   * a plant that has reached the surface bends its blades over and lays
#     them along the water, never above it;
#   * growth lengthens blades in place (handles reused) and biomass is still
#     current_height;
#   * the blades survive a save round-trip and old saves regrow them.

const PlantScript := preload("res://scripts/plant.gd")
const V: float = Plant.VOXEL_SIZE
const WATER_Y: float = 6.5


func _initialize() -> void:
	await process_frame
	var t := TestSupport.Suite.new("smoke_plant_ribbon_blades")
	var host := Node3D.new()
	host.name = "RibbonBladeHost"
	root.add_child(host)

	_check_mature_crown(t, host)
	_check_surface_trail(t, host)
	_check_growth_in_place(t, host)
	_check_dwarf_scale(t, host)
	_check_save_round_trip(t, host)

	host.queue_free()
	await process_frame
	quit(t.finish())


func _reach(p: Plant) -> int:
	return PlantEstablish.surface_reach_voxels(p.global_position.y, WATER_Y, V)


func _make(host: Node3D, height: int, params: Dictionary = {}) -> Plant:
	var p: Plant = PlantScript.new()
	host.add_child(p)
	var merged: Dictionary = {"leaf_form": "ribbon", "max_height": 34,
		"leaf_length": 8, "asymmetry_seed": 9191, "sway_amplitude": 0.22,
		"surface_pooling": true}
	merged.merge(params, true)
	p.water_surface_y = WATER_Y
	p.init(height, merged)
	return p


# Booked blade groups (the ribbon path tags each leaf state with rb_seed).
func _blades(p: Plant) -> Array:
	var out: Array = []
	for i in mini(p._leaf_groups.size(), p._leaf_states.size()):
		if (p._leaf_states[i] as Dictionary).has("rb_seed"):
			out.append(p._leaf_groups[i])
	return out


func _width(h: VoxelBatch.Handle) -> float:
	return h.transform.basis.x.length()


func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11


func _check_mature_crown(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, 21)
	var blades: Array = _blades(p)
	t.in_range(float(blades.size()), 8.0, float(Plant.RIBBON_MAX_BLADES),
		"a mature crown is many blades, but not one per growth step")
	t.check(blades.size() < p.current_height,
		"blade count (%d) is far below the step count (%d)" % [blades.size(), p.current_height])
	var finite: bool = true
	var widest_base: float = 0.0
	var tapers: bool = true
	var lighter_tip: bool = true
	var lengths: Dictionary = {}
	var twist_deg: float = 0.0
	var parallel: bool = true
	var fan_half: float = 0.0
	var lum_lo: float = INF
	var lum_hi: float = -INF
	var surface_local: float = WATER_Y - p.global_position.y - V
	for g in blades:
		var grp: Array = g
		lengths[grp.size()] = true
		for hv in grp:
			if not (hv as VoxelBatch.Handle).transform.is_finite():
				finite = false
		for hv in grp:
			var hs: VoxelBatch.Handle = hv
			if hs.transform.basis.y.normalized().y > 0.8 and hs.local_pos.y < surface_local:
				fan_half = maxf(fan_half, Vector2(hs.local_pos.x, hs.local_pos.z).length())
		if grp.size() < 4:
			continue
		var base: VoxelBatch.Handle = grp[1]
		var mid: VoxelBatch.Handle = grp[int(float(grp.size()) * 0.5)]
		if grp.size() >= 6 and _width(mid) < _width(base) * 0.8:
			parallel = false
		lum_lo = minf(lum_lo, _lum(mid.base_color))
		lum_hi = maxf(lum_hi, _lum(mid.base_color))
		var tip: VoxelBatch.Handle = grp[grp.size() - 1]
		widest_base = maxf(widest_base, _width(base))
		if _width(tip) >= _width(base) * 0.8:
			tapers = false
		if _lum(tip.base_color) <= _lum(base.base_color):
			lighter_tip = false
		# Twist: the width axis turns about the blade while it rises.
		var w0: Vector3 = base.transform.basis.x.normalized()
		for k in range(2, grp.size()):
			var hk: VoxelBatch.Handle = grp[k]
			if hk.transform.basis.y.normalized().y < 0.8:
				break
			twist_deg = maxf(twist_deg, rad_to_deg(w0.angle_to(hk.transform.basis.x.normalized())))
	t.check(finite, "every blade segment has a finite transform")
	t.in_range(widest_base, 0.4 * V, 1.15 * V,
		"a full-size blade is a narrow strap, not a paper sheet")
	t.check(parallel, "blades stay near-parallel to mid-length")
	t.check(fan_half < 1.3, "blades stand upright, not a splayed fan (half-width %.2f)" % fan_half)
	t.check(lum_hi - lum_lo > 0.06,
		"neighbouring blades carry their own tone (lum spread %.3f)" % (lum_hi - lum_lo))
	t.check(tapers, "blades taper to a narrower tip")
	t.check(lighter_tip, "blade colour lightens from the crown to the tip")
	t.check(twist_deg > 20.0, "blades twist along their length (%.1f deg)" % twist_deg)
	t.check(lengths.size() >= 2, "blade lengths vary within a crown (%d distinct)" % lengths.size())
	t.equals(p.biomass(), p.current_height, "biomass is still current_height")
	t.check(p.voxels.is_empty(), "ribbon crown grows no stem voxels")
	# Aufwuchs on a crown with no stem voxels is painted into the blade.
	for i in mini(p._leaf_groups.size(), p._leaf_states.size()):
		var st: Dictionary = p._leaf_states[i]
		if not st.has("rb_seed") or (p._leaf_groups[i] as Array).size() < 2:
			continue
		st["hair"] = 0.8
		p._paint_ribbon_aufwuchs()
		var hh: VoxelBatch.Handle = (p._leaf_groups[i] as Array)[1]
		t.check(hh.batch._colors[hh.index].a < 0.7,
			"an aufwuchs load paints into the blade (alpha %.2f)" % hh.batch._colors[hh.index].a)
		p._graze_leaf_biofilm(p._leaf_states.size())
		t.check(float(st.get("hair", 1.0)) < 0.8, "grazing strips aufwuchs off a blade")
		break
	p.free()


func _check_surface_trail(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, 1)
	var reach: int = _reach(p)
	var guard: int = 0
	while p._grow_one() and guard < 80:
		guard += 1
	t.check(p._at_surface_cap(), "the crown grew until the ecology says it reached the surface")
	var surface_local: float = WATER_Y - p.global_position.y
	var above: int = 0
	var trailing: int = 0
	var longest_run: float = 0.0
	for g in _blades(p):
		var grp: Array = g
		var first_flat := Vector3.INF
		var last_flat := Vector3.INF
		for hv in grp:
			var h: VoxelBatch.Handle = hv
			if h.local_pos.y > surface_local + 0.01:
				above += 1
			var axis: Vector3 = h.transform.basis.y.normalized()
			if absf(axis.y) < 0.35 and h.local_pos.y > surface_local - V:
				trailing += 1
				if first_flat == Vector3.INF:
					first_flat = h.local_pos
				last_flat = h.local_pos
		if first_flat != Vector3.INF:
			longest_run = maxf(longest_run, Vector2(first_flat.x, first_flat.z).distance_to(
				Vector2(last_flat.x, last_flat.z)))
	t.equals(above, 0, "no blade segment pokes above the waterline")
	t.check(trailing >= 6, "blades bend over and lie along the surface (%d flat segments)" % trailing)
	t.check(longest_run > V * 3.0, "the surface run trails well away from the crown (%.2f)" % longest_run)
	# Flat on the water: the ribbon's broad face turns up once it lies there.
	var flat_faces: int = 0
	for g in _blades(p):
		for hv in g:
			var h: VoxelBatch.Handle = hv
			if absf(h.transform.basis.y.normalized().y) < 0.2 \
					and absf(h.transform.basis.z.normalized().y) > 0.8:
				flat_faces += 1
	t.check(flat_faces >= 3, "floating ribbon lies flat, face up (%d)" % flat_faces)
	t.check(p.current_height <= reach + 1, "the surface run is geometry, not extra growth (h=%d reach=%d)"
		% [p.current_height, reach])
	# Entering the canopy must not float detached break cubes over the crown.
	var h_before: int = p.current_height
	p._enter_canopy()
	t.check(p.voxels.is_empty(), "canopy entry adds no floating meniscus cubes to a ribbon crown")
	t.check(p.current_height >= h_before, "canopy entry keeps the growth it always booked")
	p.free()


func _check_growth_in_place(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, 6)
	var before: int = 0
	for g in _blades(p):
		before = maxi(before, (g as Array).size())
	var t0: int = Time.get_ticks_usec()
	for _i in 6:
		p._grow_one()
	var per_step_ms: float = float(Time.get_ticks_usec() - t0) / 6000.0
	var after: int = 0
	var live: int = 0
	for g in _blades(p):
		after = maxi(after, (g as Array).size())
		live += (g as Array).size()
	t.check(after > before, "growth lengthens the blades (%d -> %d segments)" % [before, after])
	var slots: int = p._foliage_batch._count
	t.check(slots <= live + 8,
		"re-laying reuses handles instead of minting new ones (%d slots for %d live)" % [slots, live])
	t.check(per_step_ms < 25.0, "one ribbon growth step stays cheap (%.2f ms)" % per_step_ms)
	t.equals(p.biomass(), p.current_height, "biomass tracks growth steps as before")
	# A nibbled blade keeps its state and regrows on the next step.
	var n_groups: int = p._leaf_groups.size()
	p._take_youngest_leaf_voxel()
	p._grow_one()
	t.equals(p._leaf_groups.size(), n_groups, "a bite does not multiply blades")
	p.free()


func _check_dwarf_scale(t: TestSupport.Suite, host: Node3D) -> void:
	# Crypt parva / dwarf sag use the ribbon form at a few voxels tall.
	var p: Plant = _make(host, 3, {"max_height": 4, "leaf_length": 3,
		"surface_pooling": false})
	var blades: Array = _blades(p)
	t.check(blades.size() >= 1 and blades.size() <= 3, "a dwarf ribbon has 1-3 blades (%d)" % blades.size())
	var widest: float = 0.0
	var top: float = 0.0
	for g in blades:
		for hv in g:
			var h: VoxelBatch.Handle = hv
			widest = maxf(widest, _width(h))
			top = maxf(top, h.local_pos.y)
	t.check(widest < 2.0 * V * 0.9, "a dwarf blade stays narrow at its scale (%.3f)" % widest)
	t.check(top < WATER_Y - 2.0, "a dwarf ribbon stays down in the foreground (%.2f)" % top)
	p.free()


func _signature(p: Plant) -> Array:
	var sig: Array = []
	for g in _blades(p):
		var grp: Array = g
		sig.append([grp.size(), (grp[grp.size() - 1] as VoxelBatch.Handle).local_pos])
	return sig


func _check_save_round_trip(t: TestSupport.Suite, host: Node3D) -> void:
	var p: Plant = _make(host, 14)
	for _i in 4:
		p._grow_one()
	var d: Dictionary = p.to_save_dict()
	var p2: Plant = PlantScript.new()
	host.add_child(p2)
	p2.apply_save_dict(d)
	var a: Array = _signature(p)
	var b: Array = _signature(p2)
	t.equals(b.size(), a.size(), "blade count survives reload")
	var max_err: float = 0.0
	var same_len: bool = true
	for i in mini(a.size(), b.size()):
		if int(a[i][0]) != int(b[i][0]):
			same_len = false
		max_err = maxf(max_err, (a[i][1] as Vector3).distance_to(b[i][1] as Vector3))
	t.check(same_len, "each blade reloads at its saved length")
	t.check(max_err < 0.01, "reloaded blade tips land where they were (max err %.4f)" % max_err)
	t.equals(p2.biomass(), p.biomass(), "biomass survives reload")
	# An old save carries nothing ribbon-specific: blades regrow from height.
	var legacy: Dictionary = {"subclass": "plant", "current_height": 17,
		"water_surface_y": WATER_Y, "init_params": {"leaf_form": "ribbon",
			"max_height": 34, "leaf_length": 8, "asymmetry_seed": 77}}
	var p3: Plant = PlantScript.new()
	host.add_child(p3)
	p3.apply_save_dict(legacy)
	t.check(_blades(p3).size() >= 4, "an old save regrows a crown of ribbon blades (%d)" % _blades(p3).size())
	t.equals(p3.biomass(), 17, "old-save biomass preserved")
	p.free()
	p2.free()
	p3.free()
