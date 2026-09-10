extends RefCounted
class_name CanopyDensity

const WIDTH: int = 16
const HEIGHT: int = 8
const PLANT_CAP: int = 128

static func build(plants: Array, half_w: float, half_d: float) -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RF)
	var used: int = 0
	for plant_v in plants:
		if used >= PLANT_CAP:
			break
		if not is_instance_valid(plant_v) or not plant_v.has_method("canopy_shadow_sphere"):
			continue
		var crown: Vector4 = plant_v.canopy_shadow_sphere()
		var px: int = clampi(int((crown.x + half_w) / maxf(half_w * 2.0, 0.01)
			* float(WIDTH)), 0, WIDTH - 1)
		var py: int = clampi(int((crown.z + half_d) / maxf(half_d * 2.0, 0.01)
			* float(HEIGHT)), 0, HEIGHT - 1)
		var previous: float = image.get_pixel(px, py).r
		image.set_pixel(px, py, Color(clampf(previous + crown.w * 0.34, 0.0, 1.0), 0, 0))
		used += 1
	return image
