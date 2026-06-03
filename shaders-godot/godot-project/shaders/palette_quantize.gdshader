// Vivarium — palette quantize + Bayer dither + region awareness + outline + CRT
// Applied to the Display TextureRect that shows the SubViewport's render.
//
// Sequence per fragment:
//   1) Sample source from the SubViewport.
//   2) Apply seasonal warmth + time-of-day palette tint (palette_swap mode).
//   3) Region heuristic: low-saturation pixels (water / fog) get heavy dither;
//      high-saturation pixels (fauna, plants, coral) get light dither. The
//      switch is driven by `region_aware_dither` so the legacy single-strength
//      mode is one uniform flip.
//   4) Palette-bank lock: classify the source hue into a bank and only
//      consider the bank's nearest indices when picking the two candidates
//      for dithering. Enforces a ~16-color "active palette" feel.
//   5) Ordered-dither between the two nearest palette colors.
//   6) Edge outline: dark stroke where the unquantized source has a strong
//      luminance discontinuity vs. UV neighbors. Gated by `outline_strength`.
//   7) CRT/scanline overlay: subtle horizontal striping + tiny vignette.
//      Gated by `crt_strength`.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int palette_size : hint_range(1, 64) = 48;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform float seasonal_warmth : hint_range(-0.15, 0.15) = 0.0;
uniform vec2 internal_resolution = vec2(384.0, 216.0);

// 0 = single global dither strength (legacy). 1 = saturation-driven region
// switching: heavy dither on low-sat (water/fog), light on saturated (fauna).
uniform float region_aware_dither : hint_range(0.0, 1.0) = 1.0;
// 0 = full 48-color palette searched. 1 = restrict each fragment's candidate
// set to the 16-color hue bank closest to the source color.
uniform float palette_bank_lock : hint_range(0.0, 1.0) = 1.0;
// 0 = no edge outline. 1 = strong dark line on every silhouette.
uniform float outline_strength : hint_range(0.0, 1.0) = 0.0;
// 0 = no CRT overlay. 1 = full scanlines + vignette.
uniform float crt_strength : hint_range(0.0, 1.0) = 0.0;
// Multiplicative tint applied to the source BEFORE quantization. main.gd
// drives this from SimDriver.day_phase so the same palette breathes between
// dawn / day / dusk / night without needing distinct PNGs.
uniform vec3 palette_tint = vec3(1.0, 1.0, 1.0);

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

vec3 palette_color(int idx) {
	float u = (float(idx) + 0.5) / float(palette_size);
	return texture(palette_tex, vec2(u, 0.5)).rgb;
}

