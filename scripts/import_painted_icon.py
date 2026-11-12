#!/usr/bin/env python3
"""Turn a painted icon master (PNG, flat background) into a Media/Icon-<Name>.tga.

The set's best art is painted by an image model at 1024 px and kept outside the repo; only the
64 px TGA ships. This is the step in between: cut the flat backdrop away, trim to the subject,
square it up with a little breathing room, and resample down.

The backdrop is removed by flooding in from the four corners rather than by thresholding the whole
image, because the icons themselves carry near-black outlines that a global threshold would eat.

Usage: python scripts/import_painted_icon.py <master.png> <Name> [<master.png> <Name> ...]
Then:  python scripts/build_small_icons.py
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"

OUT = 64
SENTINEL = (255, 0, 255)
# Generous enough to take the backdrop's gradient and compression noise, tight enough to stop at
# the icon's outline: the measured backdrop sits around (32,29,32) and the outlines are darker and
# far more saturated than the few units of drift across the plate.
THRESH = 52
MARGIN = 0.012          # share of the square left empty around the subject
# A single 1024 -> 64 jump throws away most of the structure: halving repeatedly keeps it, and a
# light unsharp afterwards puts back the bite the resampling takes off. Without both, the icon
# reads soft beside the hand-painted set, which is drawn for this size to begin with.
UNSHARP = (1.0, 115, 3)  # radius, percent, threshold


def cut_background(img: Image.Image) -> Image.Image:
    rgb = img.convert("RGB")
    work = rgb.copy()
    w, h = work.size
    seeds = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2),
             (w // 2, 1), (w // 2, h - 2), (1, h // 2), (w - 2, h // 2)]
    for seed in seeds:
        ImageDraw.floodfill(work, seed, SENTINEL, thresh=THRESH)

    alpha = Image.new("L", work.size, 255)
    wp, ap = work.load(), alpha.load()
    for y in range(h):
        for x in range(w):
            if wp[x, y] == SENTINEL:
                ap[x, y] = 0

    # Pull the edge in by a hair and soften it: the flood leaves a ring of half-backdrop pixels
    # that reads as a grey halo once the icon is 16 px wide.
    alpha = alpha.filter(ImageFilter.MinFilter(5))
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def square(img: Image.Image) -> Image.Image:
    box = img.getchannel("A").getbbox()
    if box:
        img = img.crop(box)
    side = int(max(img.size) * (1 + MARGIN * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas


def downsample(img: Image.Image, target: int) -> Image.Image:
    """Halve repeatedly to the target, premultiplied so transparent edges pull no dark fringe."""
    work = img.convert("RGBa")
    while work.width // 2 > target:
        work = work.resize((work.width // 2, work.height // 2), Image.LANCZOS)
    work = work.resize((target, target), Image.LANCZOS)
    out = work.convert("RGBA")
    return out.filter(ImageFilter.UnsharpMask(*UNSHARP))


def convert(master: Path, name: str) -> None:
    img = downsample(square(cut_background(Image.open(master))), OUT)
    path = MEDIA / ("Icon-%s.tga" % name)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="TGA", compression=None)
    print("wrote %s (%dx%d) from %s" % (path.relative_to(ROOT), OUT, OUT, master.name))


def main(argv: list[str]) -> int:
    if len(argv) < 2 or len(argv) % 2:
        print(__doc__)
        return 2
    for i in range(0, len(argv), 2):
        convert(Path(argv[i]), argv[i + 1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
