#!/usr/bin/env python3
"""Upload store assets to Steamworks using Chrome session cookies.

Keys mirror Steam's own g_ImageTypes (see UploadImages in the Graphical Assets
page). All capsule/library types are localized, so their form key MUST end with
`|english`. Screenshots are not localized and use the `|english[]` array form.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import browser_cookie3
import requests
from PIL import Image

ASSETS = Path(__file__).resolve().parent / "assets"
ITEM_ID = 4796460
SAVE_URL = f"https://partner.steamgames.com/admin/game/save/{ITEM_ID}?activetab=tab_graphicalassets&json=1"
LANG = "english"

# name, path (from g_ImageTypes), width, height, localized, enforce_min
IMAGE_TYPES = [
    {"name": "Header Capsule", "path": "header_image|header|assets|header_image|image", "w": 920, "h": 430, "localized": True},
    {"name": "Small Capsule", "path": "small_capsule|capsule|assets|small_capsule|image", "w": 462, "h": 174, "localized": True},
    {"name": "Main Capsule", "path": "main_capsule|capsule_616x353|assets|main_capsule|image", "w": 1232, "h": 706, "localized": True},
    {"name": "Vertical Capsule", "path": "hero_capsule|hero_capsule|assets|hero_capsule|image", "w": 748, "h": 896, "localized": True},
    {"name": "Library Hero", "path": "library_hero|library_hero|assets|library_hero|image", "w": 3840, "h": 1240, "localized": True},
    {"name": "Library Capsule", "path": "library_capsule|library_capsule|assets|library_capsule|image", "w": 600, "h": 900, "localized": True},
    {"name": "Library Header", "path": "library_header|library_header|assets|library_header|image", "w": 920, "h": 430, "localized": True},
    {"name": "Library Logo", "path": "library_logo|logo|assets|library_logo|image", "w": 1280, "h": 720, "localized": True},
    {"name": "Screenshot", "path": "screenshot|assets|screenshots|", "w": 1920, "h": 1080, "localized": False, "enforce_min": True},
]

# Map our generated filenames to the exact Steam type (so a 920x430 file can be
# either Header Capsule or Library Header, etc.).
FILENAME_OVERRIDES = {
    "header_capsule": "Header Capsule",
    "small_capsule": "Small Capsule",
    "main_capsule": "Main Capsule",
    "hero_capsule": "Vertical Capsule",
    "library_header": "Library Header",
    "library_hero": "Library Hero",
    "library_capsule": "Library Capsule",
    "library_logo": "Library Logo",
}

STORE_CAPSULES = (
    "header_capsule_920x430.png",
    "small_capsule_462x174.png",
    "main_capsule_1232x706.png",
    "hero_capsule_748x896.png",
)


def chrome_session() -> requests.Session:
    session = requests.Session()
    for cookie in browser_cookie3.chrome(domain_name="partner.steamgames.com"):
        session.cookies.set_cookie(cookie)
    if not session.cookies.get("sessionid"):
        raise SystemExit("No Steamworks sessionid in Chrome cookies. Log in at partner.steamgames.com first.")
    return session


def valid_type(width: int, height: int, spec: dict) -> bool:
    if spec.get("enforce_min"):
        return width >= spec["w"] and height >= spec["h"]
    return width == spec["w"] and height == spec["h"]


def spec_by_name(name: str) -> dict | None:
    return next((s for s in IMAGE_TYPES if s["name"] == name), None)


def determine_type(width: int, height: int, filename: str) -> dict | None:
    lower = filename.lower()
    for hint, name in FILENAME_OVERRIDES.items():
        if hint in lower:
            spec = spec_by_name(name)
            if spec and valid_type(width, height, spec):
                return spec
    for spec in IMAGE_TYPES:
        if valid_type(width, height, spec):
            return spec
    return None


def collect_assets(store_only: bool) -> list[Path]:
    if store_only:
        return [ASSETS / "capsules" / n for n in STORE_CAPSULES if (ASSETS / "capsules" / n).exists()]
    paths: list[Path] = []
    for folder in ("screenshots", "capsules"):
        paths.extend(sorted((ASSETS / folder).glob("*.png")))
    return paths


def build_form(paths: list[Path], sessionid: str) -> tuple[list[tuple], list[tuple], list[str]]:
    files: list[tuple] = []
    params: list[tuple] = []
    notes: list[str] = []
    screenshot_idx = 0

    for path in paths:
        with Image.open(path) as img:
            width, height = img.size
        spec = determine_type(width, height, path.name)
        if not spec:
            notes.append(f"skip (unknown size): {path.name} {width}x{height}")
            continue

        data = path.read_bytes()
        filename = path.name

        if spec["name"] == "Screenshot":
            key = f"{spec['path']}{screenshot_idx}|english[]"
            params.append((f"params[{filename}][all_ages]", "1"))
            filename = f"{path.stem}.AA1{path.suffix}"
            screenshot_idx += 1
        elif spec.get("localized"):
            key = f"{spec['path']}|{LANG}"
        else:
            key = spec["path"]

        files.append((key, (filename, data, "image/png")))
        notes.append(f"upload: {path.name} -> {spec['name']} key={key}")

    form: list[tuple] = [("sessionid", sessionid), *params]
    return form, files, notes


def main() -> int:
    store_only = "--store-only" in sys.argv
    paths = collect_assets(store_only=store_only)
    if not paths:
        print("No assets found.", file=sys.stderr)
        return 1

    session = chrome_session()
    sessionid = session.cookies.get("sessionid")
    session.headers.update(
        {
            "Referer": f"https://partner.steamgames.com/admin/game/edit/{ITEM_ID}?activetab=tab_graphicalassets",
            "Origin": "https://partner.steamgames.com",
            "X-Requested-With": "XMLHttpRequest",
        }
    )
    form, files, notes = build_form(paths, sessionid)
    for line in notes:
        print(line)

    resp = session.post(SAVE_URL, data=form, files=files, timeout=180)
    print("status", resp.status_code)
    try:
        print(json.dumps(resp.json(), indent=2)[:2000])
    except json.JSONDecodeError:
        print(resp.text.strip()[:500])
    return 0 if resp.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
