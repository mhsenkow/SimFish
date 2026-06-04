#!/usr/bin/env python3
"""Chunked in-page upload helper for Steam Graphical Assets (paste steps in browser console)."""

from __future__ import annotations

import base64
import json
from pathlib import Path

ASSETS = Path(__file__).resolve().parent / "assets"
OUT = Path("/tmp/steam_upload_steps")
CHUNK = 600_000
APP_ID = 1202304


def asset_paths() -> list[Path]:
    paths: list[Path] = []
    for folder in ("screenshots", "capsules"):
        paths.extend(sorted((ASSETS / folder).glob("*.png")))
    return paths


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    steps: list[dict[str, str]] = []
    idx = 0

    for path in asset_paths():
        rel = path.relative_to(ASSETS).as_posix()
        b64 = base64.b64encode(path.read_bytes()).decode()
        key = f"__b64_{idx}"
        steps.append({"label": f"init {rel}", "expr": f"window.{key}=''; 0"})
        for part_i in range(0, len(b64), CHUNK):
            chunk = b64[part_i : part_i + CHUNK]
            steps.append({"label": f"chunk {rel} {part_i // CHUNK}", "expr": f"window.{key}+={json.dumps(chunk)};"})
        steps.append(
            {
                "label": f"load {rel}",
                "expr": f"""(() => {{
  const b64 = window.{key};
  delete window.{key};
  const bin = atob(b64);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  const file = new File([arr], {json.dumps(path.name)}, {{ type: 'image/png' }});
  LoadImageFilesForUpload([file], imgs => OnImagesLoadComplete(imgs));
  return file.name;
}})()""",
            }
        )
        idx += 1

    steps.append(
        {
            "label": "mark screenshots all-ages + submit",
            "expr": f"""(() => {{
  $J('#game_image_drop_preview div.screenshot_upload_preview').each(function() {{
    const yes = $J(this).find('input.image_all_ages_appropriate_radio[value=yes]');
    if (yes.length) yes.prop('checked', true);
  }});
  SubmitImageUpload({APP_ID}, 'Game', '', '', 1);
  return {{ previews: $J('#game_image_drop_preview div.screenshot_upload_preview').length }};
}})()""",
        }
    )

    manifest = OUT / "manifest.json"
    manifest.write_text(json.dumps(steps, indent=2))
    runner = OUT / "run_in_console.js"
    runner.write_text(
        "// Open DevTools console on Graphical Assets tab, then paste each step's expr from manifest.json\n"
        + f"// {len(steps)} steps, app {APP_ID}\n"
    )
    print(f"Wrote {len(steps)} steps to {manifest}")
    print(f"Store editor: https://partner.steamgames.com/admin/game/edit/{APP_ID}?activetab=tab_graphicalassets")


if __name__ == "__main__":
    main()
