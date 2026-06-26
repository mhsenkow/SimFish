# Shared 2D tank footprint (XZ plane).
#
# Every spawn, growth, floater drift, and creature clamp should go through
# this so box / hex / triangle / cylinder / sphere tanks stay consistent.

extends RefCounted
class_name TankFootprint

var shape: String = "box"
var half_w: float = 8.0
var half_d: float = 4.0
var substrate_y: float = 0.0
var water_y: float = 6.5
var tank_height: float = 7.0


static func from_values(p_shape: String, p_half_w: float, p_half_d: float) -> TankFootprint:
	var fp := TankFootprint.new()
	fp.shape = p_shape
	fp.half_w = p_half_w
	fp.half_d = p_half_d
	return fp


static func from_config(cfg: Node) -> TankFootprint:
	if cfg == null:
		return TankFootprint.new()
	return from_values(
		String(cfg.get("tank_shape")),
		float(cfg.get("tank_half_w")),
		float(cfg.get("tank_half_d")),
	)


static func from_world(w: Node) -> TankFootprint:
	if w == null:
		return TankFootprint.new()
	var fp := from_values(
		String(w.get("TANK_SHAPE")),
		float(w.get("TANK_HALF_W")),
		float(w.get("TANK_HALF_D")),
	)
	if w.get("SUBSTRATE_DEPTH") != null:
		fp.substrate_y = float(w.get("SUBSTRATE_DEPTH"))
	if w.get("WATER_HEIGHT") != null:
		fp.water_y = float(w.get("WATER_HEIGHT"))
	if w.get("TANK_HEIGHT") != null:
		fp.tank_height = float(w.get("TANK_HEIGHT"))
	return fp


func effective_radius(margin: float = 0.0) -> float:
	return maxf(0.05, minf(half_w - margin, half_d - margin))


func _bowl_radius(margin: float = 0.0) -> float:
	# Sphere center sits on the substrate; `effective_radius` is the open rim at water.
	var opening: float = effective_radius(margin)
	var dy_water: float = maxf(0.05, water_y - substrate_y)
	return sqrt(opening * opening + dy_water * dy_water)


func _sphere_radius(margin: float = 0.0) -> float:
	return _bowl_radius(margin)


func _water_dy() -> float:
	return maxf(0.05, water_y - substrate_y)


func _emergent_max_y(margin: float = 0.0) -> float:
	return water_y + effective_radius(margin) * 1.05 + 0.35


func _hemisphere_dy(y: float) -> float:
	# Distance from the bowl center (substrate top / dome origin).
	return absf(y - substrate_y)


func radius_at_height(y: float, margin: float = 0.0) -> float:
	# Horizontal cross-section radius at world Y.
	var rad: float = _sphere_radius(margin)
	match shape:
		"cylinder":
			return rad
		"sphere":
			var R: float = _bowl_radius(margin)
			if y < substrate_y:
				return 0.0
			var dy: float = y - substrate_y
			var dy_water: float = _water_dy()
			if dy > dy_water:
				return effective_radius(margin)
			if dy > R:
				return 0.0
			return sqrt(maxf(0.0, R * R - dy * dy))
		_:
			return 0.0


func half_width_at_z(z: float, margin: float = 0.0, world_y: float = NAN) -> float:
	# Half-width of the footprint cross-section at world Z (and optional Y for dome).
	var hw: float = half_w - margin
	var hd: float = half_d - margin
	if hw <= 0.0 or hd <= 0.0:
		return 0.0
	match shape:
		"triangle":
			if z > hd or z < -hd:
				return 0.0
			return hw * (hd - z) / (2.0 * hd)
		"cylinder":
			var rad_c: float = effective_radius(margin)
			if absf(z) > rad_c:
				return 0.0
			return sqrt(maxf(0.0, rad_c * rad_c - z * z))
		"sphere":
			var y_ref: float = substrate_y if is_nan(world_y) else world_y
			var rad_y: float = radius_at_height(y_ref, margin)
			if rad_y <= 0.0 or absf(z) > rad_y:
				return 0.0
			return sqrt(maxf(0.0, rad_y * rad_y - z * z))
		_:
			if absf(z) > hd:
				return 0.0
			return hw


