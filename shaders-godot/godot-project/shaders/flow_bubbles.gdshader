// Air bubbles in the water current (REAL_TANK top-10 #4).
//
// A bubble rises at its own terminal speed (bigger is faster) and is carried
// by the water as it goes, so a column leans with the circulation, fans out
// where the plume meets the surface, and wobbles: millimetre bubbles do not
// rise straight, they zig-zag and spiral (path instability). It pops at the
// surface instead of hanging there.
shader_type particles;

#include "res://shaders/flow_field.gdshaderinc"

uniform vec3 emission_center = vec3(0.0, 1.8, 0.0);
uniform vec3 emission_extents = vec3(0.2, 0.02, 0.2);
uniform float surface_y = 6.5;
// Terminal rise speed (units/s) for a scale-1.0 bubble.
uniform float rise_speed = 1.1;
uniform float scale_min = 0.55;
uniform float scale_max = 1.25;
// Zig-zag amplitude (units/s) and rate (Hz).
uniform float wobble = 0.22;
uniform float wobble_rate = 2.4;

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
	uint seed = NUMBER * 7919u + RANDOM_SEED;
	vec3 r = vec3(hash(seed), hash(seed * 31u + 7u), hash(seed * 131u + 3u)) * 2.0 - 1.0;
	float s = mix(scale_min, scale_max, hash(seed * 977u + 11u));
	if (RESTART_POSITION) {
		TRANSFORM = mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0),
			vec4(0.0, 0.0, s, 0.0), vec4(emission_center + r * emission_extents, 1.0));
	}
	if (RESTART_VELOCITY) {
		VELOCITY = vec3(0.0, rise_speed * sqrt(s), 0.0);
	}
	CUSTOM.x = hash(seed * 4099u + 5u) * 6.2831853;  // wobble phase
	CUSTOM.y = s;
}

void process() {
	vec3 p = TRANSFORM[3].xyz;
	float s = max(CUSTOM.y, 0.1);
	float ph = CUSTOM.x + TIME * wobble_rate * 6.2831853 / sqrt(s);
	vec3 zig = vec3(sin(ph), 0.0, cos(ph * 0.8)) * wobble;
	vec3 want = iaq_flow_at(p) + iaq_flow_detail(p, TIME) * 0.5
		+ vec3(0.0, rise_speed * sqrt(s), 0.0) + zig;
	// Bubbles have almost no mass: they take the local water velocity within
	// a fraction of a second.
	VELOCITY = mix(VELOCITY, want, clamp(DELTA * 8.0, 0.0, 1.0));
	if (p.y + VELOCITY.y * DELTA >= surface_y) {
		ACTIVE = false;  // popped; respawns at the stone on its next cycle
	}
}
