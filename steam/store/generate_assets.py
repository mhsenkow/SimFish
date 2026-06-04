#!/usr/bin/env python3
"""Generate Steam store assets from marketing art and gameplay captures."""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
MARKETING = REPO / "marketing"
SOURCE = REPO / "output" / "godot_mm.png"
PREVIEW = REPO / "output" / "walstad_loom_preview.png"
LOGO_DIR = MARKETING / "logo"
OUT = ROOT / "assets"

SCREENSHOT_SIZE = (1920, 1080)

# Hand-made marketing art → exact Steam capsule filenames.
MARKETING_CAPSULES: dict[str, str] = {
    "small_capsule_462x174.png": "Small capsule (1).png",
    "main_capsule_1232x706.png": "Main capsule (2).png",
    "library_header_920x430.png": "header capsule (1).png",
    "hero_capsule_748x896.png": "vert (1).png",
}

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


def crop_to_ratio(img: Image.Image, ratio: float, center_x: float, center_y: float, scale: float) -> Image.Image:
    w, h = img.size
    crop_h = int(h / scale)
    crop_w = int(crop_h * ratio)
    crop_w = min(crop_w, w)
    crop_h = int(crop_w / ratio)
    cx = int(w * center_x)
    cy = int(h * center_y)
    left = max(0, min(w - crop_w, cx - crop_w // 2))
    top = max(0, min(h - crop_h, cy - crop_h // 2))
    return img.crop((left, top, left + crop_w, top + crop_h))


def crop_16_9(img: Image.Image, center_x: float, center_y: float, scale: float) -> Image.Image:
    return crop_to_ratio(img, 16 / 9, center_x, center_y, scale)


def fit_cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    tw, th = size
    ratio = tw / th
    cropped = crop_to_ratio(img, ratio, 0.5, 0.5, 1.0)
    return cropped.resize(size, Image.Resampling.LANCZOS)


def load_rgb(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def save_screenshots() -> list[Path]:
    """Use hand-captured gameplay shots from marketing/ when present."""
    shots_dir = OUT / "screenshots"
    shots_dir.mkdir(parents=True, exist_ok=True)

    gameplay = sorted(MARKETING.glob("Screenshot*.png"))
    if gameplay:
        paths: list[Path] = []
        for idx, path in enumerate(gameplay[:5], start=1):
            img = load_rgb(path)
            if abs((img.width / img.height) - (16 / 9)) > 0.02:
                img = crop_16_9(img, 0.5, 0.50, 1.0)
            out_path = shots_dir / f"{idx:02d}_gameplay.png"
            img.resize(SCREENSHOT_SIZE, Image.Resampling.LANCZOS).save(out_path, optimize=True)
            paths.append(out_path)
            print(f"  screenshot: {out_path.name} <- {path.name}")
        if len(paths) < 5:
            raise SystemExit(f"Need 5 gameplay screenshots, found {len(gameplay)} in marketing/")
        return paths

    # Fallback when no hand captures exist yet.
    sources: list[tuple[str, Path, float, float, float]] = [
        ("01_gameplay_main", SOURCE, 0.50, 0.48, 1.0),
        ("02_gameplay_creature", SOURCE, 0.22, 0.45, 1.25),
        ("03_reef_tank", MARKETING / "back (1).png", 0.50, 0.50, 1.0),
        ("04_reef_coral", MARKETING / "back (1).png", 0.78, 0.48, 1.35),
        ("05_preview_art", PREVIEW, 0.50, 0.50, 1.0),
    ]

    paths = []
    for name, path, cx, cy, scale in sources:
        if not path.exists():
            print(f"  skip screenshot (missing): {path}")
            continue
        img = load_rgb(path)
        cropped = crop_16_9(img, cx, cy, scale).resize(SCREENSHOT_SIZE, Image.Resampling.LANCZOS)
        out_path = shots_dir / f"{name}.png"
        cropped.save(out_path, optimize=True)
        paths.append(out_path)
        print(f"  screenshot: {out_path.name} <- {path.name}")

    if len(paths) < 5:
        raise SystemExit(f"Need 5 screenshots, only got {len(paths)}.")
    return paths[:5]


def copy_marketing_capsules() -> dict[str, Image.Image]:
    """Copy hand-made capsules; return loaded images for deriving the rest."""
    caps_dir = OUT / "capsules"
    caps_dir.mkdir(parents=True, exist_ok=True)
    loaded: dict[str, Image.Image] = {}

    for out_name, src_name in MARKETING_CAPSULES.items():
        src = MARKETING / src_name
        if not src.exists():
            raise SystemExit(f"Missing marketing capsule: {src}")
        img = load_rgb(src)
        expected = CAPSULES[out_name.replace(".png", "")]
        if img.size != expected:
            img = fit_cover(img, expected)
        dest = caps_dir / out_name
        img.save(dest, optimize=True)
        loaded[out_name] = img
        print(f"  capsule: {out_name} <- {src_name}")

    return loaded


def save_derived_capsules(loaded: dict[str, Image.Image]) -> list[Path]:
    """Fill Steam slots that aren't in marketing/ yet."""
    caps_dir = OUT / "capsules"
    paths: list[Path] = list(caps_dir.glob("*.png"))
    main = loaded.get("main_capsule_1232x706.png")
    vert = loaded.get("hero_capsule_748x896.png")
    header = loaded.get("library_header_920x430.png")
    reef = MARKETING / "back (1).png"
    reef_img = load_rgb(reef) if reef.exists() else main

    derived: list[tuple[str, Image.Image | None, tuple[int, int]]] = [
        ("package_header_1414x464.png", header or main, (1414, 464)),
        ("library_hero_3840x1240.png", reef_img, (3840, 1240)),
        ("library_capsule_600x900.png", vert, (600, 900)),
        ("library_logo_1280x720.png", None, (1280, 720)),
    ]

    for name, src, size in derived:
        if (caps_dir / name).exists():
            continue
        if "library_logo" in name:
            wordmark = LOGO_DIR / "wordmark_1280x720.png"
            if wordmark.exists():
                out = fit_cover(load_rgb(wordmark), size)
            elif src is not None:
                w, h = src.size
                logo = src.crop((w // 3, 0, w, h))
                out = fit_cover(logo, size)
            else:
                continue
        elif src is None:
            continue
        else:
            out = fit_cover(src, size)
        out.save(caps_dir / name, optimize=True)
        paths.append(caps_dir / name)
        print(f"  derived capsule: {name}")

    return sorted(set(paths))


def pick_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
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


def save_icons() -> list[Path]:
    icons_dir = OUT / "icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    logo_512 = LOGO_DIR / "icon_512.png"
    if logo_512.exists():
        icon = Image.open(logo_512).convert("RGBA")
    else:
        icon = Image.new("RGBA", (512, 512), (30, 90, 120, 255))

    paths: list[Path] = []
    for size in (32, 256, 512):
        src = LOGO_DIR / f"icon_{size}.png"
        if src.exists():
            img = Image.open(src).convert("RGBA")
        else:
            img = icon.resize((size, size), Image.Resampling.NEAREST)
        path = icons_dir / f"icon_{size}.png"
        img.save(path, optimize=True)
        paths.append(path)

    client_icon = icons_dir / "clienticon.png"
    if (LOGO_DIR / "icon_32.png").exists():
        Image.open(LOGO_DIR / "icon_32.png").convert("RGBA").save(client_icon, optimize=True)
    else:
        icon.resize((32, 32), Image.Resampling.NEAREST).save(client_icon, optimize=True)
    paths.append(client_icon)
    return paths


def main() -> None:
    if not MARKETING.exists():
        raise SystemExit(f"Missing marketing folder: {MARKETING}")
    if not sorted(MARKETING.glob("Screenshot*.png")) and not SOURCE.exists():
        raise SystemExit(f"Missing gameplay capture: {SOURCE}")
    if not (LOGO_DIR / "icon_512.png").exists():
        print("Generating logo…")
        import generate_logo

        generate_logo.main()

    if not PREVIEW.exists():
        print("  (optional) run render_preview.py for a 5th screenshot variant")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    print("Copying marketing capsules…")
    loaded = copy_marketing_capsules()
    print("Deriving remaining capsules…")
    capsules = save_derived_capsules(loaded)
    print("Building diverse screenshots…")
    screenshots = save_screenshots()
    print("Building icons…")
    icons = save_icons()
    print(
        f"\nReady: {len(screenshots)} screenshots, {len(capsules)} capsules, {len(icons)} icons"
        f"\n  → {OUT}\n"
        f"Upload at: https://partner.steamgames.com/admin/game/edit/1202304?activetab=tab_graphicalassets"
    )


if __name__ == "__main__":
    main()
