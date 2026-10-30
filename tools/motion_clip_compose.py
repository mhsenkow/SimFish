#!/usr/bin/env python3
"""Turn motion-clip frame directories into review GIFs (CREATURE_MOTION_700 #98, #99).

dev/motion_clip.tscn writes frame_0000.png ... plus motion.csv into one
directory per clip. This tool:

  gif DIR [-o OUT.gif]
      One clip -> one looping GIF (default DIR/clip.gif).

  pair BEFORE_DIR AFTER_DIR [-o OUT.gif] [--labels before after] [--frames-out DIR]
      The same seed / species / manoeuvre captured before and after a change,
      laid side by side with a label bar over each half, frame by frame
      (the shorter clip holds its last frame). Default output:
      output/motion_lab/<before>__vs__<after>.gif. --frames-out also writes
      the composed PNG frames, for stepping through by hand.

Common options: --fps (default: the clip's meta.json fps, else 30),
--scale (resize factor, default 1.0), --every N (keep every Nth frame).

Dependency: Pillow (python3 -m pip install Pillow). Nothing else.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - dependency message only
    sys.stderr.write(
        "motion_clip_compose.py needs Pillow: python3 -m pip install Pillow\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
LABEL_H = 18


def frame_paths(d: Path) -> list[Path]:
    frames = sorted(d.glob("frame_*.png"))
    if not frames:
        raise SystemExit(f"no frame_*.png in {d}")
    return frames


def clip_fps(d: Path, fallback: float = 30.0) -> float:
    meta = d / "meta.json"
    if meta.exists():
        try:
            return float(json.loads(meta.read_text()).get("fps", fallback))
        except (ValueError, OSError):
            pass
    return fallback


def load(path: Path, scale: float) -> Image.Image:
    im = Image.open(path).convert("RGB")
    if scale != 1.0:
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))),
                       Image.NEAREST)
    return im


def save_gif(frames: list[Image.Image], out: Path, fps: float) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    # GIF delays are in centiseconds; Pillow takes milliseconds.
    duration = max(20, round(1000.0 / max(fps, 1.0)))
    # One adaptive palette per frame keeps the pixel-art colours honest.
    pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
           for f in frames]
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=duration, loop=0,
                optimize=False, disposal=1)
    print(f"[motion_clip_compose] {len(frames)} frames @ {fps:.1f} fps -> {out}")


def labelled(im: Image.Image, text: str) -> Image.Image:
    out = Image.new("RGB", (im.width, im.height + LABEL_H), (24, 26, 30))
    out.paste(im, (0, LABEL_H))
    draw = ImageDraw.Draw(out)
    draw.text((6, 3), text, fill=(225, 232, 240), font=ImageFont.load_default())
    return out


def cmd_gif(args: argparse.Namespace) -> None:
    d = Path(args.dir)
    paths = frame_paths(d)[:: args.every]
    fps = args.fps or clip_fps(d) / args.every
    frames = [load(p, args.scale) for p in paths]
    save_gif(frames, Path(args.out) if args.out else d / "clip.gif", fps)


def cmd_pair(args: argparse.Namespace) -> None:
    a, b = Path(args.before), Path(args.after)
    pa, pb = frame_paths(a)[:: args.every], frame_paths(b)[:: args.every]
    fps = args.fps or clip_fps(a) / args.every
    la, lb = args.labels
    n = max(len(pa), len(pb))
    frames_out = Path(args.frames_out) if args.frames_out else None
    if frames_out:
        frames_out.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    for i in range(n):
        ia = labelled(load(pa[min(i, len(pa) - 1)], args.scale), f"{la}  {i:04d}")
        ib = labelled(load(pb[min(i, len(pb) - 1)], args.scale), f"{lb}  {i:04d}")
        out = Image.new("RGB", (ia.width + ib.width + 4, max(ia.height, ib.height)), (10, 10, 10))
        out.paste(ia, (0, 0))
        out.paste(ib, (ia.width + 4, 0))
        frames.append(out)
        if frames_out:
            out.save(frames_out / f"frame_{i:04d}.png")
    default = ROOT / "output" / "motion_lab" / f"{a.name}__vs__{b.name}.gif"
    save_gif(frames, Path(args.out) if args.out else default, fps)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("-o", "--out", help="output GIF path")
        p.add_argument("--fps", type=float, default=0.0, help="playback fps (default: clip fps)")
        p.add_argument("--scale", type=float, default=1.0, help="resize factor (nearest)")
        p.add_argument("--every", type=int, default=1, help="keep every Nth frame")

    g = sub.add_parser("gif", help="one frame directory -> GIF")
    g.add_argument("dir")
    common(g)
    g.set_defaults(func=cmd_gif)

    p = sub.add_parser("pair", help="before/after frame directories side by side -> GIF")
    p.add_argument("before")
    p.add_argument("after")
    p.add_argument("--labels", nargs=2, default=["before", "after"], metavar=("BEFORE", "AFTER"))
    p.add_argument("--frames-out", help="also write composed PNG frames here")
    common(p)
    p.set_defaults(func=cmd_pair)

    args = ap.parse_args()
    args.every = max(1, args.every)
    args.func(args)


if __name__ == "__main__":
    main()
