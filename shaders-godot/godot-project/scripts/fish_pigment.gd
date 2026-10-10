extends RefCounted

# One pigment wash composed from life stage and emotion. These are changes
# within the animal's hue, rather than separate overlays of grey/white paint.
# state: juvenile softness, senescence, courtship, pallor.
static func compose(original: Color, state: Vector4, flush: float,
		accent: Color, base: Color) -> Color:
	var color: Color = original
	var juvenile: float = clampf(state.x, 0.0, 1.0)
	var aged: float = clampf(state.y, 0.0, 1.0)
	var flare: float = clampf(state.z, 0.0, 0.8)
	var pallor: float = clampf(state.w, 0.0, 0.75)
	# Young/stressed fish retain their markings. Adding a silver grey here
	# erased blue/red bands and promoted the whole fish to the white palette.
	color.s *= (1.0 - juvenile * 0.24) * (1.0 - aged * 0.22) * (1.0 - pallor * 0.28)
	color.v *= (1.0 - juvenile * 0.04) * (1.0 - aged * 0.18) * (1.0 - pallor * 0.06)
	# The display deepens pigment, with a small relative lift. Dark eyes and
	# ink markings stay dark; no additive white term is applied to every voxel.
	color.s = minf(1.0, color.s * (1.0 + flare * 0.18))
	color.v = minf(1.0, color.v * (1.0 + flare * 0.06))
	if flush > 0.001:
		var base_luma: float = base.get_luminance()
		var soft_tissue: bool = original.get_luminance() < base_luma - 0.06 \
			or original.a < 0.98
		# A gill/fin flush must not paint over a blue iridophore stripe.
		var warm_tissue: bool = original.r >= original.b * 0.9
		if warm_tissue:
			var flush_color: Color = accent.lerp(Color8(210, 70, 55), 0.72)
			color = color.lerp(flush_color, clampf(flush, 0.0, 1.0)
				* (0.18 if soft_tissue else 0.06))
	color.a = original.a
	return color
