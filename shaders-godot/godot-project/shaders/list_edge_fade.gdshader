shader_type canvas_item;

// Soft edge strip for scroll lists. Painted as a thin overlay at the top and
// bottom of the Residents roster so rows appear to dissolve into the panel
// background as they scroll off, instead of hard-clipping at the container
// edge. One shader, two strips: the top strip uses flip=0 (opaque at the very
// top → transparent toward the middle), the bottom strip flip=1.
//
// Purely cosmetic and mouse-ignored — a bad uniform can only make the fade look
// wrong, never break the list itself (per the project's shader-safety habit).
uniform vec4 edge_color : source_color = vec4(0.06, 0.07, 0.12, 1.0);
uniform float flip = 0.0;
uniform float softness : hint_range(0.05, 1.0) = 1.0;

void fragment() {
	float y = mix(UV.y, 1.0 - UV.y, clamp(flip, 0.0, 1.0));
	float a = 1.0 - smoothstep(0.0, softness, y);
	COLOR = edge_color;
	COLOR.a *= a;
}
