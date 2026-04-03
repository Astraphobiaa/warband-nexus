#!/usr/bin/env python3
"""
Export Warband Nexus CollectibleSourceDB (legacy* + typed sources) to a flat TSV.

Columns:
  category, source_type, source_id, encounter_id, quest_id, map_id, container_id, object_id,
  drop_type, item_id, item_name, table_drop_difficulty, statistic_ids, guaranteed, repeatable,
  rares_only, hostile_only, notes

Run from repo root: python scripts/export_collectible_source_db.py
Output: scripts/output/collectible_source_export.tsv
"""

from __future__ import annotations

import csv
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "Modules" / "CollectibleSourceDB.lua"
OUT_DIR = ROOT / "scripts" / "output"
OUT_TSV = OUT_DIR / "collectible_source_export.tsv"


def brace_match(s: str, open_idx: int) -> tuple[str, int]:
    if open_idx >= len(s) or s[open_idx] != "{":
        raise ValueError("expected {")
    depth = 0
    for i in range(open_idx, len(s)):
        c = s[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return s[open_idx + 1 : i], i + 1
    raise ValueError("unbalanced braces")


def extract_marker_block(full: str, marker: str) -> str | None:
    i = full.find(marker)
    if i < 0:
        return None
    j = full.find("{", i)
    if j < 0:
        return None
    inner, _ = brace_match(full, j)
    return inner


def parse_drop_lines(block: str) -> list[dict]:
    rows: list[dict] = []
    # Each { type = "...", itemID = N, name = "..." ... }
    pat = re.compile(
        r'\{\s*type\s*=\s*"(\w+)"\s*,\s*itemID\s*=\s*(\d+)\s*,\s*name\s*=\s*"((?:\\.|[^"\\])*)"\s*([^}]*)\}',
        re.DOTALL,
    )
    for m in pat.finditer(block):
        tail = m.group(4)
        rows.append(
            {
                "drop_type": m.group(1),
                "item_id": int(m.group(2)),
                "item_name": m.group(3).replace("\\'", "'"),
                "guaranteed": "true" if re.search(r"\bguaranteed\s*=\s*true", tail) else "",
                "repeatable": "true" if re.search(r"\brepeatable\s*=\s*true", tail) else "",
            }
        )
    return rows


def table_drop_difficulty(block: str) -> str:
    m = re.search(r'dropDifficulty\s*=\s*"([^"]+)"', block)
    return m.group(1) if m else ""


def statistic_ids(block: str) -> str:
    m = re.search(r"statisticIds\s*=\s*\{([^}]*)\}", block)
    if not m:
        return ""
    nums = re.findall(r"\d+", m.group(1))
    return ";".join(nums)


def parse_keyed_npc_like(inner: str, category: str, source_type: str) -> list[dict]:
    out: list[dict] = []
    pos = 0
    key_pat = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = key_pat.search(inner, pos)
        if not m:
            break
        key = int(m.group(1))
        ob = m.end() - 1
        sub, end = brace_match(inner, ob)
        pos = end
        tdd = table_drop_difficulty(sub)
        stats = statistic_ids(sub)
        drops = parse_drop_lines(sub)
        if not drops:
            continue
        for d in drops:
            row = {
                "category": category,
                "source_type": source_type,
                "source_id": str(key),
                "encounter_id": "",
                "quest_id": "",
                "map_id": "",
                "container_id": "",
                "object_id": "",
                "drop_type": d["drop_type"],
                "item_id": str(d["item_id"]),
                "item_name": d["item_name"],
                "table_drop_difficulty": tdd,
                "statistic_ids": stats,
                "guaranteed": d["guaranteed"],
                "repeatable": d["repeatable"],
                "rares_only": "",
                "hostile_only": "",
                "notes": "",
            }
            out.append(row)
    return out


def parse_containers(inner: str, shared: dict[str, str]) -> list[dict]:
    out: list[dict] = []
    pos = 0
    key_pat = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = key_pat.search(inner, pos)
        if not m:
            break
        cid = int(m.group(1))
        ob = m.end() - 1
        sub, end = brace_match(inner, ob)
        pos = end
        drops_block = sub
        dm = re.search(r"drops\s*=\s*\{", sub)
        if dm:
            d_inner, _ = brace_match(sub, dm.end() - 1)
            drops_block = d_inner
        else:
            ref = re.search(r"(_\w+)\[(\d+)\]", sub)
            if ref:
                arr = shared.get(ref.group(1), "")
                drops_block = arr
        tdd = table_drop_difficulty(sub)
        stats = statistic_ids(sub)
        drops = parse_drop_lines(drops_block)
        for d in drops:
            out.append(
                {
                    "category": "container",
                    "source_type": "container",
                    "source_id": "",
                    "encounter_id": "",
                    "quest_id": "",
                    "map_id": "",
                    "container_id": str(cid),
                    "object_id": "",
                    "drop_type": d["drop_type"],
                    "item_id": str(d["item_id"]),
                    "item_name": d["item_name"],
                    "table_drop_difficulty": tdd,
                    "statistic_ids": stats,
                    "guaranteed": d["guaranteed"],
                    "repeatable": d["repeatable"],
                    "rares_only": "",
                    "hostile_only": "",
                    "notes": "",
                }
            )
    return out


def parse_shared_underscore_tables(head: str) -> dict[str, str]:
    """`local _Name = { ... }` bodies (shared drop arrays) from preamble before ns.CollectibleSourceDB."""
    shared: dict[str, str] = {}
    for m in re.finditer(r"local\s+(_\w+)\s*=\s*\{", head):
        start = m.end() - 1
        try:
            body, _ = brace_match(head, start)
        except ValueError:
            continue
        shared[m.group(1)] = body
    return shared


def parse_zones(inner: str, shared: dict[str, str]) -> list[dict]:
    out: list[dict] = []
    pos = 0
    key_pat = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = key_pat.search(inner, pos)
        if not m:
            break
        mid = int(m.group(1))
        ob = m.end() - 1
        sub, end = brace_match(inner, ob)
        pos = end
        rares_only = "true" if re.search(r"raresOnly\s*=\s*true", sub) else ""
        hostile_only = "true" if re.search(r"hostileOnly\s*=\s*true", sub) else ""
        drops_block = sub
        ref = re.search(r"drops\s*=\s*(_\w+)\b", sub)
        if ref and ref.group(1) in shared:
            drops_block = shared[ref.group(1)]
        else:
            dm = re.search(r"drops\s*=\s*", sub)
            if dm:
                ob2 = sub.find("{", dm.end() - 1)
                if ob2 >= 0:
                    d_inner, _ = brace_match(sub, ob2)
                    drops_block = d_inner
        tdd = table_drop_difficulty(sub)
        for d in parse_drop_lines(drops_block):
            out.append(
                {
                    "category": "zone",
                    "source_type": "zone_drop",
                    "source_id": "",
                    "encounter_id": "",
                    "quest_id": "",
                    "map_id": str(mid),
                    "container_id": "",
                    "object_id": "",
                    "drop_type": d["drop_type"],
                    "item_id": str(d["item_id"]),
                    "item_name": d["item_name"],
                    "table_drop_difficulty": tdd,
                    "statistic_ids": statistic_ids(sub),
                    "guaranteed": d["guaranteed"],
                    "repeatable": d["repeatable"],
                    "rares_only": rares_only,
                    "hostile_only": hostile_only,
                    "notes": "",
                }
            )
    return out


def parse_encounters(inner: str) -> list[dict]:
    out: list[dict] = []
    pos = 0
    key_pat = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = key_pat.search(inner, pos)
        if not m:
            break
        eid = m.group(1)
        ob = m.end() - 1
        body, end = brace_match(inner, ob)
        pos = end
        npcs = re.findall(r"\b\d+\b", body)
        for nid in npcs:
            out.append(
                {
                    "category": "encounter_map",
                    "source_type": "encounter",
                    "source_id": nid,
                    "encounter_id": eid,
                    "quest_id": "",
                    "map_id": "",
                    "container_id": "",
                    "object_id": "",
                    "drop_type": "",
                    "item_id": "",
                    "item_name": "",
                    "table_drop_difficulty": "",
                    "statistic_ids": "",
                    "guaranteed": "",
                    "repeatable": "",
                    "rares_only": "",
                    "hostile_only": "",
                    "notes": "dungeonEncounterID -> npcID; drops on npc row",
                }
            )
    return out


def parse_encounter_names(inner: str) -> list[dict]:
    out: list[dict] = []
    pat = re.compile(r'\["((?:\\.|[^"\\])*)"\]\s*=\s*\{([^}]*)\}')
    for m in pat.finditer(inner):
        name = m.group(1).replace("\\'", "'")
        body = m.group(2)
        for nid in re.findall(r"\d+", body):
            out.append(
                {
                    "category": "encounter_name_map",
                    "source_type": "encounter_name",
                    "source_id": nid,
                    "encounter_id": "",
                    "quest_id": "",
                    "map_id": "",
                    "container_id": "",
                    "object_id": "",
                    "drop_type": "",
                    "item_id": "",
                    "item_name": "",
                    "table_drop_difficulty": "",
                    "statistic_ids": "",
                    "guaranteed": "",
                    "repeatable": "",
                    "rares_only": "",
                    "hostile_only": "",
                    "notes": name,
                }
            )
    return out


def parse_lockout_quests(inner: str) -> list[dict]:
    out: list[dict] = []
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", inner):
        out.append(
            {
                "category": "lockout_quest",
                "source_type": "lockout_quest",
                "source_id": m.group(1),
                "encounter_id": "",
                "quest_id": m.group(2),
                "map_id": "",
                "container_id": "",
                "object_id": "",
                "drop_type": "",
                "item_id": "",
                "item_name": "",
                "table_drop_difficulty": "",
                "statistic_ids": "",
                "guaranteed": "",
                "repeatable": "",
                "rares_only": "",
                "hostile_only": "",
                "notes": "npcID -> questID daily/weekly lockout",
            }
        )
    return out


def parse_sources_array(full: str) -> list[dict]:
    """Typed `sources = { ... }` entries (before legacyNpcs)."""
    out: list[dict] = []
    m = re.search(r"\bsources\s*=\s*\{", full)
    if not m:
        return out
    inner, _ = brace_match(full, m.end() - 1)
    # lockout_quest lines
    for lm in re.finditer(
        r'\{\s*sourceType\s*=\s*"lockout_quest"\s*,\s*npcID\s*=\s*(\d+)\s*,\s*questID\s*=\s*(\d+)',
        inner,
    ):
        out.append(
            {
                "category": "sources_typed",
                "source_type": "lockout_quest",
                "source_id": lm.group(1),
                "encounter_id": "",
                "quest_id": lm.group(2),
                "map_id": "",
                "container_id": "",
                "object_id": "",
                "drop_type": "",
                "item_id": "",
                "item_name": "",
                "table_drop_difficulty": "",
                "statistic_ids": "",
                "guaranteed": "",
                "repeatable": "",
                "rares_only": "",
                "hostile_only": "",
                "notes": "sources[]",
            }
        )
    for fm in re.finditer(
        r'\{\s*sourceType\s*=\s*"fishing"\s*,\s*mapIDs\s*=\s*\{([^}]*)\}\s*,\s*drops\s*=\s*(_\w+)',
        inner,
    ):
        maps = ",".join(re.findall(r"\d+", fm.group(1)))
        out.append(
            {
                "category": "sources_typed",
                "source_type": "fishing",
                "source_id": "",
                "encounter_id": "",
                "quest_id": "",
                "map_id": maps,
                "container_id": "",
                "object_id": "",
                "drop_type": "",
                "item_id": "",
                "item_name": "",
                "table_drop_difficulty": "",
                "statistic_ids": "",
                "guaranteed": "",
                "repeatable": "",
                "rares_only": "",
                "hostile_only": "",
                "notes": "drops=" + fm.group(2),
            }
        )
    return out


def main() -> int:
    if not DB_PATH.is_file():
        print("Missing", DB_PATH, file=sys.stderr)
        return 1
    text = DB_PATH.read_text(encoding="utf-8", errors="replace")

    cut = text.find("ns.CollectibleSourceDB = {")
    head = text[:cut] if cut > 0 else text
    shared = parse_shared_underscore_tables(head)

    rows: list[dict] = []
    rows.extend(parse_sources_array(text))

    for marker, cat, stype in [
        ("legacyNpcs = {", "npc", "instance_boss_or_npc"),
        ("legacyRares = {", "rare", "world_rare"),
        ("legacyObjects = {", "object", "object"),
        ("legacyFishing = {", "fishing", "fishing"),
    ]:
        inner = extract_marker_block(text, marker)
        if not inner:
            continue
        if marker.startswith("legacyFishing"):
            rows.extend(parse_keyed_npc_like(inner, cat, stype))
        else:
            rows.extend(parse_keyed_npc_like(inner, cat, stype))

    inner = extract_marker_block(text, "legacyContainers = {")
    if inner:
        rows.extend(parse_containers(inner, shared))

    inner = extract_marker_block(text, "legacyZones = {")
    if inner:
        rows.extend(parse_zones(inner, shared))

    inner = extract_marker_block(text, "legacyEncounters = {")
    if inner:
        rows.extend(parse_encounters(inner))

    inner = extract_marker_block(text, "legacyEncounterNames = {")
    if inner:
        rows.extend(parse_encounter_names(inner))

    inner = extract_marker_block(text, "legacyLockoutQuests = {")
    if inner:
        rows.extend(parse_lockout_quests(inner))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "category",
        "source_type",
        "source_id",
        "encounter_id",
        "quest_id",
        "map_id",
        "container_id",
        "object_id",
        "drop_type",
        "item_id",
        "item_name",
        "table_drop_difficulty",
        "statistic_ids",
        "guaranteed",
        "repeatable",
        "rares_only",
        "hostile_only",
        "notes",
    ]
    with OUT_TSV.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote {len(rows)} rows to {OUT_TSV}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
