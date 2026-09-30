// Fauna MultiMesh voxel shader — per-instance COLOR.rgb replaces per-color materials.
// Same look as voxel.gdshader fauna path; one shared material per fish batch.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float color_vibrancy : hint_range(0.5, 2.0) = 1.24;
uniform float aquatic_caustic_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float water_surface_y = 99.0;
uniform vec3 aquatic_light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float aquatic_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform float day_phase_offset = 0.0;
uniform float tank_fixture_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tank_fixture_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float fixture_water_floor = 0.0;
uniform float belly_flash : hint_range(0.0, 1.0) = 0.0;
uniform float bioluminescence : hint_range(0.0, 1.0) = 0.0;
uniform vec3 biolum_color : source_color = vec3(0.65, 0.85, 1.0);
uniform float room_haze_strength : hint_range(0.0, 1.0) = 0.0;
// Aerial-perspective target for room geometry. Dark on purpose: distance
// pushes a surface toward the ambient it sits in, and in a room whose
// brightest object is meant to be the tank that ambient is dark. A warm
// near-white here is what erased the room value ladder (VISUAL_DIRECTIONS #2)
// — VoxelMat.update_room_haze now caps whatever is written.
uniform vec3 room_haze_color : source_color = vec3(0.20, 0.18, 0.17);
uniform float room_haze_near : hint_range(0.0, 40.0) = 8.0;
uniform float room_haze_far : hint_range(2.0, 80.0) = 28.0;
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sss_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float irid_strength : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_strength : hint_range(0.0, 1.0) = 0.0;
uniform float fin_translucency : hint_range(0.0, 1.0) = 0.0;
uniform float fauna_rim : hint_range(0.0, 1.0) = 0.0;
uniform float fauna_vertex_bend : hint_range(0.0, 1.0) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"
#include "res://shaders/beam_cone.gdshaderinc"

// Rear backlight, published by world.gd (project.godot declares both):
//   iaq_backlight      = (x, y, z, energy)       energy 0 = off
//   iaq_backlight_tint = (r, g, b, falloff k)    att = energy / (1 + k d^2)
// Declared here rather than by including backlight.gdshaderinc: a global
// uniform may be declared once per shader, so if that include is ever added
// to this file these two lines must go.
global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;

// READABILITY AT PIXEL SCALE. A fish is seen by its flank - 15-30 render
// pixels, nearly all of them the one face turned to the camera. That face is
// vertical, so the top-down fixture key gives it ndl ~ 0 and the key floor
// (IAQ_KEY_FLOOR 0.62); it also used to take the 0.76 "other face" value,
// which put every flank at ~0.50 of its albedo. The palette quantizer maps a
// half-bright tangerine or yellow to the same mid brown (#95714e), which is
// why the fauna read as brown boxes. Real fish flanks are guanine mirrors
// that throw the top light sideways; FAUNA_FLANK stands in for that and
// lands a lit flank at ~0.80 of albedo, where orange stays orange.
const float FAUNA_FLANK = 1.22;
const float FAUNA_TOP = 1.00;
const float FAUNA_BELLY = 0.60;
// Fauna take half the water column. Its in-scatter is additive cyan-grey
// (~0.15, 0.31, 0.35 at mid-depth at 0.8), which lifted every orange flank
// into the palette's tan (#b18f6a, measured on a rendered ember tetra);
// at 0.5 orange holds #d97e2c and the depth cue still reads. They are the
// subject of the frame - a fish 20 cm behind clear glass keeps its colour.
const float FAUNA_WATER_MIX = 0.50;
// The fixture's wash and hot core are ADDITIVE lamp colour: on a saturated
// fish they read as pale tan (a lit ember tetra rendered the colour of a
// biscuit). Fauna keep the brightness the lamp gives but take most of the
// hue back from their own colour. Gain is capped so a near-black marking
// is not promoted to a bright colour.
const float FAUNA_CHROMA_KEEP = 0.65;
const float FAUNA_CHROMA_GAIN_MAX = 3.0;

