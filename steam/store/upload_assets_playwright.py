#!/usr/bin/env python3
"""Upload Graphical Assets to Steamworks (uses Chrome cookies + in-page JS)."""

from __future__ import annotations

import base64
import sys
from pathlib import Path

import browser_cookie3
from playwright.sync_api import Page, sync_playwright

ASSETS = Path(__file__).resolve().parent / "assets"
# Confirm before running — this script drives the live partner site and would
# edit whichever app this points at. Shipping app id matches project.godot /
# STEAMWORKS.md.
APP_ID = 1202304  # partner edit id; shipping AppID is 4796460
STORE_URL = f"https://partner.steamgames.com/admin/game/edit/{APP_ID}?activetab=tab_graphicalassets"

STORE_CAPSULES = (
    "header_capsule_920x430.png",
    "small_capsule_462x174.png",
    "main_capsule_1232x706.png",
    "hero_capsule_748x896.png",
)

# Steam dropdown labels in the upload preview queue.
FILENAME_TO_TYPE = {
    "header_capsule": "Header Capsule",
    "small_capsule": "Small Capsule",
    "main_capsule": "Main Capsule",
    "hero_capsule": "Vertical Capsule",
    "library_header": "Library Header",
    "library_capsule": "Library Capsule",
    "library_hero": "Library Hero",
    "library_logo": "Library Logo",
    "clienticon": "Client Icon",
}


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
            }
        )
    if not any(c["name"] == "sessionid" for c in cookies):
        raise SystemExit("No Steamworks session in Chrome. Log in at partner.steamgames.com first.")
    return cookies


def collect_files(store_only: bool) -> list[Path]:
    if store_only:
        return [ASSETS / "capsules" / name for name in STORE_CAPSULES if (ASSETS / "capsules" / name).exists()]
    paths: list[Path] = []
    for folder in ("screenshots", "capsules", "icons"):
        # .ico as well as .png: the Library Assets "Client Icon" field only
        # accepts .ico, so a png-only glob silently skipped the one asset that
        # decides what Steam shows in the library and on Linux/Steam Deck.
        for pattern in ("*.png", "*.ico"):
            paths.extend(sorted((ASSETS / folder).glob(pattern)))
    return [p for p in paths if p.name != "_icon_src.png"]


def steam_type_for(path: Path) -> str | None:
    lower = path.name.lower()
    for hint, label in FILENAME_TO_TYPE.items():
        if hint in lower:
            return label
    if "gameplay" in lower or path.parent.name == "screenshots":
        return "Screenshot"
    return None


def js_upload_file(page: Page, path: Path) -> None:
    b64 = base64.b64encode(path.read_bytes()).decode()
    mime = "image/x-icon" if path.suffix.lower() == ".ico" else "image/png"
    page.evaluate(
        """
        (args) => new Promise((resolve) => {
          const { b64, name, mime } = args;
          const bin = atob(b64);
          const arr = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
          const file = new File([arr], name, { type: mime });
          LoadImageFilesForUpload([file], imgs => {
            OnImagesLoadComplete(imgs);
            setTimeout(resolve, 1500);
          });
        })
        """,
        {"b64": b64, "name": path.name, "mime": mime},
    )


def js_assign_preview_types(page: Page, assignments: list[tuple[str, str]]) -> None:
    page.evaluate(
        """
        (assignments) => {
          const previews = [...document.querySelectorAll('#game_image_drop_preview div.screenshot_upload_preview')];
          for (const [filename, targetType] of assignments) {
            const el = previews.find(p => p.innerText.includes(filename) || p.querySelector('img')?.src?.includes(filename));
            const preview = el || previews.find(p => {
              const sel = p.querySelector('select.image_type_select');
              return sel && !sel.value;
            }) || previews[previews.length - 1];
            if (!preview) continue;
            const sel = preview.querySelector('select.image_type_select');
            if (!sel) continue;
            for (const opt of sel.options) {
              if (opt.text === targetType || opt.value === targetType) {
                sel.value = opt.value;
                sel.dispatchEvent(new Event('change', { bubbles: true }));
                break;
              }
            }
            if (targetType === 'Screenshot') {
              const yes = preview.querySelector('input.image_all_ages_appropriate_radio[value=yes]');
              if (yes) yes.checked = true;
            }
          }
        }
        """,
        assignments,
    )


def js_submit_and_save(page: Page) -> None:
    page.evaluate(f"() => SubmitImageUpload({APP_ID}, 'Game', '', '', 1)")
    page.wait_for_timeout(8000)
    save = page.locator('input[value="Save Changes"]')
    if save.count():
        save.first.click()
        page.wait_for_timeout(8000)


def main() -> int:
    store_only = "--store-only" in sys.argv
    files = collect_files(store_only=store_only)
    if not files:
        print("No assets found. Run generate_assets.py first.", file=sys.stderr)
        return 1

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=False)
        context = browser.new_context()
        context.add_cookies(steam_cookies())
        page = context.new_page()
        page.goto(STORE_URL, wait_until="networkidle", timeout=120_000)
        page.wait_for_timeout(2000)

        if "login" in page.url.lower():
            print("Steamworks session expired.", file=sys.stderr)
            browser.close()
            return 1

        assignments: list[tuple[str, str]] = []
        for path in files:
            steam_type = steam_type_for(path)
            if not steam_type:
                print(f"skip (unknown type): {path.name}")
                continue
            print(f"queue: {path.name} -> {steam_type}")
            js_upload_file(page, path)
            assignments.append((path.name, steam_type))

        js_assign_preview_types(page, assignments)
        js_submit_and_save(page)

        status = page.evaluate(
            """() => ({
              banner: document.body.innerText.match(/Store assets[^\\n]+|Screenshot assets[^\\n]+|Library assets[^\\n]+/g),
              slots: ['header_image','small_capsule','main_capsule','hero_capsule'].map(c => ({
                c,
                t: document.querySelector('.image_preview_col.' + c)?.innerText?.trim()?.slice(0, 60)
              }))
            })"""
        )
        print("result:", status)
        print(f"Done. Verify: {STORE_URL}")
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
