#!/usr/bin/env python3
"""Build the semantic UI icon set: SVG source + 64x64 RGBA TGA per icon under Media/.

Two families, both drawn on a 24-unit grid:
- glyphs:  2-unit round strokes / fills. The SVG is the white shape; names in GLYPH_COLOR ship as
           colored TGAs (fill lit from the top inside a thin dark rim). Others ship white (mono).
- colored: flat fills with a dark outline so yellow / gold stays readable on light and dark UI.

Requires the `resvg` CLI (brew install resvg) for rasterizing. Run: python3 scripts/build_ui_icons.py [Name ...]
Keys -> files are wired in Modules/UI/IconRegistry.lua (ns.UI_ICONS).
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "Media"
SIZE = 64
# Painted with Z-Image Turbo (512 px masters kept outside the repo); never overwrite these TGAs from SVG.
PAINTED = {"FactionPortraits", "WowBag34", "WowBox", "Handshake", "Checklist", "Currency", "CrossedSwords", "BarChart", "AnvilHammer", "BossSkull", "HorseHead", "PlateArmor", "Info", "GearGold", "MoneySacks", "Tabard", "Campfire", "WowLootChest", "RolledScroll", "DrawstringSack", "Paw", "Trophy", "Calendar", "Present", "TarotCards", "Spyglass", "RedQuestion", "Sparkle", "GoldPin", "Cart", "Tent", "Spellbook", "TalentTree"}

OUTLINE = "#1B130B"
OUTLINE_RGB = (0x1B, 0x13, 0x0B)
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


# settings category rail
def modules() -> str:
    return ''.join(f'<rect x="{x}" y="{y}" width="7" height="7" rx="1.6"/>' for y in (3.5, 13.5) for x in (3.5, 13.5))


def keyboard() -> str:
    return ('<rect x="2.5" y="5.5" width="19" height="13" rx="2.4"/>'
            '<path d="M7 9.5h.01M10.3 9.5h.01M13.7 9.5h.01M17 9.5h.01" stroke-width="2.4"/>'
            '<path d="M8 14.5H16"/>')


def bell_line() -> str:
    return '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.8 2H4.2Z"/><path d="M10 20.8a2.2 2.2 0 0 0 4 0"/><path d="M12 3.2V5"/>'


def palette() -> str:
    return ('<path d="M12 3a9 9 0 1 0 0 18c1.4 0 2.1-1 1.6-2.2-.6-1.3.1-2.6 1.6-2.6H18a3 3 0 0 0 3-3C21 7.1 17 3 12 3Z"/>'
            '<circle cx="7.6" cy="11.4" r="1.1" fill="#FFFFFF"/><circle cx="10.2" cy="7.4" r="1.1" fill="#FFFFFF"/>'
            '<circle cx="15" cy="7.6" r="1.1" fill="#FFFFFF"/>')


def sliders() -> str:
    return ('<path d="M4 6.5H20M4 12H20M4 17.5H20" stroke-opacity="0.55"/>'
            '<circle cx="15.5" cy="6.5" r="2.3" fill="#FFFFFF"/><circle cx="8.5" cy="12" r="2.3" fill="#FFFFFF"/>'
            '<circle cx="13.5" cy="17.5" r="2.3" fill="#FFFFFF"/>')


# row / header chrome glyphs (one stroke for the whole set)
def close() -> str:
    return '<path d="M6 6L18 18M18 6L6 18"/>'


def chevron_up() -> str:
    return '<path d="M5.5 15L12 8.5L18.5 15"/>'


def chevron_down() -> str:
    return '<path d="M5.5 9L12 15.5L18.5 9"/>'


def pin() -> str:
    return ('<path d="M12 21.5c-3.8-4.2-6.8-7.6-6.8-11.6a6.8 6.8 0 0 1 13.6 0c0 4-3 7.4-6.8 11.6Z"/>'
            '<circle cx="12" cy="9.9" r="2.4"/>')


def link() -> str:
    # two chain links on the diagonal, overlapping in the middle
    return ('<g transform="rotate(-45 12 12)"><rect x="2" y="8.6" width="11.2" height="6.8" rx="3.4"/>'
            '<rect x="10.8" y="8.6" width="11.2" height="6.8" rx="3.4"/></g>')


def todo() -> str:
    return ('<path d="M3.8 6.2l1.5 1.5 2.7-2.9M3.8 12.2l1.5 1.5 2.7-2.9"/>'
            '<circle cx="5.6" cy="18" r="1.5"/><path d="M11.5 6.5H20M11.5 12.5H20M11.5 18H20"/>')


def reminder() -> str:
    # alarm clock: reads apart from the plain clock and the notification bell
    return ('<circle cx="12" cy="13" r="7.5"/><path d="M12 9.3V13l2.6 1.7"/>'
            '<path d="M3.8 6.2l3-2.6M20.2 6.2l-3-2.6"/>')


def block() -> str:
    return '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6L18.4 18.4"/>'


def tracking() -> str:
    return ('<circle cx="12" cy="12" r="7"/><path d="M12 2.5V6M12 18V21.5M2.5 12H6M18 12H21.5"/>'
            '<circle cx="12" cy="12" r="1.7" fill="#FFFFFF"/>')


def credits() -> str:
    return ('<circle cx="9" cy="8" r="3.3"/><path d="M3 20c0-3.5 2.7-6.2 6-6.2s6 2.7 6 6.2"/>'
            '<path d="M15.6 4.8a3.3 3.3 0 0 1 0 6.4"/><path d="M17.6 14.2c2 .8 3.4 3 3.4 5.8"/>')


def discord() -> str:
    # filled Clyde head (ears up, feet down) with the eyes cut out
    body = ("M8.7 5.3C7.2 5.5 5.8 6 4.6 6.7 2.9 9.4 2.4 12.9 2.7 16.3c1.5 1.2 3.1 2 4.7 2.5L8.6 17.1"
            "c2.2.5 4.6.5 6.8 0l1.2 1.7c1.6-.5 3.2-1.3 4.7-2.5.3-3.4-.2-6.9-1.9-9.6"
            "-1.2-.7-2.6-1.2-4.1-1.4l-.6 1.1c-1.8-.3-3.6-.3-5.4 0Z")
    return ('<mask id="de" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">'
            '<rect width="24" height="24" fill="#fff"/>'
            '<ellipse cx="9.1" cy="12.3" rx="1.6" ry="1.8" fill="#000"/>'
            '<ellipse cx="14.9" cy="12.3" rx="1.6" ry="1.8" fill="#000"/></mask>'
            f'<path d="{body}" fill="#FFFFFF" stroke-width="1" mask="url(#de)"/>')


def donate() -> str:
    return '<path d="M12 20.5S3.5 15.4 3.5 9.2A4.6 4.6 0 0 1 12 6.6a4.6 4.6 0 0 1 8.5 2.6c0 6.2-8.5 11.3-8.5 11.3Z"/>'


def warband() -> str:
    # banner on a pole with a forked tail
    return ('<path d="M6 21V3"/>'
            '<path d="M6 4H18.5L15.6 8.5L18.5 13H6" fill="#FFFFFF"/>')



# ---------------------------------------------------------------- category / header (mono)

def character() -> str:
    return '<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5V20a6 6 0 0 1 6-6h3a6 6 0 0 1 6 6v.5"/>'














def medal() -> str:
    return '<path d="M7.5 2.5L10.6 9M16.5 2.5L13.4 9"/><circle cx="12" cy="15" r="6"/><circle cx="12" cy="15" r="2.2"/>'




def crossed_swords() -> str:
    return ('<path d="M4 4L16 16M13.5 18.5L18.5 13.5M17.5 17.5L20.5 20.5"/>'
            '<path d="M20 4L8 16M5.5 13.5L10.5 18.5M6.5 17.5L3.5 20.5"/>')


def bar_chart() -> str:
    return '<path d="M3.5 20.5H20.5"/><path d="M7 16.5V11M12 16.5V5.5M17 16.5V8.5"/>'








def info() -> str:
    return '<circle cx="12" cy="12" r="9.5"/><path d="M12 11V16.5"/><path d="M12 7.6h.01"/>'






def scroll() -> str:
    return ('<path d="M8 3.5h10.5a2 2 0 0 1 0 4H8"/><path d="M8 3.5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V7.5"/>'
            '<path d="M9.5 11.5H15.5M9.5 15H13.5"/>')




def paw() -> str:
    return ('<ellipse cx="12" cy="15.5" rx="4.2" ry="3.7" fill="#FFFFFF" stroke="none"/>'
            '<circle cx="6.2" cy="10.4" r="1.9" fill="#FFFFFF" stroke="none"/><circle cx="9.6" cy="6.6" r="1.9" fill="#FFFFFF" stroke="none"/>'
            '<circle cx="14.4" cy="6.6" r="1.9" fill="#FFFFFF" stroke="none"/><circle cx="17.8" cy="10.4" r="1.9" fill="#FFFFFF" stroke="none"/>')


def trophy() -> str:
    return ('<path d="M7.5 3.5h9V9a4.5 4.5 0 0 1-9 0Z"/><path d="M7.5 5.5H5a3 3 0 0 0 3 4.4M16.5 5.5H19a3 3 0 0 1-3 4.4"/>'
            '<path d="M12 13.5V17M8 20.5h8M9.5 17h5"/>')


def calendar() -> str:
    return ('<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10H20.5"/>'
            '<path d="M8 3V7M16 3V7"/><path d="M8 14h.01M12 14h.01M16 14h.01M8 17.5h.01M12 17.5h.01"/>')


def gift() -> str:
    return ('<rect x="3" y="7.5" width="18" height="4" rx="1"/><path d="M4.5 11.5V20a1 1 0 0 0 1 1h13a1 1 0 0 0 1-1v-8.5"/>'
            '<path d="M12 7.5V21"/><path d="M12 7.5C10.5 4 7 3.8 7.4 5.9 7.7 7.5 12 7.5 12 7.5ZM12 7.5c1.5-3.5 5-3.7 4.6-1.6-.3 1.6-4.6 1.6-4.6 1.6Z"/>')


def cards() -> str:
    front = '<rect x="9.5" y="6" width="10" height="14" rx="1.6" transform="rotate(10 14.5 13)"/>'
    return ('<mask id="cf" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff"/>'
            '<rect x="9.5" y="6" width="10" height="14" rx="1.6" transform="rotate(10 14.5 13)" fill="#000" stroke="#000" stroke-width="4"/></mask>'
            '<rect x="4" y="4" width="10" height="14" rx="1.6" transform="rotate(-12 9 11)" mask="url(#cf)"/>' + front)




def compass() -> str:
    return '<circle cx="12" cy="12" r="9.5"/><path d="M15.6 8.4L13.6 13.6L8.4 15.6L10.4 10.4Z"/>'




def question() -> str:
    return ('<circle cx="12" cy="12" r="9.5"/><path d="M9.4 9.4a2.7 2.7 0 1 1 3.8 2.5c-.7.3-1.2 1-1.2 1.8v.6"/>'
            '<path d="M12 17.2h.01"/>')


def sparkle() -> str:
    return ('<path d="M10.5 3.5c.7 4.6 1.9 5.8 6.5 6.5-4.6.7-5.8 1.9-6.5 6.5-.7-4.6-1.9-5.8-6.5-6.5 4.6-.7 5.8-1.9 6.5-6.5Z"/>'
            '<path d="M18 14.5c.3 2 .9 2.7 3 3-2.1.3-2.7.9-3 3-.3-2.1-.9-2.7-3-3 2.1-.3 2.7-1 3-3Z"/>')



# ---------------------------------------------------------------- WoW-flavoured category glyphs (rev 2)

def backpack() -> str:
    return ('<path d="M6 9a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v10.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5Z"/>'
            '<path d="M10 5V4a2 2 0 0 1 4 0v1"/><path d="M6 11.5h12M12 11.5v2.5"/><rect x="8.5" y="15.5" width="7" height="3.5" rx="1"/>')


def supply_crate() -> str:
    # plank crate: outer boards, inner frame, X brace corner to corner
    return ('<rect x="3.5" y="3.5" width="17" height="17" rx="1.5"/><rect x="7" y="7" width="10" height="10" rx="0.4"/>'
            '<path d="M7 7L17 17M17 7L7 17"/>')


def treasure_map() -> str:
    return ('<path d="M3 6.2L9 3.8l6 2.4 6-2.4v14l-6 2.4-6-2.4-6 2.4Z"/><path d="M9 3.8v14M15 6.2v14"/>'
            '<path d="M16.6 10.4l2 2M18.6 10.4l-2 2"/><path d="M5.5 14.5c1.2-.8 2-.8 3.5 0"/>')


def emblem() -> str:
    return f'<circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="6.2"/><path d="{star_path(12, 12.4, 3.6, 1.5)}" fill="#FFFFFF" stroke="none"/>'


def skull() -> str:
    return ('<path d="M12 3a8 8 0 0 0-8 8c0 2.6 1.2 4.6 3 5.8V20.5h10v-3.7c1.8-1.2 3-3.2 3-5.8a8 8 0 0 0-8-8Z"/>'
            '<circle cx="8.9" cy="11.2" r="1.9" fill="#FFFFFF" stroke="none"/><circle cx="15.1" cy="11.2" r="1.9" fill="#FFFFFF" stroke="none"/>'
            '<path d="M10.5 20.5V18M13.5 20.5V18"/>')


def horseshoe() -> str:
    # solid band (arch open at the bottom, flared heels) with nail holes knocked out along its centre line
    band = ('M5.4 20.5H8.6L8.8 18.1C7.4 16.7 6.7 14.8 6.7 12.6 6.7 9 9 6.3 12 6.3S17.3 9 17.3 12.6C17.3 14.8 16.6 16.7 15.2 18.1L15.4 20.5H18.6'
            'L18.4 17.5C19.7 15.9 20.5 14.3 20.5 12.4 20.5 7.3 16.7 3.5 12 3.5S3.5 7.3 3.5 12.4C3.5 14.3 4.3 15.9 5.6 17.5Z')
    holes = "".join(f'<circle cx="{n(12 + 6.95 * math.cos(math.radians(a)))}" cy="{n(12.5 - 6.95 * math.sin(math.radians(a)))}" r="1" fill="#000" stroke="none"/>'
                    for a in (190, 140, 90, 40, -10))
    return ('<mask id="nails" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff"/>'
            f'{holes}</mask><path d="{band}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="1" mask="url(#nails)"/>')


def hammer_pick() -> str:
    return ('<path d="M4 20L13.2 10.8"/><path d="M11.6 7.4L14.6 4.4L19.6 9.4L16.6 12.4Z" fill="#FFFFFF"/>'
            '<path d="M20 20L7 7"/><path d="M3.5 10.5C4 6.6 6.6 4 10.5 3.5"/>')


def helmet() -> str:
    return ('<path d="M5 13a7 7 0 0 1 14 0v5.5a1.5 1.5 0 0 1-1.5 1.5H14v-4h-4v4H6.5A1.5 1.5 0 0 1 5 18.5Z"/>'
            '<path d="M8 12.5h8"/><path d="M12 6V3"/>')


def wrench() -> str:
    return ('<path d="M15.4 3.6a4.6 4.6 0 0 0-4 6.1l-7 7a1.9 1.9 0 0 0 2.7 2.7l7-7a4.6 4.6 0 0 0 6.1-4l-2.9 2.9-2.8-.7-.7-2.8Z"/>')


def coin_sack() -> str:
    return ('<path d="M9 4h6l-1.6 3.4c3.6 1.4 6.1 4.6 6.1 8.3 0 3-2.6 4.8-7.5 4.8s-7.5-1.8-7.5-4.8c0-3.7 2.5-6.9 6.1-8.3Z"/>'
            '<path d="M9.6 7.4h4.8"/><circle cx="12" cy="15" r="2.7"/>')


def tabard() -> str:
    return ('<path d="M7 3.5h10l3 4-2.5 1.5v11.5L12 18.4l-5.5 2.1V9L4 7.5Z"/><path d="M9.8 3.5a2.2 2.2 0 0 0 4.4 0"/>'
            '<path d="M12 9.2l2.4 1v2.2c0 1.6-1 2.6-2.4 3.2-1.4-.6-2.4-1.6-2.4-3.2v-2.2Z"/>')


def loot_chest() -> str:
    return ('<path d="M3.5 11.5V9.2c0-2.4 2.3-4.2 5.2-4.2h6.6c2.9 0 5.2 1.8 5.2 4.2v2.3"/>'
            '<rect x="3.5" y="11.5" width="17" height="9" rx="1.2"/><path d="M8.2 5.2V20.5M15.8 5.2V20.5"/>'
            '<rect x="10.4" y="9.6" width="3.2" height="4" rx="0.8" fill="#FFFFFF"/>')


def vendor_pouch() -> str:
    return ('<path d="M6.5 7h5.5l-1 2.2c2.8 1.2 4.6 3.7 4.6 6.6 0 2.4-2.2 3.9-6.6 3.9s-6.5-1.5-6.5-3.9c0-2.9 1.7-5.4 4.5-6.6Z"/>'
            '<path d="M7.4 9.2h3.8"/><circle cx="18" cy="7.5" r="3"/><path d="M18 6.3v2.4"/>')


def cart() -> str:
    return ('<path d="M2.5 3.5h2.8l2.4 11.5h10.4l2.1-8.2H6.1"/><circle cx="9.2" cy="19" r="1.6"/><circle cx="16.8" cy="19" r="1.6"/>')


def tent() -> str:
    return ('<path d="M2.5 20.5H21.5"/><path d="M3.5 20.5L12 7l8.5 13.5"/><path d="M9.4 20.5L12 14.2l2.6 6.3"/>'
            '<path d="M12 7V2.5"/><path d="M12 2.6h4.2l-1.3 1.5 1.3 1.5H12" fill="#FFFFFF"/>')



# ---------------------------------------------------------------- colored tab glyphs (WoW palette, rev 3)

def _line(d: str, color: str, width: float, extra: str = "") -> str:
    return f'<path d="{d}" stroke="{color}" stroke-width="{n(width)}" fill="none"{extra}/>'


def backpack_c() -> str:
    body = "M6 9.5a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4V19.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5Z"
    flap = "M6 9.5a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2.6H6Z"
    return (outlined_stroke("M10 5.6V4.4a2 2 0 0 1 4 0v1.2", "#6B4220", 1.6)
            + outlined(body, "#9A6233") + f'<path d="{flap}" fill="#7A4B24"/>' + _line("M6 12.1h12", OUTLINE, 1)
            + f'<rect x="8.3" y="15" width="7.4" height="4.2" rx="1" fill="#7A4B24" stroke="{OUTLINE}" stroke-width="0.9"/>'
            + f'<rect x="10.6" y="10.8" width="2.8" height="2.8" rx="0.6" fill="#F2C94C" stroke="{OUTLINE}" stroke-width="0.9"/>')


def crate_c() -> str:
    box = "M3.5 5H20.5V20.5H3.5Z"
    corners = "".join(f'<rect x="{x}" y="{y}" width="3.2" height="3.2" rx="0.5" fill="#A7B0BA" stroke="{OUTLINE}" stroke-width="0.9"/>'
                      for x, y in ((3.5, 5), (17.3, 5), (3.5, 17.3), (17.3, 17.3)))
    return (outlined(box, "#B9823F") + _line("M3.5 10.2H20.5M3.5 15.3H20.5", "#7A4E22", 1)
            + outlined_stroke("M6.5 8L17.5 17.5M17.5 8L6.5 17.5", "#8F5E2C", 1.8) + corners)


def map_c() -> str:
    sheet = "M3 6.2L9 3.8l6 2.4 6-2.4v14l-6 2.4-6-2.4-6 2.4Z"
    return (outlined(sheet, "#EAD6A6") + '<path d="M9 3.8L15 6.2V20.2L9 17.8Z" fill="#D3B97F"/>'
            + _line("M9 3.8V17.8M15 6.2V20.2", "#9C7F4A", 0.9)
            + _line("M5 15.2c1.4-1.1 2.9-1.1 4.4.1s3 1.1 4.5-.8", "#7A4E22", 1.1, ' stroke-dasharray="1.3 1.3"')
            + _line("M16.4 9.4l2.6 2.6M19 9.4l-2.6 2.6", "#D9442E", 1.7))


def emblem_c() -> str:
    return (f'<circle cx="12" cy="12" r="11.2" fill="{OUTLINE}"/><circle cx="12" cy="12" r="9.6" fill="#F7C948"/>'
            '<circle cx="12" cy="12" r="6.7" fill="none" stroke="#D69E1E" stroke-width="1.4"/>'
            f'<path d="{star_path(12, 12.4, 4.3, 1.8)}" fill="#C88A14"/>'
            '<path d="M5.6 9.2a7 7 0 0 1 4.2-4.1" stroke="#FFE59A" stroke-width="1.4" fill="none"/>')


def helmet_c() -> str:
    dome = "M5 13.2a7 7 0 0 1 14 0V19a1.5 1.5 0 0 1-1.5 1.5H14.2v-4.3H9.8v4.3H6.5A1.5 1.5 0 0 1 5 19Z"
    return (outlined_stroke("M12 6.3V2.9", "#D9442E", 2) + outlined(dome, "#B4BDC8")
            + '<clipPath id="hr"><rect x="12" y="0" width="12" height="24"/></clipPath>'
            + f'<path d="{dome}" fill="#8E98A5" clip-path="url(#hr)"/>'
            + _line("M7.8 12.7h8.4", OUTLINE, 1.7)
            + '<circle cx="7.4" cy="17.8" r="0.9" fill="#E2B34A"/><circle cx="16.6" cy="17.8" r="0.9" fill="#E2B34A"/>')


def sack_c() -> str:
    sack = "M9 4h6l-1.6 3.4c3.6 1.4 6.1 4.6 6.1 8.3 0 3-2.6 4.8-7.5 4.8s-7.5-1.8-7.5-4.8c0-3.7 2.5-6.9 6.1-8.3Z"
    return (outlined(sack, "#CFA56C") + _line("M9.3 7.5h5.4", "#7A4E22", 1.7)
            + f'<circle cx="12" cy="15.2" r="3" fill="#F7C948" stroke="{OUTLINE}" stroke-width="0.9"/>'
            + '<path d="M12 13.6V16.8" stroke="#C88A14" stroke-width="1.1"/>')


def tabard_c() -> str:
    cloth = "M7 3.5h10l3 4-2.5 1.5v11.5L12 18.4l-5.5 2.1V9L4 7.5Z"
    shield = "M12 8.6l2.8 1.1v2.6c0 1.9-1.2 3.1-2.8 3.8-1.6-.7-2.8-1.9-2.8-3.8V9.7Z"
    return (outlined(cloth, "#2F6DB5") + _line("M9.8 3.5a2.2 2.2 0 0 0 4.4 0", OUTLINE, 1.3)
            + _line("M6.5 9V20.5M17.5 9V20.5", "#E2B34A", 0.9)
            + f'<path d="{shield}" fill="#F2C94C" stroke="{OUTLINE}" stroke-width="0.9"/>')


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
    "Modules": (modules, False),
    "Keyboard": (keyboard, False),
    "BellLine": (bell_line, False),
    "Palette": (palette, False),
    "Sliders": (sliders, False),
    "Close": (close, False),
    "ChevronUp": (chevron_up, False),
    "ChevronDown": (chevron_down, False),
    "Pin": (pin, False),
    "Link": (link, False),
    "Todo": (todo, False),
    "Reminder": (reminder, False),
    "Block": (block, False),
    "Tracking": (tracking, False),
    "Credits": (credits, False),
    "Discord": (discord, False),
    "Donate": (donate, False),
    # category / header
    "CrossedSwords": (crossed_swords, False),
    "BarChart": (bar_chart, False),
    "Info": (info, False),
    "Paw": (paw, False),
    "Trophy": (trophy, False),
    "Calendar": (calendar, False),
    "Sparkle": (sparkle, False),
    "Tabard": (tabard_c, True),
    "Cart": (cart, False),
    "Tent": (tent, False),
}


# Line glyphs shipped in color: the SVG stays the white shape source, the TGA gets this fill
# (light from the top) inside a thin dark rim, so it reads on dark and light panels alike.
GLYPH_COLOR = {
    "Settings": "#8FB4D9", "Modules": "#8FB4D9", "Keyboard": "#8FB4D9", "Sliders": "#8FB4D9", "Link": "#8FB4D9",
    "Filter": "#E8C066", "Lock": "#E8C066", "Clock": "#E8C066", "ChevronUp": "#E8C066", "ChevronDown": "#E8C066",
    "TriangleDown": "#E8C066", "TriangleLeft": "#E8C066", "TriangleRight": "#E8C066", "StatusPending": "#E8C066",
    "Tracking": "#E8C066", "Credits": "#E8C066",
    "BellLine": "#F0B84A", "Reminder": "#F0B84A", "Palette": "#D9A066", "CraftingOrder": "#D9A066",
    "Sound": "#7FD0E0", "Reset": "#7FD0E0", "Spinner": "#7FD0E0",
    "Upgrade": "#5FD068", "Plus": "#5FD068",
    "Minus": "#E0554A", "Close": "#E0554A", "Pin": "#E0554A", "Block": "#E0554A",
    "Todo": "#E6D3A8", "Discord": "#7A86F0", "Donate": "#E8687A",
}
WORK = 256  # colored glyphs are composed at 4x, then shrunk to SIZE
RIM_PX = 9  # ~0.85 grid units at WORK size


def colorize(shape: Image.Image, hex_color: str) -> Image.Image:
    rgb = tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    pad = RIM_PX * 2
    a = Image.new("L", (WORK + pad * 2, WORK + pad * 2), 0)
    a.paste(shape.getchannel("A"), (pad, pad))
    rim = a.filter(ImageFilter.MaxFilter(RIM_PX * 2 + 1)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", a.size, OUTLINE_RGB + (0,))
    out.putalpha(rim)
    top = Image.new("RGBA", a.size, tuple(min(255, int(c * 1.15)) for c in rgb) + (255,))
    bottom = Image.new("RGBA", a.size, tuple(int(c * 0.78) for c in rgb) + (255,))
    fill = Image.composite(bottom, top, Image.linear_gradient("L").resize(a.size))
    fill.putalpha(a)
    out.alpha_composite(fill)
    # Shrink with premultiplied alpha so the transparent edge does not pull in dark fringes.
    return out.crop((pad, pad, pad + WORK, pad + WORK)).convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")


def render(name: str, svg: str) -> None:
    svg_path = MEDIA / f"Icon-{name}.svg"
    svg_path.write_text(svg, encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "icon.png"
        px = WORK if name in GLYPH_COLOR else SIZE
        subprocess.run(["resvg", "-w", str(px), "-h", str(px), str(svg_path), str(png)], check=True)
        img = Image.open(png).convert("RGBA")
        if name in GLYPH_COLOR:
            img = colorize(img, GLYPH_COLOR[name])
        out = MEDIA / f"Icon-{name}.tga"
        # Write beside the target, then rename: the addon folder is live in the game, which must never read a half-written file.
        tmp = out.with_name(out.name + ".tmp")
        img.save(tmp, format="TGA")
        os.replace(tmp, out)
    print(f"wrote Icon-{name}.tga + .svg")


if __name__ == "__main__":
    from ui_icon_art import ART  # illustrated tab / category / storage icons (shared material model)
    for name, build in ART.items():
        ICONS[name] = (build, True)
    only = set(sys.argv[1:])  # optional icon names: rebuild just these
    for name, (build, colored) in ICONS.items():
        if name in PAINTED or (only and name not in only):
            continue
        head = COLOR_HEAD if colored else MONO_HEAD
        render(name, head + build() + "</svg>\n")
