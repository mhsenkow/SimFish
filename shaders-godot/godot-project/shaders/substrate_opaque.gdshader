shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 1=gravel 2=aquasoil 3=sand 4=eco 5=peat — matches TerrainVoxelGrid.CellMaterial
uniform int material_id = 0;
// Region-density variation. Real substrate beds aren't uniformly
// speckled — fine vs coarse grain patches break up the tile pattern.
// Same uniform as substrate_caustic.gdshader.
uniform float grain_variation : hint_range(0.0, 1.0) = 0.45;
// Hardscape contact-shadow AO. Up to 8 hardscape feet (driftwood roots,
// rock bases) — xyz = footprint center, w = radius. The substrate
// darkens within the radius to fake an ambient occlusion / contact
// shadow patch. Unused slots use w == 0.
uniform vec4 contact_ao_points[8];
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

#include "res://shaders/palette_tint.gdshaderinc"

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 apply_material_grain(vec3 col, vec3 n, int mat_id, vec3 world_pos, float variation) {
	vec2 xz = world_pos.xz * 3.5;
	float region_hash = hash21(floor(world_pos.xz * 0.4));
	float density_mod = mix(1.0, region_hash * 1.4 + 0.3, variation);
	if (mat_id == 3) {
		// Sand — fine pale speckle
		float speck = step(0.78, hash21(floor(xz * 6.0)));
		col = mix(col, col * 1.18, speck * 0.35 * density_mod);
	} else if (mat_id == 1) {
		// Gravel — chunky cool chips, with coarser grade in some regions
		float chip = step(0.62, hash21(floor(xz * 2.5)));
		float coarse = step(0.55, hash21(floor(xz * 1.1) + 9.7));
		float coarse_chip = step(0.74, hash21(floor(xz * 1.1) + 3.4)) * coarse;
		col = mix(col, col * 0.82 + vec3(0.08, 0.09, 0.12), chip * 0.45 * density_mod);
		col = mix(col, col * 0.72 + vec3(0.12, 0.13, 0.16), coarse_chip * 0.35 * density_mod);
	} else if (mat_id == 2) {
		// Aquasoil — warm organic flecks
		float fleck = step(0.7, hash21(floor(xz * 4.0) + 0.31));
		col = mix(col, col * 0.88 + vec3(0.06, 0.03, 0.0), fleck * 0.3 * density_mod);
	} else if (mat_id == 5) {
		// Peat / carbon — glossy dark streaks
		float streak = smoothstep(0.45, 0.85, sin(xz.x * 2.1 + xz.y * 1.7) * 0.5 + 0.5);
		col = mix(col, col * 0.75 + vec3(0.04, 0.02, 0.0), streak * 0.25);
	} else if (mat_id == 4) {
		// Eco-complete — volcanic sparkle
		float spark = step(0.88, hash21(floor(xz * 5.0) + 1.7));
		col = mix(col, col + vec3(0.12, 0.08, 0.14), spark * 0.4 * density_mod);
	}
	return col;
}

// Soft AO around each registered hardscape contact point. Returns a
// shading multiplier in [contact_shadow_floor..1.0] where 1.0 means
// no darkening. Falloff is exp(-d²) so the shadow concentrates right
// under the contact and fades over ~the radius.
float compute_contact_ao(vec3 world_pos) {
	float ao = 1.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = contact_ao_points[i];
		if (p.w < 0.001) {
			continue;
		}
		vec2 d = vec2(world_pos.x - p.x, world_pos.z - p.z);
		float dist2 = dot(d, d);
		// Normalize by the registered radius so larger contact patches
		// fade slower than tiny ones.
		float n_d2 = dist2 / max(p.w * p.w, 0.001);
		ao = min(ao, mix(0.60, 1.0, clamp(n_d2, 0.0, 1.0)));
	}
	return ao;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f;
	if (n.y > 0.7) {
		f = 1.00;
	} else if (n.y < -0.7) {
		f = 0.50;
	} else if (abs(n.x) > 0.7) {
		f = 0.82;
	} else {
		f = 0.68;
	}
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 col = albedo.rgb * f;
	col = apply_global_palette_tint(col, palette_hue_shift, palette_saturation,
		palette_warmth, palette_value);
	col = apply_material_grain(col, n, material_id, world_pos, grain_variation);
	// Hardscape contact shadow / AO — only meaningful on the top face
	// (where the hardscape footprint touches the substrate). Side / bottom
	// voxels are already dark from the directional shading above.
	if (n.y > 0.7) {
		col *= compute_contact_ao(world_pos);
	}
	// Angle-of-repose slope edges — 50% Bayer dither on vertical faces so
	// sculpted hills read as pixel-art terracing, not smooth ramps.
	if (abs(n.y) < 0.72) {
		vec2 bcell = floor(world_pos.xz * 10.0);
		float bayer = fract(sin(dot(bcell, vec2(12.9898, 78.233))) * 43758.5453);
		col = mix(col * 0.86, col * 1.07, step(0.5, bayer));
	}
	ALBEDO = col;
}