float luma_of(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Classify a source color into one of three hue banks:
//   0 = cool (water, sky, blue/green dominant)
//   1 = neutral / mid (substrate browns, mid greens, grays)
//   2 = warm (fauna corals, oranges, reds, yellows)
// Each bank covers 16 contiguous palette indices when palette_size == 48,
// matching the project's planted_48.png layout convention.
int classify_bank(vec3 c) {
	float r = c.r;
	float g = c.g;
	float b = c.b;
	float maxc = max(max(r, g), b);
	float minc = min(min(r, g), b);
	float sat = (maxc - minc) / max(maxc, 0.001);
	// Very desaturated → neutral bank (browns / grays).
	if (sat < 0.18) {
		return 1;
	}
	// Earth-tone browns (substrate, wood, mulch): red leads but green is
	// still a strong second — not coral pink. Neutral bank holds the
	// substrate ramp (palette indices 16–23).
	if (r > b && g > b * 1.10 && g < r && g >= r * 0.55 && sat < 0.72) {
		return 1;
	}
	// Saturated: pick by dominant channel ratio.
	if (b > r && b >= g * 0.85) {
		return 0; // cool
	}
	if (r > b && r >= g * 0.85) {
		return 2; // warm
	}
	// Green-dominant straddles neutral and cool depending on blue mix.
	if (g > b * 1.15) {
		return 1;
	}
	return 0;
}

void fragment() {
	vec3 src = texture(TEXTURE, UV).rgb;
	src = mix(src, src * vec3(1.06, 1.0, 0.94), max(seasonal_warmth, 0.0));
	src = mix(src, src * vec3(0.94, 0.98, 1.06), max(-seasonal_warmth, 0.0));
	// Time-of-day tint. Multiplicative so values that were already darkened
	// by night lighting in 3D don't double-darken; the tint just shifts hue.
	src *= palette_tint;
	float luma = luma_of(src);
	src = mix(vec3(luma), src, 1.08);
	src *= 1.04;

	// ---- Region-aware dither strength ----
	float maxc = max(max(src.r, src.g), src.b);
	float minc = min(min(src.r, src.g), src.b);
	float sat = (maxc - minc) / max(maxc, 0.001);
	// Pixels with low saturation (water blues, gray fog, brown substrate)
	// get heavier dither — they read as smooth gradients in a real 8-bit
	// game. Saturated pixels (fauna, coral, plants) get light dither so
	// silhouettes stay clean.
	float region_d = mix(dither_strength * 1.10, dither_strength * 0.35, smoothstep(0.18, 0.55, sat));
	float eff_dither = mix(dither_strength, region_d, region_aware_dither);

	// ---- Palette-bank candidate selection ----
	int bank = classify_bank(src);
	int bank_size = palette_size / 3;
	int bank_start = bank * bank_size;
	int bank_end = bank_start + bank_size;

	// Find two nearest palette colors. When palette_bank_lock is on, restrict
	// to [bank_start, bank_end). When off, scan the full palette.
	int ai = 0;
	int bi = 0;
	float best = 1e9;
	float best2 = 1e9;
	bool locked = palette_bank_lock > 0.5;
	for (int i = 0; i < 64; i++) {
		if (i >= palette_size) break;
		if (locked && (i < bank_start || i >= bank_end)) continue;
		vec3 p = palette_color(i);
		float d = dot(src - p, src - p);
		if (d < best) {
			best2 = best; bi = ai;
			best  = d;    ai = i;
		} else if (d < best2) {
			best2 = d; bi = i;
		}
	}
	// Fallback: if the locked bank only produced one candidate (rare; can
	// happen at extreme edge of the bank), open the search to full palette
	// for the runner-up only.
	if (locked && best2 > 1e8) {
		for (int j = 0; j < 64; j++) {
			if (j >= palette_size) break;
			if (j == ai) continue;
			vec3 p = palette_color(j);
			float d = dot(src - p, src - p);
			if (d < best2) {
				best2 = d; bi = j;
			}
		}
	}

	vec3 a = palette_color(ai);
	vec3 b = palette_color(bi);
	vec3 ab = b - a;
	float denom = max(dot(ab, ab), 1e-6);
	float t = clamp(dot(src - a, ab) / denom, 0.0, 1.0);

	vec2 px = UV * internal_resolution;
	float threshold = 0.5 + bayer_at(px) * eff_dither;
	int chosen = (t > threshold) ? bi : ai;
	vec3 result = palette_color(chosen);

	// ---- Edge outline ----
	// One-pixel-thin dark stroke at strong luminance discontinuities. We
	// sample 4 immediate neighbors of the unquantized source so the outline
	// follows the actual geometry boundaries, not the dithered tiles.
	if (outline_strength > 0.001) {
		vec2 step_uv = 1.0 / internal_resolution;
		float lc = luma_of(src);
		float ln = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).rgb * palette_tint);
		float ls = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv.y)).rgb * palette_tint);
		float le = luma_of(texture(TEXTURE, UV + vec2( step_uv.x, 0.0)).rgb * palette_tint);
		float lw = luma_of(texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).rgb * palette_tint);
		// Edge magnitude = max absolute luma delta vs any neighbor. Threshold
		// kills noise at smoothly-shaded areas (water column gradients).
		float dmax = max(max(abs(lc - ln), abs(lc - ls)),
						 max(abs(lc - le), abs(lc - lw)));
		float edge = smoothstep(0.10, 0.32, dmax);
		float k = outline_strength * edge;
		result *= mix(1.0, 0.35, k);
	}

	// ---- CRT scanline + vignette overlay ----
	if (crt_strength > 0.001) {
		// Scanline: dim every other row of the OUTPUT (screen-space pixel),
		// not the internal resolution — gives the classic CRT comb pattern
		// regardless of dither block layout.
		float sl = 0.5 + 0.5 * cos(FRAGCOORD.y * 3.1415926 * 0.5);
		float scan = mix(1.0, 0.82 + sl * 0.18, crt_strength);
		result *= scan;
		// Vignette: gentle darken at the corners. UV is 0..1.
		vec2 vc = UV - 0.5;
		float vig = 1.0 - dot(vc, vc) * 0.8;
		result *= mix(1.0, clamp(vig, 0.55, 1.0), crt_strength);
	}

	COLOR = vec4(result, 1.0);
}
