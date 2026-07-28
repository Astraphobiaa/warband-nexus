#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Static checks for Warband Nexus Lua file splits (satellite _bind wiring).

Catches the class of bugs where a satellite chunk calls a helper that lives as
``local`` in the parent file but was never exported via ``ns.*._bind`` or imported
via ``local Foo = B.Foo``.

Does NOT replace in-game /reload QA (WoW has no compile step; many APIs are runtime-only).

Run from repo root:
    python scripts/check_satellite_bind.py

Optional: integrate before release alongside preflight_release.py.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Parent/satellite split groups (extend when adding new _bind satellites).
SPLIT_GROUPS: list[dict] = [
    {
        "name": "UIShell",
        "parent": ROOT / "Modules" / "UI.lua",
        "bind_marker": "ns.UIShell._bind",
        "satellites": [
            ROOT / "Modules" / "UI" / "UI_MainShell.lua",
            ROOT / "Modules" / "UI" / "UI_TabHost.lua",
        ],
        "export_ns": "ns.UIShell",
    },
    {
        "name": "ItemsUI",
        "parent": ROOT / "Modules" / "UI" / "ItemsUI.lua",
        "bind_marker": "ns.ItemsUI._bind",
        "satellites": [
            ROOT / "Modules" / "UI" / "ItemsUI_StorageDraw.lua",
        ],
        "export_ns": "ns.ItemsUI",
    },
]

# Call names that are never parent-bind helpers (control flow, Lua, common WoW).
SKIP_CALL_NAMES = frozenset({
    "and", "or", "not", "function", "if", "for", "while", "repeat", "return",
    "assert", "error", "pcall", "xpcall", "type", "tonumber", "tostring",
    "pairs", "ipairs", "next", "select", "setmetatable", "getmetatable",
    "format", "match", "find", "gsub", "gmatch", "len", "lower", "upper",
    "insert", "remove", "concat", "sort", "wipe", "tinsert", "tremove",
    "CreateFrame", "GetTime", "InCombatLockdown", "issecretvalue", "date",
    "print", "strsplit", "strjoin", "unpack",
    # Common WoW API globals (not parent-bind helpers)
    "IsControlKeyDown", "IsShiftKeyDown", "IsAltKeyDown", "GetAddOnMetadata",
    "IsInGuild", "GetGuildInfo", "UnitName", "GetRealmName", "UIParent",
    "debugprofilestart", "debugprofilestop", "ReloadUI",
})

# Prefixes / patterns for helpers that should come from parent _bind when called bare in satellites.
HELPER_PREFIXES = (
    "Resolve", "Format", "Acquire", "Release", "Pack", "Apply", "Ensure",
    "Reflow", "Measure", "Sync", "Show", "Hide", "Draw", "Create", "Update",
    "Register", "Cancel", "Schedule", "Compare", "Items", "Storage", "Reposition",
    "CanView", "Build", "Chain", "Get", "Is", "Should", "Mark", "Detach",
    "Purge", "Refresh", "Wire", "Start", "Stop", "Remember", "Restore", "Save",
    "Scroll", "Normalize", "Compute", "Clear", "Arm", "Major", "Leaf",
)


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return raw.decode("utf-8")


def extract_bind_block(text: str, marker: str) -> str | None:
    idx = text.find(marker)
    if idx < 0:
        return None
    brace = text.find("{", idx)
    if brace < 0:
        return None
    depth = 0
    for i in range(brace, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace : i + 1]
    return None


def parse_bind_keys(bind_block: str) -> set[str]:
    keys: set[str] = set()
    for m in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", bind_block, re.MULTILINE):
        keys.add(m.group(1))
    return keys


def satellite_b_imports(text: str) -> set[str]:
    imported: set[str] = set()
    for m in re.finditer(r"local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*B\.([A-Za-z_][A-Za-z0-9_]*)", text):
        imported.add(m.group(1))
        if m.group(1) == m.group(2):
            imported.add(m.group(2))
    return imported


def satellite_local_defs(text: str) -> set[str]:
    names: set[str] = set()
    for m in re.finditer(r"local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)", text):
        names.add(m.group(1))
    for m in re.finditer(r"function\s+([A-Za-z_][A-Za-z0-9_]*):", text):
        names.add(m.group(1))
    for m in re.finditer(r"function\s+ns\.[A-Za-z_][A-Za-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*)", text):
        names.add(m.group(1))
    for m in re.finditer(
        r"local\s+((?:[A-Za-z_][A-Za-z0-9_]*)(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)",
        text,
    ):
        chunk = m.group(1)
        if "function" in chunk:
            continue
        for part in chunk.split(","):
            names.add(part.strip())
    return names


def find_bare_calls(text: str) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    for i, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        for m in re.finditer(r"(?<![.:])\b([A-Za-z_][A-Za-z0-9_]*)\s*\(", line):
            name = m.group(1)
            if name in SKIP_CALL_NAMES:
                continue
            hits.append((i, name))
    return hits


def looks_like_parent_helper(name: str) -> bool:
    if name.startswith("_"):
        return True
    return any(name.startswith(p) for p in HELPER_PREFIXES)


def extract_ns_exports(text: str, export_ns: str) -> set[str]:
    # ns.ItemsUI.Foo = ...  or  function ns.UIShell.Foo(
    prefix = export_ns + "."
    exports: set[str] = set()
    for m in re.finditer(re.escape(prefix) + r"([A-Za-z_][A-Za-z0-9_]*)\s*=", text):
        exports.add(m.group(1))
    for m in re.finditer(r"function\s+" + re.escape(prefix) + r"([A-Za-z_][A-Za-z0-9_]*)", text):
        exports.add(m.group(1))
    return exports


