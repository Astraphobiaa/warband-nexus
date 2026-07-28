#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Will the addon actually load? Compile every shipped Lua file and verify the TOC.

Run from repo root:  python scripts/check_lua_compile.py

Catches the two failure modes that hard-brick the addon at load time, both of
which every other gate in this repo misses:

  1. Syntax errors and the Lua chunk ceilings (200 locals, 60 upvalues, 255
     upvalue/constant limits) -- reported by luac itself, not by a heuristic.
  2. A TOC entry whose case does not match the file on disk. Windows and macOS
     load it anyway; the Linux packager that builds the CurseForge zip does not,
     so the break only shows up in the published release.

luac version matters: the game runs Lua 5.1. luac5.1 is the faithful check. A
newer luac still catches syntax errors and the chunk ceilings, but it ACCEPTS
5.2+ syntax that the game rejects, so the 5.2+ scan below runs to cover the gap.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_lua_forward_refs import strip_block_comments, strip_comment_and_strings  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "WarbandNexus.toc"

# Preference order: a real 5.1 compiler first, then anything that can parse Lua.
LUAC_CANDIDATES = ("luac5.1", "luac51", "luac-5.1", "luac")

# Constructs the 5.1 VM rejects outright. Deliberately limited to the
# unambiguous ones: bitwise operators and `//` overlap with WoW colour escapes
# and URLs, so scanning for them produced only false alarms.
LUA52_PATTERNS = (
    (re.compile(r"(?<![\w.])goto\s+[A-Za-z_]"), "goto statement (5.2+)"),
    (re.compile(r"::\s*[A-Za-z_]\w*\s*::"), "::label:: (5.2+)"),
    (re.compile(r"(?<![\w.])table\.pack\s*\("), "table.pack (5.2+)"),
    (re.compile(r"(?<![\w.])table\.unpack\s*\("), "table.unpack (5.2+; use unpack)"),
)


def find_luac() -> tuple[str | None, str]:
    for name in LUAC_CANDIDATES:
        path = shutil.which(name)
        if not path:
            continue
        try:
            proc = subprocess.run([path, "-v"], capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            continue
        banner = (proc.stdout or proc.stderr or "").strip().splitlines()
        return path, banner[0] if banner else "unknown version"
    return None, ""


def toc_lua_entries() -> list[str]:
    """Ordered .lua paths listed in the TOC, as written (separators normalised)."""
    entries: list[str] = []
    for raw in TOC.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        rel = line.replace("\\", "/")
        if rel.lower().endswith(".lua"):
            entries.append(rel)
    return entries


def exact_case_exists(rel: str) -> bool:
    """Path.exists() is case-insensitive on Windows; walk the tree to be sure."""
    current = ROOT
    for part in rel.split("/"):
        try:
            names = {p.name for p in current.iterdir()}
        except OSError:
            return False
        if part not in names:
            return False
        current = current / part
    return current.is_file()


def scan_lua52(path: Path) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    lines = strip_block_comments(path.read_text(encoding="utf-8", errors="replace").splitlines())
    for i, raw in enumerate(lines, 1):
        code = strip_comment_and_strings(raw)
        if not code.strip():
            continue
        for pattern, label in LUA52_PATTERNS:
            if pattern.search(code):
                hits.append((i, label))
    return hits


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    luac, version = find_luac()
    if not luac:
        print(
            "luac not found. Install Lua 5.1 (apt: lua5.1, brew: lua@5.1, "
            "choco: lua) so this gate can run.",
            file=sys.stderr,
        )
        return 1

    is_51 = "5.1" in version
    print(f"Compiler: {luac} ({version})")
    if not is_51:
        print("  NOTE: not Lua 5.1 -- syntax errors and chunk ceilings are still")
        print("        enforced, but 5.2+ syntax is caught by the scan below instead.")

    errors: list[str] = []
    warnings: list[str] = []

    # --- TOC integrity -------------------------------------------------------
    entries = toc_lua_entries()
    listed = set()
    for rel in entries:
        listed.add(rel)
        if not exact_case_exists(rel):
            actual = ROOT / rel
            if actual.exists():
                errors.append(f"TOC case mismatch (fails on the Linux packager): {rel}")
            else:
                errors.append(f"TOC lists a missing file: {rel}")

    for path in sorted(ROOT.glob("Modules/**/*.lua")) + sorted(ROOT.glob("Locales/*.lua")):
        rel = path.relative_to(ROOT).as_posix()
        if rel not in listed:
            warnings.append(f"Not listed in the TOC (will not load): {rel}")

    # --- Compile -------------------------------------------------------------
    targets = [ROOT / rel for rel in entries if (ROOT / rel).is_file()]
    for extra in (ROOT / "Core.lua", ROOT / "Config.lua"):
        if extra.is_file() and extra not in targets:
            targets.append(extra)

    compiled = 0
    for path in targets:
        proc = subprocess.run([luac, "-p", str(path)], capture_output=True, text=True)
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip()
            errors.append(f"{path.relative_to(ROOT).as_posix()}: {detail}")
        else:
            compiled += 1

    # --- Lua 5.2+ syntax -----------------------------------------------------
    for path in targets:
        for line_no, label in scan_lua52(path):
            errors.append(
                f"{path.relative_to(ROOT).as_posix()}:{line_no}: {label} -- "
                f"the game runs Lua 5.1"
            )

    for warning in warnings:
        print(f"  WARN {warning}")

    if errors:
        print(f"\nLua compile gate FAILED ({len(errors)} error(s)):", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print(f"Lua compile gate OK - {compiled} file(s) compiled, TOC consistent"
          f"{f', {len(warnings)} warning(s)' if warnings else ''}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
