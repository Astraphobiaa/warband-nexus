--[[ Warband Nexus - Easy Access - VaultButton_Tooltip.lua ]]

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
-- Badge
-- ============================================================================
local UpdateBadge = function()
    if not S.badge then return end
    local count = CountReady()
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    local border = colors.border or accent
    if count > 0 then
        S.badge:SetText(count)
        S.badgeBg:Show()
        S.badge:Show()
        if S.badgeBg then S.badgeBg:SetColorTexture(accent[1], accent[2], accent[3], 1.0) end
        if S.border then S.border:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0) end
    else
        S.badge:Hide()
        S.badgeBg:Hide()
        if S.border then S.border:SetBackdropBorderColor(border[1], border[2], border[3], 0.85) end
    end
    ApplyButtonVisibility(false)
    if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
end

-- ============================================================================
-- Easy Access tooltip copy (clear text; table cells keep icons)
-- ============================================================================

function M.GetBountyColumnIcon()
    local primary = (ns.Constants and ns.Constants.TROVEHUNTERS_BOUNTY_ITEM_ID) or BOUNTY_ITEM_ID
    local alt = ns.Constants and ns.Constants.TROVEHUNTERS_BOUNTY_ITEM_ID_ALT
    if C_Item and C_Item.GetItemIconByID then
        local ok, fileID = pcall(C_Item.GetItemIconByID, primary)
        if ok and type(fileID) == "number" and fileID > 0 then
            return fileID
        end
        if alt and alt ~= primary then
            local ok2, fileID2 = pcall(C_Item.GetItemIconByID, alt)
            if ok2 and type(fileID2) == "number" and fileID2 > 0 then
                return fileID2
            end
        end
    end
    return TRACK_ICONS.bounty
end

function M.GetCurrencyIconTexture(currencyID, fallback)
    if WarbandNexus and WarbandNexus.GetCurrencyData and currencyID then
        local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, currencyID, nil)
        if ok and cd then
            if cd.iconFileID then
                return cd.iconFileID
            end
            if cd.icon then
                return cd.icon
            end
        end
    end
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.iconFileID then
            return info.iconFileID
        end
    end
    return fallback
end

function M.FormatProgressFraction(progress, maxVal, isCapped)
    progress = tonumber(progress) or 0
    maxVal = tonumber(maxVal) or 0
    if maxVal <= 0 then
        return "|cffffffff" .. tostring(progress) .. "|r"
    end
    local capColor = (isCapped or progress >= maxVal) and "|cffdd3333" or "|cffd4af37"
    return capColor .. progress .. "|r|cffaaaaaa/|r|cffd4af37" .. maxVal .. "|r"
end

function M.FormatEasyAccessCharacterTitle(charRow, entry)
    local name = (entry and entry.name) or (charRow and charRow.name) or "?"
    local realm = (entry and entry.realm) or (charRow and charRow.realm) or ""
    local classFile = (entry and entry.classFile) or (charRow and charRow.classFile) or "WARRIOR"
    local classHex = GetClassHex(classFile)
    if realm == "" then
        return "|cff" .. classHex .. name .. "|r"
    end
    local realmDisp = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(realm)) or realm
    if issecretvalue and issecretvalue(realmDisp) then
        return "|cff" .. classHex .. name .. "|r"
    end
    return "|cff" .. classHex .. name .. "|r|cffffffff - " .. realmDisp .. "|r"
end

local NormalizeColonLabel = ns.UI_NormalizeColonLabelSpacing
    or function(label)
        if not label or label == "" then return "" end
        local trimmed = label:match("^%s*(.-)%s*$") or label
        trimmed = trimmed:gsub("%s*:%s*$", "")
        return trimmed .. " : "
    end

function M.EAIconLabel(iconTexture, iconAtlas, localeKey, fallback)
    local icon = ""
    if iconAtlas and CreateAtlasMarkup then
        local ok, markup = pcall(CreateAtlasMarkup, iconAtlas, 12, 12)
        if ok and markup and markup ~= "" then
            icon = markup .. " "
        end
    end
    if icon == "" and iconTexture then
        icon = "|T" .. iconTexture .. ":12:12:0:0|t "
    end
    return icon .. NormalizeColonLabel(EAL(localeKey, fallback))
