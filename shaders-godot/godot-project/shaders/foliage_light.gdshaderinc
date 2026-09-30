// Leaf light for the UNSHADED foliage pipeline: transmission, the rear
// backlight, ribbon margins and aufwuchs. Included by foliage.gdshader and
// foliage_mm.gdshader AFTER beam_cone.gdshaderinc (it reads the beam globals).
//
// WHY THIS EXISTS. A thin leaf is lit mostly from BEHIND. Held between you
// and a lamp, a vallisneria blade glows yellow-green and its veins show;
// that glow is the single strongest cue in a real planted-tank photo, and
// the frame had none of it. The old term, pow(max(-dot(n, VIEW), 0)),
// asks how much a face points AWAY from the camera - which, under
// cull_back, no visible face ever does, so it was 0 on every fragment the
// tank drew. And every light in the tank is a real Light3D that an
// unshaded material ignores, so there was nothing to transmit anyway.
//
// So both are computed here in WORLD space, from globals:
//   - the key light: the fixture beam (iaq_beam_*), or straight down when
//     no shaped light is set;
//   - the rear backlight: iaq_backlight / iaq_backlight_tint, driven by
//     world.gd from the lighting preset (0 energy = off, one branch).
//
//   iaq_backlight      = (x, y, z, energy)
//   iaq_backlight_tint = (r, g, b, falloff k)   att = 1 / (1 + k d^2)
//
// These two globals are declared HERE and nowhere else in the foliage
// include chain: a second declaration in another include would fail to
// compile every foliage shader.

global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;


// Nearest point on the fixture (a bar is a segment, see beam_cone), and how
// much of the cone reaches `wpos`. Returns the light position in xyz and the
// cone factor in w.
vec4 iaq_leaf_key_source(vec3 wpos) {
	vec3 src_pos = iaq_beam_origin;
	if (iaq_beam_axis.w > 0.5) {
		vec3 ax = iaq_beam_axis.xyz;
		float len2 = dot(ax, ax);
		if (len2 > 1e-6) {
			float t_ax = clamp(dot(wpos - iaq_beam_origin, ax) / len2, -1.0, 1.0);
			src_pos = iaq_beam_origin + ax * t_ax;
		}
	}
	vec3 to_frag = wpos - src_pos;
	float dist = length(to_frag);
	float cone = 0.0;
	if (dist > 0.0001) {
		float cd = dot(to_frag / dist, normalize(iaq_beam_dir));
		// Transmission forgives the cone edge more than direct light does:
		// light scattered through the water still arrives from above.
		cone = smoothstep(iaq_beam_cone.x - 0.25, iaq_beam_cone.y, cd);
		cone *= 1.0 - smoothstep(iaq_beam_cone.z * 0.6, iaq_beam_cone.z * 1.1, dist);
	}
	return vec4(src_pos, cone);
}


// What a thin green leaf passes: its own hue, lifted toward warm yellow, so
// a pink lamp through a green blade reads olive-khaki and a warm lamp reads
// lime - which is exactly how the reference photos read.
vec3 iaq_leaf_filter(vec3 col) {
	float peak = max(max(col.r, col.g), max(col.b, 0.05));
	vec3 chroma = clamp(col / peak, 0.0, 1.0);
	return mix(chroma, vec3(1.0, 0.95, 0.55), 0.38);
}


