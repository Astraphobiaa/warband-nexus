#!/usr/bin/env python3
"""Detect likely Lua 5.1 forward-reference nil calls (local used before definition line)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = Path(__file__).resolve().parent / "forward_refs_baseline.txt"
SCAN_DIRS = [ROOT / "Modules", ROOT / "Core.lua", ROOT / "Locales"]
SKIP_PARTS = {"libs", "Libs", ".git", "build"}

LOCAL_FN = re.compile(r"^\s*local\s+function\s+(\w+)")
LOCAL_ASSIGN_FN = re.compile(r"^\s*local\s+(\w+)\s*=\s*function\b")
# KNOWN GAP: callable aliases such as `local FormatNumber = ns.UI_FormatNumber`
# are the same trap when used above their binding line, but matching every
# `local X = ...` was tried and reverted -- it went from 20 hits to 101, nearly
# all noise, because short bindings (time, cache, total, row, key) collide with
# same-named globals and with prose inside string literals. Catching those needs
# real scope analysis, not a line regex. luac (check_lua_compile.py) does not
# catch them either: they are valid Lua that fails only at runtime.
CALL = re.compile(r"\b({name})\s*\(")

# Top-level (column 0) declarations -- only these consume main-chunk registers.
# `local function f(a, b)` declares exactly one name, so it needs its own rule:
# splitting its parameter list on commas would over-count.
TOP_LEVEL_LOCAL_FN = re.compile(r"^local\s+function\s+[\w.:]+")
TOP_LEVEL_LOCAL = re.compile(r"^local\s+(.+)")
BLOCK_COMMENT_OPEN = re.compile(r"--\[(=*)\[")

# A `function Foo:Bar()` / `local function Bar()` header is a definition, not a
# call site -- matching the name inside it flagged the definition against itself.
FUNCTION_HEADER = re.compile(r"^\s*(?:local\s+)?function\b")

# WoW/builtin globals that look like locals but are fine
BUILTIN_OK = {
    "pairs", "ipairs", "tonumber", "tostring", "type", "pcall", "xpcall",
    "select", "unpack", "table", "string", "math", "bit", "wipe",
    "print", "error", "assert", "next", "setmetatable", "getmetatable",
    "rawget", "rawset", "loadstring", "collectgarbage",
}


def iter_lua_files() -> list[Path]:
    out: list[Path] = []
    for base in SCAN_DIRS:
        if base.is_file():
            out.append(base)
            continue
        for p in base.rglob("*.lua"):
            if any(part in SKIP_PARTS for part in p.parts):
                continue
            out.append(p)
    return sorted(set(out))


def strip_comment_and_strings(line: str) -> str:
    """Blank out quoted strings and drop a trailing -- comment.

    Both are prose, not code: `-- Cache for ScanBag (nil entries are fine)` and
    `Print("... collection cache (empty)")` were both scanned as call sites.
    String bodies are replaced by spaces so column positions stay usable.
    """
    out: list[str] = []
    quote: str | None = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append("  ")
                i += 2
                continue
            out.append(" " if ch != quote else ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "-" and line.startswith("--", i):
            break
        out.append(ch)
        i += 1
    return "".join(out)


def strip_block_comments(lines: list[str]) -> list[str]:
    """Blank out --[[ ... ]] regions so commented-out code is not scanned."""
    out: list[str] = []
    closer: str | None = None
    for line in lines:
        if closer is not None:
            idx = line.find(closer)
            if idx < 0:
                out.append("")
                continue
            line = line[idx + len(closer):]
            closer = None
        m = BLOCK_COMMENT_OPEN.search(line)
        if m:
            closer = "]" + m.group(1) + "]"
            head = line[: m.start()]
            idx = line.find(closer, m.end())
            if idx >= 0:
                out.append(head + line[idx + len(closer):])
                closer = None
                continue
            out.append(head)
            continue
        out.append(line)
    return out


def analyze_file(path: Path) -> list[tuple[int, str, str, int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = strip_block_comments(text.splitlines())

    # A name may be declared in several sibling scopes (two independent `local
    # function row()` helpers, each above its own callers). Only the EARLIEST
    # definition matters: a call after it resolves to some in-scope binding, so
    # flagging later scopes produced pure noise. Keep first-seen line only.
    defs: dict[str, int] = {}
    for i, line in enumerate(lines, 1):
        m = LOCAL_FN.match(line) or LOCAL_ASSIGN_FN.match(line)
        if m:
            defs.setdefault(m.group(1), i)

    # Precompile once per name, not once per (line, name) pair.
    # (?<![\w.:]) keeps `self:Foo()` and `tbl.Foo()` out: those resolve through a
    # table at runtime and have nothing to do with local declaration order.
    patterns = [
        (name, def_line, re.compile(r"(?<![\w.:])" + re.escape(name) + r"\s*\("))
        for name, def_line in defs.items()
        if name not in BUILTIN_OK
    ]

    issues: list[tuple[int, str, str, int]] = []
    for i, raw in enumerate(lines, 1):
        if not raw or FUNCTION_HEADER.match(raw):
            continue
        line = strip_comment_and_strings(raw)
        if not line.strip():
            continue
        for name, def_line, pat in patterns:
            if def_line <= i:
                continue
            if pat.search(line):
                issues.append((i, name, line.strip()[:100], def_line))
    return issues


def count_locals(path: Path) -> int:
    """Count declared names in column-0 `local` statements (main-chunk registers).

    Heuristic only -- `local a, b, c` declares three. The authoritative check is
    scripts/check_lua_compile.py, which lets luac enforce the real 200 ceiling.
    """
    n = 0
    lines = strip_block_comments(path.read_text(encoding="utf-8", errors="replace").splitlines())
    for line in lines:
        if TOP_LEVEL_LOCAL_FN.match(line):
            n += 1
            continue
        m = TOP_LEVEL_LOCAL.match(line)
        if not m:
            continue
        names = m.group(1).split("=", 1)[0]
        n += sum(1 for part in names.split(",") if part.strip())
    return n


def main() -> int:
    # Lua sources carry non-ASCII (locale strings, arrows in comments). Printing a
    # snippet under a legacy console codepage such as cp1254 raised
    # UnicodeEncodeError mid-run, so every file after the first offender went
    # unaudited. Force UTF-8 so the gate always reaches the end of the tree.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    all_issues: list[tuple[Path, int, str, str, int]] = []
    local_counts: list[tuple[int, Path]] = []

    for path in iter_lua_files():
        lc = count_locals(path)
        if lc >= 170:
            local_counts.append((lc, path))
        for line_no, name, snippet, def_line in analyze_file(path):
            all_issues.append((path, line_no, name, snippet, def_line))

    print("=== Likely forward-reference calls (local function used before definition) ===\n")
    if not all_issues:
        print("No matches.\n")
    else:
        by_file: dict[Path, list] = {}
        for item in all_issues:
            by_file.setdefault(item[0], []).append(item)
        for path in sorted(by_file, key=lambda p: str(p)):
            rel = path.relative_to(ROOT)
            print(f"{rel}:")
            for _, line_no, name, snippet, def_line in sorted(by_file[path], key=lambda x: x[1]):
                print(f"  L{line_no}: calls {name}() before L{def_line}: {snippet}")
            print()

    print("=== Files with >= 170 top-level 'local' declarations (200-local chunk risk) ===\n")
    for lc, path in sorted(local_counts, reverse=True):
        rel = path.relative_to(ROOT)
        flag = " *** CRITICAL" if lc >= 195 else (" ** WARN" if lc >= 180 else "")
        print(f"  {lc:4d}  {rel}{flag}")
    print()

    # Baseline gate: the tree carries pre-existing forward references that need
    # individual review, so failing on all of them would just make CI red and
    # ignorable. Fail only on findings absent from the baseline -- that blocks new
    # regressions today while the recorded backlog is burned down separately.
    current = {f"{path.relative_to(ROOT).as_posix()}|{name}" for path, _, name, _, _ in all_issues}

    if "--update-baseline" in sys.argv:
        header = (
            "# Known forward references, one `path|symbol` per line.\n"
            "# The gate fails only on findings NOT listed here, so new regressions\n"
            "# break CI while this backlog is burned down. Each entry is a real Lua\n"
            "# 5.1 trap: the name compiles to a nil global at its call site.\n"
            "# Fix one by moving the helper above its first caller (or forward-\n"
            "# declaring it), then rerun with --update-baseline to drop the line.\n"
            "# Never add entries by hand to silence a new finding.\n"
        )
        BASELINE.write_text(header + "\n".join(sorted(current)) + "\n", encoding="utf-8")
        print(f"Baseline written: {BASELINE.relative_to(ROOT)} ({len(current)} entry(s)).")
        return 0

    baseline = set()
    if BASELINE.exists():
        baseline = {
            ln.strip()
            for ln in BASELINE.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")
        }

    new_hits = sorted(current - baseline)
    fixed = sorted(baseline - current)

    if fixed:
        print(f"=== {len(fixed)} baselined entry(s) no longer present -- rerun with "
              f"--update-baseline to lock the fix in ===\n")
        for key in fixed:
            print(f"  FIXED {key}")
        print()

    if new_hits:
        print("=== NEW forward references (not in baseline) ===\n", file=sys.stderr)
        for key in new_hits:
            print(f"  {key}", file=sys.stderr)
        print(f"\nForward-ref gate FAILED: {len(new_hits)} new finding(s). Define the helper "
              f"above its first caller, or forward-declare it.", file=sys.stderr)
        return 1

    print(f"Forward-ref gate OK ({len(current)} known finding(s) in baseline, 0 new).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
