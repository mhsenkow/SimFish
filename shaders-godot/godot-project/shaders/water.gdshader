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
uniform vec3 bloom_color : source_color = vec3(0.86, 0.88, 0.84);
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;
// Screen-space refraction — the single biggest "this is real water" lever.
// The scene behind the glass is sampled with a UV offset driven by the
// surface wave slope, so plants/fish/substrate seen through the water gently
// wobble. Kept subtle by default so the chunky pixel look survives.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 0.08) = 0.013;
// Depth absorption — warm wavelengths (red, then green) fade with depth, the
// way real water swallows red light first. Gives the column a sense of volume.
uniform float depth_absorption : hint_range(0.0, 1.0) = 0.4;
// Shader depth haze for Metal/macOS where volumetric fog is off (#11, #20).
uniform float aerial_haze : hint_range(0.0, 1.0) = 0.0;
uniform float surface_reflection : hint_range(0.0, 1.0) = 0.24;
uniform float underside_mirror : hint_range(0.0, 1.0) = 0.24;
uniform vec3 room_sky_color : source_color = vec3(0.55, 0.48, 0.42);
// Top-down / pond mode: calm glass (#17) + health sheen (#20).
uniform float pond_calm : hint_range(0.0, 1.0) = 0.0;
uniform float pond_health_gloss : hint_range(0.0, 1.0) = 1.0;
uniform float pond_wind : hint_range(0.0, 1.0) = 0.0;
uniform float pond_wake_activity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 pond_color_spill : source_color = vec3(0.0);
uniform float pond_color_spill_gain : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pond_dimple_points[12];

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 world_pos;
varying float surface_lift;

