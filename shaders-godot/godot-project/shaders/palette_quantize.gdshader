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
// Night palette LUT. Same 48 indices, same hue banks; just darker/cooler
// per slot so the quantize result at night is a true moonlit palette
// instead of the day palette darkened uniformly via palette_tint. Main.gd
// drives palette_night_blend from SimDriver.daylight() inverted so the
// transition is smooth across dawn / dusk.
uniform sampler2D palette_tex_night : source_color, filter_nearest, repeat_disable;
uniform float palette_night_blend : hint_range(0.0, 1.0) = 0.0;
// Highlight burnthrough — when source luma is well above the threshold
// AND it is night, the chosen palette color is lerped back toward the
// DAY palette so emissive content (coral biolum, biofilm shimmer, light
// fixtures) reads as a bright island against the moonlit field. This is
// the "bioluminescent bloom" feel without a full bloom post pass.
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.68;
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.85;
// Standalone vignette — runs independently of the CRT overlay so the
// frame always has a soft dark corner that pulls the eye to the tank.
// 0 = off, 1 = full corner darkening.
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
// How tightly the vignette falls off. Higher = darker corners earlier.
uniform float vignette_falloff : hint_range(0.5, 4.0) = 1.6;
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
uniform float material_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float material_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float material_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float material_value : hint_range(0.7, 1.3) = 1.0;

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

// Interleaved-gradient noise — a cheap, texture-free stand-in for blue noise.
// Its energy spectrum is far more isotropic than the ordered Bayer matrix, so
// smooth low-saturation gradients (water, fog, deep substrate) dissolve into
// organic stipple instead of showing the tell-tale 4x4 grid the style guide
// warns about for murk/detritus.
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))) - 0.5;
}

// 0 = pure Bayer (legacy). 1 = full blue-noise on low-saturation regions.
uniform float blue_noise_amount : hint_range(0.0, 1.0) = 0.6;

vec3 palette_color(int idx) {
	float u = (float(idx) + 0.5) / float(palette_size);
	vec3 day_c = texture(palette_tex, vec2(u, 0.5)).rgb;
	vec3 night_c = texture(palette_tex_night, vec2(u, 0.5)).rgb;
	return mix(day_c, night_c, palette_night_blend);
}

