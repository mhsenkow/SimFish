// Tank glass — faint tint, shape highlights, room reflection, sparkle read.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 glass_color : source_color = vec4(0.7, 0.85, 0.9, 0.045);
uniform float rim_brightness : hint_range(0.0, 1.0) = 0.35;
// Reflection of the room's warm wall colour, blended in by fresnel +
// vertical gradient inside the fragment. Bumped from 0.22 → 0.42 so the
// room is visibly ghosted in the glass instead of being a faint hint —
// part of the "this aquarium is in a real room" framing.
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.42;
uniform float sparkle : hint_range(0.0, 1.0) = 0.0;
uniform float shape_band : hint_range(0.0, 1.0) = 0.0;
uniform float tank_shape_id : hint_range(0.0, 3.0) = 0.0;
uniform float biofilm : hint_range(0.0, 1.0) = 0.0;
uniform float condensation : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 6.5;
// Chrome rim — concentrated specular highlight at the very top edge of
// the tank. Defaults at 0.55 because the previous rim_brightness alone
// reads more like ambient sheen; this stacks a tight high-intensity
// band on top so the lip catches light like polished aluminum.
uniform float rim_chrome : hint_range(0.0, 1.0) = 0.55;
// Iridescent biofilm shimmer — thin-film interference hue shift on the
// glass-side biofilm areas. Default 0.5 keeps the warm green tint of
// the existing biofilm but adds a subtle pink/cyan view-angle shift
// where the corner creep concentrates.
uniform float biofilm_iridescence : hint_range(0.0, 1.0) = 0.5;
// Screen-space reflection. The front pane ghosts a horizontally-mirrored,
// fresnel-weighted sample of the scene, so the room and the tank's own
// contents shimmer in the glass at grazing angles — the "real glass in a real
// room" read. Subtle by default to preserve the pixel-art palette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float screen_reflection : hint_range(0.0, 1.0) = 0.0;
// Faint travelling caustic band on vertical panes (SENTIENCE_THE_SPARK #53).
uniform float caustic_band : hint_range(0.0, 1.0) = 0.0;
uniform float fingerprint_strength : hint_range(0.0, 1.0) = 0.0;
// REAL_TANK_FIDELITY #21–24 — green dust algae film + snail grazing tracks.
uniform float green_dust : hint_range(0.0, 1.0) = 0.0;
uniform float dust_panel_bias : hint_range(0.0, 1.0) = 0.55;
uniform vec4 graze_tracks[24];
// #25 — low-iron edge glow (cyan emission at pane edges).
uniform float edge_glow : hint_range(0.0, 1.0) = 0.55;
// #32 — salt creep / hard-water spots above waterline.
uniform float salt_creep : hint_range(0.0, 1.0) = 0.0;
// #35 — chromatic fringe on high-contrast glass edges.
uniform float chroma_fringe : hint_range(0.0, 1.0) = 0.35;
// #28–31 — room reflection flip, corner double-image, waterline refract.
uniform float room_reflection_flip : hint_range(0.0, 1.0) = 0.55;
uniform float corner_ghost : hint_range(0.0, 1.0) = 0.35;
uniform float waterline_refract : hint_range(0.0, 1.0) = 0.45;
// #37 — cool-room condensation on lower third of outside glass.
uniform float condensation_lower : hint_range(0.0, 1.0) = 0.0;
// #61 — scum / biofilm line where floating mat meets the glass.
uniform float scum_line : hint_range(0.0, 1.0) = 0.0;
// #176 — fixture ghost reflection on front glass.
uniform vec3 fixture_ghost_pos = vec3(0.0, 8.0, 0.0);
uniform float fixture_ghost : hint_range(0.0, 1.0) = 0.0;

