// Faceted voxel shading + optional underwater caustics / shimmer.

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float color_vibrancy : hint_range(0.5, 2.0) = 1.0;
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
// Top-down aquarium fixture wash — unshaded voxels don't receive SpotLights,
// so at night we fake the LED bar as a vertical gradient + top-face catch.
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_floor = 0.0;
uniform float belly_flash : hint_range(0.0, 1.0) = 0.0;
// Bioluminescence — fish.gd raises this at night for is_bioluminescent
// individuals. 0 = no glow (day or non-bioluminescent), up to 1 = soft
// halo. Reads as direct emission against the unshaded voxel face.
uniform float bioluminescence : hint_range(0.0, 1.0) = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.65, 0.85, 1.0);
// Room haze — view-distance fog that fades the voxel's color toward a
// warm tint. Default 0 (no fog) keeps in-tank voxels crisp; room
// materials set this to ~0.6 so the desk/wall geometry recedes behind
// the tank visually. Tuned in view-space metres.
uniform float room_haze_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 room_haze_color : source_color = vec3(0.92, 0.84, 0.74);
uniform float room_haze_near : hint_range(0.0, 40.0) = 8.0;
uniform float room_haze_far : hint_range(2.0, 80.0) = 28.0;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;
// Fauna-only structural colour (experimental). Default 0 = no-op, so non-fauna
// voxels and the legacy look are unchanged; VoxelMat.make_fauna raises these
// when TankConfig.experimental_visuals is on.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sss_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float irid_strength : hint_range(0.0, 1.0) = 0.0;

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

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.58 + belly_flash * 0.35;
	} else if (abs(n.x) > 0.7) {
		f = 0.88;
	} else {
		f = 0.76;
	}
	vec3 col = albedo.rgb * f;
	col = apply_global_palette_tint(col, palette_hue_shift, palette_saturation,
		palette_warmth, palette_value);
	col = apply_vibrancy(col, color_vibrancy);

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

	// Bioluminescence — soft pulsing additive glow. Pulse phase keyed off
	// world_pos so different voxels on the same fish breathe slightly out
	// of sync, giving a living-organism feel rather than a uniform lamp.
	if (bioluminescence > 0.001) {
		float pulse = 0.65 + 0.35 * sin(TIME * 1.8
			+ v_world_pos.x * 0.7 + v_world_pos.z * 0.5);
		col += biolum_color * bioluminescence * pulse * 0.55;
	}

	// Room depth haze — lerp toward warm haze colour by view distance.
	// view_z is positive forward; smoothstep over [near, far] gives a
	// 0→1 fog factor scaled by room_haze_strength. Default strength 0
	// makes this a no-op for tank voxels.
	if (room_haze_strength > 0.001) {
		float view_z = -VERTEX.z;
		float fog = smoothstep(room_haze_near, room_haze_far, view_z) * room_haze_strength;
		col = mix(col, room_haze_color, fog);
	}

	// Subsurface rim — warm translucent edge at grazing view angles (ported from
	// foliage.gdshader). Reads as living flesh catching light. No-op at strength 0.
	if (sss_strength > 0.001) {
		float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
		col = mix(col, col * 0.75 + sss_color * 0.5, rim * sss_strength);
	}
	// Iridescent / structural colour — subtle view-angle hue shimmer (thin-film,
	// ported from the glass biofilm). Jewel-like sheen on scales. No-op at 0.
	if (irid_strength > 0.001) {
		float fres = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.5);
		float band = fres * 6.28318;
		vec3 sheen = vec3(0.5 + 0.5 * sin(band),
			0.5 + 0.5 * sin(band + 2.094),
			0.5 + 0.5 * sin(band + 4.188));
		col = mix(col, col * (0.65 + 0.7 * sheen), irid_strength * fres);
	}

	ALBEDO = col;
}
