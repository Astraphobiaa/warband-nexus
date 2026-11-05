#!/usr/bin/env python3
"""Build pre-shrunk copies of every shipped icon under Media/Small16|Small|Small64|Small128.

Loose TGAs get no mipmaps in the client, and asking for them (SetTexture filterMode "TRILINEAR")
crashes it, so a 64-256 px file drawn at 12-24 px aliases. The addon swaps in the smallest pre-shrunk
copy that still covers the draw (IconRegistry PickIconFile). Upscaling from a copy that is too small
reads blurry; downscaling more than 2x without mipmaps shimmers -- hence one tier per power of two.
Money/line-height markup draws at 12-14 UI units (~16-22 physical px), which is why 16 px exists.
Rerun after any icon change.
"""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"

# Physical-pixel tier -> folder under Media/. "Small" keeps its historical name for the 32 px tier.
TIERS = {16: "Small16", 32: "Small", 64: "Small64", 128: "Small128"}


def shrink(src: Path, out_dir: Path, size: int) -> None:
    # Resample with premultiplied alpha so transparent edges do not pull in dark fringes.
    img = Image.open(src).convert("RGBA").convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    out = out_dir / src.name
    # Write beside the target, then rename: the addon folder is live in the game, which must never read a half-written file.
    tmp = out.with_name(out.name + ".tmp")
    img.save(tmp, format="TGA", compression=None)
    os.replace(tmp, out)


if __name__ == "__main__":
    # icon.tga is the addon logo: it draws at 18-24 px in the title bar, minimap and tracker header,
    # and shipped only as a 256 px RLE TGA it aliased hard at those sizes.
    sources = sorted(MEDIA.glob("Icon-*.tga")) + sorted(MEDIA.glob("ClassCrest-*.tga")) + [
        MEDIA / "icon.tga", MEDIA / "patreon.tga", MEDIA / "discord.tga",
    ]
    written = 0
    for size, folder in sorted(TIERS.items()):
        out_dir = MEDIA / folder
        out_dir.mkdir(exist_ok=True)
        for src in sources:
            if not src.exists():
                continue
            with Image.open(src) as probe:
                if probe.width <= size:
                    continue  # never upscale: a tier larger than the source is dead weight
            shrink(src, out_dir, size)
            written += 1
    print(f"wrote {written} files across {', '.join(TIERS.values())}")
