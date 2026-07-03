// MultiMesh foliage — hierarchy sway, under-leaf shade, GPU flutter.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float sway_speed = 1.6;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;
uniform float tip_sway_mult : hint_range(1.0, 3.0) = 2.1;
uniform float canopy_shade : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_floor = 0.0;
// Subsurface rim — same warm translucent rim as foliage.gdshader so the
// node-based and MultiMesh paths look identical.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec3 sss_color : source_color = vec3(1.00, 0.92, 0.68);
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 v_inst_color;
varying vec3 v_world_pos;

void vertex() {
	v_inst_color = COLOR.rgb;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;

	float height_norm = clamp((world_pos.y - 0.5) / max(water_surface_y - 0.5, 1.0), 0.0, 1.0);
	float height_factor = height_norm * height_norm * tip_sway_mult;

	float time_sway = TIME * sway_speed;
	float phase = world_pos.x * 0.4 + world_pos.z * 0.3;
	float sway = sin(time_sway + phase) * sway_amplitude * height_factor;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.35;

	float time_flutter = TIME * flutter_speed;
	float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0;
	float flutter = sin(time_flutter + phase_flutter) * flutter_amplitude;
	VERTEX.y += flutter * height_factor * 0.3;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.50;
	} else if (abs(n.x) > 0.7) {
		f = 0.82;
	} else {
		f = 0.68;
	}
	vec3 col = v_inst_color * f;
	col = apply_category_palette_tint(col, iaq_palette_foliage,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);
	// Under broad canopies / lily pads — dim lower-facing leaf pixels.
	if (n.y < -0.2 && v_world_pos.y > water_surface_y - 0.6) {
		col *= 1.0 - canopy_shade * 0.38 * (1.0 - daylight * 0.35);
	}
	// Subsurface rim — thin grazing-angle warm halo. Day-tracked so the
	// effect peaks at midday when real backlight is strongest and fades
	// to almost nothing at night.
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	float lit = max(daylight, tank_fixture_glow * 0.85);
	col = mix(col, col * 0.7 + sss_color * 0.55, rim * sss_strength * (0.4 + 0.6 * lit));
	if (tank_fixture_glow > 0.001 && v_world_pos.y < water_surface_y - 0.05) {
		float span = max(water_surface_y - fixture_water_floor, 0.5);
		float depth = clamp((water_surface_y - v_world_pos.y) / span, 0.0, 1.0);
		float wash = (1.0 - depth * 0.38) * tank_fixture_glow;
		float top_catch = smoothstep(0.20, 0.88, n.y);
		col += tank_fixture_color * wash * mix(0.30, 0.55, top_catch);
		col *= 1.0 + wash * (0.62 + top_catch * 0.42);
	}
	ALBEDO = col;
}
