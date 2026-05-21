shader_type canvas_item;

uniform float border_width : hint_range(0.0, 0.2) = 0.03;
uniform vec4 border_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);

	vec4 tex_color = texture(TEXTURE, UV);

	float alpha = smoothstep(0.5, 0.49, dist);
	float border_alpha = smoothstep(0.5 - border_width, 0.5 - border_width - 0.01, dist);
	vec4 final_color = mix(border_color, tex_color, border_alpha);

	COLOR = vec4(final_color.rgb, final_color.a * alpha);
}
