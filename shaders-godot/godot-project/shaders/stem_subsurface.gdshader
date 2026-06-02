// Plant stem — faceted + soft green subsurface when backlit.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(0.3, 0.55, 0.28, 1.0);
uniform float subsurface : hint_range(0.0, 1.0) = 0.35;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	float f = (n.y > 0.7) ? 1.0 : ((n.y < -0.7) ? 0.5 : 0.75);
	float back = pow(max(dot(n, normalize(vec3(0.2, 0.9, 0.15))), 0.0), 1.8);
	vec3 glow = albedo.rgb * vec3(0.55, 1.05, 0.45);
	vec3 col = mix(albedo.rgb * f, glow, back * subsurface * daylight);
	ALBEDO = col;
}
