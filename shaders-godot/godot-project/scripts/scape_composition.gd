# Does the scape use the water VOLUME, or just the floor?
#
# VISUAL_DIRECTIONS #17.
#
# `aquascape_craft.gd` already scores a scape on composition — open-water
# percentage, focal offset, style — and it is good. It scores the grid the
# PLAYER built, in the aquascape editor, and it scores it in XZ. The tank that
# actually boots is assembled by procedural layouts in world.gd, nothing checks
# the result, and neither the editor's analysis nor the layouts say anything
# about HEIGHT.
#
# Real aquascaping composes a volume: a focal mass off-centre, a mid-ground
# that steps back, background stems that reach the surface, and negative space
# that is CHOSEN rather than left over. This measures those four things.
#
# WHAT MEASURING THEM CHANGED. The going assumption — written into
# VISUAL_DIRECTIONS #17 and into an earlier draft of this header — was that the
# generated scape was bottom-heavy, with nothing in the upper third to catch
# the lamp. The first report said otherwise: bands 0.539 / 0.329 / 0.132, every
# vertical check passing. The defect was the fourth axis, focal offset 0.062:
# the mass sat dead centre. Worth keeping as a note on how confidently a
# plausible visual diagnosis can be wrong.
#
# PURE. Takes plain item dictionaries, returns numbers — so it can be asserted
# headlessly and applied to a live scape from the same code.

class_name ScapeComposition
extends RefCounted

# Low / mid / high thirds of the water column.
const BANDS: int = 3

# ---- The contract ----------------------------------------------------------

# Every band must carry SOME mass. A tank with an empty upper third is a
# terrarium with water over it.
const BAND_MIN: float = 0.08
# …but the top must not carry as much as the bottom. A column filled evenly
# top to bottom is a hedge, not a scape, and it leaves no swimming room.
const TOP_OF_BOTTOM_MAX: float = 0.80
# Focal mass, as a fraction of half-width from centre. Dead centre is the one
# placement every aquascaping tradition agrees is wrong.
const FOCAL_OFFSET_MIN: float = 0.12
# …and not shoved into a corner either.
const FOCAL_OFFSET_MAX: float = 0.75


# Scenario visual intent → composition expectations (HOLISTIC #019 / #021).
# Dense jungles are allowed a smaller focal offset than open stone gardens:
# wall-to-wall blades are the identity, not a failed scape. Sparse gardens
# still need a decisive off-centre mass.
static func expect_for_intent(intent: String) -> Dictionary:
	match String(intent):
		"dense_jungle":
			return {
				"focal_offset_min": 0.03,
				"focal_offset_max": 0.80,
				"top_of_bottom_max": 0.95,
				# Wall-to-wall blades still need a swim passage, but a thinner
				# corridor than an open stone garden is the point of the style.
				"corridor_min": 0.12,
			}
		"open_scape", "stone_garden":
			return {
				"focal_offset_min": 0.0,
				"focal_offset_max": 0.75,
				"top_of_bottom_max": TOP_OF_BOTTOM_MAX,
				# Carpet + low stones: mass lives in the substrate band.
				# Requiring mid/upper fill forced false FAILs on real Iwagumi.
				"upper_band_min": 0.0,
				"mid_band_min": 0.0,
			}
		_:
			return {}


# An item is {"base": float, "tip": float, "mass": float, "x": float, "z": float,
# "r": float}. `base`/`tip` are world Y; a rock has base == its bottom and tip
# its top, a stem has base at the substrate and tip at its growing point.
# `z` / `r` feed the swim-corridor grid (HOLISTIC #030); older callers that
# omit them still work for band/focal checks.
static func item(base_y: float, tip_y: float, mass: float, x: float = 0.0,
		z: float = 0.0, radius: float = 0.0) -> Dictionary:
	return {
		"base": minf(base_y, tip_y),
		"tip": maxf(base_y, tip_y),
		"mass": maxf(mass, 0.0),
		"x": x,
		"z": z,
		"r": maxf(radius, 0.0),
	}


# Fraction of total mass in each vertical band, low to high.
#
# Mass is spread across the bands an item SPANS, in proportion to how much of
# the item is in each — a vallisneria blade running floor to surface belongs to
# all three, and counting it only where its root sits is how a tank full of
# tall stems can measure as empty on top.
static func band_occupancy(items: Array, floor_y: float, surface_y: float,
		bands: int = BANDS) -> PackedFloat32Array:
	var n: int = maxi(bands, 1)
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	var span: float = surface_y - floor_y
	if span <= 0.001 or items.is_empty():
		return out
	var band_h: float = span / float(n)
	var total: float = 0.0
	for it in items:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		var mass: float = float(d.get("mass", 0.0))
		if mass <= 0.0:
			continue
		var lo: float = clampf(float(d.get("base", floor_y)), floor_y, surface_y)
		var hi: float = clampf(float(d.get("tip", floor_y)), floor_y, surface_y)
		var height: float = hi - lo
		total += mass
		if height <= 0.0001:
			# A zero-height item (a flat rock, a carpet) sits wholly in the
			# band its surface is in.
			var b: int = clampi(int((lo - floor_y) / band_h), 0, n - 1)
			out[b] += mass
			continue
		for b2 in n:
			var b_lo: float = floor_y + float(b2) * band_h
			var b_hi: float = b_lo + band_h
			var overlap: float = minf(hi, b_hi) - maxf(lo, b_lo)
			if overlap > 0.0:
				out[b2] += mass * (overlap / height)
	if total <= 0.0:
		return out
	for i in n:
		out[i] = out[i] / total
	return out


# Mass-weighted centre in X, as a signed fraction of the tank's half-width.
static func focal_offset_frac(items: Array, half_w: float) -> float:
	if items.is_empty() or half_w <= 0.001:
		return 0.0
	var acc: float = 0.0
	var total: float = 0.0
	for it in items:
		if not (it is Dictionary):
			continue
		var m: float = float((it as Dictionary).get("mass", 0.0))
		if m <= 0.0:
			continue
		acc += float((it as Dictionary).get("x", 0.0)) * m
		total += m
	if total <= 0.0:
		return 0.0
	return clampf((acc / total) / half_w, -1.0, 1.0)


# Negative space: the fraction of the water column's height that carries
# almost nothing. Chosen emptiness is composition; total emptiness is not.
static func open_band_fraction(occ: PackedFloat32Array) -> float:
	if occ.is_empty():
		return 1.0
	var empty: int = 0
	for v in occ:
		if v < BAND_MIN:
			empty += 1
	return float(empty) / float(occ.size())


# ---- Swim corridor (HOLISTIC #030) ------------------------------------------
#
# Band occupancy and focal offset are vertical / lateral mass checks. They
# cannot tell a dense jungle with a clear mid-water passage from a solid hedge.
# A coarse XZ occupancy grid + flood-fill measures connected open water so
# dense planting can still score well when a swim corridor remains.
#
# Measurement only — never delete established growth to satisfy the score.

const CORRIDOR_CELLS: int = 12
# Largest connected open component must cover at least this fraction of the
# floor grid (or the scape is nearly empty, which also "passes").
const CORRIDOR_MIN: float = 0.18
# Mid-band mass that marks a cell occupied. Light stems still leave a path;
# a boulder (high mass) or thick cluster blocks.
const CORRIDOR_BLOCK_MASS: float = 2.5


static func _item_radius(d: Dictionary, half_w: float) -> float:
	var r: float = float(d.get("r", 0.0))
	if r > 0.001:
		return r
	# Mass heuristic when callers omit r: a unit stem ~0.35, a boulder grows.
	var mass: float = float(d.get("mass", 1.0))
	return clampf(0.28 + sqrt(maxf(mass, 0.0)) * 0.18, 0.25, maxf(0.6, half_w * 0.35))


