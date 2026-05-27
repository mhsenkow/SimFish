shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float caustic_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_speed = 0.8;
uniform float caustic_scale = 1.2;
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);

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
    
    // 2. Caustics projection (same logic as caustics.gdshader)
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
    ALPHA = albedo.a;
}
