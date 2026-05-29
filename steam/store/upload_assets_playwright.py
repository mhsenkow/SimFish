#!/usr/bin/env python3
"""Upload generated store assets to Steamworks store admin (Graphical Assets tab)."""

from __future__ import annotations

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ASSETS = Path(__file__).resolve().parent / "assets"
STORE_URL = "https://partner.steamgames.com/admin/game/edit/1202304?activetab=tab_graphicalassets"


def collect_files() -> list[Path]:
    paths: list[Path] = []
    for folder in ("screenshots", "capsules", "icons"):
        paths.extend(sorted((ASSETS / folder).glob("*.png")))
    # Skip intermediate icon source
    return [p for p in paths if p.name != "_icon_src.png"]


def main() -> int:
    files = collect_files()
    if not files:
        print("No assets found. Run generate_assets.py first.", file=sys.stderr)
        return 1

    chrome_data = Path.home() / "Library/Application Support/Google/Chrome"
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(chrome_data),
            channel="chrome",
            headless=False,
            args=["--profile-directory=Default"],
        )
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(STORE_URL, wait_until="domcontentloaded")
        page.wait_for_timeout(3000)
        file_input = page.locator('input[type="file"][accept*="image"]')
        if file_input.count() == 0:
            print("Could not find image upload input. Are you logged into Steamworks?", file=sys.stderr)
            context.close()
            return 1
        file_input.set_input_files([str(f) for f in files])
        page.wait_for_timeout(5000)
        upload_btn = page.locator('input[value="Upload"], button:has-text("Upload")')
        if upload_btn.count():
            upload_btn.first.click()
            page.wait_for_timeout(10000)
        print(f"Uploaded {len(files)} files via file input.")
        context.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
