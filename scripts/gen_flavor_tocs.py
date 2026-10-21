#!/usr/bin/env python3
"""Generate / check flavor TOCs (e.g. WarbandNexus_Camelot.toc) from WarbandNexus.toc.

Flavor TOCs ship beside the retail TOC in the same package. Their file list must never drift from
the main TOC, so they are generated from it instead of being edited by hand: same header (with a
per-flavor Interface / Notes), same file list, plus per-flavor extra files.

    python3 scripts/gen_flavor_tocs.py           # (re)generate every flavor TOC that is ready
    python3 scripts/gen_flavor_tocs.py --check   # fail if an existing flavor TOC is out of sync

--check validates every WarbandNexus_*.toc on disk. With none present (the WoW: Forever port has not
started) there is nothing to drift and it passes; generation refuses until the flavor's open
decisions are filled in below, so an incomplete TOC can never ship.
Plan: ~/.claude/plans/staged-wiggling-heron.md (Phase 1, steps 3-4).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN_TOC = ROOT / "WarbandNexus.toc"

# Per-flavor overrides. None = decision still open; generation refuses until it is set.
FLAVORS: dict[str, dict] = {
    "Camelot": {
        # WoW: Forever. 16001 is the beta value (warcraft.wiki.gg Patch_1.60.1); re-verify at launch.
        "interface": "16001",
        # Forever has no Warband bank, so the retail Notes ("Modern Warband bank management ...")
        # must not be reused. Fill in the player-facing text before generating.
        "notes": None,
        # Sets ns.FLAVOR_HINT before anything reads it, so it is the first file the TOC loads
        # (ahead of libraries, locales and Core.lua).
        "extra_files_first": ["Modules\\Flavor_Camelot.lua"],
    },
}


def read_text(path: Path) -> tuple[str, str]:
    raw = path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), newline


def render(flavor: str, spec: dict, main_text: str) -> str:
    out: list[str] = []
    inserted = False
    for line in main_text.split("\n"):
        if line.startswith("## Interface:"):
            line = "## Interface: " + spec["interface"]
        elif line.startswith("## Notes:") and spec.get("notes"):
            line = "## Notes: " + spec["notes"]
        elif not inserted and line.strip() and not line.startswith("#"):
            # First file entry of the main TOC: the flavor's extra files load before it.
            for extra in spec.get("extra_files_first", []):
                out.append(extra)
            inserted = True
        out.append(line)
    return "\n".join(out)


def missing_decisions(spec: dict) -> list[str]:
    problems = [f"'{k}' is not decided yet" for k, v in spec.items() if v is None]
    for extra in spec.get("extra_files_first", []):
        if not (ROOT / extra.replace("\\", "/")).is_file():
            problems.append(f"extra file {extra} does not exist")
    return problems


def check() -> int:
    main_text, _ = read_text(MAIN_TOC)
    flavor_tocs = sorted(p for p in ROOT.glob("WarbandNexus_*.toc"))
    if not flavor_tocs:
        print("gen_flavor_tocs: no flavor TOCs (WarbandNexus_*.toc) present - nothing to check.")
        return 0
    failed = False
    for toc in flavor_tocs:
        flavor = toc.stem.split("_", 1)[1]
        spec = FLAVORS.get(flavor)
        if spec is None:
            print(f"FAIL {toc.name}: unknown flavor '{flavor}' (add it to FLAVORS and generate it).")
            failed = True
            continue
        for problem in missing_decisions(spec):
            print(f"FAIL {toc.name}: {problem}.")
            failed = True
        actual, _ = read_text(toc)
        expected = render(flavor, spec, main_text)
        if actual != expected:
            a, e = actual.split("\n"), expected.split("\n")
            first = next((i for i in range(max(len(a), len(e)))
                          if (a[i] if i < len(a) else None) != (e[i] if i < len(e) else None)), None)
            got = a[first] if first is not None and first < len(a) else "<end of file>"
            want = e[first] if first is not None and first < len(e) else "<end of file>"
            print(f"FAIL {toc.name}: out of sync with WarbandNexus.toc at line {(first or 0) + 1}: "
                  f"got {got!r}, expected {want!r}. Run python3 scripts/gen_flavor_tocs.py.")
            failed = True
        else:
            print(f"ok   {toc.name} in sync with WarbandNexus.toc")
    return 1 if failed else 0


def generate() -> int:
    main_text, newline = read_text(MAIN_TOC)
    status = 0
    for flavor, spec in FLAVORS.items():
        target = ROOT / f"WarbandNexus_{flavor}.toc"
        problems = missing_decisions(spec)
        if problems:
            print(f"skip {target.name}: " + "; ".join(problems))
            status = 1
            continue
        target.write_bytes(render(flavor, spec, main_text).replace("\n", newline).encode("utf-8"))
        print(f"wrote {target.name}")
    return status


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv[1:] else generate())
