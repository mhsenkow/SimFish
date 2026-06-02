// Meniscus ripple — flat pale square that expands and fades. Unshaded so
// palette quantize keeps the voxel surface read.

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform vec4 ripple_color : source_color = vec4(0.86, 0.92, 0.96, 0.55);
uniform float ring_strength : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float ring = smoothstep(0.55, 0.72, r) * (1.0 - smoothstep(0.72, 0.98, r));
	vec3 col = ripple_color.rgb * (0.75 + ring * ring_strength * 0.5);
	float alpha = ripple_color.a * ring * ring_strength;
	ALBEDO = col;
	ALPHA = alpha;
}
