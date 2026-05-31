shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int material_id = 0;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_speed = 0.8;
uniform float caustic_scale = 1.2;
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 apply_material_grain(vec3 col, int mat_id, vec3 world_pos) {
	vec2 xz = world_pos.xz * 3.5;
	if (mat_id == 3) {
		float speck = step(0.78, hash21(floor(xz * 6.0)));
		col = mix(col, col * 1.18, speck * 0.35);
	} else if (mat_id == 1) {
		float chip = step(0.62, hash21(floor(xz * 2.5)));
		col = mix(col, col * 0.82 + vec3(0.08, 0.09, 0.12), chip * 0.45);
	} else if (mat_id == 2) {
		float fleck = step(0.7, hash21(floor(xz * 4.0) + 0.31));
		col = mix(col, col * 0.88 + vec3(0.06, 0.03, 0.0), fleck * 0.3);
	} else if (mat_id == 5) {
		float streak = smoothstep(0.45, 0.85, sin(xz.x * 2.1 + xz.y * 1.7) * 0.5 + 0.5);
		col = mix(col, col * 0.75 + vec3(0.04, 0.02, 0.0), streak * 0.25);
	} else if (mat_id == 4) {
		float spark = step(0.88, hash21(floor(xz * 5.0) + 1.7));
		col = mix(col, col + vec3(0.12, 0.08, 0.14), spark * 0.4);
	}
	return col;
}

void fragment() {
    // 1. Base voxel shading
    vec3 n = normalize(NORMAL);
    float f;
    if (n.y > 0.7) {
        f = 1.00;        // top
    } else if (n.y < -0.7) {
        f = 0.50;        // bottom
    } else if (abs(n.x) > 0.7) {
        f = 0.82;        // +X / -X sides
    } else {
        f = 0.68;        // +Z / -Z sides
    }
    vec3 base_color = albedo.rgb * f;
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    base_color = apply_material_grain(base_color, material_id, world_pos);
    
    // 2. Caustics projection (same logic as caustics.gdshader)
    vec2 uv = world_pos.xz * caustic_scale;
    float t = TIME * caustic_speed;
    
    float w1 = sin(uv.x * 1.2 + t * 0.7) * cos(uv.y * 0.8 - t * 0.5);
    float w2 = sin(uv.y * 1.4 + t * 0.9) * cos(uv.x * 1.1 + t * 0.6);
    float w3 = sin((uv.x + uv.y) * 0.6 - t * 0.3);
    
    float wave = (w1 + w2 + w3 + 1.5) / 3.0;
    float caustics = smoothstep(0.2, 0.8, wave) * 0.40;
    
    float edge_fade_x = clamp(1.0 - abs(world_pos.x) / 7.5, 0.0, 1.0);
    float edge_fade_z = clamp(1.0 - abs(world_pos.z) / 3.5, 0.0, 1.0);
    float light_fade = edge_fade_x * edge_fade_z;
    
    vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
    float up_fade = clamp(world_normal.y, 0.0, 1.0);
    
    float final_intensity = caustics * caustic_intensity * up_fade * light_fade;
    
    // 3. Add caustics additively to the base voxel color
    ALBEDO = base_color + light_color.rgb * final_intensity;
}
