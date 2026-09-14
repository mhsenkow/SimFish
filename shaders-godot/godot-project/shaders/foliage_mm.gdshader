// MultiMesh foliage — hierarchy sway, under-leaf shade, GPU flutter.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float sway_speed = 1.6;
uniform float sway_phase_offset = 0.0;
uniform float sway_amplitude = 0.08;
// Distance sway fade — see foliage.gdshader. The tank renders into a
// 512x288 buffer with pixel snapping, so full world-space sway on a plant
// that covers a few pixels reads as those pixels jumping rather than
// as motion. Far foliage settles instead.
uniform float sway_fade_start = 6.0;
uniform float sway_fade_end = 16.0;
uniform float sway_fade_floor : hint_range(0.0, 1.0) = 0.12;
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
uniform float wet_sheen_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec4 gust_wave = vec4(0.0); // xyz origin, w radius
uniform vec3 gust_direction = vec3(1.0, 0.0, 0.0);
uniform float gust_age = 99.0;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.0;
uniform float gust_response : hint_range(0.0, 1.0) = 1.0;
uniform float red_potential : hint_range(0.0, 1.0) = 0.0;
uniform float golden_hour : hint_range(0.0, 1.0) = 0.0;
uniform vec3 foliage_light_dir = vec3(0.25, 0.8, 0.35);
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
#include "res://shaders/beam_cone.gdshaderinc"

varying vec3 v_inst_color;
varying vec3 v_world_pos;
varying float v_leaf_thickness;
varying float v_leaf_phase;
varying float v_light_dose;
// Per-instance bend weight.  Plant.gd writes this from the voxel's local
// height, making a ribbon's root stationary while its successive segments
// progressively yield to the current.
varying float v_flex_weight;

void vertex() {
	v_inst_color = COLOR.rgb;
	v_leaf_thickness = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	v_leaf_phase = INSTANCE_CUSTOM.g * 6.2831853;
	v_light_dose = clamp(INSTANCE_CUSTOM.b, 0.0, 1.0);
	v_flex_weight = clamp(INSTANCE_CUSTOM.a, 0.0, 1.0);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;

	// Local bend weight is the important difference between a shader wobble
	// and a rooted plant: every blade starts pinned at the substrate, then its
	// successive voxel segments lag farther behind in the current.
	float height_factor = pow(v_flex_weight, 1.42) * tip_sway_mult;

	// Settle distant foliage so it does not pixel-jitter.
	float view_dist = length((VIEW_MATRIX * vec4(world_pos, 1.0)).xyz);
	float dist_fade = mix(1.0, sway_fade_floor,
		smoothstep(sway_fade_start, sway_fade_end, view_dist));

	float time_sway = TIME * sway_speed + sway_phase_offset + v_leaf_phase;
	float phase = world_pos.x * 0.4 + world_pos.z * 0.3
		+ sway_phase_offset * 0.37 + v_leaf_phase + v_flex_weight * 2.35;
	// A travelling phase, rather than every segment swinging together, makes
	// long ribbons describe a slow S-curve through the water.
	float sway = sin(time_sway + phase) * sway_amplitude * height_factor * dist_fade;
	vec2 flow_xz = flow_dir.xz;
	float flow_len = length(flow_xz);
	if (flow_len > 0.0001 && flow_strength > 0.001) {
		vec2 current_dir = flow_xz / flow_len;
		float current_phase = dot(world_pos.xz, current_dir) * 0.72
			- TIME * (0.52 + flow_strength * 0.72) + v_leaf_phase * 0.55
			+ v_flex_weight * 2.8;
		float current_pulse = 0.44 + sin(current_phase) * 0.26;
		VERTEX.xz += current_dir * current_pulse * flow_strength
			* sway_amplitude * height_factor * dist_fade;
	}
	float gust_dist = distance(world_pos.xz, gust_wave.xz);
	float gust_front = 1.0 - smoothstep(0.0, max(gust_wave.w * 0.22, 0.01),
		abs(gust_dist - gust_age * max(gust_wave.w, 0.01) * 0.72));
	float gust_fade = 1.0 - smoothstep(0.0, 2.2, gust_age);
	vec2 gust_push = normalize(gust_direction.xz + vec2(0.0001)) * gust_front
		* gust_fade * gust_strength * gust_response * height_factor * 0.11 * dist_fade;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.35;
	VERTEX.xz += gust_push;

	float time_flutter = TIME * flutter_speed + sway_phase_offset * 1.15 + v_leaf_phase;
	float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0
		+ sway_phase_offset * 0.61 + v_leaf_phase * 1.7;
	float flutter = sin(time_flutter + phase_flutter) * flutter_amplitude * dist_fade;
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
	vec3 anthocyanin = vec3(col.r * 1.18 + 0.10, col.g * 0.52, col.b * 0.62 + 0.04);
	col = mix(col, anthocyanin, red_potential * v_light_dose * 0.58);
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
	float wet_band = 1.0 - smoothstep(0.03, 0.16, abs(v_world_pos.y - water_surface_y));
	float wet_view = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.0);
	col += vec3(0.16, 0.20, 0.22) * wet_band * wet_view * wet_sheen_strength;
	float sun_edge = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.5)
		* max(dot(n, normalize(-foliage_light_dir)), 0.0);
	col += vec3(0.18, 0.085, 0.025) * sun_edge * golden_hour;
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
	// Shaped lamp. In an unshaded pipeline nothing responds to a light on
	// its own, so the cone is evaluated here - this is what puts the beam
	// ON the leaves instead of only in the water in front of them.
	col = iaq_beam_light_n(v_world_pos, (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz, col);
	ALBEDO = col;
}
