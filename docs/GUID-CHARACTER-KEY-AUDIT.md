# GUID / Character Key Audit (Warband Nexus)

## A1 — Character-keyed storage inventory

### Remapped by `MigrationService:ApplyCharacterKeyedStorageRenames`

| Storage path | Merge policy |
|--------------|--------------|
| `db.global.currencyData.currencies` | Move bucket; discard loser if survivor exists |
| `db.global.currencyData.totalEarned` | Same |
| `db.global.gearData` | `MergeGearDataBucket` |
| `db.global.pveProgress` | Move bucket |
| `db.global.pveCache.*` | Per-subtable move (`RemapPveCacheCharacterKeys`) |
| `db.global.statisticSnapshots` | Move or discard |
| `db.global.personalBanks` | Move or discard |
| `db.global.itemStorage` | Move or discard |
| `db.global.reputationData.characters` | Union factions; newer `lastScan` wins |
| `db.global.characterBankMoneyLogs[].character` | Field remap via rename map |
| `db.global.favoriteCharacters` | Array key replace + dedupe |
| `db.profile.characterGroupAssignments` | Key replace |
| `db.profile.characterOrder.*` | Array key replace |

### Not character-keyed / out of scope

| Storage | Notes |
|---------|-------|
| `db.global.plans[]` | Uses `characterName` + `characterRealm`; not a table index |
| `db.global.tryCounts` | Global by collectible id, not per character |
| `db.char.*` | AceDB per-character profile scope (separate lifecycle) |
| `db.global.warbandBank` | Account-wide |

### Read-side alias fallbacks (safety net, not persistence)

- `VaultCharKeysMatch` / `GetCanonicalCharacterKey`
- `CurrencyCacheService.ResolveCurrencyAliasBuckets`
- `ItemsCacheService.ResolveItemStorageRow` legacy lookup
- `VaultButton_Data.LookupPveCacheSubtable`

## A2 — `GetCharacterKey()` usage classification

| Category | Rule | Examples |
|----------|------|----------|
| **WRITE (fix)** | Must use `GetCharacterStorageKey` or `ResolveSubsidiaryCharacterKey` | `DataService`, `ItemsCacheService`, `PvECacheService`, `GearService`, `ReputationCacheService` |
| **READ** | Use `ResolveCharactersTableKey` or `GetCanonicalCharacterKey` | `CharacterService:IsCharacterTracked`, UI roster via `UI_GetCharKey` |
| **MSG** | Canonical key in `WN_*` payloads | `EventManager:OnMoneyChanged` |
| **DISPLAY / PLANS** | `GetCharacterKey(name, realm)` OK for labels and plan name-realm matching | `PlansManager`, `DailyQuestManager` plan keys |

High-risk write paths were updated to `ResolveSubsidiaryCharacterKey` in this pass.

## Roster deduplication (single path)

| Layer | API | When |
|-------|-----|------|
| Detection | `DataServiceRoster.CollectCharacterDuplicateRenames` | Merge-key grouping (GUID + Name-Realm cross-link) |
| Apply | `DataServiceRoster.ApplyCharacterRosterDeduplication` | Merge rows, remap subsidiaries, delete losers |
| Migration | `MigrationService:DeduplicateCharacterRoster` | After `MigrateGlobalCharactersToGuidStorageKeys` on `/reload` |
| Cleanup | `DatabaseCleanup` → `DeduplicateCharacterRoster` | Hourly + `/wn cleanup` |
| Login save | `RelocateLegacyCharacterSlot` | Legacy Name-Realm index → guid-shaped key only |

Display reads use `BuildMergedCharacterRosterView` so UI stays correct until DB dedup runs.