end

function M.EAFormatMoneyCopper(copper)
    if ns.UI_FormatMoney then
        return ns.UI_FormatMoney(copper or 0, M.EA_MONEY_ICON)
    end
    if WarbandNexus and WarbandNexus.API_FormatMoney then
        return WarbandNexus:API_FormatMoney(copper or 0, M.EA_MONEY_ICON)
    end
    if ns.UI_FormatGold then
        return ns.UI_FormatGold(copper or 0)
    end
    return tostring(copper or 0)
end

function M.EAFormatTitleIlvl(ilvl)
    local short = (ns.L and ns.L["ILVL_SHORT"]) or "iLvl"
    if ilvl and ilvl > 0 then
        return "|cffffd700" .. short .. " " .. string.format("%.0f", tonumber(ilvl) or 0) .. "|r"
    end
    return "|cff666666--|r"
end

function M.EAFormatTodoValue(n)
    n = tonumber(n) or 0
    if n > 0 then
        return "|cffffc864" .. tostring(n) .. "|r"
    end
    return "|cff6666660|r"
end

function M.EAAccentTitleColor()
    local ac = ns.UI_COLORS and ns.UI_COLORS.accent
    if ac then
        return { ac[1], ac[2], ac[3] }
    end
    return { 1, 0.82, 0 }
end

function M.ResolveEasyAccessGoldCopper(charKey, charRow)
    if not charRow or not ns.Utilities or not ns.Utilities.GetCharTotalCopper then
        return 0
    end
    local copper = ns.Utilities:GetCharTotalCopper(charRow) or 0
    if not ns.Utilities.GetLiveCharacterMoneyCopper then
        return copper
    end
    local curKey = GetCurrentCharKey()
    if not curKey or not charKey then
        return copper
    end
    local ck = charKey
    local cur = curKey
    if ns.Utilities.GetCanonicalCharacterKey then
        ck = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        cur = ns.Utilities:GetCanonicalCharacterKey(curKey) or curKey
    end
    if ck == cur then
        return ns.Utilities:GetLiveCharacterMoneyCopper(copper)
    end
    return copper
end

function M.ResolveEasyAccessTotalGoldCopper()
    local total = 0
    local chars = GetCharacters()
    if chars then
        local curKey = GetCurrentCharKey()
        for charKey, charData in pairs(chars) do
            local copper = ns.Utilities and ns.Utilities.GetCharTotalCopper
                and ns.Utilities:GetCharTotalCopper(charData) or 0
            if curKey and CharKeysMatch(charKey, curKey) and ns.Utilities.GetLiveCharacterMoneyCopper then
                copper = ns.Utilities:GetLiveCharacterMoneyCopper(copper)
            end
            total = total + (tonumber(copper) or 0)
        end
    end
    local warbandCopper = 0
    if ns.Utilities and ns.Utilities.GetWarbandBankMoney then
        warbandCopper = ns.Utilities:GetWarbandBankMoney() or 0
    end
    if warbandCopper == 0 and ns.Utilities and ns.Utilities.GetWarbandBankTotalCopper and WarbandNexus then
        warbandCopper = ns.Utilities:GetWarbandBankTotalCopper(WarbandNexus) or 0
    end
    return total + warbandCopper
end

-- Forward declarations (RefreshEasyAccessHoverTooltip is defined above BuildEasyAccessTooltipData / WNTooltipShow).
local BuildEasyAccessTooltipData
local WNTooltipShow
local WNTooltipHide

