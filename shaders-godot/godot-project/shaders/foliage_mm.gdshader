// MultiMesh foliage — hierarchy sway, under-leaf shade, GPU flutter.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float sway_speed = 1.6;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;
uniform float tip_sway_mult : hint_range(1.0, 3.0) = 2.1;
uniform float canopy_shade : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_inst_color;
varying vec3 v_world_pos;

void vertex() {
	v_inst_color = COLOR.rgb;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;

	float height_norm = clamp((world_pos.y - 0.5) / max(water_surface_y - 0.5, 1.0), 0.0, 1.0);
	float height_factor = height_norm * height_norm * tip_sway_mult;

	float time_sway = TIME * sway_speed;
	float phase = world_pos.x * 0.4 + world_pos.z * 0.3;
	float sway = sin(time_sway + phase) * sway_amplitude * height_factor;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.35;

	float time_flutter = TIME * flutter_speed;
	float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0;
	float flutter = sin(time_flutter + phase_flutter) * flutter_amplitude;
	VERTEX.y += flutter * height_factor * 0.3;
}

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
	vec3 col = v_inst_color * f;
	// Under broad canopies / lily pads — dim lower-facing leaf pixels.
	if (n.y < -0.2 && v_world_pos.y > water_surface_y - 0.6) {
		col *= 1.0 - canopy_shade * 0.38 * (1.0 - daylight * 0.35);
	}
	ALBEDO = col;
}
