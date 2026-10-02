// Voxel-aquarium water volume — depth tint, dual ripples, meniscus, caustics, fog.

shader_type spatial;
// depth_draw_opaque matches the shipped look. Floaters are placed above the
// water mesh so depth doesn't eat them (see world.gd).
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.62, 0.66, 0.12);
uniform vec4 deep_color : source_color = vec4(0.04, 0.10, 0.14, 0.22);
uniform vec4 tint_color : source_color = vec4(0.83, 0.55, 0.25, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float bloom_haze : hint_range(0.0, 1.0) = 0.0;
uniform float wave_amplitude : hint_range(0.0, 0.12) = 0.028;
uniform float wave2_amplitude : hint_range(0.0, 0.08) = 0.012;
uniform float wave_speed = 0.85;
uniform float wave_scale = 0.42;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 0.55;
// Adaptive quality is driven by Main's existing shader-cost ladder.  The
// default (0) preserves the full three-scale water-light pattern.  Lower
// tiers remove only high-frequency layers first, so stressed hardware still
// reads as moving water rather than a flat tinted box.
uniform int aquatic_detail : hint_range(0, 3) = 0;
uniform vec3 light_color : source_color = vec3(0.55, 0.75, 0.95);
uniform float water_floor_y = 1.0;
uniform float water_surface_y = 6.5;
uniform float depth_fog : hint_range(0.0, 1.0) = 0.45;
// Posterize the depth fog into discrete bands instead of a smooth
// gradient — keeps the look consistent with the 48-color palette and
// makes the depth dropoff read as a chunky pixel-art lineweight
// rather than blended ramp. 0 = smooth (legacy); 1 = fully posterized.
uniform float depth_fog_bands : hint_range(0.0, 1.0) = 0.75;
uniform int depth_fog_band_count : hint_range(2, 12) = 6;
uniform float day_phase_offset = 0.0;
uniform float ice_lens : hint_range(0.0, 1.0) = 0.0;
uniform float moonlight : hint_range(0.0, 1.0) = 0.0;
uniform float sunset_warmth : hint_range(0.0, 1.0) = 0.0;
uniform float tank_shape_id : hint_range(0.0, 3.0) = 0.0;
// Bacterial bloom — milky pale cast during the early cycling phase.
// Real tanks during ammonia-spike cycles look hazy white as
// heterotrophic bacteria explode and fail to colonize substrate. Clears
// once the cycle establishes and ammonia drops.
uniform float bacterial_bloom : hint_range(0.0, 1.0) = 0.0;
uniform vec3 bloom_color : source_color = vec3(0.86, 0.88, 0.84);
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;
// Screen-space refraction — the single biggest "this is real water" lever.
// The scene behind the glass is sampled with a UV offset driven by the
// surface wave slope, so plants/fish/substrate seen through the water gently
// wobble. Kept subtle by default so the chunky pixel look survives.
// SCREEN-SPACE REFRACTION WAS REMOVED HERE (VISUAL_DIRECTIONS #12).
//
// It never ran. world_atmosphere.gd enabled it only when
// `OS.get_name() != "macOS" and RenderingServer.get_current_rendering_method()
// == "forward_plus"`, and project.godot ships `renderer/rendering_method="mobile"`
// (with the web override also mobile), so the second half of that condition was
// false in every build on every platform. The uniform, the branch and the
// screen-texture sampler had been carried, and described in this header as
// "the single biggest 'this is real water' lever", for as long as they had
// existed without once executing.
//
// Deleted rather than switched on: the reason macOS was excluded — Metal
// returning black for hint_screen_texture and painting a dark slab over the
// tank — is real and is the platform this is developed on, so enabling the
// path would mean shipping an effect nobody here can see fail. The wobble
// itself is worth having; the mobile-safe way to get it is to displace the
// surface's own terms rather than sample the screen, and that is a deliberate
// piece of work rather than a flag flip.
// Depth absorption — warm wavelengths (red, then green) fade with depth, the
// way real water swallows red light first. Gives the column a sense of volume.
uniform float depth_absorption : hint_range(0.0, 1.0) = 0.4;
// Shader depth haze for Metal/macOS where volumetric fog is off (#11, #20).
uniform float aerial_haze : hint_range(0.0, 1.0) = 0.0;
uniform float surface_reflection : hint_range(0.0, 1.0) = 0.24;
uniform float underside_mirror : hint_range(0.0, 1.0) = 0.24;
uniform vec3 room_sky_color : source_color = vec3(0.55, 0.48, 0.42);
// Top-down / pond mode: calm glass (#17) + health sheen (#20).
uniform float pond_calm : hint_range(0.0, 1.0) = 0.0;
uniform float pond_health_gloss : hint_range(0.0, 1.0) = 1.0;
uniform float pond_wind : hint_range(0.0, 1.0) = 0.0;
uniform float pond_wake_activity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 pond_color_spill : source_color = vec3(0.0);
uniform float pond_color_spill_gain : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pond_dimple_points[12];
// Specular glint band — tracks fixture position along tank width (#52).
uniform float fixture_glint_center : hint_range(-24.0, 24.0) = 0.0;
uniform float fixture_glint_width : hint_range(0.5, 16.0) = 7.0;
uniform float tank_half_depth : hint_range(1.0, 24.0) = 4.0;
uniform float flow_distortion : hint_range(0.0, 1.0) = 0.0;
uniform float turbidity_haze : hint_range(0.0, 1.0) = 0.0;
uniform float floor_bounce : hint_range(0.0, 1.0) = 0.0;
// REAL_TANK_FIDELITY water-as-medium leftovers.
uniform float tannin_depth_ramp : hint_range(0.0, 1.0) = 0.0;
uniform float protein_film : hint_range(0.0, 1.0) = 0.0;
uniform float thermal_seam : hint_range(0.0, 1.0) = 0.0;
uniform float thermal_seam_y = 4.5;
uniform vec3 heater_world_pos = vec3(0.0);
uniform float heater_shimmer : hint_range(0.0, 1.0) = 0.0;
uniform vec3 bubble_column_pos = vec3(0.0);
uniform float bubble_column_glow : hint_range(0.0, 1.0) = 0.0;
uniform float column_own_color : hint_range(0.0, 1.0) = 0.0;
uniform vec3 column_tint_rgb : source_color = vec3(0.55, 0.72, 0.42);
uniform float bed_attenuation : hint_range(0.0, 1.0) = 0.35;
uniform float turbidity_cone : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fixture_world_pos = vec3(0.0, 8.0, 0.0);
// ---- Surface specular (VISUAL_DIRECTIONS #3) ----
// The one place a real aquarium photograph is blown out is the water surface
// directly under the fixture, and this render had nothing like it: a capture
// measured p99 at 158/255, with the palette's own `ffffff` and `f8f4e0` rungs
// never selected anywhere in the frame. The existing glint and glass-rim terms
// are 0.16-0.22 additive washes on a translucent surface — they tint, they do
// not blow out.
//
// A tight Blinn lobe against the fixture position does. Deliberately narrow:
// the point is a small hot band the eye reads as wet, not a brighter tank.
// gain 0 is off; world_atmosphere.gd drives it.
uniform float surface_spec_gain : hint_range(0.0, 3.0) = 0.0;
// 190 was a mirror. A rippled surface is not a mirror — its glitter path is
// broad and multi-lobed, and at a 512x288 internal render a lobe that tight
// falls between pixels: the first version of this moved the frame's p99 by
// nothing at all.
uniform float surface_spec_power : hint_range(8.0, 400.0) = 56.0;
// ---- Real-water surface (2026-09-23) ----
// The vertex waves lift the cap but never touched its NORMAL, so every
// surface term — fresnel, the fixture specular, the underside — saw a flat
// sheet: the specular under the lamp rendered as one smooth white oval.
// surface_ripple_slope perturbs the cap's normal with an analytic capillary
// ripple (three directional sines, no texture), which breaks that oval into a
// glitter path and makes the fresnel shimmer. 0 = the old flat sheet.
uniform float surface_ripple_slope : hint_range(0.0, 0.5) = 0.26;
// Total internal reflection. Seen from below (the camera under the waterline,
// looking up through the front glass), a real surface is a silver mirror
// outside Snell's window (~48.6 deg from vertical) and a bright window onto
// the room inside it. The old underside branch lived inside a view-space
// "faces up" test, so from below — where the cap faces down — it never ran.
uniform float tir_strength : hint_range(0.0, 1.0) = 1.0;
// Baked two-layer caustic tile (scripts/baked_caustics.gd). 1 = two texture
// reads per web instead of a 3x3 Worley search; the water volume evaluated
// up to five of those per fragment over most of the screen.
uniform sampler2D baked_caustics_tex : filter_linear, repeat_enable;
uniform float caustic_baked = 0.0;
// ---- Underside mirror (alive pass, 2026-09-29) ----
// Photographed from below, a planted tank's surface is the BRIGHTEST thing in
// the frame: a lamp-coloured mirror carrying an upside-down copy of the fish
// packed under it, peppered with trapped bubbles and film. The old mirror was
// a constant grey-blue at <= 65% alpha over the dark lid, which is exactly the
// dull grey plane the captures showed.
//
// under_glow scales the mirror sheet. under_reflect mixes in the reflected
// tank, read from the screen copy the glass shader already forces (so the
// sample costs no extra pass). It is sampled with filter_linear and LOD 0:
// the Mobile renderer builds no mip chain for the screen copy, and a
// mipmapped sampler there reads undefined levels - the black slab that got
// screen reads banned on macOS in the first place. 0 = sheet only.
uniform float under_glow : hint_range(0.0, 2.0) = 1.0;
uniform float under_reflect : hint_range(0.0, 1.0) = 0.55;
// How far below the surface the reflected ray is assumed to land before it
// meets something. A constant is wrong in general and right where it matters:
// the fish crowd and the valli runs live in the top couple of units.
uniform float under_reach : hint_range(0.2, 8.0) = 2.4;
uniform sampler2D under_screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// Surface film + trapped bubbles. Real ones gather where the surface is
// still: under and between floaters and along the glass.
uniform float surface_film : hint_range(0.0, 1.0) = 0.55;
// xz = world centre, z = canopy radius, w = 1 while the floater is live.
// Pushed by AquariumVisuals.sync_floater_shadows at the cosmetic tick.
uniform vec4 floater_pts[32];
uniform int floater_count = 0;
// Radial fallback for curved tanks: > 0 means UV.x is not the cap's radial
// coordinate and the edge band is measured as length(xz) / edge_radius.
uniform float edge_radius = 0.0;
global uniform vec4 iaq_beam_cone;
global uniform vec4 iaq_beam_tint;
global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;

#include "res://shaders/palette_tint.gdshaderinc"

varying vec3 world_pos;
varying float surface_lift;

// The lamp's own colour at unit brightness: the fixture beam when it is on,
// the water's light colour otherwise.
vec3 lamp_rgb(vec3 fallback) {
	vec3 lamp = mix(fallback, iaq_beam_tint.rgb, step(0.001, iaq_beam_cone.w));
	return lamp / max(max(lamp.r, lamp.g), max(lamp.b, 0.001));
}

// Floater proximity at a surface point: x = inside a canopy (0..1),
// y = the still-water ring around it where film and bubbles pile up.
vec2 floater_cover(vec2 p) {
	float inside = 0.0;
	float ring = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= floater_count) {
			break;
		}
		vec4 f = floater_pts[i];
		if (f.w < 0.5) {
			continue;
		}
		float d = length(p - f.xy);
		float r = max(f.z, 0.05);
		inside = max(inside, 1.0 - smoothstep(r * 0.62, r, d));
		ring = max(ring, smoothstep(r * 0.5, r * 0.95, d) * (1.0 - smoothstep(r * 1.1, r * 2.2, d)));
	}
	return vec2(inside, ring);
}

