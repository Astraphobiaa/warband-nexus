#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pre-release gate: locale parity, version sync, changelog keys. Fail fast before tag upload.

Run from repo root:  python .github/scripts/preflight_release.py
Used locally by agents before build/tag and in GitHub Actions (release workflow preflight job).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCALES = ROOT / "Locales"
CONSTANTS = ROOT / "Modules" / "Constants.lua"
TOC = ROOT / "WarbandNexus.toc"
CHANGELOG = ROOT / "CHANGELOG.md"
CHANGELOG_FOREVER = ROOT / "CHANGELOG_FOREVER.md"

TOC_LOCALE_NAMES = {
    "deDE.lua",
    "enUS.lua",
    "esES.lua",
    "esMX.lua",
    "frFR.lua",
    "itIT.lua",
    "koKR.lua",
    "ptBR.lua",
    "ruRU.lua",
    "zhCN.lua",
    "zhTW.lua",
}


def keys_from_locale(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'L\["([^"]+)"\]\s*=', text))


def read_version_from_constants() -> str | None:
    text = CONSTANTS.read_text(encoding="utf-8")
    m = re.search(r'ADDON_VERSION\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else None


def read_version_from_toc() -> str | None:
    text = TOC.read_text(encoding="utf-8")
    m = re.search(r"(?m)^## Version:\s*(.+)\s*$", text)
    return m.group(1).strip() if m else None


def changelog_key_for_version(version: str) -> str | None:
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", version)
    if not m:
        return None
    return "CHANGELOG_V" + m.group(1) + m.group(2) + m.group(3)


def ns_l_orphans() -> set[str]:
    orphans: set[str] = set()
    en_keys = keys_from_locale(LOCALES / "enUS.lua")
    # .claude: local agent worktrees (.claude/worktrees/*) hold other branches' copies of the addon.
    skip = {"libs", "build", ".git", ".claude"}
    for path in ROOT.rglob("*.lua"):
        parts = {p.lower() for p in path.parts}
        if parts & skip:
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("libs/"):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for key in re.findall(r'ns\.L\["([^"]+)"\]', text):
            if key not in en_keys:
                orphans.add(key)
    return orphans


def main() -> int:
    # Release gate: it echoes locale keys and changelog text, so a legacy console
    # codepage could abort it with UnicodeEncodeError right before a tag push.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    errors: list[str] = []
    warnings: list[str] = []

    if not LOCALES.is_dir():
        errors.append("Locales/ directory missing")
        _report(errors, warnings)
        return 1

    en_path = LOCALES / "enUS.lua"
    if not en_path.is_file():
        errors.append("Locales/enUS.lua missing")
        _report(errors, warnings)
        return 1

    en_keys = keys_from_locale(en_path)
    print(f"enUS key count: {len(en_keys)}")

    for name in sorted(TOC_LOCALE_NAMES):
        path = LOCALES / name
        if not path.is_file():
            errors.append(f"Missing locale file listed in TOC set: {name}")
            continue
        loc_keys = keys_from_locale(path)
        missing = en_keys - loc_keys
        extra = loc_keys - en_keys
        if missing:
            sample = ", ".join(sorted(missing)[:8])
            suffix = f" (+{len(missing) - 8} more)" if len(missing) > 8 else ""
            errors.append(f"{name}: {len(missing)} keys missing vs enUS (e.g. {sample}{suffix})")
        if extra:
            warnings.append(f"{name}: {len(extra)} extra keys not in enUS")

    const_ver = read_version_from_constants()
    toc_ver = read_version_from_toc()
    if not const_ver:
        errors.append("Could not parse ADDON_VERSION from Modules/Constants.lua")
    if not toc_ver:
        errors.append("Could not parse ## Version from WarbandNexus.toc")
    if const_ver and toc_ver and const_ver != toc_ver:
        errors.append(f"Version mismatch: Constants={const_ver!r} TOC={toc_ver!r}")

    # The WoW Forever TOCs are generated from WarbandNexus.toc (## Version included): a version bump
    # without regenerating them would ship a Forever build that reports the previous version.
    import subprocess
    flavor = subprocess.run([sys.executable, str(ROOT / "scripts" / "build_flavor_tocs.py"), "--check"],
                            capture_output=True, text=True)
    if flavor.returncode != 0:
        errors.append("Forever TOCs stale: run python scripts/build_flavor_tocs.py ("
                      + (flavor.stderr or flavor.stdout).strip() + ")")

    # WoW Forever release line: FOREVER_ADDON_VERSION, CHANGELOG_FOREVER.md, CHANGELOG_FOREVER_V*.
    fm = re.search(r'FOREVER_ADDON_VERSION\s*=\s*"([^"]+)"', CONSTANTS.read_text(encoding="utf-8"))
    forever_ver = fm.group(1) if fm else None
    if not forever_ver:
        errors.append("Could not parse FOREVER_ADDON_VERSION from Modules/Constants.lua")
    else:
        fnum = re.match(r"^(\d+)\.(\d+)\.(\d+)", forever_ver)
        fkey = ("CHANGELOG_FOREVER_V" + "".join(fnum.groups())) if fnum else None
        if not fkey:
            errors.append(f"Could not derive CHANGELOG_FOREVER key from {forever_ver!r}")
        else:
            for name in sorted(TOC_LOCALE_NAMES):
                path = LOCALES / name
                if not path.is_file():
                    continue
                text = path.read_text(encoding="utf-8")
                if fkey not in keys_from_locale(path):
                    errors.append(f"{name}: missing {fkey} for Forever version {forever_ver}")
                for prefix in ("CHANGELOG_V", "CHANGELOG_FOREVER_V"):
                    n = len(re.findall(r'L\["' + prefix + r'\d+"\]', text))
                    if n > 1:
                        errors.append(f"{name}: {n} {prefix}* keys -- keep only the current version's")
        if not CHANGELOG_FOREVER.is_file():
            errors.append("CHANGELOG_FOREVER.md missing at repo root")
        elif not re.search(rf"(?m)^## v{re.escape(forever_ver)}\b",
                           CHANGELOG_FOREVER.read_text(encoding="utf-8")):
            errors.append(f"CHANGELOG_FOREVER.md has no ## v{forever_ver} section")

    # On a release tag, the tag must name the version being shipped:
    # vX.Y.Z = retail (ADDON_VERSION), forever-vX.Y.Z = WoW Forever (FOREVER_ADDON_VERSION).
    import os
    ref = os.environ.get("GITHUB_REF_NAME", "")
    if os.environ.get("GITHUB_REF_TYPE") == "tag" and ref:
        if ref.startswith("forever-v"):
            if forever_ver and ref != f"forever-v{forever_ver}":
                errors.append(f"Tag {ref} does not match FOREVER_ADDON_VERSION {forever_ver}")
        elif ref.startswith("v"):
            if const_ver and ref != f"v{const_ver}":
                errors.append(f"Tag {ref} does not match ADDON_VERSION {const_ver}")

    version = const_ver or toc_ver
    if version:
        ck = changelog_key_for_version(version)
        if not ck:
            errors.append(f"Could not derive CHANGELOG key from version {version!r}")
        else:
            for name in sorted(TOC_LOCALE_NAMES):
                path = LOCALES / name
                if path.is_file() and ck not in keys_from_locale(path):
                    errors.append(f"{name}: missing {ck} for version {version}")
            if CHANGELOG.is_file():
                cl = CHANGELOG.read_text(encoding="utf-8")
                header = f"## v{version.split()[0]}"
                if header not in cl and f"## v{version}" not in cl:
                    # allow 3.1.7 matching ## v3.1.7 (date)
                    if not re.search(rf"(?m)^## v{re.escape(version)}\b", cl):
                        numeric = re.match(r"^[\d.]+", version)
                        if numeric and not re.search(
                            rf"(?m)^## v{re.escape(numeric.group(0))}\b", cl
                        ):
                            errors.append(
                                f"CHANGELOG.md has no ## v{version} section for current version"
                            )
            else:
                errors.append("CHANGELOG.md missing at repo root")

    orphans = ns_l_orphans()
    if orphans:
        sample = ", ".join(sorted(orphans)[:10])
        suffix = f" (+{len(orphans) - 10} more)" if len(orphans) > 10 else ""
        errors.append(f"ns.L keys used in code but missing from enUS.lua: {sample}{suffix}")

    quality_script = ROOT / "scripts" / "check_locale_quality.py"
    if quality_script.is_file():
        import subprocess

        proc = subprocess.run(
            [sys.executable, str(quality_script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if proc.returncode != 0:
            for line in (proc.stdout + proc.stderr).splitlines():
                line = line.strip()
                if line.startswith("ERROR:"):
                    errors.append(f"locale quality: {line[6:].strip()}")
                elif "Locale quality FAILED" in line:
                    errors.append("locale quality check failed (see script output)")
            if not any("locale quality" in e for e in errors):
                errors.append("locale quality check failed (scripts/check_locale_quality.py)")
    else:
        warnings.append("scripts/check_locale_quality.py missing — skip transliteration audit")

    split_script = ROOT / "scripts" / "check_split_wiring.py"
    if split_script.is_file():
        import subprocess

        proc = subprocess.run(
            [sys.executable, str(split_script)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if proc.returncode != 0:
            for line in (proc.stdout + proc.stderr).splitlines():
                line = line.strip()
                if line.startswith("ERROR:"):
                    errors.append(f"split wiring: {line[6:].strip()}")
            if not any("split wiring" in e for e in errors):
                errors.append("split wiring check failed (scripts/check_split_wiring.py)")
    else:
        warnings.append("scripts/check_split_wiring.py missing — skip module split audit")

    _report(errors, warnings)
    return 1 if errors else 0


def _report(errors: list[str], warnings: list[str]) -> None:
    def _out(text: str) -> None:
        enc = getattr(sys.stdout, "encoding", None) or "utf-8"
        print(text.encode(enc, errors="replace").decode(enc, errors="replace"))

    if warnings:
        _out("\nWarnings:")
        for w in warnings:
            _out(f"  WARN: {w}")
    if errors:
        _out("\nPreflight FAILED:")
        for e in errors:
            _out(f"  ERROR: {e}")
    else:
        _out("\nPreflight OK - locale parity, version sync, and changelog keys passed.")


if __name__ == "__main__":
    sys.exit(main())
