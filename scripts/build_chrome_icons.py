#!/usr/bin/env python3
"""Build header chrome icons: SVG source + 64x64 RGBA TGA for WoW (stroke style)."""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"
SIZE = 64
STROKE = 5
COLOR = (255, 255, 255, 255)


def blank() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def save_pair(name: str, img: Image.Image, svg_body: str) -> None:
    tga_path = MEDIA / f"Icon-{name}.tga"
    svg_path = MEDIA / f"Icon-{name}.svg"
    img.save(tga_path, format="TGA")
    svg_path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none" stroke="#FFFFFF" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round">\n{svg_body}\n</svg>\n',
        encoding="utf-8",
    )
    print(f"wrote {tga_path.name} + {svg_path.name}")


def draw_close() -> tuple[Image.Image, str]:
    im = blank()
    d = ImageDraw.Draw(im)
    pad = 14
    d.line((pad, pad, SIZE - pad, SIZE - pad), fill=COLOR, width=STROKE)
    d.line((SIZE - pad, pad, pad, SIZE - pad), fill=COLOR, width=STROKE)
    svg = f'  <line x1="{pad}" y1="{pad}" x2="{SIZE-pad}" y2="{SIZE-pad}"/>\n  <line x1="{SIZE-pad}" y1="{pad}" x2="{pad}" y2="{SIZE-pad}"/>'
    return im, svg


def draw_discord() -> tuple[Image.Image, str]:
    im = blank()
    d = ImageDraw.Draw(im)
    cx, cy = 32, 34
    d.ellipse((cx - 14, cy - 10, cx + 14, cy + 12), outline=COLOR, width=STROKE)
    d.ellipse((cx - 9, cy - 2, cx - 3, cy + 4), fill=COLOR)
    d.ellipse((cx + 3, cy - 2, cx + 9, cy + 4), fill=COLOR)
    svg = (
        f'  <ellipse cx="{cx}" cy="{cy}" rx="14" ry="11"/>\n'
        f'  <circle cx="{cx-6}" cy="{cy+1}" r="3" fill="#FFFFFF" stroke="none"/>\n'
        f'  <circle cx="{cx+6}" cy="{cy+1}" r="3" fill="#FFFFFF" stroke="none"/>'
    )
    return im, svg


def draw_donate() -> tuple[Image.Image, str]:
    im = blank()
    d = ImageDraw.Draw(im)
    cx, cy = 32, 34
    d.polygon(
        [
            (cx, cy + 12),
            (cx - 12, cy - 2),
            (cx - 6, cy - 10),
            (cx, cy - 4),
            (cx + 6, cy - 10),
            (cx + 12, cy - 2),
        ],
        outline=COLOR,
        width=STROKE,
    )
    svg = (
        f'  <path d="M{cx},{cy+12} L{cx-12},{cy-2} L{cx-6},{cy-10} L{cx},{cy-4} L{cx+6},{cy-10} L{cx+12},{cy-2} Z"/>'
    )
    return im, svg


def draw_credits() -> tuple[Image.Image, str]:
    im = blank()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((16, 14, 48, 50), radius=4, outline=COLOR, width=STROKE)
    d.line((32, 20, 32, 44), fill=COLOR, width=STROKE)
    d.line((22, 28, 42, 28), fill=COLOR, width=STROKE)
    d.line((22, 36, 42, 36), fill=COLOR, width=STROKE)
    svg = (
        '  <rect x="16" y="14" width="32" height="36" rx="4"/>\n'
        '  <line x1="32" y1="20" x2="32" y2="44"/>\n'
        '  <line x1="22" y1="28" x2="42" y2="28"/>\n'
        '  <line x1="22" y1="36" x2="42" y2="36"/>'
    )
    return im, svg


def draw_tracking() -> tuple[Image.Image, str]:
    im = blank()
    d = ImageDraw.Draw(im)
    cx, cy = 32, 32
    d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), outline=COLOR, width=STROKE)
    d.ellipse((cx - 6, cy - 6, cx + 6, cy + 6), outline=COLOR, width=STROKE)
    d.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=COLOR)
    d.line((cx, cy - 20, cx, cy - 8), fill=COLOR, width=STROKE)
    svg = (
        f'  <circle cx="{cx}" cy="{cy}" r="16"/>\n'
        f'  <circle cx="{cx}" cy="{cy}" r="6"/>\n'
        f'  <circle cx="{cx}" cy="{cy}" r="2" fill="#FFFFFF" stroke="none"/>\n'
        f'  <line x1="{cx}" y1="12" x2="{cx}" y2="24"/>'
    )
    return im, svg


def main() -> None:
    MEDIA.mkdir(parents=True, exist_ok=True)
    icons = {
        "Close": draw_close,
        "Discord": draw_discord,
        "Donate": draw_donate,
        "Credits": draw_credits,
        "Tracking": draw_tracking,
    }
    for name, fn in icons.items():
        img, svg = fn()
        save_pair(name, img, svg)


if __name__ == "__main__":
    main()
