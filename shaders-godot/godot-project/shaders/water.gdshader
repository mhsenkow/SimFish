// Voxel-aquarium water volume — depth tint, dual ripples, meniscus, caustics, fog.

shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.62, 0.66, 0.12);
uniform vec4 deep_color : source_color = vec4(0.04, 0.10, 0.14, 0.22);
uniform vec4 tint_color : source_color = vec4(0.83, 0.55, 0.25, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float bloom_haze : hint_range(0.0, 1.0) = 0.0;
uniform float wave_amplitude : hint_range(0.0, 0.12) = 0.028;
uniform float wave2_amplitude : hint_range(0.0, 0.08) = 0.012;
uniform float wave_speed = 0.85;
uniform float wave_scale = 0.42;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 0.55;
uniform vec3 light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float water_floor_y = 1.0;
uniform float water_surface_y = 6.5;
uniform float depth_fog : hint_range(0.0, 1.0) = 0.45;
// Posterize the depth fog into discrete bands instead of a smooth
// gradient — keeps the look consistent with the 48-color palette and
// makes the depth dropoff read as a chunky pixel-art lineweight
// rather than blended ramp. 0 = smooth (legacy); 1 = fully posterized.
uniform float depth_fog_bands : hint_range(0.0, 1.0) = 0.75;
uniform int depth_fog_band_count : hint_range(2, 12) = 6;
uniform float day_phase_offset = 0.0;
uniform float ice_lens : hint_range(0.0, 1.0) = 0.0;
uniform float moonlight : hint_range(0.0, 1.0) = 0.0;
uniform float sunset_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float tank_shape_id : hint_range(0.0, 3.0) = 0.0;
// Bacterial bloom — milky pale cast during the early cycling phase.
// Real tanks during ammonia-spike cycles look hazy white as
// heterotrophic bacteria explode and fail to colonize substrate. Clears
// once the cycle establishes and ammonia drops.
uniform float bacterial_bloom : hint_range(0.0, 1.0) = 0.0;
uniform vec3 bloom_color : source_color = vec3(0.92, 0.94, 0.96);

varying vec3 world_pos;
varying float surface_lift;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	vec3 n = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	surface_lift = 0.0;
	if (n.y > 0.45) {
		float w1 = sin(wp.x * wave_scale + TIME * wave_speed)
			* cos(wp.z * wave_scale * 0.91 - TIME * wave_speed * 0.74);
		float w2 = sin(wp.x * wave_scale * 1.55 - TIME * wave_speed * 1.05)
			* sin(wp.z * wave_scale * 1.35 + TIME * wave_speed * 0.88);
		float w3 = sin(wp.x * wave_scale * 3.2 + TIME * wave_speed * 2.1)
			* cos(wp.z * wave_scale * 2.8 - TIME * wave_speed * 1.9);
		surface_lift = wave_amplitude * (w1 * 0.52 + w2 * 0.33)
			+ wave2_amplitude * w3;
		VERTEX.y += surface_lift;
	}
}

void fragment() {
	float depth_span = max(water_surface_y - water_floor_y, 0.15);
	float depth_norm = clamp((water_surface_y - world_pos.y) / depth_span, 0.0, 1.0);
	// Quantize depth_norm into N discrete bands for the posterized
	// look, then blend back toward the smooth value by (1 - bands).
	// Result: smooth gradient when depth_fog_bands == 0, hard step
	// terraces when == 1. depth_fog_band_count controls the visible
	// step count; 6 is calibrated so each band is roughly one chunky
	// pixel-art tonal step in a 1.5 m-tall water column.
	float band_count = float(depth_fog_band_count);
	float depth_quant = floor(depth_norm * band_count + 0.5) / band_count;
	float depth_used = mix(depth_norm, depth_quant, depth_fog_bands);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_used * depth_used);

	// Depth fog toward deep color — also uses the quantized depth so
	// the fog density steps in the same bands as the depth gradient.
	col = mix(col, deep_color.rgb, depth_used * depth_fog * 0.35);

	vec2 cuv = world_pos.xz * 1.15;
	float t = TIME * 0.78 + day_phase_offset * 6.28318;
	float cwave = sin(cuv.x * 2.05 + t) * sin(cuv.y * 1.72 - t * 0.86)
		+ sin((cuv.x + cuv.y) * 1.38 + t * 1.15);
	float caustics = smoothstep(0.05, 0.72, cwave) * caustic_intensity;
	caustics *= 1.0 - depth_norm * 0.35;
	col += light_color * caustics * 0.22;

	vec3 n = normalize(NORMAL);
	float surface = smoothstep(0.55, 0.92, n.y);
	col = mix(col, shallow_color.rgb * 1.18, surface * 0.42);

	float meniscus = surface * (0.65 + 0.35 * sin(world_pos.x * 2.4 + world_pos.z * 2.1));
	float near_surface = 1.0 - smoothstep(0.0, 0.25, abs(world_pos.y - water_surface_y));
	float vertical = 1.0 - abs(n.y);

	// Meniscus bright ring — top cap only (avoid a cut line on curved walls).
	col += vec3(0.92, 0.98, 1.0) * meniscus * max(0.0, n.y - 0.55) * 0.14;

	// Corner meniscus on polygon tanks only; curved volumes use the top ring.
	float corner_meniscus = near_surface * vertical;
	if (tank_shape_id < 0.5) {
		col += vec3(0.85, 0.95, 1.0) * corner_meniscus * 0.18;
	}

	float fresnel = pow(1.0 - abs(dot(n, VIEW)), 2.2);
	col = mix(col, shallow_color.rgb * 0.82, fresnel * 0.28);

	col = mix(col, tint_color.rgb, tint_strength);
	col = mix(col, col * vec3(1.08, 0.92, 0.82), sunset_warmth * 0.35);
	col = mix(col, col * vec3(0.72, 0.82, 1.05), moonlight * 0.28);
	// Bacterial bloom haze — push the whole column toward bloom_color
	// (warm-white). Adds opacity too so the haze visibly obscures the
	// far side of the tank during heavy blooms.
	col = mix(col, bloom_color, bacterial_bloom * 0.55);

	// Ice lens — frosted rim at waterline in cold presets.
	float ice_rim = near_surface * (0.4 + vertical * 0.6) * ice_lens;
	col = mix(col, vec3(0.88, 0.94, 1.0), ice_rim * 0.45);

	float alpha = mix(shallow_color.a, deep_color.a, depth_norm);
	alpha += bloom_haze * 0.16;
	alpha += surface * 0.05;
	alpha += fresnel * 0.05;
	alpha += caustics * 0.04;
	alpha += ice_rim * 0.06;
	alpha += bacterial_bloom * 0.18;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.04, 0.52);
}
