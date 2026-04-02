# Audit helper: parse a shallow-cloned third-party DB under .tmp-addon-db-audit for itemId -> npcs.
import re
import pathlib
from collections import defaultdict


def extract_braced_block(s: str, open_brace_index: int) -> tuple[str | None, int]:
    i = open_brace_index
    depth = 0
    j = i
    while j < len(s):
        c = s[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return s[i : j + 1], j + 1
        j += 1
    return None, open_brace_index


def parse_lua_file(path: pathlib.Path, cat: str):
    text = path.read_text(encoding="utf-8", errors="replace")
    out = []
    for m in re.finditer(r'\["([^"]+)"\]\s*=\s*\{', text):
        name = m.group(1)
        start = m.end() - 1
        block, _ = extract_braced_block(text, start)
        if not block:
            continue
        im = re.search(r"itemId\s*=\s*(\d+)", block)
        if not im:
            continue
        item_id = int(im.group(1))
        npcs = []
        nm = re.search(r"npcs\s*=\s*(\{)", block)
        if nm:
            sub, _ = extract_braced_block(block, nm.start(1))
            if sub:
                npcs = [int(x) for x in re.findall(r"\b(\d+)\b", sub[1:-1])]
        if npcs:
            out.append((item_id, name, npcs, path.name, cat))
    return out


def main():
    repo = pathlib.Path(__file__).resolve().parents[1] / ".tmp-addon-db-audit" / "DB"
    by_item: dict[int, set[int]] = defaultdict(set)
    meta: dict[int, tuple[str, str, str]] = {}
    for sub in ("Mounts", "Pets", "Toys"):
        d = repo / sub
        if not d.is_dir():
            continue
        for p in sorted(d.glob("*.lua")):
            for item_id, name, npcs, fname, cat in parse_lua_file(p, sub):
                by_item[item_id].update(npcs)
                meta[item_id] = (name, fname, cat)

    out_tsv = repo.parent / "_extracted_item_npcs.tsv"
    with out_tsv.open("w", encoding="utf-8") as f:
        for item_id in sorted(by_item):
            name, fname, cat = meta[item_id]
            ids = " ".join(str(x) for x in sorted(by_item[item_id]))
            f.write(f"{item_id}\t{cat}\t{fname}\t{name}\t{ids}\n")
    print("entries_with_npcs", len(by_item))
    print("wrote", out_tsv)


if __name__ == "__main__":
    main()
