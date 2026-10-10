// A faint, broad reflection over pigment. Derivative filtering softens a
// catch that spans less than a render pixel without blurring body markings.
const float FAUNA_CATCH_OPACITY = 0.22;

float fauna_scale_catch(float cosine) {
	float footprint = clamp(abs(fwidth(cosine)) * 1.5, 0.0, 0.15);
	return smoothstep(0.35 - footprint, 1.0 + footprint, clamp(cosine, 0.0, 1.0));
}
