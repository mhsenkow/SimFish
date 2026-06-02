// Tank glass — faint tint, shape highlights, room reflection, sparkle read.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 glass_color : source_color = vec4(0.7, 0.85, 0.9, 0.045);
uniform float rim_brightness : hint_range(0.0, 1.0) = 0.35;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.22;
uniform float sparkle : hint_range(0.0, 1.0) = 0.0;
uniform float shape_band : hint_range(0.0, 1.0) = 0.0;
uniform float tank_shape_id : hint_range(0.0, 3.0) = 0.0;
uniform float biofilm : hint_range(0.0, 1.0) = 0.0;
uniform float condensation : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 6.5;

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

	// Waterline meniscus brightening on interior glass.
	float wl = abs(world_pos.y - water_surface_y);
	float meniscus = (1.0 - smoothstep(0.0, 0.18, wl)) * step(abs(n.y), 0.35);
	col += vec3(0.88, 0.96, 1.0) * meniscus * 0.28;

	// Biofilm + condensation green/brown creep from corners.
	float corner = smoothstep(0.55, 1.0, fresnel);
	col = mix(col, vec3(0.42, 0.52, 0.38), biofilm * corner * 0.55);
	col = mix(col, vec3(0.78, 0.84, 0.92), condensation * top_rim * 0.65);

	// Rare sparkle pixels when light grazes.
	float sp = pow(max(dot(n, normalize(view_dir + vec3(0.2, 0.8, 0.1))), 0.0), 48.0);
	col += vec3(1.0) * sp * sparkle * 0.85;

	float alpha = glass_color.a + fresnel * 0.04 + top_rim * 0.03 + meniscus * 0.02;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.02, 0.22);
}
