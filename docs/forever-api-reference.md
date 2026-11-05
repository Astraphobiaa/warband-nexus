# WoW Forever - API reference and capability findings

Measured on the live client: build 70790, interface 16001 (game type `camelot`/`forever`).
Signatures come from the client's own `Blizzard_APIDocumentationGenerated`: 410 systems,
6621 functions, 1816 events.

## The one thing to remember

**API presence proves nothing about WoW Forever.** Forever and Midnight are two game types
inside the same Mainline build, so the client ships every retail namespace either way. Its own
documentation lists the retail-only systems in full:

```
C_WeeklyRewards    21 documented functions
C_MythicPlus       21 documented functions
C_DelvesUI         40 documented functions
C_Bank             26 documented functions
C_ItemUpgrade      16 documented functions
```

`C_EventUtils.IsEventValid` is the same trap: of the 77 events this addon registers, all 77 are
valid on Forever. They simply never fire. Decide from DATA, never from the API surface.

## Detecting the flavour

```lua
-- canonical (wiki): WOW_PROJECT_CAMELOT is 18
if WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then end
-- documented fallback: interface band
local v = select(4, GetBuildInfo())  -- 16001 here; forever is 16000..19999
```

`C_GameRules.IsStandard()` returns **true** on Forever, so it is not a discriminator.
`C_GameRules.GetForeverExperiencePreset()` returns a number and is Forever-specific.
`IsGameRuleActive` is documented for the ruleset values only (`HardcoreRuleset`, `PvPRuleset`,
`RPRuleset`); asking it about other rules answered true for 41 and raised for 128, never false.

## What Forever actually has

| System | Status | Evidence |
|---|---|---|
| Level cap | 60 | `GetMaxPlayerLevel()` |
| War Mode | absent | `C_PvP.IsWarModeFeatureEnabled()` false (Blizzard-documented) |
| Legacy System | **present** | major faction 2802 `Legacy Track`, renown tiers 15/25/40/55 |
| PvP ranks | **present** | major faction 2800, 14 levels; `Enum.PvPRanks` Rank_1..Rank_14 |
| Transmog / Collections | **present** | account-wide; loot adds appearances |
| Reputation | **present** | classic ladder via `C_Reputation` walk |
| Merchant's Favor | **present** | currency 3402 |
| Great Vault | absent | no vault content; `GetActivities()` empty |
| Mythic+ / keystones | absent | `GetMapTable()` empty, `GetOwnedKeystoneLevel()` nil |
| Delves | absent | `GetCurrentDelvesSeasonNumber()` 0 |
| Warband (account) bank | absent | `CanViewBank(Account)` false |
| Item upgrade / crests | absent | `GetItemUpgradeItemInfo()` nil |
| Crafting orders | absent | `GetCrafterOrders()` empty |
| Profession knowledge / concentration | absent | `GetChildProfessionInfos()` empty |
| WoW Token | absent | `GetCommerceSystemStatus()` false, no market price |
| Rated PvP (2v2/3v3/RBG/Shuffle/Blitz) | absent | vanilla honor ladder only |
| Paragon | absent | 0 of 5 factions report paragon |

Caveat worth keeping: several "absent" rows rest on calls that answer from CHARACTER state, and
they were measured on a level 6 character. An empty Great Vault also happens on retail at low
level. The rows above combine that with the content Forever is documented to ship.

## Forever-specific events

```
ALERT_AGE_VERIFICATION_RESTRICTED()
BC_26_COLD_SWAP_FEATURE_ENABLED_CHANGED(newEnabled:bool, oldEnabled:bool)
BC_26_EXPERIENCE_CHANGED(newExperience:Bc26Experience, oldExperience:Bc26Experience)
CHAT_MSG_COLLECTED_APPEARANCE(text:cstring, playerName:cstring, languageName:cstring, channelName:cstring, playerName2:cstring, specialFlags:cstring, zoneChannelID:number, channelIndex:number, channelBaseName:cstring, languageID:number, lineID:number, guid:WOWGUID, bnSenderID:number, isMobile:bool, isSubtitle:bool, hideSenderInLetterbox:bool, suppressRaidIcons:bool, discordInfo:DiscordChatInfo)
DIEL_CYCLE_CHANGED(isDayTime:bool)
GAME_RULES_CHANGED()
GLOBAL_REGION_MOUSE_DOWN(region:ScriptRegion, button:cstring)
GLOBAL_REGION_MOUSE_UP(region:ScriptRegion, button:cstring)
PLAYER_SWING(swingDuration:number, swingType:PlayerSwingType)
PLAYER_SWING_RANGE_UPDATE(swingType:PlayerSwingType, isInRange:bool, checksRange:bool)
SHARD_TRANSFER()
SHARD_TRANSFER_CANCELLED()
SHARD_TRANSFER_IMMINENT()
UNIT_HAPPINESS(unitTarget:UnitTokenVariant)
UNIT_PET_TRAINING_POINTS(unitTarget:UnitTokenVariant)
```

## C_GameRules

