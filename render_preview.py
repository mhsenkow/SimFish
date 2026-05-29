"""
Render a walstad loom tank preview - the real palette pipeline, applied to a
hand-built scene. Produces:
  output/walstad_loom_preview.png   (single chunky pixel-art frame, upscaled 4x)
  output/walstad_loom_bubbles.gif   (12-frame loop showing rising bubbles)

This is not the Rust sim's output - it's a Python recreation of the same
rendering rules (palette quantize + Bayer dither, depth-attenuated water,
L-system plants) so you can SEE the look of the game right now.
"""

from __future__ import annotations

import math
import random
from pathlib import Path
from PIL import Image

W, H = 384, 216
UPSCALE = 4  # final image is W*UPSCALE x H*UPSCALE for visibility
SURFACE_Y = int(H * 0.20)  # meniscus row
SUBSTRATE_TOP_Y = int(H * 0.78)
HERE = Path(__file__).parent
OUT_DIR = HERE / "output"
OUT_DIR.mkdir(exist_ok=True)


# -- Palette (planted biotope, 48 entries; same as shaders-godot/make_palette.py) --
PALETTE_HEX = [
    "#0b1a22", "#163040", "#23475a", "#356379",
    "#4b8095", "#69a1b3", "#92c3d0", "#c5e2e7",
    "#102614", "#1d3b22", "#2c5a30", "#3e7f40",
    "#57a253", "#79c069", "#a5d97e", "#d0eb9a",
    "#1a120c", "#2c1f15", "#432f1f", "#5d4128",
    "#785538", "#95714e", "#b18f6a", "#cdb088",
    "#1a1a1f", "#2a2a30", "#3d3d44", "#555560",
    "#707081", "#8c8ca0", "#a8a8bd", "#c4c4d6",
    "#ffffff", "#e0eef2", "#b9d6df",
    "#c33b3b", "#d97e2c", "#e6c92a", "#2a7a4b",
    "#4a52c4", "#872cb0", "#c44a8e", "#000000",
    "#2c1810", "#1a0f08", "#0d0805", "#503820",
]


