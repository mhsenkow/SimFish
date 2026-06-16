shader_type canvas_item;

// Frosted-glass panel. Blurs the live scene behind the card, tints it, rounds
// the corners, and draws a hairline rim — a floating "glass modal" look for the
// follow portal. Applied to a ColorRect sized to the card; `rect_px` MUST be set
// to that ColorRect's pixel size so the rounding/rim land on the real edges.
//
// Cosmetic + mouse-ignored: defaults are safe, and a bad uniform can only make
// the frosting look off, never break the panel content drawn on top.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 10.0) = 3.5;
uniform vec4 tint : source_color = vec4(0.07, 0.08, 0.11, 0.55);
uniform vec2 rect_px = vec2(208.0, 330.0);
uniform float radius_px = 18.0;
uniform float border_px = 1.0;
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.18);

float _rrect(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_px;
	float d = _rrect(p, rect_px * 0.5, radius_px);
	if (d > 0.75) {
		COLOR = vec4(0.0);
	} else {
		vec2 ps = SCREEN_PIXEL_SIZE * blur;
		vec4 c = texture(screen_tex, SCREEN_UV) * 0.25;
		c += texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0)) * 0.125;
		c += texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0)) * 0.125;
		c += texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y)) * 0.125;
		c += texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y)) * 0.125;
		c += texture(screen_tex, SCREEN_UV + ps) * 0.0625;
		c += texture(screen_tex, SCREEN_UV - ps) * 0.0625;
		c += texture(screen_tex, SCREEN_UV + vec2(ps.x, -ps.y)) * 0.0625;
		c += texture(screen_tex, SCREEN_UV + vec2(-ps.x, ps.y)) * 0.0625;
		vec3 frosted = mix(c.rgb, tint.rgb, tint.a);
		float fill_a = 1.0 - smoothstep(-0.75, 0.75, d);
		float rim = smoothstep(border_px + 0.75, border_px - 0.75, abs(d + border_px));
		vec3 col = mix(frosted, border_color.rgb, rim * border_color.a);
		COLOR = vec4(col, fill_a);
	}
}
