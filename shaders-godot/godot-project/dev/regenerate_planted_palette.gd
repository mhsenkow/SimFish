# Run through scripts/dev_run.sh. Uses the same definitions as main.gd.
extends SceneTree
const Art = preload("res://scripts/aesthetics_runtime.gd")

func _initialize() -> void:
	var day := Image.create(48, 1, false, Image.FORMAT_RGBA8)
	var night := Image.create(48, 1, false, Image.FORMAT_RGBA8)
	for i in 48:
		var color := Color("#" + Art.PLANTED_PALETTE[i])
		day.set_pixel(i, 0, color)
		night.set_pixel(i, 0, Art.night_palette_color(color))
	var day_error: Error = day.save_png("res://palettes/planted_48.png")
	var night_error: Error = night.save_png("res://palettes/planted_48_night.png")
	if day_error != OK or night_error != OK:
		push_error("Palette write failed: day=%d night=%d" % [day_error, night_error])
		quit(1)
		return
	print("[palette] wrote 48 matching day/night slots")
	quit()
