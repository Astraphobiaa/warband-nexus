#!/usr/bin/env python3
"""
Full-source audit: Warband Nexus CollectibleSourceDB vs WowRarity/Rarity mount DB.

Compares (mounts only):
  - WN: same mount itemID in multiple top-level sections (legacy vs sources)
  - NPC method: itemId presence; optional NPC ID coverage vs Rarity's npcs={}
  - USE method: Rarity `items` token IDs vs WN legacyContainers keys (+ mount in drops)
  - ZONE / FISHING / other methods: listed for manual review (no auto "missing" flags)

Usage (repo root):
  pip install none  # stdlib only
  python scripts/audit_wn_vs_rarity.py
  python scripts/audit_wn_vs_rarity.py --out .tmp/audit-wn-rarity.txt

Requires: .tmp/rarity-mounts/*.lua from
  https://github.com/WowRarity/Rarity/tree/master/DB/Mounts
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = Path(__file__).resolve().parents[1]
WN_PATH = ROOT / "Modules" / "CollectibleSourceDB.lua"
RARITY_DIR = ROOT / ".tmp" / "rarity-mounts"

ENTRY_START = re.compile(r'^\s*\[["\']([^"\']+)["\']\]\s*=\s*\{', re.M)


def parse_wn_mounts_by_section(text: str) -> list[tuple[int, str, int]]:
    """Mount rows under legacy* / sources with top-level section name."""
    lines = text.splitlines()
    start_idx = None
    for i, line in enumerate(lines):
        if "ns.CollectibleSourceDB = {" in line:
            start_idx = i
            break
    if start_idx is None:
        return []

    section: str | None = None
    brace = 0
    out: list[tuple[int, str, int]] = []
    for i in range(start_idx, len(lines)):
        line = lines[i]
        pre = brace
        if pre == 1:
            m = re.match(
                r"\s*(legacyNpcs|legacyRares|legacyContainers|legacyZones|legacyObjects|"
                r"legacyFishing|legacyEncounters|sources)\s*=\s*\{",
                line,
            )
            if m:
                section = m.group(1)
        if 'type = "mount"' in line:
            mid = re.search(r"itemID\s*=\s*(\d+)", line)
            if mid and section:
                out.append((int(mid.group(1)), section, i + 1))
        brace += line.count("{") - line.count("}")
        if pre >= 2 and brace == 1:
            section = None
        if brace <= 0 and i > start_idx:
            break
    return out


def extract_table_body(full_text: str, marker: str) -> str | None:
    """Return substring inside `marker` = { ... } at ns.CollectibleSourceDB scope (best-effort)."""
    idx = full_text.find(marker)
    if idx < 0:
        return None
    brace_start = full_text.find("{", idx)
    if brace_start < 0:
        return None
    depth = 0
    i = brace_start
    while i < len(full_text):
        c = full_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return full_text[brace_start + 1 : i]
        i += 1
    return None


def mounts_in_block(block: str) -> list[int]:
    ids: list[int] = []
    for m in re.finditer(
        r'type\s*=\s*"mount"[^}\n]*itemID\s*=\s*(\d+)', block, re.DOTALL
    ):
        ids.append(int(m.group(1)))
    for m in re.finditer(r'\{ type = "mount", itemID = (\d+)', block):
        ids.append(int(m.group(1)))
    return ids


def extract_numeric_key_mounts(section_body: str) -> dict[int, set[int]]:
    """[id] = { ... } blocks -> key_id -> set of mount itemIDs."""
    out: dict[int, set[int]] = defaultdict(set)
    pos = 0
    key_re = re.compile(r"\[(\d+)\]\s*=\s*\{")
    while True:
        m = key_re.search(section_body, pos)
        if not m:
            break
        key_id = int(m.group(1))
        start = m.end() - 1
        depth = 0
        i = start
        while i < len(section_body):
            c = section_body[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    block = section_body[start : i + 1]
                    for mid in mounts_in_block(block):
                        out[key_id].add(mid)
                    pos = i + 1
                    break
            i += 1
        else:
            break
    return dict(out)


def wn_mount_item_ids(text: str) -> set[int]:
    ids: set[int] = set()
    for m in re.finditer(r'type\s*=\s*"mount"[^\n]*itemID\s*=\s*(\d+)', text):
        ids.add(int(m.group(1)))
    for m in re.finditer(r'itemID\s*=\s*(\d+)[^\n]*type\s*=\s*"mount"', text):
        ids.add(int(m.group(1)))
    for m in re.finditer(r'\{ type = "mount", itemID = (\d+)', text):
        ids.add(int(m.group(1)))
    return ids


def wn_item_to_npcs(text: str) -> dict[int, set[int]]:
    """Mount itemID -> NPC IDs that list that mount (legacyNpcs + legacyRares only)."""
    npcs_sec = extract_table_body(text, "legacyNpcs =")
    rares_sec = extract_table_body(text, "legacyRares =")
    m: dict[int, set[int]] = defaultdict(set)
    for sec in (npcs_sec, rares_sec):
        if not sec:
            continue
        for nid, mids in extract_numeric_key_mounts(sec).items():
            for iid in mids:
                m[iid].add(nid)
    return dict(m)


def wn_container_to_mounts(text: str) -> dict[int, set[int]]:
    """Container itemID -> mount itemIDs from legacyContainers."""
    sec = extract_table_body(text, "legacyContainers =")
    if not sec:
        return {}
    return extract_numeric_key_mounts(sec)


def wn_mount_to_container_tokens(text: str) -> dict[int, set[int]]:
    """Mount itemID -> container item keys that list that mount."""
    c2m = wn_container_to_mounts(text)
    m2c: dict[int, set[int]] = defaultdict(set)
    for cid, mids in c2m.items():
        for mid in mids:
            m2c[mid].add(cid)
    return dict(m2c)


def split_rarity_mount_entries() -> list[tuple[str, str]]:
    """(entry_name, block_after_opening_brace) for mount-type chunks."""
    chunks: list[tuple[str, str]] = []
    for path in sorted(RARITY_DIR.glob("*.lua")):
        t = path.read_text(encoding="utf-8", errors="replace")
        starts = list(ENTRY_START.finditer(t))
        for i, m in enumerate(starts):
            name = m.group(1)
            start = m.end() - 1
            end = starts[i + 1].start() if i + 1 < len(starts) else len(t)
            block = t[start:end]
            if "ITEM_TYPES.MOUNT" not in block:
                continue
            chunks.append((f"{path.name}::{name}", block))
    return chunks


def parse_rarity_block(block: str) -> dict:
    method_m = re.search(r"method\s*=\s*CONSTANTS\.DETECTION_METHODS\.(\w+)", block)
    item_m = re.search(r"\bitemId\s*=\s*(\d+)", block)
    npcs_m = re.search(r"npcs\s*=\s*\{([^}]*)\}", block, re.S)
    items_m = re.search(r"\bitems\s*=\s*\{([^}]*)\}", block, re.S)
    zone_m = re.search(r"zoneId\s*=\s*([^,\n]+)", block)
    return {
        "method": method_m.group(1) if method_m else None,
        "itemId": int(item_m.group(1)) if item_m else None,
        "npcs": _ints(npcs_m.group(1)) if npcs_m else [],
        "items": _ints(items_m.group(1)) if items_m else [],
        "zoneId": zone_m.group(1).strip() if zone_m else None,
    }


def _ints(s: str) -> list[int]:
    return [int(x) for x in re.findall(r"\b\d+\b", s)]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, help="Write full report to this file")
    args = ap.parse_args()

    lines: list[str] = []

    def pr(msg: str = "") -> None:
        lines.append(msg)

    if not WN_PATH.is_file():
        raise SystemExit(f"Missing {WN_PATH}")
    wn_text = WN_PATH.read_text(encoding="utf-8")
    wn_mounts = wn_mount_item_ids(wn_text)
    wn_item_npcs = wn_item_to_npcs(wn_text)
    wn_c2m = wn_container_to_mounts(wn_text)
    wn_m2c = wn_mount_to_container_tokens(wn_text)

    wn_pets = set(int(m.group(1)) for m in re.finditer(r'type\s*=\s*"pet"[^\n]*itemID\s*=\s*(\d+)', wn_text))
    wn_toys = set(int(m.group(1)) for m in re.finditer(r'type\s*=\s*"toy"[^\n]*itemID\s*=\s*(\d+)', wn_text))

    pr("=== Warband Nexus CollectibleSourceDB (mounts) ===")
    pr(f"Unique mount itemIDs (file-wide heuristic): {len(wn_mounts)}")
    pr(f"Unique pet itemIDs (inline type=pet rows): {len(wn_pets)}")
    pr(f"Unique toy itemIDs (inline type=toy rows): {len(wn_toys)}")
    pr(f"NPC keys (legacyNpcs+rares) with ≥1 mount: {sum(1 for _k, v in wn_item_npcs.items() if v)}")
    pr(f"Container keys with ≥1 mount: {len(wn_c2m)}")
    pr("(Pets/toys: no external DB compared in this script; Rarity uses separate item DBs.)")
    pr()

    wn_by_section = parse_wn_mounts_by_section(wn_text)
    by_item_sec: dict[int, list[tuple[str, int]]] = defaultdict(list)
    for iid, sec, ln in wn_by_section:
        by_item_sec[iid].append((sec, ln))
    multi_sec = {k: v for k, v in by_item_sec.items() if len({s for s, _ in v}) > 1}
    pr("=== WN mounts by top-level section (legacy + sources) ===")
    pr(f"  Mount rows with section tag: {len(wn_by_section)}")
    pr(f"  Same itemID in multiple sections: {len(multi_sec)}")
    pr("  (Often intentional: legacyNpcs boss + legacyObjects raid chest.)")
    for iid in sorted(multi_sec.keys())[:50]:
        secs = sorted({s for s, _ in multi_sec[iid]})
        pr(f"    itemID {iid}: {secs}")
    if len(multi_sec) > 50:
        pr(f"    ... and {len(multi_sec) - 50} more")
    pr()

    if not RARITY_DIR.is_dir():
        pr("ERROR: Rarity dir missing. Clone files to .tmp/rarity-mounts/ (see CONTRIBUTING.md).")
        out = "\n".join(lines)
        print(out)
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(out, encoding="utf-8")
        raise SystemExit(1)

    by_method: dict[str, int] = defaultdict(int)
    rarity_rows: list[tuple[str, dict]] = []
    for label, block in split_rarity_mount_entries():
        info = parse_rarity_block(block)
        if not info["itemId"]:
            continue
        m = info["method"] or "UNKNOWN"
        by_method[m] += 1
        rarity_rows.append((label, info))

    pr("=== Rarity DB/Mounts (parsed entries with itemId) ===")
    for k in sorted(by_method.keys(), key=lambda x: (-by_method[x], x)):
        pr(f"  {k}: {by_method[k]}")
    pr(f"  TOTAL: {len(rarity_rows)}")
    pr()

    only_r = sorted({r[1]["itemId"] for r in rarity_rows} - wn_mounts)
    only_wn = sorted(wn_mounts - {r[1]["itemId"] for r in rarity_rows})
    rarity_id_to_label: dict[int, str] = {}
    for label, info in rarity_rows:
        iid = info["itemId"]
        if iid not in rarity_id_to_label:
            rarity_id_to_label[iid] = label

    pr("=== Set diff (itemId) ===")
    pr(f"In Rarity but not any WN mount row: {len(only_r)}")
    pr(f"In WN but not Rarity itemId list: {len(only_wn)}")
    pr("(WN tracks Midnight/TWW subset; Rarity includes vendors/removed IDs — both diffs are expected in part.)")
    pr()
    pr("=== Rarity-only mount itemIds (full list) ===")
    for iid in only_r:
        pr(f"  {iid}\t{rarity_id_to_label.get(iid, '')}")
    pr()
    pr("=== WN-only mount itemIds (sample 60; Rarity may omit or use different itemId) ===")
    for iid in only_wn[:60]:
        pr(f"  {iid}")
    if len(only_wn) > 60:
        pr(f"  ... +{len(only_wn) - 60} more")
    pr()

    # NPC: Rarity lists npcs, WN should have item + overlap
    pr("=== Rarity NPC method — item missing from WN ===")
    npc_missing: list[tuple[str, int, list[int]]] = []
    npc_review: list[tuple[str, int, list[int], set[int]]] = []
    for label, info in rarity_rows:
        if info["method"] != "NPC" or not info["npcs"]:
            continue
        iid = info["itemId"]
        npcs = info["npcs"]
        if iid not in wn_mounts:
            npc_missing.append((label, iid, npcs))
            continue
        wn_n = wn_item_npcs.get(iid, set())
        if not wn_n:
            continue
        rarity_set = set(npcs)
        if rarity_set <= {99999}:
            continue
        if not rarity_set.intersection(wn_n):
            npc_review.append((label, iid, npcs, wn_n))

    for row in npc_missing:
        pr(f"  MISSING_MOUNT  {row[1]}  npcs={row[2]}  ({row[0]})")
    if not npc_missing:
        pr("  (none)")
    pr()

    pr("=== Rarity NPC method — mount in WN but zero overlapping NPC IDs ===")
    pr("(Often OK: WN uses object/chest, encounter, zone_drop, or different NPC set.)")
    for row in npc_review[:80]:
        pr(f"  REVIEW  item={row[1]}  rarity_npcs={row[2]}  wn_npcs={sorted(row[3])}  ({row[0]})")
    if len(npc_review) > 80:
        pr(f"  ... {len(npc_review) - 80} more")
    if not npc_review:
        pr("  (none)")
    pr()

    pr("=== Rarity USE method — container token vs WN legacyContainers ===")
    use_gaps: list[tuple[str, int, int, str]] = []
    use_mismatch: list[str] = []
    for label, info in rarity_rows:
        if info["method"] != "USE":
            continue
        iid = info["itemId"]
        tokens = info["items"]
        if not tokens:
            continue
        if iid not in wn_mounts:
            continue
        wn_tokens = wn_m2c.get(iid, set())
        for t in tokens:
            drops = wn_c2m.get(t)
            if drops is None or iid not in drops:
                use_gaps.append((label, iid, t, "missing_or_wrong_drop"))
        if wn_tokens and not set(tokens).intersection(wn_tokens):
            use_mismatch.append(
                f"  TOKEN_MISMATCH  mount={iid}  rarity_items={tokens}  wn_container_keys={sorted(wn_tokens)}  ({label})"
            )
    for row in use_mismatch[:40]:
        pr(row)
    if len(use_mismatch) > 40:
        pr(f"  ... {len(use_mismatch) - 40} more TOKEN_MISMATCH")
    for row in use_gaps[:80]:
        pr(f"  USE_GAP  mount={row[1]}  token={row[2]}  ({row[0]})")
    if len(use_gaps) > 80:
        pr(f"  ... {len(use_gaps) - 80} more USE_GAP")
    if not use_gaps and not use_mismatch:
        pr("  (Rarity USE tokens match WN container keys + mount drops)")
    pr()

    pr("=== Other Rarity methods (counts only; manual cross-check) ===")
    for method in sorted(by_method.keys()):
        if method in ("NPC", "USE"):
            continue
        sample = [r for r in rarity_rows if (r[1]["method"] or "") == method and r[1]["itemId"] not in wn_mounts]
        pr(f"  {method}: {by_method[method]} entries; ~{len(sample)} itemIds not in WN mount set")

    out = "\n".join(lines)
    print(out)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(out, encoding="utf-8")


if __name__ == "__main__":
    main()
