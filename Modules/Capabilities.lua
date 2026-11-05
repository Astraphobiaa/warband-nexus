--[[
    Warband Nexus - Capabilities

    One place that answers "does this client actually have system X?".

    WoW Forever (game type camelot/forever, interface 16001) runs the Mainline UI, so a retail-only
    namespace can still EXIST there while the system behind it does not. Branching on
    `if C_WeeklyRewards then` would therefore open an empty Great Vault tab instead of hiding it.
    Nothing outside this file reads WOW_PROJECT_ID: callers ask `ns.Capabilities:Supports(key)`.

    Retail is the client the addon was built for, so every capability is true there and the probes
    only run on Forever. That keeps a probe that fires before its data has loaded from switching a
    retail feature off by mistake.
]]

local ADDON_NAME, ns = ...

local M = {}
ns.Capabilities = M

local pcall, type, select = pcall, type, select

--- Feature keys, all true on retail. Module-level keys (currencies, collections, ...) stay out of
--- this table on purpose: those systems exist in Forever in some form, so they are left running
--- until the live client shows otherwise.
local FEATURES = {
    "vault",               -- Great Vault / weekly rewards
    "mythicPlus",          -- keystones, M+ rating, run history
    "renown",              -- major factions / renown levels (vs plain reputation)
    "warbandBank",         -- account bank tabs
    "delves",
    "craftingOrders",
    "professionKnowledge", -- Dragonflight-style knowledge points
    "concentration",
    "itemUpgrade",         -- C_ItemUpgrade upgrade tracks / crests
    "achievementTracking", -- the objective-tracker feature, NOT achievement data
    "encounterJournal",    -- boss/loot source data the collection + try counter paths read
    "transmog",
    "wowToken",            -- the Blizzard token commerce system
    "seasonalPvEColumns",  -- the Midnight-season PvE table columns, as one group
    "ratedPvP",            -- 2v2 / 3v3 / RBG / Solo Shuffle / Blitz brackets
    "accountWideReputations", -- warband-era shared reputation
    "conquest",            -- the Conquest currency and its weekly cap
    "legacy",              -- WoW Forever account-wide Legacy System
    "professionsTab",      -- the Professions tab as it is built today
    "pveTab",              -- the PvE tab surface
}

local caps = {}
local resolved = false
local warnedUnknown = {}

--- True when this client is WoW Forever. WOW_PROJECT_CAMELOT is 18 (added in build 70170); the
--- interface-version band is the fallback for a build that predates the constant.
local function IsForeverClient()
    if WOW_PROJECT_ID and WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then
        return true
    end
    -- `local a = cond and GetBuildInfo()` would drop everything past the first return value.
    local ok, iv = pcall(function() return (select(4, GetBuildInfo())) end)
    if ok and type(iv) == "string" then iv = tonumber(iv) end
    return (ok and type(iv) == "number" and iv >= 16000 and iv < 20000) or false
end
M.IsForeverClient = IsForeverClient

--[[
    What Forever actually has, measured on the live client (build 1.60.1.70790, interface 16001)
    with `/wn caps`. Two controls in that output confirm the measurement is sound: maxPlayerLevel
    returned 60 and C_PvP.IsWarModeFeatureEnabled returned false, the one Forever behaviour
    difference Blizzard documented in the 1.60.1 addon notes.

    This is a static table rather than a live probe on purpose. Several of these calls answer
    from CHARACTER state, not client capability -- an empty C_WeeklyRewards.GetActivities() also
    happens on retail before the server replies -- so probing at an unlucky moment would switch a
    feature off for the session. Re-run `/wn caps` to re-verify after a Forever patch.
]]
--[[
    Ruleset detection.

    C_GameRules.IsGameRuleActive answers about RULESETS, not feature flags: the documented
    Enum.GameRule values for it are HardcoreRuleset, PvPRuleset and RPRuleset, and those are the
    only three this client carries with "Ruleset" in the name. Asking it about other rules
    returned true for 41 of them and raised for 128, never false -- which is not an answer, and
    an earlier version of this file wrongly drove three capabilities off it.
]]
local RULESET_LABELS = {
    { "HardcoreRuleset", "Hardcore" },
    { "PvPRuleset", "PvP" },
    { "RPRuleset", "RP" },
}

