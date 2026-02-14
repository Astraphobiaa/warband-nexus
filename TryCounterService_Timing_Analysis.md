# TryCounterService.lua — Timing & Race Condition Analysis

## Executive Summary

Analysis of five specific timing/race scenarios in the try counter system. **2 potential bugs** identified (auto-loot race, multiple LOOT_OPENED per kill); **3 scenarios** appear correctly handled with minor edge-case notes.

---

## 1. ENCOUNTER_END Timing vs LOOT_OPENED

### 1a. ENCOUNTER_END fires during the retry timer — double-count?

**Flow:**
- **LOOT_OPENED** fires first (e.g., during RP/cinematic) → `ProcessNPCLoot()` finds no drops (recentKills empty, GUIDs secret) → sets `_pendingEncounterLoot = true` (lines 1218–1221)
- **ENCOUNTER_END** fires → adds synthetic entries to `recentKills` (lines 516–526) → clears `_pendingEncounterLoot` and schedules retry via `C_Timer.After(0.5, ...)` (lines 728–736)
- Retry runs 0.5s later → calls `ProcessNPCLoot()` if `GetNumLootItems() > 0`

**Verdict: No double-count risk.**

- `ENCOUNTER_END` fires once per encounter. It does not fire again during the 0.5s retry.
- If retry runs: `ProcessNPCLoot()` processes loot, marks `processedGUIDs[dedupGUID]` (lines 968–976), and cleans encounter entries (lines 1258–1264).
- If the player later reopens the same corpse: `GetLootSourceInfo` returns the same source GUID → `processedGUIDs[sourceGUID]` check (line 879) returns early → no second count.

### 1b. Player opens loot, closes it, and reopens — does LOOT_OPENED fire twice?

**Yes.** Each open triggers `LOOT_OPENED`.

**Scenario A — Loot closed before ENCOUNTER_END:**
1. LOOT_OPENED → no drops (recentKills empty) → `_pendingEncounterLoot = true`
2. LOOT_CLOSED
3. ENCOUNTER_END → adds recentKills, schedules retry
4. Retry: `GetNumLootItems() == 0` (loot closed) → retry does nothing
5. LOOT_OPENED (reopen) → recentKills populated → `ProcessNPCLoot()` runs → processes once ✓

**Scenario B — Loot kept open, retry runs:**
1. LOOT_OPENED → `_pendingEncounterLoot = true`
2. ENCOUNTER_END → retry scheduled
3. Retry runs → `ProcessNPCLoot()` → marks `processedGUIDs`
4. LOOT_CLOSED
5. LOOT_OPENED (reopen) → same source GUID → `processedGUIDs` check → early return ✓

**Verdict: Correctly handled.** Reopen is deduplicated via `processedGUIDs`.

---

## 2. Auto-Loot Race

**Question:** With auto-loot enabled, does `LOOT_OPENED` fire before or after items are picked up? Could `GetNumLootItems()` return 0?

**Code path:** `ScanLootForItems()` (lines 396–420) uses `GetNumLootItems()` and iterates slots. If it returns 0, `found = {}` and all trackable drops are treated as "missed" → try count increments.

**Risk:** If auto-loot runs before or in the same frame as our handler, the loot window may be empty when we scan. We would:
- Treat a successful drop as "missed" → **incorrect increment**
- Or treat a real miss as miss → correct

**WoW API behavior (uncertain):** Documentation suggests `GetNumLootItems()` reflects the state when the window opens, but exact ordering of LOOT_OPENED vs auto-loot is not clearly specified. Some addons report timing sensitivity.

**Verdict: Potential bug — needs validation.**

**Mitigation options:**
1. **LOOT_SLOT_CLEARED** — listen for items leaving the window; if an expected item disappears before we scan, treat as "obtained" rather than "missed".
2. **Deferred scan** — `C_Timer.After(0, ScanLootForItems)` to run next frame; may still be too late with fast auto-loot.
3. **BAG_UPDATE** correlation — after LOOT_OPENED, check if the collectible appeared in bags; complex and may have false positives.

**Recommendation:** Add a short deferred scan (e.g. 0.05s) as a fallback when `GetNumLootItems() == 0` but we have a valid source and trackable drops. If the deferred scan still finds 0 items, proceed with the current logic.

---

## 3. LOOT_CLOSED Timing

**Question:** What if `LOOT_CLOSED` fires before `LOOT_OPENED` processing completes? Is there a risk of flags being cleared between check and processing?

**Relevant code:**
- `OnTryCounterLootClosed()` (lines 738–746): clears `isFishing`, `isPickpocketing`, `lastContainerItemID`
- `OnTryCounterLootOpened()` (lines 781–807): checks these flags and routes to `ProcessFishingLoot`, `ProcessContainerLoot`, or `ProcessNPCLoot`

