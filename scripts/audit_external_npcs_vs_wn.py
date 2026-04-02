# Compare third-party DB npc lists (TSV from extract_external_db_npcs.py) to CollectibleSourceDB npc assignments.
import pathlib
import re
from collections import defaultdict


def extract_braced_block(s: str, open_brace_index: int) -> tuple[str | None, int]:
    depth = 0
    j = open_brace_index
    while j < len(s):
        c = s[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return s[open_brace_index : j + 1], j + 1
        j += 1
    return None, open_brace_index


def parse_wn_npc_assignments(cdb_text: str):
    """Map itemID -> set(npcID) from shared drop tables + [npc]=_alias."""
    alias_to_items: dict[str, set[int]] = defaultdict(set)
    for m in re.finditer(r"local\s+(_\w+)\s*=\s*\{", cdb_text):
        start = m.end() - 1
        block, _ = extract_braced_block(cdb_text, start)
        if not block:
            continue
        alias = m.group(1)
        for im in re.finditer(r"itemID\s*=\s*(\d+)", block):
            alias_to_items[alias].add(int(im.group(1)))

    item_to_npcs: dict[int, set[int]] = defaultdict(set)
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(_\w+)\s*,", cdb_text):
        npc = int(m.group(1))
        alias = m.group(2)
        for item_id in alias_to_items.get(alias, ()):
            item_to_npcs[item_id].add(npc)
    return item_to_npcs


def load_external_tsv(tsv_path: pathlib.Path) -> dict[int, set[int]]:
    out: dict[int, set[int]] = defaultdict(set)
    for line in tsv_path.read_text(encoding="utf-8").splitlines():
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        item_id = int(parts[0])
        ids = {int(x) for x in parts[4].split() if x.isdigit()}
        out[item_id] = ids
    return out


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    tsv = root / ".tmp-addon-db-audit" / "_extracted_item_npcs.tsv"
    cdb = (root / "Modules" / "CollectibleSourceDB.lua").read_text(encoding="utf-8", errors="replace")
    ext = load_external_tsv(tsv)
    wn = parse_wn_npc_assignments(cdb)

    missing_report = []
    for item_id, ext_npcs in sorted(ext.items()):
        wn_npcs = wn.get(item_id, set())
        miss = ext_npcs - wn_npcs
        if miss:
            missing_report.append((item_id, sorted(miss), sorted(ext_npcs), sorted(wn_npcs)))

    print("external_items_with_npcs", len(ext))
    print("wn_items_with_npc_assignments", len(wn))
    print("items_with_missing_npc_ids", len(missing_report))
    for item_id, miss, ext_all, wn_all in missing_report[:80]:
        print(f"item {item_id}: missing {miss} (ext {len(ext_all)} wn {len(wn_all)})")
    if len(missing_report) > 80:
        print(f"... and {len(missing_report) - 80} more")

    outp = root / ".tmp-addon-db-audit" / "_missing_npcs_in_wn.tsv"
    with outp.open("w", encoding="utf-8") as f:
        for item_id, miss, ext_all, wn_all in missing_report:
            f.write(
                f"{item_id}\t{','.join(map(str, miss))}\t"
                f"ext={len(ext_all)}\twn={len(wn_all)}\n"
            )
    print("wrote", outp)


if __name__ == "__main__":
    main()
