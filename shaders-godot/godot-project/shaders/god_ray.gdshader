shader_type spatial;
// Default depth_test is ON — opaque geometry in front of the beam (the
// front glass, substrate, fish, plants) culls beam pixels at the fragment
// stage, giving correct silhouette occlusion. `depth_draw_never` means
// the beam itself doesn't write depth, so it never occludes anything
// drawn after it.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 beam_color : source_color = vec4(0.55, 0.75, 1.0, 0.08);
uniform float speed : hint_range(0.1, 5.0) = 1.0;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.8;
uniform float edge_fade : hint_range(0.0, 1.0) = 0.06;
uniform float falloff_exponent : hint_range(1.0, 5.0) = 1.2;
uniform float occlusion : hint_range(0.0, 1.0) = 0.0;
// Forward-scatter anisotropy. Real underwater god rays brighten when
// viewed along the beam axis (Henyey-Greenstein g>0). Default 0.5 gives
// a noticeable boost when looking down the shaft without overwhelming
// the side-on read.
uniform float forward_scatter : hint_range(0.0, 1.0) = 0.5;
// How much the beam dissipates as it travels down through the water
// column. 0 = uniform brightness top-to-bottom (old behavior). 1 = fully
// extinct at the substrate. Real underwater shafts dim with depth as
// suspended particulates scatter the light away — 0.7 reads as a soft
// fall-off that still hits the substrate visibly.
uniform float depth_dissipation : hint_range(0.0, 1.0) = 0.7;
// Per-fish soft occluders. xyz = world position, w = effective radius.
// w == 0 marks an unused slot. World.gd refreshes the active 8 closest
// fish per visual tick so this is cheap to evaluate per fragment.
uniform vec4 occluders[8];
uniform float occluder_strength : hint_range(0.0, 1.0) = 0.65;

varying vec3 local_pos;
varying vec3 world_vertex;

void vertex() {
	local_pos = VERTEX;
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// UV.y is 0 at the top (light source) and 1 at the bottom (substrate).
	float v_y = UV.y;

	// Fresnel — beam edges fade to transparent so the polygonal cylinder
	// silhouette blends instead of showing a hard outline. Exponent kept
	// modest (1.2) so the beam reads as a full shaft, not only a grazing
	// glint at the edges.
	float fresnel = abs(dot(NORMAL, VIEW));

	// Asymmetric vertical falloff: brightest right at the lamp, dimming
	// smoothly as it descends through the water. Replaces the old
	// symmetric "fade at both ends" that left the middle of the shaft
	// the brightest part — visually wrong because real shafts get
	// brighter the closer they are to the lamp.
	float dissipation = mix(1.0, 1.0 - smoothstep(0.0, 1.0, v_y), depth_dissipation);
	float top_seal = smoothstep(0.0, edge_fade, v_y);              // hide the cap
	float bottom_seal = 1.0 - smoothstep(1.0 - edge_fade, 1.0, v_y); // soft end
	float vertical_curve = top_seal * bottom_seal * dissipation;

	float u_angle = UV.x * 2.0 * 3.14159265;
	vec2 circle_coord = vec2(cos(u_angle), sin(u_angle));
	float time = TIME * speed;
	// Two drifting octaves: a broad slow striation and a finer, faster sparkle
	// travelling DOWN the shaft (the v_y - time term) so the light visibly
	// pours downward like real suspended-particle scatter, not a static grid.
	float n1 = sin(circle_coord.x * noise_scale + time) *
	           cos(circle_coord.y * noise_scale - time * 0.7) *
	           sin(v_y * noise_scale * 2.0 - time * 1.3);
	float n2 = sin(circle_coord.x * noise_scale * 2.3 - time * 1.7) *
	           sin(v_y * noise_scale * 4.1 - time * 2.4);
	float noise = n1 * 0.7 + n2 * 0.3;
	// Wider shimmer range than the old 0.875..1.0 — beams in real water
	// have visibly stronger highlight/shadow striations from surface
	// caustics; this brings the swing to ~0.68..1.12.
	float shimmer = 0.90 + 0.22 * noise;

	// Forward scatter — the cylinder's local +Y is the beam axis. Brighter
	// when the camera is looking along the beam, dimmer side-on.
	vec3 beam_axis_world = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float scatter = abs(dot(beam_axis_world, normalize(VIEW)));
	float scatter_boost = mix(1.0, 1.0 + scatter * 0.85, forward_scatter);

	float alpha = beam_color.a * pow(fresnel, falloff_exponent) * vertical_curve * shimmer * scatter_boost;
	alpha *= 1.0 - occlusion * 0.72;

	float fish_block = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 oc = occluders[i];
		if (oc.w < 0.001) {
			continue;
		}
		float d = distance(world_vertex, oc.xyz);
		fish_block = max(fish_block, smoothstep(oc.w, oc.w * 0.35, d));
	}
	alpha *= 1.0 - fish_block * occluder_strength;

	ALBEDO = beam_color.rgb;
	ALPHA = alpha;
}
