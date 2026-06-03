shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int material_id = 0;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_speed = 0.8;
uniform float caustic_scale = 1.2;
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
// Wave-surface coupling — caustic intensity modulates with overhead wave
// crests so the spotlight pattern dances with disturbances. Matches the
// water.gdshader formula so caustic peaks track the lit surface.
uniform float wave_amplitude : hint_range(0.0, 0.30) = 0.028;
uniform float wave_speed = 0.85;
uniform float wave_scale = 0.42;
uniform float wave_coupling : hint_range(0.0, 1.0) = 0.65;
// Substrate ripple sculpting. A slow-evolving sand-ripple pattern is
// baked into the top face by a periodic darken/lighten streak. Sim
// time is fed in by the host so the pattern evolves on sim-hour scale
// (long enough that the eye reads it as natural sediment shaping, not
// an animated texture). 0 = no ripples.
uniform float ripple_strength : hint_range(0.0, 0.5) = 0.18;
uniform float ripple_phase = 0.0;
uniform vec2 ripple_dir = vec2(1.0, 0.35);

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

    // Sand-ripple sculpting on top-facing voxels. Build a long-wavelength
    // streak pattern along `ripple_dir`, plus a finer cross-pattern, then
    // shift by `ripple_phase` (set per sim-hour) so the pattern walks
    // slowly across the bed over many minutes. Skipped on vertical /
    // bottom faces; their f is already darker.
    if (ripple_strength > 0.001 && n.y > 0.7) {
        vec2 dir = normalize(ripple_dir);
        float along = world_pos.x * dir.x + world_pos.z * dir.y;
        float across = world_pos.x * dir.y - world_pos.z * dir.x;
        // Two harmonics: a slow base wave and a faster cross-ripple.
        float r = sin(along * 0.9 + ripple_phase) * 0.55
                + sin(along * 2.2 + across * 0.5 + ripple_phase * 1.3) * 0.25
                + sin(across * 1.4 - ripple_phase * 0.7) * 0.20;
        // Map [-1..1] → [-0.5..0.5], scale by strength, apply as a
        // multiplicative shading. Negative side darkens (trough), positive
        // brightens (crest) — same visual logic as real sand ripples lit
        // from above.
        float shade = clamp(0.5 + r * 0.4, 0.0, 1.0);
        base_color *= mix(1.0 - ripple_strength * 0.35,
                          1.0 + ripple_strength * 0.20, shade);
    }
    
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

    // Surface-wave coupling: modulate intensity by overhead wave crests.
    float sw1 = sin(world_pos.x * wave_scale + TIME * wave_speed)
        * cos(world_pos.z * wave_scale * 0.91 - TIME * wave_speed * 0.74);
    float sw2 = sin(world_pos.x * wave_scale * 1.55 - TIME * wave_speed * 1.05)
        * sin(world_pos.z * wave_scale * 1.35 + TIME * wave_speed * 0.88);
    float surface_lift = wave_amplitude * (sw1 * 0.52 + sw2 * 0.33);
    float lift_n = clamp(0.5 + surface_lift / max(wave_amplitude * 0.85, 0.001), 0.0, 1.0);
    float wave_mod = mix(1.0 - wave_coupling * 0.65,
                        1.0 + wave_coupling * 0.65, lift_n);
    float final_intensity = caustics * caustic_intensity * up_fade * light_fade * wave_mod;

    // 3. Add caustics additively to the base voxel color
    ALBEDO = base_color + light_color.rgb * final_intensity;
}
