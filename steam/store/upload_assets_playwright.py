#!/usr/bin/env python3
"""Upload store assets via Steamworks Graphical Assets page (uses Chrome cookies)."""

from __future__ import annotations

import sys
from pathlib import Path

import browser_cookie3
from playwright.sync_api import sync_playwright

ASSETS = Path(__file__).resolve().parent / "assets"
APP_ID = 1202304
STORE_URL = f"https://partner.steamgames.com/admin/game/edit/{APP_ID}?activetab=tab_graphicalassets"


def collect_files() -> list[Path]:
    paths: list[Path] = []
    for folder in ("screenshots", "capsules", "icons"):
        paths.extend(sorted((ASSETS / folder).glob("*.png")))
    return [p for p in paths if p.name != "_icon_src.png"]


def steam_cookies() -> list[dict]:
    cookies: list[dict] = []
    for c in browser_cookie3.chrome(domain_name="partner.steamgames.com"):
        cookies.append(
            {
                "name": c.name,
                "value": c.value,
                "domain": c.domain,
                "path": c.path or "/",
                "secure": bool(c.secure),
                "httpOnly": bool(getattr(c, "_rest", {}).get("HttpOnly", False)),
            }
        )
    if not any(c["name"] == "sessionid" for c in cookies):
        raise SystemExit("No Steamworks session in Chrome. Log in at partner.steamgames.com first.")
    return cookies


def main() -> int:
    files = collect_files()
    if not files:
        print("No assets found. Run generate_assets.py first.", file=sys.stderr)
        return 1

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=False)
        context = browser.new_context()
        context.add_cookies(steam_cookies())
        page = context.new_page()
        page.goto(STORE_URL, wait_until="networkidle", timeout=120_000)
        page.wait_for_timeout(3000)

        if "login" in page.url.lower():
            print("Steamworks session expired. Log in via Chrome, then re-run.", file=sys.stderr)
            browser.close()
            return 1

        file_input = page.locator('input[type="file"][accept*="image"]')
        if file_input.count() == 0:
            print("Upload input not found on Graphical Assets tab.", file=sys.stderr)
            browser.close()
            return 1

        print(f"Uploading {len(files)} files…")
        file_input.first.set_input_files([str(f) for f in files])
        page.wait_for_timeout(10000)

        page.evaluate(
            """() => {
              document.querySelectorAll('#game_image_drop_preview div.screenshot_upload_preview').forEach(el => {
                const yes = el.querySelector('input.image_all_ages_appropriate_radio[value=yes]');
                if (yes) yes.checked = true;
              });
            }"""
        )

        submitted = page.evaluate(
            f"""() => {{
              if (typeof SubmitImageUpload === 'function') {{
                SubmitImageUpload({APP_ID}, 'Game', '', '', 1);
                return 'SubmitImageUpload';
              }}
              return null;
            }}"""
        )
        print("submit:", submitted)
        page.wait_for_timeout(15000)
        print(f"Done. Verify at {STORE_URL}")
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
