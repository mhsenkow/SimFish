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


// Multiplier + additive glow for a world-space point.
// Returns rgb scale in .rgb and is applied by the caller.
vec3 iaq_beam_light(vec3 world_pos, vec3 base_col) {
	float energy = iaq_beam_cone.w;
	if (energy <= 0.001) {
		return base_col;
	}
	vec3 to_frag = world_pos - iaq_beam_origin;
	float dist = length(to_frag);
	float cone = 0.0;
	if (dist > 0.0001) {
		float cd = dot(to_frag / dist, normalize(iaq_beam_dir));
		// cos_outer is the wider (smaller cosine) edge; smoothstep between
		// them gives the soft-but-defined rim a real lamp has.
		cone = smoothstep(iaq_beam_cone.x, iaq_beam_cone.y, cd);
		// Reach. Past the lamp's range the cone stops rather than lighting
		// the whole room behind the tank.
		float reach = iaq_beam_cone.z;
		cone *= 1.0 - smoothstep(reach * 0.55, reach, dist);
	}
	// Outside the cone we fall toward `ambient`, which is what produces the
	// dark half. Inside, the lamp's own tint is added on top.
	float ambient = iaq_beam_tint.w;
	vec3 lit = base_col * mix(ambient, 1.0, cone);
	return lit + iaq_beam_tint.rgb * cone * energy * 0.30;
}