local function RulesetActive(ruleName)
    if type(C_GameRules) ~= "table" or type(C_GameRules.IsGameRuleActive) ~= "function" then
        return nil
    end
    local rules = (type(Enum) == "table") and Enum.GameRule
    local value = (type(rules) == "table") and rules[ruleName]
    if type(value) ~= "number" then return nil end
    local ok, active = pcall(C_GameRules.IsGameRuleActive, value)
    if not ok then return nil end
    return active and true or false
end

--- "PvP" / "RP" / "Hardcore", or nil when none applies (a normal realm, or retail).
function M:GetRulesetLabel()
    for i = 1, #RULESET_LABELS do
        if RulesetActive(RULESET_LABELS[i][1]) then return RULESET_LABELS[i][2] end
    end
    return nil
end

local FOREVER_SUPPORT = {
    vault               = false,  -- GetActivities table(0), HasAvailableRewards false
    mythicPlus          = false,  -- ChallengeMode.GetMapTable table(0), GetOwnedKeystoneLevel nil
    warbandBank         = false,  -- Bank.FetchPurchasedBankTabData(Account) table(0)
    delves              = false,  -- GetCurrentDelvesSeasonNumber 0
    craftingOrders      = false,  -- GetCrafterOrders table(0)
    professionKnowledge = false,  -- GetChildProfessionInfos table(0): no DF-style spec tree
    concentration       = false,  -- GetConcentrationCurrencyID raised
    itemUpgrade         = false,  -- GetItemUpgradeItemInfo nil
    wowToken            = false,  -- GetCommerceSystemStatus false, market price nil, 0 listed
    -- Every inline PvE column is Midnight-season content: Great Vault slots, upgrade crests,
    -- delve tasks and this season's currencies. None of it exists on a level-60 vanilla-plus
    -- client, so the group is gated as a whole rather than pretending to per-column precision.
    seasonalPvEColumns  = false,
    -- Forever's PvP is the vanilla honor ladder: Enum.PvPRanks carries RankNone/Pariah/Outlaw/
    -- Exiled/Dishonored plus Rank_1..Rank_14, major faction 2800 is "PvP Rank Points" with 14
    -- renown levels, and DisableHonorDecay is set. Rated arena and the rated brackets built on
    -- it (Solo Shuffle, Blitz) are later-expansion systems with nothing to read here.
    ratedPvP            = false,
    -- Reputation on a vanilla-plus client is per character; the account-wide section would be
    -- an empty header carrying a warband glyph above the real list.
    accountWideReputations = false,
    -- Conquest arrived with rated PvP; a vanilla honor ladder has Honor and nothing else.
    conquest            = false,
    -- The one capability that is TRUE on Forever and false on retail: major faction 2802
    -- "Legacy Track" exists only there. FEATURES defaults every key to true, so this has to be
    -- set explicitly in both directions.
    legacy              = true,
    -- The tab's rows come from professionExpansions, which is only ever seeded from Midnight
    -- child skill lines (2906-2918). Those do not exist here, so every row and 14 of its 15
    -- columns are blank. Hidden until the 1-300 model is built; see docs/forever-api-reference.
    professionsTab      = false,
    -- PvE tab surface is off for now. PvECacheService keeps caching raid lockouts, so the
    -- data is there the moment the page comes back.
    pveTab              = false,
    -- renown is deliberately absent: GetMajorFactionIDs returned table(2) on Forever. Until it
    -- is known whether those are real factions or leftover Mainline client data, renown stays
    -- on -- hiding a working panel is worse than showing an empty one.
}

local function ResolveForever()
    for key, supported in pairs(FOREVER_SUPPORT) do
        caps[key] = supported
    -- Nothing is read from IsGameRuleActive here any more: see the note above. The entries in
    -- FOREVER_SUPPORT are the only source, and each one names the measurement behind it.
    end
end

