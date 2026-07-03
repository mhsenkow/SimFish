// Fauna MultiMesh voxel shader — per-instance COLOR.rgb replaces per-color materials.
// Same look as voxel.gdshader fauna path; one shared material per fish batch.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float color_vibrancy : hint_range(0.5, 2.0) = 1.24;
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_floor = 0.0;
uniform float belly_flash : hint_range(0.0, 1.0) = 0.0;
uniform float bioluminescence : hint_range(0.0, 1.0) = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.65, 0.85, 1.0);
uniform float room_haze_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 room_haze_color : source_color = vec3(0.92, 0.84, 0.74);
uniform float room_haze_near : hint_range(0.0, 40.0) = 8.0;
uniform float room_haze_far : hint_range(2.0, 80.0) = 28.0;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sss_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float irid_strength : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_strength : hint_range(0.0, 1.0) = 0.0;
uniform float fin_translucency : hint_range(0.0, 1.0) = 0.0;
uniform float fauna_rim : hint_range(0.0, 1.0) = 0.0;
uniform float fauna_vertex_bend : hint_range(0.0, 1.0) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

vec3 apply_vibrancy(vec3 col, float vib) {
	if (vib <= 1.001) {
		return col;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = 1.0 + (vib - 1.0) * 0.75;
	col = mix(vec3(luma), col, sat);
	return col * (1.0 + (vib - 1.0) * 0.10);
}

varying vec3 v_inst_color;
varying vec3 v_world_pos;
varying vec4 v_inst_custom;

void vertex() {
	v_inst_color = COLOR.rgb;
	v_inst_custom = INSTANCE_CUSTOM;
	// PERFORMANCE #68 — micro wag in the vertex stage; pivot nodes carry macro bend.
	float bend_w = v_inst_custom.r * fauna_vertex_bend;
	float phase = TIME * 6.2 + VERTEX.z * 1.35;
	VERTEX.x += sin(phase) * bend_w * abs(VERTEX.z) * 0.11;
	VERTEX.y += cos(phase * 0.85) * bend_w * 0.03;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float belly_local = max(belly_flash, v_inst_custom.g);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.58 + belly_local * 0.35;
	} else if (abs(n.x) > 0.7) {
		f = 0.88;
	} else {
		f = 0.76;
	}
	vec3 col = v_inst_color * f;
	col = apply_category_palette_tint(col, iaq_palette_fauna,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);
	col = apply_vibrancy(col, color_vibrancy + v_inst_custom.b * 0.32);

	if (aquatic_caustic_intensity > 0.001 && v_world_pos.y < water_surface_y - 0.08) {
		vec2 cuv = v_world_pos.xz * 1.12;
		float t = TIME * 0.76 + day_phase_offset * 6.28318;
		float cwave = sin(cuv.x * 2.0 + t) * sin(cuv.y * 1.65 - t * 0.9)
			+ sin((cuv.x + cuv.y) * 1.3 + t);
		float caustics = smoothstep(0.08, 0.75, cwave) * aquatic_caustic_intensity;
		col += aquatic_light_color * caustics * 0.22;
		float shim = sin(v_world_pos.x * 4.2 + t * 2.1) * aquatic_shimmer * 0.035;
		col += vec3(shim, shim * 0.6, -shim * 0.4);
	}

	if (tank_fixture_glow > 0.001 && v_world_pos.y < water_surface_y - 0.05) {
		float span = max(water_surface_y - fixture_water_floor, 0.5);
		float depth = clamp((water_surface_y - v_world_pos.y) / span, 0.0, 1.0);
		float wash = (1.0 - depth * 0.40) * tank_fixture_glow;
		float top_catch = smoothstep(0.25, 0.88, n.y);
		col += tank_fixture_color * wash * mix(0.34, 0.62, top_catch);
		col *= 1.0 + wash * (0.58 + top_catch * 0.38);
	}

	if (bioluminescence > 0.001 || v_inst_custom.r > 0.001) {
		float biolum_local = max(bioluminescence, v_inst_custom.r);
		float pulse = 0.65 + 0.35 * sin(TIME * 1.8
			+ v_world_pos.x * 0.7 + v_world_pos.z * 0.5);
		vec3 glow_tint = biolum_color;
		if (length(biolum_color) < 0.01) {
			glow_tint = v_inst_color;
		}
		col += glow_tint * biolum_local * pulse * 0.55;
	}

	if (room_haze_strength > 0.001) {
		float view_z = -VERTEX.z;
		float fog = smoothstep(room_haze_near, room_haze_far, view_z) * room_haze_strength;
		col = mix(col, room_haze_color, fog);
	}

	if (sss_strength > 0.001) {
		float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
		col = mix(col, col * 0.75 + sss_color * 0.5, rim * sss_strength);
	}
	if (fin_translucency > 0.001) {
		float fin_rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.0);
		col = mix(col, col * 0.52 + sss_color * 0.42, fin_rim * fin_translucency);
		col *= 1.0 - fin_translucency * 0.10;
	}
	if (irid_strength > 0.001 || v_inst_custom.a > 0.001) {
		float irid_local = max(irid_strength, v_inst_custom.a);
		float fres = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.5);
		float step_f = floor(fres * 6.0) / 6.0;
		float band = step_f * 6.28318;
		vec3 sheen = vec3(0.5 + 0.5 * sin(band),
			0.5 + 0.5 * sin(band + 2.094),
			0.5 + 0.5 * sin(band + 4.188));
		col = mix(col, col * (0.65 + 0.7 * sheen), irid_local * step_f);
	}
	if (metallic_strength > 0.001) {
		float fres_m = pow(1.0 - abs(dot(n, normalize(VIEW))), 3.0);
		vec3 vdir = normalize(VIEW);
		float spec = pow(max(dot(n, normalize(vdir + vec3(0.25, 0.55, 0.18))), 0.0), 14.0);
		float band_m = floor(fres_m * 3.0) / 3.0;
		col += vec3(spec * 0.42) * metallic_strength;
		col = mix(col, col * vec3(1.12, 1.10, 1.06), band_m * metallic_strength * 0.35);
	}
	if (fauna_rim > 0.001) {
		float view_edge = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 1.75);
		float side_edge = 1.0 - abs(n.y);
		float ink = view_edge * mix(0.48, 1.0, side_edge);
		col = mix(col, col * 0.26, ink * fauna_rim);
	}

	ALBEDO = col;
}
