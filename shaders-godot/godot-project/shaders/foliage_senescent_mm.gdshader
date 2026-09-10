shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;

uniform float alpha_scale : hint_range(0.0, 1.0) = 0.62;
uniform float water_surface_y = 99.0;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 v_color;
varying vec3 v_world_pos;

void vertex() {
	v_color = COLOR.rgb;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.g * 6.2831853;
	float sway = sin(TIME * 1.15 + phase + v_world_pos.x * 0.35) * 0.025;
	VERTEX.x += sway * max(VERTEX.y + 0.3, 0.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float face = n.y > 0.7 ? 1.0 : (n.y < -0.7 ? 0.58 : 0.76);
	vec3 amber = v_color * vec3(1.08, 0.88, 0.55) * face;
	amber = apply_category_palette_tint(amber, iaq_palette_foliage, 0.0, 0.92, 0.08, 1.0);
	ALBEDO = apply_water_column(amber, v_world_pos.y, length(VERTEX));
	ALPHA = alpha_scale;
}
