#!/usr/bin/env python3
"""
Stage Warband Nexus into build/WarbandNexus and create a ZIP for manual upload
(CurseForge / Wago). Entry names use forward slashes only (Linux / CurseForge Linux safe).

Requires Python 3.8+ (stdlib only; uses os.walk + zipfile). Run from repo root:
  python3 build_addon.py
  py build_addon.py   # Windows Python launcher
"""
from __future__ import annotations

import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

# --- Same layout policy as former scripts/build-curseforge.ps1 + .pkgmeta dev excludes ---

REPO_ROOT = Path(__file__).resolve().parent
CONSTANTS = REPO_ROOT / "Modules" / "Constants.lua"
BUILD_DIR = REPO_ROOT / "build"
STAGE_NAME = "WarbandNexus"
STAGE_DIR = BUILD_DIR / STAGE_NAME

# Do not descend into these top-level directories when copying from repo
EXCLUDE_ROOT = frozenset({
    ".git",
    ".cursor",
    ".vscode",
    ".claude",
    ".tmp",
    "build",
    "scripts",
    "Screenshots",
    ".tmp-addon-db-audit",
    "WarbandNexus",  # stray distribution folder if present
    "tests",
})

# Skip these directory names at any depth (matches embeds / .pkgmeta)
EXCLUDE_DIR_ANYWHERE = frozenset({
    "AceComm-3.0",
    "AceTab-3.0",
})

# Root-level files never shipped in the addon zip
ROOT_FILES_SKIP = frozenset({
    ".gitignore",
    ".gitattributes",
    ".pkgmeta",
    "README.md",
    "CHANGES.txt",
    "VERSION_CURSEFORGE.md",
    "VERSION_DISCORD.md",
    "_enc_w.html",
    "TOS_COMPLIANCE.md",
    "OPTIMIZATION_SUMMARY.md",
    "DEAD_CODE_AUDIT.md",
    "EVENTS_AUDIT.md",
    "STEP_FIX_LOG.md",
    "build_addon.py",
})

LIB_JUNK = [
    "libs/README.md",
    "libs/README.textile",
    "libs/changelog.txt",
    "libs/CHANGES.txt",
    "libs/LICENSE.txt",
    "libs/Changelog-libdatabroker-1-1-v1.1.4.txt",
    "libs/Ace3.toc",
    "libs/LibDBIcon-1.0.toc",
    "libs/embeds.xml",
    "libs/Bindings.xml",
    "libs/Ace3.lua",
    "libs/LibDeflate/.xml",
]


def read_addon_version() -> str:
    if not CONSTANTS.is_file():
        sys.exit(f"Missing {CONSTANTS}")
    raw = CONSTANTS.read_text(encoding="utf-8", errors="replace")
    m = re.search(r'ADDON_VERSION\s*=\s*"([^"]+)"', raw)
    if not m:
        sys.exit("ADDON_VERSION not found in Modules/Constants.lua")
    return m.group(1)


def copy_tree_filtered() -> None:
    if STAGE_DIR.exists():
        shutil.rmtree(STAGE_DIR)
    STAGE_DIR.mkdir(parents=True)

    for dirpath, dirnames, filenames in os.walk(REPO_ROOT, topdown=True):
        current = Path(dirpath)
        rel_dir = current.relative_to(REPO_ROOT)
        parts = rel_dir.parts

        dirnames[:] = [
            d for d in dirnames
            if d not in EXCLUDE_DIR_ANYWHERE
            and not (len(parts) == 0 and d in EXCLUDE_ROOT)
        ]

        for fn in filenames:
            src = current / fn
            rel = src.relative_to(REPO_ROOT)
            if rel.parts and rel.parts[0] in EXCLUDE_ROOT:
                continue
            if any(p in EXCLUDE_DIR_ANYWHERE for p in rel.parts[:-1]):
                continue
            if len(rel.parts) == 1 and rel.name in ROOT_FILES_SKIP:
                continue

            dst = STAGE_DIR / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)


def remove_lib_junk() -> None:
    for rel in LIB_JUNK:
        p = STAGE_DIR / rel
        if p.is_file():
            p.unlink()


def write_zip(version: str) -> Path:
    zip_path = BUILD_DIR / f"{STAGE_NAME}-{version}.zip"
    if zip_path.exists():
        zip_path.unlink()

    stage = STAGE_DIR.resolve()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for f in stage.rglob("*"):
            if not f.is_file():
                continue
            rel = f.relative_to(stage)
            arcname = f"{STAGE_NAME}/{rel.as_posix()}"
            zf.write(f, arcname=arcname)

    return zip_path


def verify_zip(zip_path: Path) -> None:
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        if not names:
            sys.exit("ZIP is empty")
        bad_sep = [n for n in names if "\\" in n]
        if bad_sep:
            sys.exit(f"ZIP entries must use '/': {bad_sep[:5]!r}")
        bad_root = [n for n in names if not n.startswith(f"{STAGE_NAME}/")]
        if bad_root:
            sys.exit(f"ZIP entries must start with {STAGE_NAME!r}/: {bad_root[:5]!r}")


def main() -> None:
    version = read_addon_version()
    copy_tree_filtered()
    remove_lib_junk()
    zip_path = write_zip(version)
    verify_zip(zip_path)
    print(f"OK version {version}")
    print(STAGE_DIR)
    print(zip_path)


if __name__ == "__main__":
    main()
