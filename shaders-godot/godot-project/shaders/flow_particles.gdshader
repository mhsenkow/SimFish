// Particles carried by the water current (REAL_TANK top-10 #4).
//
// Marine snow, cycle haze and anything else suspended in the water: each
// particle relaxes toward the local current plus its own settling speed, so
// it rides the circulation the fish swim in - up the plume, along the
// surface, down the far glass, slowing into the dead spot where it settles.
// That is the single most legible sign that the water is moving.
shader_type particles;

#include "res://shaders/flow_field.gdshaderinc"

// Spawn box (world space; the emitter runs with local_coords off).
uniform vec3 emission_center = vec3(0.0, 3.0, 0.0);
uniform vec3 emission_extents = vec3(6.0, 2.0, 3.0);
// Water volume the particles live in. One that leaves it respawns.
uniform vec3 volume_min = vec3(-8.0, 1.6, -4.0);
uniform vec3 volume_max = vec3(8.0, 6.5, 4.0);
// Settling speed (units/s, positive = sinks). Marine snow sinks slowly; a
// buoyant fleck can be negative.
uniform float settle_speed = 0.035;
// How fast a particle takes on the water's velocity, 1/s. Fine particulate
// is effectively a tracer.
uniform float response = 3.0;
// Random walk, units/s, on top of the sub-grid turbulence.
uniform float wander = 0.012;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

vec3 rand3(uint seed) {
	return vec3(hash(seed), hash(seed * 1973u + 9277u), hash(seed * 26699u + 4111u));
}

void start() {
	if (RESTART_POSITION) {
		vec3 r = rand3(NUMBER + RANDOM_SEED * 7919u) * 2.0 - 1.0;
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = emission_center + r * emission_extents;
	}
	if (RESTART_VELOCITY) {
		VELOCITY = iaq_flow_at(TRANSFORM[3].xyz);
	}
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	vec3 water = iaq_flow_at(p) + iaq_flow_detail(p, TIME + float(INDEX) * 0.37);
	vec3 r = rand3(INDEX * 131u + uint(TIME * 2.0)) * 2.0 - 1.0;
	vec3 want = water + vec3(0.0, -settle_speed, 0.0) + r * wander;
	VELOCITY = mix(VELOCITY, want, clamp(response * DELTA, 0.0, 1.0));
	// Left the water (through the surface, into the bed, past the glass):
	// reappear somewhere else in the column rather than piling up.
	vec3 next = p + VELOCITY * DELTA;
	if (any(lessThan(next, volume_min)) || any(greaterThan(next, volume_max))) {
		vec3 rr = rand3(INDEX * 7u + uint(TIME * 13.0) + 1u) * 2.0 - 1.0;
		TRANSFORM[3].xyz = emission_center + rr * emission_extents;
		VELOCITY = iaq_flow_at(TRANSFORM[3].xyz);
	}
}