def parent_ns_defined(text: str, export_ns: str) -> set[str]:
    prefix = export_ns + "."
    defined: set[str] = set()
    for m in re.finditer(r"function\s+" + re.escape(prefix) + r"([A-Za-z_][A-Za-z0-9_]*)", text):
        defined.add(m.group(1))
    for m in re.finditer(re.escape(prefix) + r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function", text):
        defined.add(m.group(1))
    return defined


def parent_ns_imports(text: str, export_ns: str) -> set[str]:
    prefix = export_ns + "."
    used: set[str] = set()
    for m in re.finditer(re.escape(prefix) + r"([A-Za-z_][A-Za-z0-9_]*)", text):
        used.add(m.group(1))
    return used


def count_top_level_locals(path: Path) -> int:
    text = read_text(path)
    return len(re.findall(r"(?m)^local\s+", text))


def satellite_warbandnexus_methods(text: str) -> set[str]:
    return set(re.findall(r"function\s+WarbandNexus:([A-Za-z_][A-Za-z0-9_]*)", text))


def check_group(group: dict) -> list[str]:
    errors: list[str] = []
    parent = group["parent"]
    if not parent.is_file():
        return [f"MISSING parent file: {parent}"]

    parent_text = read_text(parent)
    bind_block = extract_bind_block(parent_text, group["bind_marker"])
    if not bind_block:
        errors.append(f"{parent.relative_to(ROOT)}: missing {group['bind_marker']}")
        bind_keys: set[str] = set()
    else:
        bind_keys = parse_bind_keys(bind_block)

    export_ns = group.get("export_ns")
    parent_needs_exports: set[str] = set()
    satellite_exports: set[str] = set()
    satellite_wn_methods: set[str] = set()
    if export_ns:
        parent_needs_exports = parent_ns_imports(parent_text, export_ns)
        parent_needs_exports -= parent_ns_defined(parent_text, export_ns)
        parent_needs_exports -= {"_bind", "_storageNameCache", "_uiChildEnumScratch", "_uiRegionEnumScratch"}

    for sat in group["satellites"]:
        if not sat.is_file():
            errors.append(f"MISSING satellite: {sat}")
            continue
        sat_text = read_text(sat)
        if group["bind_marker"] not in sat_text and "._bind" not in sat_text:
            errors.append(f"{sat.relative_to(ROOT)}: no reference to parent _bind (expected B = assert(..._bind))")

        imported = satellite_b_imports(sat_text)
        local_defs = satellite_local_defs(sat_text)
        if export_ns:
            satellite_exports |= extract_ns_exports(sat_text, export_ns)
            satellite_wn_methods |= satellite_warbandnexus_methods(sat_text)

        for line_no, name in find_bare_calls(sat_text):
            if name in local_defs or name in imported:
                continue
            if name in bind_keys and name not in imported:
                errors.append(
                    f"{sat.relative_to(ROOT)}:{line_no}: calls `{name}(...)` but missing "
                    f"`local {name} = B.{name}` (in parent {group['bind_marker']})"
                )
                continue
            if looks_like_parent_helper(name) and name not in bind_keys:
                errors.append(
                    f"WARN {sat.relative_to(ROOT)}:{line_no}: bare `{name}(...)` — "
                    f"not local/B-import; add to parent _bind if split from ItemsUI/UI.lua"
                )

    if export_ns:
        missing_exports = parent_needs_exports - satellite_exports - satellite_wn_methods
        missing_exports.discard("_bind")
        for name in sorted(missing_exports):
            errors.append(
                f"{group['name']}: parent uses `{export_ns}.{name}` but no satellite assigns `{export_ns}.{name} =`"
            )

    loc = count_top_level_locals(parent)
    if loc > 120:
        errors.append(
            f"WARN {parent.relative_to(ROOT)}: {loc} top-level `local` lines (target <120 before split)"
        )

    return errors


def check_bom(strict: bool) -> list[str]:
    issues: list[str] = []
    for path in ROOT.rglob("*.lua"):
        if "libs" in path.parts or "build" in path.parts:
            continue
        if path.read_bytes()[:3] == b"\xef\xbb\xbf":
            rel = str(path.relative_to(ROOT))
            issues.append(f"WARN BOM in {rel}" if not strict else f"BOM in {rel}")
    return issues


def main() -> int:
    # A legacy console codepage turns any non-ASCII in the output into an
    # UnicodeEncodeError, which aborts the gate mid-report. Force UTF-8.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    strict_bom = "--strict-bom" in sys.argv
    all_errors: list[str] = []
    for group in SPLIT_GROUPS:
        all_errors.extend(check_group(group))
    all_errors.extend(check_bom(strict_bom))

    if not all_errors:
        print("check_satellite_bind: OK")
        return 0

    hard = [e for e in all_errors if not e.startswith("WARN")]
    warns = [e for e in all_errors if e.startswith("WARN")]
    if hard:
        print("check_satellite_bind: FAILED")
        for err in hard:
            print(f"  ERROR: {err}")
    else:
        print("check_satellite_bind: OK (with warnings)")
    for err in warns:
        print(f"  {err}")
    if warns:
        print(f"({len(warns)} warning(s) — latent split/bind gaps or BOM; use --strict-bom to fail on BOM)")
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
