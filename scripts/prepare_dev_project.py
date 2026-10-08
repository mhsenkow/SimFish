#!/usr/bin/env python3
"""Make an isolated Godot config without copying large assets or editing the game."""
import json
import re
import sys
from pathlib import Path


def isolated_config(text: str, name: str) -> str:
    lines = text.splitlines()
    result = []
    section = ""
    for line in lines:
        match = re.fullmatch(r"\s*\[([^]]+)\]\s*", line)
        if match:
            section = match[1]
        if section == "application" and re.match(
            r"\s*config/(use_custom_user_dir|custom_user_dir_name)\s*=", line
        ):
            continue
        result.append(line)
        if match and section == "application":
            result.extend([
                "config/use_custom_user_dir=true",
                "config/custom_user_dir_name=" + json.dumps(name),
            ])
    return "\n".join(result) + "\n"


def main() -> None:
    source, destination = map(Path, sys.argv[1:3])
    name = sys.argv[3]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name) or name == "walstad loom":
        raise SystemExit("Scratch user directory must be a simple, distinct name")
    for child in source.iterdir():
        target = destination / child.name
        if child.name in ("project.godot", "override.cfg"):
            target.write_text(isolated_config(child.read_text(), name))
        else:
            target.symlink_to(child.resolve(), target_is_directory=child.is_dir())


if __name__ == "__main__":
    main()