local RefreshEasyAccessHoverTooltip = function()
    local hover = S.eaTooltipHover
    if not hover.anchor or not hover.charKey then
        return
    end
    local chars = GetCharacters()
    if not chars or not chars[hover.charKey] then
        return
    end
    local tip = BuildEasyAccessTooltipData(hover.charKey, hover.entry)
    if not tip then
        return
    end
    WNTooltipShow(hover.anchor, {
        type = "custom",
        title = EAL("CONFIG_VAULT_BUTTON_SECTION", "Easy Access"),
        icon = ICON_TEXTURE,
        titleColor = tip.titleColor,
        titleAffixPair = tip.titleAffixPair,
        description = tip.description,
        lines = tip.lines,
        anchor = "ANCHOR_RIGHT",
        maxWidth = 360,
    })
end

function M.GetActiveTodoCountForChar(charName, charRealm)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return 0
    end
    if not charName or charName == "" then
        return 0
    end
    if charName and issecretvalue and issecretvalue(charName) then
        return 0
    end
    if charRealm and issecretvalue and issecretvalue(charRealm) then
        charRealm = nil
    end
    local plans = WarbandNexus.db.global.plans
    if not plans then
        return 0
    end
    local n = 0
    for i = 1, #plans do
        local plan = plans[i]
        if plan and not plan.completed and not plan.completionNotified
            and plan.characterName == charName
            and (not charRealm or plan.characterRealm == charRealm) then
            n = n + 1
        end
    end
    return n
end

function M.CharHasVaultSnapshot(charKey)
    if not charKey then return false end
    if GetCharActivities(charKey) then return true end
    for _, cat in ipairs({ "raids", "mythicPlus", "world" }) do
        for _, slot in ipairs(GetSlotData(charKey, cat)) do
            if (tonumber(slot.threshold) or 0) > 0 then
                return true
            end
        end
    end
    return HasAnyProgress(charKey)
end

function M.ResolveVaultTooltipFlags(charKey, entry)
    if entry then
        return entry.isReady == true, entry.isPending == true, tonumber(entry.slots) or 0,
            entry.bounty, entry.voidcore, entry.gildedStash, entry.manaflux
    end
    if not charKey then
        return false, false, 0, nil, nil, nil, nil
    end
    local pveCache = GetPveCache()
    local rewards = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
    local rewardData = rewards and LookupPveCacheSubtable(rewards, charKey)
    local isReady = rewardData and rewardData.hasAvailableRewards or false
    local currentKey = GetCurrentCharKey()
    if CharKeysMatch(charKey, currentKey) then
        if WarbandNexus and WarbandNexus.HasUnclaimedVaultRewards then
            isReady = WarbandNexus:HasUnclaimedVaultRewards()
        else
            isReady = false
        end
    elseif not isReady and not CharKeysMatch(charKey, currentKey)
        and (CountReadySlots(charKey) or 0) > 0
        and VaultResetCrossedFor(charKey) then
        isReady = true
    end
    local isPending = not isReady and HasAnyProgress(charKey)
    return isReady, isPending, CountReadySlots(charKey),
        GetBountyStatus(charKey), GetVoidcoreData(charKey), GetGildedStashData(charKey), GetManafluxData(charKey)
end

function M.AppendVaultStatusLine(lines, isReady, isPending, slotsEarned)
    if isReady then
        right = "|cff44ff44" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_READY", "Ready to claim") .. "|r"
    elseif slotsEarned and slotsEarned > 0 then
        right = "|cff66ddff" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_SLOTS", "%d slot(s) earned", slotsEarned) .. "|r"
    elseif isPending then
        right = "|cffffd700" .. EAL("EA_TOOLTIP_SUMMARY_CHAR_PROGRESS", "In progress") .. "|r"
    else
        right = "|cff888888" .. DASH .. "|r"
    end
    lines[#lines + 1] = {
        left = EAIconLabel(M.EA_STATUS_ICON, nil, "PVE_HEADER_STATUS_SHORT", "Status"),
        right = right,
        leftColor = M.EA_LABEL_COLOR,
        rightColor = M.EA_VALUE_COLOR,
    }
end

