--[[
    Warband Nexus - Gear paperdoll slot button factory.
    Split from GearUI_Paperdoll.lua (ops-040).
    Loaded after Modules/UI/GearUI_Paperdoll.lua (deps bound on ns.GearUI_Paperdoll._slotDeps).
]]

local _, ns = ...
ns.GearUI_Paperdoll = ns.GearUI_Paperdoll or {}

local function D(name)
    local deps = ns.GearUI_Paperdoll._slotDeps
    assert(deps, "GearUI_Paperdoll_Slots: bind _slotDeps before load")
    local v = deps[name]
    assert(v ~= nil, "GearUI_Paperdoll_Slots: missing dep " .. tostring(name))
    return v
end



    local GearFact = D("GearFact")
    local SLOT_SIZE = D("SLOT_SIZE")
    local GFR = D("GFR")
    local FontManager = D("FontManager")
    local GearGetFrameContentInset = D("GearGetFrameContentInset")
    local EMPTY_SLOT_TEXTURE = D("EMPTY_SLOT_TEXTURE")
    local SLOT_FALLBACK_TEXTURE = D("SLOT_FALLBACK_TEXTURE")
    local COLORS = D("COLORS")
    local GearSlotRefreshUpgradeArrow = D("GearSlotRefreshUpgradeArrow")
    local GearSlotClearPaperdollOverlays = D("GearSlotClearPaperdollOverlays")
    local PlaceGearUpgradeLockTowardModel = D("PlaceGearUpgradeLockTowardModel")
    local STATUS_UPGRADE_ICON = D("STATUS_UPGRADE_ICON")
    local STATUS_ICON_INSET = D("STATUS_ICON_INSET")
    local GEAR_DEBUG_ALWAYS_SHOW_UPGRADE = D("GEAR_DEBUG_ALWAYS_SHOW_UPGRADE")
    local TRACK_TEXT_W = D("TRACK_TEXT_W")
    local TEXT_OFFSET_FROM_SLOT_CENTER = D("TEXT_OFFSET_FROM_SLOT_CENTER")
    local ShowTooltip = D("ShowTooltip")
    local HideTooltip = D("HideTooltip")
    local SLOT_BY_ID = D("SLOT_BY_ID")
    local tinsert = D("tinsert")
    local issecretvalue = D("issecretvalue")
    local format = D("format")
    local GearSlotHideLegacyIncreaseLabels = D("GearSlotHideLegacyIncreaseLabels")
    local SLOT_HALF = D("SLOT_HALF")
    local LocalizeUpgradeTrackName = D("LocalizeUpgradeTrackName")

