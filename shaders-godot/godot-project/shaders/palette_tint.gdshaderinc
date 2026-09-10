// Shared global material tint — driven by TankConfig via VoxelMat global uniforms.
// Per-shader palette_* uniforms are music-sync overlays (0 / 1 = global only).

global uniform vec4 iaq_palette_fauna;
global uniform vec4 iaq_palette_foliage;
global uniform vec4 iaq_palette_hardscape;
global uniform vec4 iaq_palette_substrate;
global uniform vec4 iaq_palette_water;

// ---- Water column extinction -------------------------------------------------
//
// Water is not a blue filter laid over the picture — it is a medium that eats
// light, and it eats the long wavelengths first. Red is gone within a couple of
// feet, green hangs on, blue travels furthest. That single fact is most of why
// a photograph taken through an aquarium reads as "through water" rather than
// "in air with a blue tint": near objects stay warm and saturated, far ones
// lose their reds and drift toward the water's own colour.
//
// Beer–Lambert per channel over the light's path — down from the surface to the
// fragment, then back out to the eye — plus in-scattering, which is what fills
// the shadows with ambient water colour and gives the tank its sense of volume.
//
//   iaq_water_absorb : rgb = absorption per world unit, a = master strength
//   iaq_water_body   : rgb = in-scatter colour, a = water surface world Y
//
// a == 0 disables the whole thing, so the room, the potato tier and any
// non-aquatic surface pay one float compare.
global uniform vec4 iaq_water_absorb;
global uniform vec4 iaq_water_body;


// `world_y` is the fragment's world height, `view_dist` its distance from the
// camera. Returns the colour as seen through the intervening water.
vec3 apply_water_column(vec3 col, float world_y, float view_dist) {
	float strength = iaq_water_absorb.a;
	if (strength < 0.001) {
		return col;
	}
	float surface_y = iaq_water_body.a;
	float depth = max(surface_y - world_y, 0.0);
	if (depth <= 0.0) {
		return col;  // emergent growth, floaters, anything above the waterline
	}
	// Downwelling light travels the depth; the reflected light then travels the
	// view ray back out. The view term is weighted well under 1 because most of
	// that distance is AIR — the camera orbits outside the glass, and only the
	// last stretch is actually in water. Weighting it fully turned the whole
	// tank cyan at the default camera radius.
	float path = depth + view_dist * 0.35;
	vec3 transmit = exp(-iaq_water_absorb.rgb * path * strength);
	// In-scatter saturates with path length: distant water tends toward its own
	// colour rather than toward black. Kept gentle — this is a wash, not fog.
	float haze = 1.0 - exp(-path * strength * 0.020);
	return col * transmit + iaq_water_body.rgb * haze;
}

vec3 apply_global_palette_tint(vec3 col, float hue_shift, float sat_mult,
		float warmth, float val_mult) {
	if (abs(hue_shift) < 0.0001 && abs(sat_mult - 1.0) < 0.0001 && abs(warmth) < 0.0001 && abs(val_mult - 1.0) < 0.0001) {
		return col;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, sat_mult);
	col *= val_mult;
	col = mix(col, col * vec3(1.08, 1.0, 0.92), max(warmth, 0.0));
	col = mix(col, col * vec3(0.92, 0.98, 1.08), max(-warmth, 0.0));
	if (abs(hue_shift) > 0.0001) {
		float angle = hue_shift * 6.28318530718;
		float s = sin(angle);
		float c = cos(angle);
		mat3 hue_rot = mat3(
			vec3(0.299, 0.587, 0.114) + vec3(0.701, -0.587, -0.114) * c + vec3(0.168, 0.330, -0.497) * s,
			vec3(0.299, 0.587, 0.114) + vec3(-0.299, 0.413, -0.114) * c + vec3(-0.328, 0.035, 0.292) * s,
			vec3(0.299, 0.587, 0.114) + vec3(-0.300, -0.588, 0.886) * c + vec3(1.250, -1.050, -0.203) * s
		);
		col = clamp(hue_rot * col, 0.0, 1.0);
	}
	return col;
}

vec3 apply_category_palette_tint(vec3 col, vec4 global_pal,
		float hue_shift, float sat_mult, float warmth, float val_mult) {
	return apply_global_palette_tint(col,
		global_pal.x + hue_shift,
		global_pal.y * sat_mult,
		global_pal.z + warmth,
		global_pal.w * val_mult);
}