# Returns {open_frac, corridor_frac, cells, open, corridor}. `corridor_frac` is
# the largest 4-connected open component over the XZ floor grid.
static func swim_corridor(items: Array, half_w: float, half_d: float,
		floor_y: float, surface_y: float, cells: int = CORRIDOR_CELLS) -> Dictionary:
	var n: int = clampi(cells, 4, 24)
	var empty: Dictionary = {
		"open_frac": 1.0, "corridor_frac": 1.0, "cells": n * n,
		"open": n * n, "corridor": n * n,
	}
	if half_w <= 0.001 or half_d <= 0.001:
		return empty
	var span_y: float = surface_y - floor_y
	# Mid-water slab: corridors read where fish actually swim, not the carpet.
	var mid_lo: float = floor_y + span_y * 0.22
	var mid_hi: float = floor_y + span_y * 0.78
	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(n * n)
	blocked.fill(0)
	var cell_w: float = (half_w * 2.0) / float(n)
	var cell_d: float = (half_d * 2.0) / float(n)
	for it in items:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		var mass: float = float(d.get("mass", 0.0))
		if mass < CORRIDOR_BLOCK_MASS * 0.35:
			continue
		var lo: float = float(d.get("base", floor_y))
		var hi: float = float(d.get("tip", floor_y))
		if hi < mid_lo or lo > mid_hi:
			continue
		var ix: float = float(d.get("x", 0.0))
		var iz: float = float(d.get("z", 0.0))
		var rad: float = _item_radius(d, half_w)
		# Heavier mass blocks a wider footprint.
		rad *= clampf(0.85 + mass / 12.0, 0.85, 1.8)
		var x0: int = clampi(int(floor((ix - rad + half_w) / cell_w)), 0, n - 1)
		var x1: int = clampi(int(floor((ix + rad + half_w) / cell_w)), 0, n - 1)
		var z0: int = clampi(int(floor((iz - rad + half_d) / cell_d)), 0, n - 1)
		var z1: int = clampi(int(floor((iz + rad + half_d) / cell_d)), 0, n - 1)
		for zc in range(z0, z1 + 1):
			for xc in range(x0, x1 + 1):
				var cx: float = -half_w + (float(xc) + 0.5) * cell_w
				var cz: float = -half_d + (float(zc) + 0.5) * cell_d
				if (cx - ix) * (cx - ix) + (cz - iz) * (cz - iz) <= rad * rad:
					blocked[zc * n + xc] = 1
	var open_n: int = 0
	for i in blocked.size():
		if blocked[i] == 0:
			open_n += 1
	var total: int = n * n
	if open_n == 0:
		return {
			"open_frac": 0.0, "corridor_frac": 0.0, "cells": total,
			"open": 0, "corridor": 0,
		}
	# Flood-fill largest open component (4-connected).
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(total)
	seen.fill(0)
	var best: int = 0
	var stack: Array[int] = []
	for start in total:
		if blocked[start] != 0 or seen[start] != 0:
			continue
		stack.clear()
		stack.append(start)
		seen[start] = 1
		var size: int = 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			size += 1
			var cx: int = cur % n
			# Deliberate integer division: row index in the corridor grid.
			@warning_ignore("integer_division")
			var cz: int = cur / n
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + off.x
				var nz: int = cz + off.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var ni: int = nz * n + nx
				if blocked[ni] != 0 or seen[ni] != 0:
					continue
				seen[ni] = 1
				stack.append(ni)
		best = maxi(best, size)
	return {
		"open_frac": float(open_n) / float(total),
		"corridor_frac": float(best) / float(total),
		"cells": total,
		"open": open_n,
		"corridor": best,
	}


