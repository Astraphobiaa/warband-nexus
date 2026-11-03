#!/usr/bin/env python3
"""Build the class crests: one 128x128 RGBA TGA per class and variant.

Media/ClassCrest-<CLASS>.tga       crest with the class-colored ring
Media/ClassCrest-<CLASS>-Bare.tga  crest art only

<CLASS> is the upper-case classFile (DEATHKNIGHT). One small file per crest, not a 512 px atlas:
the shipped addon only ever used textures up to 256 px, and the client crashed drawing the atlas.
Keep CLASS_ORDER in sync with CLASS_CREST in Modules/UI/SharedWidgets_Icons.lua.
Sources: scripts/assets/class_icons/<class>_ring.png and <class>.png (512 px, transparent).
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "scripts" / "assets" / "class_icons"
MEDIA = ROOT / "Media"
SIZE = 128

CLASS_ORDER = [
    "warrior", "paladin", "hunter", "rogue",
    "priest", "deathknight", "shaman", "mage",
    "warlock", "monk", "druid", "demonhunter",
    "evoker",
]


def build(suffix: str, file_suffix: str) -> None:
    for key in CLASS_ORDER:
        img = Image.open(SRC / f"{key}{suffix}.png").convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
        out = MEDIA / f"ClassCrest-{key.upper()}{file_suffix}.tga"
        # Write beside the target, then rename: the addon folder is live in the game, which must never read a half-written file.
        tmp = out.with_name(out.name + ".tmp")
        img.save(tmp, format="TGA")
        os.replace(tmp, out)
        print(f"wrote {out.name}")


if __name__ == "__main__":
    build("_ring", "")
    build("", "-Bare")
