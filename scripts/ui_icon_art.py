"""Illustrated colored icons for tabs, source categories and storage markers.

One shared material model so the whole set reads as one hand: every part gets a dark outline, a
top-lit vertical gradient (lighter top, darker bottom) and a soft sheen over its upper half.
Light comes from the top; internal detail lines use a darker shade of the part's own color.
Each builder returns SVG body markup (its own <defs> included) for the 24-unit grid.
"""
from __future__ import annotations

import math

OUTLINE = "#1B130B"
EDGE_W = 2.6  # outline stroke under each part: 1.3 units show outside the shape


def n(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def _rgb(hexc: str) -> tuple[int, int, int]:
    h = hexc.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def mix(a: str, b: str, t: float) -> str:
    ra, ga, ba = _rgb(a)
    rb, gb, bb = _rgb(b)
    return "#%02X%02X%02X" % (round(ra + (rb - ra) * t), round(ga + (gb - ga) * t), round(ba + (bb - ba) * t))


def lighter(c: str, t: float = 0.2) -> str:
    return mix(c, "#FFFFFF", t)


def darker(c: str, t: float = 0.25) -> str:
    return mix(c, "#000000", t)


def circle(cx: float, cy: float, r: float) -> str:
    return f"M{n(cx - r)} {n(cy)}a{n(r)} {n(r)} 0 1 0 {n(2 * r)} 0a{n(r)} {n(r)} 0 1 0 {n(-2 * r)} 0Z"


def rect(x: float, y: float, w: float, h: float, r: float = 0) -> str:
    if r <= 0:
        return f"M{n(x)} {n(y)}H{n(x + w)}V{n(y + h)}H{n(x)}Z"
    return (f"M{n(x + r)} {n(y)}H{n(x + w - r)}A{n(r)} {n(r)} 0 0 1 {n(x + w)} {n(y + r)}V{n(y + h - r)}"
            f"A{n(r)} {n(r)} 0 0 1 {n(x + w - r)} {n(y + h)}H{n(x + r)}A{n(r)} {n(r)} 0 0 1 {n(x)} {n(y + h - r)}"
            f"V{n(y + r)}A{n(r)} {n(r)} 0 0 1 {n(x + r)} {n(y)}Z")


def rot_rect(cx: float, cy: float, length: float, width: float, deg: float) -> str:
    a = math.radians(deg)
    ux, uy = math.cos(a) * length / 2, math.sin(a) * length / 2
    vx, vy = -math.sin(a) * width / 2, math.cos(a) * width / 2
    pts = [(cx - ux - vx, cy - uy - vy), (cx + ux - vx, cy + uy - vy), (cx + ux + vx, cy + uy + vy), (cx - ux + vx, cy - uy + vy)]
    return "M" + "L".join(f"{n(x)} {n(y)}" for x, y in pts) + "Z"


def star(cx: float, cy: float, r_out: float, r_in: float, points: int = 5, rot: float = -90) -> str:
    pts = []
    for i in range(points * 2):
        a = math.radians(rot + i * 180 / points)
        r = r_out if i % 2 == 0 else r_in
        pts.append(f"{n(cx + r * math.cos(a))} {n(cy + r * math.sin(a))}")
    return "M" + "L".join(pts) + "Z"


class Art:
    """Collects <defs> for one icon and draws parts with the shared material."""

    def __init__(self) -> None:
        self.defs: list[str] = []
        self.k = 0
        self.sheen = self._grad("#FFFFFF", "#FFFFFF", 0.34, 0.0, stop2=0.55)

    def _id(self, p: str) -> str:
        self.k += 1
        return f"{p}{self.k}"

    def _grad(self, top: str, bottom: str, o1: float = 1.0, o2: float = 1.0, stop2: float = 1.0) -> str:
        gid = self._id("g")
        self.defs.append(f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
                         f'<stop offset="0" stop-color="{top}" stop-opacity="{n(o1)}"/>'
                         f'<stop offset="{n(stop2)}" stop-color="{bottom}" stop-opacity="{n(o2)}"/></linearGradient>')
        return gid

    def part(self, d: str, base: str, *, edge: bool = True, sheen: bool = True, light: float = 0.2, dark: float = 0.22,
             extra: str = "") -> str:
        g = self._grad(lighter(base, light), darker(base, dark))
        s = ""
        if edge:
            s += f'<path d="{d}" fill="{OUTLINE}" stroke="{OUTLINE}" stroke-width="{EDGE_W}" stroke-linejoin="round"{extra}/>'
        s += f'<path d="{d}" fill="url(#{g})"{extra}/>'
        if sheen:
            s += f'<path d="{d}" fill="url(#{self.sheen})"{extra}/>'
        return s

    def rod(self, d: str, base: str, width: float, *, cap: str = "round") -> str:
        """Stroked part (handles, ribbons): dark rim, gradient body, thin light core."""
        g = self._grad(lighter(base, 0.18), darker(base, 0.2))
        return (f'<path d="{d}" stroke="{OUTLINE}" stroke-width="{n(width + EDGE_W)}" stroke-linecap="{cap}"/>'
                f'<path d="{d}" stroke="url(#{g})" stroke-width="{n(width)}" stroke-linecap="{cap}"/>'
                f'<path d="{d}" stroke="{lighter(base, 0.35)}" stroke-width="{n(width * 0.28)}" stroke-linecap="{cap}" stroke-opacity="0.7"/>')

    def line(self, d: str, color: str, width: float, extra: str = "") -> str:
        return f'<path d="{d}" stroke="{color}" stroke-width="{n(width)}" fill="none"{extra}/>'

    def fill(self, d: str, color: str, extra: str = "") -> str:
        return f'<path d="{d}" fill="{color}"{extra}/>'

    def clip(self, d: str) -> str:
        cid = self._id("c")
        self.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        return cid

    def done(self, body: str) -> str:
        return "<defs>" + "".join(self.defs) + "</defs>" + body


# palette (WoW-leaning: warm golds, leather browns, steel, deep blue cloth)
GOLD = "#E8B43E"
GOLD_D = "#B98318"
STEEL = "#B7C0CB"
STEEL_D = "#7E8896"
LEATHER = "#9A6233"
LEATHER_D = "#6E4321"
WOOD = "#A8713A"
WOOD_D = "#74491F"
PARCH = "#EBD8A8"
PARCH_D = "#C9AC70"
CLOTH_BLUE = "#2F6DB5"
CLOTH_RED = "#B8352A"
BONE = "#EAE0C6"
DARK = "#2A1E14"


# ---------------------------------------------------------------- tabs

def portrait() -> str:
    a = Art()
    inner = circle(12, 12, 7.4)
    cid = a.clip(inner)
    bust = (a.fill(circle(12, 10.2, 3.1), "#C7D2E6") + a.fill("M5.2 20.5a6.8 6.6 0 0 1 13.6 0Z", "#C7D2E6")
            + a.fill("M5.2 20.5a6.8 6.6 0 0 1 13.6 0Z", "#93A2BE", ' opacity="0.45" transform="translate(0 1.2)"'))
    return a.done(a.part(circle(12, 12, 10), GOLD) + a.part(inner, "#24365C", sheen=False, light=0.25, dark=0.15)
                  + f'<g clip-path="url(#{cid})">{bust}</g>'
                  + a.line(inner, darker(GOLD, 0.45), 0.9))


def medal() -> str:
    a = Art()
    return a.done(a.part("M6.4 2.5H10.6L13.4 10H9.2Z", CLOTH_RED) + a.part("M17.6 2.5H13.4L10.6 10H14.8Z", darker(CLOTH_RED, 0.12))
                  + a.part(circle(12, 15.2, 6), GOLD) + a.line(circle(12, 15.2, 4.2), GOLD_D, 1)
                  + a.fill(star(12, 15.5, 2.9, 1.25), GOLD_D))


def skull() -> str:
    a = Art()
    head = "M12 2.8a8.2 8.2 0 0 0-8.2 8.2c0 2.7 1.3 4.8 3.2 6V20.6h10V17c1.9-1.2 3.2-3.3 3.2-6A8.2 8.2 0 0 0 12 2.8Z"
    return a.done(a.part(head, BONE)
                  + a.fill("M6.6 11.2a2.4 2.1 0 1 0 4.8 0 2.4 2.1 0 1 0-4.8 0Z", DARK)
                  + a.fill("M12.6 11.2a2.4 2.1 0 1 0 4.8 0 2.4 2.1 0 1 0-4.8 0Z", DARK)
                  + a.fill("M12 13.8l1.1 2.1h-2.2Z", DARK)
                  + a.line("M10 20.6V18.2M12 20.6V18.2M14 20.6V18.2", darker(BONE, 0.45), 0.9)
                  + a.fill("M7.6 10.3a.8.6 0 1 0 1.6 0 .8.6 0 1 0-1.6 0Z", "#FFFFFF", ' opacity="0.25"'))


def _sword(a: Art) -> str:
    blade = "M12 2.4L13.5 4.6V15H10.5V4.6Z"
    return (a.part(blade, STEEL) + a.line("M12 4.4V14.6", STEEL_D, 0.7)
            + a.part(rect(8.1, 15, 7.8, 1.9, 0.95), GOLD) + a.part(rect(10.95, 16.9, 2.1, 3.3, 0.6), "#7A2E20", sheen=False)
            + a.part(circle(12, 21, 1.25), GOLD))


def crossed_swords() -> str:
    a = Art()
    return a.done(f'<g transform="rotate(-42 12 12.4)">{_sword(a)}</g><g transform="rotate(42 12 12.4)">{_sword(a)}</g>')


def bar_chart() -> str:
    a = Art()
    return a.done(a.part(rect(3.6, 12.2, 4.4, 8.3, 0.8), "#3B82C4") + a.part(rect(9.8, 7.2, 4.4, 13.3, 0.8), "#3FAE5B")
                  + a.part(rect(16, 3.5, 4.4, 17, 0.8), GOLD) + a.rod("M2.6 21H21.4", STEEL_D, 1.1, cap="round"))


def horseshoe() -> str:
    a = Art()
    band = ("M5.4 20.5H8.6L8.8 18.1C7.4 16.7 6.7 14.8 6.7 12.6 6.7 9 9 6.3 12 6.3S17.3 9 17.3 12.6C17.3 14.8 16.6 16.7 15.2 18.1L15.4 20.5H18.6"
            "L18.4 17.5C19.7 15.9 20.5 14.3 20.5 12.4 20.5 7.3 16.7 3.5 12 3.5S3.5 7.3 3.5 12.4C3.5 14.3 4.3 15.9 5.6 17.5Z")
    holes = "".join(a.fill(circle(12 + 6.95 * math.cos(math.radians(d)), 12.5 - 6.95 * math.sin(math.radians(d)), 0.75), DARK)
                    for d in (195, 145, 90, 35, -15))
    return a.done(a.part(band, STEEL) + holes)


def hammer_pick() -> str:
    a = Art()
    hammer_head = rot_rect(7.6, 7.6, 7.4, 3.4, 45)
    return a.done(a.rod("M5.2 18.8L15.8 8.2", WOOD, 1.8) + a.rod("M13.2 4.9Q17.6 4.1 19.6 8.2", STEEL, 2.2)
                  + a.rod("M18.8 18.8L8.4 8.4", WOOD, 1.8) + a.part(hammer_head, STEEL)
                  + a.line(rot_rect(7.6, 7.6, 7.4, 3.4, 45), STEEL_D, 0.0))


def info() -> str:
    a = Art()
    return a.done(a.part(circle(12, 12, 9.6), "#2F80D1", light=0.28, dark=0.25)
                  + a.line("M12 10.8V17", "#FFFFFF", 2.4, ' stroke-linecap="round"')
                  + a.fill(circle(12, 7.4, 1.45), "#FFFFFF"))


def wrench() -> str:
    a = Art()
    d = "M15.4 3.6a4.6 4.6 0 0 0-4 6.1l-7 7a1.9 1.9 0 0 0 2.7 2.7l7-7a4.6 4.6 0 0 0 6.1-4l-2.9 2.9-2.8-.7-.7-2.8Z"
    return a.done(a.part(d, STEEL) + a.fill(circle(5.9, 18.1, 0.7), STEEL_D))


# ---------------------------------------------------------------- storage

def backpack() -> str:
    a = Art()
    body = "M6 9.5a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4V19.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 19.5Z"
    flap = "M6 9.5a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2.9H6Z"
    return a.done(a.rod("M10 5.6V4.4a2 2 0 0 1 4 0v1.2", LEATHER_D, 1.5) + a.part(body, LEATHER)
                  + a.part(flap, LEATHER_D, edge=False) + a.line("M6 12.4h12", OUTLINE, 0.9)
                  + a.part(rect(8.3, 15, 7.4, 4.3, 1), LEATHER_D, sheen=False) + a.line("M8.6 16.3h6.8", darker(LEATHER_D, 0.3), 0.6)
                  + a.part(rect(10.6, 11.1, 2.8, 2.8, 0.6), GOLD))


def crate() -> str:
    a = Art()
    corners = "".join(a.part(rect(x, y, 3.1, 3.1, 0.5), STEEL, sheen=False) for x, y in ((3.4, 4.9), (17.5, 4.9), (3.4, 17.4), (17.5, 17.4)))
    return a.done(a.part(rect(3.5, 5, 17, 15.5, 1), WOOD) + a.line("M3.5 10.1H20.5M3.5 15.3H20.5", WOOD_D, 0.9)
                  + a.rod("M6.6 8L17.4 17.4", lighter(WOOD, 0.05), 1.6) + a.rod("M17.4 8L6.6 17.4", lighter(WOOD, 0.05), 1.6) + corners)


def coin_sack() -> str:
    a = Art()
    sack = "M9 4h6l-1.6 3.4c3.6 1.4 6.1 4.6 6.1 8.3 0 3-2.6 4.8-7.5 4.8s-7.5-1.8-7.5-4.8c0-3.7 2.5-6.9 6.1-8.3Z"
    return a.done(a.part(sack, "#C99A5E") + a.rod("M9.2 7.5h5.6", LEATHER_D, 1.4)
                  + a.part(circle(12, 15.2, 3.1), GOLD) + a.line(circle(12, 15.2, 2), GOLD_D, 0.7)
                  + a.fill(star(12, 15.3, 1.3, 0.55), GOLD_D))


def tabard() -> str:
    a = Art()
    cloth = "M7 3.5h10l3 4-2.5 1.5v11.5L12 18.4l-5.5 2.1V9L4 7.5Z"
    shield = "M12 8.4l3 1.2v2.7c0 2-1.3 3.3-3 4-1.7-.7-3-2-3-4V9.6Z"
    return a.done(a.part(cloth, CLOTH_BLUE) + a.fill("M9.6 3.5a2.4 2.1 0 0 0 4.8 0Z", DARK)
                  + a.line("M6.5 9.2V20.3M17.5 9.2V20.3", GOLD, 0.9) + a.part(shield, GOLD))


def warband() -> str:
    a = Art()
    banner = "M7 3.6H19.2L16.8 8.3L19.2 13H7Z"
    return a.done(a.rod("M6 21.2V2.8", WOOD, 1.6) + a.part(banner, CLOTH_BLUE)
                  + a.part(star(12.4, 8.3, 2.4, 1), GOLD, sheen=False) + a.part(circle(6, 2.6, 1.2), GOLD, sheen=False))


# ---------------------------------------------------------------- plans / currency / gear

def treasure_map() -> str:
    a = Art()
    sheet = "M3 6.2L9 3.8l6 2.4 6-2.4v14l-6 2.4-6-2.4-6 2.4Z"
    return a.done(a.part(sheet, PARCH) + a.fill("M9 3.8L15 6.2V20.2L9 17.8Z", PARCH_D, ' opacity="0.75"')
                  + a.line("M9 3.8V17.8M15 6.2V20.2", darker(PARCH_D, 0.25), 0.8)
                  + a.line("M5 15.2c1.4-1.1 2.9-1.1 4.4.1s3 1.1 4.5-.8", "#7A4E22", 1.1, ' stroke-dasharray="1.3 1.3"')
                  + a.rod("M16.5 9.5l2.4 2.4M18.9 9.5l-2.4 2.4", CLOTH_RED, 1.3))


def emblem() -> str:
    a = Art()
    return a.done(a.part(circle(12, 12, 9.6), GOLD) + a.line(circle(12, 12, 6.8), GOLD_D, 1.2)
                  + a.part(star(12, 12.4, 4.4, 1.85), lighter(GOLD, 0.15), sheen=False))


def helmet() -> str:
    a = Art()
    dome = "M5 13.2a7 7 0 0 1 14 0V19a1.5 1.5 0 0 1-1.5 1.5H14.2v-4.3H9.8v4.3H6.5A1.5 1.5 0 0 1 5 19Z"
    cid = a.clip(dome)
    return a.done(a.part("M11.2 6.9C11.3 3.9 13.6 2.3 17.4 2.5c-1 1.7-2.6 3-5 4.4Z", CLOTH_RED) + a.part(dome, STEEL)
                  + f'<g clip-path="url(#{cid})"><rect x="12" y="0" width="12" height="24" fill="{STEEL_D}" opacity="0.45"/></g>'
                  + a.line("M7.8 12.7h8.4", DARK, 1.6) + a.line("M12 6.6V10.6", STEEL_D, 0.9)
                  + a.fill(circle(7.4, 17.8, 0.85), GOLD) + a.fill(circle(16.6, 17.8, 0.85), GOLD))


# ---------------------------------------------------------------- source categories

def loot_chest() -> str:
    a = Art()
    lid = "M3.5 11.4V9.2c0-2.4 2.3-4.2 5.2-4.2h6.6c2.9 0 5.2 1.8 5.2 4.2v2.2Z"
    body = rect(3.5, 11.4, 17, 9.1, 1.1)
    bands = (a.part(rect(7.2, 5.1, 2.1, 15.4, 0.3), GOLD, sheen=False) + a.part(rect(14.7, 5.1, 2.1, 15.4, 0.3), GOLD, sheen=False))
    return a.done(a.part(body, WOOD_D) + a.part(lid, WOOD) + bands + a.line("M3.5 11.4H20.5", OUTLINE, 1)
                  + a.part(rect(10.2, 9.7, 3.6, 4.4, 0.8), GOLD) + a.fill("M12 11a.8.8 0 0 0-.4 1.5V13.2h.8V12.5A.8.8 0 0 0 12 11Z", DARK))


def quest_scroll() -> str:
    a = Art()
    return a.done(a.part(rect(6, 5, 12, 14, 0), PARCH) + a.part(rect(4.5, 3, 15, 3.4, 1.7), PARCH_D)
                  + a.part(rect(4.5, 17.6, 15, 3.4, 1.7), PARCH_D)
                  + a.line("M8.5 9.6H15.5M8.5 12.2H15.5M8.5 14.8H12.6", darker(PARCH_D, 0.35), 0.9)
                  + a.part(circle(15.4, 15.2, 1.9), CLOTH_RED, sheen=False))


def vendor_scale() -> str:
    # merchant balance: post on a foot, beam with a finial, two pans hanging on chains
    a = Art()
    chain = "M4.6 6.8L3.2 12.2M4.6 6.8L8 12.2M19.4 6.8L16 12.2M19.4 6.8L20.8 12.2"
    chains = a.line(chain, OUTLINE, 1.5) + a.line(chain, GOLD_D, 0.7)
    left_pan, right_pan = "M2.4 12.2h7.4a3.7 2.7 0 0 1-7.4 0Z", "M14.2 12.2h7.4a3.7 2.7 0 0 1-7.4 0Z"
    return a.done(chains + a.rod("M12 5.6V19.4", GOLD, 2.2) + a.part(rect(7.6, 19, 8.8, 2.3, 1.1), GOLD)
                  + a.rod("M4.6 6.8H19.4", GOLD, 1.9) + a.part(circle(12, 4.4, 1.6), GOLD, sheen=False)
                  + a.part(left_pan, GOLD) + a.part(right_pan, GOLD))


def paw() -> str:
    a = Art()
    c = "#D9913E"
    return a.done(a.part("M12 11.5c-3 0-5.6 2.6-5.6 5.2 0 2 1.6 3.3 3.4 3.3 1 0 1.5-.5 2.2-.5s1.2.5 2.2.5c1.8 0 3.4-1.3 3.4-3.3 0-2.6-2.6-5.2-5.6-5.2Z", c)
                  + "".join(a.part(circle(x, y, 1.9), c) for x, y in ((5.6, 10.4), (9.3, 6.4), (14.7, 6.4), (18.4, 10.4))))


def achievement() -> str:
    a = Art()
    shield = "M12 2.8L19.6 5.6V11.2c0 4.8-3.2 8.3-7.6 10-4.4-1.7-7.6-5.2-7.6-10V5.6Z"
    inner = "M12 5.3L17.1 7.2V11.3c0 3.4-2.1 5.9-5.1 7.2-3-1.3-5.1-3.8-5.1-7.2V7.2Z"
    return a.done(a.part(shield, GOLD) + a.part(inner, CLOTH_RED, sheen=False) + a.part(star(12, 11.6, 3.3, 1.4), GOLD, sheen=False))


def calendar() -> str:
    a = Art()
    page = rect(3.5, 5, 17, 15.5, 1.8)
    dots = "".join(a.fill(circle(x, y, 0.75), darker(PARCH_D, 0.45)) for x in (8, 12, 16) for y in (13.6, 17.2))
    return a.done(a.part(page, "#F3ECDC") + a.part("M3.5 6.8a1.8 1.8 0 0 1 1.8-1.8h13.4a1.8 1.8 0 0 1 1.8 1.8V10H3.5Z", CLOTH_RED, edge=False)
                  + a.line("M3.5 10H20.5", OUTLINE, 0.9) + dots + a.part(rect(14.6, 15.8, 2.8, 2.8, 0.5), GOLD, sheen=False)
                  + a.rod("M8 3V6.6", STEEL, 1.2) + a.rod("M16 3V6.6", STEEL, 1.2))


def gift() -> str:
    a = Art()
    bow = ("M12 7.4C10.3 3.8 6.7 3.6 7.1 5.8 7.4 7.4 12 7.4 12 7.4Z", "M12 7.4c1.7-3.6 5.3-3.8 4.9-1.6-.3 1.6-4.9 1.6-4.9 1.6Z")
    return a.done(a.part(rect(4.5, 11, 15, 9.6, 1), CLOTH_RED) + a.part(rect(3, 7.4, 18, 4, 1), lighter(CLOTH_RED, 0.08))
                  + a.part(rect(10.8, 7.4, 2.4, 13.2, 0), GOLD, sheen=False) + a.part(bow[0], GOLD) + a.part(bow[1], GOLD))


def cards() -> str:
    a = Art()
    back = f'<g transform="rotate(-13 9 11.5)">{a.part(rect(4.2, 4.5, 9.6, 13.6, 1.4), "#2F5FA8")}</g>'
    front_card = rect(9.8, 6.2, 9.6, 13.6, 1.4)
    front = (a.part(front_card, "#2F5FA8") + a.line(rect(11.1, 7.5, 7, 11, 0.8), GOLD, 0.8)
             + a.part("M14.6 10.4L16.6 13L14.6 15.6L12.6 13Z", GOLD, sheen=False))
    return a.done(back + f'<g transform="rotate(9 14.6 13)">{front}</g>')


def cart() -> str:
    a = Art()
    basket = "M6.1 6.8H20.6L18.5 15H7.8Z"
    return a.done(a.rod("M2.6 3.6H5.3L7.8 15H18.6", STEEL_D, 1.5) + a.part(basket, CLOTH_BLUE)
                  + a.line("M10.6 7V14.8M14.4 7V14.8M6.9 10.9H19.6", lighter(CLOTH_BLUE, 0.35), 0.8)
                  + a.part(circle(9.3, 19, 1.8), DARK, sheen=False) + a.part(circle(17, 19, 1.8), DARK, sheen=False))


def compass() -> str:
    a = Art()
    return a.done(a.part(circle(12, 12, 9.6), "#C9962F") + a.part(circle(12, 12, 7), "#F3ECDC", sheen=False)
                  + a.fill("M16 8L12.9 12.9 11.1 11.1Z", CLOTH_RED) + a.fill("M8 16L11.1 11.1 12.9 12.9Z", STEEL_D)
                  + a.fill(circle(12, 12, 0.9), GOLD_D))


def tent() -> str:
    a = Art()
    canopy = "M3.2 20.5L12 7.2l8.8 13.3Z"
    cid = a.clip(canopy)
    stripes = "".join(f'<path d="M{n(x)} 4L{n(x + 4)} 22H{n(x + 6.4)}L{n(x + 2.4)} 4Z" fill="{GOLD}"/>' for x in (2.2, 9.2, 16.2))
    return a.done(a.rod("M12 7.4V2.8", WOOD, 1.2) + a.part("M12.4 2.6H16.6L15.3 4.1 16.6 5.6H12.4Z", GOLD, sheen=False)
                  + a.part(canopy, "#6C3FA8") + f'<g clip-path="url(#{cid})" opacity="0.85">{stripes}</g>'
                  + a.part("M9.6 20.5L12 14.4l2.4 6.1Z", DARK, sheen=False) + a.rod("M2.4 20.8H21.6", WOOD_D, 0.9))


def question() -> str:
    a = Art()
    q = "M9.4 9.4a2.7 2.7 0 1 1 3.8 2.5c-.7.3-1.2 1-1.2 1.8v.8"
    return a.done(a.part(circle(12, 12, 9.6), "#3D6FA8") + a.rod(q, GOLD, 2.4) + a.part(circle(12, 17.6, 1.4), GOLD, sheen=False))


def sparkle() -> str:
    a = Art()
    big = "M10.5 2.8c.8 5 2.1 6.3 7.1 7.1-5 .8-6.3 2.1-7.1 7.1-.8-5-2.1-6.3-7.1-7.1 5-.8 6.3-2.1 7.1-7.1Z"
    small = "M18 13.8c.4 2.3 1 3 3.3 3.3-2.3.4-2.9 1-3.3 3.3-.4-2.3-1-2.9-3.3-3.3 2.3-.3 2.9-1 3.3-3.3Z"
    return a.done(a.part(big, GOLD) + a.part(small, lighter(GOLD, 0.1)))


def map_pin() -> str:
    a = Art()
    pin = "M12 21.5s-6.8-6.4-6.8-11.6a6.8 6.8 0 0 1 13.6 0c0 5.2-6.8 11.6-6.8 11.6Z"
    return a.done(a.part(pin, "#D23F31") + a.part(circle(12, 9.8, 2.5), "#F3ECDC", sheen=False))



# ---------------------------------------------------------------- rev 5 (user brief: satchel, crates, checklist, coins, plate, vault door, campfire)

def satchel() -> str:
    a = Art()
    body = "M4.5 10.5c0-1.7 1.3-3 3-3h9c1.7 0 3 1.3 3 3v8a2.5 2.5 0 0 1-2.5 2.5h-10A2.5 2.5 0 0 1 4.5 18.5Z"
    flap = "M4.5 10.5c0-1.7 1.3-3 3-3h9c1.7 0 3 1.3 3 3v2.4c0 .9-.7 1.6-1.6 1.6H6.1c-.9 0-1.6-.7-1.6-1.6Z"
    return a.done(a.rod("M7.6 7.6C7.6 3.4 16.4 3.4 16.4 7.6", LEATHER_D, 1.6) + a.part(body, LEATHER)
                  + a.part(flap, LEATHER_D, sheen=False) + a.part(rect(10.7, 12.6, 2.6, 4.4, 0.8), LEATHER_D, sheen=False)
                  + a.part(rect(10.1, 15.4, 3.8, 2.6, 0.5), GOLD, sheen=False)
                  + a.line("M6.6 19.3H17.4", lighter(LEATHER, 0.25), 0.7, ' stroke-dasharray="1 0.9"'))


def _crate(a: Art, x: float, y: float, w: float, h: float, brace: bool) -> str:
    s = a.part(rect(x, y, w, h, 0.8), WOOD) + a.line(f"M{n(x)} {n(y + h / 3)}H{n(x + w)}M{n(x)} {n(y + 2 * h / 3)}H{n(x + w)}", WOOD_D, 0.8)
    if brace:
        s += a.rod(f"M{n(x + 1.6)} {n(y + 1.4)}L{n(x + w - 1.6)} {n(y + h - 1.4)}", lighter(WOOD, 0.05), 1.3)
    for cx, cy in ((x, y), (x + w - 2.4, y), (x, y + h - 2.4), (x + w - 2.4, y + h - 2.4)):
        s += a.part(rect(cx, cy, 2.4, 2.4, 0.4), STEEL, sheen=False)
    return s


def storage_crates() -> str:
    a = Art()
    return a.done(_crate(a, 8.2, 3.2, 10.2, 7.8, False) + _crate(a, 3.4, 11, 17.2, 9.8, True))


def checklist() -> str:
    a = Art()
    rows = ""
    for i, y in enumerate((8.6, 12.9, 17.2)):
        rows += a.part(rect(7, y - 1.4, 2.8, 2.8, 0.5), "#F7F1E2", sheen=False)
        rows += a.line(f"M11.6 {n(y)}H16.6", "#6E5530", 1.5, ' stroke-linecap="round"')
        if i < 2:
            rows += a.line(f"M7.5 {n(y)}l1 1 2.2-2.6", OUTLINE, 2.2, ' stroke-linecap="round" stroke-linejoin="round"')
            rows += a.line(f"M7.5 {n(y)}l1 1 2.2-2.6", "#41C95E", 1.1, ' stroke-linecap="round" stroke-linejoin="round"')
    return a.done(a.part(rect(4.8, 3.6, 14.4, 17.6, 1.5), PARCH) + a.part(rect(9, 2.2, 6, 3, 1), GOLD) + rows)


def currency_coins() -> str:
    a = Art()

    def coin(cx: float, cy: float, r: float, c: str) -> str:
        return a.part(circle(cx, cy, r), c) + a.line(circle(cx, cy, r * 0.68), darker(c, 0.25), 0.9)

    return a.done(coin(7.6, 9.4, 4.9, "#D7874B") + coin(16.4, 9.4, 4.9, "#CDD3DA") + coin(12, 15.4, 5.6, GOLD)
                  + a.fill(star(12, 15.6, 2.3, 1), GOLD_D))


def plate_armor() -> str:
    a = Art()
    torso = "M7 6.5L9.6 4.8h4.8L17 6.5l1 4.2-1.2 9.8H7.2L6 10.7Z"
    cid = a.clip(torso)
    return a.done(a.part("M3 9.4c0-2.6 2-4.4 4.6-4.4L8.8 10 5.3 11.8C3.9 11.6 3 10.6 3 9.4Z", lighter(STEEL, 0.06))
                  + a.part("M21 9.4c0-2.6-2-4.4-4.6-4.4L15.2 10l3.5 1.8c1.4-.2 2.3-1.2 2.3-2.4Z", lighter(STEEL, 0.06))
                  + a.part(torso, STEEL)
                  + f'<g clip-path="url(#{cid})"><rect x="12" y="0" width="12" height="24" fill="{STEEL_D}" opacity="0.4"/></g>'
                  + a.fill("M9.6 4.8a2.4 1.7 0 0 0 4.8 0Z", DARK) + a.line("M9.2 5.2a2.8 2.1 0 0 0 5.6 0", GOLD, 0.9)
                  + a.line("M3.6 8.6c.6-1.9 2.2-3.1 4-3.2M20.4 8.6c-.6-1.9-2.2-3.1-4-3.2", GOLD, 0.9)
                  + a.line("M12 6.6V16.4", STEEL_D, 0.9) + a.line("M8.2 11c1.3 1.1 2.5 1.6 3.8 1.6s2.5-.5 3.8-1.6", STEEL_D, 0.9)
                  + a.part(rect(7.1, 16.4, 9.8, 1.9, 0.5), GOLD, sheen=False) + a.fill(circle(12, 17.35, 0.7), GOLD_D))


def vault_door() -> str:
    a = Art()
    ticks = "".join(f"M{n(12 + 4.1 * math.cos(math.radians(d)))} {n(12 + 4.1 * math.sin(math.radians(d)))}"
                    f"L{n(12 + 5 * math.cos(math.radians(d)))} {n(12 + 5 * math.sin(math.radians(d)))}" for d in range(0, 360, 30))
    bolts = "".join(a.fill(circle(12 + 6.4 * math.cos(math.radians(d)), 12 + 6.4 * math.sin(math.radians(d)), 0.55), STEEL_D)
                    for d in range(15, 360, 45))
    return a.done(a.part(rect(3, 3, 18, 18, 2.2), "#8C96A3") + a.part(rect(1.9, 6.2, 2.2, 3.2, 0.5), GOLD, sheen=False)
                  + a.part(rect(1.9, 14.6, 2.2, 3.2, 0.5), GOLD, sheen=False) + a.part(circle(12, 12, 7.6), STEEL) + bolts
                  + a.line(ticks, DARK, 0.8) + a.part(circle(12, 12, 3.1), GOLD) + a.line("M12 12L12 9.6", DARK, 1.1, ' stroke-linecap="round"'))


def campfire() -> str:
    a = Art()
    stones = "".join(a.part(f"M{n(x - 1.6)} {n(y)}a1.6 1.1 0 1 0 3.2 0a1.6 1.1 0 1 0-3.2 0Z", "#8C8A86", sheen=False)
                     for x, y in ((4.4, 20.2), (8.2, 21), (12, 21.3), (15.8, 21), (19.6, 20.2)))
    flame = "M12 3c.8 2.8 3.8 4.6 4.6 7.8.7 3-1 5.9-4.6 5.9s-5.3-2.9-4.6-5.9c.4-1.7 1.5-2.8 2.4-4 .4 1.5 1.2 2.2 2 2.4-.6-2.1-.4-4.2.2-6.2Z"
    inner = "M12 9.2c.5 1.7 2.1 2.7 2.3 4.4.2 1.7-.9 3-2.3 3s-2.5-1.3-2.3-3c.2-1.7 1.7-2.7 2.3-4.4Z"
    return a.done(a.rod("M5 19.6L19 15.4", WOOD, 2) + a.rod("M19 19.6L5 15.4", lighter(WOOD, 0.06), 2)
                  + a.part(flame, "#E8752A", light=0.25, dark=0.1) + a.part(inner, "#F7C948", edge=False, sheen=False) + stones)



# ---------------------------------------------------------------- rev 6: drawn from WoW's own item icons
# Bag    <- INV_Misc_Bag_07 / _19 / _22 (flap backpack, two straps with buckles, top roll, side ring)
# Crate  <- INV_Crate_01 (three-quarter wooden crate, plank faces)
# Loot   <- INV_Misc_TreasureChest02b (dark wood chest, gold corner fittings and lock, domed lid)
# Bank   <- Achievement_GuildPerk_MobileBanking (open chest heaped with gold coins)

def wow_bag() -> str:
    # INV_Misc_Bag_08 shape: deep flap with stitched edge, one strap down the middle with a big
    # buckle on the flap's lower edge, rolled top and a side ring
    a = Art()
    tan = "#A8703A"
    strap = darker(tan, 0.25)
    body = rect(4.8, 6.2, 14.4, 15, 3)
    flap = "M4.8 9.2a3 3 0 0 1 3-3h8.4a3 3 0 0 1 3 3v4.6c0 .8-.6 1.4-1.4 1.4H6.2c-.8 0-1.4-.6-1.4-1.4Z"
    straps = a.rod("M12 6.6V18.8", strap, 1.7, cap="butt")
    buckles = a.part(rect(9.8, 12.8, 4.4, 3.4, 0.7), GOLD) + a.fill(rect(11.3, 13.9, 1.4, 1.2, 0.2), darker(tan, 0.3)) + a.line("M12 13.1V16", GOLD_D, 0.7)
    return a.done(a.part(rect(6.4, 3.4, 11.2, 3.6, 1.8), darker(tan, 0.2)) + a.line("M8.4 5.2H15.6", darker(tan, 0.4), 0.6)
                  + a.line(circle(4.3, 16.6, 1.5), STEEL_D, 1.1) + a.part(body, tan) + a.part(flap, lighter(tan, 0.08))
                  + a.line("M6.2 14H17.8", darker(tan, 0.3), 0.6, ' stroke-dasharray="0.9 0.8"') + straps + buckles)


def wow_crate() -> str:
    a = Art()
    front = "M3 9.5H15V21H3Z"
    top = "M3 9.5L9 4.5H21L15 9.5Z"
    side = "M15 9.5L21 4.5V16L15 21Z"
    return a.done(a.part(side, darker(WOOD, 0.18), sheen=False) + a.part(top, lighter(WOOD, 0.12)) + a.part(front, WOOD)
                  + a.line("M3 13.3H15M3 17.2H15", WOOD_D, 0.8) + a.line("M5.8 9.5L11.8 4.5M9 9.5L15 4.5M12 9.5L18 4.5", WOOD_D, 0.7)
                  + a.line("M15 13.4L21 8.4M15 17.2L21 12.2", darker(WOOD_D, 0.15), 0.7)
                  + a.line("M4.4 10.9H13.6V19.6H4.4Z", darker(WOOD_D, 0.1), 0.9) + a.line("M4.6 19.4L13.4 11.1", darker(WOOD_D, 0.1), 0.9))


def wow_loot_chest() -> str:
    a = Art()
    wood = "#5E3B22"
    body = "M3 11.5H15.2V20.8H3Z"
    body_side = "M15.2 11.5L20.6 8V17.2L15.2 20.8Z"
    lid = "M3 11.5V9.2C3 6.5 5.2 4.9 8.4 4.9h3.6c2 0 3.2 1.6 3.2 4.3v2.3Z"
    lid_side = "M15.2 11.5L20.6 8V6.8C20.6 4.6 19.5 3.4 17.6 3.4L12.4 4.9C14.3 5 15.2 6.6 15.2 9.2Z"
    fittings = (a.part(rect(2.6, 18.4, 3, 2.8, 0.4), GOLD, sheen=False) + a.part(rect(12.6, 18.4, 3, 2.8, 0.4), GOLD, sheen=False)
                + a.part(rect(2.6, 10.8, 12.9, 1.6, 0.3), GOLD, sheen=False))
    return a.done(a.part(body_side, darker(wood, 0.25), sheen=False) + a.part(lid_side, darker(wood, 0.15), sheen=False)
                  + a.part(body, wood) + a.part(lid, lighter(wood, 0.08)) + fittings
                  + a.line("M6.2 5.4V10.8M12 5V10.8", GOLD_D, 0.9)
                  + a.part(rect(7.4, 11.6, 3.4, 4.3, 0.7), GOLD) + a.fill("M9.1 12.9a.75.75 0 0 0-.4 1.4v.9h.8v-.9a.75.75 0 0 0-.4-1.4Z", DARK))


def wow_bank_chest() -> str:
    # Achievement_GuildPerk_MobileBanking: open chest heaped with gold; coins drawn as a gold mound with
    # thin dark-gold coin rims, not separate black-outlined discs
    a = Art()
    wood = "#7A4A26"
    lid_inside = "M4.4 12L6.8 4.4H17.2L19.6 12Z"
    mound = "M4.4 12.4C5.2 8.8 8.4 6.8 12 6.8s6.8 2 7.6 5.6Z"
    rims = "".join(a.line(circle(x, y, 1.45), GOLD_D, 0.6) for x, y in ((7.6, 11), (10.6, 9.6), (13.6, 9.4), (16.4, 10.8), (12, 7.9), (9, 11.6), (14.8, 11.7)))
    return a.done(a.part(lid_inside, darker(wood, 0.3), sheen=False) + a.line("M7.2 6.2H16.8", GOLD, 0.9)
                  + a.part(mound, GOLD) + rims + a.part(rect(3.2, 12, 17.6, 9, 1), wood)
                  + a.part(rect(2.9, 12, 18.2, 1.8, 0.4), GOLD, sheen=False) + a.part(rect(10.3, 13.6, 3.4, 4, 0.7), GOLD)
                  + a.part(rect(2.8, 18.4, 3, 2.8, 0.4), GOLD, sheen=False) + a.part(rect(18.2, 18.4, 3, 2.8, 0.4), GOLD, sheen=False))


# ---------------------------------------------------------------- rev 7: remaining icons drawn from WoW icons
# Collections <- Ability_Mount_RidingHorse      Professions <- Trade_Blacksmithing   QoL <- Trade_Engineering
# Reputation  <- Achievement_Reputation_01      Vendor <- INV_Misc_Bag_10            Discovery <- INV_Misc_Spyglass_02
# Unknown     <- INV_Misc_QuestionMark          Promotion <- INV_Holiday_Christmas_Present_01
# Quest       <- INV_Scroll_03                  Location <- WoW gold waypoint pin    TCG <- INV_Misc_Ticket_Tarot

HORSE = "#9A5A2E"
SKIN = "#E3AE86"
GIFT_GREEN = "#3F8F3A"
TAROT = "#6B3FA8"


def horse_head() -> str:
    a = Art()
    head = ("M19.5 21.5C19.6 16.5 18.8 12.6 16.6 8.6L15.6 4.4 14.1 6.2 13 3.4 11.8 6.8C9.6 8 7.6 10.2 5.6 12.6"
            "c-.8 1-.9 2.4.1 3.2.9.7 2.2.7 3.4.3l3.4-1.2c.2 2.4-.4 4.6-1.8 7.2Z")
    mane = "M16.6 8.6C18.8 12.6 19.6 16.5 19.5 21.5h-2.4c.2-4.6-.6-8.4-2.6-12.2L15.6 4.4Z"
    return a.done(a.part(head, HORSE) + a.part(mane, darker(HORSE, 0.45), edge=False, sheen=False)
                  + a.line("M8.6 10.6L12.4 14.2M7.2 13.4L9.6 12", GOLD, 0.8)
                  + a.fill("M10.6 9.4a.8.6 0 1 0 1.6 0 .8.6 0 1 0-1.6 0Z", DARK) + a.fill(circle(6.7, 13.9, 0.5), DARK))


def anvil_hammer() -> str:
    a = Art()
    anvil_d = "#6E7682"
    top = "M3 9H21V11.2a3 3 0 0 1-3 3H11.5c-1.6 0-3-1-3.4-2.2C5.6 11.6 3.6 10.6 3 9Z"
    return a.done(a.part(rect(8.4, 18, 11, 2.8, 0.8), darker(anvil_d, 0.1)) + a.part("M11.6 14.2L10.6 18H17.4L16.4 14.2Z", darker(anvil_d, 0.2), sheen=False)
                  + a.part(top, anvil_d, light=0.3) + a.rod("M11 8.2L19.2 2.6", WOOD, 1.6)
                  + a.part(rot_rect(9.4, 7.4, 5, 2.6, 55), STEEL))


def gear_gold() -> str:
    a = Art()
    pts = []
    for i in range(10):
        ang = i * 36
        for d, r in ((ang - 12, 7.4), (ang - 7, 10), (ang + 7, 10), (ang + 12, 7.4)):
            t = math.radians(d - 90)
            pts.append(f"{n(12 + r * math.cos(t))} {n(12 + r * math.sin(t))}")
    gear = "M" + "L".join(pts) + "Z"
    return a.done(a.part(gear, GOLD) + a.line(circle(12, 12, 5.2), GOLD_D, 1.1) + a.part(circle(12, 12, 2.6), DARK, sheen=False))


def handshake() -> str:
    # Achievement_Reputation_01: short sleeves from the bottom corners, two large hands clasped in the middle;
    # the right hand closes over the left (finger bands), the left thumb lies on top
    a = Art()
    left_hand = "M4.6 16.4C6.6 12.6 10 9.8 14.4 9.2c1.6-.2 2.6 1.4 1.6 2.6L12 16.6c-1.4 1.6-3.8 2-5.4.8Z"
    right_hand = "M19.4 16.6C17.6 12.8 14 10.2 9.6 9.8c-1.6-.1-2.4 1.6-1.4 2.7l4.2 4.4c1.4 1.5 3.8 1.7 5.4.4Z"
    return a.done(a.rod("M2.6 21.4L6.4 17.4", CLOTH_BLUE, 5, cap="butt") + a.rod("M21.4 21.4L17.6 17.4", GOLD, 5, cap="butt")
                  + a.part(left_hand, darker(SKIN, 0.1)) + a.part(right_hand, SKIN)
                  + a.line("M10.4 11.2l2.6 2.8M12.1 10.6l2.5 2.7M13.8 10.5l2.2 2.4", darker(SKIN, 0.32), 0.75, ' stroke-linecap="round"')
                  + a.rod("M7.2 13.6c1.6-1.7 3.6-2.6 5.8-2.6", darker(SKIN, 0.05), 1.3))


def drawstring_sack() -> str:
    a = Art()
    tan = "#C99A5E"
    body = "M12 7.2c-4.6 0-8 3.6-8 8 0 3.4 3.2 5.6 8 5.6s8-2.2 8-5.6c0-4.4-3.4-8-8-8Z"
    ruffle = "M9.4 7.8L8 3.8c1.4.7 2.7.7 4 0 1.3.7 2.6.7 4 0l-1.4 4Z"
    return a.done(a.part(ruffle, lighter(tan, 0.08)) + a.part(body, tan) + a.rod("M9 7.8h6", LEATHER_D, 1.4)
                  + a.rod("M14.8 7.8c1.4.6 2.4 1.8 2.6 3.6", LEATHER_D, 1.1)
                  + a.line("M7.2 15.6c.6 2 2.4 3 4.8 3", lighter(tan, 0.35), 0.9, ' stroke-linecap="round"'))


def spyglass() -> str:
    a = Art()
    return a.done(a.part(rot_rect(6.6, 17.4, 3.6, 2.8, -45), GOLD) + a.part(rot_rect(9.6, 14.4, 5.4, 3.6, -45), LEATHER)
                  + a.part(rot_rect(14.6, 9.4, 7.4, 4.6, -45), GOLD)
                  + a.part(rot_rect(18.4, 5.6, 1.6, 5.4, -45), darker(GOLD, 0.15), sheen=False)
                  + a.fill(rot_rect(18.9, 5.1, 0.8, 4.2, -45), "#9ED3E6")
                  + a.line("M12.2 13.4l1.6-1.6M16 9.6l1.6-1.6", GOLD_D, 0.8))


def red_question() -> str:
    a = Art()
    q = "M8.2 8.4a3.8 3.8 0 1 1 5.6 3.4c-1 .6-1.8 1.6-1.8 2.8v.8"
    return a.done(a.rod(q, "#D23A2E", 3.4) + a.part(circle(12, 19.4, 2), "#D23A2E"))


def present() -> str:
    a = Art()
    bow = ("M12 7.4C10.3 3.8 6.7 3.6 7.1 5.8 7.4 7.4 12 7.4 12 7.4Z", "M12 7.4c1.7-3.6 5.3-3.8 4.9-1.6-.3 1.6-4.9 1.6-4.9 1.6Z")
    return a.done(a.part(rect(4.5, 11, 15, 9.6, 1), GIFT_GREEN) + a.part(rect(3, 7.4, 18, 4, 1), lighter(GIFT_GREEN, 0.08))
                  + a.part(rect(10.8, 7.4, 2.4, 13.2, 0), CLOTH_RED, sheen=False) + a.part(bow[0], CLOTH_RED) + a.part(bow[1], CLOTH_RED))


def rolled_scroll() -> str:
    # INV_Scroll_03: a fat rolled sheet on the diagonal, spiral ends, red ribbon band with a wax seal
    a = Art()
    ends = "".join(f'<g transform="rotate(-45 {n(x)} {n(y)})">' + a.part(f"M{n(x - 1.6)} {n(y)}a1.6 3.6 0 1 0 3.2 0a1.6 3.6 0 1 0-3.2 0Z", PARCH_D, sheen=False)
                   + a.line(f"M{n(x - 0.6)} {n(y)}a.6 1.6 0 1 0 1.2 0", darker(PARCH_D, 0.35), 0.6) + "</g>"
                   for x, y in ((6.7, 17.3), (17.3, 6.7)))
    return a.done(a.part(rot_rect(12, 12, 15, 7.2, -45), PARCH) + ends
                  + a.part(rot_rect(12, 12, 2.2, 7.8, -45), CLOTH_RED, sheen=False) + a.part(circle(13.6, 13.6, 2.2), darker(CLOTH_RED, 0.12)))


def gold_pin() -> str:
    a = Art()
    pin = "M12 21.5s-6.8-6.4-6.8-11.6a6.8 6.8 0 0 1 13.6 0c0 5.2-6.8 11.6-6.8 11.6Z"
    return a.done(a.part(pin, GOLD) + a.part(circle(12, 9.8, 2.5), darker(GOLD, 0.45), sheen=False))


def tarot_cards() -> str:
    a = Art()
    back = f'<g transform="rotate(-13 9 11.5)">{a.part(rect(4.2, 4.5, 9.6, 13.6, 1.4), darker(TAROT, 0.15))}</g>'
    front = (a.part(rect(9.8, 6.2, 9.6, 13.6, 1.4), TAROT) + a.line(rect(11.1, 7.5, 7, 11, 0.8), GOLD, 0.8)
             + a.line("M14.6 13a1 1 0 1 1 1 1 2 2 0 1 1-2-2 3 3 0 1 1 3 3", "#E8D7FF", 0.8))
    return a.done(back + f'<g transform="rotate(9 14.6 13)">{front}</g>')



# ---------------------------------------------------------------- rev 8: peer feedback (portraits, bag/storage/bank from WoW art, boss skull)
# Characters <- WoW unit-frame portraits (gold ring), one Alliance human and one Horde orc
# Bag        <- INV_Misc_Bag_08 three-quarter pack       Storage <- INV_Box_01 light wood chest with gold trim
# Bank       <- Interface/Minimap/Tracking/Banker (two tied money sacks)   PvE <- Tormentors-Boss (horned boss skull)

ALLIANCE_BG = "#1F4E8C"
HORDE_BG = "#8C1F1F"
ORC = "#6E9A3E"


def _portrait(a: Art, cx: float, cy: float, r: float, bg: str, face: str) -> str:
    inner = circle(cx, cy, r - 1)
    cid = a.clip(inner)
    return (a.part(circle(cx, cy, r), GOLD) + a.part(inner, bg, sheen=False, light=0.25, dark=0.2)
            + f'<g clip-path="url(#{cid})">{face}</g>' + a.line(inner, darker(GOLD, 0.45), 0.7))


def faction_portraits() -> str:
    a = Art()
    # Alliance human (back, top left): brown hair and beard, blue tunic shoulders; faces fill the frame
    human = (a.fill("M1.8 15.2a6.2 4.6 0 0 1 12.4 0Z", "#3B6DB3")
             + a.fill("M4.8 7.6a3.2 3.6 0 1 0 6.4 0 3.2 3.6 0 1 0-6.4 0Z", "#E3AE86")
             + a.fill("M4.6 7.2c.2-2.6 1.6-4 3.4-4s3.2 1.4 3.4 4c-.8-1-2-1.6-3.4-1.6S5.4 6.2 4.6 7.2Z", "#6B4423")
             + a.fill("M5 8.8c.4 2.4 1.6 3.6 3 3.6s2.6-1.2 3-3.6c-.6.8-1.6 1.2-3 1.2S5.6 9.6 5 8.8Z", "#6B4423")
             + a.fill(circle(6.9, 7.5, 0.4), DARK) + a.fill(circle(9.1, 7.5, 0.4), DARK))
    # Horde orc (front, bottom right): green skin, black topknot, white tusks, red armour shoulders
    orc = (a.fill("M9.6 23.4a6.4 4.6 0 0 1 12.8 0Z", "#7A2B22")
           + a.fill("M12.6 15.4a3.4 3.6 0 1 0 6.8 0 3.4 3.6 0 1 0-6.8 0Z", ORC)
           + a.fill("M14.8 10.8c.8-1.6 1.8-2 2.8-1.7-.3.8-.2 1.6.4 2.3Z", DARK)
           + a.fill("M14.2 17.6l.6-2 .6 2ZM16.6 17.6l.6-2 .6 2Z", "#F3ECDC")
           + a.fill("M12.6 14.6l-1.8-1.2 2 .1ZM19.4 14.6l1.8-1.2-2 .1Z", ORC)
           + a.fill("M14 14.6l1.6.5M16.4 15.1l1.6-.5", DARK) + a.line("M14 14.4l1.6.6M16.4 15l1.6-.6", DARK, 0.6)
           + a.fill(circle(14.8, 15.4, 0.4), "#FFD54A") + a.fill(circle(17.2, 15.4, 0.4), "#FFD54A"))
    return a.done(_portrait(a, 8, 8, 6.4, ALLIANCE_BG, human) + _portrait(a, 16, 16, 6.4, HORDE_BG, orc))


def wow_bag_34() -> str:
    a = Art()
    tan = "#B07A3E"
    body = "M5 9.6C5 7.4 6.8 6 9 6h6.4c2.4 0 4.2 1.6 4.2 3.8V18c0 1.9-1.6 3.2-3.6 3.2H8.2C6.4 21.2 5 19.8 5 18Z"
    side = "M17.4 6.4c1.4.5 2.2 1.8 2.2 3.4V18c0 1.6-1 2.8-2.4 3.1Z"
    flap = "M5 9.6C5 7.4 6.8 6 9 6h6.4c2.4 0 4.2 1.6 4.2 3.8v1.8c-1.6 2-4.4 3.2-7.4 3.2S6.4 13.6 5 11.6Z"
    return a.done(a.rod("M8.4 6.2C8.4 3.4 15.8 3.4 15.8 6.2", darker(tan, 0.35), 1.5) + a.part(body, tan)
                  + a.fill(side, darker(tan, 0.22)) + a.part(flap, lighter(tan, 0.08))
                  + a.line("M6.2 12.4c1.8 1.4 3.8 2 6 2s4.2-.6 6-2", darker(tan, 0.35), 0.6, ' stroke-dasharray="0.9 0.8"')
                  + a.rod("M12.1 13.2V19.8", darker(tan, 0.3), 1.6, cap="butt")
                  + a.part(rect(10.1, 12.4, 4, 3.6, 0.6), STEEL) + a.fill(rect(11.3, 13.4, 1.6, 1.6, 0.2), darker(tan, 0.35)))


def wow_box() -> str:
    a = Art()
    wood = "#C08A4A"
    front = "M3 10H15.4V20.8H3Z"
    top = "M3 10L8.6 5.2H21L15.4 10Z"
    side = "M15.4 10L21 5.2V16L15.4 20.8Z"
    trims = (a.part(rect(2.6, 9.4, 13.2, 1.6, 0.3), GOLD, sheen=False) + a.part(rect(2.6, 19.6, 13.2, 1.6, 0.3), GOLD, sheen=False)
             + a.part(rect(2.6, 9.4, 1.6, 11.8, 0.3), GOLD, sheen=False) + a.part(rect(14.2, 9.4, 1.6, 11.8, 0.3), GOLD, sheen=False))
    return a.done(a.part(side, darker(wood, 0.2), sheen=False) + a.part(top, lighter(wood, 0.1)) + a.part(front, wood)
                  + a.line("M5 13.6H13.4M5 16.8H13.4", darker(wood, 0.3), 0.7) + trims
                  + a.part(rect(7.6, 12.6, 3.2, 3.8, 0.6), GOLD))


def banker_sacks() -> str:
    a = Art()
    tan = "#C9A06A"

    def sack(dx: float, dy: float, sc: float) -> str:
        body = (f"M{n(dx + 12 * sc)} {n(dy + 8 * sc)}c{n(-4.2 * sc)} 0 {n(-7 * sc)} {n(3.4 * sc)} {n(-7 * sc)} {n(7.2 * sc)}"
                f"c0 {n(3 * sc)} {n(2.8 * sc)} {n(4.8 * sc)} {n(7 * sc)} {n(4.8 * sc)}s{n(7 * sc)} {n(-1.8 * sc)} {n(7 * sc)} {n(-4.8 * sc)}"
                f"c0 {n(-3.8 * sc)} {n(-2.8 * sc)} {n(-7.2 * sc)} {n(-7 * sc)} {n(-7.2 * sc)}Z")
        neck = (f"M{n(dx + 9.8 * sc)} {n(dy + 8.6 * sc)}L{n(dx + 8.8 * sc)} {n(dy + 5 * sc)}c{n(1.1 * sc)} {n(0.6 * sc)} {n(2.1 * sc)} {n(0.6 * sc)} {n(3.2 * sc)} 0"
                f"c{n(1.1 * sc)} {n(0.6 * sc)} {n(2.1 * sc)} {n(0.6 * sc)} {n(3.2 * sc)} 0L{n(dx + 14.2 * sc)} {n(dy + 8.6 * sc)}Z")
        tie = f"M{n(dx + 9.6 * sc)} {n(dy + 8.4 * sc)}h{n(4.8 * sc)}"
        return a.part(neck, lighter(tan, 0.06)) + a.part(body, tan) + a.rod(tie, CLOTH_RED, 1.2 * sc)

    return a.done(sack(-2.4, -2.0, 0.82) + sack(4.6, 3.4, 0.82))


def boss_skull() -> str:
    a = Art()
    bone = "#D9CDB0"
    horns = ("M6.4 8.6C4 7.8 2.6 5.6 2.8 2.8c1.2 2 2.8 2.9 4.8 3.1Z", "M17.6 8.6c2.4-.8 3.8-3 3.6-5.8-1.2 2-2.8 2.9-4.8 3.1Z")
    cranium = "M12 4C8 4 5.2 6.8 5.2 10.6c0 2.2.9 3.9 2.3 5.1l.9 3.3h7.2l.9-3.3c1.4-1.2 2.3-2.9 2.3-5.1C18.8 6.8 16 4 12 4Z"
    jaw = "M8.6 18.6h6.8l-.8 3h-5.2Z"
    sockets = "M7.6 11.2l3.4.8-.6 2.4c-1.6.2-2.6-.9-2.8-3.2ZM16.4 11.2l-3.4.8.6 2.4c1.6.2 2.6-.9 2.8-3.2Z"
    return a.done(a.part(horns[0], "#5B4A3A") + a.part(horns[1], "#5B4A3A") + a.part(cranium, bone, dark=0.3)
                  + a.part(jaw, darker(bone, 0.15), sheen=False) + a.fill(sockets, DARK)
                  + a.fill(circle(9.4, 12.9, 0.75), "#FF4A2A") + a.fill(circle(14.6, 12.9, 0.75), "#FF4A2A")
                  + a.fill("M12 14.6l.9 1.8h-1.8Z", DARK) + a.line("M10.4 18.6V21.4M12 18.6V21.6M13.6 18.6V21.4", darker(bone, 0.5), 0.6)
                  + a.line("M12 4.4V7.4", darker(bone, 0.3), 0.6))


ART = {
    # name -> builder (all colored)
    "FactionPortraits": faction_portraits,
    "Handshake": handshake,
    "BossSkull": boss_skull,
    "CrossedSwords": crossed_swords,
    "BarChart": bar_chart,
    "HorseHead": horse_head,
    "AnvilHammer": anvil_hammer,
    "Info": info,
    "GearGold": gear_gold,
    "WowBag34": wow_bag_34,
    "WowBox": wow_box,
    "MoneySacks": banker_sacks,
    "Tabard": tabard,
    "Campfire": campfire,
    "Checklist": checklist,
    "Currency": currency_coins,
    "PlateArmor": plate_armor,
    "WowLootChest": wow_loot_chest,
    "RolledScroll": rolled_scroll,
    "DrawstringSack": drawstring_sack,
    "Paw": paw,
    "Trophy": achievement,
    "Calendar": calendar,
    "Present": present,
    "TarotCards": tarot_cards,
    "Cart": cart,
    "Spyglass": spyglass,
    "Tent": tent,
    "RedQuestion": red_question,
    "Sparkle": sparkle,
    "GoldPin": gold_pin,
}