func lateral_room(x: float, z: float, margin: float = 0.0, world_y: float = NAN) -> float:
	# Horizontal clearance from (x, z) to the nearest side wall.
	if not is_inside(x, z, margin, world_y):
		return 0.0
	match shape:
		"triangle":
			return half_width_at_z(z, margin) - absf(x)
		"cylinder", "sphere":
			var y_ref: float = substrate_y if is_nan(world_y) else world_y
			var rad_y: float = radius_at_height(y_ref, margin)
			return rad_y - Vector2(x, z).length()
		"hex":
			var hw: float = half_w - margin
			var hd: float = half_d - margin
			var q: float = absf(x) / hw
			var r: float = absf(z) / hd
			var slack_q: float = (1.0 - q - r * 0.5) * hw
			var slack_r: float = (1.0 - r) * hd
			return minf(slack_q, slack_r)
		_:
			var hw: float = half_w - margin
			var hd: float = half_d - margin
			return minf(hw - absf(x), hd - absf(z))


func _lateral_inward(x: float, z: float, margin: float) -> Vector3:
	var inward := Vector3.ZERO
	match shape:
		"cylinder", "sphere":
			var xz := Vector2(x, z)
			if xz.length_squared() > 1e-8:
				inward = Vector3(-xz.x, 0.0, -xz.y) / xz.length()
			else:
				inward = Vector3(1.0, 0.0, 0.0)
		_:
			var hw: float = half_w - margin
			var hd: float = half_d - margin
			var clear_x: float = hw - absf(x)
			var clear_z: float = hd - absf(z)
			var to_center := Vector3(-x, 0.0, -z)
			# Diagonal escape at box corners — single-axis inward used to let fish
			# slide into the glass seam and read as vanishing behind the rim.
			if clear_x < 0.55 and clear_z < 0.55 and to_center.length_squared() > 1e-6:
				return to_center.normalized()
			if clear_x <= clear_z:
				inward = Vector3(-1.0 if x >= 0.0 else 1.0, 0.0, 0.0)
			else:
				inward = Vector3(0.0, 0.0, -1.0 if z >= 0.0 else 1.0)
			# Slight corner bias only — heavy center blend made rim fish steer inward
			# and read as bouncing off the glass toward the middle.
			if shape == "hex" or shape == "triangle":
				if to_center.length_squared() > 1e-6:
					inward = (inward + to_center.normalized() * 0.12).normalized()
	if inward.length_squared() < 1e-6:
		inward = Vector3(1.0, 0.0, 0.0)
	return inward


# Horizontal glass only — substrate and meniscus are handled separately so
# mid-column fish are not perpetually steered upward toward the surface.
func lateral_boundary_info(x: float, y: float, z: float, margin: float = 0.0) -> Dictionary:
	var lat: float = lateral_room(x, z, margin, y)
	return {"clearance": maxf(0.0, lat), "inward": _lateral_inward(x, z, margin)}


# Floor / ceiling repulsion activates only within a narrow band near each plane.
func vertical_boundary_info(_x: float, y: float, _z: float, margin: float = 0.0,
		floor_band: float = 0.50, ceil_band: float = 0.42) -> Dictionary:
	var floor_m: float = substrate_y + margin
	var ceil_m: float = water_y - margin
	var clear_down: float = y - floor_m
	var clear_up: float = ceil_m - y
	if clear_down < floor_band and clear_down <= clear_up:
		return {
			"clearance": maxf(0.0, clear_down),
			"inward": Vector3(0.0, 1.0, 0.0),
			"active": true,
		}
	if clear_up < ceil_band and clear_up < clear_down:
		return {
			"clearance": maxf(0.0, clear_up),
			"inward": Vector3(0.0, -1.0, 0.0),
			"active": true,
		}
	return {"clearance": 99.0, "inward": Vector3.ZERO, "active": false}


