// MultiMesh voxel shader — faceted cube shading with per-instance color.
//
// Identical look to voxel.gdshader, but the color comes from the MultiMesh's
// per-instance color buffer (COLOR) instead of an `albedo` uniform, so a single
// MultiMeshInstance3D can draw thousands of differently-colored voxels in one
// draw call. Used for plant roots / runners and any non-swaying voxel batch.

shader_type spatial;
render_mode unshaded, cull_back;

varying vec3 v_inst_color;

void vertex() {
	// MultiMesh per-instance color arrives multiplied into COLOR.
	v_inst_color = COLOR.rgb;
}

void fragment() {
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
	ALBEDO = v_inst_color * f;
}
