#!/usr/bin/env python3
"""Build the class crest atlases: two 512x512 RGBA TGAs, 4x4 grid of 128 px cells.

Media/ClassIcons.tga      crest with the class-colored ring
Media/ClassIconsBare.tga  crest art only

Cell index = classID - 1, row-major (WARRIOR top-left ... EVOKER on row 4, column 1).
Keep CLASS_ORDER in sync with CLASS_ICON_CELL in Modules/UI/SharedWidgets_Icons.lua.
Sources: scripts/assets/class_icons/<class>_ring.png and <class>.png (512 px, transparent).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "assets" / "class_icons"
MEDIA = ROOT / "Media"
ATLAS = 512
CELL = 128
COLS = ATLAS // CELL

CLASS_ORDER = [
    "warrior", "paladin", "hunter", "rogue",
    "priest", "deathknight", "shaman", "mage",
    "warlock", "monk", "druid", "demonhunter",
    "evoker",
]


def build(suffix: str, out_name: str) -> None:
    atlas = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    for i, key in enumerate(CLASS_ORDER):
        cell = Image.open(SRC / f"{key}{suffix}.png").convert("RGBA").resize((CELL, CELL), Image.LANCZOS)
        atlas.paste(cell, ((i % COLS) * CELL, (i // COLS) * CELL))
    out = MEDIA / out_name
    atlas.save(out, format="TGA")
    print(f"wrote {out.name}")


if __name__ == "__main__":
    build("_ring", "ClassIcons.tga")
    build("", "ClassIconsBare.tga")