# The composition checks, in the same {name, value, want, ok} shape FrameMetrics
# uses so a capture run can print one table. `expect` overrides the universal
# thresholds (see expect_for_intent) so dense jungles and open gardens are
# not scored by one density rule. Optional `corridor` (from swim_corridor)
# adds the connected-open-water row without forcing callers to delete plants.
static func grade(occ: PackedFloat32Array, focal_frac: float,
		expect: Dictionary = {}, corridor: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var top: float = occ[occ.size() - 1] if not occ.is_empty() else 0.0
	var bottom: float = occ[0] if not occ.is_empty() else 0.0
	var top_cap: float = float(expect.get("top_of_bottom_max", TOP_OF_BOTTOM_MAX))
	var fmin: float = float(expect.get("focal_offset_min", FOCAL_OFFSET_MIN))
	var fmax: float = float(expect.get("focal_offset_max", FOCAL_OFFSET_MAX))
	var upper_min: float = float(expect.get("upper_band_min", BAND_MIN))
	var mid_min: float = float(expect.get("mid_band_min", BAND_MIN))
	out.append({
		"name": "upper band",
		"value": top,
		"want": ">= %.2f" % upper_min,
		"ok": top >= upper_min,
	})
	# Deliberate integer division: the middle band index.
	@warning_ignore("integer_division")
	var mid_idx: int = occ.size() / 2
	var mid: float = occ[mid_idx] if not occ.is_empty() else 0.0
	out.append({
		"name": "mid band",
		"value": mid,
		"want": ">= %.2f" % mid_min,
		"ok": mid >= mid_min,
	})
	out.append({
		"name": "top vs bottom",
		"value": top / maxf(bottom, 0.0001),
		"want": "<= %.2f" % top_cap,
		"ok": top <= bottom * top_cap + 0.0001,
	})
	var af: float = absf(focal_frac)
	out.append({
		"name": "focal offset",
		"value": af,
		"want": "%.2f..%.2f" % [fmin, fmax],
		"ok": af >= fmin and af <= fmax,
	})
	if not corridor.is_empty():
		var cmin: float = float(expect.get("corridor_min", CORRIDOR_MIN))
		var cfrac: float = float(corridor.get("corridor_frac", 1.0))
		var ofrac: float = float(corridor.get("open_frac", 1.0))
		# Nearly empty tanks pass; dense tanks need a connected corridor.
		var ok_c: bool = ofrac >= 0.85 or cfrac >= cmin
		out.append({
			"name": "swim corridor",
			"value": cfrac,
			"want": ">= %.2f (or open)" % cmin,
			"ok": ok_c,
		})
	return out


static func format_report(occ: PackedFloat32Array, focal_frac: float,
		intent: String = "", corridor: Dictionary = {}) -> String:
	var parts := PackedStringArray()
	for v in occ:
		parts.append("%.3f" % v)
	var base: String = "bands[low..high] %s  focal %+.3f  open %.2f" % [
		" ".join(parts), focal_frac, open_band_fraction(occ)]
	if not corridor.is_empty():
		base = "%s  corridor %.2f" % [base, float(corridor.get("corridor_frac", 0.0))]
	if intent.strip_edges().is_empty():
		return base
	return "%s  intent=%s" % [base, intent]


# ---- Placement bias --------------------------------------------------------
#
# The measured failure. A capture of the generated `beginner_sandbox` scape
# reported bands 0.539 / 0.329 / 0.132 — every band occupied, top lighter than
# bottom, all three vertical checks passing — and a focal offset of 0.062. The
# tank was not bottom-heavy at all, which was the going assumption; its mass
# was sitting dead centre, which is the one placement every aquascaping
# tradition agrees is wrong.
#
# The layouts in world.gd are symmetric by construction: `corner_refuge` plants
# two opposite corners, `central_island` plants a disc on the origin. Each is a
# reasonable shape and their sum is a centred blob.

# Where the focal mass wants to sit, as a fraction of half-width. A third of
# the way out is the power-point the rule of thirds names.
const POWER_POINT_FRAC: float = 0.333


## X coordinate of the tank's focal power-point. `side` is -1 or +1; a tank
## picks one from its seed and keeps it, so a scape is asymmetric the same way
## every time it is built.
static func power_point_x(half_w: float, side: int) -> float:
	return half_w * POWER_POINT_FRAC * (1.0 if side >= 0 else -1.0)


## How hard a plant of this mature height should be pulled toward the focal
## point, 0..1.
##
## Height-weighted on purpose: pulling EVERYTHING to one side just moves the
## blob. Pulling the tall species while carpets stay spread is what builds a
## background stand on one side with open foreground on the other, which is
## the composition rather than a lopsided version of the same problem.
static func focal_pull_for_height(mature_height: int) -> float:
	if mature_height <= 5:
		return 0.0
	return clampf(float(mature_height - 5) / 12.0, 0.0, 1.0) * 0.70


# Hard cap on how far one plant may be moved, in world units.
#
# WITHOUT THIS the bias relocates plants instead of leaning them.
# `smoke_scenario_layouts` caught it: the `corner_refuge` layout plants two
# opposite corners, and an unbounded pull of 0.7 dragged a corner stem from
# x = -5.85 to x = +2.6 — out of the corner the layout exists to make, leaving
# 1 corner plant out of 21. A carpet's radius drifted past its contract for the
# same reason.
#
# The layouts' shapes are the design; the bias is a lean applied to them, not a
# replacement for them. 0.9 units is enough to move the aggregate and small
# enough that a corner is still a corner.
const FOCAL_MAX_SHIFT: float = 0.9


## Move `x` toward `target` by `pull`, never further than FOCAL_MAX_SHIFT.
static func bias_toward(x: float, target: float, pull: float) -> float:
	var want: float = lerpf(x, target, clampf(pull, 0.0, 1.0))
	return x + clampf(want - x, -FOCAL_MAX_SHIFT, FOCAL_MAX_SHIFT)


# ---- Live scape ------------------------------------------------------------

# Build the item list from a running tank. Kept here rather than in world.gd so
# the definition of "what counts as mass" lives next to the maths that uses it.
#
# Plants contribute their stem from base to tip; hardscape contributes its
# footprint sphere. Fish are deliberately excluded — they move, and a
# composition that depends on where the fish happen to be is not a composition.
static func items_from_scape(plants: Array, hardscape: Array,
		voxel_size: float) -> Array:
	var out: Array = []
	for p in plants:
		if not is_instance_valid(p):
			continue
		var node: Node3D = p as Node3D
		if node == null:
			continue
		var h_v: Variant = p.get("current_height")
		var height: float = float(h_v) * voxel_size if h_v != null else 0.0
		var mass: float = 1.0
		if p.has_method("biomass"):
			mass = maxf(float(p.call("biomass")), 1.0)
		out.append(item(node.global_position.y,
			node.global_position.y + height, mass, node.global_position.x,
			node.global_position.z))
	for h in hardscape:
		if not (h is Vector4):
			continue
		var s: Vector4 = h
		if s.w <= 0.001:
			continue
		# Sphere proxy: mass scales with volume so a boulder outweighs a pebble.
		# Vector4 is (x, y, z, radius); z feeds the corridor grid.
		out.append(item(s.y - s.w, s.y + s.w, s.w * s.w * s.w * 12.0, s.x,
			s.z, s.w))
	return out