// Pure day-palette lookup. Used by the highlight burnthrough path so the
// bright pixels of a glowing coral can punch out of the night palette in
// the same warm colors they had during the day.
vec3 palette_color_day(int idx) {
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
	src = apply_global_palette_tint(src, material_hue_shift, material_saturation,
		material_warmth, material_value);
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
	// Luma-aware suppression: as a low-sat region brightens past ~0.55
	// luma, adjacent palette entries land further apart and the dither
	// pattern reads as a visible "grid" of chunks instead of smooth noise.
	// Scale dither toward 0.45× at full bright so the substrate at noon
	// stops grid-aliasing while dark scenes keep the smooth-gradient
	// benefit they need. Only applied to LOW-saturation pixels — saturated
	// fauna/plants already drop to 0.35× via region_d above.
	float bright_suppress = mix(1.0, 0.45, smoothstep(0.55, 0.95, luma));
	float low_sat_factor = 1.0 - smoothstep(0.18, 0.55, sat);
	region_d *= mix(1.0, bright_suppress, low_sat_factor);
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
	// Blend the dither kernel toward blue-noise on low-saturation pixels (the
	// smooth water/fog/substrate gradients) where Bayer's grid is most visible;
	// keep Bayer on saturated fauna/plants so their silhouettes stay crisp.
	float bn_region = low_sat_factor * blue_noise_amount;
	float dpat = mix(bayer_at(px), ign(px), bn_region);
	float threshold = 0.5 + dpat * eff_dither;
	int chosen = (t > threshold) ? bi : ai;
	vec3 result = palette_color(chosen);

	// ---- Bioluminescent bloom (HDR-ish highlight handling) ----
	// Two paths combined:
	//   1. Night burnthrough — bright source pixels at night get lerped
	//      back toward the DAY palette so emissive content (coral biolum,
	//      biofilm shimmer, light fixtures) reads as warm islands against
	//      the moonlit field. Same idea as the previous version, but
	//      slightly stronger.
	//   2. Always-on overbright lift — when source luma is well above
	//      1.0 (set by emissive coral via .lightened(>0)), additively
	//      push the result toward warm white. This is the "HDR-ish"
	//      shoulder: pixels that the sim labelled as emitting more than
	//      diffuse-white intensity actually punch out of the palette
	//      instead of being clamped to the nearest 8-bit slot.
	float src_luma = luma_of(src);
	if (palette_night_blend > 0.01) {
		float bloom = smoothstep(bloom_threshold, 0.92, src_luma)
		            * palette_night_blend
		            * bloom_strength;
		if (bloom > 0.001) {
			vec3 day_c = palette_color_day(chosen);
			result = mix(result, day_c, bloom);
		}
	}
	// HDR shoulder — input luma over ~0.85 lifts the output toward a
	// warm white. Strength scales with how far above the shoulder the
	// source sits, so a gentle 0.92 reads as "a bit hot" while a 1.4
	// (very emissive coral or fixture) actually saturates to bloom.
	float over = max(src_luma - 0.85, 0.0);
	float hdr_lift = clamp(over * 1.6, 0.0, 0.85);
	if (hdr_lift > 0.001) {
		vec3 hot_white = vec3(1.0, 0.97, 0.90);
		result = mix(result, hot_white, hdr_lift);
	}

	// ---- Edge outline with depth-aware thickness ----
	// Two-band detector: a 1-px neighborhood for the standard thin stroke
	// AND a 2-px neighborhood to catch high-contrast silhouettes (closer
	// fish, foreground plants) where the gradient persists over a wider
	// span. Closer objects fire BOTH bands → a 2-px thick outline; flat
	// gradients in the water column or distant geometry fire only the
	// thin band → a 1-px stroke. The result reads as "closer = thicker"
	// without needing the SubViewport's depth texture wired through.
	if (outline_strength > 0.001) {
		vec2 step_uv = 1.0 / internal_resolution;
		float lc = luma_of(src);
		float ln1 = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).rgb * palette_tint);
		float ls1 = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv.y)).rgb * palette_tint);
		float le1 = luma_of(texture(TEXTURE, UV + vec2( step_uv.x, 0.0)).rgb * palette_tint);
		float lw1 = luma_of(texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).rgb * palette_tint);
		float dmax_near = max(max(abs(lc - ln1), abs(lc - ls1)),
		                     max(abs(lc - le1), abs(lc - lw1)));
		// Threshold raised from 0.10 → 0.18 so dither-pattern luma jitter
		// (typically 0.03–0.12) stops triggering false outlines on
		// otherwise-smooth surfaces (substrate, water, fog). Real
		// silhouettes have a 0.2+ luma jump and still trigger cleanly.
		float edge_near = smoothstep(0.18, 0.38, dmax_near);

		// Wider-baseline tap to catch silhouettes that survive 2 px out.
		float ln2 = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv.y * 2.0)).rgb * palette_tint);
		float ls2 = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv.y * 2.0)).rgb * palette_tint);
		float le2 = luma_of(texture(TEXTURE, UV + vec2( step_uv.x * 2.0, 0.0)).rgb * palette_tint);
		float lw2 = luma_of(texture(TEXTURE, UV + vec2(-step_uv.x * 2.0, 0.0)).rgb * palette_tint);
		float dmax_far = max(max(abs(lc - ln2), abs(lc - ls2)),
		                    max(abs(lc - le2), abs(lc - lw2)));
		// Far tap threshold also raised (0.18 → 0.26) — only strong
		// silhouettes promote to the thick band; small ornamental detail
		// stays at the 1-px line.
		float edge_far = smoothstep(0.26, 0.48, dmax_far);

		// Thick band: both fire (close, high-contrast). Thin band: only
		// near fires. mix() blends darkening factor between the two so
		// the transition is graded rather than stepwise.
		float k_thin = outline_strength * edge_near * (1.0 - edge_far * 0.6);
		float k_thick = outline_strength * edge_near * edge_far;
		float darken = mix(1.0, 0.35, k_thin) * mix(1.0, 0.22, k_thick);
		result *= darken;
	}

	// ---- Standalone vignette ----
	// Independent of CRT. Always-on soft corner darkening that pulls the
	// eye to the tank centre. UV is 0..1; dot(uv_centered, uv_centered)
	// gives squared distance from frame centre. pow() controls falloff
	// curve — vignette_falloff=1.0 is linear, higher = darker corners.
	if (vignette_strength > 0.001) {
		vec2 vc = UV - 0.5;
		float r2 = dot(vc, vc) * 4.0;  // 0 at centre, 1 at frame corners
		float v = pow(clamp(r2, 0.0, 1.0), vignette_falloff);
		result *= mix(1.0, 1.0 - vignette_strength * 0.55, v);
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
