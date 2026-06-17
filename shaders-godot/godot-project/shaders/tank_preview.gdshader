// Animated "living tank" placeholder for menu cards that have no saved
// thumbnail yet. A drifting water gradient + caustic shimmer + a couple of
// slow silhouettes, so the gallery feels alive instead of showing flat rects.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.16, 0.34, 0.42, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.05, 0.10, 0.16, 1.0);
uniform vec4 fish_color : source_color = vec4(0.85, 0.62, 0.30, 1.0);
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// Depth gradient.
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
	float t = TIME * 0.6 + seed * 7.0;

	// Caustic shimmer (cheap sine web) brighter near the top.
	float c = sin(uv.x * 18.0 + t) * cos(uv.y * 14.0 - t * 0.8)
		+ sin((uv.x + uv.y) * 11.0 + t * 1.2);
	float caust = smoothstep(0.6, 1.8, c + 1.2) * (1.0 - uv.y) * 0.18;
	col += vec3(0.6, 0.8, 0.9) * caust;

	// God-ray slabs drifting slowly across.
	float ray = smoothstep(0.45, 0.0, abs(fract(uv.x * 1.5 - t * 0.04) - 0.5));
	col += vec3(0.5, 0.7, 0.85) * ray * (1.0 - uv.y) * 0.05;

	// A couple of drifting fish silhouettes.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float phase = t * (0.25 + fi * 0.07) + fi * 2.1 + seed * 3.0;
		vec2 fp = vec2(fract(phase) , 0.3 + 0.18 * fi + 0.05 * sin(phase * 3.0));
		// Swim direction flips each lap; squash the body into a fish ellipse.
		vec2 d = (uv - fp);
		d.x *= 3.2;
		float body = smoothstep(0.05, 0.0, length(d));
		// Tail wag wedge behind the body.
		float tail = smoothstep(0.035, 0.0, length(vec2((d.x + 0.10) * 1.4, d.y * 1.6)))
			* (0.6 + 0.4 * sin(phase * 12.0));
		col = mix(col, fish_color.rgb * (0.7 + 0.3 * fi), clamp(body + tail * 0.5, 0.0, 0.9));
	}

	// Soft vignette.
	vec2 vc = uv - 0.5;
	col *= 1.0 - dot(vc, vc) * 0.6;
	COLOR = vec4(col, 1.0);
}