Forever's own surface. `GetForeverExperiencePreset` is the flavour tell.

```
C_GameRules.AccountHasSDEnabled() -> isSDEnabled:bool
C_GameRules.AutoConnectToGameModeRealm(gameModeRecordID:number) -> 
C_GameRules.DoesGameModeHavePromo(gameModeRecordID:number) -> hasPromo:bool
C_GameRules.GetActiveGameMode() -> gameMode:GameMode
C_GameRules.GetCurrentEventRealmQueues() -> eventRealmQueues:EventRealmQueues
C_GameRules.GetCurrentGameModeDisplayInfo() -> info:GameModeDisplayInfo?
C_GameRules.GetCurrentGameModeRecordID() -> gameModeRecordID:number
C_GameRules.GetDisplayedGameModeRecordIDAtIndex(displayIndex:luaIndex) -> gameModeRecordID:number
C_GameRules.GetForeverExperiencePreset() -> preset:ForeverExperiencePreset?
C_GameRules.GetGameModeDisplayInfoByRecordID(gameModeRecordID:number) -> info:GameModeDisplayInfo?
C_GameRules.GetGameModeGlueScreenName() -> screenName:cstring
C_GameRules.GetGameModePromoGlobalString(gameModeRecordID:number) -> promoGlobalString:cstring
C_GameRules.GetGameRuleAsFloat(gameRule:GameRule, decimalPlaces:number) -> value:number
C_GameRules.GetGameRuleAsFrameStrata(gameRule:GameRule) -> frameStrata:cstring
C_GameRules.GetNumDisplayedGameModes() -> numDisplayedGameModes:number
C_GameRules.IsCharacterlessLoginActive() -> active:bool
C_GameRules.IsClassAllowedForGameMode(classID:number) -> valid:bool
C_GameRules.IsGameModeEnabled(gameModeRecordID:number) -> enabled:bool
C_GameRules.IsGameRuleActive(gameRule:GameRule) -> isActive:bool
C_GameRules.IsHardcoreActive() -> active:bool
C_GameRules.IsMultiActionBarVisibilityForced() -> valid:bool
C_GameRules.IsPersonalResourceDisplayEnabled() -> isPersonalResourceDisplayEnabled:bool
C_GameRules.IsPlunderstorm() -> active:bool
C_GameRules.IsSDHDToggleEnabled() -> isEnabled:bool
C_GameRules.IsSelfFoundAllowed() -> active:bool
C_GameRules.IsStandard() -> active:bool
C_GameRules.IsWoWHack() -> active:bool
C_GameRules.SetForeverExperiencePresetPostLogin(preset:ForeverExperiencePreset) -> 
C_GameRules.SetForeverExperiencePresetPreLogin(preset:ForeverExperiencePreset) -> 
C_GameRules.SetSDHDToggleValue(setToSD:bool, usageLocation:SdToggleUsageLocationUI) -> 
```

## C_MajorFactions

Legacy Track is faction **2802**, PvP Rank Points **2800**. `GetRenownRewardsForLevel` returns
rewards for levels that are still locked, which is how upcoming Legacy tiers can be shown.

```
C_MajorFactions.GetCurrentRenownLevel(majorFactionID:number) -> level:number
C_MajorFactions.GetMajorFactionData(majorFactionID:number) -> data:MajorFactionData?
C_MajorFactions.GetMajorFactionIDs(expansionID:number?) -> majorFactionIDs:table
C_MajorFactions.GetMajorFactionProgressionInfo(majorFactionID:number) -> data:MajorFactionProgressionInfo?
C_MajorFactions.GetMajorFactionRenownInfo(majorFactionID:number) -> data:MajorFactionRenownInfo?
C_MajorFactions.GetRenownLevels(majorFactionID:number) -> levels:table
C_MajorFactions.GetRenownNPCFactionID() -> renownNPCFactionID:number
C_MajorFactions.GetRenownRewardsForLevel(majorFactionID:number, renownLevel:number) -> rewards:table
C_MajorFactions.GetTotalReputationForRenownLevel(majorFactionID:number, renownLevel:number) -> totalReputation:number
C_MajorFactions.HasMaximumRenown(majorFactionID:number) -> hasMaxRenown:bool
C_MajorFactions.IsMajorFactionHiddenFromExpansionPage(majorFactionID:number) -> isHidden:bool
C_MajorFactions.IsWeeklyRenownCapped(majorFactionID:number) -> isWeeklyCapped:bool
C_MajorFactions.ShouldDisplayMajorFactionAsJourney(majorFactionID:number) -> shouldDisplayMajorFactionAsJourney:bool
C_MajorFactions.ShouldUseJourneyRewardTrack(majorFactionID:number) -> shouldUseJourneyRewardTrack:bool
```

## Regenerating this file

In game: `/reload`, then `/wn api` and `/wn apidoc`, then `/reload` again so SavedVariables are
flushed. The reload BEFORE the command matters: editing the addon's Lua without it means the old
code runs and writes a snapshot that silently lacks the new sections.
