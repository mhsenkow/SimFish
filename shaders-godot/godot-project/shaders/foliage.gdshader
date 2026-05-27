// Foliage shader - unshaded faceted shading + vertex-shader based sway and flutter.
// Animating foliage in the vertex shader runs at the GPU's full framerate (60fps+)
// smoothly, bypassing the CPU overhead of iterating over thousands of leaf nodes.

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float sway_speed = 1.6;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;

void vertex() {
    // 1. Get world space position for spatial variance
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // 2. Slow gentle sway (swimming pool current / wind)
    float time_sway = TIME * sway_speed;
    float phase = world_pos.x * 0.4 + world_pos.z * 0.3;
    float sway = sin(time_sway + phase) * sway_amplitude;
    
    // Scale sway by height (higher vertices sway more)
    // Local Y of the vertex shows the height from the instance origin
    float height_factor = max(0.0, VERTEX.y + 0.4); 
    VERTEX.x += sway * height_factor;
    VERTEX.z += sway * 0.35 * height_factor;
    
    // 3. High-frequency leaf flutter
    float time_flutter = TIME * flutter_speed;
    float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0;
    float flutter = sin(time_flutter + phase_flutter) * flutter_amplitude;
    VERTEX.y += flutter * height_factor * 0.3;
}

void fragment() {
    // Face-based voxel shading
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
    ALBEDO = albedo.rgb * f;
}