// Direct (unshadowed) cone coverage at a point and the direction to the
// lamp, mirroring iaq_beam_light_n's cone term. Used for the rim catch and
// the iridescent flash, which need the light's direction, not just its sum.
float fauna_beam_direct(vec3 wpos, out vec3 to_lamp) {
	to_lamp = vec3(0.0, 1.0, 0.0);
	if (iaq_beam_cone.w <= 0.001) {
		return 0.0;
	}
	vec3 src = iaq_beam_origin;
	if (iaq_beam_axis.w > 0.5) {
		vec3 ax = iaq_beam_axis.xyz;
		float len2 = dot(ax, ax);
		if (len2 > 1e-6) {
			src = iaq_beam_origin + ax * clamp(dot(wpos - iaq_beam_origin, ax) / len2, -1.0, 1.0);
		}
	}
	vec3 d = wpos - src;
	float dist = length(d);
	if (dist < 0.0001) {
		return 0.0;
	}
	to_lamp = -d / dist;
	float cone = smoothstep(iaq_beam_cone.x, iaq_beam_cone.y, dot(d / dist, normalize(iaq_beam_dir)));
	return cone * (1.0 - smoothstep(iaq_beam_cone.z * 0.55, iaq_beam_cone.z, dist));
}

// Backlight on a fish: a silhouette rim in the lamp colour on edges lying
// between camera and lamp, plus transmission through thin fins (their own
// colour, lit from behind - the way a guppy tail glows against a backlit
// tank). `fin` is 0 for the body, 1 for fin/tail voxels.
vec3 fauna_backlight(vec3 col, vec3 wpos, vec3 n, vec3 v, float fin) {
	float e = iaq_backlight.w;
	if (e <= 0.001) {
		return col;
	}
	vec3 to_l = iaq_backlight.xyz - wpos;
	float d2 = dot(to_l, to_l);
	vec3 l = to_l * inversesqrt(max(d2, 1e-4));
	float att = e / (1.0 + max(iaq_backlight_tint.a, 0.0) * d2);
	float behind = max(dot(-v, l), 0.0);
	float edge = pow(1.0 - clamp(abs(dot(n, v)), 0.0, 1.0), 2.0);
	vec3 tint = iaq_backlight_tint.rgb;
	vec3 rim = tint * edge * (0.30 + 0.70 * behind) * att * 0.45;
	vec3 trans = col * tint * fin * behind * behind * att * 0.60;
	return col + rim + trans;
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

varying vec3 v_inst_color;
varying vec3 v_world_pos;
varying vec4 v_inst_custom;
varying float v_bend;
varying float v_biolum;

// INSTANCE_CUSTOM contract (writers: FaunaVoxelBuilder.pack_custom_r,
// fish.gd _push_fauna_inst_custom, fauna_species_batch.gd):
//   r  fract = bone bend weight (static; head 0.08 .. tail ~1)
//      floor / 32 = bioluminescence (per fish)
//   g  belly flash      b  display vibrancy      a  iridescence (static)
// r used to carry bend OR glow depending on which writer ran last, so every
// tail glowed pale blue at rest and lost its wag once a fish flashed.
void vertex() {
	v_inst_color = COLOR.rgb;
	v_inst_custom = INSTANCE_CUSTOM;
	v_bend = fract(INSTANCE_CUSTOM.r);
	v_biolum = floor(INSTANCE_CUSTOM.r) / 32.0;
	float bend_w = v_bend * fauna_vertex_bend;
	// Body wave (PERFORMANCE #68: pivots carry the macro bend, this is the
	// ripple on top). The phase travels along the pivot's body axis in world
	// space, so voxels further back lag the ones ahead of them and the
	// flank reads as one S-curve rather than every voxel wagging in unison.
	// The amplitude is in world units (a fraction of the voxel's own
	// length or height), converted back to this voxel's local x.
	vec3 ax_z = MODEL_MATRIX[2].xyz;
	float sz = max(length(ax_z), 1e-4);
	float sx = max(length(MODEL_MATRIX[0].xyz), 1e-4);
	float s_ref = max(sz, length(MODEL_MATRIX[1].xyz));
	float along = dot(MODEL_MATRIX[3].xyz, ax_z / sz);
	float wave = sin(TIME * 6.2 - along * 5.0);
	VERTEX.x += wave * bend_w * bend_w * 0.30 * s_ref / sx;
	// Fin flutter: fins (weight ~0.72) shear at a higher rate, trailing edge
	// most, so pectorals and the dorsal visibly scull while hovering.
	float fin = 1.0 - smoothstep(0.06, 0.14, abs(v_bend - 0.72));
	VERTEX.x += sin(TIME * 10.5 - along * 7.0) * fin * fauna_vertex_bend
		* (VERTEX.z + 0.5) * 0.30 * s_ref / sx;
	VERTEX.y += cos(TIME * 5.3 - along * 5.0) * bend_w * 0.03;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 n_ws = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 v_ws = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float belly_local = max(belly_flash, v_inst_custom.g);
	// Face values in WORLD space (they were view-space, so the face turned
	// to the camera - the flank - always took the dim "other" bucket).
	float f;
	if (n_ws.y > 0.7) {
		f = FAUNA_TOP;
	} else if (n_ws.y < -0.7) {
		f = FAUNA_BELLY + belly_local * 0.35;
	} else {
		f = FAUNA_FLANK;
	}
	float fin_w = smoothstep(0.60, 0.72, v_bend);
	vec3 col = v_inst_color * f;
	col = apply_category_palette_tint(col, iaq_palette_fauna,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);
	col = apply_vibrancy(col, color_vibrancy + v_inst_custom.b * 0.32);

	if (aquatic_caustic_intensity > 0.001 && v_world_pos.y < water_surface_y - 0.08) {
		vec2 cuv = v_world_pos.xz * 1.12;
		float t = TIME * 0.76 + day_phase_offset * 6.28318;
		float cwave = sin(cuv.x * 2.0 + t) * sin(cuv.y * 1.65 - t * 0.9)
			+ sin((cuv.x + cuv.y) * 1.3 + t);
		float caustics = smoothstep(0.08, 0.75, cwave) * aquatic_caustic_intensity;
		col += aquatic_light_color * caustics * 0.22;
		float shim = sin(v_world_pos.x * 4.2 + t * 2.1) * aquatic_shimmer * 0.035;
		col += vec3(shim, shim * 0.6, -shim * 0.4);
	}

	if (tank_fixture_glow > 0.001 && v_world_pos.y < water_surface_y - 0.05) {
		float span = max(water_surface_y - fixture_water_floor, 0.5);
		float depth = clamp((water_surface_y - v_world_pos.y) / span, 0.0, 1.0);
		float wash = (1.0 - depth * 0.40) * tank_fixture_glow;
		float top_catch = smoothstep(0.25, 0.88, n.y);
		col += tank_fixture_color * wash * mix(0.34, 0.62, top_catch);
		col *= 1.0 + wash * (0.58 + top_catch * 0.38);
	}

	if (bioluminescence > 0.001 || v_biolum > 0.001) {
		float biolum_local = max(bioluminescence, v_biolum);
		float pulse = 0.65 + 0.35 * sin(TIME * 1.8
			+ v_world_pos.x * 0.7 + v_world_pos.z * 0.5);
		vec3 glow_tint = biolum_color;
		if (length(biolum_color) < 0.01) {
			glow_tint = v_inst_color;
		}
		col += glow_tint * biolum_local * pulse * 0.55;
	}

	if (room_haze_strength > 0.001) {
		float view_z = -VERTEX.z;
		float fog = smoothstep(room_haze_near, room_haze_far, view_z) * room_haze_strength;
		col = mix(col, room_haze_color, fog);
	}

	if (sss_strength > 0.001) {
		float rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 3.0);
		col = mix(col, col * 0.75 + sss_color * 0.5, rim * sss_strength);
	}
	if (fin_translucency > 0.001) {
		float fin_rim = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.0);
		col = mix(col, col * 0.52 + sss_color * 0.42, fin_rim * fin_translucency);
		col *= 1.0 - fin_translucency * 0.10;
	}
	if (irid_strength > 0.001 || v_inst_custom.a > 0.001) {
		float irid_local = max(irid_strength, v_inst_custom.a);
		float fres = pow(1.0 - abs(dot(n, normalize(VIEW))), 2.5);
		float step_f = floor(fres * 6.0) / 6.0;
		float band = step_f * 6.28318;
		vec3 sheen = vec3(0.5 + 0.5 * sin(band),
			0.5 + 0.5 * sin(band + 2.094),
			0.5 + 0.5 * sin(band + 4.188));
		col = mix(col, col * (0.65 + 0.7 * sheen), irid_local * step_f);
	}
	if (metallic_strength > 0.001) {
		float fres_m = pow(1.0 - abs(dot(n, normalize(VIEW))), 3.0);
		vec3 vdir = normalize(VIEW);
		float spec = pow(max(dot(n, normalize(vdir + vec3(0.25, 0.55, 0.18))), 0.0), 14.0);
		float band_m = floor(fres_m * 3.0) / 3.0;
		col += vec3(spec * 0.42) * metallic_strength;
		col = mix(col, col * vec3(1.12, 1.10, 1.06), band_m * metallic_strength * 0.35);
	}
	if (fauna_rim > 0.001) {
		float view_edge = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 1.75);
		float side_edge = 1.0 - abs(n.y);
		float ink = view_edge * mix(0.48, 1.0, side_edge);
		col = mix(col, col * 0.26, ink * fauna_rim);
	}

	// Water column — red dies first with depth and distance. Global uniform, so
	// it costs one compare on anything above the waterline or out of the tank.
	col = mix(col, apply_water_column_ws(col, v_world_pos, CAMERA_POSITION_WORLD),
		FAUNA_WATER_MIX);
	// Analytic fixture cone — the only light model an unshaded pipeline has.
	// See shaders/beam_cone.gdshaderinc (VISUAL_DIRECTIONS #1).
	vec3 base_lit = col;
	vec3 lit = iaq_beam_light_n(v_world_pos, n_ws, col);
	const vec3 LUMA = vec3(0.299, 0.587, 0.114);
	float l_in = max(dot(base_lit, LUMA), 1e-3);
	float gain = min(dot(lit, LUMA) / l_in, FAUNA_CHROMA_GAIN_MAX);
	col = mix(lit, base_lit * gain, FAUNA_CHROMA_KEEP);
	vec3 to_lamp;
	float direct = fauna_beam_direct(v_world_pos, to_lamp);
	if (direct > 0.001) {
		float energy = iaq_beam_cone.w;
		float ndv = clamp(abs(dot(n_ws, v_ws)), 0.0, 1.0);
		// Beam rim: the top edge of a fish catching the fixture, one bright
		// pixel row that separates it from the plants behind.
		float edge = pow(1.0 - ndv, 2.0) * max(n_ws.y, 0.0);
		col += iaq_beam_tint.rgb * edge * direct * energy * 0.35;
		// Iridescent turn flash. Iridophores are angle-selective mirrors:
		// the flank flares in bands as the angle between its normal and the
		// lamp/camera half-vector sweeps, i.e. as the fish yaws or rolls, and
		// holds steady when the fish does. Flank faces only, scaled by the
		// voxel's own iridescence (a).
		float irid_f = max(irid_strength, v_inst_custom.a);
		float flank = 1.0 - smoothstep(0.55, 0.75, abs(n_ws.y));
		if (irid_f > 0.001 && flank > 0.001) {
			vec3 h = normalize(to_lamp + v_ws);
			float ang = acos(clamp(dot(n_ws, h), -1.0, 1.0));
			float flash = pow(0.5 + 0.5 * cos(ang * 7.0), 8.0);
			vec3 sheen = base_lit * 1.35 + vec3(0.10, 0.16, 0.18);
			col = mix(col, max(col, sheen), flash * flank * direct * clamp(irid_f * 1.6, 0.0, 1.0));
		}
	}
	col = fauna_backlight(col, v_world_pos, n_ws, v_ws, fin_w);
	ALBEDO = col;
}
