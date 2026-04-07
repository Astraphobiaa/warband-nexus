# CurseForge / Wago — **Warband Nexus v2.5.11** (2026-04-07)

## Summary for project description / changelog field

**v2.5.11** — PvE Trovehunter's Bounty column is per-character with Midnight-safe quest checks; weekly flag uses quest **86371** only. Collections **Achievements** tab enumerates all achievements correctly (`GetCategoryNumAchievements(..., true)`) with a one-time full re-scan. Try Counter mount/timer fixes, Lucent Hawkstrider mount ID, To-Do try popup left-click only, Information **Special Thanks** credits, locale updates.

## Full notes

### PvE
- Trovehunter's Bounty / Bountiful: per-character cache per header row; live API fallback only for current character; em dash + hint for alts without snapshot.
- `SafeIsQuestFlaggedCompleted` in PvE cache (pcall + secret guards).
- `PVE_BOUNTIFUL_WEEKLY_QUEST_IDS` = `{ 86371 }` only (removed OR with 92600 / 81514).

### Collections
- Achievement scan and UI: `GetCategoryNumAchievements(categoryID, true)` in `CollectionService` (async scan + title iterator paths).
- Migration: `wnAchievementIncludeAllScanV1` + achievement scan cooldown cleared once so `EnsureCollectionData` queues a full re-scan.

### Try Counter & data
- Collected mount/pet handling, missed-drop filtering, `C_Timer.After` callback fix.
- CollectibleSourceDB: Lucent Hawkstrider mount ID.

### UI
- SharedWidgets / PlanCardFactory / PlansUI / PlansTrackerWindow: try-count `popupOnRightClick = false` for To-Do cards.
- InformationDialog: Special Thanks (Contributors-style).

### Localization
- Credits subtitle (Special Thanks) across locales; `PVE_BOUNTY_NEED_LOGIN` (enUS); `CHANGELOG_V2511` (What's New).

---

Package: `WarbandNexus-2.5.11.zip` from `python build_addon.py` at repo root.
