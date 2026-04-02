#!/usr/bin/env python3
"""Compare L[\"key\"] entries in Locales/*.lua to enUS.lua."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOC = ROOT / "Locales"
PAT = re.compile(r'L\["([^"]+)"\]')


def keys_in(path: Path) -> set[str]:
    return set(PAT.findall(path.read_text(encoding="utf-8")))


def main() -> None:
    base = keys_in(LOC / "enUS.lua")
    print(f"enUS: {len(base)} keys")
    for f in sorted(LOC.glob("*.lua")):
        if f.name == "enUS.lua":
            continue
        k = keys_in(f)
        missing = sorted(base - k)
        extra = sorted(k - base)
        print(f"{f.name}: missing {len(missing)}, extra {len(extra)}")
        if missing:
            for m in missing[:40]:
                print(f"  - {m}")
            if len(missing) > 40:
                print(f"  ... +{len(missing) - 40}")
        if extra and len(extra) <= 20:
            for e in extra:
                print(f"  + extra: {e}")


if __name__ == "__main__":
    main()
