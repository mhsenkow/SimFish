shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 1=gravel 2=aquasoil 3=sand 4=eco 5=peat — matches TerrainVoxelGrid.CellMaterial
uniform int material_id = 0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 apply_material_grain(vec3 col, vec3 n, int mat_id, vec3 world_pos) {
	vec2 xz = world_pos.xz * 3.5;
	if (mat_id == 3) {
		// Sand — fine pale speckle
		float speck = step(0.78, hash21(floor(xz * 6.0)));
		col = mix(col, col * 1.18, speck * 0.35);
	} else if (mat_id == 1) {
		// Gravel — chunky cool chips
		float chip = step(0.62, hash21(floor(xz * 2.5)));
		col = mix(col, col * 0.82 + vec3(0.08, 0.09, 0.12), chip * 0.45);
	} else if (mat_id == 2) {
		// Aquasoil — warm organic flecks
		float fleck = step(0.7, hash21(floor(xz * 4.0) + 0.31));
		col = mix(col, col * 0.88 + vec3(0.06, 0.03, 0.0), fleck * 0.3);
	} else if (mat_id == 5) {
		// Peat / carbon — glossy dark streaks
		float streak = smoothstep(0.45, 0.85, sin(xz.x * 2.1 + xz.y * 1.7) * 0.5 + 0.5);
		col = mix(col, col * 0.75 + vec3(0.04, 0.02, 0.0), streak * 0.25);
	} else if (mat_id == 4) {
		// Eco-complete — volcanic sparkle
		float spark = step(0.88, hash21(floor(xz * 5.0) + 1.7));
		col = mix(col, col + vec3(0.12, 0.08, 0.14), spark * 0.4);
	}
	return col;
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
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 col = albedo.rgb * f;
	col = apply_material_grain(col, n, material_id, world_pos);
	ALBEDO = col;
}
