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
	return maxf(0.0, y - substrate_y)


func radius_at_height(y: float, margin: float = 0.0) -> float:
	# Horizontal cross-section radius at world Y.
	var rad: float = _sphere_radius(margin)
	match shape:
		"cylinder":
			return rad
		"sphere":
			var R: float = _bowl_radius(margin)
			var dy: float = _hemisphere_dy(y)
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


func fits_point_with_radius(x: float, z: float, radius: float, margin: float = 0.0,
		world_y: float = NAN) -> bool:
	if radius <= 0.0:
		return is_inside(x, z, margin, world_y)
	if not is_inside(x, z, margin + radius, world_y):
		return false
	return lateral_room(x, z, margin, world_y) >= radius - 1e-4


func is_inside_3d(x: float, y: float, z: float, margin: float = 0.0) -> bool:
	if y < substrate_y - margin:
		return false
	match shape:
		"sphere":
			var R: float = _bowl_radius(margin)
			var dy: float = _hemisphere_dy(y)
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
			if y > water_y + margin:
				return false
			return is_inside(x, z, margin, y)


func clamp_inside_3d(p: Vector3, margin: float = 0.0) -> Vector3:
	if is_inside_3d(p.x, p.y, p.z, margin):
		return p
	match shape:
		"sphere":
			var R: float = _bowl_radius(margin) * 0.985
			var dy: float = clampf(_hemisphere_dy(p.y), 0.0, R)
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
			var xz2: Vector2 = clamp_inside(p.x, p.z, margin)
			return Vector3(
				xz2.x,
				clampf(p.y, substrate_y + margin, water_y - margin),
				xz2.y,
			)


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


func random_point(margin: float = 0.4, rng: RandomNumberGenerator = null) -> Vector2:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	for _attempt in 48:
		var x: float = 0.0
		var z: float = 0.0
		if shape == "cylinder" or shape == "sphere":
			var ang: float = r.randf() * TAU
			var y_ref: float = substrate_y
			var rad: float = radius_at_height(y_ref, margin) * 0.96
			var dist: float = sqrt(r.randf()) * rad
			x = cos(ang) * dist
			z = sin(ang) * dist
		else:
			x = r.randf_range(-half_w, half_w)
			z = r.randf_range(-half_d, half_d)
		if is_inside(x, z, margin):
			return Vector2(x, z)
	return clamp_inside(0.0, 0.0, margin)


func random_point_in_band(z_min: float, z_max: float, margin: float = 0.4,
		rng: RandomNumberGenerator = null, min_lateral_room: float = 0.0) -> Vector2:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	for _attempt in 48:
		var x: float = r.randf_range(-half_w, half_w)
		var z: float = r.randf_range(z_min, z_max)
		if is_inside(x, z, margin) and lateral_room(x, z, margin) >= min_lateral_room:
			return Vector2(x, z)
	# Fall back to any interior point, then clamp Z toward the band center.
	var fallback: Vector2 = random_point(margin, r)
	fallback.y = clampf((z_min + z_max) * 0.5, -half_d, half_d)
	fallback = clamp_inside(fallback.x, fallback.y, margin)
	if min_lateral_room > 0.0 and lateral_room(fallback.x, fallback.y, margin) < min_lateral_room:
		return clamp_inside(0.0, 0.0, margin)
	return fallback


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
