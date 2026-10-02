shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;

uniform float alpha_scale : hint_range(0.0, 1.0) = 0.62;
uniform float water_surface_y = 99.0;
// Same PlantSkeleton rest pose as foliage_mm, so a yellowing leaf stays on
// its bent stem (static part only - dying leaves hang, they do not sway).
uniform vec2 chain_bend = vec2(0.0);

#include "res://shaders/palette_tint.gdshaderinc"
#include "res://shaders/beam_cone.gdshaderinc"

varying vec3 v_color;
varying vec3 v_world_pos;

void vertex() {
	v_color = COLOR.rgb;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.g * 6.2831853;
	float sway = sin(TIME * 1.15 + phase + v_world_pos.x * 0.35) * 0.025;
	VERTEX.x += sway * max(VERTEX.y + 0.3, 0.0);
	if (dot(chain_bend, chain_bend) > 1e-8) {
		float cs = clamp(INSTANCE_CUSTOM.a, 0.0, 1.0);
		vec2 coff = chain_bend * cs * cs * (3.0 - cs) * 0.5;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(coff.x, 0.0, coff.y);
	}
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float face = n.y > 0.7 ? 1.0 : (n.y < -0.7 ? 0.50 : 0.70);
	vec3 amber = v_color * vec3(1.08, 0.88, 0.55) * face;
	amber = apply_category_palette_tint(amber, iaq_palette_foliage, 0.0, 0.92, 0.08, 1.0);
	// Analytic fixture cone (VISUAL_DIRECTIONS #1) — dying leaves live in the
	// same light as living ones.
	amber = iaq_beam_light_n(v_world_pos, (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz, amber);
	ALBEDO = apply_water_column_ws(amber, v_world_pos, CAMERA_POSITION_WORLD);
	ALPHA = alpha_scale;
}
