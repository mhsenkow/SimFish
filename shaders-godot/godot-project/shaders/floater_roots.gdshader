shader_type spatial;
// Floater root curtain (alive pass, 2026-09-30).
//
// WHY THIS EXISTS. In the reference photos a frogbit / water-lettuce mat is
// read from inside the tank almost entirely by its roots: a curtain of
// red-brown strands a third of the column long, each one furred with fine
// lateral hairs, swaying slowly and glowing where a lamp sits behind them.
// The old roots were 4-5 straight 0.05 boxes per plant - one draw call and
// one material each, swung stiffly by a node rotation at the sim tick - and
// they were hidden outright in dense mats, which is exactly the photo's case.
//
// One merged ribbon mesh per plant (floating_plant.gd _root_curtain), two
// crossed ribbons per strand so it has width from any yaw. The hairs are not
// geometry: the ribbon is wider than the strand and the fragment keeps only
// the core plus slanted barbs, so a curtain costs one draw call and a few
// hundred vertices. Sway is in the vertex stage, weighted by depth below the
// crown, so it runs at frame rate with no CPU cost.
//
// Mesh contract: UV.x = across the ribbon (-1..1), UV.y = along the strand
// (0 at the crown, 1 at the tip), UV2 = (strand phase, strand length),
// COLOR = linear root colour (crown -> red-brown -> tip).
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/palette_tint.gdshaderinc"
#include "res://shaders/beam_cone.gdshaderinc"

global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;

uniform float sway_amount : hint_range(0.0, 0.3) = 0.085;
uniform float sway_speed : hint_range(0.0, 3.0) = 0.75;
// 0 = bare strands, 1 = fully feathered.
uniform float hair_density : hint_range(0.0, 1.0) = 0.8;

varying vec3 v_world_pos;
varying float v_along;
varying float v_across;
varying float v_phase;
varying float v_len;

void vertex() {
	float d = UV.y;
	float len = UV2.y;
	float phase = UV2.x + dot(NODE_POSITION_WORLD.xz, vec2(1.7, 2.3));
	// The crown is held by the plant; the tip is free. pow keeps the upper
	// strand nearly still, the way a long root bends only low down.
	float amp = sway_amount * len * pow(d, 1.6);
	float t = TIME * sway_speed;
	VERTEX.x += sin(t + phase + d * 2.2) * amp;
	VERTEX.z += cos(t * 0.83 + phase * 1.3 + d * 1.7) * amp * 0.8;
	v_along = d;
	v_across = UV.x;
	v_phase = UV2.x;
	v_len = len;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = abs(v_across);
	// Core strand, thinning toward the tip.
	float core = step(u, mix(0.30, 0.16, v_along));
	// Feather barbs slant down and out from the core. Sparse at the crown
	// (young root), full along the body, fraying at the tip.
	float barb = fract(v_along * v_len * 13.0 - u * 0.9 + v_phase);
	float reach = mix(0.45, 1.0, smoothstep(0.04, 0.35, v_along));
	float hair = step(barb, 0.24) * step(u, reach) * step(0.5, hair_density + (1.0 - u) * 0.3);
	if (max(core, hair) < 0.5) {
		discard;
	}
	float fine = hair * (1.0 - core);
	// Hairs are thinner, so more of the light through them survives: paler.
	vec3 col = mix(COLOR.rgb, COLOR.rgb * 1.18 + vec3(0.03, 0.025, 0.02), fine);
	col = apply_category_palette_tint(col, iaq_palette_foliage, 0.0, 1.0, 0.0, 1.0);
	col = apply_water_column_ws(col, v_world_pos, CAMERA_POSITION_WORLD);
	// Roots are translucent: a lamp behind the curtain lights it through,
	// the hairs most of all. That glow is the strongest root cue in photos.
	if (iaq_backlight.w > 0.001) {
		vec3 bd = v_world_pos - iaq_backlight.xyz;
		float att = clamp(iaq_backlight.w / (1.0 + iaq_backlight_tint.a * dot(bd, bd)), 0.0, 1.0);
		col += iaq_backlight_tint.rgb * att * (0.30 + fine * 0.30) * (0.5 + col);
	}
	col = iaq_beam_light(v_world_pos, col);
	ALBEDO = col;
}