// Organic caustics web (matches caustics.gdshader) — drifting Worley cells.
vec2 caustic_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
float worley_caustic(vec2 uv, float tt) {
	vec2 g = floor(uv);
	vec2 fr = fract(uv);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 fp = caustic_hash(g + cell);
			vec2 pt = cell + 0.5 + 0.42 * sin(tt + 6.2831 * fp);
			float d = length(pt - fr);
			if (d < d1) { d2 = d1; d1 = d; }
			else if (d < d2) { d2 = d; }
		}
	}
	return pow(clamp(d2 - d1, 0.0, 1.0), 1.6);
}

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
		float wind_w = sin(wp.x * wave_scale * 0.55 + TIME * wave_speed * 0.35 + wp.z * 0.08)
			* cos(wp.z * wave_scale * 0.48 - TIME * wave_speed * 0.28);
		float calm_waves = mix(1.0, 0.12, pond_calm);
		float wake_amp = 1.0 + pond_wake_activity * 0.55;
		surface_lift = (wave_amplitude * (w1 * 0.52 + w2 * 0.33)
			+ wave2_amplitude * w3
			+ pond_wind * wave_amplitude * 0.35 * wind_w) * calm_waves * wake_amp;
		for (int i = 0; i < 12; i++) {
			vec4 pt = pond_dimple_points[i];
			if (pt.w < 0.01) {
				continue;
			}
			vec2 d = wp.xz - pt.xz;
			float r2 = dot(d, d);
			surface_lift -= pt.w * exp(-r2 * 7.5) * pt.z * 0.14;
		}
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
	float ign = fract(52.9829189 * fract(0.06711056 * world_pos.x + 0.00583715 * world_pos.z));
	depth_quant += (ign - 0.5) * (0.85 / band_count) * depth_fog_bands;
	depth_quant = clamp(depth_quant, 0.0, 1.0);
	float depth_used = mix(depth_norm, depth_quant, depth_fog_bands);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_used * depth_used);
	col = apply_category_palette_tint(col, iaq_palette_water,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);

	// Depth fog toward deep color — also uses the quantized depth so
	// the fog density steps in the same bands as the depth gradient.
	col = mix(col, deep_color.rgb, depth_used * depth_fog * 0.35);

	// Depth absorption: red goes first, then green, leaving the deep column
	// blue-shifted. Subtle, scaled by depth_used so the surface stays neutral.
	col *= mix(vec3(1.0),
		vec3(1.0 - depth_used * 0.55, 1.0 - depth_used * 0.22, 1.0),
		depth_absorption);

	// Aerial perspective — back of tank desaturates into the water tint (#11).
	col = mix(col, deep_color.rgb, depth_used * aerial_haze * 0.32);
	// Murky-water scatter glow around bright objects (#19).
	float murk_glow = bacterial_bloom * 0.42 + bloom_haze * 0.28;
	if (murk_glow > 0.01) {
		float bright = max(max(col.r, col.g), col.b);
		col += light_color * smoothstep(0.32, 0.88, bright) * murk_glow * 0.16;
	}

	// Organic caustics web instead of sine interference.
	vec2 cuv = world_pos.xz * 1.15;
	float t = TIME * 0.78 + day_phase_offset * 6.28318;
	float cw1 = worley_caustic(cuv * 0.7, t * 0.6);
	float cw2 = worley_caustic(cuv * 1.4 + vec2(9.0, 4.0), -t * 0.4 + 1.5);
	float cw3 = worley_caustic(cuv * 2.6 + vec2(15.0, 8.0), t * 0.28 + 3.0);
	float caustics = smoothstep(0.12, 0.85, cw1 * 0.5 + cw1 * cw2 * 0.75 + cw2 * cw3 * 0.35) * caustic_intensity;
	caustics *= 1.0 - depth_used * 0.35;
	// Dampen caustic shimmer at the surface — thin stems flicker less (#28).
	float surf_dist = abs(world_pos.y - water_surface_y);
	caustics *= smoothstep(0.0, 0.22, surf_dist);
	vec3 caustic_absorb = mix(vec3(1.0),
		vec3(1.0 - depth_used * 0.55, 1.0 - depth_used * 0.22, 1.0),
		depth_absorption);
	col += light_color * caustics * 0.24 * caustic_absorb;

	vec3 n = normalize(NORMAL);
	float surface = smoothstep(0.55, 0.92, n.y);
	float fresnel = pow(1.0 - abs(dot(n, VIEW)), 2.2);
	col = mix(col, shallow_color.rgb * 1.18, surface * 0.42);
	// Living ceiling: viewed from below, the surface fractures the light into a
	// drifting bright web. Reuses the caustic Worley so it matches the floor.
	if (surface > 0.01) {
		float surf_web = worley_caustic(world_pos.xz * 0.9 + vec2(3.0, 1.0), TIME * 0.5);
		col += light_color * surf_web * surface * 0.18;
		// Room/sky sheen on the top cap (#24).
		float refl = surface_reflection * pond_health_gloss;
		col = mix(col, room_sky_color,
			surface * fresnel * refl * (0.35 + sunset_warmth * 0.35));
		col = mix(col, shallow_color.rgb * 1.08,
			surface * pond_calm * 0.22 * pond_health_gloss);
		col = mix(col, pond_color_spill,
			surface * pond_color_spill_gain * 0.32 * pond_health_gloss);
		// Underside mirror — total-internal-reflection read from below (#17).
		vec3 view_dir = normalize(VIEW);
		float from_below = smoothstep(0.15, 0.82, -view_dir.y) * surface;
		float ceil_web = worley_caustic(world_pos.xz * 1.05 + vec2(5.0, 2.0), TIME * 0.42);
		col += light_color * ceil_web * from_below * underside_mirror * 0.32;
		col += vec3(0.92, 0.97, 1.0) * from_below * underside_mirror * 0.12;
	}

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

	// Refraction at the air/water interface only — mid-column fauna stay sharp (#REFINE).
	if (refraction_strength > 0.0001) {
		vec2 wob = vec2(
			sin(world_pos.x * 1.7 + world_pos.z * 1.1 + TIME * 0.9),
			cos(world_pos.z * 1.9 - world_pos.x * 0.8 - TIME * 0.75));
		wob += n.xz * 1.2;
		float surf_prox = 1.0 - smoothstep(0.0, 0.38, abs(world_pos.y - water_surface_y));
		float depth_refr = (1.0 - depth_used) * mix(0.18, 1.0, surf_prox);
		wob *= 0.28 + depth_refr * 0.38;
		vec2 ruv = SCREEN_UV + wob * refraction_strength;
		vec3 refr = texture(screen_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb;
		float refr_mix = clamp((0.08 + depth_refr * 0.18) * (1.0 - bacterial_bloom), 0.0, 0.32);
		col = mix(col, refr * mix(vec3(1.0), col + 0.5, 0.35), refr_mix);
		alpha = max(alpha, refr_mix * 0.28);
	}

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.04, 0.62);
}
