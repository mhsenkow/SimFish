// Faceted voxel shading + optional underwater caustics / shimmer.

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float color_vibrancy : hint_range(0.5, 2.0) = 1.0;
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
uniform float belly_flash : hint_range(0.0, 1.0) = 0.0;
// Bioluminescence — fish.gd raises this at night for is_bioluminescent
// individuals. 0 = no glow (day or non-bioluminescent), up to 1 = soft
// halo. Reads as direct emission against the unshaded voxel face.
uniform float bioluminescence : hint_range(0.0, 1.0) = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.65, 0.85, 1.0);

vec3 apply_vibrancy(vec3 col, float vib) {
	if (vib <= 1.001) {
		return col;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	float sat = 1.0 + (vib - 1.0) * 0.75;
	col = mix(vec3(luma), col, sat);
	return col * (1.0 + (vib - 1.0) * 0.10);
}

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
		f = 0.58 + belly_flash * 0.35;
	} else if (abs(n.x) > 0.7) {
		f = 0.88;
	} else {
		f = 0.76;
	}
	vec3 col = albedo.rgb * f;
	col = apply_vibrancy(col, color_vibrancy);

	if (aquatic_caustic_intensity > 0.001 && v_world_pos.y < water_surface_y - 0.08) {
		vec2 cuv = v_world_pos.xz * 1.12;
		float t = TIME * 0.76 + day_phase_offset * 6.28318;
		float cwave = sin(cuv.x * 2.0 + t) * sin(cuv.y * 1.65 - t * 0.9)
			+ sin((cuv.x + cuv.y) * 1.3 + t);
		float caustics = smoothstep(0.08, 0.75, cwave) * aquatic_caustic_intensity;
		col += aquatic_light_color * caustics * 0.22;
		float shim = sin(v_world_pos.x * 4.2 + t * 2.1) * aquatic_shimmer * 0.035;
		col += vec3(shim, shim * 0.6, -shim * 0.4);
	}

	// Bioluminescence — soft pulsing additive glow. Pulse phase keyed off
	// world_pos so different voxels on the same fish breathe slightly out
	// of sync, giving a living-organism feel rather than a uniform lamp.
	if (bioluminescence > 0.001) {
		float pulse = 0.65 + 0.35 * sin(TIME * 1.8
			+ v_world_pos.x * 0.7 + v_world_pos.z * 0.5);
		col += biolum_color * bioluminescence * pulse * 0.55;
	}

	ALBEDO = col;
}