--- Resolve once. `force` re-probes (used after login, when more of the API surface is live).
function M:Resolve(force)
    if resolved and not force then return end
    local forever = IsForeverClient()
    M.isForever = forever
    for i = 1, #FEATURES do
        caps[FEATURES[i]] = true
    end
    -- Forever-only systems are off everywhere else, so they cannot ride the default-on rule.
    caps.legacy = false
    if forever then
        local ok = pcall(ResolveForever)
        if not ok then
            -- A probe raising is itself a signal that this is not a retail client; stay conservative
            -- and keep whatever resolved before the error rather than claiming full retail support.
            if ns.DebugPrint then ns.DebugPrint("|cffffff00[WN]|r capability probe failed") end
        end
    end
    resolved = true
end

--- The question every caller asks. Unknown keys answer true: a capability nobody declared is not a
--- reason to hide working UI.
function M:Supports(key)
    if not resolved then M:Resolve() end
    local v = caps[key]
    if v == nil then
        -- Answering true keeps an undeclared capability from hiding working UI, but it also means
        -- a typo'd key passes silently. Say so in debug, otherwise the gate is invisible.
        if ns.DebugPrint and not warnedUnknown[key] then
            warnedUnknown[key] = true
            ns.DebugPrint("|cffffff00[WN]|r capability not declared, defaulting to on: " .. tostring(key))
        end
        return true
    end
    return v
end

--- Snapshot for `/wn caps`, ordered so the output is stable.
function M:Snapshot()
    if not resolved then M:Resolve() end
    local out = {}
    for i = 1, #FEATURES do
        out[i] = { key = FEATURES[i], value = caps[FEATURES[i]] and true or false }
    end
    return out, M.isForever and true or false
end

--[[
    Deep probe (`/wn caps probe`).

    HasAPI above answers "is the function there", which turned out to be useless on Forever: it
    ships the Mainline UI, so C_WeeklyRewards, C_MythicPlus, C_MajorFactions and friends all exist
    and every capability reported yes on a client that has none of those systems. What separates a
    present system from a present namespace is what the call RETURNS, so this walks the real calls
    once and prints it. Read-only, pcall around every call, run by hand -- never on the login path.
]]
local function Count(v)
    if type(v) ~= "table" then return nil end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return n
end

local function Try(label, fn)
    local ok, a, b = pcall(fn)
    if not ok then return label, "|cffff6060error|r" end
    if a == nil then return label, "|cffaaaaaanil|r" end
    local c = Count(a)
    if c ~= nil then
        return label, (c > 0 and "|cff40ff40" or "|cffff6060") .. "table(" .. c .. ")|r"
    end
    if type(a) == "boolean" then
        return label, (a and "|cff40ff40true|r" or "|cffff6060false|r")
    end
    return label, "|cff40ff40" .. tostring(a) .. "|r" .. (b ~= nil and (" , " .. tostring(b)) or "")
end

