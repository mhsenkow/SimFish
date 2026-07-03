#[compute]
#version 450

// PERFORMANCE_UNTHROTTLED #57 — parallel conspecific boids accumulation.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly buffer Params {
	float count_f;
	float radius_sq;
	float view_dot;
	float lookahead;
	float pad;
} params;

layout(set = 0, binding = 1, std430) restrict readonly buffer Positions {
	vec4 data[];
} positions;

layout(set = 0, binding = 2, std430) restrict readonly buffer Velocities {
	vec4 data[];
} velocities;

layout(set = 0, binding = 3, std430) restrict readonly buffer Headings {
	vec4 data[];
} headings;

layout(set = 0, binding = 4, std430) restrict readonly buffer Species {
	uint data[];
} species;

layout(set = 0, binding = 5, std430) restrict readonly buffer Meta {
	vec4 data[];
} meta;

layout(set = 0, binding = 6, std430) restrict buffer OutSep {
	vec4 data[];
} out_sep;

layout(set = 0, binding = 7, std430) restrict buffer OutAli {
	vec4 data[];
} out_ali;

layout(set = 0, binding = 8, std430) restrict buffer OutCoh {
	vec4 data[];
} out_coh;

layout(set = 0, binding = 9, std430) restrict buffer OutStats {
	ivec4 data[];
} out_stats;

void main() {
	uint i = gl_GlobalInvocationID.x;
	uint count = uint(params.count_f);
	if (i >= count) {
		return;
	}

	vec3 pos_i = positions.data[i].xyz;
	vec3 head_i = headings.data[i].xyz;
	float sep_r = positions.data[i].w;
	uint sp_i = species.data[i];
	float home_y = meta.data[i].x;

	vec3 sep = vec3(0.0);
	vec3 ali = vec3(0.0);
	vec3 coh = vec3(0.0);
	float speed_sum = 0.0;
	int nc = 0;
	float sep_r2 = sep_r * sep_r;

	for (uint j = 0u; j < count; j++) {
		if (j == i) {
			continue;
		}
		vec3 diff = pos_i - positions.data[j].xyz;
		float d2 = dot(diff, diff);
		if (d2 < 1e-4) {
			continue;
		}
		if (d2 < sep_r2) {
			vec3 push = diff;
			push.y *= 0.45;
			sep += normalize(push) / max(sqrt(d2), 0.1);
		}
		if (species.data[j] != sp_i) {
			continue;
		}
		if (abs(diff.y) > home_y * 2.4) {
			continue;
		}
		vec3 to_n = -diff;
		float dot_v = dot(head_i, normalize(to_n));
		if (dot_v < params.view_dot) {
			continue;
		}
		vec3 predicted = positions.data[j].xyz + velocities.data[j].xyz * params.lookahead;
		ali += headings.data[j].xyz;
		coh += predicted;
		speed_sum += length(velocities.data[j].xyz);
		nc++;
		if (abs(diff.y) < home_y * 0.85) {
			sep.y += sign(-diff.y) * 0.28;
		}
	}

	out_sep.data[i] = vec4(sep, 0.0);
	out_ali.data[i] = vec4(ali, 0.0);
	out_coh.data[i] = vec4(coh, 0.0);
	out_stats.data[i] = ivec4(nc, int(speed_sum * 1000.0), 0, 0);
}
