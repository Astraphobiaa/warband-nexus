# GUID character key audit (Warband Nexus)

Policy: **subsidiary SavedVariables use GUID** (`Player-…` from `UnitGUID("player")` via `SafeGuid`). Name-Realm is display, plans, and migration only.

Wiki: [API UnitGUID](https://warcraft.wiki.gg/wiki/API_UnitGUID) — returns the unit GUID; player tokens use the `Player-` prefix.

## Write path (required)

| Resolver | Use |
|----------|-----|
| `GetCharacterStorageKey(addon)` | Live session row + subsidiary writes |
| `ResolveSubsidiaryCharacterKey(addon, key?)` | Currency, gear, PvE, items, reputation buckets |
| `ResolveCharacterRowKey(charData)` | Offline row → storage key |
| `GetCharactersTablePersistKey` | Tracking dialog / first row create |

## Read path (required)

| Resolver | Use |
|----------|-----|
| `ResolveCharactersTableKey(addon)` | `db.global.characters[*]` logged-in index |
| `ResolveSubsidiaryCharacterKey` / `GetCanonicalCharacterKey` | Subsidiary cache lookup |
| `UI_GetCharKey(char)` | UI roster rows (GUID before raw `_key`) |

## Legacy bridges (gated)

Removed or skipped when `db.global.guidOnlySubsidiaryV1`:

- `ItemsCacheService` Name-Realm `itemStorage` alias read
- `CurrencyCacheService` `ResolveCurrencyAliasBuckets` / `VaultCharKeysMatch` totalEarned scan
- `GearService` `MigrateLegacyGearDataKey` on scan path
- `CharacterService:CharacterOwnsSubsidiaryKey` `VaultCharKeysMatch`

Pre-flag: first login runs `MigrateSubsidiaryOrphanKeys` + `MigrateSubsidiaryAliasBucketsV1`, then sets `guidOnlySubsidiaryV1`.

## Exceptions (Name-Realm retained)

- `GetCharacterKey()` / `GetCharacterKey(name, realm)` — display, diagnostics, migration
- `plans[]`, `PlansManager`, `DailyQuestManager`, `PlansManager_Vault`
- `MigrationService`, `DataService_RosterHelpers`
- `DataService` save paths: `legacyKey` merge into GUID slot on login
- `CharacterBankMoneyLogPopup` historic log entry keys
- `GetCharacterStorageKey` fallback when GUID secret/unavailable

## Commands

- `/wn guidmigrate` — force subsidiary orphan + alias remap
- `/wn charkeys` (debug on) — key diagnostics
- `/reload` — normal migration pipeline

## In-game test (minimum)

1. `/wn guidmigrate` then `/reload` on a character with pre-migration SV.
2. Items tab: bags match pre-migration counts (GUID `itemStorage` bucket).
3. Currency / Gear / PvE tabs: logged-in character data visible.
4. `/wn charkeys`: `storageKey` and `subsidiaryKey` are GUID-shaped when guid known.
5. Create plan for current character — still matches via Name-Realm plan fields.
