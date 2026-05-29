// MultiMesh foliage shader — faceted cube shading + GPU vertex sway, with
// per-instance color. This is foliage.gdshader ported to MultiMesh: the slow
// current sway + leaf flutter still run on the GPU at full framerate, but every
// leaf voxel of a plant is now an instance in one MultiMesh (one draw call)
// instead of its own MeshInstance3D node. Color comes from the per-instance
// COLOR buffer so each voxel keeps its own tint.

shader_type spatial;
render_mode unshaded, cull_back;

uniform float sway_speed = 1.6;
uniform float sway_amplitude = 0.08;
uniform float flutter_speed = 3.6;
uniform float flutter_amplitude = 0.03;

varying vec3 v_inst_color;

void vertex() {
	v_inst_color = COLOR.rgb;

	// MODEL_MATRIX is per-instance for a MultiMesh, so world_pos varies per
	// voxel and neighbouring voxels sway in phase, just like the old per-leaf
	// foliage nodes did.
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float time_sway = TIME * sway_speed;
	float phase = world_pos.x * 0.4 + world_pos.z * 0.3;
	float sway = sin(time_sway + phase) * sway_amplitude;

	float height_factor = max(0.0, world_pos.y * 0.5);
	VERTEX.x += sway * height_factor;
	VERTEX.z += sway * 0.35 * height_factor;

	float time_flutter = TIME * flutter_speed;
	float phase_flutter = world_pos.x * 1.5 + world_pos.y * 2.0;
	float flutter = sin(time_flutter + phase_flutter) * flutter_amplitude;
	VERTEX.y += flutter * height_factor * 0.3;
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
