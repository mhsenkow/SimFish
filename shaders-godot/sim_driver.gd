# walstad loom sim driver - skeleton that writes the texture inputs the shaders read.
#
# Until sim-rust/ is wired in via GDExtension, this script generates fake data
# so you can see the rendering pipeline working end to end. It produces:
#   - density_image : 288x144 R8, mostly full except a thin band near the surface
#   - chemistry_image : 288x144 RGBA8, with slowly drifting tannin / cloudiness
# Both are uploaded each frame to the WaterVolume material.
#
# Attach to: the SubViewport's WaterVolume ColorRect (or a sibling Node).

extends Node

@export var water_volume: ColorRect
@export var sim_width: int = 288
@export var sim_height: int = 144

var _density_img: Image
var _density_tex: ImageTexture
var _chem_img: Image
var _chem_tex: ImageTexture
var _t: float = 0.0

func _ready() -> void:
    _density_img = Image.create(sim_width, sim_height, false, Image.FORMAT_R8)
    _chem_img    = Image.create(sim_width, sim_height, false, Image.FORMAT_RGBA8)
    _density_tex = ImageTexture.create_from_image(_density_img)
    _chem_tex    = ImageTexture.create_from_image(_chem_img)
    if water_volume and water_volume.material is ShaderMaterial:
        var m: ShaderMaterial = water_volume.material
        m.set_shader_parameter("density_tex", _density_tex)
        m.set_shader_parameter("chemistry_tex", _chem_tex)

func _process(delta: float) -> void:
    _t += delta
    _refresh_density()
    _refresh_chemistry()
    if water_volume and water_volume.material is ShaderMaterial:
        (water_volume.material as ShaderMaterial).set_shader_parameter("time_seconds", _t)

func _refresh_density() -> void:
    # full water below surface_y, fading band at the surface.
    # When sim-rust lands this becomes a memcpy from the FFI buffer.
    _density_img.fill(Color(1, 0, 0, 1))   # R=1 (full water) by default
    var surface_row := int(sim_height * 0.15)
    for x in sim_width:
        for y in range(surface_row - 2, surface_row + 1):
            if y < 0 or y >= sim_height: continue
            var t := (float(y - (surface_row - 2)) / 3.0)
            _density_img.set_pixel(x, y, Color(t, 0, 0, 1))
    _density_tex.update(_density_img)

func _refresh_chemistry() -> void:
    # Slow drift in tannins + cloudiness as a placeholder.
    var tannins := 0.15 + sin(_t * 0.05) * 0.05
    var cloudiness := 0.05 + max(0.0, sin(_t * 0.03) * 0.1)
    for y in sim_height:
        for x in sim_width:
            _chem_img.set_pixel(x, y, Color(tannins, 0.0, cloudiness, 1.0))
    _chem_tex.update(_chem_img)
