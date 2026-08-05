// PERFORMANCE_UNTHROTTLED #81/#82 — compile-stripped quantize pass (potato tier).
// Core palette quantize + region dither only; no outline/CRT/grain/extra taps.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D palette_tex_night : source_color, filter_nearest, repeat_disable;
uniform float palette_night_blend : hint_range(0.0, 1.0) = 0.0;
uniform int palette_size : hint_range(1, 64) = 48;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform float seasonal_warmth : hint_range(-0.15, 0.15) = 0.0;
uniform vec2 internal_resolution = vec2(384.0, 216.0);
uniform float region_aware_dither : hint_range(0.0, 1.0) = 1.0;
uniform float dither_world_lock : hint_range(0.0, 1.0) = 0.0;
uniform vec2 dither_world_origin = vec2(0.0, 0.0);
uniform float palette_bank_lock : hint_range(0.0, 1.0) = 1.0;
uniform vec3 palette_tint = vec3(1.0, 1.0, 1.0);
uniform float material_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float material_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float material_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float material_value : hint_range(0.7, 1.3) = 1.0;
uniform float health_grade : hint_range(0.0, 1.0) = 1.0;
uniform float blue_noise_amount : hint_range(0.0, 1.0) = 0.6;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_falloff : hint_range(0.5, 4.0) = 1.6;
uniform float fxaa_strength : hint_range(0.0, 1.0) = 0.0;
uniform float deband_strength : hint_range(0.0, 1.0) = 0.0;

#include "res://shaders/palette_tint.gdshaderinc"

const float bayer4[16] = float[16](
	 0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
	12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
	 3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
	15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

float bayer_at(vec2 pixel_xy) {
	ivec2 p = ivec2(mod(pixel_xy, 4.0));
	return bayer4[p.y * 4 + p.x] - 0.5;
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))) - 0.5;
}

vec3 palette_color(int idx) {
	float u = (float(idx) + 0.5) / float(palette_size);
	vec3 day_c = texture(palette_tex, vec2(u, 0.5)).rgb;
	vec3 night_c = texture(palette_tex_night, vec2(u, 0.5)).rgb;
	return mix(day_c, night_c, palette_night_blend);
}

float luma_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

int classify_bank(vec3 c) {
	float r = c.r;
	float g = c.g;
	float b = c.b;
	float maxc = max(max(r, g), b);
	float minc = min(min(r, g), b);
	float sat = (maxc - minc) / max(maxc, 0.001);
	if (sat < 0.18) {
		return 1;
	}
	if (r > b && g > b * 1.10 && g < r && g >= r * 0.55 && sat < 0.72) {
		return 1;
	}
	if (b > r && b >= g * 0.85) {
		return 0;
	}
	if (r > b && r >= g * 0.85) {
		return 2;
	}
	if (g > b * 1.15) {
		if (sat >= 0.25 && g >= r * 0.92) {
			return 0;
		}
		return 1;
	}
	return 0;
}

void fragment() {
	vec3 src = texture(TEXTURE, UV).rgb;
	src = apply_global_palette_tint(src, material_hue_shift, material_saturation,
		material_warmth, material_value);
	src = mix(src, src * vec3(1.06, 1.0, 0.94), max(seasonal_warmth, 0.0));
	src = mix(src, src * vec3(0.94, 0.98, 1.06), max(-seasonal_warmth, 0.0));
	src *= palette_tint;
	float stress = 1.0 - health_grade;
	src = mix(src, src * vec3(0.92, 0.96, 1.04), stress * 0.42);
	src = mix(vec3(luma_of(src)), src, 1.0 - stress * 0.18);

	float maxc = max(max(src.r, src.g), src.b);
	float minc = min(min(src.r, src.g), src.b);
	float sat = (maxc - minc) / max(maxc, 0.001);
	float region_d = mix(dither_strength * 1.10, dither_strength * 0.35, smoothstep(0.18, 0.55, sat));
	float eff_dither = mix(dither_strength, region_d, region_aware_dither);
	eff_dither *= mix(1.0, 0.42, smoothstep(0.42, 0.78, sat));

	int bank = classify_bank(src);
	int bank_size = palette_size / 3;
	int bank_start = bank * bank_size;
	int bank_end = bank_start + bank_size;
	int ai = 0;
	int bi = 0;
	float best = 1e9;
	float best2 = 1e9;
	bool locked = palette_bank_lock > 0.5;
	const int SEARCH_CAP = 24;
	for (int i = 0; i < SEARCH_CAP; i++) {
		if (i >= palette_size) {
			break;
		}
		if (locked && (i < bank_start || i >= bank_end)) {
			continue;
		}
		vec3 p = palette_color(i);
		float d = dot(src - p, src - p);
		if (d < best) {
			best2 = best;
			bi = ai;
			best = d;
			ai = i;
		} else if (d < best2) {
			best2 = d;
			bi = i;
		}
	}

	vec3 a = palette_color(ai);
	vec3 b = palette_color(bi);
	vec3 ab = b - a;
	float denom = max(dot(ab, ab), 1e-6);
	float t = clamp(dot(src - a, ab) / denom, 0.0, 1.0);

	vec2 screen_px = UV * internal_resolution;
	vec2 world_px = dither_world_origin + (UV - 0.5) * internal_resolution;
	vec2 px = mix(screen_px, world_px, dither_world_lock);
	float low_sat_factor = 1.0 - smoothstep(0.18, 0.55, sat);
	float dpat = mix(bayer_at(px), ign(px), low_sat_factor * blue_noise_amount);
	float threshold = 0.5 + dpat * eff_dither;
	int chosen = (t > threshold) ? bi : ai;
	vec3 result = palette_color(chosen);

	if (vignette_strength > 0.001) {
		vec2 vc = UV - 0.5;
		float r2 = dot(vc, vc) * 4.0;
		float v = pow(clamp(r2, 0.0, 1.0), vignette_falloff);
		result *= mix(1.0, 1.0 - vignette_strength * 0.55, v);
	}

	if (fxaa_strength > 0.001) {
		vec2 step_uv = 1.0 / internal_resolution;
		vec3 c_n = texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).rgb;
		vec3 c_s = texture(TEXTURE, UV + vec2(0.0,  step_uv.y)).rgb;
		vec3 c_e = texture(TEXTURE, UV + vec2( step_uv.x, 0.0)).rgb;
		vec3 c_w = texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).rgb;
		vec3 blur = (c_n + c_s + c_e + c_w) * 0.25;
		float lc = luma_of(result);
		float edge = max(max(abs(lc - luma_of(c_n)), abs(lc - luma_of(c_s))),
			max(abs(lc - luma_of(c_e)), abs(lc - luma_of(c_w))));
		float k = smoothstep(0.04, 0.18, edge) * fxaa_strength * 0.72;
		result = mix(result, blur, k);
	}
	if (deband_strength > 0.001) {
		float n1 = ign(px);
		float n2 = ign(px + vec2(19.0, 47.0));
		result = clamp(result + vec3((n1 + n2) * deband_strength * 0.012), 0.0, 1.0);
	}

	COLOR = vec4(result, 1.0);
}
