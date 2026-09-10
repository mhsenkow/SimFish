// MultiMesh foliage — hierarchy sway, under-leaf shade, GPU flutter.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float sway_speed = 1.6;
uniform float sway_phase_offset = 0.0;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;
uniform float tip_sway_mult : hint_range(1.0, 3.0) = 2.1;
uniform float canopy_shade : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 flow_dir = vec3(0.0, 0.0, 1.0);
uniform float flow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_floor = 0.0;
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
// Subsurface rim — same warm translucent rim as foliage.gdshader so the
// node-based and MultiMesh paths look identical.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec3 sss_color : source_color = vec3(1.00, 0.94, 0.62);
uniform float backlight_boost : hint_range(0.0, 1.0) = 0.55;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 v_inst_color;
varying vec3 v_world_pos;
varying float v_leaf_thickness;

void vertex() {
	v_inst_color = COLOR.rgb;
	v_leaf_thickness = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;

	float height_norm = clamp((world_pos.y - 0.5) / max(water_surface_y - 0.5, 1.0), 0.0, 1.0);
	// Gentle power curve: flexible mid-column, soft tip — avoids squared tip whip.
	float height_factor = pow(height_norm, 1.35) * tip_sway_mult;

	float time_sway = TIME * sway_speed + sway_phase_offset;
	float phase = world_pos.x * 0.4 + world_pos.z * 0.3 + sway_phase_offset * 0.37;
	float flow_push = dot(flow_dir, vec3(world_pos.x, 0.0, world_pos.z)) * flow_strength * 0.12;
	float sway = (sin(time_sway + phase) + flow_push) * sway_amplitude * height_factor;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.35;

	float time_flutter = TIME * flutter_speed + sway_phase_offset * 1.15;
	float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0 + sway_phase_offset * 0.61;
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
	// Bounded two-wave caustic shared with voxel.gdshader. This deliberately
	// stays cheaper than the substrate Worley web and is disabled on low tier.
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
	// Subsurface rim — thin grazing-angle warm halo. Day-tracked so the
	// effect peaks at midday when real backlight is strongest and fades
	// to almost nothing at night.
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	float lit = max(daylight, tank_fixture_glow * 0.85);
	// REAL_TANK_FIDELITY #121 — backlit translucency: veins darker, thin blade luminous.
	float thin_transmission = mix(1.0, 0.28, v_leaf_thickness);
	float backlit = pow(max(-dot(n, VIEW), 0.0), 1.8) * backlight_boost * lit
		* thin_transmission;
	col = mix(col, col * 0.55 + sss_color * 0.85, backlit * 0.65);
	col = mix(col, col * 0.7 + sss_color * 0.55,
		rim * sss_strength * (0.4 + 0.6 * lit) * thin_transmission);
	// Vein darkening through the luminous blade.
	float vein = step(0.82, fract(v_world_pos.y * 7.0 + v_world_pos.x * 3.0));
	col *= 1.0 - vein * backlit * 0.18;
	if (tank_fixture_glow > 0.001 && v_world_pos.y < water_surface_y - 0.05) {
		float span = max(water_surface_y - fixture_water_floor, 0.5);
		float depth = clamp((water_surface_y - v_world_pos.y) / span, 0.0, 1.0);
		float wash = (1.0 - depth * 0.38) * tank_fixture_glow;
		float top_catch = smoothstep(0.20, 0.88, n.y);
		col += tank_fixture_color * wash * mix(0.30, 0.55, top_catch);
		col *= 1.0 + wash * (0.62 + top_catch * 0.42);
	}
	// Water column — red dies first with depth and distance. Global uniform, so
	// it costs one compare on anything above the waterline or out of the tank.
	col = apply_water_column(col, v_world_pos.y, length(VERTEX));
	ALBEDO = col;
}
