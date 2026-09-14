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


# An item is {"base": float, "tip": float, "mass": float, "x": float}.
# `base`/`tip` are world Y; a rock has base == its bottom and tip its top, a
# stem has base at the substrate and tip at its growing point.
static func item(base_y: float, tip_y: float, mass: float, x: float = 0.0) -> Dictionary:
	return {
		"base": minf(base_y, tip_y),
		"tip": maxf(base_y, tip_y),
		"mass": maxf(mass, 0.0),
		"x": x,
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


# The four checks, in the same {name, value, want, ok} shape FrameMetrics uses
# so a capture run can print one table.
static func grade(occ: PackedFloat32Array, focal_frac: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var top: float = occ[occ.size() - 1] if not occ.is_empty() else 0.0
	var bottom: float = occ[0] if not occ.is_empty() else 0.0
	out.append({
		"name": "upper band",
		"value": top,
		"want": ">= %.2f" % BAND_MIN,
		"ok": top >= BAND_MIN,
	})
	# Deliberate integer division: the middle band index.
	@warning_ignore("integer_division")
	var mid_idx: int = occ.size() / 2
	var mid: float = occ[mid_idx] if not occ.is_empty() else 0.0
	out.append({
		"name": "mid band",
		"value": mid,
		"want": ">= %.2f" % BAND_MIN,
		"ok": mid >= BAND_MIN,
	})
	out.append({
		"name": "top vs bottom",
		"value": top / maxf(bottom, 0.0001),
		"want": "<= %.2f" % TOP_OF_BOTTOM_MAX,
		"ok": top <= bottom * TOP_OF_BOTTOM_MAX + 0.0001,
	})
	var af: float = absf(focal_frac)
	out.append({
		"name": "focal offset",
		"value": af,
		"want": "%.2f..%.2f" % [FOCAL_OFFSET_MIN, FOCAL_OFFSET_MAX],
		"ok": af >= FOCAL_OFFSET_MIN and af <= FOCAL_OFFSET_MAX,
	})
	return out


static func format_report(occ: PackedFloat32Array, focal_frac: float) -> String:
	var parts := PackedStringArray()
	for v in occ:
		parts.append("%.3f" % v)
	return "bands[low..high] %s  focal %+.3f  open %.2f" % [
		" ".join(parts), focal_frac, open_band_fraction(occ)]


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
			node.global_position.y + height, mass, node.global_position.x))
	for h in hardscape:
		if not (h is Vector4):
			continue
		var s: Vector4 = h
		if s.w <= 0.001:
			continue
		# Sphere proxy: mass scales with volume so a boulder outweighs a pebble.
		out.append(item(s.y - s.w, s.y + s.w, s.w * s.w * s.w * 12.0, s.x))
	return out
