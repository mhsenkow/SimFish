// Analytic spot cone for the UNSHADED voxel pipeline.
//
// WHY THIS EXISTS. Every voxel and foliage shader in this project is
// `render_mode unshaded` - a deliberate choice, because the palette
// quantizer needs direct control of the colour that reaches it and real
// lighting fights that. The cost is that nothing in the tank responds to a
// light at all: a plant renders the same bright green whether the lamp is
// pointing at it or at the opposite wall. Turning shadows on in a spot
// changed nothing for exactly this reason.
//
// So the cone is evaluated analytically instead. One set of globals
// describes the lamp; anything that includes this file brightens inside
// the cone and falls toward `ambient` outside it. That is what makes the
// beam land ON the plants rather than merely crossing the water in front
// of them.
//
//   iaq_beam_cone = (cos_outer, cos_inner, range, energy)
//   iaq_beam_tint = (r, g, b, ambient_outside)
//
// energy 0 disables the whole path, so tanks with no shaped light pay one
// branch and nothing else.

global uniform vec3 iaq_beam_origin;
global uniform vec3 iaq_beam_dir;
global uniform vec4 iaq_beam_cone;
global uniform vec4 iaq_beam_tint;
global uniform vec4 iaq_beam_falloff;
// Directional sources use a unit vector TO the light and continuous energy.
// Point sources carry position, energy, and tint.a = inverse-square softening.
global uniform vec4 iaq_sun_light;
global uniform vec4 iaq_sun_tint;
global uniform vec4 iaq_moon_light;
global uniform vec4 iaq_moon_tint;
global uniform vec4 iaq_accent1;
global uniform vec4 iaq_accent1_tint;
global uniform vec4 iaq_accent2;
global uniform vec4 iaq_accent2_tint;
// The room's share of global_intensity dimming (LightingRig.room_light). The
// post tint spares a lit tank the room's dimness; the light the room would
// have taken away is taken here instead, from the AMBIENT term only. Inside
// the cone the lamp owns the brightness, outside it the tank falls to the
// room's level - a pool of light in a dim room. 1.0 = no change.
global uniform float iaq_room_light;
// xyz = half-extent vector along a LINE fixture, w > 0.5 marks it a line.
//
// A bar light is not a point. world.gd builds it as four SpotLights spaced
// along the housing and the globals only ever carried the first of them, so
// the "cone" for the commonest fixture in the game was a 42-degree spot
// hanging off the left end of the bar. Carrying the axis lets the same maths
// treat the fixture as a segment: the cone is measured from the nearest point
// ON the bar, which is what a bar actually does.
global uniform vec4 iaq_beam_axis;

// ---- The tank as the light source (REAL_TANK top-10 #1) ---------------------
//
// The ambient term above is ONE number for the whole scene, so the water and
// the wall behind the tank were lit to exactly the same level and the tank
// could never glow relative to its room. In a photograph of a lit aquarium the
// tank is the brightest object in the room, its top is brighter than its floor,
// and the desk and wall near it are lit BY it. These three globals split the
// ambient by position and give the tank its spill.
//
//   iaq_tank_box   : x/y = water half extents X/Z, z = glass floor Y,
//                    w = water surface Y. x == 0 disables the whole path.
//   iaq_tank_light : x = ambient multiplier OUTSIDE the tank (the room),
//                    y = lamp-light gain at the surface, z = at the glass floor,
//                    w = share of the lamp's DIRECT light that reaches
//                    surfaces outside the tank. A lamp sits on the tank and
//                    its hood throws the light down into the water; without
//                    this the wall behind sat inside the cone and stayed as
//                    bright as the water whatever the ambient did.
//   iaq_tank_glow  : rgb = colour of the light leaving the glass (linear),
//                    a = its strength at the glass.
//
// LightingRig.tank_light / tank_glow build them; (1, 1, 1) and a = 0 are the
// identity, so a lamp that is off leaves the scene exactly as it was.
global uniform vec4 iaq_tank_box;
global uniform vec4 iaq_tank_light;
global uniform vec4 iaq_tank_glow;

// 1 inside the water volume (and the floaters and emergent growth just above
// it), 0 outside, with a short soft edge so a voxel straddling the glass does
// not split into two brightnesses.
float iaq_tank_inside(vec3 p) {
	vec2 half_ext = iaq_tank_box.xy;
	vec2 out_xz = abs(p.xz) - half_ext;
	float out_h = max(out_xz.x, out_xz.y);
	float out_v = max(iaq_tank_box.z - p.y, p.y - (iaq_tank_box.w + 0.6));
	return 1.0 - smoothstep(0.0, 0.12, max(out_h, out_v));
}

// Multiplier on the ambient term: 1 in the tank, the room dim outside it.
float iaq_tank_ambient_mul(vec3 p) {
	if (iaq_tank_box.x <= 0.001) {
		return 1.0;
	}
	return mix(iaq_tank_light.x, 1.0, iaq_tank_inside(p));
}

// Gain on everything lit INSIDE the tank: the surface is brighter than the
// floor. Applied to the finished light rather than the ambient because inside
// the cone the direct term replaces the ambient, so an ambient lift there
// changed nothing.
float iaq_tank_depth_gain(vec3 p) {
	if (iaq_tank_box.x <= 0.001) {
		return 1.0;
	}
	float span = max(iaq_tank_box.w - iaq_tank_box.z, 0.5);
	float t = clamp((iaq_tank_box.w - p.y) / span, 0.0, 1.0);
	// Light is lost fastest in the first stretch below the surface, so the
	// top third reads distinctly brighter rather than the gradient being an
	// even ramp nobody notices.
	float gain = mix(iaq_tank_light.y, iaq_tank_light.z, pow(t, 0.75));
	return mix(1.0, gain, iaq_tank_inside(p));
}

// Multiplier on the lamp's direct term: 1 in the tank, iaq_tank_light.w
// outside it.
float iaq_tank_direct_mul(vec3 p) {
	if (iaq_tank_box.x <= 0.001) {
		return 1.0;
	}
	return mix(iaq_tank_light.w, 1.0, iaq_tank_inside(p));
}

// Light the tank throws onto the room: strongest on surfaces close to the
// glass that face it. Zero inside the tank, where the lamp already lights it.
vec3 iaq_tank_spill(vec3 p, vec3 n, vec3 base_col) {
	if (iaq_tank_glow.a <= 0.001 || iaq_tank_box.x <= 0.001) {
		return vec3(0.0);
	}
	vec3 lo = vec3(-iaq_tank_box.x, iaq_tank_box.z, -iaq_tank_box.y);
	vec3 hi = vec3(iaq_tank_box.x, iaq_tank_box.w, iaq_tank_box.y);
	vec3 nearest = clamp(p, lo, hi);
	vec3 d = nearest - p;
	float dist2 = dot(d, d);
	if (dist2 < 1e-5) {
		return vec3(0.0);
	}
	vec3 L = d * inversesqrt(dist2);
	float facing = 1.0;
	if (dot(n, n) > 1e-6) {
		facing = clamp((dot(normalize(n), L) + 0.35) / 1.35, 0.0, 1.0);
	}
	// A short reach: the desk at the glass and the wall right behind it are
	// lit, the far wall is not. At half the tank width the spill lit the whole
	// wall back up by exactly as much as the room dim took away.
	float reach = clamp(max(iaq_tank_box.x, iaq_tank_box.y) * 0.22, 1.2, 3.5);
	float fall = 1.0 / (1.0 + dist2 / (reach * reach));
	fall *= fall;
	return base_col * iaq_tank_glow.rgb * (iaq_tank_glow.a * facing * fall);
}

// ---- Occluder field (VISUAL_DIRECTIONS #4) ----------------------------------
//
// WHAT WAS MISSING. Shadow casting in this project reached exactly one
// surface: the substrate. `substrate_caustic.gdshader` took eight hardscape
// contact-AO footprints and a 16-slot fish blob buffer, and
// `shadow_audit.gd` existed to assert that gameplay uses blob shadows only.
// Nothing cast onto a plant, onto hardscape, onto another fish, or onto the
// glass, so the tank floated: driftwood read as a decal on the sand and a fish
// swimming under a leaf was as bright as one in open water.
//
// The buffer was already the right shape — a packed Nx1 data texture of
// (world position, radius) spheres. It was just a per-material uniform on two
// materials. Promoted to a global, every shader that samples the light can
// sample what blocks it, for one texelFetch loop.
//
//   iaq_occluder_tex  : 16x1 RGBAF, xyz = world centre, w = radius (0 = unused)
//   iaq_occluder_info : x = live count, y = gain, z/w spare
//
// gain 0 disables the whole path (potato tier, room-only shots), so a tank
// that does not want it pays one compare.
//
// COST. Up to 16 texelFetches plus a few ALU ops per lit fragment, on eight
// shaders. At the shipped 512x288 internal render that is ~2.4M fetches a
// frame, which is nothing on a desktop GPU and is why world.gd hands this a
// gain of 0 at shader_perf_tier >= 2 rather than trying to be clever. If it
// ever needs to be cheaper, the answer is a bounding test on the whole set,
// not a smaller set: the count is already the legibility budget.
global uniform sampler2D iaq_occluder_tex;
global uniform vec4 iaq_occluder_info;


// Fraction of the lamp that reaches `world_pos`. 1 = unshadowed.
float iaq_shadow(vec3 world_pos, vec3 light_pos) {
	float gain = iaq_occluder_info.y;
	int count = int(iaq_occluder_info.x);
	if (gain <= 0.001 || count <= 0) {
		return 1.0;
	}
	vec3 to_light = light_pos - world_pos;
	float light_dist = length(to_light);
	if (light_dist < 0.0001) {
		return 1.0;
	}
	vec3 L = to_light / light_dist;
	float occ = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) {
			break;
		}
		vec4 o = texelFetch(iaq_occluder_tex, ivec2(i, 0), 0);
		float r = o.w;
		if (r <= 0.001) {
			continue;
		}
		vec3 d = o.xyz - world_pos;
		float dist2 = dot(d, d);
		float rr = r * r;
		// SELF-SHADOW GUARD. A fragment inside an occluder sphere IS that
		// object — the fish's own blob would otherwise darken the top half of
		// every fish in the tank.
		if (dist2 < rr) {
			continue;
		}
		// Crossing the self-shadow sphere must not switch an entire voxel
		// between full shadow and full light. Feather just outside its radius;
		// squared distances avoid another square root in this fragment loop.
		float self_fade = smoothstep(rr, rr * 1.5625, dist2);
		float t = dot(d, L);
		// Only things BETWEEN the fragment and the lamp cast onto it.
		if (t <= 0.02 || t >= light_dist) {
			continue;
		}
		float perp2 = dist2 - t * t;
		if (perp2 >= rr) {
			continue;
		}
		// Soft edge: opaque through the sphere's centre line, feathered to
		// nothing at its silhouette.
		float k = (1.0 - sqrt(max(perp2, 0.0) / rr)) * self_fade;
		// Contact hardening. A leaf resting on the sand casts a sharp dark
		// shadow; the same leaf near the lamp casts a wide faint one. Without
		// this, every shadow in the tank has the same weight and the depth cue
		// the shadows exist to give is lost.
		float prox = 1.0 - clamp(t / light_dist, 0.0, 1.0);
		occ = max(occ, k * mix(0.30, 1.0, prox));
	}
	// Never fully black: a shadowed surface is lit by the rest of the tank.
	return 1.0 - clamp(occ * gain, 0.0, 0.88);
}


// How dark a face turned AWAY from the lamp goes while still inside the cone.
// Not 0: the unlit side of a leaf is in shadow, not absent.
const float IAQ_KEY_FLOOR = 0.62;


// One shared source/coverage calculation for surfaces, leaves, fish and water.
vec3 iaq_beam_source(vec3 world_pos) {
	vec3 src = iaq_beam_origin;
	if (iaq_beam_axis.w > 0.5) {
		vec3 ax = iaq_beam_axis.xyz;
		float len2 = dot(ax, ax);
		if (len2 > 1e-6) {
			src += ax * clamp(dot(world_pos - src, ax) / len2, -1.0, 1.0);
		}
	}
	return src;
}

vec4 iaq_beam_at(vec3 world_pos) {
	vec3 to_light = iaq_beam_source(world_pos) - world_pos;
	float dist = length(to_light);
	if (dist < 0.0001) {
		return vec4(0.0, 1.0, 0.0, 0.0);
	}
	vec3 L = to_light / dist;
	float cd = dot(-L, normalize(iaq_beam_dir));
	float cone = smoothstep(iaq_beam_cone.x, iaq_beam_cone.y, cd);
	cone *= 1.0 - smoothstep(iaq_beam_cone.z * 0.55, iaq_beam_cone.z, dist);
	if (iaq_beam_falloff.x > 0.0) {
		float exponent = iaq_beam_falloff.z;
		if (iaq_beam_falloff.w > 0.0) {
			exponent = mix(1.0, 2.0, smoothstep(iaq_beam_falloff.w, iaq_beam_falloff.w * 4.0, dist));
		}
		float ratio = iaq_beam_falloff.x * iaq_beam_falloff.x
			/ max(dist * dist + iaq_beam_falloff.y * iaq_beam_falloff.y, 1e-4);
		cone *= clamp(pow(ratio, exponent * 0.5), 0.0, 1.5);
	}
	return vec4(L, cone);
}

// Diffuse reflection preserves the surface pigment. Normalizing the normal
// with a guarded reciprocal avoids NaNs on billboard/point callers.
vec3 iaq_directional_light(vec3 pigment, vec3 n, vec4 source, vec3 tint) {
	if (source.w <= 0.0) {
		return vec3(0.0);
	}
	float ndl = dot(n, source.xyz);
	float wrap = clamp((ndl + 0.20) / 1.20, 0.0, 1.0);
	return pigment * tint * source.w * wrap * 0.22;
}

vec3 iaq_point_light(vec3 pigment, vec3 world_pos, vec3 n, vec4 source, vec4 tint) {
	if (source.w <= 0.0) {
		return vec3(0.0);
	}
	vec3 d = source.xyz - world_pos;
	float d2 = dot(d, d);
	vec3 L = d * inversesqrt(max(d2, 1e-4));
	float wrap = clamp((dot(n, L) + 0.25) / 1.25, 0.0, 1.0);
	float att = source.w / (1.0 + max(tint.w, 0.0) * d2);
	return pigment * tint.rgb * wrap * att * 0.65;
}

// Full form: cone falloff plus a directional key from the surface normal, plus
// a tight hot core where a face points straight back at the lamp.
//
// The key is what turns "a pool of light on the floor" into lighting. Without
// it every surface inside the cone gets the same multiplier and a plant reads
// as a flat green cutout standing in a bright patch; with it the leaves facing
// up catch the bar and the ones facing away fall off, which is the whole
// difference between a lit object and a tinted one.
//
// `world_normal` need not be normalised. Pass vec3(0.0) to skip the key.
vec3 iaq_beam_light_surface_n(vec3 world_pos, vec3 world_normal, vec3 base_col,
		float catch_opacity) {
	float energy = max(iaq_beam_cone.w, 0.0);
	vec4 sample_light = iaq_beam_at(world_pos);
	float cone = sample_light.w;
	vec3 n = world_normal * inversesqrt(max(dot(world_normal, world_normal), 1e-6));
	float ndl = 1.0;
	if (dot(world_normal, world_normal) > 1e-6) {
		ndl = max(dot(n, sample_light.xyz), 0.0);
	}
	// Shadow attenuates DIRECT light only — ambient is what fills a shadow in.
	float shadow = energy > 0.0 ? iaq_shadow(world_pos, iaq_beam_source(world_pos)) : 1.0;
	float spectrum_peak = max(max(iaq_beam_tint.r, iaq_beam_tint.g), iaq_beam_tint.b);
	float direct = cone * shadow * clamp(energy * max(spectrum_peak, 0.0) * 2.0, 0.0, 1.0)
		* iaq_tank_direct_mul(world_pos);
	float ambient = iaq_beam_tint.w * iaq_room_light * iaq_tank_ambient_mul(world_pos);
	float lit_side = mix(IAQ_KEY_FLOOR, 1.0, ndl);
	// Adding a source cannot darken an existing ambient reflection. Keep
	// the diffuse addition in the source spectrum, including a black RGB lamp.
	vec3 source_hue = iaq_beam_tint.rgb / max(spectrum_peak, 1e-4);
	vec3 lit = base_col * ambient
		+ base_col * source_hue * max(lit_side - ambient, 0.0) * direct;
	// Light reflects the surface pigment. A uniform white wash erased the
	// colour relationship between adjacent leaves, stones and markings.
	float pigment_luma = dot(base_col, vec3(0.299, 0.587, 0.114));
	vec3 pigment = mix(vec3(pigment_luma), base_col, 0.72);
	lit += pigment * iaq_beam_tint.rgb * direct * energy * 0.40;
	// Hot core: the term that lets a face turned up at the bar reach the
	// bright end of the palette, which nothing in the frame did before
	// (VISUAL_DIRECTIONS #3 — a measured p99 of 158 out of 255).
	//
	// Exponent 3, not 6. A bar fixture is a wide source and its specular is
	// correspondingly broad; at 6 the core only lit faces within about 30
	// degrees of pointing straight at the lamp, which in a planted tank is
	// almost nothing, and the frame kept its missing top end.
	// The core scales with sqrt(energy) below full power: a dimmed LED still
	// glints where a face turns straight at it - it is the pool around the
	// glint that dims. Linear energy left a 0.28 fixture no highlight at all.
	float core_e = energy < 1.0 ? sqrt(energy) : energy;
	lit += iaq_beam_tint.rgb * pow(ndl, 3.0) * direct * direct * core_e * 0.62
		* catch_opacity;
	lit *= iaq_tank_depth_gain(world_pos);
	lit += iaq_directional_light(pigment, n, iaq_sun_light, iaq_sun_tint.rgb);
	lit += iaq_directional_light(pigment, n, iaq_moon_light, iaq_moon_tint.rgb);
	lit += iaq_point_light(pigment, world_pos, n, iaq_accent1, iaq_accent1_tint);
	lit += iaq_point_light(pigment, world_pos, n, iaq_accent2, iaq_accent2_tint);
	lit += iaq_tank_spill(world_pos, world_normal, pigment);
	return lit;
}


vec3 iaq_beam_light_n(vec3 world_pos, vec3 world_normal, vec3 base_col) {
	return iaq_beam_light_surface_n(world_pos, world_normal, base_col, 1.0);
}


// Point form, no directional key. Kept for call sites where the normal is not
// meaningful (billboards, translucent sheets).
vec3 iaq_beam_light(vec3 world_pos, vec3 base_col) {
	return iaq_beam_light_n(world_pos, vec3(0.0), base_col);
}