float fp_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - abs(dot(n, view_dir)), 2.5);
	vec3 col = glass_color.rgb;

	// Top rim catch-light (bevel read).
	float top_rim = smoothstep(0.55, 0.95, n.y) * rim_brightness;
	col += vec3(0.92, 0.97, 1.0) * top_rim;

	// Shape-specific band highlight.
	float band = 0.0;
	if (tank_shape_id < 0.5) {
		band = smoothstep(0.35, 0.65, abs(sin(world_pos.y * 0.55 + world_pos.x * 0.08)));
	} else if (tank_shape_id < 1.5) {
		band = smoothstep(0.82, 0.98, abs(dot(n, vec3(0.0, 0.3, 1.0))));
	} else {
		band = smoothstep(0.7, 0.95, fresnel);
	}
	col += glass_color.rgb * band * shape_band * 0.45;

	// Faint room reflection (vertical gradient + horizontal band).
	float room_ref = smoothstep(0.15, 0.85, world_pos.y / max(water_surface_y, 0.1));
	room_ref *= 0.35 + 0.65 * fresnel;
	col = mix(col, vec3(0.55, 0.48, 0.42), room_ref * reflection_strength);

	// Travelling caustic shimmer on vertical glass (water light leak).
	if (caustic_band > 0.001 && abs(n.y) < 0.42) {
		float band_y = fract(world_pos.y * 0.22 - TIME * 0.14 + world_pos.x * 0.05);
		float band = smoothstep(0.42, 0.5, band_y) * (1.0 - smoothstep(0.54, 0.62, band_y));
		col += vec3(0.55, 0.82, 0.95) * band * caustic_band * fresnel * 0.35;
	}
	// Waterline caustic concentration (#64).
	if (abs(n.y) < 0.38) {
		float wl = abs(world_pos.y - water_surface_y);
		float wl_band = (1.0 - smoothstep(0.0, 0.14, wl))
			* step(0.0, world_pos.y - water_surface_y);
		col += vec3(0.78, 0.94, 1.0) * wl_band * caustic_band * 0.55;
	}

	// Faint static fingerprints on the front pane (#59).
	if (fingerprint_strength > 0.001) {
		float front_face = pow(max(dot(n, view_dir), 0.0), 0.55);
		vec2 fp_cell = floor(world_pos.xz * 7.5 + world_pos.y * 4.2);
		float fp = smoothstep(0.86, 0.98, fp_hash(fp_cell + vec2(3.1, 9.7)));
		col = mix(col, col * 0.90 + vec3(0.04, 0.03, 0.02), fp * fingerprint_strength * front_face * 0.32);
	}

	// Screen-space reflection: mirror the framebuffer horizontally and nudge
	// by the surface normal so the room + tank contents ghost across the pane.
	// Weighted by fresnel so it only blooms at grazing angles, like real glass.
	if (screen_reflection > 0.001) {
		// #28 — vertically flipped room reflection (strongest where water is dark).
		vec2 refl_uv = vec2(1.0 - SCREEN_UV.x,
			mix(SCREEN_UV.y, 1.0 - SCREEN_UV.y, room_reflection_flip * 0.65))
			+ n.xy * 0.028;
		vec3 refl = textureLod(screen_tex, clamp(refl_uv, vec2(0.001), vec2(0.999)), 1.5).rgb;
		float cam_up = smoothstep(0.25, 0.82, abs(view_dir.y));
		float dark_water = 1.0 - smoothstep(0.35, 0.85, world_pos.y / max(water_surface_y, 0.1));
		float refl_w = fresnel * screen_reflection * mix(0.38, 1.0, cam_up)
			* mix(0.55, 1.15, dark_water * room_reflection_flip);
		col = mix(col, refl, clamp(refl_w, 0.0, 0.38));
		// #31 — faint double-image ghost at corners (looking through two panes).
		if (corner_ghost > 0.01) {
			vec2 ghost_uv = refl_uv + vec2(0.012, -0.008);
			vec3 ghost = textureLod(screen_tex, clamp(ghost_uv, vec2(0.001), vec2(0.999)), 2.0).rgb;
			float corner = smoothstep(0.55, 1.0, fresnel);
			col = mix(col, ghost, corner * corner_ghost * 0.18);
		}
	}

	// #30 — waterline refraction offset (objects crossing the line break sideways).
	if (waterline_refract > 0.01 && abs(world_pos.y - water_surface_y) < 0.35) {
		float band = 1.0 - smoothstep(0.0, 0.28, abs(world_pos.y - water_surface_y));
		col += vec3(0.08, 0.12, 0.16) * band * waterline_refract * fresnel * 0.35;
		col.r += band * waterline_refract * 0.04;
		col.b -= band * waterline_refract * 0.03;
	}

	// Waterline meniscus brightening on interior glass. The real meniscus
	// is a tiny curved ring where surface tension pulls the water up
	// against the glass. We sell it as:
	//   - a bright thin ring centered just above the water line
	//   - a faint dark hairline just below (the curvature throws a
	//     shadow on real meniscus, a classic faux-3D trick)
	//   - a small horizontal undulation along x/z so the ring has
	//     visible per-pixel variation, not a flat band
	float wl_signed = world_pos.y - water_surface_y;
	float wl = abs(wl_signed);
	float undulate = 0.5 + 0.5 * sin(world_pos.x * 4.2 + world_pos.z * 3.6 + TIME * 0.3);
	float ring_w = mix(0.05, 0.10, undulate);
	float ring_above = smoothstep(ring_w * 1.6, 0.0, abs(wl_signed - 0.025))
		* step(abs(n.y), 0.35) * step(0.0, wl_signed);
	float ring_below = smoothstep(0.025, 0.0, abs(wl_signed + 0.018))
		* step(abs(n.y), 0.35) * step(wl_signed, 0.0);
	col += vec3(0.92, 0.99, 1.0) * ring_above * 0.28;
	col -= vec3(0.10, 0.14, 0.18) * ring_below * 0.22;
	// Broader falloff so the original soft glow still reads.
	float meniscus = (1.0 - smoothstep(0.0, 0.18, wl)) * step(abs(n.y), 0.35);
	col += vec3(0.88, 0.96, 1.0) * meniscus * 0.08;
	// REAL_TANK_FIDELITY #61 — dark/green scum band at mat × glass waterline.
	if (scum_line > 0.01 && abs(n.y) < 0.45) {
		float band = 1.0 - smoothstep(0.0, 0.14, abs(world_pos.y - water_surface_y + 0.02));
		float grit = mix(0.55, 1.0, fp_hash(floor(world_pos.xz * 22.0)));
		col = mix(col, col * vec3(0.55, 0.62, 0.42) + vec3(0.04, 0.06, 0.02),
			band * scum_line * grit * 0.72);
	}

	// Biofilm + condensation green/brown creep from corners. The biofilm
	// here gets a thin-film iridescent shimmer — real glass-side biofilm
	// shows a faint oily rainbow at grazing angles where the bacterial
	// film thickness varies, especially in established tanks.
	float corner = smoothstep(0.55, 1.0, fresnel);
	if (biofilm > 0.01) {
		// Base green-brown creep (preserved from the original).
		vec3 biofilm_base = vec3(0.42, 0.52, 0.38);
		// Iridescent hue rotation: cycle through pink → green → cyan based
		// on a view-angle parameter modulated by world position. Real
		// thin-film interference shifts hue with viewing angle and film
		// thickness; this approximates both at a fragment cost of one
		// sin and one dot.
		float iri_phase = world_pos.y * 0.6 + world_pos.x * 0.4 + dot(n, view_dir) * 2.0;
		vec3 iri_hue = vec3(
			0.5 + 0.5 * sin(iri_phase),
			0.5 + 0.5 * sin(iri_phase + 2.094),  // +120°
			0.5 + 0.5 * sin(iri_phase + 4.189)); // +240°
		// Lift toward iri_hue only where the biofilm is THICK (corner +
		// biofilm uniform both high) so the rainbow only shows where the
		// player would expect a film build-up.
		vec3 biofilm_col = mix(biofilm_base, iri_hue, biofilm_iridescence * 0.45);
		col = mix(col, biofilm_col, biofilm * corner * 0.55);
	}
	col = mix(col, vec3(0.78, 0.84, 0.92), condensation * top_rim * 0.65);
	// #37 — soft low-frequency condensation on the lower third (cool room).
	if (condensation_lower > 0.01) {
		float low = 1.0 - smoothstep(0.0, water_surface_y * 0.38, world_pos.y);
		float blotch = smoothstep(0.35, 0.85, fp_hash(floor(world_pos.xz * 2.2 + world_pos.y * 1.1)));
		col = mix(col, col * 0.92 + vec3(0.10, 0.12, 0.14), low * blotch * condensation_lower * 0.55);
	}
	// #176 — fixture ghost on the front glass, offset by glass thickness.
	if (fixture_ghost > 0.01) {
		vec2 d = world_pos.xz - fixture_ghost_pos.xz;
		float gd = length(d);
		float spot = exp(-gd * gd * 0.08) * fixture_ghost * fresnel;
		col += vec3(1.0, 0.95, 0.82) * spot * 0.35;
	}

	// Chrome rim — a tight high-intensity highlight at the very top
	// edge of the glass, where the polished aluminum or trim catches
	// the light. Narrower than rim_brightness (n.y > 0.85) and brighter
	// (multiplier 1.4) so the lip reads as "this is the rim of the
	// tank, not just a top-facing surface."
	float chrome_band = smoothstep(0.85, 0.99, n.y);
	// Also lift on the OUTSIDE silhouette via fresnel so the rim shines
	// when viewed from below the lip line.
	float chrome_outside = smoothstep(0.78, 1.0, fresnel) * smoothstep(0.45, 0.92, n.y);
	float chrome = max(chrome_band, chrome_outside) * rim_chrome;
	col += vec3(1.0, 0.97, 0.92) * chrome * 0.45;

	// Rare sparkle pixels when light grazes.
	float sp = pow(max(dot(n, normalize(view_dir + vec3(0.2, 0.8, 0.1))), 0.0), 48.0);
	col += vec3(1.0) * sp * sparkle * 0.85;

	// Front-pane specular streak (#57) — soft diagonal highlight sells "glass
	// between you and the tank." Weighted toward panes facing the camera.
	float front_face = pow(max(dot(n, view_dir), 0.0), 0.55);
	float streak_phase = world_pos.x * 1.15 - world_pos.y * 0.72 + world_pos.z * 0.28;
	float streak = smoothstep(0.38, 0.52, sin(streak_phase * 2.4))
		* (1.0 - smoothstep(0.58, 0.72, sin(streak_phase * 2.4 + 1.9)));
	col += vec3(0.96, 0.99, 1.0) * streak * front_face * mix(0.22, 0.42, fresnel);

	// Green edge tint — real aquarium glass reads green in section (#61).
	float edge_section = smoothstep(0.62, 0.94, fresnel) * (1.0 - smoothstep(0.72, 0.98, abs(n.y)));
	col = mix(col, col * vec3(0.82, 1.02, 0.86), edge_section * 0.38);
	// Low-iron edge glow — blue-green luminous rim (REAL_TANK_FIDELITY #25).
	col += vec3(0.35, 0.85, 0.78) * edge_section * edge_glow * 0.42;

	// Green dust algae film (#21–24). Heavier on light-facing / back panels;
	// grazing tracks carve clean radiating paths through the dust.
	if (green_dust > 0.01 && abs(n.y) < 0.55) {
		float panel = mix(0.35, 1.0, dust_panel_bias);
		// Back glass (facing -Z) and light-facing get more dust.
		float face_w = mix(0.55, 1.15, smoothstep(-0.2, 0.85, -n.z));
		float dust_n = fp_hash(floor(world_pos.xy * 14.0 + world_pos.z * 3.0));
		float dust_cov = green_dust * panel * face_w * mix(0.55, 1.0, dust_n);
		vec3 dust_col = vec3(0.28, 0.48, 0.22);
		// Carve grazing tracks.
		float clear = 0.0;
		for (int i = 0; i < 24; i++) {
			vec4 t = graze_tracks[i];
			if (t.w < 0.01) {
				continue;
			}
			float d = length(world_pos - t.xyz);
			clear = max(clear, (1.0 - smoothstep(0.0, t.w, d)) * clamp(t.w * 2.5, 0.0, 1.0));
		}
		dust_cov *= 1.0 - clear * 0.92;
		col = mix(col, mix(col, dust_col, 0.72), clamp(dust_cov, 0.0, 0.78));
	}

	// Salt creep / hard-water spots above the waterline (#32).
	if (salt_creep > 0.01 && world_pos.y > water_surface_y) {
		float spot = step(0.92, fp_hash(floor(world_pos.xz * 18.0 + world_pos.y * 9.0)));
		col = mix(col, col * 1.15 + vec3(0.12, 0.11, 0.09), spot * salt_creep * 0.55);
	}

	// Chromatic fringe on high-contrast glass edges (#35).
	if (chroma_fringe > 0.01) {
		float fringe = pow(fresnel, 2.2) * chroma_fringe;
		col.r += fringe * 0.08;
		col.b -= fringe * 0.06;
	}

	// Dark silhouette frame (#58) — thin ink line at grazing tank edges so
	// the aquarium reads as a contained volume, not an open box.
	float silhouette = smoothstep(0.68, 0.94, fresnel);
	float edge_ink = silhouette * (1.0 - smoothstep(0.82, 0.98, abs(dot(n, view_dir))));
	col = mix(col, col * 0.28 + vec3(0.02, 0.05, 0.08), edge_ink * 0.62);

	// Fresnel rim bloom (#60) — glass brightens as you orbit to grazing angles.
	float fresnel_rim = pow(fresnel, 1.65);
	col += vec3(0.90, 0.96, 1.0) * fresnel_rim * 0.38;

	float alpha = glass_color.a + fresnel * 0.04 + top_rim * 0.03 + meniscus * 0.02 + ring_above * 0.05;
	alpha += chrome * 0.08;
	alpha += fresnel_rim * 0.07 + edge_ink * 0.04;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.02, 0.30);
}
