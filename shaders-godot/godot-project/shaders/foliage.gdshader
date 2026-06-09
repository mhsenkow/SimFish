// Foliage shader - unshaded faceted shading + vertex-shader based sway and flutter.
// Animating foliage in the vertex shader runs at the GPU's full framerate (60fps+)
// smoothly, bypassing the CPU overhead of iterating over thousands of leaf nodes.

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float color_vibrancy : hint_range(0.5, 2.0) = 1.0;
uniform float sway_speed = 1.6;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;
// Subsurface-scattering rim — thin leaves get a warm translucent edge
// when they catch grazing light. View-space fresnel proxy lets us
// approximate the backlit-rim effect without a real light pass.
// Daylight gate matches foliage_mm so the rim fades to almost nothing
// at night (no sun → no backlight); the previous always-on version was
// brightening every leaf edge at midnight and turning the tank into a
// neon forest.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec3 sss_color : source_color = vec3(1.00, 0.92, 0.68);
uniform float sss_daylight : hint_range(0.0, 1.0) = 1.0;
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_top = 99.0;
uniform float fixture_water_floor = 0.0;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 v_world_pos;

void vertex() {
    // 1. Get world space position for spatial variance
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_pos = world_pos;
    
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

vec3 apply_vibrancy(vec3 col, float vib) {
    if (vib <= 1.001) {
        return col;
    }
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    float sat = 1.0 + (vib - 1.0) * 0.75;
    col = mix(vec3(luma), col, sat);
    return col * (1.0 + (vib - 1.0) * 0.10);
}

void fragment() {
    // Face-based voxel shading
    vec3 n = normalize(NORMAL);
    float f;
    if (n.y > 0.7) {
        f = 1.00;        // top
    } else if (n.y < -0.7) {
        f = 0.58;        // bottom
    } else if (abs(n.x) > 0.7) {
        f = 0.88;        // +X / -X sides
    } else {
        f = 0.76;        // +Z / -Z sides
    }
    vec3 col = apply_vibrancy(albedo.rgb * f, color_vibrancy);
    col = apply_global_palette_tint(col, palette_hue_shift, palette_saturation,
        palette_warmth, palette_value);
    // Subsurface rim — at grazing view angles the leaf reads as
    // translucent and picks up a warm tint from light passing through.
    // pow(1-NdotV, 3) keeps the rim a thin sliver instead of a halo.
    // Day-tracked so the rim disappears at night (matches foliage_mm).
    float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
    float rim_amt = sss_strength * (0.25 + 0.75 * max(sss_daylight, tank_fixture_glow * 0.85));
    col = mix(col, col * 0.7 + sss_color * 0.55, rim * rim_amt);
    if (tank_fixture_glow > 0.001 && v_world_pos.y < fixture_water_top - 0.05) {
        float span = max(fixture_water_top - fixture_water_floor, 0.5);
        float depth = clamp((fixture_water_top - v_world_pos.y) / span, 0.0, 1.0);
        float wash = (1.0 - depth * 0.38) * tank_fixture_glow;
        float top_catch = smoothstep(0.20, 0.88, n.y);
        col += tank_fixture_color * wash * mix(0.30, 0.55, top_catch);
        col *= 1.0 + wash * (0.62 + top_catch * 0.42);
    }
    ALBEDO = col;
}