// Organic caustics web (matches caustics.gdshader) — drifting Worley cells.
vec2 caustic_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
float worley_caustic(vec2 uv, float tt) {
	vec2 g = floor(uv);
	vec2 fr = fract(uv);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 fp = caustic_hash(g + cell);
			vec2 pt = cell + 0.5 + 0.42 * sin(tt + 6.2831 * fp);
			float d = length(pt - fr);
			if (d < d1) { d2 = d1; d1 = d; }
			else if (d < d2) { d2 = d; }
		}
	}
	return pow(clamp(d2 - d1, 0.0, 1.0), 1.6);
}

// One caustic web sample: baked tile when bound, live Worley otherwise.
float water_web(vec2 uv, float tt) {
	if (caustic_baked > 0.5) {
		float a = texture(baked_caustics_tex, uv * 0.25 + vec2(tt * 0.031, -tt * 0.019)).r;
		float b = texture(baked_caustics_tex, uv * 0.31 + vec2(-tt * 0.022, -tt * 0.027)).g;
		return clamp(a * 0.62 + b * 0.42 + a * b * 0.9, 0.0, 1.0);
	}
	return worley_caustic(uv, tt);
}

// Analytic capillary-ripple slope (d height / d xz) at a world XZ. Three
// directional waves at unrelated wavelengths so the glitter never grids.
vec2 ripple_slope(vec2 p, float tt) {
	const vec2 D1 = vec2(0.83, 0.56);
	const vec2 D2 = vec2(-0.47, 0.88);
	const vec2 D3 = vec2(0.21, -0.98);
	float p1 = dot(p, D1) * 2.3 + tt * 1.7;
	float p2 = dot(p, D2) * 3.1 - tt * 2.1;
	float p3 = dot(p, D3) * 4.7 + tt * 2.9;
	return D1 * cos(p1) * 0.55 + D2 * cos(p2) * 0.30 + D3 * cos(p3) * 0.15;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	vec3 n = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	surface_lift = 0.0;
	if (n.y > 0.45) {
		float w1 = sin(wp.x * wave_scale + TIME * wave_speed)
			* cos(wp.z * wave_scale * 0.91 - TIME * wave_speed * 0.74);
		float w2 = sin(wp.x * wave_scale * 1.55 - TIME * wave_speed * 1.05)
			* sin(wp.z * wave_scale * 1.35 + TIME * wave_speed * 0.88);
		float w3 = sin(wp.x * wave_scale * 3.2 + TIME * wave_speed * 2.1)
			* cos(wp.z * wave_scale * 2.8 - TIME * wave_speed * 1.9);
		float wind_w = sin(wp.x * wave_scale * 0.55 + TIME * wave_speed * 0.35 + wp.z * 0.08)
			* cos(wp.z * wave_scale * 0.48 - TIME * wave_speed * 0.28);
		float calm_waves = mix(1.0, 0.12, pond_calm);
		float wake_amp = 1.0 + pond_wake_activity * 0.55;
		surface_lift = (wave_amplitude * (w1 * 0.52 + w2 * 0.33)
			+ wave2_amplitude * w3
			+ pond_wind * wave_amplitude * 0.35 * wind_w) * calm_waves * wake_amp;
		for (int i = 0; i < 12; i++) {
			vec4 pt = pond_dimple_points[i];
			if (pt.w < 0.01) {
				continue;
			}
			vec2 d = wp.xz - pt.xz;
			float r2 = dot(d, d);
			surface_lift -= pt.w * exp(-r2 * 7.5) * pt.z * 0.14;
		}
		VERTEX.y += surface_lift;
	}
}

