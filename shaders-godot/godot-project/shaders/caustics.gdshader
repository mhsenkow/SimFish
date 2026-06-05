shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float caustic_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_speed = 0.8;
uniform float caustic_scale = 1.2;
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
// Surface-ripple coupling. Caustic intensity modulates with the wave
// crests above the fragment, so the spotlight pattern visibly dances
// when the tank is disturbed (fish dart, surface ripple, etc.). These
// match water.gdshader defaults so caustics line up with the lit water
// surface without extra wiring.
uniform float wave_amplitude : hint_range(0.0, 0.30) = 0.028;
uniform float wave_speed = 0.85;
uniform float wave_scale = 0.42;
uniform float wave_coupling : hint_range(0.0, 1.0) = 0.65;

void fragment() {
    // Get world-space coordinates of the pixel
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // Project caustics onto XZ plane
    vec2 uv = world_pos.xz * caustic_scale;
    float t = TIME * caustic_speed;

    // Surface-wave displacement of the caustic UVs. The position the
    // photon converges to on the substrate is offset laterally by the
    // slope of the water surface directly above — so we sample the
    // surface wave's spatial derivative and shift the UV by it. The
    // pattern visibly slides + warps with the surface motion instead
    // of holding its shape and only flickering brighter/dimmer.
    vec2 surf_uv = world_pos.xz * wave_scale;
    float ts = TIME * wave_speed;
    vec2 surf_grad = vec2(
        cos(surf_uv.x + ts) * cos(surf_uv.y * 0.91 - ts * 0.74)
        + cos(surf_uv.x * 1.55 - ts * 1.05) * sin(surf_uv.y * 1.35 + ts * 0.88) * 1.55,
        -sin(surf_uv.x + ts) * sin(surf_uv.y * 0.91 - ts * 0.74) * 0.91
        + sin(surf_uv.x * 1.55 - ts * 1.05) * cos(surf_uv.y * 1.35 + ts * 0.88) * 1.35);
    // Scale the distortion by amplitude * coupling so a calm surface
    // (low amp / coupling) gives nearly-stationary caustics, while an
    // agitated surface visibly drags the pattern around.
    uv += surf_grad * wave_amplitude * wave_coupling * 6.0;

    // Smooth sine-wave interference pattern (simulating wave crests crossing)
    float w1 = sin(uv.x * 1.2 + t * 0.7) * cos(uv.y * 0.8 - t * 0.5);
    float w2 = sin(uv.y * 1.4 + t * 0.9) * cos(uv.x * 1.1 + t * 0.6);
    float w3 = sin((uv.x + uv.y) * 0.6 - t * 0.3);

    // Combine waves and normalize to [0, 1] range
    float wave = (w1 + w2 + w3 + 1.5) / 3.0;

    // Use a soft smoothstep to get broad, flowing ripple bands instead of sharp dots.
    // Keeps the color transition gentle so the palette quantizer/dither behaves smoothly.
    float caustics = smoothstep(0.2, 0.8, wave) * 0.40;

    // Fade out caustics near the edges of the tank to match the natural light pool falloff
    // (Tank boundary is approx X: [-8.0, 8.0], Z: [-4.0, 4.0])
    float edge_fade_x = clamp(1.0 - abs(world_pos.x) / 7.5, 0.0, 1.0);
    float edge_fade_z = clamp(1.0 - abs(world_pos.z) / 3.5, 0.0, 1.0);
    float light_fade = edge_fade_x * edge_fade_z;

    // Fade out caustics on vertical/underneath walls (only project on top-facing surfaces)
    vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
    float up_fade = clamp(world_normal.y, 0.0, 1.0);

    // Surface-wave coupling: sample the SAME wave formula water.gdshader
    // uses, projected to XZ. High wave crests focus light brighter onto
    // the substrate (real caustics); troughs dim. Multiply rather than
    // add so the existing dual-Voronoi pattern still drives the shape.
    float sw1 = sin(world_pos.x * wave_scale + TIME * wave_speed)
        * cos(world_pos.z * wave_scale * 0.91 - TIME * wave_speed * 0.74);
    float sw2 = sin(world_pos.x * wave_scale * 1.55 - TIME * wave_speed * 1.05)
        * sin(world_pos.z * wave_scale * 1.35 + TIME * wave_speed * 0.88);
    float surface_lift = wave_amplitude * (sw1 * 0.52 + sw2 * 0.33);
    // surface_lift ≈ -wave_amplitude .. +wave_amplitude. Map to [0..1] then
    // lerp the caustic intensity between (1 - coupling) and (1 + coupling).
    float lift_n = clamp(0.5 + surface_lift / max(wave_amplitude * 0.85, 0.001), 0.0, 1.0);
    float wave_mod = mix(1.0 - wave_coupling * 0.65,
                        1.0 + wave_coupling * 0.65, lift_n);

    float final_intensity = caustics * caustic_intensity * up_fade * light_fade * wave_mod;

    ALBEDO = light_color.rgb * final_intensity;
    ALPHA = final_intensity;
}