function M.AppendCharacterVaultTooltipLines(lines, charKey, entry)
    if not ShowEasyAccessDisplay("tooltipVault")
        and not ShowEasyAccessDisplay("tooltipBounty")
        and not ShowEasyAccessDisplay("tooltipVoidcore")
        and not ShowEasyAccessDisplay("tooltipGildedStash")
        and not ShowEasyAccessDisplay("tooltipManaflux")
        and not ShowEasyAccessDisplay("tooltipKeystone")
        and not ShowEasyAccessDisplay("tooltipMythicScore") then
        return
    end

    local settings = GetSettings()
    local chars = GetCharacters()
    local charRow = chars and chars[charKey]
    local shiftHeld = IsShiftKeyDown and IsShiftKeyDown() or false
    local isReady, isPending, slotsEarned, bounty, voidcore, gildedStash, manaflux =
        ResolveVaultTooltipFlags(charKey, entry)

    if ShowEasyAccessDisplay("tooltipVault") then
        if not CharHasVaultSnapshot(charKey) and not isReady and not isPending and (slotsEarned or 0) <= 0 then
            lines[#lines + 1] = {
                text = EAL("EA_TOOLTIP_NO_CHAR_VAULT", "No vault data for this character yet. Open the Great Vault once."),
                color = M.EA_LABEL_COLOR,
            }
        else
            lines[#lines + 1] = { type = "spacer", height = 4 }
            lines[#lines + 1] = {
                text = EAL("EA_TOOLTIP_SECTION_VAULT", "Great Vault"),
                color = M.EA_SECTION_COLOR,
            }

            local catDefs = GetEnabledCategoryDefs()
            if #catDefs > 0 then
                for ci = 1, #catDefs do
                    local cat = catDefs[ci]
                    local tipMeta = M.EA_CAT_TIP[cat.key]
                    local slots = GetSlotData(charKey, cat.key)
                    local right = ns.VaultFormatCategoryColumn(slots, cat.key, {
                        shiftHeld = shiftHeld,
                        showRewardProgress = settings.showRewardProgress,
                        showRewardItemLevel = settings.showRewardItemLevel,
                        vaultLootClaimable = isReady,
                    })
                    lines[#lines + 1] = {
                        left = EAIconLabel(
                            tipMeta and tipMeta.icon or cat.icon,
                            nil,
                            tipMeta and tipMeta.key or "EA_TOOLTIP_CAT_RAID",
                            tipMeta and tipMeta.fallback or cat.label),
                        right = right,
                        leftColor = M.EA_LABEL_COLOR,
                        rightColor = M.EA_VALUE_COLOR,
                    }
                end
            end

            AppendVaultStatusLine(lines, isReady, isPending, slotsEarned)
        end
    end

    if ShowEasyAccessDisplay("tooltipBounty") and bounty ~= nil then
        local bountyRight = bounty and EAL("EA_TOOLTIP_BOUNTY_DONE", "Collected")
            or EAL("EA_TOOLTIP_BOUNTY_TODO", "Not collected")
        local bountyColor = bounty and { 0.35, 0.9, 0.4 } or { 0.9, 0.55, 0.35 }
        lines[#lines + 1] = {
            left = EAIconLabel(GetBountyColumnIcon(), nil, "EA_TOOLTIP_BOUNTY_LABEL", "Trovehunter's Bounty"),
            right = bountyRight,
            leftColor = M.EA_LABEL_COLOR,
            rightColor = bountyColor,
        }
    end

    if ShowEasyAccessDisplay("tooltipVoidcore") and voidcore then
        local right = FormatProgressFraction(voidcore.progress, voidcore.seasonMax, voidcore.isCapped)
        if voidcore.isCapped then
            right = right .. EAL("EA_TOOLTIP_VOIDCORE_CAPPED_SUFFIX", " (capped)")
        end
        lines[#lines + 1] = {
            left = EAIconLabel(TRACK_ICONS.voidcore, nil, "EA_TOOLTIP_VOIDCORE_LABEL", "Nebulous Voidcore"),
            right = right,
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
    end

    if ShowEasyAccessDisplay("tooltipGildedStash") and gildedStash then
        local maxClaims = gildedStash.max or 4
        if gildedStash.unknown then
            right = EAL("EA_TOOLTIP_STASH_UNKNOWN", "?/%d", maxClaims)
        else
            right = EAL("EA_TOOLTIP_STASH_CLAIMED", "%d/%d claimed", gildedStash.current or 0, maxClaims)
        end
        lines[#lines + 1] = {
            left = EAIconLabel(TRACK_ICONS.gildedStash, nil, "EA_TOOLTIP_STASH_LABEL", "Gilded Stashes"),
            right = right,
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
        if gildedStash.unknown then
            lines[#lines + 1] = {
                text = EAL("EA_TOOLTIP_STASH_SCAN_HINT",
                    "T11 Bountiful delve reward. Log in on this character and open Delves (J) once to scan."),
                color = M.EA_FOOTER_COLOR,
            }
        end
    end

    if ShowEasyAccessDisplay("tooltipManaflux") and manaflux then
        local mfProgress = manaflux.quantity or 0
        local mfMax = 0
        if WarbandNexus and WarbandNexus.GetCurrencyData then
            local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, MANAFLUX_ID, charKey)
            if ok and cd then
                mfMax = tonumber(cd.seasonMax) or tonumber(cd.maxQuantity) or 0
                if cd.useTotalEarnedForMaxQty and cd.totalEarned then
                    mfProgress = tonumber(cd.totalEarned) or mfProgress
                end
            end
        end
        lines[#lines + 1] = {
            left = EAIconLabel(GetCurrencyIconTexture(MANAFLUX_ID, TRACK_ICONS.manaflux), nil,
                "EA_TOOLTIP_MANAFLUX_LABEL", "Dawnlight Manaflux"),
            right = FormatProgressFraction(mfProgress, mfMax, mfMax > 0 and mfProgress >= mfMax),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
    end

    if ShowEasyAccessDisplay("tooltipKeystone") then
        lines[#lines + 1] = {
            left = EAIconLabel(TRACK_ICONS.keystone, KEYSTONE_ICON_ATLAS, "EA_TOOLTIP_KEYSTONE_LABEL", "Keystone"),
            right = FormatKeystoneTooltipRight(charKey, charRow),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
    end

    if ShowEasyAccessDisplay("tooltipMythicScore") then
        lines[#lines + 1] = {
            left = EAIconLabel(TRACK_ICONS.mythicPlus, nil, "EA_TOOLTIP_MYTHIC_SCORE_LABEL", "M+ Rating"),
            right = FormatMythicScoreTooltipRight(charKey),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
    end
end

function M.AppendWarbandVaultSummaryLines(lines)
    if not ShowEasyAccessDisplay("tooltipVault") then
        return
    end
    local list = BuildCharList()
    if #list == 0 then
        lines[#lines + 1] = {
            text = EAL("EA_TOOLTIP_NO_WARBAND_VAULT", "No tracked vault activity this week."),
            color = M.EA_LABEL_COLOR,
        }
        return
    end
    local readyN, progN, slotN = 0, 0, 0
    for i = 1, #list do
        local e = list[i]
        if e.isReady then
            readyN = readyN + 1
        elseif e.isPending then
            progN = progN + 1
        elseif (e.slots or 0) > 0 then
            slotN = slotN + 1
        end
    end
    lines[#lines + 1] = { type = "spacer", height = 4 }
    lines[#lines + 1] = {
        text = EAL("EA_TOOLTIP_SECTION_WARBAND", "Warband"),
        color = M.EA_SECTION_COLOR,
    }
    if readyN > 0 then
        lines[#lines + 1] = {
            left = NormalizeColonLabel(EAL("EA_TOOLTIP_SECTION_VAULT", "Great Vault")),
            right = EAL("EA_TOOLTIP_SUMMARY_READY_COUNT", "%d ready to claim", readyN),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = { 0.35, 0.9, 0.4 },
        }
    end
    if progN > 0 then
        lines[#lines + 1] = {
            left = NormalizeColonLabel(EAL("EA_TOOLTIP_STATUS_IN_PROGRESS", "In progress this week")),
            right = tostring(progN),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = { 1, 0.82, 0 },
        }
    end
    if slotN > 0 then
        lines[#lines + 1] = {
            left = NormalizeColonLabel(EAL("EA_TOOLTIP_STATUS_SLOTS_EARNED", "%d slot(s) earned - claim at the Great Vault")),
            right = tostring(slotN),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = { 0.4, 0.85, 1 },
        }
    end
    lines[#lines + 1] = {
        text = EAL("EA_TOOLTIP_GRID_SUB", "Raid, Dungeon, and World columns match the tracker. Shift: remaining to next slot."),
        color = M.EA_FOOTER_COLOR,
    }
end

--- Plans-style tooltip payload: hero name + ilvl in header band, realm subtitle, metric double-lines.
BuildEasyAccessTooltipData = function(charKey, entry)
    local chars = GetCharacters()
    local charRow = chars and chars[charKey]
    local tooltipEntry = entry or {}
    if not tooltipEntry.name and charRow then
        tooltipEntry.name = charRow.name
    end
    if not tooltipEntry.classFile and charRow then
        tooltipEntry.classFile = charRow.classFile
    end
    if not tooltipEntry.realm and charRow then
        tooltipEntry.realm = charRow.realm
    end
    if entry and entry.itemLevel and not tooltipEntry.itemLevel then
        tooltipEntry.itemLevel = entry.itemLevel
    end

    local ilvl = (entry and entry.itemLevel) or (charRow and charRow.itemLevel) or 0
    local settings = GetSettings()
    local warbandSummary = settings.showSummaryOnMouseover == true and not entry
    local shiftHeld = IsShiftKeyDown and IsShiftKeyDown() or false

    local lines = {}
    if warbandSummary then
        AppendWarbandVaultSummaryLines(lines)
        if #lines > 0 then
            lines[#lines + 1] = { type = "spacer", height = 6 }
        end
    elseif charKey then
        local before = #lines
        AppendCharacterVaultTooltipLines(lines, charKey, entry)
        if #lines > before then
            lines[#lines + 1] = { type = "spacer", height = 6 }
        end
    end

    if ShowEasyAccessDisplay("tooltipGold") then
        lines[#lines + 1] = {
            left = EAIconLabel("Interface\\MoneyFrame\\UI-GoldIcon", "coin-gold", "EA_TOOLTIP_LINE_GOLD", "Gold"),
            right = EAFormatMoneyCopper(ResolveEasyAccessGoldCopper(charKey, charRow)),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
        if shiftHeld and not warbandSummary then
            lines[#lines + 1] = {
                left = EAIconLabel("Interface\\MoneyFrame\\UI-GoldIcon", "coin-gold", "TOTAL_GOLD_LABEL", "Total Gold:"),
                right = EAFormatMoneyCopper(ResolveEasyAccessTotalGoldCopper()),
                leftColor = M.EA_LABEL_COLOR,
                rightColor = { 0.35, 0.9, 0.4 },
            }
        end
    end
    if charKey and not warbandSummary and ShowEasyAccessDisplay("tooltipTodo") then
        lines[#lines + 1] = {
            left = EAIconLabel("Interface\\Icons\\INV_Misc_Map_01", nil, "EA_TOOLTIP_LINE_TODO", "To-Do"),
            right = EAFormatTodoValue(GetActiveTodoCountForChar(tooltipEntry.name, tooltipEntry.realm)),
            leftColor = M.EA_LABEL_COLOR,
            rightColor = M.EA_VALUE_COLOR,
        }
    end
    if charKey and not warbandSummary and ShowEasyAccessDisplay("tooltipVault") then
        local catDefs = GetEnabledCategoryDefs()
        if #catDefs > 0 then
            lines[#lines + 1] = { type = "spacer", height = 4 }
            lines[#lines + 1] = {
                text = EAL("EA_TOOLTIP_SHIFT_HINT", "Hold Shift on vault columns for remaining progress."),
                color = M.EA_FOOTER_COLOR,
            }
        end
    end
    lines[#lines + 1] = { type = "spacer", height = 8 }
    lines[#lines + 1] = {
        text = EAL("EA_TOOLTIP_CONTROLS", "Left-click: action  |  Right-click: menu  |  Drag to move"),
        color = M.EA_FOOTER_COLOR,
    }

    return {
        titleAffixPair = {
            left = FormatEasyAccessCharacterTitle(charRow, tooltipEntry),
            right = EAFormatTitleIlvl(ilvl),
            leftColor = { 1, 1, 1 },
            rightColor = { 1, 0.82, 0 },
        },
        lines = lines,
        titleColor = EAAccentTitleColor(),
    }
end

-- ============================================================================
-- Themed tooltip helpers (delegate to ns.UI_ShowTooltip / ns.UI_HideTooltip,
-- with GameTooltip fallback before TooltipService is initialised).
-- ============================================================================
WNTooltipShow = function(anchor, data)
    if ns.UI_ShowTooltip and WarbandNexus and WarbandNexus.Tooltip then
        ns.UI_ShowTooltip(anchor, data)
    else
        GameTooltip:SetOwner(anchor, data.anchor or "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local tc = data.titleColor or { 1, 0.82, 0 }
        if data.title then
            GameTooltip:AddLine(data.title, tc[1], tc[2], tc[3])
        end
        if data.titleAffixPair then
            local ap = data.titleAffixPair
            local lc = ap.leftColor or { 1, 1, 1 }
            local rc = ap.rightColor or { 1, 0.82, 0 }
            GameTooltip:AddDoubleLine(ap.left or "", ap.right or "", lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
        end
        if data.description then
            GameTooltip:AddLine(data.description, 0.55, 0.57, 0.62)
        end
        if data.lines then
            for _, line in ipairs(data.lines) do
                if line.left or line.right then
                    local lc, rc = line.leftColor or { 1, 1, 1 }, line.rightColor or { 1, 1, 1 }
                    GameTooltip:AddDoubleLine(line.left or "", line.right or "",
                        lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
                else
                    local c = line.color or { 1, 1, 1 }
                    GameTooltip:AddLine(line.text or "", c[1], c[2], c[3], line.wrap == true)
                end
            end
        end
        GameTooltip:Show()
    end
end

WNTooltipHide = function()
    if ns.UI_HideTooltip then ns.UI_HideTooltip() else GameTooltip:Hide() end
end

-- ============================================================================
-- Hover tooltip (current character summary)
-- ============================================================================
function M.ShowHoverTooltip(anchor)
    EnsureVaultShiftWatcher()
    local charKey = GetCurrentCharKey()
    local chars = GetCharacters()
    if not charKey or not chars or not chars[charKey] then
        S.eaTooltipHover.anchor = anchor
        S.eaTooltipHover.charKey = nil
        S.eaTooltipHover.entry = nil
        WNTooltipShow(anchor, {
            type = "custom",
            title = EAL("CONFIG_VAULT_BUTTON_SECTION", "Easy Access"),
            icon = ICON_TEXTURE,
            anchor = "ANCHOR_RIGHT",
            maxWidth = 360,
            lines = {
                {
                    text = EAL("EA_TOOLTIP_NO_CHAR", "No character data yet."),
                    color = M.EA_LABEL_COLOR,
                },
            },
        })
        return
    end
    S.eaTooltipHover.anchor = anchor
    S.eaTooltipHover.charKey = charKey
    S.eaTooltipHover.entry = nil
    RefreshEasyAccessHoverTooltip()
end

M.UpdateBadge = UpdateBadge
M.BuildEasyAccessTooltipData = BuildEasyAccessTooltipData
M.RefreshEasyAccessHoverTooltip = RefreshEasyAccessHoverTooltip
M.WNTooltipShow = WNTooltipShow
M.WNTooltipHide = WNTooltipHide

-- ============================================================================

