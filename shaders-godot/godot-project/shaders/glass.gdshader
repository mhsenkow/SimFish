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
	float undulate = 0.5 + 0.5 * sin(world_pos.x * 4.2 + world_pos.z * 3.6);
	float ring_w = mix(0.05, 0.10, undulate);
	float ring_above = smoothstep(ring_w * 1.6, 0.0, abs(wl_signed - 0.025))
		* step(abs(n.y), 0.35) * step(0.0, wl_signed);
	float ring_below = smoothstep(0.025, 0.0, abs(wl_signed + 0.018))
		* step(abs(n.y), 0.35) * step(wl_signed, 0.0);
	col += vec3(0.92, 0.99, 1.0) * ring_above * 0.55;
	col -= vec3(0.10, 0.14, 0.18) * ring_below * 0.35;
	// Broader falloff so the original soft glow still reads.
	float meniscus = (1.0 - smoothstep(0.0, 0.18, wl)) * step(abs(n.y), 0.35);
	col += vec3(0.88, 0.96, 1.0) * meniscus * 0.16;

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

	float alpha = glass_color.a + fresnel * 0.04 + top_rim * 0.03 + meniscus * 0.02 + ring_above * 0.05;
	alpha += chrome * 0.08;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.02, 0.30);
}
