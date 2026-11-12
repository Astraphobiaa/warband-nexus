#!/usr/bin/env python3
"""Markup-token gate: no new bare `|cff` colors under Modules/UI.

Roughly three quarters of the colored text in this addon is inline `|cff` markup
spliced into a localized string rather than a SetTextColor call. The RGBA getters
in SharedWidgets_Theme cannot serve that, so files used to bridge the gap with
local `*Hex()` shims behind hardcoded fallbacks -- the same role rendered `ffd700`
in one tab and `ffcc00` in the next, and a theme toggle reached neither.

`ns.UI_HEX` is the markup layer those shims were standing in for: one role ->
markup table, re-synced in place on every theme change. This gate keeps new bare
literals from being added while the recorded backlog is migrated onto it.

Baseline, same contract as the forward-ref gate: existing hits are recorded per
file, the gate fails only on counts ABOVE the recorded number, and a file whose
count drops is reported so the win can be locked in with --update-baseline.
Counting per file rather than per line keeps the baseline stable when unrelated
edits move lines around.

Usage:
    python scripts/check_markup_tokens.py
    python scripts/check_markup_tokens.py --update-baseline
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI_DIR = ROOT / "Modules" / "UI"
BASELINE = Path(__file__).resolve().parent / "markup_tokens_baseline.txt"

# These files ARE the palette: they define the markup the rest of the addon reads.
EXEMPT = {
    "SharedWidgets_Theme.lua",
    "SharedWidgets_ClassicTheme.lua",
}

# `|cff` followed by six hex digits. `|cnNAME:` (Blizzard's named color escape) and
# `|c%02x...` built from a getter are not literals and are not matched.
LITERAL = re.compile(r"\|cff([0-9a-fA-F]{6})")

# Not theme ink, so not theme debt:
#   the Blizzard item-quality ramp, which M+ score tiers reuse as a rating scale --
#   remapping those to theme roles would destroy the meaning players read them by;
#   and pure black, which is only ever used as a text shadow behind another string.
# Everything else under Modules/UI belongs to a role in `ns.UI_HEX`.
EXEMPT_HEX = {
    "ff8000",  # legendary
    "a335ee",  # epic
    "0070dd",  # rare
    "1eff00",  # uncommon
    "9d9d9d",  # poor
    "c7c7cf",  # money: silver
    "eda55f",  # money: copper
    "000000",  # text shadow
}


def scan() -> dict[str, int]:
    counts: dict[str, int] = {}
    for path in sorted(UI_DIR.rglob("*.lua")):
        if path.name in EXEMPT:
            continue
        found = LITERAL.findall(path.read_text(encoding="utf-8"))
        hits = sum(1 for h in found if h.lower() not in EXEMPT_HEX)
        if hits:
            counts[path.relative_to(ROOT).as_posix()] = hits
    return counts


def read_baseline() -> dict[str, int]:
    if not BASELINE.exists():
        return {}
    out: dict[str, int] = {}
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rel, _, count = line.rpartition("|")
        out[rel] = int(count)
    return out


def write_baseline(counts: dict[str, int]) -> None:
    header = (
        "# Known bare `|cff` literals under Modules/UI, one `path|count` per line.\n"
        "# The gate fails only when a file's count RISES above its recorded number,\n"
        "# so new literals break CI while this backlog is migrated onto `ns.UI_HEX`.\n"
        "# Each hit is a color that does not follow the theme: it keeps its dark-mode\n"
        "# value on light surfaces, where several of these measure under 2:1.\n"
        "# Fix one by reading `ns.UI_HEX.<role>` at the call site -- never by adding\n"
        "# a fallback literal -- then rerun with --update-baseline to lock the drop in.\n"
        "# Never raise a number by hand to silence a new finding.\n"
    )
    body = "\n".join(f"{rel}|{n}" for rel, n in sorted(counts.items()))
    BASELINE.write_text(header + body + "\n", encoding="utf-8")


DECL = "local HEX = ns.UI_HEX"
USE = re.compile(r"\bHEX\.")
THEME_REL = "Modules/UI/SharedWidgets_Theme.lua"


def toc_order() -> dict[str, int]:
    """File -> load position, so `declared before the theme` can be caught."""
    order: dict[str, int] = {}
    toc = ROOT / "WarbandNexus.toc"
    if not toc.exists():
        return order
    pos = 0
    for line in toc.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.lower().endswith(".lua"):
            order[line.replace("\\", "/")] = pos
            pos += 1
    return order


def check_declarations() -> list[tuple[str, str]]:
    """`HEX.role` compiles to a global read, so none of these raise at load time --
    they raise the first time the line runs, as `attempt to index global 'HEX'`.
    Neither luac nor the forward-ref gate sees them, so they are checked here."""
    order = toc_order()
    theme_pos = order.get(THEME_REL)
    problems: list[tuple[str, str]] = []

    for path in sorted(UI_DIR.rglob("*.lua")):
        rel = path.relative_to(ROOT).as_posix()
        if path.name in EXEMPT:
            continue
        text = path.read_text(encoding="utf-8")
        uses = [m.start() for m in USE.finditer(text)]
        if not uses:
            continue
        if DECL not in text:
            problems.append((rel, "uses HEX. but never declares `local HEX = ns.UI_HEX`"))
            continue
        if min(uses) < text.index(DECL):
            problems.append((rel, "declares `local HEX` BELOW its first use"))
        pos = order.get(rel)
        if pos is not None and theme_pos is not None and pos < theme_pos:
            problems.append(
                (rel, "loads before SharedWidgets_Theme, so ns.UI_HEX is nil at chunk level")
            )
    return problems


def main() -> int:
    if not UI_DIR.is_dir():
        print(f"Markup-token gate: {UI_DIR} not found.", file=sys.stderr)
        return 1

    current = scan()

    # Not baselined: a misplaced declaration is always a bug, never accepted debt.
    decl_problems = check_declarations()
    if decl_problems:
        print("=== Broken `ns.UI_HEX` declarations ===\n", file=sys.stderr)
        for rel, why in decl_problems:
            print(f"  {rel}: {why}", file=sys.stderr)
        print(
            f"\nMarkup-token gate FAILED: {len(decl_problems)} broken declaration(s). "
            f"Declare `local HEX = ns.UI_HEX` directly under the `local _, ns = ...` line, "
            f"in a file that loads after SharedWidgets_Theme.",
            file=sys.stderr,
        )
        return 1

    if "--update-baseline" in sys.argv:
        write_baseline(current)
        total = sum(current.values())
        print(
            f"Baseline written: {BASELINE.relative_to(ROOT)} "
            f"({len(current)} file(s), {total} literal(s))."
        )
        return 0

    baseline = read_baseline()

    regressions = []
    for rel, n in sorted(current.items()):
        was = baseline.get(rel, 0)
        if n > was:
            regressions.append((rel, was, n))

    improved = []
    for rel, was in sorted(baseline.items()):
        now = current.get(rel, 0)
        if now < was:
            improved.append((rel, was, now))

    if improved:
        print(
            f"=== {len(improved)} file(s) improved -- rerun with --update-baseline "
            f"to lock the fix in ===\n"
        )
        for rel, was, now in improved:
            print(f"  FIXED {rel}: {was} -> {now}")
        print()

    if regressions:
        print("=== NEW bare |cff literals (above baseline) ===\n", file=sys.stderr)
        for rel, was, now in regressions:
            print(f"  {rel}: {was} -> {now}", file=sys.stderr)
        print(
            f"\nMarkup-token gate FAILED: {len(regressions)} file(s) above baseline. "
            f"Read `ns.UI_HEX.<role>` at the call site instead of writing a literal.",
            file=sys.stderr,
        )
        return 1

    total = sum(current.values())
    print(
        f"Markup-token gate OK ({total} known literal(s) across "
        f"{len(current)} file(s) in baseline, 0 new)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