# Nearest-boundary clearance + unit normal pointing into the tank interior.
# Used for clamp / overlap resolution. Fauna steering should prefer
# lateral_boundary_info + vertical_boundary_info instead.
func boundary_info(x: float, y: float, z: float, margin: float = 0.0) -> Dictionary:
	var floor_m: float = substrate_y + margin
	var ceil_m: float = water_y - margin
	var clear_down: float = y - floor_m
	var clear_up: float = ceil_m - y
	var lat: float = lateral_room(x, z, margin, y)
	var best: float = minf(minf(clear_down, clear_up), lat)
	var inward := Vector3.ZERO
	if best <= clear_down + 0.0001:
		inward = Vector3(0.0, 1.0, 0.0)
	elif best <= clear_up + 0.0001:
		inward = Vector3(0.0, -1.0, 0.0)
	else:
		inward = _lateral_inward(x, z, margin)
	return {"clearance": maxf(0.0, best), "inward": inward}


# Map a 0..1 water-column fraction to world Y at a specific XZ. On dome /
# cylinder tanks the highest in-bounds Y at the rim can sit below the global
# meniscus — using a flat column would place fish outside the glass.
func column_fraction_to_y(x: float, z: float, frac: float, margin: float = 0.0,
		floor_y: float = NAN) -> float:
	var floor_m: float = substrate_y + margin
	if not is_nan(floor_y):
		floor_m = maxf(floor_m, floor_y + margin * 0.35)
	var hi: float = water_y - margin
	if shape == "sphere" or shape == "cylinder":
		if not is_inside(x, z, margin, hi):
			var y_lo: float = floor_m
			var y_hi: float = hi
			for _i in 16:
				var mid: float = (y_lo + y_hi) * 0.5
				if is_inside(x, z, margin, mid):
					y_lo = mid
				else:
					y_hi = mid
			hi = y_lo
	hi = maxf(floor_m + 0.08, hi)
	return lerpf(floor_m, hi, clampf(frac, 0.0, 1.0))


func local_column_height(x: float, z: float, margin: float = 0.0,
		floor_y: float = NAN) -> float:
	var lo: float = column_fraction_to_y(x, z, 0.0, margin, floor_y)
	var hi: float = column_fraction_to_y(x, z, 1.0, margin, floor_y)
	return maxf(0.12, hi - lo)


func fits_point_with_radius(x: float, z: float, radius: float, margin: float = 0.0,
		world_y: float = NAN) -> bool:
	if radius <= 0.0:
		return is_inside(x, z, margin, world_y)
	if not is_inside(x, z, margin + radius, world_y):
		return false
	return lateral_room(x, z, margin, world_y) >= radius - 1e-4


