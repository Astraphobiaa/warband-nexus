#!/usr/bin/env python3
"""Static wiring checks for Warband Nexus module splits (_bind, Fns, RT snapshots, Frame APIs)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "Modules"

# Satellite chunks: underscore in basename, under Modules/
SATELLITE_GLOB = "**/*_*.lua"

SKIP_RT_SNAPSHOT_FILES = {
    "Modules/TryCounterService.lua",  # main chunk owns RT table
}

SKIP_RT_SNAPSHOT_SYMBOLS = {
    "vars",  # local V = RT.vars is intentional in main/handlers
}

# RT table fields reassigned after LoadRuntimeSourceTables (TryCounter satellites only).
TRY_COUNTER_REASSIGNED_RT_TABLES = {
    "npcDropDB",
    "objectDropDB",
    "fishingDropDB",
    "containerDropDB",
    "zoneDropDB",
    "encounterDB",
    "encounterNameToNpcs",
    "lockoutQuestsDB",
    "npcIDToEncounterID",
    "tryCounterNpcEligible",
    "instanceBossSlotOutcomeRules",
    "currentEncounterCache",
    "recentKills",
    "recentKillByNpcID",
    "lootSession",
    "fishingCtx",
    "processedGUIDs",
    "pendingEncounterLootSnapshot",
    "mergedStatSeedByTypeKey",
    "mergedStatSeedGroupList",
    "statSeedTryKeyPending",
    "statSeedWorkQueue",
    "runtimeStatReseedDropScratch",
    "pendingRuntimeStatNpcIds",
}


def extract_bind_keys(main_text: str, bind_marker: str) -> set[str]:
    idx = main_text.find(bind_marker)
    if idx < 0:
        return set()
    start = main_text.find("{", idx)
    if start < 0:
        return set()
    depth = 0
    for i in range(start, len(main_text)):
        c = main_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                body = main_text[start + 1 : i]
                return set(re.findall(r"^\s*(\w+)\s*=", body, re.M))
    return set()


def satellite_bind_aliases(sat_text: str, prefix: str) -> set[str]:
    return set(re.findall(rf"local \w+ = {re.escape(prefix)}(\w+)", sat_text))


def check_bind(main_rel: str, bind_marker: str, sat_rel: str, prefix: str) -> list[str]:
    errors: list[str] = []
    main = (ROOT / main_rel).read_text(encoding="utf-8")
    sat = (ROOT / sat_rel).read_text(encoding="utf-8")
    keys = extract_bind_keys(main, bind_marker)
    if not keys:
        errors.append(f"ERROR: no bind table {bind_marker} in {main_rel}")
        return errors
    aliases = satellite_bind_aliases(sat, prefix)
    missing = sorted(aliases - keys)
    if missing:
        errors.append(f"ERROR: {sat_rel} aliases missing from {bind_marker}: {missing}")
    return errors


def check_trycounter_fns() -> list[str]:
    defs: set[str] = set()
    calls: set[str] = set()
    skip = {
        "TryChat",
        "BuildObtainedChat",
        "ProcessChatLootEncounterForNpc",
        "RegisterQuestStarterMountKey",
        "StatisticSnapshotStorageKey",
    }
    for p in sorted(MODULES.glob("TryCounterService*.lua")):
        t = p.read_text(encoding="utf-8")
        defs.update(re.findall(r"function Fns\.(\w+)", t))
        defs.update(re.findall(r"Fns\.(\w+)\s*=\s*function", t))
        calls.update(re.findall(r"Fns\.(\w+)\(", t))
    missing = sorted(calls - defs - skip)
    if missing:
        return [f"ERROR: TryCounter Fns missing definitions: {missing}"]
    return []


def check_setname() -> list[str]:
    errors: list[str] = []
    for p in MODULES.rglob("*.lua"):
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith("libs/"):
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if ":SetName(" in line and "AceGUI" not in rel:
                errors.append(f"ERROR: {rel}:{i} uses :SetName (not a WoW Frame API)")
    return errors


def check_collections_draw_exports() -> list[str]:
    draw = MODULES / "UI" / "CollectionsUI_Draw.lua"
    if not draw.exists():
        return []
    t = draw.read_text(encoding="utf-8")
    if "local RequestCollectionFillFromUI = M.RequestCollectionFillFromUI" in t:
        return []
    if re.search(r"(?<![.\w])RequestCollectionFillFromUI\s*\(", t):
        return [
            "ERROR: CollectionsUI_Draw.lua calls RequestCollectionFillFromUI without M. alias"
        ]
    return []


def check_rt_snapshots() -> list[str]:
    """TryCounter satellites: no top-level snapshot of RT tables main reassigns after load."""
    errors: list[str] = []
    pat = re.compile(r"^local (\w+) = RT\.(\w+)\s*$")
    for p in sorted(MODULES.glob("TryCounterService_*.lua")):
        rel = p.relative_to(ROOT).as_posix()
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if not line.startswith("local "):
                continue
            m = pat.match(line.rstrip())
            if not m:
                continue
            sym = m.group(2)
            if sym not in TRY_COUNTER_REASSIGNED_RT_TABLES:
                continue
            errors.append(
                f"ERROR: {rel}:{i} top-level snapshot RT.{sym} - use RT.{sym} at use site"
            )
    return errors


def check_collections_state_snapshot() -> list[str]:
    errors: list[str] = []
    pat = re.compile(r"^local collectionsState = M\.state\s*$")
    for p in sorted((MODULES / "UI").glob("CollectionsUI*.lua")):
        rel = p.relative_to(ROOT).as_posix()
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if pat.match(line.strip()):
                errors.append(
                    f"ERROR: {rel}:{i} snapshots M.state - use M.state directly in callbacks"
                )
    return errors


def check_db_global_rt_corruption() -> list[str]:
    errors: list[str] = []
    for p in MODULES.rglob("*.lua"):
        rel = p.relative_to(ROOT).as_posix()
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if "db.global.RT." in line or "global.RT." in line:
                errors.append(f"ERROR: {rel}:{i} corrupt db path global.RT.*")
    return errors


def check_invalid_local_rt_syntax() -> list[str]:
    errors: list[str] = []
    pat = re.compile(r"^local RT\.")
    for p in MODULES.rglob("*.lua"):
        rel = p.relative_to(ROOT).as_posix()
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if pat.match(line.strip()):
                errors.append(f"ERROR: {rel}:{i} invalid syntax: local RT.*")
    return errors


def check_gear_slot_deps() -> list[str]:
    main = (ROOT / "Modules/UI/GearUI_Paperdoll.lua").read_text(encoding="utf-8")
    sat = (ROOT / "Modules/UI/GearUI_Paperdoll_Slots.lua").read_text(encoding="utf-8")
    keys = extract_bind_keys(main, "ns.GearUI_Paperdoll._slotDeps")
    used = set(re.findall(r'D\("(\w+)"\)', sat))
    missing = sorted(used - keys)
    if missing:
        return [f"ERROR: GearUI_Paperdoll_Slots.lua D() deps missing from _slotDeps: {missing}"]
    return []


def main() -> int:
    errors: list[str] = []
    errors.extend(
        check_bind(
            "Modules/UI/ItemsUI.lua",
            "ns.ItemsUI._bind",
            "Modules/UI/ItemsUI_StorageDraw.lua",
            "B.",
        )
    )
    errors.extend(
        check_bind(
            "Modules/UI.lua",
            "ns.UIShell._bind",
            "Modules/UI/UI_MainShell.lua",
            "B.",
        )
    )
    errors.extend(
        check_bind(
            "Modules/UI.lua",
            "ns.UIShell._bind",
            "Modules/UI/UI_TabHost.lua",
            "B.",
        )
    )
    errors.extend(check_gear_slot_deps())
    errors.extend(check_trycounter_fns())
    errors.extend(check_setname())
    errors.extend(check_collections_draw_exports())
    errors.extend(check_rt_snapshots())
    errors.extend(check_collections_state_snapshot())
    errors.extend(check_db_global_rt_corruption())
    errors.extend(check_invalid_local_rt_syntax())

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1
    print("check_split_wiring: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