--- Returns an ordered {label, text} list. Nothing here is cached or acted on.
function M:DeepProbe()
    local rows = {}
    local function add(label, fn) local l, v = Try(label, fn); rows[#rows + 1] = { l, v } end

    add("maxPlayerLevel", function() return GetMaxPlayerLevel() end)
    add("warModeFeature", function() return C_PvP.IsWarModeFeatureEnabled() end)
    add("vault.activities", function() return C_WeeklyRewards.GetActivities() end)
    add("vault.hasRewards", function() return C_WeeklyRewards.HasAvailableRewards() end)
    add("mplus.mapTable", function() return C_ChallengeMode.GetMapTable() end)
    add("mplus.ownedKey", function() return C_MythicPlus.GetOwnedKeystoneLevel() end)
    add("renown.factionIDs", function() return C_MajorFactions.GetMajorFactionIDs() end)
    add("bank.accountTabs", function()
        return C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
    end)
    add("bank.accountBagID", function() return Enum.BagIndex.AccountBankTab_1 end)
    add("delves.season", function() return C_DelvesUI.GetCurrentDelvesSeasonNumber() end)
    add("prof.childInfos", function() return C_TradeSkillUI.GetChildProfessionInfos() end)
    add("prof.concentration", function() return C_TradeSkillUI.GetConcentrationCurrencyID() end)
    add("itemUpgrade.info", function() return C_ItemUpgrade.GetItemUpgradeItemInfo() end)
    add("craftingOrders", function() return C_CraftingOrders.GetCrafterOrders() end)
    add("numFactions", function() return C_Reputation.GetNumFactions() end)
    -- Bank: "no tabs purchased" also happens on retail, so it cannot answer whether the
    -- account (warband) bank EXISTS. Max tab count and viewability can.
    add("bank.maxAccountTabs", function()
        return C_Bank.FetchMaxNumBankTabs(Enum.BankType.Account)
    end)
    add("bank.canViewAccount", function()
        return C_Bank.CanViewBank(Enum.BankType.Account)
    end)
    add("bank.canPurchaseAcct", function()
        return C_Bank.CanPurchaseBankTab(Enum.BankType.Account)
    end)
    add("bank.viewableTypes", function() return C_Bank.FetchViewableBankTypes() end)
    add("bank.maxCharTabs", function()
        return C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character)
    end)
    -- WoW Token: the Character tab shows "N/A" here; is the commerce system even up?
    add("token.commerceStatus", function()
        return C_WowTokenPublic.GetCommerceSystemStatus()
    end)
    add("token.marketPrice", function()
        return C_WowTokenPublic.GetCurrentMarketPrice()
    end)
    add("token.numListed", function()
        return C_WowTokenPublic.GetNumListedAuctionableTokens()
    end)
    -- Currencies / Reputations are data-driven walks, so what matters is what the walk SEES.
    add("curr.listSize", function() return C_CurrencyInfo.GetCurrencyListSize() end)
    add("rep.numFactions", function() return C_Reputation.GetNumFactions() end)
    -- GetMajorFactionIDs returned 2 entries here; are they real renown factions or leftovers?
    add("renown.ids", function()
        local ids = C_MajorFactions.GetMajorFactionIDs()
        if type(ids) ~= "table" then return ids end
        local parts = {}
        for k = 1, #ids do
            local okD, d = pcall(C_MajorFactions.GetMajorFactionData, ids[k])
            parts[#parts + 1] = tostring(ids[k]) .. ":" ..
                ((okD and type(d) == "table" and tostring(d.name)) or "nodata")
        end
        return table.concat(parts, ", ")
    end)
    -- IsGameRuleActive answered true for 41 rules and raised for the other 128 -- never false.
    -- That smells like "this rule has a value" rather than "this rule is on", which would make
    -- the whole active-rule list unsafe to read as fact. GetGameRuleAsFloat settles it.
    add("rule.campsitesValue", function()
        return C_GameRules.GetGameRuleAsFloat(Enum.GameRule.DisableCampsites)
    end)
    add("rule.ammoValue", function()
        return C_GameRules.GetGameRuleAsFloat(Enum.GameRule.EnableAmmoSystem)
    end)
    add("rule.transmogValue", function()
        return C_GameRules.GetGameRuleAsFloat(Enum.GameRule.TransmogEnabled)
    end)
    -- Control: a rule that errored on IsGameRuleActive. If this returns a value too, then
    -- "errored" only meant "not configured".
    add("rule.hardcoreValue", function()
        return C_GameRules.GetGameRuleAsFloat(Enum.GameRule.HardcoreEnabled)
    end)
    -- Vanilla brought back the ranged weapon slot and ammo. The gear paperdoll walks a fixed
    -- retail slot list, so if a ranged slot is shown here it is a slot we never draw.
    add("slot.rangedShown", function() return C_PaperDollInfo.IsRangedSlotShown() end)
    add("slot.ammoNeeded", function() return C_PaperDollInfo.AmmoNeeded() end)
    add("slot.usesAmmo", function() return UnitUsesAmmo("player") end)
    add("slot.rangedID", function() return (GetInventorySlotInfo("RangedSlot")) end)
    add("slot.ammoID", function() return (GetInventorySlotInfo("AmmoSlot")) end)
    add("slot.tabardID", function() return (GetInventorySlotInfo("TabardSlot")) end)
    return rows
end
