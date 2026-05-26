shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 beam_color : source_color = vec4(0.55, 0.75, 1.0, 0.08);
uniform float speed : hint_range(0.1, 5.0) = 1.0;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.8;
uniform float edge_fade : hint_range(0.0, 1.0) = 0.15;
uniform float falloff_exponent : hint_range(1.0, 5.0) = 2.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// UV.y is 0 at the top cap of the cylinder/cone, and 1 at the bottom.
	float v_y = UV.y;
	
	// Fresnel/edge falloff: we fade the sides of the beam based on view angle.
	// We want it to be brightest in the center (facing the camera) and fade to 0 at the edges
	// so the polygonal cylinder edges blend smoothly into transparency.
	float fresnel = abs(dot(NORMAL, VIEW));
	
	// Smooth vertical fade: fade near the top light source (edge_fade)
	// and near the substrate (1.0 - edge_fade) to prevent harsh intersection rings.
	float fade_top = smoothstep(0.0, edge_fade, v_y);
	float fade_bottom = 1.0 - smoothstep(1.0 - edge_fade, 1.0, v_y);
	float top_bottom_fade = fade_top * fade_bottom;
	
	// Shimmering underwater god-ray noise using UV wrapping circular coordinates.
	// This ensures the noise wraps perfectly around the cylinder.
	float u_angle = UV.x * 2.0 * 3.14159265;
	vec2 circle_coord = vec2(cos(u_angle), sin(u_angle));
	float time = TIME * speed;
	float noise = sin(circle_coord.x * noise_scale + time) * 
	              cos(circle_coord.y * noise_scale - time * 0.7) * 
	              sin(v_y * noise_scale * 2.0 + time * 1.3);
	
	// Map noise from [-1, 1] to [0.75, 1.0] for gentle animated intensity variations.
	float shimmer = 0.875 + 0.125 * noise;
	
	// Combine the calculations
	float alpha = beam_color.a * pow(fresnel, falloff_exponent) * top_bottom_fade * shimmer;
	
	ALBEDO = beam_color.rgb;
	ALPHA = alpha;
}
