#!/usr/bin/env python3
"""Build the semantic UI icon set: SVG source + 64x64 RGBA TGA per icon under Media/.

Two families, both drawn on a 24-unit grid:
- mono:    white 2-unit round strokes / fills, tinted in game (theme vertex or caller color).
- colored: flat fills with a dark outline so yellow / gold stays readable on light and dark UI.

Requires the `resvg` CLI (brew install resvg) for rasterizing. Run: python3 scripts/build_ui_icons.py
Keys -> files are wired in Modules/UI/IconRegistry.lua (ns.UI_ICONS).
"""
from __future__ import annotations

import math
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"
SIZE = 64

OUTLINE = "#1B130B"
OUTLINE_W = 3.2  # stroke drawn under the fill: 1.6 units show outside the shape
MONO_HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" '
             'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">')
COLOR_HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
              'stroke-linecap="round" stroke-linejoin="round">')

COIN = {
    "Gold": ("#F7C948", "#D69E1E", "#FFE59A"),
    "Silver": ("#D9DEE4", "#A9B2BC", "#F4F6F8"),
    "Copper": ("#DE8E52", "#B4663A", "#F3B888"),
}


def n(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def outlined(d: str, fill: str, extra: str = "") -> str:
    """Path drawn twice: dark outline stroke underneath, flat fill on top."""
    return (f'<path d="{d}" fill="{OUTLINE}" stroke="{OUTLINE}" stroke-width="{OUTLINE_W}"{extra}/>'
            f'<path d="{d}" fill="{fill}" stroke="{fill}" stroke-width="0.6"{extra}/>')


def outlined_stroke(d: str, color: str, width: float) -> str:
    """Stroke glyph (check, x) with a dark rim around it."""
    return (f'<path d="{d}" stroke="{OUTLINE}" stroke-width="{n(width + OUTLINE_W)}"/>'
            f'<path d="{d}" stroke="{color}" stroke-width="{n(width)}"/>')


def star_path(cx: float = 12, cy: float = 12.7, r_out: float = 10, r_in: float = 4.3) -> str:
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = r_out if i % 2 == 0 else r_in
        pts.append(f"{n(cx + r * math.cos(a))} {n(cy + r * math.sin(a))}")
    return "M" + "L".join(pts) + "Z"


def gear_path(teeth: int = 8, r_out: float = 10, r_root: float = 7.6, half_top: float = 9.5, half_root: float = 17.5) -> str:
    pts = []
    for i in range(teeth):
        a = i * 360 / teeth
        for ang, r in ((a - half_root, r_root), (a - half_top, r_out), (a + half_top, r_out), (a + half_root, r_root)):
            t = math.radians(ang - 90)
            pts.append(f"{n(12 + r * math.cos(t))} {n(12 + r * math.sin(t))}")
    return "M" + "L".join(pts) + "Z"


# ---------------------------------------------------------------- colored

def coin_stack(cx: float, rx: float, ry: float, top: float, coins: int, h: float, tones: tuple[str, str, str]) -> str:
    face, side, light = tones
    parts = []
    # bottom coin first so each upper coin's outline sits on top of the one below it
    for k in reversed(range(coins)):
        y0, y1 = top + k * h, top + (k + 1) * h
        body = (f"M{n(cx - rx)} {n(y0)}V{n(y1)}A{n(rx)} {n(ry)} 0 0 0 {n(cx + rx)} {n(y1)}V{n(y0)}"
                f"A{n(rx)} {n(ry)} 0 0 1 {n(cx - rx)} {n(y0)}Z")
        parts.append(outlined(body, side))
    face_d = (f"M{n(cx - rx)} {n(top)}A{n(rx)} {n(ry)} 0 0 1 {n(cx + rx)} {n(top)}"
              f"A{n(rx)} {n(ry)} 0 0 1 {n(cx - rx)} {n(top)}Z")
    parts.append(outlined(face_d, face))
    parts.append(f'<ellipse cx="{n(cx)}" cy="{n(top - ry * 0.25)}" rx="{n(rx * 0.55)}" ry="{n(ry * 0.38)}" fill="{light}"/>')
    return "".join(parts)


def coins(tones: tuple[str, str, str]) -> str:
    back = coin_stack(9.0, 6.4, 2.4, 4.4, 4, 3.3, tones)
    front = coin_stack(16.6, 5.4, 2.1, 13.2, 2, 3.2, tones)
    # scaled into the 24 grid so the outline keeps a ~1.5 unit margin on every side
    return f'<g transform="translate(1.2 1.2) scale(0.9)">{back}{front}</g>'


def favorite_on() -> str:
    # one flat tone per half: lighter left half, split on the vertical axis (no offset highlight)
    d = star_path()
    return (f'<clipPath id="half"><rect x="0" y="0" width="12" height="24"/></clipPath>'
            + outlined(d, "#F2B935")
            + f'<path d="{d}" fill="#FFD866" stroke="#FFD866" stroke-width="0.6" clip-path="url(#half)"/>')


def favorite_off() -> str:
    # same outer silhouette as favorite_on (toggling never changes size); a concentric star hole with a dark rim
    d = star_path()
    hole = star_path(12, 12.7, 6.2, 2.67)
    return ('<mask id="hole" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">'
            '<rect width="24" height="24" fill="#fff"/>'
            f'<path d="{hole}" fill="#000" stroke="#000" stroke-width="0.6"/></mask>'
            f'<g mask="url(#hole)">{outlined(d, "#F2B935")}</g>'
            f'<path d="{hole}" stroke="{OUTLINE}" stroke-width="1.2"/>')


def status_ok() -> str:
    return outlined_stroke("M4.6 12.6L9.6 17.4L19.4 6.8", "#41C95E", 3)


def check_minimal() -> str:
    return outlined_stroke("M5.4 12.8L9.8 16.8L18.6 7.4", "#41C95E", 2)


def status_fail() -> str:
    return outlined_stroke("M6.5 6.5L17.5 17.5M17.5 6.5L6.5 17.5", "#E5483C", 3)


def status_warn() -> str:
    return outlined_stroke("M6.5 6.5L17.5 17.5M17.5 6.5L6.5 17.5", "#F2C230", 3)


def warning() -> str:
    tri = "M12 2.8L22 20.4H2Z"
    return (outlined(tri, "#F2B630", ' stroke-linejoin="round"')
            + f'<path d="M12 9V14" stroke="{OUTLINE}" stroke-width="2.4"/>'
            + f'<circle cx="12" cy="17.2" r="1.35" fill="{OUTLINE}"/>')


def attention() -> str:
    return (f'<circle cx="12" cy="12" r="10.4" fill="{OUTLINE}"/><circle cx="12" cy="12" r="8.8" fill="#F7C948"/>'
            f'<path d="M12 6.6V13.2" stroke="{OUTLINE}" stroke-width="2.6"/>'
            f'<circle cx="12" cy="16.9" r="1.5" fill="{OUTLINE}"/>')


# ---------------------------------------------------------------- mono

def triangle_down() -> str:
    return '<path d="M5.5 8.5H18.5L12 16.5Z" fill="#FFFFFF"/>'


def triangle_left() -> str:
    return '<path d="M15.5 5.5V18.5L7.5 12Z" fill="#FFFFFF"/>'


def triangle_right() -> str:
    return '<path d="M8.5 5.5V18.5L16.5 12Z" fill="#FFFFFF"/>'


def status_pending() -> str:
    return '<circle cx="12" cy="12" r="4" fill="#FFFFFF" stroke="none"/>'


def clock() -> str:
    return '<circle cx="12" cy="12" r="9.5"/><path d="M12 6.8V12L15.6 14.2"/>'


def lock() -> str:
    return ('<rect x="4.5" y="10.5" width="15" height="11" rx="2.4"/>'
            '<path d="M8 10.5V7.2a4 4 0 0 1 8 0V10.5"/><path d="M12 14.6V17.2"/>')


def plus() -> str:
    return '<path d="M12 5V19M5 12H19"/>'


def minus() -> str:
    return '<path d="M5 12H19"/>'


def settings() -> str:
    return f'<path d="{gear_path()}"/><circle cx="12" cy="12" r="3"/>'


def filter_icon() -> str:
    return '<path d="M3.5 5H20.5L14 12.6V19L10 20.5V12.6Z"/>'


def sound() -> str:
    return ('<path d="M4 9.5H7.5L12 5.5V18.5L7.5 14.5H4Z"/>'
            '<path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18.2 6.5a7.5 7.5 0 0 1 0 11"/>')


def spinner() -> str:
    return '<path d="M12 3a9 9 0 1 1 -9 9"/>'


def reset() -> str:
    return '<path d="M4.5 12a7.5 7.5 0 1 0 2.2 -5.3"/><path d="M4.5 3.8V8.2H8.9"/>'


def upgrade() -> str:
    return '<path d="M12 4L19.5 12H15V20H9V12H4.5Z" fill="#FFFFFF"/>'


def crafting_order() -> str:
    # hammer: square head on a diagonal handle
    return ('<path d="M10.6 13.4L4.4 19.6"/>'
            '<path d="M11.2 5.2L18.8 12.8L15.9 15.7L8.3 8.1Z" fill="#FFFFFF"/>')


def warband() -> str:
    # banner on a pole with a forked tail
    return ('<path d="M6 21V3"/>'
            '<path d="M6 4H18.5L15.6 8.5L18.5 13H6" fill="#FFFFFF"/>')


ICONS = {
    # name: (builder, colored)
    "TriangleDown": (triangle_down, False),
    "TriangleLeft": (triangle_left, False),
    "TriangleRight": (triangle_right, False),
    "StatusOk": (status_ok, True),
    "StatusFail": (status_fail, True),
    "StatusWarn": (status_warn, True),
    "StatusPending": (status_pending, False),
    "CheckMinimal": (check_minimal, True),
    "FavoriteOn": (favorite_on, True),
    "FavoriteOff": (favorite_off, True),
    "CoinGold": (lambda: coins(COIN["Gold"]), True),
    "CoinSilver": (lambda: coins(COIN["Silver"]), True),
    "CoinCopper": (lambda: coins(COIN["Copper"]), True),
    "Clock": (clock, False),
    "Lock": (lock, False),
    "Warning": (warning, True),
    "Attention": (attention, True),
    "Plus": (plus, False),
    "Minus": (minus, False),
    "Settings": (settings, False),
    "Filter": (filter_icon, False),
    "Sound": (sound, False),
    "Spinner": (spinner, False),
    "Reset": (reset, False),
    "Upgrade": (upgrade, False),
    "CraftingOrder": (crafting_order, False),
    "Warband": (warband, False),
}


def render(name: str, svg: str) -> None:
    svg_path = MEDIA / f"Icon-{name}.svg"
    svg_path.write_text(svg, encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "icon.png"
        subprocess.run(["resvg", "-w", str(SIZE), "-h", str(SIZE), str(svg_path), str(png)], check=True)
        Image.open(png).convert("RGBA").save(MEDIA / f"Icon-{name}.tga", format="TGA")
    print(f"wrote Icon-{name}.tga + .svg")


if __name__ == "__main__":
    for name, (build, colored) in ICONS.items():
        head = COLOR_HEAD if colored else MONO_HEAD
        render(name, head + build() + "</svg>\n")
