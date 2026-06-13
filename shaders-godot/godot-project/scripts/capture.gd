# One-shot capture: wait for the SubViewport's first useful frame, save the
# palette-quantized output to disk, and quit. Run via:
#   Godot --path . --headless dev/capture.tscn
# Output: res://capture_out.png (which lives next to project.godot).

extends Node

@onready var sub_viewport: SubViewport = $SubViewport
@onready var display: TextureRect = $Display

var _frame := 0

func _ready() -> void:
    display.texture = sub_viewport.get_texture()
    var cam: Camera3D = $SubViewport/World/Camera3D
    cam.look_at(Vector3(0, 3.0, 0), Vector3.UP)
    cam.make_current()
    print_verbose("[capture] camera current=", cam.current, " viewport size=", sub_viewport.size)


func _process(_dt: float) -> void:
    _frame += 1
    # Wait a few frames so the 3D world script has built everything and the
    # bubbler particles have spawned at least one full lifecycle.
    if _frame == 240:
        var sub_img: Image = sub_viewport.get_texture().get_image()
        # Sample a few pixels to verify the SubViewport contains actual 3D content.
        var cx: int = int(sub_img.get_width() / 2.0)
        var cy: int = int(sub_img.get_height() / 2.0)
        var center: Color = sub_img.get_pixel(cx, cy)
        var bottom: Color = sub_img.get_pixel(cx, int(sub_img.get_height() * 0.85))
        print_verbose("[capture] subviewport size=", sub_img.get_size(),
              " center=", center, " bottom=", bottom)
        sub_img.save_png("res://capture_raw.png")

        # And a quantized version (the actual game look). To get the post
        # shader, render the Display TextureRect via a SceneTreeTimer dance:
        # easier: render the parent viewport (the game window) which already
        # has the shader applied.
        var root_img: Image = get_viewport().get_texture().get_image()
        root_img.save_png("res://capture_quantized.png")
        print_verbose("captured: capture_raw.png, capture_quantized.png")
        get_tree().quit()
