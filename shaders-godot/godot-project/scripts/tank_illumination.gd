extends RefCounted

# Relative useful light for the ecosystem, not lux or measured PAR. Godot's
# artistic lamp energies and RGB tints cannot identify photon flux or spectrum.
# One means a healthy default lamp / bright default noon. We take the dominant
# source rather than adding two independently calibrated artistic exposures;
# otherwise the default tank would produce twice its tuned photosynthesis.
# Local water absorption and canopy/floater shade are applied by Plant.
const REFERENCE_INTENSITY: float = 0.5
const MAX_IRRADIANCE: float = 1.5


static func normalized_irradiance(daylight: float, global_intensity: float,
		room_darkness: float, fixture_output_ratio: float,
		master_enabled: bool = true) -> float:
	if not master_enabled:
		return 0.0
	var solar: float = _finite_nonnegative(daylight) \
		* _finite_nonnegative(global_intensity) / REFERENCE_INTENSITY \
		* (1.0 - clampf(_finite_nonnegative(room_darkness), 0.0, 1.0))
	return clampf(maxf(solar, _finite_nonnegative(fixture_output_ratio)),
		0.0, MAX_IRRADIANCE)


static func _finite_nonnegative(value: float) -> float:
	return maxf(0.0, value) if is_finite(value) else 0.0
