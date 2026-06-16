shader_type canvas_item;

uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float zoom : hint_range(1.0, 8.0) = 3.5;
uniform float border_width : hint_range(0.0, 0.2) = 0.02;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.32);
// Viewport width / height. Corrects the magnifier so a square porthole shows an
// undistorted (un-squished) crop of the wide tank render. 1.0 = no correction.
uniform float aspect = 1.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);

	// Magnify the main tank render around the tracked creature. The x offset is
	// divided by aspect so equal on-screen distances sample equal world pixels.
	vec2 sample_uv = vec2(centered_uv.x / aspect, centered_uv.y) / zoom + center_uv;
	vec4 tex_color = texture(TEXTURE, sample_uv);

	float alpha = smoothstep(0.5, 0.49, dist);
	float border_alpha = smoothstep(0.5 - border_width, 0.5 - border_width - 0.01, dist);
	vec4 final_color = mix(border_color, tex_color, border_alpha);

	COLOR = vec4(final_color.rgb, final_color.a * alpha);
}
