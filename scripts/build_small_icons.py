#!/usr/bin/env python3
"""Build Media/Small/: 32x32 copies of every Media/Icon-*.tga and Media/ClassCrest-*.tga.

Loose TGAs get no mipmaps in the client, and asking for them (SetTexture filterMode "TRILINEAR")
crashes it, so a 64-128 px file drawn at 16-24 px aliases. The addon swaps in these pre-shrunk
copies for small draws (IconRegistry SmallIconFile, ApplyClassIconTexture). Rerun after any icon change.
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"
OUT = MEDIA / "Small"
SIZE = 32


def shrink(src: Path) -> None:
    # Resample with premultiplied alpha so transparent edges do not pull in dark fringes.
    img = Image.open(src).convert("RGBA").convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    out = OUT / src.name
    # Write beside the target, then rename: the addon folder is live in the game, which must never read a half-written file.
    tmp = out.with_name(out.name + ".tmp")
    img.save(tmp, format="TGA")
    os.replace(tmp, out)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    sources = sorted(MEDIA.glob("Icon-*.tga")) + sorted(MEDIA.glob("ClassCrest-*.tga"))
    for src in sources:
        shrink(src)
    print(f"wrote {len(sources)} files to {OUT.relative_to(ROOT)}")