function ns.GearUI_Paperdoll.CreateSlotButton(parent, slotID, slotData, x, y, hasUpgradePath, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar, inspectListHost)
    -- Slot is always the same size; space reserved even when the icon is hidden (empty texture)
    local btn = GearFact:CreateButton(parent, SLOT_SIZE, SLOT_SIZE, true)
    btn:SetPoint("TOPLEFT", x, y)
    if btn.SetClipsChildren then btn:SetClipsChildren(false) end
    btn._slotID = slotID
    btn._slotDataRef = slotData
    btn._gearUpgradeInfo = upgradeInfo
    btn._gearCurrencyAmounts = currencyAmounts
    btn._gearIsCurrentChar = (isCurrentChar == true)
    btn._gearInspectSt = {
        hasEnchant = false,
        isMissingGem = false,
        isEnchantable = false,
        craftingQualityTier = nil,
        ready = false,
        socketSig = "",
        socketEntries = nil,
    }
    btn._needsDeferredInspect = false
    if slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
        btn._needsDeferredInspect = true
    end
    local inspectRoot = inspectListHost or parent
    if inspectRoot then
        inspectRoot._gearSlotInspectList = inspectRoot._gearSlotInspectList or {}
        tinsert(inspectRoot._gearSlotInspectList, btn)
    end

    -- Plain icon cell (no rim / dark fill — both Modern and Classic)
    local borderFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    borderFrame:SetAllPoints()
    if ns.GearUI_Chrome and ns.GearUI_Chrome.ApplyGearSlotPlainChrome then
        ns.GearUI_Chrome.ApplyGearSlotPlainChrome(btn, borderFrame, nil)
    else
        borderFrame:Hide()
    end
    btn.borderFrame = borderFrame

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:Hide()
    btn._gearSlotBg = bg

    -- Item / empty slot texture
    local rimInset = GearGetFrameContentInset()
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", rimInset, -rimInset)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -rimInset, rimInset)
    btn.iconTex = tex

    -- ilvl label (bottom-right overlay); FontManager applies font before Populate() SetText
    btn.ilvlLabel = FontManager:CreateFontString(btn, GFR("gearSlotIlvl"), "OVERLAY")
    if btn.ilvlLabel then
        btn.ilvlLabel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -rimInset, rimInset)
        btn.ilvlLabel:SetJustifyH("RIGHT")
        if btn.ilvlLabel.SetDrawLayer then btn.ilvlLabel:SetDrawLayer("OVERLAY", 7) end
    end

    -- Populate with item or empty slot art
    local function Populate(data)
        if data and data.itemLink then
            local icon = ns.GearUI_GetItemIconSafe(data.itemLink) or ns.GearUI_GetItemIconSafe(data.itemID)
            if (not icon or icon == 0 or icon == "") and isCurrentChar == true and btn._slotID
                and ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemIcon then
                pcall(function()
                    local loc = ItemLocation:CreateFromEquipmentSlot(btn._slotID)
                    if loc and loc:IsValid() then
                        local ic = C_Item.GetItemIcon(loc)
                        if ic and ic ~= 0 and ic ~= "" then icon = ic end
                    end
                end)
            end
            if icon then
                tex:SetVertexColor(1, 1, 1, 1)
                tex:SetTexture(icon)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif not (issecretvalue and issecretvalue(data.itemLink)) then
                -- Item cache not warmed yet — avoid empty-slot art while link is valid.
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                tex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
                tex:SetTexCoord(0, 1, 0, 1)
            end

            -- ilvl label (only when slot has an item link and valid ilvl)
            if btn.ilvlLabel and data.itemLink and data.itemLevel and data.itemLevel > 0 then
                btn.ilvlLabel:SetText(tostring(math.floor(tonumber(data.itemLevel) or 0)))
                ns.UI_SetTextColorRole(btn.ilvlLabel, "Bright")
                if ns.UI_ApplyOverlayLabelShadow then
                    ns.UI_ApplyOverlayLabelShadow(btn.ilvlLabel)
                else
                    btn.ilvlLabel:SetShadowOffset(1, -1)
                    btn.ilvlLabel:SetShadowColor(0, 0, 0, 1)
                end
                btn.ilvlLabel:Show()
            elseif btn.ilvlLabel then
                btn.ilvlLabel:Hide()
            end
        else
            -- Empty slot
            tex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
            tex:SetTexCoord(0, 1, 0, 1)
            if btn.ilvlLabel then btn.ilvlLabel:Hide() end
            GearSlotClearPaperdollOverlays(btn)
        end
    end

    Populate(slotData)

    local side = textSide or "right"
    btn._gearTextSide = side
    btn._gearTextWidth = textWidth
    local upgradeArrow = nil

    local isBottomLeft  = (side == "bottom" or side == "bottom_left")
    local isBottomRight = (side == "bottom_right")

    -- Center line: text center, icon center, and slot center on the same horizontal line (left/right/bottom)
    local upSlot = upgradeInfo and upgradeInfo[slotID]
    local isCraftedSlot = upSlot and upSlot.isCrafted
    local arrowDisplay = (upSlot and ns.GearUI_GetUpgradeArrowDisplay)
        and ns.GearUI_GetUpgradeArrowDisplay(upSlot, currencyAmounts) or nil
    if upSlot then upSlot.upgradeArrowDisplay = arrowDisplay end
    local statusUpgradeSz = STATUS_UPGRADE_ICON - 2 * STATUS_ICON_INSET
    local wantDebugUpgrade = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE == true and slotData and slotData.itemLink
        and not (issecretvalue and issecretvalue(slotData.itemLink))
    -- Always reserve an arrow texture when the slot has an item (unless lock-only), so a late upgradeInfo refresh can still show/hide in _gearApplySlotVisual.
    local hasItemNow = slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink))
    local lockOnly = isNotUpgradeable and hasItemNow and not wantDebugUpgrade
    local showUpgradeChip = wantDebugUpgrade
        or (hasUpgradePath and arrowDisplay == "green" and hasItemNow and not isNotUpgradeable)
    local canAffordNext = (arrowDisplay == "green")
    if not lockOnly and showUpgradeChip then
        local upgradeBd = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrowBgBorder = upgradeBd
        upgradeBd:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        upgradeBd:SetVertexColor(0.1, 0.78, 0.26, 0.95)
        if upgradeBd.SetDrawLayer then upgradeBd:SetDrawLayer("OVERLAY", 5) end
        if upgradeBd.SetFrameLevel and btn.GetFrameLevel then
            upgradeBd:SetFrameLevel((btn:GetFrameLevel() or 0) + 2)
        end

        local upgradeBg = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrowBg = upgradeBg
        upgradeBg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        upgradeBg:SetVertexColor(0, 0, 0, 0.88)
        if upgradeBg.SetDrawLayer then upgradeBg:SetDrawLayer("OVERLAY", 6) end
        if upgradeBg.SetFrameLevel and btn.GetFrameLevel then
            upgradeBg:SetFrameLevel((btn:GetFrameLevel() or 0) + 3)
        end

        upgradeArrow = btn:CreateTexture(nil, "OVERLAY")
        btn._gearUpgradeArrow = upgradeArrow
        if upgradeArrow.SetFrameLevel and btn.GetFrameLevel then
            upgradeArrow:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
        end
        local useCraftedAtlas = isCraftedSlot and hasUpgradePath and canAffordNext
        btn._gearUpgradeArrowCraftedAtlas = (useCraftedAtlas == true)
        if useCraftedAtlas and upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("Professions-Crafting-Orders-Icon", false)
            if upgradeArrow.SetVertexColor then upgradeArrow:SetVertexColor(1, 1, 1) end
        elseif upgradeArrow.SetAtlas then
            upgradeArrow:SetAtlas("loottoast-arrow-green", false)
            if upgradeArrow.SetVertexColor then upgradeArrow:SetVertexColor(0.2, 1, 0.48) end
        else
            upgradeArrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            upgradeArrow:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            upgradeArrow:SetVertexColor(0.15, 1, 0.42)
        end
        if upgradeArrow.SetDrawLayer then upgradeArrow:SetDrawLayer("OVERLAY", 7) end
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, upgradeBd, upgradeBg, upgradeArrow, nil)
    elseif lockOnly then
        local lockIcon = btn:CreateTexture(nil, "OVERLAY")
        btn._gearLockIcon = lockIcon
        lockIcon:SetSize(statusUpgradeSz, statusUpgradeSz)
        if lockIcon.SetFrameLevel and btn.GetFrameLevel then
            lockIcon:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
        end
        if lockIcon.SetDrawLayer then lockIcon:SetDrawLayer("OVERLAY", 7) end
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, nil, nil, nil, lockIcon)
        lockIcon:SetTexture("Interface\\Common\\LockIcon")
        lockIcon:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    end

    -- Tooltip: item link + simplified upgrade info (custom tooltip service)
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]

    -- Enchant/gem/socket scan deferred to next frame (see GearSlotApplyDeferredEnchantGemInspect).
    btn._gearLayoutCtx = { side = side, upgradeArrow = upgradeArrow, upgradeArrowBg = btn._gearUpgradeArrowBg, upgradeArrowBgBorder = btn._gearUpgradeArrowBgBorder }

    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            local snap = self._slotDataRef or slotData
            local up = upgradeInfo and upgradeInfo[slotID]
            if up and snap and ns.Gear_SyncUpgradeEntryFromSlot then
                up = ns.Gear_SyncUpgradeEntryFromSlot(up, snap) or up
                if upgradeInfo then upgradeInfo[slotID] = up end
            end
            if up and ns.GearUI_GetUpgradeArrowDisplay then
                up.upgradeArrowDisplay = ns.GearUI_GetUpgradeArrowDisplay(up, currencyAmounts)
                GearSlotRefreshUpgradeArrow(self, snap or slotData, (up and up.notUpgradeable) or false)
            end
            local additionalLines = {}
            local underTitleLines

            -- Stat / enchant / gem body comes from C_TooltipInfo.GetHyperlink in TooltipService (Blizzard lines + icons).
            -- Only append Warband-specific upgrade / recraft hints below.

            if up and up.isCrafted then
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                local tierLabel = LocalizeUpgradeTrackName(up.craftedTierName or "Crafted")
                if not up.canUpgrade then
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_CRAFTED_MAX_ILVL_LINE"]) or "%s (max ilvl %d)", tierLabel, up.currentIlvl or 0),
                        color = { 0.6, 0.6, 0.6 }
                    }
                else
                    local range = ns.GearUI_GetCraftedIlvlRange(up, currencyAmounts)
                    if range then
                        local bestName = LocalizeUpgradeTrackName(range.bestCrestName or "")
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_CRAFTED_RECAST_TO_LINE"]) or "Recraft to %s (ilvl %d)", bestName, range.maxIlvl),
                            color = { 0.4, 1, 0.4 }
                        }
                    else
                        additionalLines[#additionalLines + 1] = {
                            text = (ns.L and ns.L["GEAR_CRAFTED_NO_CRESTS"]) or "No crests available for recraft",
                            color = { 0.8, 0.5, 0.2 }
                        }
                    end
                end
            elseif up and up.canUpgrade then
                additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                if ns.GearUI_CanAffordImmediateNextStep then
                    up.canAffordNext = ns.GearUI_CanAffordImmediateNextStep(up, currencyAmounts)
                end
                local canPayNext = up.canAffordNext == true
                local crestNeed = (ns.GearUI_GetNextStepCrestNeed and ns.GearUI_GetNextStepCrestNeed(up)) or (up.crestCost or 20)
                local cid = up.currencyID or 0
                local haveCrests = (currencyAmounts and currencyAmounts[cid]) or 0
                local goldCopper = (ns.GearUI_GetGearCurrencyGoldCopper and ns.GearUI_GetGearCurrencyGoldCopper(currencyAmounts))
                    or ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
                local goldNeed = up.moneyCost or (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000)
                local nextTier = (up.currUpgrade or 0) + 1
                local TRACK_ILVLS = ns.TRACK_ILVLS
                local nextIlvl = TRACK_ILVLS and TRACK_ILVLS[up.trackName] and TRACK_ILVLS[up.trackName][nextTier]
                local ilvlStr = nextIlvl and format(" (%d)", nextIlvl) or ""
                if canPayNext then
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_UPGRADE_AVAILABLE_FORMAT"]) or "Available upgrade to %s %d/%d%s", LocalizeUpgradeTrackName(up.trackName or ""), nextTier, up.maxUpgrade or 0, ilvlStr),
                        color = { 0.4, 1, 0.4 }
                    }
                    if crestNeed > 0 then
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_TT_NEXT_STEP_CRESTS"]) or "Next step: %d %s.", crestNeed, (ns.L and ns.L["GEAR_TT_DAWNCREST_WORD"]) or "Dawncrest"),
                            color = { 0.6, 0.9, 0.6 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_SLOT_CURRENCY_HAVE_NEED"]) or "%d/%d", haveCrests, crestNeed),
                            color = { 0.55, 0.95, 0.55 }
                        }
                        if up.nextUpgradeIsDiscounted then
                            additionalLines[#additionalLines + 1] = {
                                text = (ns.L and ns.L["GEAR_TT_DISCOUNTED_UPGRADE"]) or "Discounted crest cost (high watermark)",
                                color = { 0.55, 0.82, 1 }
                            }
                        end
                    elseif ns.GearUI_IsNextStepGoldOnlyUpgrade and ns.GearUI_IsNextStepGoldOnlyUpgrade(up) then
                        additionalLines[#additionalLines + 1] = {
                            text = (ns.L and ns.L["GEAR_CRESTS_GOLD_ONLY"]) or "Crests needed: 0 (gold only — previously reached)",
                            color = { 1, 0.85, 0.4 }
                        }
                    end
                else
                    if crestNeed > 0 then
                        local crestWord = (ns.L and ns.L["GEAR_TT_DAWNCREST_WORD"]) or "Dawncrest"
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_TT_NEXT_STEP_CRESTS"]) or "Next step: %d %s.", crestNeed, crestWord),
                            color = { 0.85, 0.85, 0.85 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_NEED_MORE_CRESTS_FORMAT"]) or "%s %d/%d - need more crests", LocalizeUpgradeTrackName(up.trackName or ""), haveCrests, crestNeed),
                            color = { 1, 0.55, 0.25 }
                        }
                        if up.nextUpgradeIsDiscounted then
                            additionalLines[#additionalLines + 1] = {
                                text = (ns.L and ns.L["GEAR_TT_DISCOUNTED_UPGRADE"]) or "Discounted crest cost (high watermark)",
                                color = { 0.55, 0.82, 1 }
                            }
                        end
                    elseif goldCopper < goldNeed then
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_TT_NEXT_STEP_GOLD_ONLY"]) or "Next step: gold only (you already reached this item level on this slot)."),
                            color = { 1, 0.85, 0.4 }
                        }
                        additionalLines[#additionalLines + 1] = {
                            text = format("Gold %d / %d", math.floor(goldCopper / 10000), math.floor(goldNeed / 10000)),
                            color = { 1, 0.55, 0.25 }
                        }
                    else
                        additionalLines[#additionalLines + 1] = {
                            text = format((ns.L and ns.L["GEAR_NEED_MORE_CRESTS_FORMAT"]) or "%s %d/%d - need more crests", LocalizeUpgradeTrackName(up.trackName or ""), haveCrests, crestNeed),
                            color = { 1, 0.55, 0.25 }
                        }
                    end
                end
            end

            if #additionalLines == 0 then
                additionalLines = nil
            end

            if ShowTooltip then
                ShowTooltip(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    underTitleLines = underTitleLines,
                    itemTooltipContext = itemTooltipContext,
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    underTitleLines = underTitleLines,
                    itemTooltipContext = itemTooltipContext,
                })
            end
        else
            local title = (slotDef and slotDef.label) or "Empty"
            if ShowTooltip then
                ShowTooltip(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = (ns.L and ns.L["GEAR_NO_ITEM_EQUIPPED"]) or "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = (ns.L and ns.L["GEAR_NO_ITEM_EQUIPPED"]) or "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                })
            end
        end
    end)
    btn:SetScript("OnLeave", function()
        if HideTooltip then
            HideTooltip()
        elseif ns.TooltipService then
            ns.TooltipService:Hide()
        end
    end)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    local hiA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.08 or 0.12
    hi:SetColorTexture(1, 1, 1, hiA)

    -- Slot name (Head, Trinket 1, Main Hand etc.) — above the Veteran/Champion text
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
    local slotName = (slotDef and slotDef.label) and slotDef.label or ""
    -- Labels: API slot 11 = first finger, 12 = second (matches default Character frame top-to-bottom).
    if slotID == 11 then slotName = (ns.L and ns.L["GEAR_SLOT_RING1"]) or "Ring 1"
    elseif slotID == 12 then slotName = (ns.L and ns.L["GEAR_SLOT_RING2"]) or "Ring 2"
    elseif slotID == 13 then slotName = (ns.L and ns.L["GEAR_SLOT_TRINKET1"]) or "Trinket 1"
    elseif slotID == 14 then slotName = (ns.L and ns.L["GEAR_SLOT_TRINKET2"]) or "Trinket 2"
    end
    local slotNameLabel
    if slotName ~= "" then
        slotNameLabel = FontManager:CreateFontString(parent, GFR("gearSlotName"), "OVERLAY")
        local slotHex = (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
        slotNameLabel:SetText(slotHex .. slotName .. "|r")
        slotNameLabel:SetNonSpaceWrap(false)
        if slotNameLabel.SetWordWrap then slotNameLabel:SetWordWrap(false) end
    end

    local trackText = (statusText and statusText ~= "") and statusText or nil
    local trackLabel = nil
    local w = textWidth or TRACK_TEXT_W
    local currentTextOffset = TEXT_OFFSET_FROM_SLOT_CENTER

    if trackText and side ~= "top" then
        trackLabel = FontManager:CreateFontString(parent, GFR("gearTrackLabel"), "OVERLAY")
        btn._gearTrackLabel = trackLabel
        trackLabel:SetText(trackText)
        trackLabel:SetNonSpaceWrap(false)
        if trackLabel.SetWordWrap then trackLabel:SetWordWrap(false) end
        trackLabel:SetWidth(w)

        if side == "left" or side == "right" or isBottomLeft or isBottomRight then
            local textCenterX
            if side == "left" or isBottomLeft then
                textCenterX = -currentTextOffset
            else
                textCenterX = currentTextOffset
            end
            local blockCenterOffset = 8
            trackLabel:ClearAllPoints()
            trackLabel:SetWidth(textWidth or TRACK_TEXT_W)
            trackLabel:SetPoint("CENTER", btn, "CENTER", textCenterX, -blockCenterOffset)

            if side == "left" or isBottomLeft then
                trackLabel:SetJustifyH("RIGHT")
            elseif side == "right" or isBottomRight then
                trackLabel:SetJustifyH("LEFT")
            else
                trackLabel:SetJustifyH("CENTER")
            end

            if slotNameLabel then
                slotNameLabel:ClearAllPoints()
                slotNameLabel:SetPoint("BOTTOM", trackLabel, "TOP", 0, 2)
                if side == "left" or isBottomLeft then
                    slotNameLabel:SetPoint("RIGHT", trackLabel, "RIGHT", 0, 0)
                    slotNameLabel:SetJustifyH("RIGHT")
                elseif side == "right" or isBottomRight then
                    slotNameLabel:SetPoint("LEFT", trackLabel, "LEFT", 0, 0)
                    slotNameLabel:SetJustifyH("LEFT")
                else
                    slotNameLabel:SetPoint("CENTER", trackLabel, "CENTER", 0, 0)
                    slotNameLabel:SetJustifyH("CENTER")
                end
            end
        end
    elseif slotNameLabel then
        if side == "left" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", -currentTextOffset, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("RIGHT")
        elseif side == "right" then
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", currentTextOffset, 0)
            slotNameLabel:SetWidth(TRACK_TEXT_W)
            slotNameLabel:SetJustifyH("LEFT")
        else
            slotNameLabel:SetPoint("CENTER", btn, "CENTER", (side == "bottom_right") and currentTextOffset or -currentTextOffset, 0)
            slotNameLabel:SetWidth(textWidth or TRACK_TEXT_W)
            slotNameLabel:SetJustifyH((side == "bottom_right") and "LEFT" or "RIGHT")
        end
    end

    function btn._gearApplySlotVisual(self, slotData, canUpgrade, trackStatusText, notUpgradeable)
        local prev = self._slotDataRef
        local prevLink = prev and prev.itemLink
        local newLink = slotData and slotData.itemLink
        local function linkEmpty(l)
            return not l or l == "" or (issecretvalue and issecretvalue(l))
        end
        local linkUnchanged = linkEmpty(newLink) == linkEmpty(prevLink)
            and (linkEmpty(newLink) or newLink == prevLink)

        self._slotDataRef = slotData
        self._needsDeferredInspect = false
        if slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
            local st = self._gearInspectSt
            if not linkUnchanged or not st or not st.ready then
                self._needsDeferredInspect = true
            end
        end
        if not linkUnchanged then
            if self._gearInspectSt then
                self._gearInspectSt.ready = false
                self._gearInspectSt.socketSig = ""
                self._gearInspectSt.socketEntries = nil
            end
            GearSlotClearPaperdollOverlays(self)
        end
        Populate(slotData)
        if self._gearTrackLabel then
            local t = (type(trackStatusText) == "string" and trackStatusText ~= "") and trackStatusText or ""
            if t == "" then
                self._gearTrackLabel:Hide()
            else
                self._gearTrackLabel:SetText(t)
                self._gearTrackLabel:Show()
            end
        end
        GearSlotRefreshUpgradeArrow(self, slotData, notUpgradeable)
        GearSlotHideLegacyIncreaseLabels(self)
        if self._gearLockIcon then
            if notUpgradeable and slotData and slotData.itemLink then self._gearLockIcon:Show() else self._gearLockIcon:Hide() end
        end
        self._gearLastCanAffordNext = canUpgrade == true
    end

    local upInit = upgradeInfo and upgradeInfo[slotID]
    local initArrow = (upInit and ns.GearUI_GetUpgradeArrowDisplay)
        and ns.GearUI_GetUpgradeArrowDisplay(upInit, currencyAmounts) or nil
    if upInit then upInit.upgradeArrowDisplay = initArrow end
    local canAffordInit = initArrow == "green"
    local trackTextInit = (statusText and statusText ~= "") and statusText or nil
    btn:_gearApplySlotVisual(slotData, canAffordInit, trackTextInit, isNotUpgradeable)

    return btn
end
assert(ns.GearUI_Paperdoll.CreateSlotButton, "GearUI_Paperdoll_Slots: CreateSlotButton export missing")
