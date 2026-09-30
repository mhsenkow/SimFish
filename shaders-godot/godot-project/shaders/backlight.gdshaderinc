// Rear backlight for opaque tank surfaces: substrate, hardscape, voxels.
//
// Every tank shader is unshaded, so the TankBacklight OmniLight (world.gd)
// lights nothing by itself. world.gd publishes it as two globals instead:
//
//   iaq_backlight      = (x, y, z, energy)       energy 0 = off
//   iaq_backlight_tint = (r, g, b, falloff k)    att = energy / (1 + k d^2)
//
// Same contract as foliage_light.gdshaderinc and water.gdshader. Those two
// declare the globals themselves, so a shader must include AT MOST ONE of
// them: a second declaration of a global uniform fails to compile.
//
// Two terms. A wrapped diffuse wash, so the back of the substrate and the
// lamp-facing sides of stone take the lamp's colour while keeping their own
// hue; and a rim on silhouettes lying between the camera and the lamp, which
// is what a backlit tank photographs as - the edge of every rock glows.
global uniform vec4 iaq_backlight;
global uniform vec4 iaq_backlight_tint;

vec3 iaq_backlight_light(vec3 col, vec3 wpos, vec3 n_ws, vec3 cam_ws) {
	float e = iaq_backlight.w;
	if (e <= 0.001) {
		return col;
	}
	vec3 to_l = iaq_backlight.xyz - wpos;
	float d2 = dot(to_l, to_l);
	vec3 l = to_l * inversesqrt(max(d2, 1e-4));
	float att = e / (1.0 + max(iaq_backlight_tint.a, 0.0) * d2);
	vec3 n = n_ws * inversesqrt(max(dot(n_ws, n_ws), 1e-6));
	vec3 v = normalize(cam_ws - wpos);
	float wrap = clamp((dot(n, l) + 0.3) / 1.3, 0.0, 1.0);
	float rim = pow(1.0 - clamp(abs(dot(n, v)), 0.0, 1.0), 3.0)
		* (0.25 + 0.75 * max(dot(-v, l), 0.0));
	vec3 tint = iaq_backlight_tint.rgb;
	return col + col * tint * (wrap * att * 0.42) + tint * (rim * att * 0.30);
}
