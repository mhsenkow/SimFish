// Rising air bubble — rim highlight, O₂ tint, soft shadow read.

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 bubble_color : source_color = vec4(0.78, 0.92, 0.96, 0.42);
uniform float highlight : hint_range(0.0, 1.5) = 1.0;
uniform float o2_tint : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.35;
// HDR shoulder for palette-quantize night burnthrough (pearling, filter bubbles).
uniform float emissive_boost : hint_range(1.0, 1.6) = 1.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	float ndv = clamp(dot(n, view_dir), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.4);
	float spec = pow(max(dot(n, normalize(view_dir + vec3(0.35, 0.55, 0.2))), 0.0), 18.0);

	vec3 o2_col = mix(bubble_color.rgb, vec3(0.62, 0.88, 1.0), o2_tint * 0.45);
	vec3 core = o2_col * (0.55 + ndv * 0.25);
	vec3 edge = o2_col * 1.35 + vec3(0.12, 0.18, 0.22) * highlight;
	vec3 col = mix(core, edge, rim);
	col += vec3(1.0) * spec * 0.28 * highlight;
	col *= 1.0 - shadow_strength * (1.0 - ndv) * 0.25 * step(n.y, -0.55);

	float alpha = bubble_color.a * (0.28 + rim * 0.62 + spec * 0.12);
	col *= emissive_boost;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.08, 0.72);
}
