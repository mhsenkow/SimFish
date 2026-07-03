// Shared global material tint — driven by TankConfig via VoxelMat global uniforms.
// Per-shader palette_* uniforms are music-sync overlays (0 / 1 = global only).

global uniform vec4 iaq_palette_fauna;
global uniform vec4 iaq_palette_foliage;
global uniform vec4 iaq_palette_hardscape;
global uniform vec4 iaq_palette_substrate;
global uniform vec4 iaq_palette_water;

vec3 apply_global_palette_tint(vec3 col, float hue_shift, float sat_mult,
		float warmth, float val_mult) {
	if (abs(hue_shift) < 0.0001 && abs(sat_mult - 1.0) < 0.0001 && abs(warmth) < 0.0001 && abs(val_mult - 1.0) < 0.0001) {
		return col;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, sat_mult);
	col *= val_mult;
	col = mix(col, col * vec3(1.08, 1.0, 0.92), max(warmth, 0.0));
	col = mix(col, col * vec3(0.92, 0.98, 1.08), max(-warmth, 0.0));
	if (abs(hue_shift) > 0.0001) {
		float angle = hue_shift * 6.28318530718;
		float s = sin(angle);
		float c = cos(angle);
		mat3 hue_rot = mat3(
			vec3(0.299, 0.587, 0.114) + vec3(0.701, -0.587, -0.114) * c + vec3(0.168, 0.330, -0.497) * s,
			vec3(0.299, 0.587, 0.114) + vec3(-0.299, 0.413, -0.114) * c + vec3(-0.328, 0.035, 0.292) * s,
			vec3(0.299, 0.587, 0.114) + vec3(-0.300, -0.588, 0.886) * c + vec3(1.250, -1.050, -0.203) * s
		);
		col = clamp(hue_rot * col, 0.0, 1.0);
	}
	return col;
}

vec3 apply_category_palette_tint(vec3 col, vec4 global_pal,
		float hue_shift, float sat_mult, float warmth, float val_mult) {
	return apply_global_palette_tint(col,
		global_pal.x + hue_shift,
		global_pal.y * sat_mult,
		global_pal.z + warmth,
		global_pal.w * val_mult);
}
