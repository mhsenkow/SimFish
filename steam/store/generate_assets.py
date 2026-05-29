#!/usr/bin/env python3
"""Generate Steam store assets from gameplay screenshot and app icon."""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
SOURCE = REPO / "output" / "godot_mm.png"
ICON_SOURCE = REPO / "steam" / "content" / "macos" / "WalstadLoom.app" / "Contents" / "Resources" / "icon.icns"
OUT = ROOT / "assets"

SCREENSHOT_SIZE = (1920, 1080)
CAPSULES = {
    "small_capsule_462x174": (462, 174),
    "main_capsule_1232x706": (1232, 706),
    "package_header_1414x464": (1414, 464),
    "hero_capsule_748x896": (748, 896),
    "library_capsule_600x900": (600, 900),
    "library_hero_3840x1240": (3840, 1240),
    "library_logo_1280x720": (1280, 720),
    "library_header_920x430": (920, 430),
}


def load_source() -> Image.Image:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source screenshot: {SOURCE}")
    return Image.open(SOURCE).convert("RGB")


def crop_16_9(img: Image.Image, center_x: float, center_y: float, scale: float) -> Image.Image:
    w, h = img.size
    target_ratio = 16 / 9
    crop_h = int(h / scale)
    crop_w = int(crop_h * target_ratio)
    crop_w = min(crop_w, w)
    crop_h = int(crop_w / target_ratio)
    cx = int(w * center_x)
    cy = int(h * center_y)
    left = max(0, min(w - crop_w, cx - crop_w // 2))
    top = max(0, min(h - crop_h, cy - crop_h // 2))
    return img.crop((left, top, left + crop_w, top + crop_h))


def save_screenshots(img: Image.Image) -> list[Path]:
    shots_dir = OUT / "screenshots"
    shots_dir.mkdir(parents=True, exist_ok=True)
    crops = [
        ("01_main", 0.50, 0.48, 1.0),
        ("02_left", 0.34, 0.50, 1.15),
        ("03_right", 0.66, 0.50, 1.15),
        ("04_close", 0.50, 0.42, 1.35),
        ("05_wide", 0.50, 0.55, 0.85),
    ]
    paths: list[Path] = []
    for name, cx, cy, scale in crops:
        cropped = crop_16_9(img, cx, cy, scale).resize(SCREENSHOT_SIZE, Image.Resampling.LANCZOS)
        path = shots_dir / f"{name}.png"
        cropped.save(path, optimize=True)
        paths.append(path)

    extra_dir = shots_dir / "extra"
    if extra_dir.exists():
        for idx, extra in enumerate(sorted(extra_dir.glob("*.png")), start=6):
            extra_img = Image.open(extra).convert("RGB")
            cropped = crop_16_9(extra_img, 0.5, 0.48, 1.0).resize(
                SCREENSHOT_SIZE, Image.Resampling.LANCZOS
            )
            path = shots_dir / f"{idx:02d}_extra.png"
            cropped.save(path, optimize=True)
            paths.append(path)
    return paths[:5] if len(paths) >= 5 else paths


def pick_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()


def compose_capsule(bg: Image.Image, size: tuple[int, int], title: str) -> Image.Image:
    w, h = size
    cover = crop_16_9(bg, 0.5, 0.48, 1.05).resize((w, h), Image.Resampling.LANCZOS)
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(h):
        alpha = int(180 * (y / h) ** 1.6)
        draw.line([(0, y), (w, y)], fill=(8, 12, 18, alpha))
    composed = Image.alpha_composite(cover.convert("RGBA"), overlay)
    draw = ImageDraw.Draw(composed)
    font_size = max(18, int(h * 0.18))
    font = pick_font(font_size)
    bbox = draw.textbbox((0, 0), title, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (w - tw) // 2
    y = h - th - max(8, h // 12)
    draw.text((x + 2, y + 2), title, font=font, fill=(0, 0, 0, 180))
    draw.text((x, y), title, font=font, fill=(230, 245, 255, 255))
    return composed.convert("RGB")


def save_capsules(img: Image.Image) -> list[Path]:
    caps_dir = OUT / "capsules"
    caps_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for name, size in CAPSULES.items():
        path = caps_dir / f"{name}.png"
        if size[0] / size[1] < 1:
            # Portrait store/library capsules
            cover = crop_16_9(img, 0.5, 0.45, 1.2)
            cover = cover.resize(
                (int(size[1] * 16 / 9), size[1]), Image.Resampling.LANCZOS
            )
            left = max(0, (cover.width - size[0]) // 2)
            cover = cover.crop((left, 0, left + size[0], size[1]))
        elif size[0] >= 1200 and "library_hero" not in name:
            cover = crop_16_9(img, 0.5, 0.45, 0.95).resize(size, Image.Resampling.LANCZOS)
        elif "library_hero" in name:
            cover = crop_16_9(img, 0.5, 0.45, 0.95).resize(size, Image.Resampling.LANCZOS)
        elif size[0] >= 1000:
            cover = crop_16_9(img, 0.5, 0.45, 1.0).resize(size, Image.Resampling.LANCZOS)
        else:
            cover = compose_capsule(img, size, "walstad loom")
        cover.save(path, optimize=True)
        paths.append(path)
    return paths


def save_icons() -> list[Path]:
    icons_dir = OUT / "icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    tmp_png = icons_dir / "_icon_src.png"
    if ICON_SOURCE.exists():
        subprocess.run(
            ["sips", "-s", "format", "png", str(ICON_SOURCE), "--out", str(tmp_png)],
            check=True,
            capture_output=True,
        )
        icon = Image.open(tmp_png).convert("RGBA")
    else:
        icon = Image.new("RGBA", (512, 512), (30, 90, 120, 255))

    paths: list[Path] = []
    for size in (32, 256, 512):
        path = icons_dir / f"icon_{size}.png"
        icon.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)
        paths.append(path)

    client_icon = icons_dir / "clienticon.png"
    icon.resize((32, 32), Image.Resampling.LANCZOS).save(client_icon, optimize=True)
    paths.append(client_icon)
    return paths


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    img = load_source()
    screenshots = save_screenshots(img)
    capsules = save_capsules(img)
    icons = save_icons()
    print(f"Generated {len(screenshots)} screenshots, {len(capsules)} capsules, {len(icons)} icons in {OUT}")


if __name__ == "__main__":
    main()
