shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 1=gravel 2=aquasoil 3=sand 4=eco 5=peat — matches TerrainVoxelGrid.CellMaterial
uniform int material_id = 0;
// Region-density variation. Real substrate beds aren't uniformly
// speckled — fine vs coarse grain patches break up the tile pattern.
uniform float grain_variation : hint_range(0.0, 1.0) = 0.45;
// Hardscape contact-shadow AO. Up to 8 hardscape feet (driftwood roots,
// rock bases) — xyz = footprint center, w = radius.
uniform vec4 contact_ao_points[8];
uniform float palette_hue_shift : hint_range(-0.5, 0.5) = 0.0;
uniform float palette_saturation : hint_range(0.5, 1.5) = 1.0;
uniform float palette_warmth : hint_range(-1.0, 1.0) = 0.0;
uniform float palette_value : hint_range(0.7, 1.3) = 1.0;

// REAL_TANK_FIDELITY §A — stratified cross-section at the glass.
// World-space bed bounds; side faces sample depth to paint soil under cap.
uniform float bed_bottom_y = 0.0;
uniform float bed_top_y = 1.6;
uniform float cap_fraction : hint_range(0.05, 0.95) = 0.42;
uniform vec4 soil_color : source_color = vec4(0.10, 0.07, 0.05, 1.0);
uniform vec4 cap_color : source_color = vec4(0.55, 0.50, 0.42, 1.0);
uniform float boundary_wave : hint_range(0.0, 0.5) = 0.18;
uniform float mix_band : hint_range(0.0, 0.5) = 0.30;
uniform float anoxic_darken : hint_range(0.0, 1.0) = 0.55;
uniform float grain_population : hint_range(0.0, 1.0) = 0.85;
uniform float root_density : hint_range(0.0, 1.0) = 0.0;
uniform float tunnel_strength : hint_range(0.0, 1.0) = 0.0;
uniform float detritus_amount : hint_range(0.0, 1.0) = 0.25;
uniform float bed_age : hint_range(0.0, 1.0) = 0.35;
uniform float wet_line_y = 99.0;
uniform float glass_contact : hint_range(0.0, 1.0) = 0.7;
uniform float gas_pocket : hint_range(0.0, 1.0) = 0.15;
uniform float slope_hint : hint_range(0.0, 1.0) = 0.0;

#include "res://shaders/palette_tint.gdshaderinc"

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 apply_material_grain(vec3 col, vec3 n, int mat_id, vec3 world_pos, float variation) {
	vec2 xz = world_pos.xz * 3.5;
	float region_hash = hash21(floor(world_pos.xz * 0.4));
	float density_mod = mix(1.0, region_hash * 1.4 + 0.3, variation);
	if (mat_id == 3) {
		float speck = step(0.78, hash21(floor(xz * 6.0)));
		col = mix(col, col * 1.18, speck * 0.35 * density_mod);
	} else if (mat_id == 1) {
		float chip = step(0.62, hash21(floor(xz * 2.5)));
		float coarse = step(0.55, hash21(floor(xz * 1.1) + 9.7));
		float coarse_chip = step(0.74, hash21(floor(xz * 1.1) + 3.4)) * coarse;
		col = mix(col, col * 0.82 + vec3(0.08, 0.09, 0.12), chip * 0.45 * density_mod);
		col = mix(col, col * 0.72 + vec3(0.12, 0.13, 0.16), coarse_chip * 0.35 * density_mod);
	} else if (mat_id == 2) {
		float fleck = step(0.7, hash21(floor(xz * 4.0) + 0.31));
		col = mix(col, col * 0.88 + vec3(0.06, 0.03, 0.0), fleck * 0.3 * density_mod);
	} else if (mat_id == 5) {
		float streak = smoothstep(0.45, 0.85, sin(xz.x * 2.1 + xz.y * 1.7) * 0.5 + 0.5);
		col = mix(col, col * 0.75 + vec3(0.04, 0.02, 0.0), streak * 0.25);
	} else if (mat_id == 4) {
		float spark = step(0.88, hash21(floor(xz * 5.0) + 1.7));
		col = mix(col, col + vec3(0.12, 0.08, 0.14), spark * 0.4 * density_mod);
	}
	return col;
}

