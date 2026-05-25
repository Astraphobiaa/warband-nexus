--[[ Warband Nexus - Easy Access - VaultButton_Data.lua ]]

local ADDON_NAME, ns = ...
local M = assert(ns.VaultButton)
local WarbandNexus = ns.WarbandNexus
local S = M.state

local function VB__setfenv()
    return setmetatable({ M = M, ns = ns, WarbandNexus = WarbandNexus, S = M.state }, {
        __index = function(_, k)
            local v = M[k]
            if v ~= nil then return v end
            return _G[k]
        end,
    })
end
setfenv(1, VB__setfenv())
--[[ Shared API: M.* / S.* only across VaultButton_* chunks (see VaultButton_Core.lua). ]]
-- ============================================================================
-- Data helpers
-- ============================================================================
function M.GetClassHex(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return string.format("%02x%02x%02x",
            math.floor((c.r or 1)*255), math.floor((c.g or 1)*255), math.floor((c.b or 1)*255))
    end
    return "aaaaaa"
end

function M.FormatCharacterName(entry)
    local name = entry and entry.name or ""
    local realm = entry and entry.realm or ""
    if GetSettings().showRealmName and realm ~= "" then
        name = name .. " - " .. realm
    end
    return "|cff" .. GetClassHex(entry and entry.classFile) .. name .. "|r"
end

function M.GetCurrentCharKey()
local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey and WarbandNexus then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k then return k end
    end
    local raw = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        or (ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey())
    if not raw then return nil end
    if ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
    end
    return raw
end

--- True when two keys refer to the same character (GUID vs Name-Realm vs storage key).
function M.CharKeysMatch(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local ca = ns.Utilities:GetCanonicalCharacterKey(a)
        local cb = ns.Utilities:GetCanonicalCharacterKey(b)
        if ca and cb and ca == cb then return true end
    end
    return false
end
ns.VaultCharKeysMatch = M.CharKeysMatch

--- Lookup a per-character pveCache subtable when keys were written under a canonical alias.
--- For rewards: a claimed row (hasAvailableRewards=false + claimedAt) wins over stale true on another key.
function M.LookupPveCacheSubtable(subtable, charKey)
    if not subtable or not charKey then return nil end
    local direct = subtable[charKey]
    if direct ~= nil and type(direct) ~= "table" then return direct end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local ck = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if ck and subtable[ck] ~= nil then
            direct = subtable[ck]
            if type(direct) ~= "table" then return direct end
        end
    end
    local best, bestUpdate, claimedEntry = direct, direct and (tonumber(direct.lastUpdate) or 0) or -1, nil
    for k, v in pairs(subtable) do
        if type(v) == "table" and CharKeysMatch(k, charKey) then
            local lu = tonumber(v.lastUpdate) or 0
            local ca = tonumber(v.claimedAt) or 0
            if v.hasAvailableRewards == false and ca > 0 then
                claimedEntry = v
            end
            if lu >= bestUpdate then
                bestUpdate = lu
                best = v
            end
        end
    end
    return claimedEntry or best
end
ns.LookupPvECacheSubtable = M.LookupPveCacheSubtable

function M.GetCharActivities(charKey)
    local pveCache = GetPveCache()
    if not pveCache or not pveCache.greatVault or not pveCache.greatVault.activities then return nil end
    return LookupPveCacheSubtable(pveCache.greatVault.activities, charKey)
end

function M.HasAnyProgress(charKey)
    local acts = GetCharActivities(charKey)
    if not acts then return false end
    -- isPostReset means data is from last week — treat as no this-week progress
    if acts.isPostReset then return false end
    for _, cat in ipairs({ acts.raids, acts.mythicPlus, acts.world }) do
        if cat then
            for _, a in ipairs(cat) do
                local p = tonumber(a.progress) or 0
                local t = tonumber(a.threshold) or 0
                if t > 0 and p >= t then return true end
            end
        end
    end
    return false
end

function M.GetSlotData(charKey, category)
    local acts = GetCharActivities(charKey)
    -- isPostReset means data is from last week — show empty slots for this week
    local cat  = (acts and not acts.isPostReset) and acts[category] or {}
    local typeName = CAT_TO_TYPE[category]
    local slots = {}
    for i = 1, 3 do
        local a = cat[i]
        local prog   = a and (tonumber(a.progress) or 0) or 0
        local thresh = a and (tonumber(a.threshold) or 0) or 0
        slots[i] = {
            complete   = thresh > 0 and prog >= thresh,
            ilvl       = a and a.rewardItemLevel or 0,
            progress   = prog,
            threshold  = thresh,
            canUpgrade = SlotShowsUpgrade(a, typeName),
        }
    end
    return slots
end

--- Count how many vault slots are complete across all categories
function M.CountReadySlots(charKey)
    local n = 0
    for _, cat in ipairs({ "raids", "mythicPlus", "world" }) do
        for _, s in ipairs(GetSlotData(charKey, cat)) do
            if s.complete then n = n + 1 end
        end
    end
    return n
end

--- True if `time()` has crossed the stored weeklyResetTime for this char's activities,
--- meaning the cached "ready slots" are now sitting unclaimed in the vault chest.
function ns.VaultResetCrossedFor(charKey)
    local pveCache = GetPveCache()
    local activities = pveCache and pveCache.greatVault and pveCache.greatVault.activities
        and LookupPveCacheSubtable(pveCache.greatVault.activities, charKey) or nil
    if not activities then return false end
    local resetT = tonumber(activities.weeklyResetTime) or 0
    if resetT <= 0 then return false end
    local rewards = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
    local rewardData = rewards and LookupPveCacheSubtable(rewards, charKey)
    local claimedResetTime = rewardData and tonumber(rewardData.claimedResetTime) or nil
    if claimedResetTime and claimedResetTime >= resetT then
        return false
    end
    return GetServerTime() >= resetT
end
M.VaultResetCrossedFor = ns.VaultResetCrossedFor

--- Get Trovehunter's Bounty status for a character
--- Returns: true = done, false = not done, nil = unknown (never logged in)
function M.GetBountyStatus(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local delveChar = pveCache.delves and pveCache.delves.characters
        and pveCache.delves.characters[charKey]
    if not delveChar then return nil end
    return delveChar.bountifulComplete
end

function M.GetGildedStashData(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local delveChar = pveCache.delves and pveCache.delves.characters
        and pveCache.delves.characters[charKey]
    if not delveChar then return nil end
    local current = tonumber(delveChar.gildedStashes)
    if current == nil then return nil end
    return {
        current = current,
        max = tonumber(delveChar.gildedStashesMax) or 4,
        unknown = current < 0,
    }
end

--- Get Nebulous Voidcore data for a character { current, seasonMax }
--- Uses WarbandNexus:GetCurrencyData which reads from CurrencyCacheService.
--- - quantity    = how many you currently hold (unspent)
--- - totalEarned = season progress (how many earned this season, shown as X/seasonMax)
--- - seasonMax   = season cap (increases by 2 each week)
function M.GetVoidcoreData(charKey)
    if not WarbandNexus or not WarbandNexus.GetCurrencyData then return nil end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, VOIDCORE_ID, charKey)
    if not ok or not cd then return nil end
    local sm = tonumber(cd.seasonMax) or 0
    local te = tonumber(cd.totalEarned) or 0
    local qty = tonumber(cd.quantity) or 0
    -- If useTotalEarnedForMaxQty, season progress = totalEarned; otherwise use quantity
    local progress = cd.useTotalEarnedForMaxQty and te or qty
    return {
        quantity    = qty,        -- currently held (unspent)
        progress    = progress,   -- season earned (for X/seasonMax display)
        seasonMax   = sm,
        isCapped    = sm > 0 and progress >= sm,
    }
end

--- Get Dawnlight Manaflux data for a character { quantity }
function M.GetManafluxData(charKey)
    if not WarbandNexus or not WarbandNexus.GetCurrencyData then return nil end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, MANAFLUX_ID, charKey)
    if not ok or not cd then
        local currencyData = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.currencyData
        local stored = currencyData and currencyData.currencies and currencyData.currencies[charKey]
            and currencyData.currencies[charKey][MANAFLUX_ID]
        if type(stored) == "table" then stored = stored.quantity end
        local quantity = tonumber(stored)
        if quantity == nil then return nil end
        return { quantity = quantity, totalEarned = 0 }
    end
    return {
        quantity = tonumber(cd.quantity) or 0,
        totalEarned = tonumber(cd.totalEarned) or 0,
    }
end

--- Cached keystone row (pveCache.mythicPlus.keystones, then characters[].mythicKey).
function M.GetKeystoneData(charKey, charRow)
    if not charKey then return nil end
    local pveCache = GetPveCache()
    local mp = pveCache and pveCache.mythicPlus
    local key = mp and mp.keystones and LookupPveCacheSubtable(mp.keystones, charKey)
    if key and (tonumber(key.level) or 0) > 0 then
        return key
    end
    local row = charRow
    if not row then
        local chars = GetCharacters()
        row = chars and chars[charKey]
    end
    local mk = row and row.mythicKey
    if mk and (tonumber(mk.level) or 0) > 0 then
        return mk
    end
    return nil
end

function M.FormatKeystoneTooltipRight(charKey, charRow)
    local ks = GetKeystoneData(charKey, charRow)
    if not ks or (tonumber(ks.level) or 0) <= 0 then
        return "|cff888888" .. EAL("EA_TOOLTIP_KEYSTONE_NONE", "No keystone") .. "|r"
    end
    local level = tonumber(ks.level) or 0
    local mapName = ks.dungeonName
    if (not mapName or mapName == "") and ks.mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, ks.mapID)
        if ok and name and name ~= "" then
            if not (issecretvalue and issecretvalue(name)) then
                mapName = name
            end
        end
    end
    if not mapName or mapName == "" or (issecretvalue and issecretvalue(mapName)) then
        mapName = EAL("KEYSTONE", "Keystone")
    end
    return "|cff00ff00" .. EAL("EA_TOOLTIP_KEYSTONE_FORMAT", "+%d %s", level, mapName) .. "|r"
end

function M.GetMythicOverallScore(charKey)
    if not charKey then return nil end
    local pveCache = GetPveCache()
    local mp = pveCache and pveCache.mythicPlus
    if not mp or not mp.dungeonScores then return nil end
    local ds = LookupPveCacheSubtable(mp.dungeonScores, charKey)
    local score = ds and tonumber(ds.overallScore)
    if score and score > 0 then
        return score
    end
    return nil
end

function M.FormatMythicScoreTooltipRight(charKey)
    local score = GetMythicOverallScore(charKey)
    if not score then
        return "|cff888888" .. EAL("EA_TOOLTIP_MYTHIC_SCORE_NONE", "--") .. "|r"
    end
    return "|cffd4af37" .. EAL("EA_TOOLTIP_MYTHIC_SCORE_VALUE", "%d", score) .. "|r"
end


--- Open WarbandNexus main window on a specific tab (nil = session / profile lastTab).
function M.OpenWNTab(tabKey)
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    if not WarbandNexus or not WarbandNexus.ShowMainWindow then return end
    WarbandNexus:ShowMainWindow(tabKey)
end

--- Toggle main window: hides if already shown, otherwise opens on the last-used tab
function M.ToggleMainWindow()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() then
        mf:Hide()
        return
    end
    OpenWNTab(nil)
end

function M.OpenWNPveTab() OpenWNTab("pve") end

function M.OpenWNCharsTab() OpenWNTab("chars") end

function M.ToggleWNCharsTab()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() and mf.currentTab == "chars" then
        mf:Hide()
        return
    end
    OpenWNCharsTab()
end

function M.ToggleWNPveTab()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() and mf.currentTab == "pve" then
        mf:Hide()
        return
    end
    OpenWNPveTab()
end

function M.OpenWNSettingsTab()
    HideTable()
    HideMenu()
    HideSavedInstances()
    if WarbandNexus and WarbandNexus.OpenOptions then
        WarbandNexus:OpenOptions()
    elseif WarbandNexus and WarbandNexus.ShowSettings then
        WarbandNexus:ShowSettings()
    else
        OpenWNTab("settings")
    end
end

local WORLD_REWARD_QUALITY_BY_ILVL = {
    [233] = 3, [237] = 3, [240] = 3, [243] = 3,
    [246] = 4, [250] = 4, [253] = 4,
    [259] = 5,
}

function M.ColorByItemQuality(value, quality)
    local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then
        return color.hex .. tostring(value) .. "|r"
    end
    return "|cffd4af37" .. tostring(value) .. "|r"
end

function M.FormatRewardIlvl(ilvl, category)
    ilvl = tonumber(ilvl) or 0
    if ilvl <= 0 then return CHECK end
    if category == "world" then
        return ColorByItemQuality(ilvl, WORLD_REWARD_QUALITY_BY_ILVL[ilvl])
    end
    return "|cffd4af37" .. ilvl .. "|r"
end

--- Build SlotSymbols-shaped slot rows from great-vault activity list (PvE tracker / grid).
function ns.VaultSlotsFromActivityList(activityList, slotCount, typeName)
    slotCount = slotCount or 3
    if slotCount < 1 then slotCount = 3 end
    local catKey = (typeName == "Raid" and "raids")
        or (typeName == "M+" and "mythicPlus")
        or (typeName == "World" and "world")
        or typeName
    local apiType = CAT_TO_TYPE[catKey] or typeName
    local slots = {}
    for i = 1, slotCount do
        local a = activityList and activityList[i]
        local th = tonumber(a and a.threshold) or 0
        local prog = tonumber(a and a.progress) or 0
        slots[i] = {
            complete = th > 0 and prog >= th,
            progress = prog,
            threshold = th,
            ilvl = a and a.rewardItemLevel or 0,
            canUpgrade = SlotShowsUpgrade(a, apiType),
        }
    end
    return slots, catKey
end

--- Remaining weekly events to finish one vault activity slot (nil if complete or unknown).
function ns.GetVaultActivityRemaining(activity)
    if not activity then return nil end
    local th = tonumber(activity.threshold) or 0
    local prog = tonumber(activity.progress) or 0
    if th <= 0 or prog >= th then return nil end
    return th - prog
end

--- In-progress slot center text: `3/8` by default, `5` when Shift is held.
function ns.FormatVaultSlotProgressText(activity, shiftHeld)
    if not activity then return nil end
    local th = tonumber(activity.threshold) or 0
    local prog = tonumber(activity.progress) or 0
    if th <= 0 or prog >= th then return nil end
    local rem = th - prog
    if shiftHeld then
        return "|cffffcc00" .. rem .. "|r"
    end
    return string.format("|cffffcc00%d|r|cff666666/|r|cff888888%d|r", prog, th)
end

--- Tracker column width: icons only, progress suffix `(3/8)`, or compact Shift remaining digit(s).
function ns.ResolveVaultTrackerColumnWidth(showRewardProgress)
    if showRewardProgress then
        return COL_PROGRESS
    end
    return COL_RAID
end

--- Single vault slot glyph for tracker/PvE columns (one of three fixed cells).
function M.FormatVaultSlotPart(slot, category, showIlvl)
    if not slot then
        return CROSS
    end
    if slot.complete then
        if showIlvl and (tonumber(slot.ilvl) or 0) > 0 then
            return FormatRewardIlvl(slot.ilvl, category)
        end
        if slot.canUpgrade then
            return UPARROW
        end
        return CHECK
    end
    return CROSS
end

function M.GetVaultColumnNextProgress(slots)
    for i = 1, 3 do
        local slot = slots[i]
        if slot and not slot.complete then
            local th = tonumber(slot.threshold) or 0
            local prog = tonumber(slot.progress) or 0
            if th > 0 and (not nextThresh or th < nextThresh) then
                nextThresh = th
                nextProg = prog
            end
        end
    end
    return nextProg, nextThresh
end

--- Raid / Dungeon / World tracker column (not expanded vault cards).
--- Normal: slot glyphs; optional `(3/8)` when showRewardProgress.
--- Shift: only remaining count toward the next unlock (e.g. `5`), no icons.
function ns.VaultFormatCategoryColumn(slots, category, opts)
    opts = opts or {}
    local shiftHeld = opts.shiftHeld == true
    local showIlvl = opts.showRewardItemLevel == true
    local showProg = opts.showRewardProgress == true
    if opts.vaultLootClaimable then
        -- Compact column width (72px): full "Ready to Claim" truncates in PvE / tracker grids.
        local readyLabel = (ns.L and ns.L["VAULT_READY_TO_CLAIM"]) or "Ready"
        return "|cff44ff44" .. readyLabel .. "|r"
    end

    local nextProg, nextThresh = GetVaultColumnNextProgress(slots)

    if shiftHeld and nextThresh and nextThresh > 0 then
        local rem = nextThresh - math.min(tonumber(nextProg) or 0, nextThresh)
        if rem > 0 then
            return "|cffffcc00" .. rem .. "|r"
        end
    end

    local parts = {}
    for i = 1, 3 do
        parts[i] = FormatVaultSlotPart(slots[i], category, showIlvl)
    end

    local text = table.concat(parts, " ")
    if showProg and nextThresh and nextThresh > 0 then
        local progShown = math.min(tonumber(nextProg) or 0, nextThresh)
        text = text .. " |cffaaaaaa(" .. progShown .. "/" .. nextThresh .. ")|r"
    end
    return text
end

local VAULT_TRACKER_SLOTS_PER_COL = 3

function M.PaintVaultTrackerColumnCells(cellGroup, opts)
    opts = opts or {}
    local fses = cellGroup.fses
    local bindData = cellGroup.data
    if not fses or not bindData or not bindData.slots then return end

    local shiftHeld = opts.shiftHeld == true
    local showIlvl = bindData.showRewardItemLevel == true
    local showProg = bindData.showRewardProgress == true
    local slots = bindData.slots
    local category = bindData.category

    for i = 1, VAULT_TRACKER_SLOTS_PER_COL do
        if fses[i] and fses[i].SetText then
            fses[i]:SetText("")
        end
    end

    if bindData.vaultLootClaimable then
        if fses[2] and fses[2].SetText then
            local readyLabel = (ns.L and ns.L["VAULT_READY_TO_CLAIM"]) or "Ready"
            fses[2]:SetText("|cff44ff44" .. readyLabel .. "|r")
        end
        return
    end

    local nextProg, nextThresh = GetVaultColumnNextProgress(slots)
    if shiftHeld and nextThresh and nextThresh > 0 then
        local rem = nextThresh - math.min(tonumber(nextProg) or 0, nextThresh)
        if rem > 0 and fses[2] and fses[2].SetText then
            fses[2]:SetText("|cffffcc00" .. rem .. "|r")
        end
        return
    end

    for i = 1, VAULT_TRACKER_SLOTS_PER_COL do
        if fses[i] and fses[i].SetText then
            fses[i]:SetText(FormatVaultSlotPart(slots[i], category, showIlvl))
        end
    end

    if showProg and nextThresh and nextThresh > 0 and fses[3] and fses[3].SetText then
        local progShown = math.min(tonumber(nextProg) or 0, nextThresh)
        local slotText = fses[3]:GetText() or ""
        fses[3]:SetText(slotText .. " |cffaaaaaa(" .. progShown .. "/" .. nextThresh .. ")|r")
    end
end

function M.RefreshVaultShiftBindings()
    local shiftHeld = IsShiftKeyDown and IsShiftKeyDown() or false
    for fs, activity in pairs(S.vaultSlotProgressBindings) do
        if fs and fs.SetText then
            local txt = ns.FormatVaultSlotProgressText(activity, shiftHeld)
            if txt then
                fs:SetText(txt)
            end
        end
    end
    for fs, data in pairs(S.vaultColumnBindings) do
        if fs and fs.SetText and data and data.slots then
            fs:SetText(ns.VaultFormatCategoryColumn(data.slots, data.category, {
                shiftHeld = shiftHeld,
                showRewardProgress = data.showRewardProgress,
                showRewardItemLevel = data.showRewardItemLevel,
                vaultLootClaimable = data.vaultLootClaimable,
            }))
        end
    end
    for _, cellGroup in pairs(S.vaultColumnCellBindings) do
        PaintVaultTrackerColumnCells(cellGroup, { shiftHeld = shiftHeld })
    end
end

function ns.RefreshVaultShiftAwareDisplays()
    RefreshVaultShiftBindings()
end

function M.EnsureVaultShiftWatcher()
    if S.vaultShiftWatcher then return end
    S.vaultShiftWatcher = CreateFrame("Frame")
    S.vaultShiftWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    S.vaultShiftWatcher:SetScript("OnEvent", function(_, _, key)
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        RefreshVaultShiftBindings()
        RefreshEasyAccessHoverTooltip()
    end)
end

function ns.UI_BindVaultSlotProgress(fs, activity)
    if not fs or not fs.SetText then return end
    EnsureVaultShiftWatcher()
    S.vaultSlotProgressBindings[fs] = activity
    local txt = ns.FormatVaultSlotProgressText(activity, IsShiftKeyDown and IsShiftKeyDown())
    if txt then
        fs:SetText(txt)
    end
end

function ns.UI_UnbindVaultSlotProgress(fs)
    if fs then
        S.vaultSlotProgressBindings[fs] = nil
    end
end

function ns.UI_BindVaultColumnDisplay(fs, bindData)
    if not fs or not fs.SetText or not bindData then return end
    EnsureVaultShiftWatcher()
    S.vaultColumnBindings[fs] = bindData
    fs:SetText(ns.VaultFormatCategoryColumn(bindData.slots, bindData.category, {
        shiftHeld = IsShiftKeyDown and IsShiftKeyDown(),
        showRewardProgress = bindData.showRewardProgress,
        showRewardItemLevel = bindData.showRewardItemLevel,
        vaultLootClaimable = bindData.vaultLootClaimable,
    }))
end

function ns.UI_UnbindVaultColumnDisplay(fs)
    if fs then
        S.vaultColumnBindings[fs] = nil
    end
end

--- Vault Tracker table: three equal sub-cells per raid/dungeon/world column (symmetric iLvl vs icons).
function ns.UI_BindVaultColumnCells(row, baseX, colWidth, bindData)
    if not row or not bindData then return end
    EnsureVaultShiftWatcher()
    local slotW = math.floor(colWidth / VAULT_TRACKER_SLOTS_PER_COL)
    local extra = colWidth - (slotW * VAULT_TRACKER_SLOTS_PER_COL)
    local fses = {}
    local offset = baseX
    for i = 1, VAULT_TRACKER_SLOTS_PER_COL do
        local w = slotW + ((i == VAULT_TRACKER_SLOTS_PER_COL) and extra or 0)
        local fs = VBFontString(row, "body")
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", offset, 0)
        fs:SetSize(w, ROW_H)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        if fs.SetMaxLines then fs:SetMaxLines(1) end
        fses[i] = fs
        offset = offset + w
    end
    local cellGroup = { fses = fses, data = bindData }
    S.vaultColumnCellBindings[fses[1]] = cellGroup
    PaintVaultTrackerColumnCells(cellGroup, { shiftHeld = IsShiftKeyDown and IsShiftKeyDown() })
end

function ns.UI_UnbindVaultColumnCells(anchorFs)
    if anchorFs then
        S.vaultColumnCellBindings[anchorFs] = nil
    end
end

function M.SlotSymbols(slots, category, vaultLootClaimable)
    local settings = GetSettings()
    return ns.VaultFormatCategoryColumn(slots, category, {
        shiftHeld = IsShiftKeyDown and IsShiftKeyDown(),
        showRewardProgress = settings.showRewardProgress,
        showRewardItemLevel = settings.showRewardItemLevel,
        vaultLootClaimable = vaultLootClaimable == true,
    })
end

function M.BuildCharList()
    local pveCache   = GetPveCache()
    local characters = GetCharacters()
    if not pveCache or not characters then return {} end
    local rewards    = pveCache.greatVault and pveCache.greatVault.rewards
    local currentKey = GetCurrentCharKey()
    local settings   = GetSettings()
    local result     = {}
    for charKey, charData in pairs(characters) do
        local rewardData = rewards and LookupPveCacheSubtable(rewards, charKey)
        local isReady    = rewardData and rewardData.hasAvailableRewards or false
        if CharKeysMatch(charKey, currentKey) then
            if WarbandNexus and WarbandNexus.HasUnclaimedVaultRewards then
                isReady = WarbandNexus:HasUnclaimedVaultRewards()
            else
                isReady = false
            end
        end
        -- Alt auto-flip: cached \226\128\156slots earned\226\128\157 last week + reset crossed -> sitting chest.
        if not isReady and not CharKeysMatch(charKey, currentKey)
            and (CountReadySlots(charKey) or 0) > 0
            and VaultResetCrossedFor(charKey) then
            isReady = true
        end
        local isPending  = not isReady and HasAnyProgress(charKey)
        local bounty = GetBountyStatus(charKey)
        if isReady or isPending or (settings.includeBountyOnly and bounty == true) then
            table.insert(result, {
                charKey   = charKey,
                name      = charData.name or charKey,
                realm     = charData.realm or "",
                classFile = charData.classFile or "WARRIOR",
                itemLevel = charData.itemLevel or 0,
                isReady   = isReady,
                isPending = isPending,
                isCurrent = CharKeysMatch(charKey, currentKey),
                bounty    = bounty,
                voidcore  = GetVoidcoreData(charKey),
                manaflux  = GetManafluxData(charKey),
                gildedStash = GetGildedStashData(charKey),
                slots     = CountReadySlots(charKey),
            })
        end
    end
    table.sort(result, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.isReady   ~= b.isReady   then return a.isReady   end
        return a.name < b.name
    end)
    return result
end

function M.CountReady()
    local n = 0
    for _, e in ipairs(BuildCharList()) do
        if e.isReady then n = n + 1 end
    end
    return n
end


