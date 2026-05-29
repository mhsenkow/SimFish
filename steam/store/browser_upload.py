#!/usr/bin/env python3
"""Generate small JS snippets for in-page Steam asset upload (Cursor browser CDP)."""

from __future__ import annotations

import base64
import json
from pathlib import Path

ASSETS = Path(__file__).resolve().parent / "assets"
OUT = Path("/tmp/steam_upload_steps")
CHUNK = 700_000


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
        steps.append(
            {
                "label": f"init {rel}",
                "expr": f"window.{key}=''; 0",
            }
        )
        for part_i in range(0, len(b64), CHUNK):
            chunk = b64[part_i : part_i + CHUNK]
            steps.append(
                {
                    "label": f"chunk {rel} {part_i // CHUNK}",
                    "expr": f"window.{key}+={json.dumps(chunk)};",
                }
            )
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
            "expr": """(() => {
  $J('#game_image_drop_preview div.screenshot_upload_preview').each(function() {
    const sel = $J(this).find('select.image_type_select');
    if (sel.length && !sel.val()) {
      const opts = sel.find('option[value!=""]');
      if (opts.length === 1) sel.val(opts.val());
    }
    const type = sel.val() || $J(this).find('input.image_type_select').val();
    if (type === 'Screenshot') {
      $J(this).find('input.image_all_ages_appropriate_radio[value=yes]').prop('checked', true);
    }
  });
  const n = $J('#game_image_drop_preview div.screenshot_upload_preview').length;
  SubmitImageUpload(1202304, 'Game', '', '', 1);
  return { previews: n };
})()""",
        }
    )

    manifest = OUT / "manifest.json"
    manifest.write_text(json.dumps(steps, indent=2))
    print(f"Wrote {len(steps)} steps to {manifest}")


if __name__ == "__main__":
    main()
