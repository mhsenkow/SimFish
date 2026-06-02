// Vivarium - palette quantize + Bayer dither (canvas-item version)
// Applied to a CanvasItem (TextureRect) that displays the SubViewport's render.
// The SubViewport runs the 3D voxel scene at low resolution; this shader snaps
// the output to a limited palette with ordered dither between two nearest hits.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int palette_size : hint_range(1, 64) = 48;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform float seasonal_warmth : hint_range(-0.15, 0.15) = 0.0;
uniform vec2 internal_resolution = vec2(384.0, 216.0);

const float bayer4[16] = float[16](
     0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
    12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
     3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
    15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

float bayer_at(vec2 pixel_xy) {
    ivec2 p = ivec2(mod(pixel_xy, 4.0));
    return bayer4[p.y * 4 + p.x] - 0.5;
}

vec3 palette_color(int idx) {
    float u = (float(idx) + 0.5) / float(palette_size);
    return texture(palette_tex, vec2(u, 0.5)).rgb;
}

void fragment() {
    vec3 src = texture(TEXTURE, UV).rgb;
    src = mix(src, src * vec3(1.06, 1.0, 0.94), max(seasonal_warmth, 0.0));
    src = mix(src, src * vec3(0.94, 0.98, 1.06), max(-seasonal_warmth, 0.0));
    float luma = dot(src, vec3(0.299, 0.587, 0.114));
    src = mix(vec3(luma), src, 1.08);
    src *= 1.04;

    // Find two nearest palette colors.
    int ai = 0;
    int bi = 0;
    float best = 1e9;
    float best2 = 1e9;
    for (int i = 0; i < 64; i++) {
        if (i >= palette_size) break;
        vec3 p = palette_color(i);
        float d = dot(src - p, src - p);
        if (d < best) {
            best2 = best; bi = ai;
            best  = d;    ai = i;
        } else if (d < best2) {
            best2 = d; bi = i;
        }
    }

    vec3 a = palette_color(ai);
    vec3 b = palette_color(bi);
    vec3 ab = b - a;
    float denom = max(dot(ab, ab), 1e-6);
    float t = clamp(dot(src - a, ab) / denom, 0.0, 1.0);

    vec2 px = UV * internal_resolution;
    float threshold = 0.5 + bayer_at(px) * dither_strength;
    int chosen = (t > threshold) ? bi : ai;

    COLOR = vec4(palette_color(chosen), 1.0);
}
