#!/usr/bin/env python3
"""Generate dark-mode variants for SVG diagrams under ``docs/images``."""

from __future__ import annotations

import re
import sys
from pathlib import Path

IMAGES_DIR = Path(__file__).resolve().parent.parent / "images"

SWAPS: list[tuple[str, str]] = [
    ("#ffffff", "#1e1e26"),
    ("#fafafb", "#1e1e26"),
    ("#f5f5f5", "#2a2a30"),
    ("#f8cecc", "#5a2e2c"),
    ("#b85450", "#e88a85"),
    ("#d5e8d4", "#2c4a2a"),
    ("#82b366", "#9ad075"),
    ("#dae8fc", "#283a55"),
    ("#6c8ebf", "#8aaee0"),
    ("#fff2cc", "#4a3e15"),
    ("#d6b656", "#e0c870"),
    ("#e1d5e7", "#3a2d4a"),
    ("#9673a6", "#b894c8"),
    ("#ffe6cc", "#4a3618"),
    ("#d79b00", "#e8b440"),
    ("#1e1e26", "#e6e6ec"),
    ("#222222", "#e6e6ec"),
    ("#333333", "#d0d0d6"),
    ("#666666", "#aaaaaa"),
    ("#999999", "#8a909a"),
    ("#cccccc", "#666666"),
]


def darken(svg: str) -> str:
    """Apply a deterministic light-to-dark palette swap."""
    out = svg
    for light, dark in SWAPS:
        pattern = re.compile(re.escape(light) + r"(?![0-9a-fA-F])", re.IGNORECASE)
        out = pattern.sub(dark, out)
    return out.replace("color-scheme: light", "color-scheme: dark")


def main() -> int:
    if not IMAGES_DIR.exists():
        print(f"images dir not found: {IMAGES_DIR}", file=sys.stderr)
        return 1

    light_svgs = sorted(
        path for path in IMAGES_DIR.glob("*.svg") if not path.stem.endswith("-dark")
    )
    if not light_svgs:
        print("no light SVGs found", file=sys.stderr)
        return 1

    for light_path in light_svgs:
        dark_path = light_path.with_name(f"{light_path.stem}-dark.svg")
        dark_path.write_text(darken(light_path.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"wrote {dark_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
