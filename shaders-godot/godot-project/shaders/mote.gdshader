shader_type spatial;
// Suspended particulate ("marine snow") that catches the light (alive pass).
//
// WHY THIS EXISTS. In the reference photos the water is visibly full of
// motes, and they only show where the light is: a scatter of bright specks
// inside the lamp's cone and around a lamp glowing behind the plants, next
// to nothing in the shade. The old snow was 38 opaque grey voxels at one
// flat colour, so it read as dust on the screen rather than stuff in the
// water, and never answered the light at all.
//
// Unshaded like the rest of the pipeline: the beam cone and the backlight
// are evaluated analytically (beam_cone.gdshaderinc), each mote twinkles on
// its own phase as it tumbles, and in the shade it drops to a dim fleck.
render_mode unshaded, cull_back;

#include "res://shaders/palette_tint.gdshaderinc"
#include "res://shaders/beam_cone.gdshaderinc"

global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;

uniform vec4 mote_color : source_color = vec4(0.78, 0.80, 0.76, 1.0);
// Brightness of a mote nobody is lighting. Low: shade hides them.
uniform float shade_level : hint_range(0.0, 1.0) = 0.32;
uniform float glint : hint_range(0.0, 3.0) = 1.35;
// Set by AquariumVisuals from the world's water column.
uniform float water_top = 6.5;
uniform float water_floor = 1.6;

varying vec3 v_wp;
varying float v_seed;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + 0.137);
}

void fragment() {
	float tw = 0.5 + 0.5 * sin(TIME * (1.1 + v_seed * 2.3) + v_seed * 41.0);
	vec3 base = mote_color.rgb * shade_level;
	// How much the lamp lifts this point, as a multiplier on a white mote.
	vec3 lit = iaq_beam_light(v_wp, vec3(1.0)) - vec3(1.0);
	vec3 col = base + max(lit, vec3(0.0)) * mote_color.rgb * glint * (0.45 + tw * 0.75);
	if (iaq_backlight.w > 0.001) {
		vec3 bd = v_wp - iaq_backlight.xyz;
		float att = clamp(iaq_backlight.w / (1.0 + iaq_backlight_tint.a * dot(bd, bd)), 0.0, 1.0);
		col += iaq_backlight_tint.rgb * att * glint * (0.35 + tw * 0.65);
	}
	// Near the surface the light is strongest even without a shaped beam.
	float top = smoothstep(0.55, 1.0, clamp((v_wp.y - water_floor)
		/ max(water_top - water_floor, 0.5), 0.0, 1.0));
	col += mote_color.rgb * top * 0.22 * tw;
	col = apply_water_column_ws(col, v_wp, CAMERA_POSITION_WORLD);
	ALBEDO = col;
}