float compute_contact_ao(vec3 world_pos) {
	float ao = 1.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = contact_ao_points[i];
		if (p.w < 0.001) {
			continue;
		}
		vec2 d = vec2(world_pos.x - p.x, world_pos.z - p.z);
		float dist2 = dot(d, d);
		float n_d2 = dist2 / max(p.w * p.w, 0.001);
		ao = min(ao, mix(0.60, 1.0, clamp(n_d2, 0.0, 1.0)));
	}
	return ao;
}

// Discrete pebble palette for Tank-A-style gravel (cream/tan/slate/rust/black/quartz).
vec3 grain_palette_sample(float h) {
	if (h < 0.14) {
		return vec3(0.86, 0.80, 0.68);
	} else if (h < 0.30) {
		return vec3(0.72, 0.62, 0.48);
	} else if (h < 0.48) {
		return vec3(0.42, 0.44, 0.48);
	} else if (h < 0.62) {
		return vec3(0.58, 0.38, 0.28);
	} else if (h < 0.78) {
		return vec3(0.18, 0.16, 0.15);
	} else if (h < 0.90) {
		return vec3(0.78, 0.82, 0.86);
	}
	return vec3(0.55, 0.52, 0.46);
}

vec3 stratified_bed_color(vec3 world_pos, vec3 n, vec3 base_col) {
	float bed_h = max(bed_top_y - bed_bottom_y, 0.05);
	// Local surface height hint from slope — banks higher at back/left.
	float local_top = bed_top_y + slope_hint * (
		(world_pos.z * -0.08) + (world_pos.x * -0.04)
		+ (hash21(floor(world_pos.xz * 0.55)) - 0.5) * 0.12);
	float depth_frac = clamp((local_top - world_pos.y) / bed_h, 0.0, 1.0);

	// Wavy soil/cap boundary (±15% of cap thickness via low-freq noise).
	float wave = (hash21(floor(world_pos.xz * 0.85)) - 0.5) * 2.0
		+ sin(world_pos.x * 0.55 + world_pos.z * 0.38) * 0.55
		+ sin(world_pos.x * 1.3 - world_pos.z * 0.9) * 0.25;
	float cap_split = cap_fraction + wave * boundary_wave * cap_fraction;
	cap_split = clamp(cap_split, 0.08, 0.92);

	float mix_w = mix_band * cap_fraction;
	float soil_w = smoothstep(cap_split - mix_w, cap_split + mix_w, depth_frac);

	vec3 soil = soil_color.rgb;
	vec3 cap = mix(cap_color.rgb, base_col, 0.35);

	// Age dulls and olives the cap.
	cap = mix(cap, cap * vec3(0.78, 0.82, 0.68), bed_age * 0.55);
	soil = mix(soil, soil * 0.72, bed_age * 0.25);

	// Anoxic darkening with depth (independent of lighting).
	soil *= mix(1.0, 0.35, anoxic_darken * smoothstep(0.35, 1.0, depth_frac));

	vec3 col = mix(cap, soil, soil_w);

	// Discrete grains on vertical faces near the glass (side walls).
	bool side = abs(n.y) < 0.55;
	if (side && grain_population > 0.01 && soil_w < 0.92) {
		float size_scale = mix(5.5, 2.8, smoothstep(0.0, cap_split, depth_frac));
		vec2 cell = floor(vec2(world_pos.x, world_pos.y) * size_scale
			+ vec2(world_pos.z * 0.3, 0.0));
		float gh = hash21(cell);
		float in_grain = step(0.42, gh) * step(hash21(cell + 17.3),
			mix(0.55, 0.82, grain_population));
		vec3 pebble = grain_palette_sample(hash21(cell + 3.1));
		// Finer grains deeper in the cap.
		float fine = smoothstep(0.0, cap_split * 0.85, depth_frac);
		pebble = mix(pebble * 1.05, mix(pebble, soil, 0.35), fine * 0.4);
		col = mix(col, pebble, in_grain * grain_population * (1.0 - soil_w * 0.7));
		// Wet-dark contact ring at glass.
		float edge = 1.0 - smoothstep(0.0, 0.12, abs(fract(world_pos.x * size_scale) - 0.5)
			+ abs(fract(world_pos.y * size_scale) - 0.5));
		col *= mix(1.0, 0.78, edge * glass_contact * in_grain * 0.55);
	}

	// Root hairs in soil against front glass.
	if (side && root_density > 0.01 && soil_w > 0.25) {
		float root_n = hash21(floor(vec2(world_pos.x * 9.0, world_pos.y * 14.0)));
		float strand = step(0.88 - root_density * 0.25, root_n)
			* step(0.15, fract(world_pos.y * 11.0 + root_n * 4.0));
		vec3 root_col = vec3(0.72, 0.64, 0.48);
		col = mix(col, root_col, strand * root_density * 0.55 * soil_w);
	}

	// MTS tunnels — pale voids in soil.
	if (side && tunnel_strength > 0.01 && soil_w > 0.4) {
		float tcell = hash31(floor(world_pos * 3.2));
		float tunnel = smoothstep(0.82, 0.95, tcell)
			* smoothstep(0.15, 0.0, abs(fract(world_pos.y * 2.4 + tcell) - 0.5));
		col = mix(col, col * 1.35 + vec3(0.08, 0.06, 0.04), tunnel * tunnel_strength * 0.7);
	}

	// Detritus in grain interstices (dark fines).
	if (detritus_amount > 0.01) {
		float det = step(0.91, hash21(floor(world_pos.xz * 8.0 + world_pos.y * 3.0)));
		col = mix(col, col * 0.45, det * detritus_amount * (1.0 - soil_w * 0.3));
	}

	// Gas pockets — rare bright lenses in established soil.
	if (side && gas_pocket > 0.01 && soil_w > 0.55) {
		float gp = step(0.985 - gas_pocket * 0.02, hash31(floor(world_pos * 2.1)));
		col = mix(col, vec3(0.75, 0.78, 0.72), gp * gas_pocket * 0.85);
	}

	// Wet vs dry at waterline — cap above waterline is paler.
	if (world_pos.y > wet_line_y - 0.08) {
		float dry = smoothstep(wet_line_y - 0.08, wet_line_y + 0.12, world_pos.y);
		col = mix(col, col * 1.18 + vec3(0.06, 0.05, 0.03), dry * 0.55 * (1.0 - soil_w));
	}

	return col;
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
	if (n.y > 0.7) {
		vec2 bed_cell = floor(world_pos.xz * 9.0);
		float bed_hash = hash21(bed_cell + floor(world_pos.y * 14.0));
		col *= mix(0.94, 1.06, bed_hash);
	}
	col = apply_category_palette_tint(col, iaq_palette_substrate,
		palette_hue_shift, palette_saturation, palette_warmth, palette_value);
	col = apply_material_grain(col, n, material_id, world_pos, grain_variation);

	// Stratified cross-section — strongest on vertical faces at the glass.
	col = stratified_bed_color(world_pos, n, col);

	if (n.y > 0.7) {
		float depth_z = clamp((world_pos.z + 8.0) / 16.0, 0.0, 1.0);
		float coarse = mix(1.35, 0.75, depth_z);
		vec2 xz_c = world_pos.xz * (3.5 * coarse);
		float speck = step(0.88, hash21(floor(xz_c * 6.0)));
		col = mix(col, col * 1.16, speck * 0.28);
	}
	if (n.y > 0.7) {
		float edge_x = 1.0 - smoothstep(7.0, 8.0, abs(world_pos.x));
		float edge_z = 1.0 - smoothstep(3.2, 4.0, abs(world_pos.z));
		col *= mix(1.0, 0.72, max(edge_x, edge_z) * 0.55);
	}
	if (n.y > 0.7) {
		col *= compute_contact_ao(world_pos);
	}
	if (abs(n.y) < 0.72) {
		vec2 bcell = floor(world_pos.xz * 10.0);
		float bayer = fract(sin(dot(bcell, vec2(12.9898, 78.233))) * 43758.5453);
		col = mix(col * 0.86, col * 1.07, step(0.5, bayer));
	}
	ALBEDO = col;
}
