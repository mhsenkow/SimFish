// Fauna MultiMesh voxel shader — per-instance COLOR.rgb replaces per-color materials.
// Same look as voxel.gdshader fauna path; one shared material per fish batch.
// Shared body (uniforms, INSTANCE_CUSTOM contract, wave, fragment) lives in
// fauna_mm_common.gdshaderinc; voxel_fauna_skinned.gdshader is the species-batch
// variant that composes a GPU bone palette on top of the same body.

shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/fauna_mm_common.gdshaderinc"

void vertex() {
	v_inst_color = COLOR.rgb;
	v_tissue_density = COLOR.a;
	// floor(g) is reserved for the skinned variant's bone slot; per-pivot
	// writers never set it, so fract() is the identity here.
	v_inst_custom = vec4(INSTANCE_CUSTOM.r, fract(INSTANCE_CUSTOM.g),
		INSTANCE_CUSTOM.b, fract(INSTANCE_CUSTOM.a));
	v_bend = fract(INSTANCE_CUSTOM.r);
	v_biolum = floor(INSTANCE_CUSTOM.r) / 32.0;
	float quiet_q = floor(INSTANCE_CUSTOM.a);
	VERTEX = fauna_wave_displace(MODEL_MATRIX, VERTEX, v_bend, quiet_q,
		fauna_wave_phase, TIME);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
