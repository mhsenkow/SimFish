// Gravel and soil as seen through the front glass (REAL_TANK top-10 #8).
//
// The cross-section used to be drawn with square hash cells 0.18-0.36 units
// across - at the glass, a checkerboard of 4-8 px blocks - and a soil/cap
// boundary keyed on a hash that stepped every 1.2 units, so the line that
// should wander was a staircase. Real gravel at the glass is rounded grains
// of a few sizes packed with dark gaps between them; real soil is dark and
// fine with sand specks; and the boundary between them is a wavy, mixed
// band where snails and roots have worked gravel down into the soil.
//
// Names are sg_-prefixed: both substrate shaders include this alongside
// their own hash helpers.

float sg_hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// Smooth 1D value noise, -1..1.
float sg_vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(sg_hash(vec2(i, 7.1)), sg_hash(vec2(i + 1.0, 7.1)), u) * 2.0 - 1.0;
}

// The soil/cap boundary offset along the glass, -1..1: two octaves of smooth
// noise and a slow sine, so it wanders rather than steps.
float sg_boundary_wave(vec3 wp) {
	float s = wp.x + wp.z * 0.35;
	return sg_vnoise(s * 0.9) * 0.55 + sg_vnoise(s * 2.6 + 11.0) * 0.30
		+ sin(s * 0.42) * 0.25;
}

// Rounded grain in a jittered cell. q = face coordinates (along the glass,
// up), size = grain spacing in world units. Returns (inside 0..1, grain id
// hash, top-lit shade multiplier, unused).
vec4 sg_grain(vec2 q, float size) {
	vec2 g = q / size;
	vec2 ci = floor(g);
	vec2 f = fract(g);
	vec2 c = vec2(sg_hash(ci + 1.7), sg_hash(ci + 9.2)) * 0.36 + 0.32;
	float r = mix(0.30, 0.47, sg_hash(ci + 4.4));
	// Grains settle flat-side down: a little wider than tall.
	vec2 d = (f - c) * vec2(1.0, 1.22);
	float dist = length(d);
	float inside = 1.0 - smoothstep(r - 0.07, r, dist);
	// Lit from above through the water: the upper face of each grain is
	// lighter, its underside sits in the gap's shadow.
	float shade = 0.82 + 0.36 * clamp((c.y - f.y) / max(r, 0.01) * -0.5 + 0.5, 0.0, 1.0);
	return vec4(inside, sg_hash(ci + 3.1), shade, 0.0);
}

// One gravel face: two grain sizes so it never reads as a grid, dark gaps
// between. `tones` picks a grain colour from a hash.
vec3 sg_gravel(vec2 q, vec3 gap_col, vec3 tone_a, vec3 tone_b, vec3 tone_c, float size) {
	vec4 big = sg_grain(q, size);
	vec4 small = sg_grain(q + vec2(0.37, 0.11) * size, size * 0.55);
	float pick = big.x > 0.5 ? big.y : small.y;
	float inside = max(big.x, small.x * 0.9);
	float shade = big.x > 0.5 ? big.z : small.z;
	vec3 tone = pick < 0.38 ? tone_a : (pick < 0.72 ? tone_b : tone_c);
	tone *= 0.88 + 0.24 * fract(pick * 7.3);
	return mix(gap_col, tone * shade, inside);
}
