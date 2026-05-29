#!/usr/bin/env python3
"""Upload store assets to Steamworks using Chrome session cookies."""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path

import browser_cookie3
import requests
from PIL import Image

ASSETS = Path(__file__).resolve().parent / "assets"
ITEM_ID = 1202304
SAVE_URL = f"https://partner.steamgames.com/admin/game/save/{ITEM_ID}?activetab=tab_graphicalassets&json=1"

IMAGE_TYPES = [
    {"name": "Small Capsule", "path": "small_capsule|capsule|assets|small_capsule|image", "w": 462, "h": 174},
    {"name": "Main Capsule", "path": "main_capsule|capsule_616x353|assets|main_capsule|image", "w": 1232, "h": 706},
    {"name": "Package Header", "path": "header_image|header|assets|header_image|image", "w": 1414, "h": 464},
    {"name": "Vertical Capsule", "path": "hero_capsule|hero_capsule|assets|hero_capsule|image", "w": 748, "h": 896},
    {"name": "Library Hero", "path": "library_hero|library_hero|assets|library_hero|image", "w": 3840, "h": 1240},
    {"name": "Library Capsule", "path": "library_capsule|library_capsule|assets|library_capsule|image", "w": 600, "h": 900},
    {"name": "Library Header", "path": "library_header|library_header|assets|library_header|image", "w": 920, "h": 430},
    {"name": "Library Logo", "path": "library_logo|logo|assets|library_logo|image", "w": 1280, "h": 720},
    {"name": "Screenshot", "path": "screenshot|assets|screenshots|", "w": 1920, "h": 1080, "enforce_min": True},
]


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


FILENAME_OVERRIDES = {
    "package_header": "Package Header",
    "hero_capsule": "Vertical Capsule",
    "library_header": "Library Header",
    "library_hero": "Library Hero",
    "library_logo": "Library Logo",
    "library_capsule": "Library Capsule",
    "main_capsule": "Main Capsule",
    "small_capsule": "Small Capsule",
}


def determine_type(width: int, height: int, filename: str) -> dict | None:
    lower = filename.lower()
    for hint, name in FILENAME_OVERRIDES.items():
        if hint in lower:
            for spec in IMAGE_TYPES:
                if spec["name"] == name and valid_type(width, height, spec):
                    return spec
    for spec in IMAGE_TYPES:
        if spec["w"] and not valid_type(width, height, spec):
            continue
        return spec
    return None


def collect_assets() -> list[Path]:
    paths: list[Path] = []
    for folder in ("screenshots", "capsules"):
        paths.extend(sorted((ASSETS / folder).glob("*.png")))
    return paths


def build_form(paths: list[Path], sessionid: str) -> tuple[list[tuple], list[str]]:
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
            ext = path.suffix
            stem = path.stem
            filename = f"{stem}.AA1{ext}"
            screenshot_idx += 1
        else:
            key = spec["path"]

        files.append((key, (filename, data, "image/png")))
        notes.append(f"upload: {path.name} -> {spec['name']} key={key}")

    form: list[tuple] = [("sessionid", sessionid), *params]
    return form, files, notes


def main() -> int:
    paths = collect_assets()
    if not paths:
        print("No assets found.", file=sys.stderr)
        return 1

    session = chrome_session()
    sessionid = session.cookies.get("sessionid")
    form, files, notes = build_form(paths, sessionid)
    for line in notes:
        print(line)

    resp = session.post(SAVE_URL, data=form, files=files, timeout=120)
    print("status", resp.status_code)
    text = resp.text.strip()
    try:
        payload = resp.json()
        print(json.dumps(payload, indent=2)[:2000])
    except json.JSONDecodeError:
        print(text[:500])
    return 0 if resp.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