def hex_to_rgb(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


PALETTE = [hex_to_rgb(h) for h in PALETTE_HEX]


# Bayer 4x4 matrix, 0..15 normalized to -0.5..+0.5
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def bayer(x: int, y: int) -> float:
    return BAYER4[y & 3][x & 3] / 16.0 - 0.5


def nearest_two(rgb: tuple[int, int, int]) -> tuple[int, int, float]:
    """Return (best_idx, second_idx, t) where t is how far rgb sits between them."""
    best = (1e18, 0)
    sec = (1e18, 0)
    for i, p in enumerate(PALETTE):
        d = (rgb[0] - p[0]) ** 2 + (rgb[1] - p[1]) ** 2 + (rgb[2] - p[2]) ** 2
        if d < best[0]:
            sec = best
            best = (d, i)
        elif d < sec[0]:
            sec = (d, i)
    a = PALETTE[best[1]]
    b = PALETTE[sec[1]]
    abx, aby, abz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    denom = abx * abx + aby * aby + abz * abz
    if denom == 0:
        return best[1], sec[1], 0.0
    cax, cay, caz = rgb[0] - a[0], rgb[1] - a[1], rgb[2] - a[2]
    t = (cax * abx + cay * aby + caz * abz) / denom
    return best[1], sec[1], max(0.0, min(1.0, t))


def quantize_to_palette(buf: list[list[tuple[int, int, int]]]) -> Image.Image:
    """Snap each pixel to the nearest palette color, dithered."""
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            ai, bi, t = nearest_two(buf[y][x])
            thresh = 0.5 + bayer(x, y) * 0.85
            px[x, y] = PALETTE[bi if t > thresh else ai]
    return img


# -- Scene builders. They write floats first; quantize at the end. --


def hash21(x: float, y: float) -> float:
    n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return n - math.floor(n)


def vnoise(x: float, y: float) -> float:
    ix, iy = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - ix, y - iy
    a = hash21(ix, iy)
    b = hash21(ix + 1, iy)
    c = hash21(ix, iy + 1)
    d = hash21(ix + 1, iy + 1)
    ux = fx * fx * (3 - 2 * fx)
    uy = fy * fy * (3 - 2 * fy)
    return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy


def lerp_rgb(a, b, t):
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def build_background(time: float) -> list[list[tuple[int, int, int]]]:
    """Continuous-color buffer; quantized later."""
    buf = [[(0, 0, 0)] * W for _ in range(H)]

    # ---- Room behind the tank (warm wall) ----
    wall_top = hex_to_rgb("#5e4a6e")  # plummy upper wall
    wall_bot = hex_to_rgb("#3c2c4a")
    for y in range(H):
        t = y / H
        buf[y] = [lerp_rgb(wall_top, wall_bot, t)] * W

    # ---- Sky/light above water (warm cast through tank top) ----
    above_top = hex_to_rgb("#8aa9b3")
    above_bot = hex_to_rgb("#c5e2e7")
    for y in range(SURFACE_Y):
        t = y / max(1, SURFACE_Y)
        for x in range(W):
            buf[y][x] = lerp_rgb(above_top, above_bot, t)

    # ---- Water column, depth-attenuated ----
    water_shallow = hex_to_rgb("#69a1b3")
    water_deep = hex_to_rgb("#0b1a22")
    tannin_tint = hex_to_rgb("#d8b888")
    tannin_strength = 0.10
    for y in range(SURFACE_Y, H):
        depth = (y - SURFACE_Y) / max(1, (H - SURFACE_Y))
        light = math.exp(-1.8 * depth)
        base = lerp_rgb(water_deep, water_shallow, light)
        # Tannins shift base toward warm brown.
        tt = (
            int(base[0] * (1 - tannin_strength) + tannin_tint[0] * tannin_strength * 0.7),
            int(base[1] * (1 - tannin_strength) + tannin_tint[1] * tannin_strength * 0.7),
            int(base[2] * (1 - tannin_strength) + tannin_tint[2] * tannin_strength * 0.6),
        )
        for x in range(W):
            buf[y][x] = tt

    # ---- Caustics: top 25% of water ----
    for y in range(SURFACE_Y, SURFACE_Y + (H - SURFACE_Y) // 4):
        d = (y - SURFACE_Y) / ((H - SURFACE_Y) / 4)
        strength = (1 - d) * 0.4
        for x in range(W):
            c = vnoise(x * 0.08 + time * 0.4, y * 0.18 + time * 0.15)
            c = max(0.0, (c - 0.55) / 0.3)
            if c > 0:
                px = buf[y][x]
                buf[y][x] = (
                    min(255, int(px[0] + 60 * c * strength)),
                    min(255, int(px[1] + 70 * c * strength)),
                    min(255, int(px[2] + 70 * c * strength)),
                )

    # ---- Meniscus: bright 1px line, with slight bulge highlight one above ----
    meniscus = hex_to_rgb("#e0eef2")
    sub_meniscus = hex_to_rgb("#b9d6df")
    for x in range(W):
        buf[SURFACE_Y][x] = meniscus
        if SURFACE_Y - 1 >= 0:
            buf[SURFACE_Y - 1][x] = lerp_rgb(buf[SURFACE_Y - 1][x], sub_meniscus, 0.5)
    return buf


def draw_substrate(buf, rng: random.Random):
    soil_ramp = ["#1a120c", "#2c1f15", "#432f1f", "#5d4128", "#785538", "#95714e"]
    soil_ramp = [hex_to_rgb(s) for s in soil_ramp]
    gravel = hex_to_rgb("#555560")
    gravel2 = hex_to_rgb("#3d3d44")
    # Aquasoil 12 rows deep with grain noise.
    aquasoil_top = SUBSTRATE_TOP_Y
    aquasoil_bot = SUBSTRATE_TOP_Y + 12
    for y in range(aquasoil_top, min(H, aquasoil_bot)):
        depth_t = (y - aquasoil_top) / 12
        for x in range(W):
            # Noisy ramp - top is lighter, deeper is darker, plus grain dither.
            g = vnoise(x * 0.6, y * 0.6)
            base_idx = max(0, min(5, int((1 - depth_t) * 4 + g * 2)))
            buf[y][x] = soil_ramp[base_idx]
    # Sand cap row.
    sand = hex_to_rgb("#cdb088")
    for y in range(aquasoil_bot, min(H, aquasoil_bot + 2)):
        for x in range(W):
            g = vnoise(x * 0.9, y * 0.9)
            buf[y][x] = lerp_rgb(sand, hex_to_rgb("#b18f6a"), g)
    # Gravel below.
    for y in range(aquasoil_bot + 2, H):
        for x in range(W):
            buf[y][x] = gravel if vnoise(x * 0.8, y * 0.8) > 0.5 else gravel2


def draw_driftwood(buf):
    """Driftwood arching out of the substrate, rooted on the left, branching up."""
    dark = hex_to_rgb("#1a120c")
    mid = hex_to_rgb("#2c1f15")
    high = hex_to_rgb("#5d4128")
    # Main trunk: sweeps from buried-left up and right.
    trunk = [
        (32, SUBSTRATE_TOP_Y + 8),   # buried root
        (58, SUBSTRATE_TOP_Y - 2),
        (98, SUBSTRATE_TOP_Y - 14),
        (148, SUBSTRATE_TOP_Y - 22),
        (190, SUBSTRATE_TOP_Y - 18),
        (228, SUBSTRATE_TOP_Y - 6),
        (252, SUBSTRATE_TOP_Y + 6),   # ends buried again on the right
    ]
    branch = [
        (148, SUBSTRATE_TOP_Y - 22),
        (160, SUBSTRATE_TOP_Y - 38),
        (172, SUBSTRATE_TOP_Y - 54),
        (188, SUBSTRATE_TOP_Y - 66),
    ]

    def stroke(points, thick_taper=True):
        for i in range(len(points) - 1):
            x0, y0 = points[i]
            x1, y1 = points[i + 1]
            steps = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
            for s in range(steps):
                t = s / steps
                x = int(x0 + (x1 - x0) * t)
                y = int(y0 + (y1 - y0) * t)
                # Taper: thicker in the middle of the trunk.
                local_t = (i + t) / max(1, len(points) - 1)
                taper_factor = math.sin(local_t * math.pi) if thick_taper else 0.7
                thickness = max(1, int(1 + 3 * taper_factor))
                for dy in range(-thickness, thickness + 1):
                    for dx in range(-thickness, thickness + 1):
                        if dx * dx + dy * dy > thickness * thickness:
                            continue
                        xx, yy = x + dx, y + dy
                        if not (0 <= xx < W and 0 <= yy < H):
                            continue
                        # Inner dark, mid ring, top highlight on the upper face.
                        d = math.sqrt(dx * dx + dy * dy)
                        if d < thickness - 1.5:
                            buf[yy][xx] = mid
                        elif dy < 0:
                            buf[yy][xx] = high
                        else:
                            buf[yy][xx] = dark

    stroke(trunk, thick_taper=True)
    stroke(branch, thick_taper=False)


def draw_lsystem_plant(buf, root_x: int, root_y: int, rng: random.Random,
                       leaf_palette_hex=("#102614", "#1d3b22", "#2c5a30", "#3e7f40", "#57a253"),
                       n_blades=7, height_range=(36, 60)):
    """Riverblade-style turtle interpretation of an L-system. Stochastic per blade."""
    leaf_palette = [hex_to_rgb(s) for s in leaf_palette_hex]
    for _ in range(n_blades):
        # Each blade is a slightly tilted ribbon.
        h = rng.randint(*height_range)
        sx = root_x + rng.randint(-4, 4)
        sway_phase = rng.random() * math.pi * 2
        sway_amp = rng.uniform(2.0, 5.0)
        for step in range(h):
            ny = root_y - step
            if ny < 0:
                break
            # Bend with phototropism + small sway.
            phototropism = -math.sin(step / h * math.pi / 2) * 0.05
            nx = sx + int(sway_amp * math.sin(sway_phase + step * 0.1) * (step / h))
            nx += int(phototropism * step)
            if not (0 <= nx < W):
                continue
            shade = min(4, step // (h // 5))
            buf[ny][nx] = leaf_palette[4 - shade]
            # Thicken middle of blade.
            if 6 < step < h - 4:
                if 0 <= nx - 1 < W:
                    buf[ny][nx - 1] = leaf_palette[3 - min(3, shade)]


def draw_fish(buf, x: int, y: int, length: int, body_hex: str, accent_hex: str,
              facing: int = 1):
    """Tetra-like fish facing right (facing=1) or left (facing=-1).
    Body is an asymmetric teardrop: blunt head, tapered tail, with a forked tail fin."""
    body = hex_to_rgb(body_hex)
    body_dark = lerp_rgb(body, (0, 0, 0), 0.35)
    accent = hex_to_rgb(accent_hex)
    eye = hex_to_rgb("#0b1a22")
    # Body: thickest 1/3 from head, then taper.
    for i in range(length):
        local = i / (length - 1)
        # Teardrop profile: peaks at ~0.35.
        prof = math.sin(local ** 0.7 * math.pi)
        thickness = max(1, int(prof * 2.2))
        bx = x + (i if facing == 1 else (length - 1 - i))
        for dy in range(-thickness, thickness + 1):
            yy = y + dy
            if 0 <= bx < W and 0 <= yy < H:
                # Underside darker (depth shading).
                buf[yy][bx] = body_dark if dy > 0 else body
        # Lateral line accent.
        if thickness >= 1 and 0.15 < local < 0.85:
            yy = y
            if 0 <= bx < W and 0 <= yy < H:
                buf[yy][bx] = accent
    # Tail fin: forked. Drawn off the tail end.
    tail_x = x + length if facing == 1 else x - 1
    fin_dx = 1 if facing == 1 else -1
    if 0 <= tail_x < W:
        for dy in (-2, -1, 0, 1, 2):
            if 0 <= y + dy < H:
                buf[y + dy][tail_x] = body
        # Top + bottom prongs of the fork.
        if 0 <= tail_x + fin_dx < W:
            for dy in (-3, 3):
                if 0 <= y + dy < H:
                    buf[y + dy][tail_x + fin_dx] = body
    # Dorsal fin
    dorsal_x = x + (length // 2 if facing == 1 else length // 2)
    if 0 <= dorsal_x < W and 0 <= y - 3 < H:
        buf[y - 3][dorsal_x] = body
    # Eye one pixel back from the head.
    eye_x = x + (1 if facing == 1 else length - 2)
    if 0 <= eye_x < W and 0 <= y < H:
        buf[y][eye_x] = eye


def draw_snail(buf, x: int, y: int, shell_hex: str = "#872cb0", body_hex: str = "#2c1f15"):
    """Tiny spiral snail (ramshorn-style) - 5x5 footprint, glass-clinging."""
    shell = hex_to_rgb(shell_hex)
    shell_dark = lerp_rgb(shell, (0, 0, 0), 0.4)
    body = hex_to_rgb(body_hex)
    # 5x5 spiral. Hard-coded little sprite.
    sprite = [
        "..ss.",
        ".sSs.",
        "sSdSs",
        ".sSs.",
        "bb.bb",
    ]
    palette_map = {"s": shell, "S": shell_dark, "d": shell_dark, "b": body}
    for dy, row in enumerate(sprite):
        for dx, ch in enumerate(row):
            if ch == ".":
                continue
            xx, yy = x + dx, y + dy
            if 0 <= xx < W and 0 <= yy < H:
                buf[yy][xx] = palette_map[ch]


def draw_bubbles(buf, stone_x: int, time: float, rng: random.Random):
    """A column of rising bubbles emanating from the bubbler stone."""
    # Stone itself.
    for dy in range(0, 4):
        for dx in range(-3, 4):
            xx, yy = stone_x + dx, H - 4 + dy
            if 0 <= xx < W and 0 <= yy < H:
                buf[yy][xx] = hex_to_rgb("#3d3d44") if (dx + dy) & 1 else hex_to_rgb("#2a2a30")
    # Bubbles, spawned at intervals based on time.
    bubble_color = hex_to_rgb("#c5e2e7")
    highlight = hex_to_rgb("#ffffff")
    n_bubbles = 14
    for i in range(n_bubbles):
        phase = (time * 0.6 + i / n_bubbles) % 1.0
        by = int(H - 6 - phase * (H - 8 - SURFACE_Y))
        if by < SURFACE_Y + 2:
            continue
        wobble = int(2 * math.sin(phase * 18 + i))
        bx = stone_x + wobble
        size = 1 + (i % 3)
        for dy in range(-size, size + 1):
            for dx in range(-size, size + 1):
                if dx * dx + dy * dy <= size * size:
                    xx, yy = bx + dx, by + dy
                    if 0 <= xx < W and 0 <= yy < H:
                        buf[yy][xx] = bubble_color
        # 1-pixel highlight on top-left of larger bubbles.
        if size >= 2 and 0 <= bx - 1 < W and 0 <= by - 1 < H:
            buf[by - 1][bx - 1] = highlight


def draw_tank_glass(buf):
    """Thin glass frame edges; the cabinet beneath."""
    frame = hex_to_rgb("#c4c4d6")
    inner = hex_to_rgb("#92c3d0")
    cabinet = hex_to_rgb("#2a2a30")
    # Top frame
    for x in range(20, W - 20):
        for y in range(8, 10):
            buf[y][x] = frame
    # Sides + bottom
    for y in range(8, H - 20):
        for x in (20, 21, W - 22, W - 21):
            if 0 <= x < W:
                buf[y][x] = frame
    for x in range(20, W - 20):
        for y in (H - 21, H - 20):
            buf[y][x] = frame
    # Cabinet
    for y in range(H - 20, H):
        for x in range(15, W - 15):
            buf[y][x] = cabinet
    # Faint highlight on the inside of the top edge (waterline reflection).
    for x in range(22, W - 22):
        buf[SURFACE_Y - 1][x] = lerp_rgb(buf[SURFACE_Y - 1][x], inner, 0.4)


def build_scene(time: float, seed: int) -> Image.Image:
    rng = random.Random(seed)
    buf = build_background(time)
    draw_substrate(buf, rng)
    draw_driftwood(buf)

    # A few plant clusters along the back.
    rng_plant = random.Random(seed + 1)
    draw_lsystem_plant(buf, 60, SUBSTRATE_TOP_Y, rng_plant, n_blades=8, height_range=(38, 64))
    draw_lsystem_plant(buf, 110, SUBSTRATE_TOP_Y - 4, rng_plant, n_blades=6, height_range=(30, 50))
    draw_lsystem_plant(buf, 250, SUBSTRATE_TOP_Y, rng_plant, n_blades=9, height_range=(46, 72))
    draw_lsystem_plant(buf, 310, SUBSTRATE_TOP_Y - 2, rng_plant, n_blades=7, height_range=(36, 58))

    # Crownleaf-style midground rosette (chunkier, shorter).
    draw_lsystem_plant(
        buf, 180, SUBSTRATE_TOP_Y - 4, random.Random(seed + 7),
        leaf_palette_hex=("#1d3b22", "#2c5a30", "#3e7f40", "#57a253", "#79c069"),
        n_blades=10, height_range=(14, 24),
    )

    # Bubbler stone on the right.
    draw_bubbles(buf, 340, time, rng)

    # Glassdart school - mid-water, all facing same direction (schooling).
    school_x = 110
    school_y = 95
    school_offsets = [(0, 0), (14, 4), (28, -2), (44, 6), (58, 1), (24, 12)]
    for dx, dy in school_offsets:
        draw_fish(buf, school_x + dx, school_y + dy, 7, "#c33b3b", "#e6c92a", facing=1)

    # A solo mudsifter on the substrate.
    draw_fish(buf, 230, SUBSTRATE_TOP_Y - 3, 9, "#785538", "#cdb088", facing=-1)

    # Spiralsnails on the glass + on driftwood (referencing the real tank's snails).
    draw_snail(buf, 28, SUBSTRATE_TOP_Y - 30, shell_hex="#872cb0")
    draw_snail(buf, 68, SUBSTRATE_TOP_Y - 18, shell_hex="#c44a8e")
    draw_snail(buf, 305, SUBSTRATE_TOP_Y - 12, shell_hex="#872cb0")
    draw_snail(buf, W - 30, SUBSTRATE_TOP_Y - 50, shell_hex="#c44a8e")
    # A baby on the leaf of a plant.
    draw_snail(buf, 256, 130, shell_hex="#872cb0")

    draw_tank_glass(buf)
    return quantize_to_palette(buf)


def upscale(img: Image.Image, factor: int) -> Image.Image:
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def main():
    print("Rendering still frame...")
    frame = build_scene(time=0.0, seed=42)
    big = upscale(frame, UPSCALE)
    out_png = OUT_DIR / "walstad_loom_preview.png"
    big.save(out_png)
    print(f"  -> {out_png}  ({big.width}x{big.height})")

    print("Rendering 12-frame bubble loop...")
    frames = []
    for i in range(12):
        f = build_scene(time=i / 12.0, seed=42)
        frames.append(upscale(f, UPSCALE))
    out_gif = OUT_DIR / "walstad_loom_bubbles.gif"
    frames[0].save(
        out_gif,
        save_all=True,
        append_images=frames[1:],
        duration=120,
        loop=0,
        optimize=False,
    )
    print(f"  -> {out_gif}  ({frames[0].width}x{frames[0].height}, 12 frames)")


if __name__ == "__main__":
    main()
