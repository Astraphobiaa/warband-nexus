# Legacy Key Hard-Cut — Static Performance Report

**Scope:** Static audit (no runtime instrumentation). Applied optimizations and remaining risks from the Legacy Key Hard-Cut + Dedup plan.

---

## 1. Top CPU peak risks (priority order)

| Priority | Location | Risk | Mitigation applied |
|----------|----------|------|--------------------|
| **P1** | `Modules/UI/CharactersUI.lua` — `DrawCharacterList` | O(n²) inner loop per section (favorites, regular, untracked): for each character, a full list scan to find `actualPosition`. | **Fixed:** Use loop index `i` as position; removed inner `for pos, c in ipairs(list)` (three sections). |
| **P2** | `Modules/DataService.lua` — bag/bank full scan completion | On full scan, `SaveCurrentCharacterData()` was called, triggering full character save (professions, PvE, currencies, gear, etc.) and duplicate bag/bank copy. | **Fixed:** On full scan, only call `SaveItemsCompressed(key, "bags"|"bank", array)`; no full character save from scan path. |
| **P3** | `Modules/DataService.lua` — `GetItemCountsPerCharacter` / `GetDetailedItemCounts` | Iterated `charData.bags` and `GetPersonalBankV2` per character; double structure (character.bags + personalBanks). | **Fixed:** Single source via `GetItemsData(charKey)`; iterate `.bags` and `.bank` arrays only. |
| **P4** | Event handlers (e.g. `OnItemLevelChanged`, currency sync) | Ad-hoc key construction could cause duplicate DB lookups or wrong key writes. | **Fixed:** All character keys from `ns.Utilities:GetCharacterKey()` / `GetCharacterKey(name, realm)` only. |

**Remaining (no change in this pass):**

- **CharactersUI** — Guild column width: single pass over all visible characters to measure max guild name; O(n) with small n; acceptable.
- **GetAllCharacters** — Single pass with dedupe by canonical key; no change.
- **Throttle/Debounce** — Already used for `ITEM_LEVEL_UPDATE`, currency, and bag updates; no additional throttling added.

---

## 2. RAM pressure sources

| Source | Before | After |
|--------|--------|--------|
| **Character record `bags`** | Full copy of bag items in `db.global.characters[key].bags` (per character). | **Removed.** Bags live only in `db.global.itemStorage[key].bags` (ItemsCacheService). |
| **personalBanks vs itemStorage** | Bank data could exist in both `db.global.personalBanks[key]` and (after save) in character flow. | **Single write path:** Save path writes only to `itemStorage` via `SaveItemsCompressed`. `GetItemsData` still falls back to `personalBanks` for legacy SV. |
| **Duplicate key slots** | Legacy + canonical keys could both exist in characters, gearData, pveProgress, etc. | **One-time migration** rewrites all character-keyed tables to canonical keys; collision = keep newest by `lastSeen`. |
| **Item count cache** | `GetDetailedItemCounts` / `GetItemCountsPerCharacter` built from character.bags + personalBank. | Same cache TTL; data source is now single (`GetItemsData`); fewer intermediate tables. |

**Retention points (unchanged):**

- `decompressedItemCache` in ItemsCacheService (session; invalidated on scan).
- `itemSummaryIndex` per character (lazy rebuild on change).
- Currency/rep metadata caches (session-only, FIFO).

---

## 3. User impact assessment

| Area | Impact |
|------|--------|
| **UI stutter** | **Improved.** Character list render no longer does O(n²) position lookup per section; large favorite/regular/untracked lists should scroll and open sections with less CPU spike. |
| **Scan latency** | **Improved.** Bag/bank full scan no longer triggers full character save; only item storage is updated. Login and bank-open flows should feel lighter. |
| **Frame drops** | **Neutral to improved.** Fewer duplicate structures and single key path reduce chance of redundant work during events (e.g. `WN_ITEMS_UPDATED`, `WN_CHARACTER_UPDATED`). |
| **Character switch / data loss** | **Addressed.** Canonical key everywhere + one-time migration + no legacy fallback writes ensure one slot per character and correct reads after switch. |

---

## 4. Before/after complexity notes

| Change | Before | After |
|--------|--------|--------|
| **Character key construction** | Mixed: `name.."-"..realm`, `name:gsub().."-"..realm:gsub()`, and `Utilities:GetCharacterKey()`. | **Single source:** `Utilities:GetCharacterKey()` or `GetCharacterKey(name, realm)` only; no ad-hoc fallbacks. |
| **Character list position** | For each row, inner loop to find position in list (O(n²) per section). | Index `i` is position; one loop per section (O(n)). |
| **Bag/bank persistence** | SaveCurrentCharacterData wrote to character.bags and UpdatePersonalBankV2; scan path also called SaveCurrentCharacterData. | SaveCurrentCharacterData writes only to `itemStorage` via SaveItemsCompressed; scan path writes only SaveItemsCompressed (no full save). |
| **Item counts (tooltip, etc.)** | Read character.bags and GetPersonalBankV2 (which merged from multiple sources). | Read only GetItemsData(charKey); .bags and .bank arrays. |
| **DB character-keyed tables** | Only `characters` and `currencyData.currencies` normalized in migration. | **Full migration:** characters, currencyData.currencies, gearData, pveProgress, statisticSnapshots, personalBanks, favoriteCharacters, profile.characterOrder (favorites/regular/untracked); collision = keep newest by lastSeen. |

---

## 5. File/function reference summary

- **Canonical key only:** `EventManager.lua` (OnItemLevelChanged), `CurrencyCacheService.lua` (current player key), `DebugService.lua` (PrintPvEData), `TryCounterService.lua` (two call sites), `DataService.lua` (SaveMinimal, SaveCurrent, CaptureLogout, GenerateWeeklyAlerts, GetAllCharacters), `CharactersUI.lua`, `ProfessionsUI.lua` (GetCharKey).
- **Migration (all character-keyed):** `MigrationService.lua` — `MigrateCharacterKeyNormalize` (characters, currencyData.currencies, gearData, pveProgress, statisticSnapshots, personalBanks, favoriteCharacters, profile.characterOrder).
- **Dedup (no character.bags, single item store):** `DataService.lua` (SaveCurrentCharacterData, GetItemCountsPerCharacter, GetDetailedItemCounts, ScanCharacterBags, ScanPersonalBank); `ItemsCacheService.lua` (GetItemsData fallback to personalBanks for legacy).
- **CPU (O(n²) removal, no full save from scan):** `CharactersUI.lua` (DrawCharacterList — three sections), `DataService.lua` (ScanCharacterBags, bank scan — use SaveItemsCompressed only).

---

*Report generated as part of the Legacy Key Hard-Cut implementation. No runtime profiling was performed.*
