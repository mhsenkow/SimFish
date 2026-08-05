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
// 1 = anchor dither pattern to world XZ (stops crawl on camera pans). #26
uniform float dither_world_lock : hint_range(0.0, 1.0) = 0.0;
uniform vec2 dither_world_origin = vec2(0.0, 0.0);
// 0 = full 48-color palette searched. 1 = restrict each fragment's candidate
// set to the 16-color hue bank closest to the source color.
uniform float palette_bank_lock : hint_range(0.0, 1.0) = 1.0;
// 0 = no edge outline. 1 = strong dark line on every silhouette.
uniform float outline_strength : hint_range(0.0, 1.0) = 0.0;
// Extra ink on saturated life (fauna, plants, coral) — reads as a second
// outline pass on top of the watercolor quantize without outlining water.
uniform float creature_outline_strength : hint_range(0.0, 1.0) = 0.0;
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
// Tank health read — 1 = crisp/thriving, 0 = stressed/murky (#66).
uniform float health_grade : hint_range(0.0, 1.0) = 1.0;
// Palette-locked paper grain (#77).
uniform float film_grain_strength : hint_range(0.0, 1.0) = 0.0;
// Soft display AA + banding break — runs after quantize so MultiMesh stays
// untouched. Defaults off; Mac quality preset enables a light dose.
uniform float fxaa_strength : hint_range(0.0, 1.0) = 0.0;
uniform float deband_strength : hint_range(0.0, 1.0) = 0.0;
// Extra emissive bloom shoulder on hot pixels (#73).
uniform float selective_glow : hint_range(0.0, 1.0) = 0.0;
// Suppress outlines on low-sat water/substrate (#72).
uniform float outline_subject_bias : hint_range(0.0, 1.0) = 0.65;
// Coarser cluster-dot dither on earth-tone substrate (#8).
uniform float dither_substrate_coarse : hint_range(0.0, 1.0) = 0.35;
// 0 = cosine scanline, 1 = aperture grille, 2 = shadow mask (#74).
uniform float crt_mode : hint_range(0.0, 2.0) = 0.0;

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
// 0=full palette search, 1=32-cap, 2=24-cap (#19–20).
uniform float shader_perf_tier : hint_range(0.0, 2.0) = 0.0;

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
//   2 = warm (fauna corals, oranges, reds, yellows; indices 35–46)
// Highlights at 32–34 (white + icy blues) classify via the blue-dominant rule.
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
	// Green-dominant: saturated foliage → cool bank (greens 8–15); olives stay neutral.
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
	// Time-of-day tint. Multiplicative so values that were already darkened
	// by night lighting in 3D don't double-darken; the tint just shifts hue.
	src *= palette_tint;
	// Health-driven mood grade — thriving tanks stay vivid; stressed ones cool + dull.
	float stress = 1.0 - health_grade;
	src = mix(src, src * vec3(0.92, 0.96, 1.04), stress * 0.42);
	src = mix(vec3(luma_of(src)), src, 1.0 - stress * 0.18);
	float luma = luma_of(src);
	float maxc2 = max(max(src.r, src.g), src.b);
	float minc2 = min(min(src.r, src.g), src.b);
	float sat_post = (maxc2 - minc2) / max(maxc2, 0.001);
	float sat_lift = mix(1.08, 1.0, smoothstep(0.38, 0.72, sat_post));
	src = mix(vec3(luma), src, sat_lift);
	src *= mix(1.04, 1.0, smoothstep(0.42, 0.78, sat_post));

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
	// Vivid fauna/plants: lighter dither so silhouettes stay legible through glass.
	eff_dither *= mix(1.0, 0.42, smoothstep(0.42, 0.78, sat));
	// Flat-area clustering (#6): when neighbours share luma, keep terraces flat.
	vec2 step_uv_cluster = 1.0 / internal_resolution;
	float lc_pre = luma;
	float ln_c = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv_cluster.y)).rgb * palette_tint);
	float ls_c = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv_cluster.y)).rgb * palette_tint);
	float le_c = luma_of(texture(TEXTURE, UV + vec2( step_uv_cluster.x, 0.0)).rgb * palette_tint);
	float lw_c = luma_of(texture(TEXTURE, UV + vec2(-step_uv_cluster.x, 0.0)).rgb * palette_tint);
	float lvar = abs(lc_pre - ln_c) + abs(lc_pre - ls_c) + abs(lc_pre - le_c) + abs(lc_pre - lw_c);
	float flat_factor = 1.0 - smoothstep(0.02, 0.14, lvar);
	eff_dither *= mix(1.0, 0.38, flat_factor * low_sat_factor);
	// Substrate gets a coarser stipple than water (#8).
	int bank_hint = classify_bank(src);
	bool is_substrate = (bank_hint == 1 && sat < 0.55 && luma < 0.62);
	float coarse = is_substrate ? dither_substrate_coarse : 0.0;

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
	int search_cap = palette_size;
	if (shader_perf_tier >= 1.5) {
		search_cap = min(palette_size, 24);
	} else if (shader_perf_tier >= 0.5) {
		search_cap = min(palette_size, 32);
	}
	for (int i = 0; i < 64; i++) {
		if (i >= search_cap) break;
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
	// Adjacent-bank bridge when runner-up is a poor match (#18).
	if (locked && best2 > best * 1.06) {
		int lo = max(bank_start - bank_size, 0);
		int hi = min(bank_end + bank_size, palette_size);
		for (int j = lo; j < hi; j++) {
			if (j >= bank_start && j < bank_end) continue;
			vec3 p = palette_color(j);
			float d = dot(src - p, src - p);
			if (d < best2) {
				best2 = d; bi = j;
			}
		}
	}
	// Rare: still no runner-up — scan full palette once.
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

	vec2 screen_px = UV * internal_resolution;
	vec2 world_px = dither_world_origin + (UV - 0.5) * internal_resolution;
	vec2 px = mix(screen_px, world_px, dither_world_lock);
	float dpat_coarse = mix(bayer_at(px * 0.5), ign(px * 1.7), 0.55);
	// Blend the dither kernel toward blue-noise on low-saturation pixels (the
	// smooth water/fog/substrate gradients) where Bayer's grid is most visible;
	// keep Bayer on saturated fauna/plants so their silhouettes stay crisp.
	float bn_region = low_sat_factor * blue_noise_amount;
	float dpat = mix(bayer_at(px), ign(px), bn_region);
	dpat = mix(dpat, dpat_coarse, coarse);
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
		vec3 hot_hue = normalize(max(src, vec3(0.001)));
		vec3 hot_white = mix(hot_hue, vec3(1.0, 0.97, 0.90), 0.32);
		result = mix(result, hot_white, hdr_lift);
	}
	// Selective glow on emissives — pearling, biolum, fixtures (#73).
	if (selective_glow > 0.001 && src_luma > bloom_threshold) {
		float glow = smoothstep(bloom_threshold, 1.05, src_luma) * selective_glow;
		vec3 glow_c = palette_color_day(chosen);
		result = mix(result, glow_c, glow * 0.55);
		result = mix(result, vec3(1.0, 0.98, 0.92), glow * 0.22);
	}

	// ---- Edge outline with depth-aware thickness ----
	// Two-band detector: a 1-px neighborhood for the standard thin stroke
	// AND a 2-px neighborhood to catch high-contrast silhouettes (closer
	// fish, foreground plants) where the gradient persists over a wider
	// span. Closer objects fire BOTH bands → a 2-px thick outline; flat
	// gradients in the water column or distant geometry fire only the
	// thin band → a 1-px stroke. The result reads as "closer = thicker"
	// without needing the SubViewport's depth texture wired through.
	if (shader_perf_tier < 1.95 && outline_strength > 0.001) {
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
		// Selective outline — fauna/hardscape bold, water/substrate whisper (#72).
		float subject_w = mix(1.0, smoothstep(0.12, 0.50, sat), outline_subject_bias);
		float k_thin = outline_strength * edge_near * (1.0 - edge_far * 0.6) * subject_w;
		float k_thick = outline_strength * edge_near * edge_far * subject_w;
		float caustic_false = smoothstep(0.04, 0.18, lvar) * (1.0 - smoothstep(0.14, 0.42, sat));
		k_thin *= 1.0 - caustic_false * 0.78;
		k_thick *= 1.0 - caustic_false * 0.78;
		float darken = mix(1.0, 0.35, k_thin) * mix(1.0, 0.22, k_thick);
		result *= darken;
	}

	// Creature ink — second outline pass on saturated subjects only. Keeps
	// fish/plants readable when the glass + blue-noise watercolor is strong.
	if (creature_outline_strength > 0.001) {
		vec2 step_uv = 1.0 / internal_resolution;
		float lc = luma_of(src);
		float ln1 = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv.y)).rgb * palette_tint);
		float ls1 = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv.y)).rgb * palette_tint);
		float le1 = luma_of(texture(TEXTURE, UV + vec2( step_uv.x, 0.0)).rgb * palette_tint);
		float lw1 = luma_of(texture(TEXTURE, UV + vec2(-step_uv.x, 0.0)).rgb * palette_tint);
		float dmax_near = max(max(abs(lc - ln1), abs(lc - ls1)),
		                     max(abs(lc - le1), abs(lc - lw1)));
		float edge_creature = smoothstep(0.10, 0.28, dmax_near);
		float ln2 = luma_of(texture(TEXTURE, UV + vec2(0.0, -step_uv.y * 2.0)).rgb * palette_tint);
		float ls2 = luma_of(texture(TEXTURE, UV + vec2(0.0,  step_uv.y * 2.0)).rgb * palette_tint);
		float le2 = luma_of(texture(TEXTURE, UV + vec2( step_uv.x * 2.0, 0.0)).rgb * palette_tint);
		float lw2 = luma_of(texture(TEXTURE, UV + vec2(-step_uv.x * 2.0, 0.0)).rgb * palette_tint);
		float dmax_far = max(max(abs(lc - ln2), abs(lc - ls2)),
		                    max(abs(lc - le2), abs(lc - lw2)));
		float edge_creature_thick = smoothstep(0.18, 0.38, dmax_far);
		float life_sat = smoothstep(0.20, 0.55, sat);
		float k_creature = creature_outline_strength * life_sat * edge_creature;
		float k_creature_thick = creature_outline_strength * life_sat * edge_creature * edge_creature_thick;
		result *= mix(1.0, 0.28, k_creature) * mix(1.0, 0.14, k_creature_thick * 0.85);
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
	if (shader_perf_tier < 1.95 && crt_strength > 0.001) {
		float sl = 0.5 + 0.5 * cos(FRAGCOORD.y * 3.1415926 * 0.5);
		float scan = 1.0;
		if (crt_mode < 0.5) {
			// Classic horizontal scanlines.
			scan = mix(1.0, 0.82 + sl * 0.18, crt_strength);
		} else if (crt_mode < 1.5) {
			// Aperture grille — RGB column triads.
			float col = mod(FRAGCOORD.x, 3.0);
			vec3 grille = vec3(
				col < 1.0 ? 0.92 : 1.0,
				col >= 1.0 && col < 2.0 ? 0.92 : 1.0,
				col >= 2.0 ? 0.92 : 1.0);
			result *= mix(vec3(1.0), grille, crt_strength * 0.55);
			scan = mix(1.0, 0.88 + sl * 0.10, crt_strength * 0.45);
		} else {
			// Shadow mask — offset dot triad.
			float mx = mod(FRAGCOORD.x + FRAGCOORD.y * 0.5, 3.0);
			float mask = 0.90 + 0.10 * step(0.5, abs(sin(mx * 2.094)));
			scan = mix(1.0, mask, crt_strength);
		}
		result *= scan;
		// Gentle barrel curvature (opt-in retro flavor).
		vec2 vc = UV - 0.5;
		float r2 = dot(vc, vc);
		vec2 barrel = vc * (1.0 + r2 * 0.08 * crt_strength);
		result *= mix(1.0, 1.0 - smoothstep(0.15, 0.55, r2) * 0.12, crt_strength);
		float vig = 1.0 - r2 * 0.8;
		result *= mix(1.0, clamp(vig, 0.55, 1.0), crt_strength * 0.65);
	}

	// Palette-locked film grain (#77).
	if (film_grain_strength > 0.001) {
		float grain = ign(px * 1.3 + vec2(17.0, 31.0)) * film_grain_strength * 0.08;
		result = clamp(result + vec3(grain), 0.0, 1.0);
	}

	// Cheap FXAA-lite — blend toward a 4-tap neighborhood on high-contrast edges.
	// Softens stair-steps when SubViewport MSAA is Off (Mac Metal path).
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

	// Triangular deband noise — breaks flat posterize terraces without soft blur.
	if (deband_strength > 0.001) {
		float n1 = ign(px);
		float n2 = ign(px + vec2(19.0, 47.0));
		float tri = n1 + n2; // approx [-1, 1] triangular
		result = clamp(result + vec3(tri * deband_strength * 0.012), 0.0, 1.0);
	}

	COLOR = vec4(result, 1.0);
}
