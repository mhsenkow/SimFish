// Faceted voxel with alpha — tail fins, veil fins.
shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 0.55);

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.50;
	} else if (abs(n.x) > 0.7) {
		f = 0.82;
	} else {
		f = 0.68;
	}
	ALBEDO = albedo.rgb * f;
	ALPHA = albedo.a * (0.45 + f * 0.35);
}
