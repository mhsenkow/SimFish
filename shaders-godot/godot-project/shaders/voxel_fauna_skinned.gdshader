// Species-batch fauna shader with a GPU bone palette (CROWDED_FISH item 3:
// "move bone transforms into a GPU palette"). Instances are STATIC in
// bone-local space; fauna_species_batch.gd writes one 3x4 matrix per moving
// bone per frame into fauna_bone_tex (3 texels per slot, one row per slot)
// and the vertex stage composes it here. That replaces one CPU transform
// write per VOXEL per frame with one texture row per BONE per frame while
// keeping the one-draw-call-per-species batching and the exact look of
// voxel_fauna_mm.gdshader (shared body in fauna_mm_common.gdshaderinc).
//
// The bone slot rides floor(INSTANCE_CUSTOM.g); slot 0 is pinned to identity
// so untracked static geometry registered without a bone renders unmoved.

shader_type spatial;
render_mode unshaded, cull_back, skip_vertex_transform;

#include "res://shaders/fauna_mm_common.gdshaderinc"

uniform sampler2D fauna_bone_tex : filter_nearest, repeat_disable;

// Rows as written by fauna_species_batch.gd SkinPalette.write():
//   texel(0, slot) = (m00, m01, m02, tx)
//   texel(1, slot) = (m10, m11, m12, ty)
//   texel(2, slot) = (m20, m21, m22, tz)
mat4 fauna_bone_matrix(int slot) {
	vec4 r0 = texelFetch(fauna_bone_tex, ivec2(0, slot), 0);
	vec4 r1 = texelFetch(fauna_bone_tex, ivec2(1, slot), 0);
	vec4 r2 = texelFetch(fauna_bone_tex, ivec2(2, slot), 0);
	return mat4(
		vec4(r0.x, r1.x, r2.x, 0.0),
		vec4(r0.y, r1.y, r2.y, 0.0),
		vec4(r0.z, r1.z, r2.z, 0.0),
		vec4(r0.w, r1.w, r2.w, 1.0));
}

void vertex() {
	v_inst_color = COLOR.rgb;
	v_tissue_density = COLOR.a;
	v_inst_custom = vec4(INSTANCE_CUSTOM.r, fract(INSTANCE_CUSTOM.g),
		INSTANCE_CUSTOM.b, fract(INSTANCE_CUSTOM.a));
	v_bend = fract(INSTANCE_CUSTOM.r);
	v_biolum = floor(INSTANCE_CUSTOM.r) / 32.0;
	float quiet_q = floor(INSTANCE_CUSTOM.a);
	// MODEL_MATRIX = batch root global * static bone-local voxel transform;
	// the palette entry is pivot_global * root_global^-1, so the product is
	// the voxel's live world transform (identical to what the CPU path wrote).
	mat4 bone = fauna_bone_matrix(int(floor(INSTANCE_CUSTOM.g)));
	mat4 wm = bone * MODEL_MATRIX;
	vec3 displaced = fauna_wave_displace(wm, VERTEX, v_bend, quiet_q,
		fauna_wave_phase, TIME);
	vec4 world = wm * vec4(displaced, 1.0);
	v_world_pos = world.xyz;
	// skip_vertex_transform: hand Godot view-space VERTEX/NORMAL ourselves.
	// Normals take the plain basis (no inverse-transpose), matching the
	// engine's default path the per-pivot shader relies on.
	VERTEX = (VIEW_MATRIX * world).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(mat3(wm) * NORMAL, 0.0)).xyz);
}
