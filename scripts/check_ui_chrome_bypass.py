#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Flag ad-hoc SetColorTexture divider/stripe usage outside Factory chrome allowlist.

Run from repo root:  python scripts/check_ui_chrome_bypass.py

See docs/CLASSIC-THEME-GAPS-FACTORY.md (Governance section).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Factory-owned chrome; tab/popup code should call CreateThemeDivider / ApplyBorder instead.
ALLOWLIST_PREFIXES = (
    "Modules/UI/SharedWidgets",
    "Modules/UI/FramePoolFactory.lua",
    "Modules/UI/WindowFactory.lua",
    "Modules/UI/NotificationToastFactory.lua",
    "Modules/UI/GearUI_Chrome.lua",
    "Modules/UI/TooltipFactory.lua",
    "Modules/Profiler",
    "Modules/VaultButton_Core.lua",
    "Modules/VaultButton_Table.lua",
    "Modules/VaultButton_SavedInstancesUI.lua",
    "Modules/UI/StatisticsUI.lua",
    "Modules/UI/PvEUI_VaultGrid.lua",
)

# Whole files exempt (event hosts, fullscreen FX, Blizzard template shims).
ALLOWLIST_FILES = {
    "Modules/NotificationManager.lua",  # screen flash fullscreen host
    "Modules/NotificationManager_ToastFx.lua",
    "Modules/NotificationManager_ToastChrome.lua",
}

SKIP_DIRS = {"libs", "build", ".git"}

SET_COLOR_RE = re.compile(r"SetColorTexture\s*\(")
INLINE_ALLOW_RE = re.compile(r"WN_CHROME_ALLOW\b")


def is_allowlisted(rel_posix: str) -> bool:
    if rel_posix in ALLOWLIST_FILES:
        return True
    for prefix in ALLOWLIST_PREFIXES:
        if rel_posix.startswith(prefix) or rel_posix == prefix:
            return True
    return False


def scan_file(path: Path) -> list[tuple[int, str]]:
    rel = path.relative_to(ROOT).as_posix()
    if is_allowlisted(rel):
        return []
    hits: list[tuple[int, str]] = []
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return hits
    for i, line in enumerate(lines, start=1):
        if not SET_COLOR_RE.search(line):
            continue
        if INLINE_ALLOW_RE.search(line):
            continue
        # Gradients, fills, badges, and icon tints are out of scope for this divider gate.
        stripped = line.strip()
        if any(
            token in stripped
            for token in (
                "SetGradient",
                "SetVertexColor",
                "SetBackdropColor",
                "highlight",
                "Highlight",
                "badge",
                "Badge",
                "icon",
                "Icon",
                "vertex",
                "Vertex",
                "headerBar",
                "row.headerBar",
                "zebra",
                "Zebra",
                "pillBg",
                "sunHalo",
                "sunCore",
                "wash",
                "vignette",
                "flash",
                "grad",
                "gradient",
                "Quality",
                "quality",
                "ReadyCheck",
                "status",
                "chip",
                "progress",
                "Progress",
            )
        ):
            continue
        # Thin rules / dividers: width or height 1, or variable names suggesting separators.
        if re.search(r"\b(div|Div|sep|Sep|split|Split|rule|Rule|midDiv|colDiv|stackDiv|rail|Rail|stripe|Stripe)\b", line):
            hits.append((i, stripped))
            continue
        if re.search(r"SetWidth\s*\(\s*1\s*\)|SetHeight\s*\(\s*1\s*\)", stripped):
            hits.append((i, stripped))
    return hits


def main() -> int:
    errors: list[str] = []
    for path in sorted(ROOT.glob("Modules/**/*.lua")):
        parts = {p.lower() for p in path.parts}
        if parts & SKIP_DIRS:
            continue
        for line_no, text in scan_file(path):
            rel = path.relative_to(ROOT).as_posix()
            errors.append(f"{rel}:{line_no}: {text}")

    if errors:
        print("UI chrome bypass check FAILED (use Factory:CreateThemeDivider or mark WN_CHROME_ALLOW):", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        print(f"\n{len(errors)} hit(s).", file=sys.stderr)
        return 1

    print("UI chrome bypass check OK (no flagged divider SetColorTexture in tab/popup paths).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
