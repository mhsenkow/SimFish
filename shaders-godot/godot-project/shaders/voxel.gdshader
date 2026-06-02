// Faceted voxel shading + optional underwater caustics / shimmer.

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
uniform float belly_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.50 + belly_flash * 0.35;
	} else if (abs(n.x) > 0.7) {
		f = 0.82;
	} else {
		f = 0.68;
	}
	vec3 col = albedo.rgb * f;

	if (aquatic_caustic_intensity > 0.001 && v_world_pos.y < water_surface_y - 0.08) {
		vec2 cuv = v_world_pos.xz * 1.12;
		float t = TIME * 0.76 + day_phase_offset * 6.28318;
		float cwave = sin(cuv.x * 2.0 + t) * sin(cuv.y * 1.65 - t * 0.9)
			+ sin((cuv.x + cuv.y) * 1.3 + t);
		float caustics = smoothstep(0.08, 0.75, cwave) * aquatic_caustic_intensity;
		col += aquatic_light_color * caustics * 0.16;
		float shim = sin(v_world_pos.x * 4.2 + t * 2.1) * aquatic_shimmer * 0.035;
		col += vec3(shim, shim * 0.6, -shim * 0.4);
	}

	ALBEDO = col;
}