// Thin-leaf transmission plus the rear lamp's direct wash.
//
// `n_ws` is the WORLD normal of the visible face, `thin` 0..1 (1 = paper
// thin), `key_rgb` the key light's colour times its strength (callers pass
// the fixture/daylight fallback; the beam overrides it when one is set).
vec3 iaq_leaf_light(vec3 col, vec3 wpos, vec3 n_ws, vec3 cam_pos, float thin,
		vec3 key_rgb) {
	vec3 v_ws = normalize(cam_pos - wpos);
	vec3 filt = iaq_leaf_filter(col);
	vec3 add = vec3(0.0);
	float veil = 0.0;

	// Key light from above. A face we can see, with the lamp on its far side,
	// is lit through. The forward lobe - looking up INTO the light through
	// the leaf - is where a blade lying on the surface glows.
	vec3 key_pos = wpos + vec3(0.0, 8.0, 0.0);
	float key_cone = 1.0;
	vec3 key_col = key_rgb;
	if (iaq_beam_cone.w > 0.001) {
		vec4 ks = iaq_leaf_key_source(wpos);
		key_pos = ks.xyz;
		key_cone = ks.w;
		key_col = iaq_beam_tint.rgb * clamp(iaq_beam_cone.w * 0.5, 0.0, 1.2)
			+ key_rgb * 0.35;
	}
	vec3 lk = normalize(key_pos - wpos);
	float t_key = max(-dot(n_ws, lk), 0.0)
		* (0.3 + 0.7 * pow(max(dot(-v_ws, lk), 0.0), 3.0)) * key_cone;
	add += key_col * filt * t_key * 0.85;
	veil += t_key * 0.35;

	// Rear lamp. Energy 0 = off; one compare for every tank without one.
	float bl_e = iaq_backlight.w;
	if (bl_e > 0.001) {
		vec3 to_l = iaq_backlight.xyz - wpos;
		float d2 = dot(to_l, to_l);
		vec3 lb = to_l * inversesqrt(max(d2, 1e-4));
		float att = bl_e / (1.0 + max(iaq_backlight_tint.a, 0.0) * d2);
		float t_b = max(-dot(n_ws, lb), 0.0)
			* (0.35 + 0.65 * pow(max(dot(-v_ws, lb), 0.0), 2.0));
		add += iaq_backlight_tint.rgb * filt * t_b * att * 1.1;
		veil += t_b * att * 0.4;
		// Faces turned toward the lamp and the camera are lit directly: a
		// warm wash that keeps the leaf's own hue.
		float d_b = max(dot(n_ws, lb), 0.0);
		add += col * iaq_backlight_tint.rgb * d_b * att * 0.45;
	}
	// A backlit leaf's own surface colour washes out under the glow.
	float k = clamp(thin, 0.0, 1.0);
	col *= 1.0 - clamp(veil * k, 0.0, 0.45);
	return col + add * k;
}


// Ribbon margins and midrib, from the PRE-displacement unit-box coordinate.
// At 3-4 art pixels across, dark margin / light midrib / dark margin is what
// separates two overlapping blades after the palette quantize: without a
// luminance step between them the outline pass never fires and the whole
// stand merges into one colour region.
float iaq_blade_margin(vec3 local_box, float amount) {
	if (amount <= 0.001) {
		return 1.0;
	}
	// Broad face (thin axis is local z): shade across the width.
	if (abs(local_box.z) > 0.45) {
		float m = abs(local_box.x) * 2.0;
		return mix(1.0, mix(1.12, 0.70, smoothstep(0.40, 0.95, m)), amount);
	}
	// Edge face: a blade seen edge-on is its darkest line.
	if (abs(local_box.x) > 0.45) {
		return mix(1.0, 0.72, amount);
	}
	return 1.0;
}


// World-quantized, so the speckle sticks to the leaf instead of crawling.
float iaq_leaf_hash(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}


// Aufwuchs: the brown-olive film and hair algae on old leaves. `fuzz` 0..1
// comes from the instance colour's alpha (1 - a), so it costs no custom-data
// channel; margins fuzz first, the way it collects in real tanks.
vec3 iaq_leaf_aufwuchs(vec3 col, vec3 wpos, vec3 local_box, float fuzz) {
	if (fuzz <= 0.01) {
		return col;
	}
	float m = clamp(abs(local_box.x) * 2.0, 0.0, 1.0);
	float h = iaq_leaf_hash(wpos * 18.0);
	float mask = step(1.0 - fuzz * (0.35 + 0.65 * m), h);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	// Film: dull and warm the whole blade a little.
	col = mix(col, vec3(l) * vec3(1.06, 1.0, 0.78), fuzz * 0.32);
	vec3 aufwuchs = mix(vec3(0.36, 0.34, 0.19), vec3(0.55, 0.47, 0.33),
		step(0.7, fract(h * 7.31)));
	return mix(col, aufwuchs, mask * 0.6);
}
