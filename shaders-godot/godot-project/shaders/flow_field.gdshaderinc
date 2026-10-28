// The tank's water current as a shader global (REAL_TANK top-10 #4).
//
// One coarse incompressible fluid solve (scripts/water_current.gd, driven by
// scripts/tank_flow_field.gd) is uploaded every step as a 3D texture, so
// plants, motes, bubbles and the surface all move with the SAME water the
// fish swim in - not each with its own sine.
//
//   iaq_flow_tex  : RGB = velocity (world units/s), A = turbulence
//                   (|vorticity|, 1/s). One texel per cell, linear filtered.
//   iaq_flow_box  : xyz = world position of the grid's min corner, w = cell size
//   iaq_flow_dims : xyz = cells per axis, w = 1 when a field is published
//
// Include this once per shader; it is the only place these are declared.

global uniform sampler3D iaq_flow_tex;
global uniform vec4 iaq_flow_box;
global uniform vec4 iaq_flow_dims;

vec3 iaq_flow_uvw(vec3 wpos) {
	vec3 extent = max(iaq_flow_dims.xyz * iaq_flow_box.w, vec3(0.001));
	return clamp((wpos - iaq_flow_box.xyz) / extent, vec3(0.0), vec3(1.0));
}

// Water velocity at a world position, units/s. Zero before a field exists.
vec3 iaq_flow_at(vec3 wpos) {
	if (iaq_flow_dims.w < 0.5) {
		return vec3(0.0);
	}
	return textureLod(iaq_flow_tex, iaq_flow_uvw(wpos), 0.0).rgb;
}

// How churned the water is here, 1/s.
float iaq_flow_turb(vec3 wpos) {
	if (iaq_flow_dims.w < 0.5) {
		return 0.0;
	}
	return textureLod(iaq_flow_tex, iaq_flow_uvw(wpos), 0.0).a;
}

// Sub-grid motion. The grid resolves the circulation, not the centimetre
// eddies that make a leaf shiver or a mote wander. This adds them, scaled by
// how churned the resolved flow is here, so the shiver lives in the plume
// and the outflow and dies in the dead spots. Cheap value-noise curl.
vec3 iaq_flow_hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx) * 2.0 - 1.0;
}

vec3 iaq_flow_detail(vec3 wpos, float time) {
	float turb = iaq_flow_turb(wpos);
	vec3 speed = iaq_flow_at(wpos);
	float amp = clamp(turb * 0.10 + length(speed) * 0.18, 0.0, 0.6);
	if (amp < 0.002) {
		return vec3(0.0);
	}
	vec3 q = wpos * 1.7 - speed * time * 0.6;
	vec3 a = iaq_flow_hash3(floor(q) + floor(time * 1.3));
	vec3 b = iaq_flow_hash3(floor(q) + floor(time * 1.3) + 1.0);
	return mix(a, b, smoothstep(0.0, 1.0, fract(time * 1.3))) * amp;
}

// Flow-map advection (Vlachos 2010): two copies of a pattern, each pushed
// along the local current for one period and then reset, cross-faded so
// neither reset shows. Lets a ripple or caustic texture travel downstream at
// the water's own speed without stretching. Returns (offset time 0,
// offset time 1, blend toward the second).
vec3 iaq_flow_map_phase(float t, float period) {
	float a = fract(t / period);
	float b = fract(t / period + 0.5);
	return vec3(a * period, b * period, abs(a - 0.5) * 2.0);
}
