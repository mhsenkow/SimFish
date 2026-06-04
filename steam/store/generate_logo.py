#!/usr/bin/env python3
"""Generate walstad loom logo mark and wordmark (pixel-art style)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
OUT = REPO / "marketing" / "logo"
GODOT_ICON = REPO / "shaders-godot" / "godot-project" / "icon.png"

# Game palette
BG = (22, 48, 64)
WATER_DEEP = (11, 26, 34)
WATER = (52, 99, 117)
WATER_LIGHT = (105, 161, 179)
FRAME = (196, 196, 214)
FRAME_DARK = (112, 112, 128)
SUBSTRATE = (120, 85, 56)
SAND = (205, 176, 136)
PLANT = (87, 162, 83)
PLANT_MID = (62, 122, 64)
PLANT_DARK = (44, 90, 48)
FISH = (195, 59, 59)
FISH_TAIL = (230, 201, 42)
MENISCUS = (224, 238, 242)
WOOD = (149, 113, 78)
WOOD_LIGHT = (177, 143, 110)
SLATE = (38, 52, 64)
SLATE_LIGHT = (52, 68, 82)
TEXT = (230, 245, 255)
TEXT_SHADOW = (18, 28, 36)

NATIVE = 64


def px(img: Image.Image, x: int, y: int, color: tuple[int, int, int]) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
    draw = ImageDraw.Draw(img)
    draw.rectangle((x0, y0, x1, y1), fill=color)


def line_pixels(img: Image.Image, points: list[tuple[int, int]], color: tuple[int, int, int], thick: int = 1) -> None:
    draw = ImageDraw.Draw(img)
    if len(points) < 2:
        return
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=color, width=thick)


def build_icon_mark() -> Image.Image:
    img = Image.new("RGB", (NATIVE, NATIVE), BG)

    # Tank glass frame
    rect(img, 8, 10, 55, 55, FRAME_DARK)
    rect(img, 10, 12, 53, 53, FRAME)
    rect(img, 12, 14, 51, 51, WATER_DEEP)

    # Water gradient bands
    for y in range(14, 44):
        t = (y - 14) / 30
        c = tuple(int(WATER_DEEP[i] + (WATER_LIGHT[i] - WATER_DEEP[i]) * (1 - t * 0.65)) for i in range(3))
        rect(img, 13, y, 50, y, c)

    # Meniscus
    rect(img, 13, 14, 50, 14, MENISCUS)

    # Substrate
    rect(img, 13, 44, 50, 50, SUBSTRATE)
    rect(img, 13, 50, 50, 50, SAND)

    # Loom weave: two stems crossing
    left_stem = [(18, 49), (20, 40), (24, 28), (28, 20), (31, 18)]
    right_stem = [(45, 49), (43, 38), (39, 26), (35, 19), (32, 17)]
    line_pixels(img, left_stem, PLANT_DARK, thick=2)
    line_pixels(img, right_stem, PLANT_MID, thick=2)
    line_pixels(img, left_stem, PLANT, thick=1)
    line_pixels(img, right_stem, PLANT, thick=1)

    # Small leaves at stem tips
    for x, y in [(28, 19), (35, 18), (31, 17)]:
        rect(img, x - 1, y - 2, x + 1, y, PLANT)
        rect(img, x, y - 1, x + 2, y + 1, PLANT_MID)

    # Fish
    rect(img, 36, 30, 40, 31, FISH)
    rect(img, 41, 30, 42, 31, FISH_TAIL)
    px(img, 37, 30, TEXT)

    # Cabinet base
    rect(img, 6, 56, 57, 58, FRAME_DARK)
    rect(img, 7, 57, 56, 57, FRAME)

    return img


def upscale_nearest(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.Resampling.NEAREST)


def pick_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Avenir Next Heavy.ttf",
        "/System/Library/Fonts/Supplemental/Avenir Next Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()


def draw_notched_frame(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: tuple[int, int, int], notch: int) -> None:
    x0, y0, x1, y1 = box
    draw.rectangle(box, outline=color, width=notch)
    for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
        draw.rectangle((x - notch, y - notch, x + notch, y + notch), fill=color)


def build_wordmark(size: tuple[int, int] = (1280, 720)) -> Image.Image:
    w, h = size
    img = Image.new("RGB", (w, h), BG)

    # Soft water gradient backdrop
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        c = tuple(int(BG[i] + (WATER_DEEP[i] - BG[i]) * t * 0.5) for i in range(3))
        draw.line([(0, y), (w, y)], fill=c)

    panel_w, panel_h = int(w * 0.72), int(h * 0.62)
    px0 = (w - panel_w) // 2
    py0 = (h - panel_h) // 2
    px1 = px0 + panel_w
    py1 = py0 + panel_h

    draw.rectangle((px0 - 10, py0 - 10, px1 + 10, py1 + 10), fill=WOOD)
    draw.rectangle((px0 - 4, py0 - 4, px1 + 4, py1 + 4), fill=WOOD_LIGHT)
    draw.rectangle((px0, py0, px1, py1), fill=SLATE)
    draw.rectangle((px0 + 6, py0 + 6, px1 - 6, py1 - 6), fill=SLATE_LIGHT)

    title_font = pick_font(int(h * 0.17))
    subtitle_font = pick_font(int(h * 0.14))

    title = "WALSTAD"
    subtitle = "LOOM"

    tb = draw.textbbox((0, 0), title, font=title_font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    sb = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    sw, sh = sb[2] - sb[0], sb[3] - sb[1]

    gap = int(h * 0.03)
    total_h = th + gap + sh
    y = py0 + (panel_h - total_h) // 2
    x_title = px0 + (panel_w - tw) // 2
    x_sub = px0 + (panel_w - sw) // 2

    draw.text((x_title + 3, y + 3), title, font=title_font, fill=TEXT_SHADOW)
    draw.text((x_title, y), title, font=title_font, fill=TEXT)
    draw.text((x_sub + 3, y + th + gap + 3), subtitle, font=subtitle_font, fill=TEXT_SHADOW)
    draw.text((x_sub, y + th + gap), subtitle, font=subtitle_font, fill=TEXT)

    # Musical notes flanking LOOM
    note_r = int(h * 0.025)
    note_y = y + th + gap + sh // 2
    for nx in (x_sub - note_r * 5, x_sub + sw + note_r * 3):
        draw.ellipse((nx - note_r, note_y - note_r, nx + note_r, note_y + note_r), fill=WOOD_LIGHT)
        draw.rectangle((nx + note_r - 2, note_y - note_r * 4, nx + note_r + 3, note_y), fill=WOOD_LIGHT)

    return img


def build_horizontal_lockup(size: tuple[int, int] = (1232, 706)) -> Image.Image:
    """Icon + wordmark side by side for wide banners."""
    w, h = size
    img = Image.new("RGB", (w, h), BG)
    mark = upscale_nearest(build_icon_mark(), int(h * 0.55))
    word = build_wordmark((int(w * 0.62), int(h * 0.72)))
    word = word.resize((int(w * 0.62), int(h * 0.72)), Image.Resampling.LANCZOS)
    img.paste(mark, (int(w * 0.06), (h - mark.height) // 2))
    img.paste(word, (int(w * 0.32), (h - word.height) // 2))
    return img


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"  {path.relative_to(REPO)}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    mark = build_icon_mark()

    print("Logo mark (app icon):")
    for size in (32, 128, 256, 512, 1024):
        save_png(upscale_nearest(mark, size), OUT / f"icon_{size}.png")

    print("Wordmark:")
    save_png(build_wordmark(), OUT / "wordmark_1280x720.png")
    save_png(build_wordmark((640, 360)), OUT / "wordmark_640x360.png")

    print("Lockup:")
    save_png(build_horizontal_lockup(), OUT / "lockup_1232x706.png")

    # Godot project icon
    save_png(upscale_nearest(mark, 512), GODOT_ICON)

    print(f"\nDone → {OUT}")


if __name__ == "__main__":
    main()
