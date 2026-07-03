// MultiMesh voxel shader — faceted cube shading with per-instance color.
//
// Identical look to voxel.gdshader, but the color comes from the MultiMesh's
// per-instance color buffer (COLOR) instead of an `albedo` uniform, so a single
// MultiMeshInstance3D can draw thousands of differently-colored voxels in one
// draw call. Used for plant roots / runners and any non-swaying voxel batch.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_top = 99.0;
uniform float fixture_water_floor = 0.0;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 v_inst_color;
varying vec3 v_world_pos;

void vertex() {
	// MultiMesh per-instance color arrives multiplied into COLOR.
	v_inst_color = COLOR.rgb;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;        // top
	} else if (n.y < -0.7) {
		f = 0.50;        // bottom
	} else if (abs(n.x) > 0.7) {
		f = 0.82;        // +X / -X sides
	} else {
		f = 0.68;        // +Z / -Z sides
	}
	vec3 col = v_inst_color * f;
	col = apply_category_palette_tint(col, iaq_palette_hardscape,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);
	if (tank_fixture_glow > 0.001 && v_world_pos.y < fixture_water_top - 0.05) {
		float span = max(fixture_water_top - fixture_water_floor, 0.5);
		float depth = clamp((fixture_water_top - v_world_pos.y) / span, 0.0, 1.0);
		float wash = (1.0 - depth * 0.42) * tank_fixture_glow;
		float top_catch = smoothstep(0.25, 0.88, n.y);
		col += tank_fixture_color * wash * mix(0.28, 0.50, top_catch);
		col *= 1.0 + wash * (0.50 + top_catch * 0.30);
	}
	ALBEDO = col;
}
