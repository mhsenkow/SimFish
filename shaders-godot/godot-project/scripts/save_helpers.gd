# Stateless helpers for JSON-friendly conversion of Godot types.
#
# Vector3 and Color don't serialize to JSON natively — they'd become opaque
# strings via JSON.stringify. We convert them to plain Arrays of floats so
# the saved state.json round-trips cleanly. Everywhere a script saves a
# vector or color, route through these.

class_name SaveHelpers


# ---- Color ----

static func color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func array_to_color(a, fallback: Color = Color.WHITE) -> Color:
	if a is Array and a.size() >= 3:
		var alpha: float = float(a[3]) if a.size() >= 4 else 1.0
		return Color(float(a[0]), float(a[1]), float(a[2]), alpha)
	return fallback


static func colors_to_array(cs: Array) -> Array:
	var out: Array = []
	for c in cs:
		if c is Color:
			out.append(color_to_array(c))
	return out


static func array_to_colors(a) -> Array:
	var out: Array = []
	if not (a is Array):
		return out
	for x in a:
		if x is Array and x.size() >= 3:
			out.append(array_to_color(x))
	return out


# ---- Vector3 ----

static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# ---- Vector2 ----

static func vec2_to_array(v: Vector2) -> Array:
	return [v.x, v.y]


static func array_to_vec2(a, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback
