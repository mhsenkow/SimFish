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
// xyz = half-extent vector along a LINE fixture, w > 0.5 marks it a line.
//
// A bar light is not a point. world.gd builds it as four SpotLights spaced
// along the housing and the globals only ever carried the first of them, so
// the "cone" for the commonest fixture in the game was a 42-degree spot
// hanging off the left end of the bar. Carrying the axis lets the same maths
// treat the fixture as a segment: the cone is measured from the nearest point
// ON the bar, which is what a bar actually does.
global uniform vec4 iaq_beam_axis;

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
		float k = 1.0 - sqrt(perp2 / rr);
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
vec3 iaq_beam_light_n(vec3 world_pos, vec3 world_normal, vec3 base_col) {
	float energy = iaq_beam_cone.w;
	if (energy <= 0.001) {
		return base_col;
	}
	vec3 src_pos = iaq_beam_origin;
	if (iaq_beam_axis.w > 0.5) {
		vec3 ax = iaq_beam_axis.xyz;
		float len2 = dot(ax, ax);
		if (len2 > 1e-6) {
			float t_ax = clamp(dot(world_pos - iaq_beam_origin, ax) / len2, -1.0, 1.0);
			src_pos = iaq_beam_origin + ax * t_ax;
		}
	}
	vec3 to_frag = world_pos - src_pos;
	float dist = length(to_frag);
	float cone = 0.0;
	if (dist > 0.0001) {
		float cd = dot(to_frag / dist, normalize(iaq_beam_dir));
		cone = smoothstep(iaq_beam_cone.x, iaq_beam_cone.y, cd);
		float reach = iaq_beam_cone.z;
		cone *= 1.0 - smoothstep(reach * 0.55, reach, dist);
	}
	float ndl = 1.0;
	if (dot(world_normal, world_normal) > 1e-6 && dist > 0.0001) {
		ndl = max(dot(normalize(world_normal), -to_frag / dist), 0.0);
	}
	// Shadow attenuates DIRECT light only — ambient is what fills a shadow in.
	float shadow = iaq_shadow(world_pos, src_pos);
	float direct = cone * shadow;
	float ambient = iaq_beam_tint.w;
	float lit_side = mix(IAQ_KEY_FLOOR, 1.0, ndl);
	vec3 lit = base_col * mix(ambient, lit_side, direct);
	// Wash: the lamp's own colour spread across everything it reaches.
	lit += iaq_beam_tint.rgb * direct * energy * 0.30;
	// Hot core: the term that lets a face turned up at the bar reach the
	// bright end of the palette, which nothing in the frame did before
	// (VISUAL_DIRECTIONS #3 — a measured p99 of 158 out of 255).
	//
	// Exponent 3, not 6. A bar fixture is a wide source and its specular is
	// correspondingly broad; at 6 the core only lit faces within about 30
	// degrees of pointing straight at the lamp, which in a planted tank is
	// almost nothing, and the frame kept its missing top end.
	lit += iaq_beam_tint.rgb * pow(ndl, 3.0) * direct * direct * energy * 0.62;
	return lit;
}


// Point form, no directional key. Kept for call sites where the normal is not
// meaningful (billboards, translucent sheets).
vec3 iaq_beam_light(vec3 world_pos, vec3 base_col) {
	return iaq_beam_light_n(world_pos, vec3(0.0), base_col);
}
