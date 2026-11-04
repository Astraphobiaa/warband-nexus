#!/usr/bin/env python3
"""Generate Modules/CollectibleFactionDB.lua: Alliance / Horde only pets, toys and titles.

The in-game API exposes faction only for mounts (C_MountJournal.GetMountInfoByID isFactionSpecific / faction).
Pets, toys and titles get it from client DB2 tables via the wago.tools CSV export:

  BattlePetSpecies.Flags   0x100 = Horde only, 0x200 = Alliance only
                           (verified 2026-11-04: Argent Gruntling 216 = 0x100, Argent Squire 214 = 0x200)
  Toy.ItemID -> ItemSparse.Flags_1  0x1 = Horde only, 0x2 = Alliance only
                           (verified 2026-11-04: Thunder Bluff Banner 45013 = 0x1, Stormwind Banner 45011 = 0x2,
                            each pair linked by OppositeFactionItemID)
  CharTitles.Mask_ID <- Achievement.Reward_lang ("Title: X" / "Title Reward: X") + Achievement.Faction
                           (0 = Horde, 1 = Alliance; verified: Grand Marshal 5343 = 1, High Warlord 5356 = 0)

Usage:  python3 scripts/gen_collectible_faction_db.py [--csv-dir DIR]
Without --csv-dir the CSVs are downloaded from wago.tools (latest live build).
"""
from __future__ import annotations

import argparse
import csv
import datetime
import io
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Modules" / "CollectibleFactionDB.lua"
TABLES = ("BattlePetSpecies", "Toy", "ItemSparse", "Achievement", "CharTitles")

PET_FLAG_HORDE, PET_FLAG_ALLIANCE = 0x100, 0x200
ITEM_FLAG2_HORDE, ITEM_FLAG2_ALLIANCE = 0x1, 0x2
ACH_FACTION = {"0": "H", "1": "A"}


def load_rows(table: str, csv_dir: Path | None) -> list[dict]:
    if csv_dir:
        text = (csv_dir / f"{table}.csv").read_text(encoding="utf-8")
    else:
        with urllib.request.urlopen(f"https://wago.tools/db2/{table}/csv", timeout=300) as resp:
            text = resp.read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(text)))


def int_or_zero(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def title_key(text: str) -> str | None:
    if not text:
        return None
    text = text.replace("%s", "").replace("：", ":")
    if ":" in text:
        text = text.rsplit(":", 1)[1]
    text = text.strip().lstrip(",").strip()
    return text.lower() or None


def build(csv_dir: Path | None) -> dict[str, dict[int, str]]:
    pets: dict[int, str] = {}
    for row in load_rows("BattlePetSpecies", csv_dir):
        flags = int_or_zero(row["Flags"])
        if flags & PET_FLAG_HORDE and not flags & PET_FLAG_ALLIANCE:
            pets[int(row["ID"])] = "H"
        elif flags & PET_FLAG_ALLIANCE and not flags & PET_FLAG_HORDE:
            pets[int(row["ID"])] = "A"

    toy_items = {int(r["ItemID"]) for r in load_rows("Toy", csv_dir)}
    toys: dict[int, str] = {}
    for row in load_rows("ItemSparse", csv_dir):
        item_id = int(row["ID"])
        if item_id not in toy_items:
            continue
        flags = int_or_zero(row["Flags_1"])
        if flags & ITEM_FLAG2_HORDE and not flags & ITEM_FLAG2_ALLIANCE:
            toys[item_id] = "H"
        elif flags & ITEM_FLAG2_ALLIANCE and not flags & ITEM_FLAG2_HORDE:
            toys[item_id] = "A"

    reward_faction: dict[str, set[str]] = {}
    for row in load_rows("Achievement", csv_dir):
        side = ACH_FACTION.get(row["Faction"])
        key = title_key(row["Reward_lang"])
        if key:
            reward_faction.setdefault(key, set()).add(side or "-")
    titles: dict[int, str] = {}
    for row in load_rows("CharTitles", csv_dir):
        mask = int_or_zero(row["Mask_ID"])
        if mask <= 0:
            continue
        sides: set[str] = set()
        for name_col in ("Name_lang", "Name1_lang"):
            key = title_key(row.get(name_col, ""))
            if key and key in reward_faction:
                sides |= reward_faction[key]
        # Only when every awarding achievement is the same faction (a neutral or two-sided award stays neutral).
        if sides in ({"H"}, {"A"}):
            titles[mask] = sides.pop()
    return {"petSpecies": pets, "toyItems": toys, "titleMasks": titles}


def emit(data: dict[str, dict[int, str]]) -> str:
    today = datetime.date.today().isoformat()
    lines = [
        "--[[",
        "    Warband Nexus - Collectible faction data (GENERATED - do not edit by hand)",
        f"    Source: wago.tools DB2 CSV export, latest live build, {today}.",
        "    Regenerate: python3 scripts/gen_collectible_faction_db.py",
        "    \"A\" = Alliance only, \"H\" = Horde only; absent = both factions. Mounts use the live API instead",
        "    (WarbandNexus:GetMountFactionKey).",
        "]]",
        "",
        "local _, ns = ...",
        "",
        "ns.CollectibleFactionDB = {",
    ]
    for key in ("petSpecies", "toyItems", "titleMasks"):
        lines.append(f"    {key} = {{")
        for ident in sorted(data[key]):
            lines.append(f"        [{ident}] = \"{data[key][ident]}\",")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--csv-dir", type=Path, help="read <Table>.csv files from here instead of downloading")
    args = ap.parse_args()
    data = build(args.csv_dir)
    OUT.write_text(emit(data), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: " + ", ".join(f"{k}={len(v)}" for k, v in data.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