**WoW event order:** For a single loot session, `LOOT_OPENED` always precedes `LOOT_CLOSED`. They are ordered.

**Lua execution:** WoW addon code is single-threaded. When `LOOT_OPENED` fires, the handler runs to completion before the next event. `LOOT_CLOSED` cannot fire "during" `OnTryCounterLootOpened` or `ProcessNPCLoot`/`ProcessFishingLoot`.

**Async case:** The only async path is the ENCOUNTER_END retry (`C_Timer.After(0.5, ...)`). That callback calls `ProcessNPCLoot()` directly, which does not use `isFishing` or `isPickpocketing`. So clearing those flags on `LOOT_CLOSED` does not affect the retry.

**Verdict: No race.** Flags are only used for routing at `LOOT_OPENED`; processing is synchronous.

---

## 4. Disconnect/Reload During Loot

**Question:** If the player disconnects or `/reload`s while a loot window is open, what happens to `recentKills` and encounter entries?

**State storage:**
- `recentKills`, `processedGUIDs`, `_pendingEncounterLoot`, `isFishing`, `isPickpocketing` are **in-memory only** (lines 149–156, 1218).
- They are **not** in SavedVariables.

**On disconnect/reload:**
- All Lua state is lost.
- `recentKills = {}`, `processedGUIDs = {}`, etc.

**Encounter entries:** Lost. After reload:
- If the player re-opens the same corpse: `GetLootSourceInfo` may still return a valid GUID (if the corpse exists). `processedGUIDs` is empty, so we would process again → **possible double-count** for that specific reopen-after-reload case.
- If the corpse despawned: no loot window, no count.

**Lockout state:** `SyncLockoutState()` (lines 491–516) runs 3s after init. It syncs `lockoutAttempted` from `C_QuestLog.IsQuestFlaggedCompleted`, so lockout behavior is preserved across reload.

**Verdict: Minor edge case.**

- Reload during loot is uncommon.
- If the corpse is still lootable after reload, we might count again. `processedGUIDs` TTL is 300s (line 32); a quick reload would lose it, so the second open could be counted.
- **Mitigation:** Consider persisting `processedGUIDs` (or a hash of recent encounter+source) to SavedVariables with a short TTL. Higher complexity for a rare case.

---

## 5. Multiple LOOT_OPENED Per Kill

**Question:** Some bosses have multiple loot windows (e.g., personal loot + bonus roll). Could this cause double-counting?

**Scenario:** Boss kill → LOOT_OPENED (personal loot) → LOOT_CLOSED → LOOT_OPENED (bonus roll) → LOOT_CLOSED.

**Current deduplication:**
- `processedGUIDs[sourceGUID]` (line 879) — we return early if we've already processed this GUID.
- `GetLootSourceInfo(slotIndex)` returns the GUID of the entity that provided the loot.

**Risk:** Personal loot and bonus roll may use **different** source GUIDs (e.g., boss corpse vs bonus roll object). If so:
- First LOOT_OPENED: sourceGUID = boss corpse → process → increment
- Second LOOT_OPENED: sourceGUID = bonus roll object → not in `processedGUIDs` → process again → **double increment**

**Verdict: Potential bug — needs validation.**

**Mitigation options:**
1. **Encounter-based dedup** — if we're in an instance and `recentKills` has encounter entries for this boss, mark the encounter as "processed" for a short window (e.g. 30s) and skip any subsequent LOOT_OPENED that matches that encounter.
2. **Time-based dedup** — within N seconds of a processed boss loot, skip any LOOT_OPENED that matches the same encounter/npcID.
3. **Empirical check** — verify whether bonus roll uses a different `GetLootSourceInfo` GUID; if it reuses the boss GUID, no change needed.

---

## Summary Table

| Scenario | Verdict | Action |
|----------|---------|--------|
| 1a. ENCOUNTER_END during retry | ✓ No bug | — |
| 1b. Open/close/reopen loot | ✓ Handled | — |
| 2. Auto-loot race | ⚠ Potential bug | Validate; consider deferred scan when GetNumLootItems()==0 |
| 3. LOOT_CLOSED timing | ✓ No race | — |
| 4. Disconnect/reload during loot | ⚠ Edge case | Optional: persist processedGUIDs with short TTL |
| 5. Multiple LOOT_OPENED (bonus roll) | ⚠ Potential bug | Validate GetLootSourceInfo; add encounter-based dedup if needed |

---

## Code Reference Summary

| Area | Lines |
|------|-------|
| Deferred retry (_pendingEncounterLoot) | 715–736, 1196–1224 |
| processedGUIDs deduplication | 879–880, 968–976 |
| LOOT_CLOSED flag clearing | 738–746 |
| ScanLootForItems / GetNumLootItems | 396–420, 537 |
| recentKills (in-memory) | 149, 516–526, 762–764, 1188–1214, 1258–1264 |
| SyncLockoutState (survives reload) | 491–516 |
