// Faceted voxel shading - no actual lights, just face-based brightness ramps.
//
// This is the classic "voxel game" look (Minecraft, Cube World): each face of a
// cube gets a different brightness multiplier based on its world-space normal.
// Top faces brightest, bottom faces dimmest, sides in between. The palette
// quantize shader at the end of the pipeline is what enforces the limited
// color set - this shader just gives us 3D-readable shading.
//
// Set `albedo` per-instance via ShaderMaterial.set_shader_parameter("albedo", color).

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
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
