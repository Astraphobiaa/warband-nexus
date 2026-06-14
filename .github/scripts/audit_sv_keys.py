#!/usr/bin/env python3
"""Audit Warband Nexus SavedVariables character-key health."""
import re
import sys
from pathlib import Path


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def slice_between(content: str, start_pat: str, end_pats: list[str], max_len: int = 900000) -> str:
    m = re.search(start_pat, content)
    if not m:
        return ""
    start = m.start()
    rest = content[start + 40 :]
    end = min(len(content), start + max_len)
    for ep in end_pats:
        em = re.search(ep, rest)
        if em:
            end = min(end, start + 40 + em.start())
            break
    return content[start:end]


def table_keys(block: str) -> tuple[set[str], set[str]]:
    guids = set(re.findall(r'\["(Player-\d+-\w+)"\]\s*=\s*\{', block))
    nrs: set[str] = set()
    for km in re.finditer(r'\["([^"]+)"\]\s*=\s*\{', block):
        k = km.group(1)
        if k.startswith("Player-"):
            continue
        if k.startswith("group_") or k.startswith("_"):
            continue
        if re.match(r"^\d+$", k):
            continue
        if "-" in k and re.match(r"^[A-Za-z]", k):
            nrs.add(k)
    return guids, nrs


def roster_gold(content: str) -> dict[str, tuple[str, int]]:
    block = slice_between(
        content,
        r'\["characters"\]\s*=\s*\{\s*\["Player-',
        [r'\["warbandBank"\]', r'\["cacheBackups"\]', r'\["plans"\]'],
        700000,
    )
    out: dict[str, tuple[str, int]] = {}
    for km in re.finditer(r'\["(Player-\d+-\w+)"\]\s*=\s*\{', block):
        guid = km.group(1)
        chunk = block[km.start() : km.start() + 12000]
        nm = re.search(r'\["name"\]\s*=\s*"([^"]+)"', chunk)
        gd = re.search(r'\["gold"\]\s*=\s*(\d+)', chunk)
        if nm and gd:
            out[guid] = (nm.group(1), int(gd.group(1)))
    return out


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else r"e:\World of Warcraft\_retail_\WTF\Account\436855179#1\SavedVariables\WarbandNexus.lua"
    bak_path = str(Path(path).with_suffix(".lua.bak"))
    content = read(path)
    bak = read(bak_path) if Path(bak_path).exists() else ""

    print(f"File: {path}")
    print(f"Size: {len(content) / 1024 / 1024:.2f} MB")
    if bak:
        print(f"Backup: {bak_path} ({len(bak) / 1024 / 1024:.2f} MB)")

    flags = [
        "charactersGuidKeyedV1",
        "charactersKeyNormalized",
        "charactersNameGuidConsolidatedV1",
        "subsidiaryOrphanRemapV1",
        "subsidiaryAliasConsolidatedV1",
        "guidOnlySubsidiaryV1",
        "_legacyReputationsDropV1",
        "_legacyGlobalCurrenciesDropV1",
    ]
    print("\n=== Migration flags ===")
    for fl in flags:
        m = re.search(r'\["' + re.escape(fl) + r'"\]\s*=\s*(true|false)', content)
        print(f"  {fl}: {m.group(1) if m else 'NOT SET'}")

    sections = [
        (
            "currencyData.currencies (live)",
            r'\["currencyData"\]\s*=\s*\{',
            r'\["currencies"\]\s*=\s*\{',
            [r'\["gearData"\]', r'\["reputationData"\]'],
        ),
        (
            "global.characters roster",
            r'\["characters"\]\s*=\s*\{\s*\["Player-',
            None,
            [r'\["warbandBank"\]', r'\["cacheBackups"\]', r'\["plans"\]'],
        ),
        (
            "reputationData.characters (live)",
            r'\["reputationData"\]\s*=\s*\{',
            r'\["characters"\]\s*=\s*\{',
            [r'\["profile"\]', r'\},\s*\["char"\]', r'\["plans"\]'],
        ),
        ("itemStorage", r'\["itemStorage"\]\s*=\s*\{', None, [r'\["warbandBank"\]', r'\["gearData"\]']),
        ("gearData", r'\["gearData"\]\s*=\s*\{', None, [r'\["pveProgress"\]', r'\["currencyData"\]']),
        (
            "cacheBackups.reputation (archive only)",
            r'\["cacheBackups"\]\s*=\s*\{',
            r'\["reputation"\]\s*=\s*\{',
            [r'\["pve"\]', r'\["currency"\]'],
        ),
    ]

    print("\n=== Subsidiary / roster keys ===")
    for name, outer, inner, ends in sections:
        if inner:
            om = re.search(outer, content)
            if not om:
                print(f"  {name}: section not found")
                continue
            sub = content[om.start() :]
            im = re.search(inner, sub)
            if not im:
                print(f"  {name}: inner not found")
                continue
            block_start = om.start() + im.start()
            block = slice_between(content[block_start:], r'.', ends, 800000)
            block = content[block_start : block_start + len(block)] if block else content[block_start : block_start + 800000]
        else:
            block = slice_between(content, outer, ends, 700000)
        guids, nrs = table_keys(block)
        tag = "OK" if not nrs or "archive" in name else ("WARN" if nrs else "OK")
        print(f"  [{tag}] {name}: GUID={len(guids)} NR={len(nrs)}")
        if nrs and len(nrs) <= 20:
            print(f"       NR sample: {sorted(nrs)[:12]}")

    rg = roster_gold(content)
    print(f"\n=== Roster integrity ({len(rg)} characters) ===")
    for g, (n, gold) in sorted(rg.items(), key=lambda x: x[1][0]):
        if n == "Superluminal":
            print(f"  Superluminal: {g} gold={gold}")

    if bak:
        rb = roster_gold(bak)
        missing = sorted(set(rb) - set(rg))
        extra = sorted(set(rg) - set(rb))
        print(f"\n=== vs .bak (roster count {len(rb)} -> {len(rg)}) ===")
        print(f"  Removed rows: {len(missing)}")
        if missing:
            print(f"    {missing}")
        print(f"  Added rows: {len(extra)}")
        if extra:
            print(f"    {extra}")
        gold_diff = []
        for g in set(rg) & set(rb):
            if rg[g][1] != rb[g][1]:
                gold_diff.append((rg[g][0], rg[g][1], rb[g][1]))
        print(f"  Gold changes (normal if you played): {len(gold_diff)}")
        for name, now, was in sorted(gold_diff, key=lambda x: -abs(x[1] - x[2]))[:10]:
            print(f"    {name}: {now} (was {was})")
        if not missing and not extra:
            print("  No roster row loss vs backup.")

    legacy_tables = ["personalBanks", "warbandBankV2", '["reputations"]']
    print("\n=== Legacy global tables ===")
    if re.search(r'\["personalBanks"\]\s*=\s*\{', content):
        print("  personalBanks: PRESENT (legacy)")
    else:
        print("  personalBanks: absent")
    if re.search(r'\["warbandBankV2"\]', content):
        print("  warbandBankV2: PRESENT (legacy)")
    else:
        print("  warbandBankV2: absent")
    if re.search(r'\["reputations"\]\s*=\s*\{', content) and not re.search(
        r'\["_legacyReputationsDropV1"\]\s*=\s*true', content
    ):
        print("  db.global.reputations: PRESENT (legacy)")
    else:
        print("  db.global.reputations: dropped/absent")


def line_range_audit(path: str) -> None:
    """Fast path: use known line anchors from grep when regex slicing is ambiguous."""
    lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
    ranges = {
        "currencyData.currencies": (8967, 94738),
        "global.characters": (94738, 104000),
        "reputationData.characters": (238855, 250433),
        "itemStorage": (7434, 7630),
    }
    print("\n=== Line-range audit (live slices) ===")
    for name, (a, b) in ranges.items():
        block = "\n".join(lines[a:b])
        guids, nrs = table_keys(block)
        tag = "OK" if not nrs else "WARN"
        print(f"  [{tag}] {name}: GUID={len(guids)} NR={len(nrs)}")
        if nrs:
            print(f"       NR: {sorted(nrs)[:8]}")


if __name__ == "__main__":
    main()
    line_range_audit(sys.argv[1] if len(sys.argv) > 1 else r"e:\World of Warcraft\_retail_\WTF\Account\436855179#1\SavedVariables\WarbandNexus.lua")