func is_inside_3d(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	match shape:
		"sphere":
			# Water lives in the upper bowl only (y >= substrate top).
			if y < substrate_y - margin * 0.5:
				return false
			var R: float = _bowl_radius(margin)
			var dy: float = maxf(0.0, y - substrate_y)
			var xz2: float = x * x + z * z
			if y > water_y + margin:
				var open_r: float = effective_radius(margin)
				if xz2 > open_r * open_r:
					return false
				return y <= _emergent_max_y(margin)
			if dy > R:
				return false
			return xz2 + dy * dy <= R * R
		_:
			if y < substrate_y - margin:
				return false
			if y > water_y + margin:
				return false
			return is_inside(x, z, margin, y)


func clamp_inside_3d(p: Vector3, margin: float = 0.0) -> Vector3:
	if is_inside_3d(p.x, p.y, p.z, margin):
		return p
	match shape:
		"sphere":
			var R: float = _bowl_radius(margin) * 0.985
			p.y = maxf(p.y, substrate_y + margin)
			var dy: float = clampf(p.y - substrate_y, 0.0, R)
			var xz := Vector2(p.x, p.z)
			var xz_len: float = xz.length()
			if p.y > water_y:
				var open_r: float = effective_radius(margin) * 0.985
				if xz_len > open_r and xz_len > 1e-6:
					xz = xz * (open_r / xz_len)
				p.x = xz.x
				p.z = xz.y
				p.y = clampf(p.y, water_y + margin, _emergent_max_y(margin))
				return p
			var max_xz: float = sqrt(maxf(0.0, R * R - dy * dy))
			if xz_len > max_xz and xz_len > 1e-6:
				xz = xz * (max_xz / xz_len)
			p.x = xz.x
			p.z = xz.y
			p.y = clampf(p.y, substrate_y + margin, water_y + margin)
			if not is_inside_3d(p.x, p.y, p.z, margin):
				var t: float = 0.0
				for _i in 12:
					t = (float(_i) + 1.0) / 12.0
					var q: Vector3 = p.lerp(
						Vector3(0.0, substrate_y + R * 0.35, 0.0), t)
					if is_inside_3d(q.x, q.y, q.z, margin):
						return q
			return p
		_:
			var xz2: Vector2 = clamp_inside(p.x, p.z, margin, p.y)
			p = Vector3(
				xz2.x,
				clampf(p.y, substrate_y + margin, water_y - margin),
				xz2.y,
			)
			if is_inside_3d(p.x, p.y, p.z, margin):
				return p
			for _i in 12:
				var t: float = float(_i + 1) / 12.0
				var q: Vector3 = p.lerp(
					Vector3(0.0, substrate_y + (water_y - substrate_y) * 0.35, 0.0), t)
				if is_inside_3d(q.x, q.y, q.z, margin):
					return q
			return p


func is_inside(x: float, z: float, margin: float = 0.0, world_y: float = NAN) -> bool:
	var hw: float = half_w - margin
	var hd: float = half_d - margin
	if hw <= 0.0 or hd <= 0.0:
		return false
	match shape:
		"hex":
			var q: float = absf(x) / hw
			var r: float = absf(z) / hd
			return q + r * 0.5 < 1.0 and r < 1.0
		"triangle":
			if z > hd or z < -hd:
				return false
			var base_half: float = hw * (hd - z) / (2.0 * hd)
			return absf(x) <= base_half
		"cylinder":
			var rad_c: float = effective_radius(margin)
			return x * x + z * z <= rad_c * rad_c
		"sphere":
			var y_ref: float = substrate_y if is_nan(world_y) else world_y
			var rad_y: float = radius_at_height(y_ref, margin)
			return x * x + z * z <= rad_y * rad_y
		_:
			return absf(x) <= hw and absf(z) <= hd


func clamp_inside(x: float, z: float, margin: float = 0.0, world_y: float = NAN) -> Vector2:
	if is_inside(x, z, margin, world_y):
		return Vector2(x, z)
	var p := Vector2(x, z)
	if shape == "cylinder" or shape == "sphere":
		var y_ref: float = substrate_y if is_nan(world_y) else world_y
		var rad: float = radius_at_height(y_ref, margin) * 0.98
		var xz_len: float = p.length()
		if xz_len < 1e-6:
			return Vector2.ZERO
		if xz_len <= rad:
			return p
		return p * (rad / xz_len)
	# Pull toward center along a ray — works for all convex footprints.
	var lo: float = 0.0
	var hi: float = 1.0
	for _i in 14:
		var t: float = (lo + hi) * 0.5
		var q: Vector2 = p.lerp(Vector2.ZERO, t)
		if is_inside(q.x, q.y, margin, world_y):
			lo = t
		else:
			hi = t
	return p.lerp(Vector2.ZERO, lo)


func bounding_half_extents(margin: float = 0.0) -> Vector2:
	# Tight AABB half-sizes for voxel grids / spawn boxes (not the inscribed shape).
	var max_x: float = 0.05
	var max_z: float = 0.05
	for c in footprint_corners(12):
		max_x = maxf(max_x, absf(c.x))
		max_z = maxf(max_z, absf(c.z))
	if shape == "sphere":
		var rim: float = effective_radius(margin)
		max_x = maxf(max_x, rim)
		max_z = maxf(max_z, rim)
	return Vector2(max_x + margin, max_z + margin)


func _sample_xz_at_height(r: RandomNumberGenerator, margin: float, world_y: float) -> Vector2:
	if shape == "cylinder" or shape == "sphere":
		var ang: float = r.randf() * TAU
		var rad: float = radius_at_height(world_y, margin) * 0.96
		var dist: float = sqrt(r.randf()) * rad
		return Vector2(cos(ang) * dist, sin(ang) * dist)
	if shape == "triangle":
		var hd: float = half_d - margin
		var z: float = r.randf_range(-hd, hd)
		var hw: float = half_width_at_z(z, margin, world_y)
		return Vector2(r.randf_range(-hw, hw), z)
	if shape == "hex":
		var hd: float = half_d - margin
		var hw: float = half_w - margin
		var z: float = r.randf_range(-hd, hd)
		return Vector2(r.randf_range(-hw, hw), z)
	var hw_box: float = half_w - margin
	var hd_box: float = half_d - margin
	return Vector2(r.randf_range(-hw_box, hw_box), r.randf_range(-hd_box, hd_box))


func _sample_xz(r: RandomNumberGenerator, margin: float, z_min: float, z_max: float) -> Vector2:
	var z: float = r.randf_range(z_min, z_max)
	if shape == "cylinder" or shape == "sphere":
		return _sample_xz_at_height(r, margin, substrate_y)
	if shape == "triangle":
		var hd: float = half_d - margin
		z = r.randf_range(maxf(-hd, z_min), minf(hd, z_max))
		var hw: float = half_width_at_z(z, margin)
		return Vector2(r.randf_range(-hw, hw), z)
	if shape == "hex":
		z = r.randf_range(maxf(-(half_d - margin), z_min), minf(half_d - margin, z_max))
		var hw: float = half_w - margin
		return Vector2(r.randf_range(-hw, hw), z)
	return Vector2(r.randf_range(-(half_w - margin), half_w - margin), z)


func random_point(margin: float = 0.4, rng: RandomNumberGenerator = null) -> Vector2:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var ext: Vector2 = bounding_half_extents(margin)
	for _attempt in 48:
		var xz: Vector2 = _sample_xz(r, margin, -ext.y, ext.y)
		if is_inside(xz.x, xz.y, margin):
			return xz
	return clamp_inside(0.0, 0.0, margin)


func random_point_in_band(z_min: float, z_max: float, margin: float = 0.4,
		rng: RandomNumberGenerator = null, min_lateral_room: float = 0.0) -> Vector2:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if z_min > z_max:
		var tmp: float = z_min
		z_min = z_max
		z_max = tmp
	for _attempt in 48:
		var xz: Vector2 = _sample_xz(r, margin, z_min, z_max)
		if is_inside(xz.x, xz.y, margin) and lateral_room(xz.x, xz.y, margin) >= min_lateral_room:
			return xz
	var fallback: Vector2 = random_point(margin, r)
	fallback = clamp_inside(fallback.x, clampf((z_min + z_max) * 0.5, -half_d, half_d), margin)
	if min_lateral_room > 0.0 and lateral_room(fallback.x, fallback.y, margin) < min_lateral_room:
		return clamp_inside(0.0, 0.0, margin + min_lateral_room)
	return fallback


func random_point_in_volume(y_min: float, y_max: float, margin: float = 0.4,
		rng: RandomNumberGenerator = null) -> Vector3:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if y_min > y_max:
		var tmp: float = y_min
		y_min = y_max
		y_max = tmp
	for _attempt in 48:
		var y: float = r.randf_range(y_min, y_max)
		var xz: Vector2 = _sample_xz_at_height(r, margin, y)
		if is_inside_3d(xz.x, y, xz.y, margin):
			return Vector3(xz.x, y, xz.y)
	var xz_fb: Vector2 = random_point(margin, r)
	var y_fb: float = clampf(r.randf_range(y_min, y_max), substrate_y + margin, water_y - margin)
	xz_fb = clamp_inside(xz_fb.x, xz_fb.y, margin, y_fb)
	return Vector3(xz_fb.x, y_fb, xz_fb.y)


func is_substrate_voxel(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	# Vertical prism: footprint at each XZ, stacked up to the substrate surface.
	if y < 0.0 or y > substrate_y + 0.02:
		return false
	return is_inside(x, z, margin)


func is_revolution() -> bool:
	return shape == "cylinder" or shape == "sphere"


func is_regular_polygon() -> bool:
	return shape == "hex" or shape == "triangle"


# Glass/water shader family: 0 = prism, 1 = cylinder, 2 = sphere bowl.
func shader_shape_class() -> int:
	match shape:
		"cylinder":
			return 1
		"sphere":
			return 2
		_:
			return 0


# Rough open-surface area proxy (XZ) for ecology caps and spawn density.
func surface_area_proxy() -> float:
	match shape:
		"cylinder", "sphere":
			var r: float = effective_radius(0.0)
			return PI * r * r
		"hex":
			return half_w * half_d * 1.5
		"triangle":
			return half_w * half_d
		_:
			return (half_w * 2.0) * (half_d * 2.0)


# Usable water-surface area after a glass margin — drives floater capacity.
# Cylinder/sphere use the horizontal slice at `world_y`; rectilinear shapes
# use inset half-extents (radius_at_height returns 0 for box/hex/triangle).
func usable_surface_area(margin: float = 0.0, world_y: float = NAN) -> float:
	var y: float = water_y if is_nan(world_y) else world_y
	match shape:
		"cylinder", "sphere":
			var r: float = radius_at_height(y, margin)
			if r > 0.0:
				return PI * r * r
			return surface_area_proxy()
		"hex":
			var hw: float = maxf(0.0, half_w - margin)
			var hd: float = maxf(0.0, half_d - margin)
			return hw * hd * 1.5
		"triangle":
			var hw_t: float = maxf(0.0, half_w - margin)
			var hd_t: float = maxf(0.0, half_d - margin)
			return hw_t * hd_t
		_:
			var hw_b: float = maxf(0.0, half_w - margin)
			var hd_b: float = maxf(0.0, half_d - margin)
			return hw_b * 2.0 * hd_b * 2.0


func footprint_corners(segments: int = 24) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	match shape:
		"hex":
			for i in 6:
				var a: float = (float(i) / 6.0) * TAU
				pts.append(Vector3(cos(a) * half_w, 0.0, sin(a) * half_d))
		"triangle":
			pts.append(Vector3(0.0, 0.0, half_d))
			pts.append(Vector3(-half_w, 0.0, -half_d))
			pts.append(Vector3(half_w, 0.0, -half_d))
		"cylinder", "sphere":
			var rad: float = effective_radius(0.0)
			var segs: int = maxi(segments, 12)
			for i in segs:
				var a: float = (float(i) / float(segs)) * TAU
				pts.append(Vector3(cos(a) * rad, 0.0, sin(a) * rad))
		_:
			pts.append(Vector3(half_w, 0.0, half_d))
			pts.append(Vector3(-half_w, 0.0, half_d))
			pts.append(Vector3(-half_w, 0.0, -half_d))
			pts.append(Vector3(half_w, 0.0, -half_d))
	return pts
