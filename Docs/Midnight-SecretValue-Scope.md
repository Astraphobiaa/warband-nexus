# Midnight 12.0 Secret-Value Guard Scope

## Shared helpers (use these)

Defined in `Modules/Utilities.lua`:

- `Utilities:SafeString(val, fallback)` — use before any string method or display.
- `Utilities:SafeNumber(val, fallback)` — use before `tonumber` or numeric comparison.
- `Utilities:SafeBool(val, fallback)` — use for API-returned booleans that may be secret.
- `Utilities:SafeGuid(unit)` — use instead of raw `UnitGUID(unit)` when result may be used as key or in string ops.
- `Utilities:IsSecretValue(val)` — check only; do not use `val` if true.
- `Utilities:HasSecretValueAPI()` — true when `issecretvalue` exists (12.0+).

## API usage checklist (verify guard before use)

| API / source                | Files to verify |
|----------------------------|-----------------|
| `ENCOUNTER_END` args       | TryCounterService, PlansManager |
| `GetLootSourceInfo(slot)`  | TryCounterService |
| `UnitGUID("target" etc.)`  | TryCounterService, DataService, CurrencyCacheService |
| `EJ_GetEncounterInfoByIndex` returns | TryCounterService |
| `IsInInstance()` return    | TryCounterService, TooltipService |
| `GetStatistic(id)` return  | TryCounterService |
| `CHAT_MSG_LOOT` payload    | TryCounterService |
| Collection APIs (mount/pet/toy collected, IDs) | TooltipService, TryCounterService, CollectionsUI, PlansManager, NotificationManager |
| Tooltip `line:GetText()`   | TooltipService, CommandService |
| Reputation message text   | ReputationCacheService |

## Priority modules (already guarded or to migrate)

1. **TryCounterService.lua** — ENCOUNTER_END, GetLootSourceInfo, UnitGUID, EJ_*, IsInInstance, GetStatistic, CHAT_MSG_LOOT; uses local `issecretvalue` and SafeGetUnitGUID; optional migration to Utilities:Safe* for consistency.
2. **TooltipService.lua** — line:GetText(), collection API returns, IsInInstance; guarded; optional migration to Utilities:Safe*.
3. **ReputationCacheService.lua** — CHAT_MSG_COMBAT_FACTION_CHANGE message; guarded at parse; optional SafeString for message.
4. **CollectionService.lua** — collection API returns; ensure all call sites guard before string/number ops (CollectionsUI, PlansManager, NotificationManager already guard in places).

## UI Factory refactor scope (plan phase 3)

- **SettingsUI.lua**: Refactored to use `ns.UI.Factory:CreateContainer`, `CreateButton`, `CreateEditBox` and `FontManager:CreateFontString` for dropdown menu, main window, header, content area, ghosts, detail card, collapse button, and edit boxes. Slider remains `CreateFrame("Slider"...)` (no Factory:CreateSlider yet).
- **CollectionsUI.lua**: `CreateDetailEmptyOverlay` and `CreateModelViewer` panel use `Factory:CreateContainer`; remaining `CreateFrame` usages (e.g. scroll children, achievement rows, search row) are left as follow-up per-file tasks.
- **PlanCardFactory.lua**: Single `CreateFrame("Button"...)` for criteria link button; can be migrated to `Factory:CreateButton` in a follow-up.

## Rule

Before any string method (`:find()`, `:match()`, `:len()`, etc.), comparison, or `tonumber()` on values from the above APIs, either:

- Call `Utilities:IsSecretValue(val)` and skip use if true, or
- Use `Utilities:SafeString(val)`, `Utilities:SafeNumber(val)`, or `Utilities:SafeGuid(unit)` and use the result.