void fragment() {
	float depth_span = max(water_surface_y - water_floor_y, 0.15);
	float depth_norm = clamp((water_surface_y - world_pos.y) / depth_span, 0.0, 1.0);
	// Quantize depth_norm into N discrete bands for the posterized
	// look, then blend back toward the smooth value by (1 - bands).
	// Result: smooth gradient when depth_fog_bands == 0, hard step
	// terraces when == 1. depth_fog_band_count controls the visible
	// step count; 6 is calibrated so each band is roughly one chunky
	// pixel-art tonal step in a 1.5 m-tall water column.
	float band_count = float(depth_fog_band_count);
	float depth_quant = floor(depth_norm * band_count + 0.5) / band_count;
	float ign = fract(52.9829189 * fract(0.06711056 * world_pos.x + 0.00583715 * world_pos.z));
	depth_quant += (ign - 0.5) * (0.85 / band_count) * depth_fog_bands;
	depth_quant = clamp(depth_quant, 0.0, 1.0);
	float depth_used = mix(depth_norm, depth_quant, depth_fog_bands);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_used * depth_used);
	col = apply_category_palette_tint(col, iaq_palette_water,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);

	// Depth fog toward deep color — also uses the quantized depth so
	// the fog density steps in the same bands as the depth gradient.
	col = mix(col, deep_color.rgb, depth_used * depth_fog * 0.35);

	// Depth absorption: red goes first, then green, leaving the deep column
	// blue-shifted. Stronger than before so "this is water" reads at a glance (#32).
	col *= mix(vec3(1.0),
		vec3(1.0 - depth_used * 0.72, 1.0 - depth_used * 0.32, 1.0),
		depth_absorption);
	// Mid-column cyan shift — water as a medium, not tinted glass (#35).
	col = mix(col, col * vec3(0.92, 1.02, 1.08), depth_used * (1.0 - depth_used) * 0.28);

	// Aerial perspective — back of tank desaturates into the water tint (#11, #33).
	// Background plants live at −Z; the front glass is +Z (see world._spawn_z_band).
	// horiz_depth must rise toward the BACK so near subjects keep local contrast
	// while the far wall retains depth haze (HOLISTIC #041).
	col = mix(col, deep_color.rgb, depth_used * aerial_haze * 0.28);
	float horiz_depth = clamp((tank_half_depth - world_pos.z) / max(tank_half_depth * 2.0, 0.1), 0.0, 1.0);
	col = mix(col, deep_color.rgb, horiz_depth * aerial_haze * 0.48);
	// Depth-scaled contrast — distant subjects lose punch (#37). Weight the
	// back wall harder than vertical depth so mid-water fish near the glass
	// keep chroma.
	float through_water = clamp(depth_used * 0.35 + horiz_depth * 0.65, 0.0, 1.0);
	float col_luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(col_luma), col, 1.0 - through_water * 0.38);
	// In-scatter (alive pass). Everything above fogs toward deep_color, which
	// is why haze read as grey-blue murk. Real haze is lit matter: toward the
	// lamp it glows in the lamp's colour (a lavender/pink band under a pink
	// LED), and around a lamp behind the plants it glows in that lamp's.
	{
		vec3 lamp_s = lamp_rgb(light_color);
		float up = clamp(1.0 - depth_used, 0.0, 1.0);
		float beam_on = step(0.001, iaq_beam_cone.w);
		float scat = (0.08 + aerial_haze * 0.26 + turbidity_haze * 0.36)
			* up * up * (0.55 + beam_on * 0.35) * (0.45 + horiz_depth * 0.55);
		col = mix(col, col * 0.55 + lamp_s * mix(shallow_color.rgb, vec3(0.95), 0.55),
			clamp(scat, 0.0, 0.26));
		if (iaq_backlight.w > 0.001) {
			vec3 bd = world_pos - iaq_backlight.xyz;
			float att = clamp(iaq_backlight.w / (1.0 + iaq_backlight_tint.a * dot(bd, bd)), 0.0, 1.0);
			col += iaq_backlight_tint.rgb * att * (0.06 + aerial_haze * 0.10 + turbidity_haze * 0.10);
		}
	}
	// Turbidity milky read (#40 / REAL_TANK_FIDELITY #39–47).
	if (turbidity_haze > 0.01) {
		col = mix(col, bloom_color, turbidity_haze * (0.22 + depth_used * 0.38));
		// Bacterial bloom scatters forward and washes contrast (milk, not grey fog).
		float milk = turbidity_haze * (0.55 + bacterial_bloom * 0.45);
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(luma) * bloom_color * 1.08, milk * 0.42);
		col = mix(col, col * 0.92 + bloom_color * 0.18, milk * depth_used * 0.35);
	}
	// Depth-dependent contrast falloff (#40) — back glass milkier; near glass
	// keeps punch so fish and leaf edges separate from the water body.
	float contrast_loss = clamp(horiz_depth * 0.72 + depth_used * 0.22, 0.0, 1.0)
		* (0.32 + turbidity_haze * 0.42);
	float cl = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(cl), col, 1.0 - contrast_loss * 0.58);
	// Warm substrate bounce in the lower column (#43).
	col = mix(col, col * vec3(1.08, 1.03, 0.94),
		floor_bounce * (1.0 - depth_used) * depth_used * 0.42);
	// Low-frequency flow warp (#39).
	if (flow_distortion > 0.001) {
		float flow_w = sin(world_pos.x * 0.07 + world_pos.y * 0.04 + TIME * 0.11)
			* cos(world_pos.z * 0.06 - TIME * 0.08);
		col *= 1.0 + flow_w * flow_distortion * 0.04 * (0.35 + depth_used * 0.65);
	}
	// Murky-water scatter glow around bright objects (#19 / #41).
	float murk_glow = bacterial_bloom * 0.42 + bloom_haze * 0.28;
	if (murk_glow > 0.01) {
		float bright = max(max(col.r, col.g), col.b);
		col += light_color * smoothstep(0.32, 0.88, bright) * murk_glow * 0.32;
	}

	// Organic caustics web instead of sine interference.
	vec2 cuv = world_pos.xz * 1.15;
	float t = TIME * 0.78 + day_phase_offset * 6.28318;
	float cw1 = 0.0;
	float cw2 = 0.0;
	float cw3 = 0.0;
	if (aquatic_detail < 3) {
		if (caustic_baked > 0.5) {
			// The baked web already crosses two layers; one sample is the
			// whole cw1/cw2/cw3 stack, so the tiers collapse to on/off.
			cw1 = water_web(cuv * 0.7, t * 0.6);
		} else {
			cw1 = worley_caustic(cuv * 0.7, t * 0.6);
			if (aquatic_detail < 2) {
				cw2 = worley_caustic(cuv * 1.4 + vec2(9.0, 4.0), -t * 0.4 + 1.5);
				if (aquatic_detail < 1) {
					cw3 = worley_caustic(cuv * 2.6 + vec2(15.0, 8.0), t * 0.28 + 3.0);
				}
			}
		}
	}
	float caustic_web = cw1 * 0.5;
	if (aquatic_detail < 2) {
		caustic_web += cw1 * cw2 * 0.75;
	}
	if (aquatic_detail < 1) {
		caustic_web += cw2 * cw3 * 0.35;
	}
	float caustics = smoothstep(0.12, 0.85, caustic_web) * caustic_intensity;
	caustics *= 1.0 - depth_used * 0.35;
	// Dampen caustic shimmer at the surface — thin stems flicker less (#28).
	float surf_dist = abs(world_pos.y - water_surface_y);
	caustics *= smoothstep(0.0, 0.22, surf_dist);
	vec3 caustic_absorb = mix(vec3(1.0),
		vec3(1.0 - depth_used * 0.55, 1.0 - depth_used * 0.22, 1.0),
		depth_absorption);
	col += light_color * caustics * 0.24 * caustic_absorb;

	vec3 n = normalize(NORMAL);
	float spec_alpha = 0.0;
	float under_alpha = 0.0;
	// World-space facing. Godot flips NORMAL on back faces of a cull_disabled
	// mesh, so seen from below the cap faces DOWN; the view-space n.y tests
	// below were therefore blind to the underside.
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float cap = smoothstep(0.55, 0.92, abs(nw.y))
		* step(water_surface_y - 0.35, world_pos.y);
	float cam_below = step(CAMERA_POSITION_WORLD.y, water_surface_y - 0.02);
	vec2 rgrad = vec2(0.0);
	if (cap > 0.01 && surface_ripple_slope > 0.001) {
		rgrad = ripple_slope(world_pos.xz, TIME * wave_speed) * surface_ripple_slope;
	}
	vec3 n_rip_w = normalize(vec3(-rgrad.x, 1.0, -rgrad.y));
	vec3 n_rip = normalize((VIEW_MATRIX * vec4(n_rip_w, 0.0)).xyz);
	// Deep corners go genuinely dark (#38).
	float corner_dark = pow(depth_used, 1.35) * (1.0 - abs(n.y) * 0.35);
	col *= 1.0 - corner_dark * 0.28;
	float surface = smoothstep(0.55, 0.92, n.y) * (1.0 - cam_below);
	// Rippled normal on the cap, the mesh normal everywhere else.
	vec3 n_s = normalize(mix(n, n_rip, surface));
	float fresnel = pow(1.0 - abs(dot(n_s, VIEW)), 2.2);
	// Refractive shimmer: looking down through a rippled surface the floor
	// swims in bright and dark bands that follow the slope. A brightness
	// modulation on the cap, keyed to the slope toward the light.
	col *= 1.0 + dot(rgrad, vec2(0.55, 0.84)) * 1.6 * surface;
	col = mix(col, shallow_color.rgb * 1.18, surface * 0.42);
	// Living ceiling: viewed from below, the surface fractures the light into a
	// drifting bright web. Reuses the caustic Worley so it matches the floor.
	if (surface > 0.01) {
		float surf_web = 0.0;
		if (aquatic_detail < 3) {
			surf_web = water_web(world_pos.xz * 0.9 + vec2(3.0, 1.0), TIME * 0.5);
		}
		col += light_color * surf_web * surface * 0.18;
		// Room/sky sheen on the top cap (#24).
		float refl = surface_reflection * pond_health_gloss;
		col = mix(col, room_sky_color,
			surface * fresnel * refl * (0.35 + sunset_warmth * 0.35));
		col = mix(col, shallow_color.rgb * 1.08,
			surface * pond_calm * 0.22 * pond_health_gloss);
		col = mix(col, pond_color_spill,
			surface * pond_color_spill_gain * 0.32 * pond_health_gloss);
	}
	// Underside: total internal reflection (#17), from the camera's real
	// position rather than a view-space guess.
	float under = cap * cam_below;
	if (under > 0.01 && tir_strength > 0.001) {
		vec3 v_w = normalize(CAMERA_POSITION_WORLD - world_pos);
		float cos_t = abs(dot(v_w, n_rip_w));
		// Outside Snell's window (48.6 deg from vertical, cos ~0.66) nothing
		// leaves the water: the surface is a perfect mirror.
		float tir = 1.0 - smoothstep(0.60, 0.70, cos_t);
		float ceil_web = 0.0;
		if (aquatic_detail < 2) {
			ceil_web = water_web(world_pos.xz * 1.05 + vec2(5.0, 2.0), TIME * 0.42);
		}
		vec3 lamp = lamp_rgb(light_color);
		// The sheet: the lit upper water body seen in the mirror, silvered and
		// wearing the lamp's colour (a pink LED makes a pink ceiling). The
		// ripple slope swells it gently instead of striping it.
		vec3 body = mix(shallow_color.rgb, vec3(0.92, 0.92, 0.94), 0.62);
		vec3 sheet = body * mix(vec3(1.0), lamp, 0.72) * under_glow * 1.12;
		sheet *= 1.0 + dot(rgrad, vec2(0.55, 0.84)) * 0.55 + ceil_web * 0.10;
		// A lamp glowing behind the plants lights its own patch of ceiling.
		if (iaq_backlight.w > 0.001) {
			vec3 bd = world_pos - iaq_backlight.xyz;
			float att = iaq_backlight.w / (1.0 + iaq_backlight_tint.a * dot(bd, bd));
			sheet += iaq_backlight_tint.rgb * clamp(att, 0.0, 1.0) * 0.45;
		}
		// Reflected tank: follow the mirrored ray a short way back down and
		// read what the opaque pass drew there. Fish packed under the surface
		// meet their own upside-down copies at the waterline, which is the
		// single strongest "this is a real tank" cue in the reference photos.
		vec3 refl = sheet;
		if (under_reflect > 0.001 && aquatic_detail < 3) {
			vec3 r_w = reflect(-v_w, -n_rip_w);
			vec3 q = world_pos + r_w * under_reach;
			vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(q, 1.0));
			if (clip.w > 0.001) {
				vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
				float inb = smoothstep(0.0, 0.05, suv.x) * smoothstep(1.0, 0.95, suv.x)
					* smoothstep(0.0, 0.05, suv.y) * smoothstep(1.0, 0.95, suv.y);
				vec3 scene = textureLod(under_screen_tex, clamp(suv, vec2(0.002), vec2(0.998)), 0.0).rgb;
				// Seen through the same bright upper water, so the copy keeps
				// its silhouettes but sits inside the sheet's glow.
				vec3 copy_c = scene * mix(vec3(1.0), lamp, 0.35) * 1.25 + sheet * 0.30;
				refl = mix(sheet, copy_c, under_reflect * inb * tir);
			}
		}
		// Film and trapped bubbles, clustered where the surface is still.
		vec2 fc = floater_count > 0 ? floater_cover(world_pos.xz) : vec2(0.0);
		float radial = edge_radius > 0.0 ? length(world_pos.xz) / edge_radius : UV.x;
		float glass_band = smoothstep(0.80, 0.985, radial);
		float still = clamp(fc.y + glass_band * 0.85 + fc.x * 0.5, 0.0, 1.0);
		if (surface_film > 0.001) {
			// Film: slow low-frequency scum, warmer and duller where it is thick.
			float film_n = water_web(world_pos.xz * 0.35 + vec2(TIME * 0.01, 7.0), 0.0);
			float film = surface_film * clamp(0.05 + still * 0.95, 0.0, 1.0) * film_n;
			refl = mix(refl, refl * vec3(0.95, 0.92, 0.87) + vec3(0.035, 0.028, 0.02), film * 0.5);
			// Bubbles: whole-pixel-sized cells so each one lands as a speck.
			vec2 cell = floor(world_pos.xz * 15.0);
			vec2 hb = caustic_hash(cell + vec2(17.0, 3.0));
			float density = surface_film * (0.04 + still * 0.42);
			float bubble = step(1.0 - density, hb.x);
			refl = mix(refl, mix(vec3(1.0, 0.99, 0.97), lamp, 0.18) * 1.12, bubble * (0.55 + hb.y * 0.45));
		}
		// Inside Snell's window: the lamp itself, luminous but not a white sheet.
		// HOLISTIC #047 — keep surface light while revealing leaf gaps/overlap.
		vec3 window_c = mix(room_sky_color, lamp, 0.50) * 1.16;
		vec3 under_col = mix(window_c, refl, tir);
		// A floater's canopy sits just ABOVE the cap, so from below the cap
		// is the nearer surface and an opaque mirror would paint over every
		// leaf. Let the canopy through; the ring around it stays mirror.
		float k = under * tir_strength * mix(0.70, 0.90, tir) * (1.0 - fc.x * 0.88);
		col = mix(col, under_col, k);
		col += light_color * ceil_web * under * underside_mirror * 0.09;
		under_alpha = k;
	}

	float meniscus = surface * (0.65 + 0.35 * sin(world_pos.x * 2.4 + world_pos.z * 2.1 + TIME * 0.35));
	// 1px-class meniscus band — style guide §1; was a soft 0.25wu gradient (#45).
	float near_surface = 1.0 - smoothstep(0.0, 0.07, abs(world_pos.y - water_surface_y));
	float vertical = 1.0 - abs(n.y);

	// Meniscus bright ring — day side brighter than the water below (#46).
	col += vec3(1.0, 1.0, 0.98) * meniscus * max(0.0, n.y - 0.50) * 0.18;
	col = mix(col, col * vec3(1.08, 1.06, 1.02), near_surface * surface * 0.22);
	// Film and trapped bubbles seen from ABOVE (alive pass): the same still-
	// water clustering as the underside - a dull protein sheen and bright
	// bead-sized bubbles in the rings round floaters and along the glass,
	// clean moving water everywhere else.
	if (surface > 0.01 && surface_film > 0.001) {
		vec2 fc_t = floater_count > 0 ? floater_cover(world_pos.xz) : vec2(0.0);
		float radial_t = edge_radius > 0.0 ? length(world_pos.xz) / edge_radius : UV.x;
		float still_t = clamp(fc_t.y + smoothstep(0.80, 0.985, radial_t) * 0.85, 0.0, 1.0);
		float film_t = surface_film * still_t
			* water_web(world_pos.xz * 0.35 + vec2(TIME * 0.01, 7.0), 0.0);
		col = mix(col, col * vec3(0.95, 0.93, 0.86) + vec3(0.05, 0.045, 0.03),
			film_t * 0.40 * surface);
		vec2 hb_t = caustic_hash(floor(world_pos.xz * 15.0) + vec2(17.0, 3.0));
		float bub_t = step(1.0 - surface_film * still_t * 0.30, hb_t.x);
		col = mix(col, vec3(0.93, 0.97, 0.99), bub_t * surface * 0.65);
	}

	// Above/below split — warm lighter air-side, cool submerged (#47).
	float above_line = smoothstep(water_surface_y - 0.05, water_surface_y + 0.02, world_pos.y);
	float below_line = 1.0 - smoothstep(water_surface_y - 0.02, water_surface_y + 0.08, world_pos.y);
	col = mix(col, col * vec3(1.07, 1.03, 0.96), above_line * 0.26);
	col = mix(col, col * vec3(0.93, 0.98, 1.06), below_line * 0.24);

	// Fixture specular glint on the surface cap (#52).
	if (surface > 0.01) {
		float glint_dist = abs(world_pos.x - fixture_glint_center);
		float glint = smoothstep(fixture_glint_width * 0.52, fixture_glint_width * 0.06, glint_dist);
		glint *= 0.55 + 0.45 * sin(world_pos.z * 1.8 + TIME * 0.65);
		col += light_color * glint * surface * (0.22 + caustic_intensity * 0.28);
	}

	// Specular glint where the fixture reflects off the surface. Computed in
	// view space, which is where NORMAL and VIEW already live.
	if (surface_spec_gain > 0.001) {
		vec3 lp_view = (VIEW_MATRIX * vec4(fixture_world_pos, 1.0)).xyz;
		vec3 l_dir = normalize(lp_view - VERTEX);
		vec3 h_dir = normalize(l_dir + normalize(VIEW));
		// Only the up-facing surface, and only where the water is actually
		// lit — a shaded corner of the meniscus must not spark.
		float spec = pow(max(dot(n_s, h_dir), 0.0), surface_spec_power) * surface;
		// Glitter: the rippled lobe is already broken into streaks; harden
		// its brighter half so the sparks land on whole pixels.
		spec = mix(spec, smoothstep(0.30, 0.75, spec), 0.5);
		// Toward white, not toward light_color: light_color is the water's own
		// blue-green transmission tint, and a highlight wearing it can never
		// reach the top of the palette. A specular is the light source seen
		// directly, so it takes the source's colour, not the medium's.
		col += mix(light_color, vec3(1.0, 0.98, 0.94), 0.62) * spec * surface_spec_gain;
		// AND the surface must become opaque where it sparks. This is the step
		// that was missing first time round: the water is blend_mix with alpha
		// capped at 0.62, so however hot `col` gets a translucent fragment can
		// only contribute 62% of it and the highlight never blows out. A real
		// specular hides what is behind it.
		spec_alpha = clamp(spec * surface_spec_gain, 0.0, 1.0);
	}

	// Corner meniscus on polygon tanks only; curved volumes use the top ring.
	float corner_meniscus = near_surface * vertical;
	if (tank_shape_id < 0.5) {
		col += vec3(0.92, 0.98, 1.0) * corner_meniscus * 0.09;
	}
	// Bright rim where water meets vertical glass (#54).
	float glass_rim = (1.0 - smoothstep(0.0, 0.10, abs(world_pos.y - water_surface_y)))
		* step(0.32, abs(n.y));
	col += vec3(0.94, 0.99, 1.0) * glass_rim * 0.16;

	// Not on the underside: a mirror's grazing angle is where it is brightest,
	// and this fresnel wash is what used to grey it back down.
	col = mix(col, shallow_color.rgb * 0.82, fresnel * 0.28 * (1.0 - under));

	col = mix(col, tint_color.rgb, tint_strength);
	// #45 — tannin staining deepens with depth (tea ramp).
	if (tannin_depth_ramp > 0.01 && tint_strength > 0.01) {
		col = mix(col, tint_color.rgb * vec3(0.85, 0.55, 0.28),
			tint_strength * tannin_depth_ramp * depth_used * 0.85);
	}
	// #52 — water's own green-gold colour (valli jungle backlight).
	if (column_own_color > 0.01) {
		col = mix(col, column_tint_rgb, column_own_color * (0.25 + depth_used * 0.35)
			* (1.0 - under * 0.6));
	}
	// #46 — surface-to-substrate light attenuation darkens the bed.
	col *= 1.0 - bed_attenuation * depth_used * depth_used * 0.55;
	// #50 — convection shimmer near the heater (vertical refraction read).
	if (heater_shimmer > 0.01) {
		float hd = length(world_pos.xz - heater_world_pos.xz);
		float column = exp(-hd * hd * 1.55) * heater_shimmer;
		float shim = sin(world_pos.y * 11.0 - TIME * 2.8 + world_pos.x * 2.0) * 0.5 + 0.5;
		float shim2 = sin(world_pos.y * 17.0 + TIME * 3.6) * 0.5 + 0.5;
		float mix_s = mix(shim, shim2, 0.35);
		col *= 1.0 + column * mix_s * 0.12;
		col += light_color * column * mix_s * 0.10;
		// Slight warm shift in the rising plume (#50).
		col = mix(col, col * vec3(1.08, 1.02, 0.94), column * mix_s * 0.35);
	}
	// #51 — thermal layering seam.
	if (thermal_seam > 0.01) {
		float seam = 1.0 - smoothstep(0.0, 0.22, abs(world_pos.y - thermal_seam_y));
		col = mix(col, col * vec3(1.04, 1.02, 0.96), seam * thermal_seam * 0.45);
		col += vec3(0.9, 0.95, 1.0) * seam * thermal_seam * 0.06;
	}
	// #44/#170 — soft glow around the bubble column.
	if (bubble_column_glow > 0.01) {
		float bd = length(world_pos.xz - bubble_column_pos.xz);
		float halo = exp(-bd * bd * 2.2) * bubble_column_glow;
		col += light_color * halo * (0.18 + turbidity_haze * 0.25);
	}
	// #62 — protein film sheen on open surface.
	if (protein_film > 0.01 && surface > 0.2) {
		float film = protein_film * surface * (0.4 + 0.6 * fresnel);
		float iri = 0.5 + 0.5 * sin(world_pos.x * 3.0 + world_pos.z * 2.2 + TIME * 0.2);
		col = mix(col, col * vec3(1.05, 1.02, 0.95) + vec3(0.08, 0.06, 0.04) * iri,
			film * 0.35);
	}
	// #173 — turbidity cone from fixture to substrate.
	if (turbidity_cone > 0.01 && turbidity_haze > 0.05) {
		vec3 to_fix = normalize(fixture_world_pos - world_pos);
		float along = max(dot(to_fix, vec3(0.0, 1.0, 0.0)), 0.0);
		float cone = along * turbidity_haze * turbidity_cone;
		col += light_color * cone * 0.12;
		col = mix(col, bloom_color, cone * 0.18);
	}
	col = mix(col, col * vec3(1.08, 0.92, 0.82), sunset_warmth * 0.35);
	col = mix(col, col * vec3(0.72, 0.82, 1.05), moonlight * 0.28);
	// Bacterial bloom haze — push the whole column toward bloom_color
	// (warm-white). Adds opacity too so the haze visibly obscures the
	// far side of the tank during heavy blooms.
	col = mix(col, bloom_color, bacterial_bloom * 0.55);

	// Ice lens — frosted rim at waterline in cold presets.
	float ice_rim = near_surface * (0.4 + vertical * 0.6) * ice_lens;
	col = mix(col, vec3(0.88, 0.94, 1.0), ice_rim * 0.45);

	float alpha = mix(shallow_color.a, deep_color.a, depth_norm);
	alpha += bloom_haze * 0.16;
	alpha += surface * 0.05;
	alpha += fresnel * 0.05;
	alpha += caustics * 0.04;
	alpha += ice_rim * 0.06;
	alpha += bacterial_bloom * 0.18;

	ALBEDO = col;
	// The specular is allowed past the translucency cap; nothing else is.
	ALPHA = max(max(clamp(alpha, 0.04, 0.62), spec_alpha * 0.96), under_alpha);
}
