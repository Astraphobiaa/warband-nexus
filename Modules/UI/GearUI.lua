--[[
    Warband Nexus - Gear Management Tab
    Paperdoll with Midnight Dawncrests and upgrade analysis.

    Layout:
    ┌────────────────────────────────────────────────────────────────────────────┐
    │ [Header: Title / subtitle (left)                    Character ▼ (right)]    │
    ├────────────────────────────────────────────────────────────────────────────┤
    │ Paperdoll — Slot icons (left/right/bottom) + portrait (center) + crests    │
    └────────────────────────────────────────────────────────────────────────────┘
]]

local _, ns = ...
local WarbandNexus, FontManager = ns.WarbandNexus, ns.FontManager

--- Tek merkez: Modules/FontManager.lua → FONT_ROLE
local function GFR(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- Services / helpers
local COLORS              = ns.UI_COLORS
local CreateCard          = ns.UI_CreateCard
local ApplyVisuals        = ns.UI_ApplyVisuals
local GetQualityHex       = ns.UI_GetQualityHex
local CreateThemedButton  = ns.UI_CreateThemedButton
local FormatGold          = ns.UI_FormatGold
local FormatNumber        = ns.UI_FormatNumber
local DrawEmptyState      = ns.UI_DrawEmptyState
local CreateHeaderIcon    = ns.UI_CreateHeaderIcon
local GetTabIcon          = ns.UI_GetTabIcon
local ShowTooltip         = ns.UI_ShowTooltip
local HideTooltip         = ns.UI_HideTooltip
local ApplyProfessionCraftingQualityAtlasToTexture = ns.UI_ApplyProfessionCraftingQualityAtlasToTexture
local GetEnchantmentCraftingQualityTierFromItemLink = ns.UI_GetEnchantmentCraftingQualityTierFromItemLink

-- Slot definitions from GearService
local GEAR_SLOTS         = ns.GEAR_SLOTS
local SLOT_BY_ID         = ns.SLOT_BY_ID
local EQUIP_LOC_TO_SLOTS = ns.EQUIP_LOC_TO_SLOTS

local format = string.format
local tinsert = table.insert
local wipe = wipe
local debugprofilestop = debugprofilestop

--[[ WN_FACTORY: `WarbandNexus.toc` loads SharedWidgets.lua before GearUI.lua; `ns.UI.Factory` is mandatory at runtime.
     Remaining raw `CreateFrame` (BackdropTemplate / UIPanel / wow widget types — not plain layout shells):
     • EnsureGearContentVeil — HIGH-strata opaque loading blocker + spinner over scrollChild.
     • CreateSlotButton `borderFrame` — dynamic quality-colored slot rim (`SetBackdropBorderColor`).
     • paperChrome, storagePanel — paper-band / recommendation card tinted shells.
     • `_gearPaperdollCenterPlaceholder` — deferred layout chrome on card when doll paints next frame.
     • `CreateFrame(widgetType, …)` — DressUpModel / PlayerModel (dynamic subtype).
     • Character selector trigger, Hide-filter opener, dropdown `menu`, hide-threshold popup `row` — custom combobox/popup chrome.
     • Fullscreen dismiss layers on UIParent — transparent hit targets (see also `GearFact:CreateButton` where used).]]
local GearFact = ns.UI.Factory

--- Minimum time the gear-tab loading veil stays visible (defer/yield can finish in one frame).
local GEAR_CONTENT_VEIL_MIN_DISPLAY_SEC = 0.5
--- Minimum time "Scanning storage…" stays up before swapping to rows/empty (avoids sub-500ms flicker).
local GEAR_STORAGE_SCANNING_MIN_DISPLAY_SEC = 0.5

--- Locale helper (defined before first use; GetLocalizedText is declared later in this file).
local function GearTabL(key, fallback)
    local v = ns.L and ns.L[key]
    if type(v) == "string" and v ~= "" and v ~= key then
        return v
    end
    return fallback
end

--- Paperdoll / portrait textures: aligns with `MAIN_SHELL.FRAME_CONTENT_INSET`.
local function GearGetFrameContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

--- Visible height of the results scroll viewport (scrollChild is often 1px tall during PopulateContent teardown).
---@param mf Frame|nil
---@return number
local function GearResultsViewportHeight(mf)
    local scroll = mf and mf.scroll
    if not scroll then return 480 end
    local h = scroll:GetHeight() or 0
    if h < 2 and mf.fixedHeader and scroll then
        local fhBot = mf.fixedHeader:GetBottom()
        local sb = scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            h = fhBot - sb
        end
    end
    return math.max(h, 400)
end

--- Loading veil inside the tab results container (scrollChild) only — not over header or chrome.
---@param scrollChild Frame
---@param mf Frame|nil
---@param gen number
local function EnsureGearContentVeil(scrollChild, mf, gen)
    if not scrollChild or not mf then return end
    if mf._gearVeilMinDismissTimer and mf._gearVeilMinDismissTimer.Cancel then
        mf._gearVeilMinDismissTimer:Cancel()
    end
    mf._gearVeilMinDismissTimer = nil
    local host = scrollChild._gearLoadingHost
    if not host or host:GetParent() ~= scrollChild then
        if host and host.Hide then host:Hide() end
        host = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        host._wnKeepOnTabSwitch = true
        host:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        host:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
        host:SetFrameStrata("HIGH")
        host:SetFrameLevel(500)
        host:EnableMouse(true)
        local spinner = host:CreateTexture(nil, "OVERLAY")
        spinner:SetSize(48, 48)
        spinner:SetPoint("CENTER", 0, 18)
        if spinner.SetAtlas then
            spinner:SetAtlas("auctionhouse-ui-loadingspinner")
        else
            spinner:SetTexture("Interface\\COMMON\\StreamCircle")
        end
        host._wnSpinner = spinner
        if FontManager then
            local titleFs = FontManager:CreateFontString(host, GFR("loadingCardTitle"), "OVERLAY")
            titleFs:SetPoint("TOP", spinner, "BOTTOM", 0, -10)
            titleFs:SetText("|cff00ccff" .. GearTabL("GEAR_TAB_LOADING", "Loading gear...") .. "|r")
            local hintFs = FontManager:CreateFontString(host, GFR("loadingCardHint"), "OVERLAY")
            hintFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -4)
            hintFs:SetTextColor(0.55, 0.58, 0.62)
            hintFs:SetText(GearTabL("PLEASE_WAIT", "Please wait..."))
        end
        scrollChild._gearLoadingHost = host
    end
    local w = scrollChild:GetWidth() or 0
    if w < 2 and mf.scroll then
        w = mf.scroll:GetWidth() or 800
    end
    local h = GearResultsViewportHeight(mf)
    host:SetSize(math.max(w, 320), h)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    host._veilGen = gen
    host._gearVeilShownAt = GetTime()
    host:Show()
    mf._gearContentVeil = host
    scrollChild:SetHeight(math.max(scrollChild:GetHeight() or 0, h))
    local spin = host._wnSpinner
    if spin and spin.SetRotation then
        host._wnSpinRot = host._wnSpinRot or 0
        host:SetScript("OnUpdate", function(self, elapsed)
            self._wnSpinRot = (self._wnSpinRot or 0) + (elapsed * 270)
            if spin.SetRotation then spin:SetRotation(math.rad(self._wnSpinRot)) end
        end)
    end
end

local function DismissGearContentVeil(mf, gen)
    local veil = mf and mf._gearContentVeil
    if not veil or veil._veilGen ~= gen then return end
    if mf._gearVeilMinDismissTimer and mf._gearVeilMinDismissTimer.Cancel then
        mf._gearVeilMinDismissTimer:Cancel()
    end
    mf._gearVeilMinDismissTimer = nil
    veil:SetScript("OnUpdate", nil)
    veil:Hide()
end

---@param mf Frame|nil
---@param gen number
local function TryDismissGearContentVeil(mf, gen)
    if not mf or gen ~= (ns._gearTabDrawGen or 0) then return end
    if ns._gearStorageDeferAwaiting or ns._gearStorageYieldCo then return end
    if (mf._gearDeferChainActive == true) then return end
    local veil = mf._gearContentVeil
    if not veil or veil._veilGen ~= gen then return end
    local shownAt = veil._gearVeilShownAt
    local now = GetTime()
    if shownAt and (now - shownAt) < GEAR_CONTENT_VEIL_MIN_DISPLAY_SEC then
        if mf._gearVeilMinDismissTimer and mf._gearVeilMinDismissTimer.Cancel then
            mf._gearVeilMinDismissTimer:Cancel()
        end
        local delay = GEAR_CONTENT_VEIL_MIN_DISPLAY_SEC - (now - shownAt)
        mf._gearVeilMinDismissTimer = C_Timer.NewTimer(delay, function()
            mf._gearVeilMinDismissTimer = nil
            TryDismissGearContentVeil(mf, gen)
        end)
        return
    end
    if mf._gearVeilMinDismissTimer and mf._gearVeilMinDismissTimer.Cancel then
        mf._gearVeilMinDismissTimer:Cancel()
    end
    mf._gearVeilMinDismissTimer = nil
    DismissGearContentVeil(mf, gen)
end

--- Live selection can be nil for a frame (GUID migration, dropdown refresh). Defer must not treat that as
--- "selection != pending" or applyStorageScanUI would skip with nil ~= capCanon and strand "Scanning…".
---@param mf Frame|nil
---@param pendingCapCanon string|nil
---@return string|nil
local function ResolveGearTabSelectionKeyForStorageScan(mf, pendingCapCanon)
    local sel = GetSelectedCharKey and GetSelectedCharKey() or nil
    if sel then
        return sel
    end
    local U = ns.Utilities
    local function toCanon(k)
        if not k then return nil end
        if U and U.GetCanonicalCharacterKey then
            return U:GetCanonicalCharacterKey(k) or k
        end
        return k
    end
    local capC = toCanon(pendingCapCanon)
    if mf and mf._gearPopulateCanonKey then
        local pC = toCanon(mf._gearPopulateCanonKey)
        if not capC or pC == capC then
            return mf._gearPopulateCanonKey
        end
    end
    if pendingCapCanon then
        return pendingCapCanon
    end
    return nil
end

--- Start yielded storage scan after paperdoll defer chain (never same frame as DressUpModel / row paint).
---@param mf Frame|nil
---@param paintGen number
local function TryStartPendingGearStorageScan(mf, paintGen)
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        WarbandNexus:GearStoragePanelDebug("TryStart skip (stash rec disabled)")
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        if mf then
            mf._gearPendingStorageScan = nil
        end
        return
    end
    if not mf then
        WarbandNexus:GearStoragePanelDebug("TryStart abort (mainFrame nil)")
        return
    end
    local pending = mf._gearPendingStorageScan
    if not pending or pending.paintGen ~= paintGen then
        if paintGen ~= (ns._gearTabDrawGen or 0) then
            return
        end
        -- Duplicate C_Timer(0): first TryStart cleared `pending` while a scan is still scheduled
        if ns._gearStorageYieldCo then
            WarbandNexus:GearStoragePanelDebug("TryStart wait (yield scan already running)")
            return
        end
        -- Same paint gen, defer still expected, but pending was consumed by another tick — re-queue once.
        if ns._gearStorageDeferAwaiting and mf._gearPopulateCanonKey
            and ns._gearStorageDeferAwaitCanon == mf._gearPopulateCanonKey then
            mf._gearPendingStorageScan = {
                canon = ns._gearStorageDeferAwaitCanon,
                paintGen = paintGen,
            }
            return TryStartPendingGearStorageScan(mf, paintGen)
        end
        WarbandNexus:GearStoragePanelDebug("TryStart abort (no pending, no yield, defer/populate mismatch — possible orphan defer)")
        return
    end
    local capCanon = pending.canon
    mf._gearPendingStorageScan = nil
    WarbandNexus:GearStorageTrace("TryStart pending storage scan canon=" .. tostring(capCanon) .. " paintGen=" .. tostring(paintGen))

    if paintGen ~= (ns._gearTabDrawGen or 0) then
        WarbandNexus:GearStoragePanelDebug("TryStart cancel (stale paintGen vs _gearTabDrawGen); clearing defer")
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        TryDismissGearContentVeil(mf, paintGen)
        return
    end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
        WarbandNexus:GearStoragePanelDebug("TryStart cancel (not on gear tab); clearing defer")
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        TryDismissGearContentVeil(mf, paintGen)
        return
    end

    local Usel = ns.Utilities
    local function gearStorageCanonKey(k)
        if not k then return nil end
        return (Usel and Usel.GetCanonicalCharacterKey) and Usel:GetCanonicalCharacterKey(k) or k
    end
    local capCanonCmp = gearStorageCanonKey(capCanon)
    local selKey = ResolveGearTabSelectionKeyForStorageScan(mf, capCanon)
    local selCanon = gearStorageCanonKey(selKey)
    -- Pending canon can lag selection by a frame (dropdown → refresh). Dropping defer here used to orphan
    -- the in-scroll "Scanning storage…" line; re-queue for the current selection instead.
    if capCanonCmp and selCanon and selCanon ~= capCanonCmp then
        WarbandNexus:GearStorageTrace("TryStart requeue (selection != pending cap) cap=" .. tostring(capCanonCmp) .. " sel=" .. tostring(selCanon))
        if selCanon then
            mf._gearPendingStorageScan = {
                canon = selCanon,
                paintGen = paintGen,
            }
            ns._gearStorageDeferAwaiting = true
            ns._gearStorageDeferAwaitCanon = selCanon
            C_Timer.After(0, function()
                if paintGen ~= (ns._gearTabDrawGen or 0) then return end
                TryStartPendingGearStorageScan(mf, paintGen)
            end)
        else
            ns._gearStorageDeferAwaiting = false
            ns._gearStorageDeferAwaitCanon = nil
            TryDismissGearContentVeil(mf, paintGen)
        end
        return
    end

    local P2 = ns.Profiler
    local function applyStorageScanUI()
        if paintGen ~= (ns._gearTabDrawGen or 0) then return end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
        selKey = ResolveGearTabSelectionKeyForStorageScan(mf, capCanon)
        selCanon = gearStorageCanonKey(selKey)
        if capCanonCmp and selCanon and selCanon ~= capCanonCmp then
            -- Scan finished for a character we are no longer viewing; do not touch defer (new paint owns it).
            WarbandNexus:GearStorageTrace("apply skip (selection changed) cap=" .. tostring(capCanonCmp) .. " sel=" .. tostring(selCanon))
            return
        end

        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil

        local ok
        ns._gearStorageAllowEquipSigInvBypass = true
        if P2 and P2.enabled and P2.Wrap and P2.SliceLabel and WarbandNexus.RedrawGearStorageRecommendationsOnly then
            ok = P2:Wrap(P2:SliceLabel(P2.CAT.UI, "Gear_StorageRec_refresh"), WarbandNexus.RedrawGearStorageRecommendationsOnly, WarbandNexus, capCanon, paintGen, true)
        elseif WarbandNexus.RedrawGearStorageRecommendationsOnly then
            ok = WarbandNexus:RedrawGearStorageRecommendationsOnly(capCanon, paintGen, true)
        end
        ns._gearStorageAllowEquipSigInvBypass = false
        -- Storage scan finished after paperdoll defer; allow veil dismiss even if slot-inspect chain left the flag set.
        if mf then
            mf._gearDeferChainActive = false
        end
        TryDismissGearContentVeil(mf, paintGen)
        WarbandNexus:GearStorageTrace("apply RedrawStorageRec ok=" .. tostring(ok) .. " canon=" .. tostring(capCanon))
        WarbandNexus:GearStoragePanelDebug(("applyStorageScanUI Redraw ok=%s canon=%s"):format(tostring(ok), tostring(capCanon)))
        if ok then return end
        if P2 and P2.enabled and P2.Wrap and P2.SliceLabel then
            P2:Wrap(P2:SliceLabel(P2.CAT.UI, "Gear_StorageRec_fallbackPopulate"), function()
                WarbandNexus:PopulateContent()
                local mfPop = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                if mfPop and mfPop.CancelPendingPopulateDebounce then
                    mfPop:CancelPendingPopulateDebounce()
                end
            end)
        else
            WarbandNexus:PopulateContent()
            local mfPop = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mfPop and mfPop.CancelPendingPopulateDebounce then
                mfPop:CancelPendingPopulateDebounce()
            end
        end
    end

    local function beginYieldedStorageFind()
        WarbandNexus:GearStorageTrace("beginYielded canon=" .. tostring(capCanon) .. " paintGen=" .. tostring(paintGen))
        WarbandNexus:GearStoragePanelDebug(("TryStart beginYielded canon=%s paintGen=%s"):format(tostring(capCanon), tostring(paintGen)))
        if WarbandNexus.RunFindGearStorageUpgradesYielded then
            WarbandNexus:RunFindGearStorageUpgradesYielded(capCanon, paintGen, function()
                if WarbandNexus.OnGearStorageYieldedScanComplete then
                    WarbandNexus:OnGearStorageYieldedScanComplete(capCanon, paintGen, function()
                        C_Timer.After(0, applyStorageScanUI)
                    end)
                else
                    C_Timer.After(0, applyStorageScanUI)
                end
            end)
        elseif WarbandNexus.FindGearStorageUpgrades then
            WarbandNexus:FindGearStorageUpgrades(capCanon)
            if WarbandNexus.OnGearStorageYieldedScanComplete then
                WarbandNexus:OnGearStorageYieldedScanComplete(capCanon, paintGen, function()
                    C_Timer.After(0, applyStorageScanUI)
                end)
            else
                C_Timer.After(0, applyStorageScanUI)
            end
        else
            applyStorageScanUI()
        end
    end

    local P = ns.Profiler
    if P and P.enabled and P.Wrap and P.SliceLabel then
        P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_FindStorageUpgrades_deferred"), beginYieldedStorageFind)
    else
        beginYieldedStorageFind()
    end
end

-- Single GetChildren() vararg pack for storage rec scroll (avoid fresh {} in RedrawGearStorageRecommendationsOnly).
local _gearRecChildScratch = {}
local function PackGearRecChildren(recContent, ...)
    wipe(_gearRecChildScratch)
    local n = select("#", ...)
    for i = 1, n do
        _gearRecChildScratch[i] = select(i, ...)
    end
    return n
end

local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleasePooledRowsInSubtree = ns.UI_ReleasePooledRowsInSubtree

-- GetGearPopulateSignature: reuse string-building tables (see _gearPopulateSigDepth for reentrancy).
local _gearSigParts = {}
local _gearSigCurBlob = {}
local _gearSigUpPieces = {}
local _gearPopulateSigDepth = 0

local WEAPON_ENCHANT_EQUIP_LOCS = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON = true,
}

---Midnight primary-enchant expectation by slot + equip location.
---@param slotID number
---@param slotData table|nil
---@return boolean
local function IsPrimaryEnchantExpected(slotID, slotData)
    local enchantableSlots = ns.Constants and ns.Constants.GEAR_ENCHANTABLE_SLOTS
    if not (enchantableSlots and enchantableSlots[slotID]) then
        return false
    end
    if slotID == 16 or slotID == 17 then
        local equipLoc = slotData and slotData.equipLoc or ""
        return WEAPON_ENCHANT_EQUIP_LOCS[equipLoc] == true
    end
    return true
end

--- English track names from Blizzard tooltip/API → locale (e.g. zhCN PVE_CREST_*).
local function LocalizeUpgradeTrackName(name)
    if not name or name == "" then return name end
    if issecretvalue and issecretvalue(name) then return name end
    local L = ns.L
    if not L then return name end
    local trimmed = name:match("^%s*(.-)%s*$") or name
    local key = ({
        Adventurer = "PVE_CREST_ADV",
        Veteran = "PVE_CREST_VET",
        Champion = "PVE_CREST_CHAMP",
        Hero = "PVE_CREST_HERO",
        Myth = "PVE_CREST_MYTH",
        Explorer = "PVE_CREST_EXPLORER",
        Crafted = "GEAR_TRACK_CRAFTED_FALLBACK",
    })[trimmed]
    if key and L[key] then return L[key] end
    return name
end

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

local function GetUpgradeTrackHex(englishName)
    if ns.UI_GetUpgradeTrackTierHex then
        return ns.UI_GetUpgradeTrackTierHex(englishName)
    end
    return nil
end

local function FormatFloat2(value)
    if not value then return nil end
    local n = tonumber(value)
    if not n then return nil end
    return format("%.2f", n)
end

-- ============================================================================
-- CONSTANTS / LAYOUT  (addon theme: ns.UI_LAYOUT when available)
-- ============================================================================

local function GetLayout() return ns.UI_LAYOUT or {} end
local UI_LAYOUT      = ns.UI_LAYOUT or {}
local SIDE_MARGIN    = UI_LAYOUT.SIDE_MARGIN or 16
local TOP_MARGIN     = UI_LAYOUT.TOP_MARGIN or 12
local HEADER_H       = UI_LAYOUT.HEADER_HEIGHT or 32
-- Character strip + dropdown: match header controls elsewhere (SharedWidgets sort dropdown = 32px row, 26px menu entries).
local GEAR_CHAR_SELECTOR_WIDTH = 292
local GEAR_CHAR_SELECTOR_HEIGHT = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or HEADER_H or 32
local GEAR_CHAR_DROPDOWN_ENTRY_H = (ns.UI_LAYOUT and ns.UI_LAYOUT.DROPDOWN_MENU_ROW_HEIGHT) or (ns.UI_LAYOUT and ns.UI_LAYOUT.ROW_HEIGHT) or 26
local GEAR_HIDE_FILTER_BUTTON_W = 84

-- Paper doll: sol panel | orta panel | sağ panel | alt panel (fixed widths); %10 büyütme
-- [[WN_GEAR_PAPERDOLL_MOVED]]
-- Paperdoll chunk lives in GearUI_Paperdoll.lua (Lua 200-local limit)
local GEAR_STORAGE_RECOMMENDATIONS_ENABLED = true
local GEAR_STORAGE_REC_TABLE_HDR = 30

---@return boolean
function WarbandNexus:IsGearStorageRecommendationsEnabled()
    return GEAR_STORAGE_RECOMMENDATIONS_ENABLED == true
end

local function GetGearTabMinCardInnerW()
    return ns.GearUI_GetGearTabMinCardInnerW()
end

local MIN_GEAR_CARD_W = 2 * (SIDE_MARGIN or 16) + 2 * 12 + GetGearTabMinCardInnerW()
ns.MIN_GEAR_CARD_W = MIN_GEAR_CARD_W

local GEAR_PAPERDOLL_REFRESH_SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
-- [[/WN_GEAR_PAPERDOLL_MOVED]]

-- ============================================================================
-- SESSION STATE  (selected character; persists within session)
-- ============================================================================

local selectedCharKey = nil  -- nil = auto-select current player

local function GetSelectedCharKey()
    if selectedCharKey then return selectedCharKey end
    local U = ns.Utilities
    if not U then return nil end
    local store = (ns.CharacterService and WarbandNexus and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(WarbandNexus))
        or (U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus))
        or (U.GetCharacterKey and U:GetCharacterKey())
    if store and U.GetCanonicalCharacterKey then
        return U:GetCanonicalCharacterKey(store) or store
    end
    return store
end

local function GetLowLevelHideThreshold(profile)
    if not profile then return 0 end
    local threshold = tonumber(profile.hideLowLevelThreshold) or 0
    if threshold >= 90 then return 90 end
    if threshold >= 80 then return 80 end
    -- Backward compatibility for older boolean setting.
    if profile.hideLowLevelCharacters == true then
        return 80
    end
    return 0
end

local function GetLowLevelHideCycleNext(current)
    if current == 0 then return 80 end
    if current == 80 then return 90 end
    return 0
end

local function GetLowLevelHideLabel(threshold)
    if threshold == 90 then return GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") end
    if threshold == 80 then return GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

local function ApplyLowLevelHideThreshold(threshold)
    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not profile then return end
    local nextThreshold = tonumber(threshold) or 0
    if nextThreshold ~= 80 and nextThreshold ~= 90 then
        nextThreshold = 0
    end
    profile.hideLowLevelThreshold = nextThreshold
    profile.hideLowLevelCharacters = (nextThreshold >= 80)
    local events = ns.Constants and ns.Constants.EVENTS
    if WarbandNexus and WarbandNexus.SendMessage and events and events.CHARACTER_TRACKING_CHANGED then
        WarbandNexus:SendMessage(events.CHARACTER_TRACKING_CHANGED, {
            source = "HideFilter",
            threshold = nextThreshold,
        })
    end
end

-- Gear event refresh is centralized in UI.lua SchedulePopulateContent
-- (WN_GEAR_UPDATED, WN_ITEMS_UPDATED, WN_CHARACTER_UPDATED, WN_CURRENCY_UPDATED).

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Get tracked characters honoring user prefs:
---   * `db.profile.hideLowLevelThreshold` filters out chars below level 80/90.
---   * `db.profile.characterOrder` (favorites + regular arrays) drives manual order;
---     unranked chars fall back to lastSeen DESC. Mirrors PvE/Characters tab order.
local function GetTrackedCharacters()
    local chars = {}
    local db = WarbandNexus.db and WarbandNexus.db.global
    if not db or not db.characters then return chars end
    local profile = WarbandNexus.db and WarbandNexus.db.profile or {}
    local minLevel = GetLowLevelHideThreshold(profile)
    for charKey, data in pairs(db.characters) do
        local lvl = tonumber(data.level) or 0
        if data.isTracked and (minLevel == 0 or lvl >= minLevel) then
            chars[#chars + 1] = { key = charKey, data = data }
        end
    end

    -- Manual order index from db.profile.characterOrder.{favorites, regular}.
    local rankOf, nextRank = {}, 1
    local order = profile.characterOrder
    if order then
        local lists = { order.favorites or {}, order.regular or {} }
        for li = 1, #lists do
            local list = lists[li]
            for i = 1, #list do
                local k = list[i]
                if rankOf[k] == nil then
                    rankOf[k] = nextRank
                    nextRank = nextRank + 1
                end
            end
        end
    end

    table.sort(chars, function(a, b)
        local ra, rb = rankOf[a.key], rankOf[b.key]
        if ra and rb then return ra < rb end
        if ra and not rb then return true end
        if rb and not ra then return false end
        return (a.data.lastSeen or 0) > (b.data.lastSeen or 0)
    end)
    return chars
end

--- Format item level with quality color (real data only; empty slot = empty string).
local function ColoredIlvl(ilvl, quality)
    if not ilvl or ilvl == 0 then return "" end
    local hex = GetQualityHex and GetQualityHex(quality or 0) or "ffffff"
    return format("|cff%s%d|r", hex, ilvl)
end

---@param linkOrId string|number itemLink or itemID
---@return number|string|nil texture (fileID or path)
local function GetItemIconSafe(linkOrId)
    if not linkOrId then return nil end
    local ok, result = pcall(function()
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(linkOrId)
            if icon and icon ~= 0 and icon ~= "" then return icon end
        end
        local itemId = type(linkOrId) == "number" and linkOrId or nil
        if not itemId and type(linkOrId) == "string" then
            if issecretvalue and issecretvalue(linkOrId) then
                itemId = nil
            else
                itemId = tonumber(linkOrId:match("item:(%d+)"))
            end
        end
        if type(linkOrId) == "string" and C_Item and C_Item.GetItemInfo and not (issecretvalue and issecretvalue(linkOrId)) then
            -- Instant path can miss icons for freshly equipped / bonus-heavy links; GetItemInfo resolves texture.
            local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(linkOrId)
            if tex and tex ~= 0 and tex ~= "" then return tex end
        end
        if not itemId then return nil end
        -- GetItemInfoInstant returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        if icon and icon ~= 0 and icon ~= "" then return icon end
        if C_Item and C_Item.GetItemInfo then
            local _, _, _, _, _, _, _, _, _, tex2 = C_Item.GetItemInfo(itemId)
            if tex2 and tex2 ~= 0 and tex2 ~= "" then return tex2 end
        end
        return nil
    end)
    return (ok and result) or nil
end

-- ============================================================================
-- CRAFTED ITEM RECRAFT RANGE
-- ============================================================================

--- Calculate achievable ilvl range for a crafted item based on player's crest inventory.
--- Crafted items can be recrafted with crests to jump to higher ilvl tiers.
--- Each tier has its own crest type and cost (e.g. Myth = 80 crests, Hero = 60).
--- Also returns the next unaffordable tier info so UI can show what's needed.
---@param upInfo table slot upgrade info with isCrafted=true
---@param currencyAmounts table map currencyID → amount
---@return table|nil { minIlvl, maxIlvl, bestCrestName, bestCrestCost, nextTierName, nextTierCost, nextTierHave, nextTierMaxIlvl } or nil if no crests
local function GetCraftedIlvlRange(upInfo, currencyAmounts)
    if not upInfo or not upInfo.isCrafted then return nil end
    local currentIlvl = upInfo.currentIlvl or 0
    local tiers = ns.CRAFTED_CREST_TIERS
    if not tiers or not currencyAmounts then return nil end

    local bestMaxIlvl = currentIlvl
    local bestCrestName = nil
    local bestCrestCost = 0
    local nextTierName, nextTierCost, nextTierHave, nextTierMaxIlvl = nil, nil, nil, nil

    for i = 1, #tiers do
        local tier = tiers[i]
        local have = currencyAmounts[tier.crestID] or 0
        if have >= tier.cost and tier.maxIlvl > currentIlvl then
            bestMaxIlvl = tier.maxIlvl
            bestCrestName = tier.name
            bestCrestCost = tier.cost
            break
        elseif tier.maxIlvl > currentIlvl and not nextTierName then
            nextTierName = tier.name
            nextTierCost = tier.cost
            nextTierHave = have
            nextTierMaxIlvl = tier.maxIlvl
        end
    end

    if bestMaxIlvl <= currentIlvl then return nil end

    return {
        minIlvl = currentIlvl,
        maxIlvl = bestMaxIlvl,
        bestCrestName = bestCrestName,
        bestCrestCost = bestCrestCost,
        nextTierName = nextTierName,
        nextTierCost = nextTierCost,
        nextTierHave = nextTierHave,
        nextTierMaxIlvl = nextTierMaxIlvl,
    }
end

--- Hesaplama matematiği (upgrade affordability):
--- - Her tier 20 crest + gold. Watermark: o slotta daha önce ulaşılan max ilvl; o ilvl'e kadar tier'lar "gold only".
--- - Döngü: currTier+1 .. maxTier. Her adımda: ilvl <= watermark ise sadece gold düş; değilse 20 crest + gold düş.
--- - haveCrests / 20 = en fazla crest'li upgrade sayısı değil; tier-by-tier düşüyoruz (3/6→4/6 bir crest, 4/6→5/6 bir crest).
--- - Sonuç: totalAffordable = kaç tier atlanabiliyor, goldOnlyCount = bunlardan kaçı crest gerektirmiyor.
---
--- Calculate affordable upgrades tier-by-tier, accounting for watermark (gold-only) levels.
---@param upInfo table slot upgrade info from GetPersistedUpgradeInfo
---@param currencyAmounts table map currencyID → amount (0 = gold in gold units)
---@return number totalAffordable how many upgrades the player can afford
---@return number goldOnlyCount how many of those are gold-only (below watermark)
local function CalculateAffordableUpgrades(upInfo, currencyAmounts)
    if not upInfo or not upInfo.canUpgrade then return 0, 0 end

    local currTier = upInfo.currUpgrade or 0
    local maxTier = upInfo.maxUpgrade or 0
    if currTier >= maxTier then return 0, 0 end

    local trackName = upInfo.trackName
    local TRACK_ILVLS = ns.TRACK_ILVLS
    local tiers = TRACK_ILVLS and TRACK_ILVLS[trackName]
    if not tiers then return 0, 0 end

    local wmIlvl = upInfo.watermarkIlvl or 0
    local goldPerUpgrade = upInfo.moneyCost or (ns.UPGRADE_GOLD_PER_LEVEL_COPPER or 100000)
    local crestPerUpgrade = upInfo.crestCost or (ns.UPGRADE_CREST_PER_LEVEL or 20)
    local currencyID = upInfo.currencyID or 0

    local haveGoldCopper = ((currencyAmounts and currencyAmounts[0]) or 0) * 10000
    local haveCrests = (currencyAmounts and currencyAmounts[currencyID]) or 0

    local totalAffordable = 0
    local goldOnlyCount = 0

    for nextTier = currTier + 1, maxTier do
        local nextIlvl = tiers[nextTier]
        if not nextIlvl then break end

        local isGoldOnly = (nextIlvl <= wmIlvl)

        if haveGoldCopper < goldPerUpgrade then break end

        if not isGoldOnly then
            if haveCrests < crestPerUpgrade then break end
            haveCrests = haveCrests - crestPerUpgrade
        end

        haveGoldCopper = haveGoldCopper - goldPerUpgrade
        totalAffordable = totalAffordable + 1
        if isGoldOnly then
            goldOnlyCount = goldOnlyCount + 1
        end
    end

    return totalAffordable, goldOnlyCount
end

--- Check if the player can afford at least one upgrade for this slot.
---@param upInfo table slot upgrade info from GetPersistedUpgradeInfo
---@param currencyAmounts table map currencyID → amount
---@return boolean
local function CanAffordNextUpgrade(upInfo, currencyAmounts)
    if not upInfo or not upInfo.canUpgrade then return false end
    if upInfo.isCrafted then
        local range = GetCraftedIlvlRange(upInfo, currencyAmounts)
        return range and range.maxIlvl > (upInfo.currentIlvl or 0)
    end
    local count = CalculateAffordableUpgrades(upInfo, currencyAmounts)
    return count > 0
end

--- True when this slot should show the upgrade arrow (next tier / recraft available), regardless of crest affordability.
local function GearUpgradeInfoHasPath(upInfo)
    return upInfo and upInfo.canUpgrade == true and not upInfo.notUpgradeable
end

--- Get the class color hex for a classFile string (e.g. "SHAMAN").
local function GetClassHex(classFile)
    if not classFile then return "ffffff" end
    local classColors = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if classColors then
        return format("%02x%02x%02x",
            math.floor(classColors.r * 255),
            math.floor(classColors.g * 255),
            math.floor(classColors.b * 255))
    end
    -- Fallback from Constants
    local Constants = ns.Constants
    if Constants and Constants.CLASS_COLORS and Constants.CLASS_COLORS[classFile] then
        local s = Constants.CLASS_COLORS[classFile]
        return s:gsub("|cff", "")
    end
    return "ffffff"
end

--- Color character name in storage source line; warband stays plain.
local function ColoredStorageSourceName(classFile, name)
    if not name or name == "" then return name end
    if issecretvalue and issecretvalue(name) then return "" end
    return "|cff" .. GetClassHex(classFile) .. name .. "|r"
end

local function FormatStorageSourceDisplay(source, sourceClassFile, viewerClassFile)
    if not source then return "" end
    if issecretvalue and issecretvalue(source) then return "" end
    if source == "Warband Bank" then
        return source
    end
    if source == "Guild Bank" or (type(source) == "string" and source:find("^Guild Bank", 1, true)) then
        return source
    end
    if source == "Your Bag" or source == "Your Bank" then
        return ColoredStorageSourceName(viewerClassFile, source)
    end
    local paren = source:find(" %(")
    if paren and paren > 1 then
        local namePart = source:sub(1, paren - 1)
        local rest = source:sub(paren)
        return ColoredStorageSourceName(sourceClassFile, namePart) .. rest
    end
    return ColoredStorageSourceName(sourceClassFile, source)
end

--- Tooltip spec: prefer saved specID; else first spec for class (offline / stale DB still get correct primary stat).
local function GetGearTabTooltipSpecID(charData)
    if not charData then return nil end
    local sid = tonumber(charData.specID)
    if sid and sid > 0 then return sid end
    local cid = tonumber(charData.classID)
    if not cid or cid < 1 then
        local cf = charData.classFile
        if type(cf) == "string" and cf ~= "" then
            local uc = strupper or string.upper
            local map = ns.Constants and ns.Constants.CLASS_FILE_TO_CLASS_ID
            cid = map and map[uc(cf)]
        end
    end
    if cid and cid > 0 and GetSpecializationInfoForClassID then
        local specID = select(1, GetSpecializationInfoForClassID(cid, 1))
        specID = tonumber(specID)
        if specID and specID > 0 then return specID end
    end
    return nil
end

--- { level, specID } for TooltipService when showing Gear tab items for this character.
local function BuildGearTabItemTooltipContext(charData)
    if not charData then return nil end
    local lvl = tonumber(charData.level)
    if not lvl or lvl < 1 then return nil end
    local specID = GetGearTabTooltipSpecID(charData)
    if not specID or specID < 1 then return nil end
    return { level = lvl, specID = specID }
end

--- FontStrings parented to `recContent` are not returned by `GetChildren()`; clear the single status line we own.
local function ClearGearRecStatusOverlay(recContent)
    if not recContent then return end
    local fs = recContent._gearStorageStatusFont
    if fs then
        recContent._gearStorageStatusFont = nil
        if fs.Hide then fs:Hide() end
        if fs.SetParent then fs:SetParent(nil) end
    end
end

--- Release pooled storage rows under the gear recommendations scroll child, then recycle non-pooled leftovers (empty states, legacy frames).
local function ClearGearRecScrollContent(recContent)
    if not recContent then return end
    ClearGearRecStatusOverlay(recContent)
    if ReleasePooledRowsInSubtree then
        ReleasePooledRowsInSubtree(recContent)
    end
    local bin = ns.UI_RecycleBin
    local nKids = PackGearRecChildren(recContent, recContent:GetChildren())
    for i = 1, nKids do
        local ch = _gearRecChildScratch[i]
        if ch then
            if ch.isPooled and ch.rowType == "storage" and ch._wnInFramePool then
                -- Idle pooled row: still parented here; do not move to recycle bin.
            else
                ch:Hide()
                if bin then ch:SetParent(bin) else ch:SetParent(nil) end
            end
        end
    end
end

--- Column layout: Slot | Gear (icon+name) | Recommend (ilvl delta) | Location (widest; long bank labels).
local function GetGearStorageRecColumnLayout(contentW)
    local pad = 8
    local gap = 6
    local inner = math.max(40, contentW - pad * 2)
    -- Slot: fit "Main Hand" / localized long labels without ellipsis.
    local slotW = math.min(108, math.max(86, math.floor(inner * 0.20 + 0.5)))
    local recommendW = math.min(128, math.max(76, math.floor(inner * 0.20 + 0.5)))
    local locationW = math.min(168, math.max(88, math.floor(inner * 0.28 + 0.5)))
    local gearW = inner - slotW - recommendW - locationW - 3 * gap
    local rw, lw = recommendW, locationW
    local gw = gearW
    if gw < 72 then
        local deficit = 72 - gw
        rw = math.max(58, rw - math.floor(deficit * 0.40))
        lw = math.max(80, lw - math.ceil(deficit * 0.60))
        gw = inner - slotW - rw - lw - 3 * gap
    end
    local iconSz = math.min(26, math.max(20, math.floor(24 * 0.92)))
    local xSlot = pad
    local xGear = xSlot + slotW + gap
    local xRecommend = xGear + gw + gap
    local xLocation = xRecommend + rw + gap
    return {
        pad = pad,
        gap = gap,
        iconSz = iconSz,
        slotW = slotW,
        gearW = gw,
        recommendW = rw,
        locationW = lw,
        xSlot = xSlot,
        xGear = xGear,
        xRecommend = xRecommend,
        xLocation = xLocation,
    }
end

local function GetGearStorageItemDisplayName(itemLink, itemID)
    local nm
    if itemLink and (not (issecretvalue and issecretvalue(itemLink))) and C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(function()
            return (C_Item.GetItemInfo(itemLink))
        end)
        if ok and type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
            nm = n
        end
    end
    if not nm and itemID and C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(function()
            return (C_Item.GetItemInfo(itemID))
        end)
        if ok and type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
            nm = n
        end
    end
    return nm
end

--- Plain item name for colored display (API name can include |c sequences in some builds).
local function StripItemNameColorCodes(text)
    if not text or text == "" then return "" end
    if issecretvalue and issecretvalue(text) then return "" end
    return tostring(text):gsub("|c%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
end

--- Resolve quality for storage recommendation row.
--- Midnight: prefer C_Item.GetItemQualityByID; optional GetItemQuality(itemLink) per https://warcraft.wiki.gg/wiki/API_C_Item.GetItemQuality (pcall if signature differs).
local function GetStorageRecRowItemQuality(rowData)
    if not rowData then return 1 end
    local q = tonumber(rowData.quality)
    if q and q >= 0 and q <= 8 then return q end
    local link = rowData.itemLink
    if link and type(link) == "string" and link ~= "" and not (issecretvalue and issecretvalue(link)) then
        if C_Item and C_Item.GetItemQuality then
            local ok, qq = pcall(C_Item.GetItemQuality, link)
            if ok and type(qq) == "number" and qq >= 0 then return qq end
        end
    end
    local id = tonumber(rowData.itemID)
    if id and C_Item and C_Item.GetItemQualityByID then
        local ok2, qq2 = pcall(C_Item.GetItemQualityByID, id)
        if ok2 and type(qq2) == "number" and qq2 >= 0 then return qq2 end
    end
    return 1
end

--- Column header for the gear-tab storage recommendations table.
local function PaintGearStorageRecColumnHeader(parent, contentW)
    if not parent or not FontManager then return end
    local lay = GetGearStorageRecColumnLayout(contentW)
    local hdr = GearFact:CreateContainer(parent, contentW, GEAR_STORAGE_REC_TABLE_HDR, false)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local rule = hdr:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", lay.pad, 2)
    rule:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -lay.pad, 2)
    rule:SetColorTexture(0.35, 0.38, 0.44, 0.45)
    local hdrColor = { 1, 1, 1 }
    local function colFs(text, leftX, width, justify)
        local fs = FontManager:CreateFontString(hdr, GFR("gearStorageHdr"), "OVERLAY")
        fs:SetPoint("LEFT", hdr, "LEFT", leftX, 1)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text)
        fs:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3])
        return fs
    end
    colFs(GetLocalizedText("GEAR_STORAGE_TABLE_HDR_SLOT", "Slot"), lay.xSlot, lay.slotW, "LEFT")
    colFs(GetLocalizedText("GEAR_STORAGE_TABLE_HDR_GEAR", "Gear"), lay.xGear, lay.gearW, "LEFT")
    do
        local fs = FontManager:CreateFontString(hdr, GFR("gearStorageHdr"), "OVERLAY")
        fs:SetPoint("TOPLEFT", hdr, "TOPLEFT", lay.xRecommend, 1)
        fs:SetPoint("TOPRIGHT", hdr, "TOPLEFT", lay.xRecommend + lay.recommendW, 1)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        fs:SetText(GetLocalizedText("GEAR_STORAGE_TABLE_HDR_RECOMMEND", "Recommend"))
        fs:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3])
    end
    do
        local fs = FontManager:CreateFontString(hdr, GFR("gearStorageHdr"), "OVERLAY")
        fs:SetPoint("TOPLEFT", hdr, "TOPLEFT", lay.xLocation, 1)
        fs:SetPoint("TOPRIGHT", hdr, "TOPLEFT", lay.xLocation + lay.locationW, 1)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(GetLocalizedText("GEAR_STORAGE_TABLE_HDR_LOCATION", "Location"))
        fs:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3])
    end
end

--- Paint one storage-upgrade row (slot | gear | recommend | location).
local function PaintGearStorageRecommendationRow(line, index, rowH, contentW, rowData, itemTooltipContext, viewerClassFile)
    if not line then return end
    local parent = line:GetParent()
    if not parent then return end
    local lay = GetGearStorageRecColumnLayout(contentW)
    local innerH = math.max(1, rowH - 2)
    -- Stack every data row below the in-content column header (not only row 1), or row 2+ overlaps row 1.
    local yOff = -(index - 1) * rowH
    if parent._gearRecHasHeader then
        yOff = yOff - GEAR_STORAGE_REC_TABLE_HDR
    end
    line:SetSize(contentW, innerH)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
    line:EnableMouse(true)
    if ns.UI.Factory and ns.UI.Factory.ApplyRowBackground then
        ns.UI.Factory:ApplyRowBackground(line, index)
    end
    -- Factory even/odd colors are identical in UI_SPACING; use visible zebra on this dark panel.
    if line.bg then
        local a = (index % 2 == 0) and 0.07 or 0.04
        line.bg:SetColorTexture(0.10, 0.12, 0.16, a)
    end
    if line.qtyText then line.qtyText:Hide() end
    if line.nameText then line.nameText:Hide() end
    if line.locationText then line.locationText:Hide() end
    if line.arrowTex then line.arrowTex:Hide() end
    if line.currIlvlText then line.currIlvlText:Hide() end
    if line.targetIlvlText then line.targetIlvlText:Hide() end
    if line.deltaText then line.deltaText:Hide() end

    local slotText = line.slotText
    if not slotText and FontManager then
        slotText = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.slotText = slotText
    end
    if slotText then
        slotText:Show()
        slotText:SetPoint("LEFT", line, "LEFT", lay.xSlot, 0)
        slotText:SetWidth(lay.slotW)
        slotText:SetJustifyH("LEFT")
        slotText:SetWordWrap(false)
        slotText:SetText(rowData.slotName or "Slot")
        slotText:SetTextColor(0.92, 0.93, 0.98)
    end

    local cur = math.floor(tonumber(rowData.currentIlvl) or 0)
    local tgt = math.floor(tonumber(rowData.targetIlvl) or 0)
    local delta = tgt - cur
    local upgradeSummary = line.upgradeSummaryText
    if not upgradeSummary and FontManager then
        upgradeSummary = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.upgradeSummaryText = upgradeSummary
    end
    if upgradeSummary then
        upgradeSummary:Show()
        upgradeSummary:ClearAllPoints()
        upgradeSummary:SetPoint("TOPLEFT", line, "TOPLEFT", lay.xRecommend, 0)
        upgradeSummary:SetPoint("TOPRIGHT", line, "TOPLEFT", lay.xRecommend + lay.recommendW, 0)
        upgradeSummary:SetJustifyH("CENTER")
        upgradeSummary:SetWordWrap(false)
        local parts = {}
        parts[1] = "|cffb8bcc6"
        parts[2] = tostring(cur)
        parts[3] = "|r |cff66ee88>|r |cffc8ffd0"
        parts[4] = tostring(tgt)
        parts[5] = "|r"
        if delta > 0 then
            parts[6] = string.format(" |cff55dd77(+%d)|r", delta)
        end
        upgradeSummary:SetText(table.concat(parts))
    end

    local itemIcon = line.icon
    if not itemIcon then
        itemIcon = line:CreateTexture(nil, "ARTWORK")
        line.icon = itemIcon
    end
    itemIcon:Show()
    itemIcon:SetSize(lay.iconSz, lay.iconSz)
    itemIcon:SetPoint("LEFT", line, "LEFT", lay.xGear, 0)
    local icon = rowData.itemLink and GetItemIconSafe(rowData.itemLink) or GetItemIconSafe(rowData.itemID)
    itemIcon:SetTexture(icon or 134400)
    itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local itemNameFs = line.itemNameText
    if not itemNameFs and FontManager then
        itemNameFs = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.itemNameText = itemNameFs
    end
    if itemNameFs then
        itemNameFs:Show()
        itemNameFs:SetPoint("LEFT", itemIcon, "RIGHT", lay.gap, 0)
        itemNameFs:SetPoint("RIGHT", line, "LEFT", lay.xRecommend - 2, 0)
        itemNameFs:SetJustifyH("LEFT")
        itemNameFs:SetWordWrap(false)
        local dispRaw = GetGearStorageItemDisplayName(rowData.itemLink, rowData.itemID)
        if not dispRaw or dispRaw == "" then
            dispRaw = "#" .. tostring(rowData.itemID or 0)
        end
        local dispPlain = StripItemNameColorCodes(dispRaw)
        local iq = GetStorageRecRowItemQuality(rowData)
        local qhex = GetQualityHex and GetQualityHex(iq) or "ffffff"
        itemNameFs:SetText(format("|cff%s%s|r", qhex, dispPlain))
        itemNameFs:SetTextColor(1, 1, 1)
    end

    local sourceText = line.sourceText
    if not sourceText and FontManager then
        sourceText = FontManager:CreateFontString(line, GFR("gearStorageSource"), "OVERLAY")
        line.sourceText = sourceText
    end
    if sourceText then
        sourceText:ClearAllPoints()
        sourceText:SetPoint("TOPLEFT", line, "TOPLEFT", lay.xLocation, 0)
        sourceText:SetPoint("TOPRIGHT", line, "TOPLEFT", lay.xLocation + lay.locationW, 0)
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        if sourceText.SetMaxLines then sourceText:SetMaxLines(2) end
        local srcDisplay = FormatStorageSourceDisplay(rowData.source or "", rowData.sourceClassFile, viewerClassFile)
        sourceText:SetText(srcDisplay ~= "" and srcDisplay or (rowData.source or ""))
        sourceText:SetTextColor(0.72, 0.76, 0.84)
    end

    line:SetScript("OnEnter", function(self)
        if ShowTooltip then
            ShowTooltip(self, {
                type = "item",
                itemID = rowData.itemID,
                itemLink = rowData.itemLink,
                anchor = "ANCHOR_LEFT",
                itemTooltipContext = itemTooltipContext,
            })
        end
    end)
    line:SetScript("OnLeave", function()
        if HideTooltip then HideTooltip() end
    end)
end

local GEAR_STORAGE_ROWS_PER_FRAME = 5

---Paint storage recommendation rows across multiple frames (never bulk N rows on one spike).
local function PaintGearStorageRowsBatched(recContent, recScroll, rows, contentW, rowH, charData, drawGen, onComplete)
    if not recContent or not rows or #rows == 0 then
        if onComplete then onComplete() end
        return
    end
    if not AcquireStorageRow then
        if onComplete then onComplete() end
        return
    end
    ClearGearRecScrollContent(recContent)
    recContent._gearRecHasHeader = true
    PaintGearStorageRecColumnHeader(recContent, contentW)
    local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
    local viewerClass = charData and charData.classFile
    local idx = 1
    local function paintChunk()
        if drawGen and drawGen ~= (ns._gearTabDrawGen or 0) then return end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
        local last = math.min(idx + GEAR_STORAGE_ROWS_PER_FRAME - 1, #rows)
        for i = idx, last do
            local r = rows[i]
            local line = AcquireStorageRow(recContent, contentW, math.max(1, rowH - 2))
            if line then
                PaintGearStorageRecommendationRow(line, i, rowH, contentW, r, itemTooltipContext, viewerClass)
            end
        end
        idx = last + 1
        if idx <= #rows then
            C_Timer.After(0.012, paintChunk)
        else
            if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
            end
            if recScroll and recScroll.SetVerticalScroll then
                recScroll:SetVerticalScroll(0)
            end
            WarbandNexus:GearStoragePanelDebug(("PaintGearStorageRowsBatched DONE rows=%d (batched paint)"):format(#rows))
            if onComplete then onComplete() end
        end
    end
    paintChunk()
end

local function ShowGearStorageScanningInRecContent(recContent)
    if not recContent then return end
    local mfG = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfG then
        if mfG._gearStorageScanningMinPaintTimer and mfG._gearStorageScanningMinPaintTimer.Cancel then
            mfG._gearStorageScanningMinPaintTimer:Cancel()
        end
        mfG._gearStorageScanningMinPaintTimer = nil
    end
    ClearGearRecScrollContent(recContent)
    if not FontManager then return end
    recContent._gearRecForceNextPaint = true
    local scanFs = FontManager:CreateFontString(recContent, GFR("gearStorageEmpty"), "OVERLAY")
    recContent._gearStorageStatusFont = scanFs
    scanFs:SetAllPoints()
    scanFs:SetJustifyH("CENTER")
    scanFs:SetJustifyV("MIDDLE")
    scanFs:SetText(GearTabL("GEAR_STORAGE_SCANNING", "Scanning storage for upgrades..."))
    scanFs:SetTextColor(0.65, 0.68, 0.75)
    if mfG then
        mfG._gearStorageScanningShownAt = GetTime()
    end
end

---Yielded storage scan for UI redraw paths (never block the main thread with FindGearStorageUpgrades).
---@param canonKey string
---@param drawGen number
---@param onDone function|nil
function WarbandNexus:ScheduleGearStorageFindingsResolve(canonKey, drawGen, onDone)
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        if onDone then onDone() end
        return
    end
    if not canonKey then
        if onDone then onDone() end
        return
    end
    -- Same canon already scanning: chain this completion only. Do NOT nil `_gearStorageYieldCo` here —
    -- killing the active coroutine orphans TryStartPendingGearStorageScan's `onDone` (defer/veil never clear).
    if ns._gearStorageYieldCo and ns._gearStorageYieldFindCanon == canonKey then
        WarbandNexus:GearStorageTrace("ScheduleResolve queue (yield in flight) canon=" .. tostring(canonKey))
        WarbandNexus:GearStoragePanelDebug(("ScheduleResolve QUEUED onDone (yield in flight) canon=%s"):format(tostring(canonKey)))
        if type(onDone) == "function" then
            local q = ns._gearStorageResolveQueuedDones
            if not q then
                q = {}
                ns._gearStorageResolveQueuedDones = q
            end
            tinsert(q, onDone)
        end
        return
    end
    WarbandNexus:GearStorageTrace("ScheduleResolve begin canon=" .. tostring(canonKey) .. " drawGen=" .. tostring(drawGen))
    WarbandNexus:GearStoragePanelDebug(("ScheduleResolve BEGIN canon=%s drawGen=%s yieldInFlight=%s")
        :format(tostring(canonKey), tostring(drawGen), tostring(ns._gearStorageYieldCo ~= nil)))
    local function beginScan()
        if self.RunFindGearStorageUpgradesYielded then
            self:RunFindGearStorageUpgradesYielded(canonKey, drawGen, function()
                local function drainQueued()
                    local queuedList = ns._gearStorageResolveQueuedDones
                    ns._gearStorageResolveQueuedDones = nil
                    if onDone then onDone() end
                    if queuedList then
                        for qi = 1, #queuedList do
                            local fn = queuedList[qi]
                            if type(fn) == "function" then
                                fn()
                            end
                        end
                    end
                end
                if self.OnGearStorageYieldedScanComplete then
                    self:OnGearStorageYieldedScanComplete(canonKey, drawGen, drainQueued)
                else
                    drainQueued()
                end
            end)
        elseif self.FindGearStorageUpgrades then
            self:FindGearStorageUpgrades(canonKey)
            if onDone then onDone() end
        elseif onDone then
            onDone()
        end
    end
    local P = ns.Profiler
    if P and P.enabled and P.Wrap and P.SliceLabel then
        P:Wrap(P:SliceLabel(P.CAT.SVC, "Gear_ScheduleStorageResolve"), beginScan)
    else
        beginScan()
    end
end

-- Enchant quality glyph: same anchor band as missing-enchant/gem alert (arrow ±9), profession atlases from SharedWidgets.
local GEAR_ENCHANT_QUALITY_SZ = 18

--- True if item hyperlink encodes a non-zero enchant id in the standard payload field.

local function BuildStorageRecommendationRows(findings, gearData)
    local rows = {}
    if not findings then return rows end
    local equippedSlots = gearData and gearData.slots or {}
    local seenItemLink = {}

    for slotID, candidates in pairs(findings) do
        local best = candidates and candidates[1]
        if best then
            local currentDisplay = (equippedSlots[slotID] and equippedSlots[slotID].itemLevel) or 0
            local target = best.itemLevel or 0
            -- Do not re-filter with live `currentDisplay` only: it can be newer than the scan snapshot
            -- (equip/scan race), which drops every row while findings still lists valid scan-time upgrades.
            local scanBase = tonumber(best.equippedIlvlAtFind) or currentDisplay
            if target > scanBase then
                local linkKey = best.itemLink or ("id:" .. tostring(best.itemID or 0))
                if seenItemLink[linkKey] then
                    -- Same item already shown (e.g. trinket for slot 13 and 14) — show once
                else
                    seenItemLink[linkKey] = true
                    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
                    rows[#rows + 1] = {
                        slotID = slotID,
                        slotName = (slotDef and slotDef.label) or GetLocalizedText("GEAR_SLOT_FALLBACK_FORMAT", "Slot %d"):format(tonumber(slotID) or 0),
                        currentIlvl = currentDisplay,
                        targetIlvl = target,
                        itemLink = best.itemLink,
                        itemID = best.itemID,
                        source = best.source or "",
                        sourceType = best.sourceType or "",
                        sourceClassFile = best.sourceClassFile,
                        delta = target - currentDisplay,
                        requiredLevel = best.requiredLevel,
                    }
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.delta ~= b.delta then
            return a.delta > b.delta
        end
        return a.slotID < b.slotID
    end)
    return rows
end

--- After deferred storage scan: repaint only the recommendations scroll (same-frame gen + canon guards).
---@param expectedCanonKey string
---@param expectedDrawGen number
---@param trustEquipSigWhenInvMiss boolean|nil When true, after a strict cache miss try canon+equipSig match (invEpoch must match unless ns._gearStorageAllowEquipSigInvBypass — set only for one post-yield redraw in DrawGearTab).
---@return boolean ok true when the scroll was repainted (caller skips full PopulateContent).
function WarbandNexus:RedrawGearStorageRecommendationsOnly(expectedCanonKey, expectedDrawGen, trustEquipSigWhenInvMiss)
    WarbandNexus:GearStoragePanelDebug(("Redraw ENTER want=%s gen=%s trustInvBypassPath=%s"):format(
        tostring(expectedCanonKey), tostring(expectedDrawGen), tostring(trustEquipSigWhenInvMiss == true)))
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        WarbandNexus:GearStoragePanelDebug("Redraw EXIT false (stash rec disabled)")
        return false
    end
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then
            WarbandNexus:GearStoragePanelDebug("Redraw EXIT false (no FontManager)")
            return false
        end
    end
    local mf = self.UI and self.UI.mainFrame
    if not mf then
        WarbandNexus:GearStoragePanelDebug("Redraw EXIT false (no mainFrame)")
        return false
    end
    if expectedDrawGen ~= (ns._gearTabDrawGen or 0) then
        WarbandNexus:GearStoragePanelDebug(("Redraw EXIT false (stale drawGen exp=%s cur=%s)"):format(
            tostring(expectedDrawGen), tostring(ns._gearTabDrawGen or 0)))
        return false
    end

    local host = mf._gearStorageRecHost
    if not host or host.drawGen ~= expectedDrawGen then
        WarbandNexus:GearStoragePanelDebug(("Redraw EXIT false (no _gearStorageRecHost or host.drawGen mismatch hostGen=%s expGen=%s)"):format(
            tostring(host and host.drawGen), tostring(expectedDrawGen)))
        return false
    end
    local hostCanon = host.canonKey
    local wantCanon = expectedCanonKey
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        hostCanon = U:GetCanonicalCharacterKey(hostCanon) or hostCanon
        wantCanon = U:GetCanonicalCharacterKey(wantCanon) or wantCanon
    end
    if hostCanon ~= wantCanon then
        WarbandNexus:GearStoragePanelDebug(("Redraw EXIT false (canon mismatch host=%s want=%s)"):format(tostring(hostCanon), tostring(wantCanon)))
        return false
    end

    local recContent = host.recContent
    local recScroll = host.recScroll
    local storagePanel = host.storagePanel
    if not recContent or not recScroll or not storagePanel then
        WarbandNexus:GearStoragePanelDebug("Redraw EXIT false (missing recContent/recScroll/storagePanel)")
        return false
    end
    if not recContent.GetParent or not recContent:GetParent() then
        WarbandNexus:GearStoragePanelDebug("Redraw EXIT false (recContent has no parent)")
        return false
    end

    -- Yielded storage scan still pumping: keep the loading line; do not return false (avoids applyStorageScanUI Populate storm).
    if ns._gearStorageYieldCo and ns._gearStorageYieldFindCanon == expectedCanonKey then
        WarbandNexus:GearStoragePanelDebug("Redraw -> scanning UI (yield in flight for this canon)")
        ShowGearStorageScanningInRecContent(recContent)
        return true
    end

    local Pst = ns.Profiler
    local stOn = Pst and Pst.enabled and Pst.StartSlice and Pst.StopSlice
    local function stStart(nm)
        if stOn then Pst:StartSlice(Pst.CAT.UI, nm) end
    end
    local function stStop(nm)
        if stOn then Pst:StopSlice(Pst.CAT.UI, nm) end
    end

    stStart("Gear_StorageRec_resolve")
    local findings, cachedHit
    if self.GetGearStorageFindingsIfCached then
        findings, cachedHit = self:GetGearStorageFindingsIfCached(expectedCanonKey)
    end
    if not cachedHit and trustEquipSigWhenInvMiss and self.GetGearStorageFindingsIfEquipSigMatch then
        findings, cachedHit = self:GetGearStorageFindingsIfEquipSigMatch(expectedCanonKey)
    end
    if not cachedHit and self.TryCoalesceGearStorageFullFind then
        local coalesced = self:TryCoalesceGearStorageFullFind(expectedCanonKey)
        if coalesced then
            findings = coalesced
            cachedHit = true
        end
    end
    if not cachedHit then
        -- Post-yield redraw: use findings committed by the scan that just finished.
        if ns._gearStorageAllowEquipSigInvBypass then
            if self.GetGearStorageFindingsCommitted then
                findings, cachedHit = self:GetGearStorageFindingsCommitted(expectedCanonKey)
            end
            if not cachedHit and self.GetGearStorageFindingsIfEquipSigMatch then
                findings, cachedHit = self:GetGearStorageFindingsIfEquipSigMatch(expectedCanonKey)
            end
        end
        if not cachedHit then
        -- Scan still running or queued: never block the frame with a second full FindGearStorageUpgrades.
        if ns._gearStorageDeferAwaiting or ns._gearStorageYieldCo then
            stStop("Gear_StorageRec_resolve")
            WarbandNexus:GearStoragePanelDebug(("Redraw -> scanning UI (deferAwait=%s yieldCo=%s kickMayRun=%s)"):format(
                tostring(ns._gearStorageDeferAwaiting == true),
                tostring(ns._gearStorageYieldCo ~= nil),
                tostring(ns._gearStorageDeferAwaiting and not ns._gearStorageYieldCo
                    and ns._gearStorageDeferAwaitCanon == wantCanon)))
            -- Defer is set but no coroutine is pumping (TryStart missed / populate-key race): kick once per draw gen.
            if ns._gearStorageDeferAwaiting and not ns._gearStorageYieldCo
                and ns._gearStorageDeferAwaitCanon == wantCanon and mf
                and mf._gearStorageScanKickGen ~= expectedDrawGen then
                mf._gearStorageScanKickGen = expectedDrawGen
                mf._gearPendingStorageScan = mf._gearPendingStorageScan or {
                    canon = wantCanon,
                    paintGen = expectedDrawGen,
                }
                C_Timer.After(0, function()
                    mf._gearStorageScanKickGen = nil
                    if expectedDrawGen ~= (ns._gearTabDrawGen or 0) then return end
                    TryStartPendingGearStorageScan(mf, expectedDrawGen)
                end)
            end
            ShowGearStorageScanningInRecContent(recContent)
            return true
        end
        -- Never run a full cross-character Find on the UI thread (~25-30ms per call). Schedule yielded scan.
        stStop("Gear_StorageRec_resolve")
        WarbandNexus:GearStoragePanelDebug("Redraw -> schedule ScheduleGearStorageFindingsResolve (no cache yet, not defer-waiting)")
        ShowGearStorageScanningInRecContent(recContent)
        ns._gearStorageRecFindPending = ns._gearStorageRecFindPending or {}
        if not ns._gearStorageRecFindPending[expectedCanonKey] then
            ns._gearStorageRecFindPending[expectedCanonKey] = true
            self:ScheduleGearStorageFindingsResolve(expectedCanonKey, expectedDrawGen, function()
                ns._gearStorageRecFindPending[expectedCanonKey] = nil
                C_Timer.After(0, function()
                    if expectedDrawGen ~= (ns._gearTabDrawGen or 0) then return end
                    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
                    ns._gearStorageAllowEquipSigInvBypass = true
                    WarbandNexus:RedrawGearStorageRecommendationsOnly(expectedCanonKey, expectedDrawGen, true)
                    ns._gearStorageAllowEquipSigInvBypass = false
                    TryDismissGearContentVeil(mf, expectedDrawGen)
                end)
            end)
        else
            WarbandNexus:GearStoragePanelDebug(("Redraw -> ScheduleResolve already pending canon=%s"):format(tostring(expectedCanonKey)))
        end
        return true
        end
    end
    findings = findings or {}
    stStop("Gear_StorageRec_resolve")
    do
        local fs, fc = 0, 0
        for _, list in pairs(findings) do
            fs = fs + 1
            if type(list) == "table" then
                fc = fc + #list
            end
        end
        WarbandNexus:GearStoragePanelDebug(("Redraw RESOLVED strictCached=%s findingsSlots=%d candidates=%d equipSigBypass=%s"):format(
            tostring(cachedHit == true), fs, fc, tostring(ns._gearStorageAllowEquipSigInvBypass == true)))
    end

    stStart("Gear_StorageRec_rows")
    local gearData = (self.GetEquippedGear and self:GetEquippedGear(expectedCanonKey)) or {}
    local rows = BuildStorageRecommendationRows(findings, gearData)
    stStop("Gear_StorageRec_rows")
    WarbandNexus:GearStoragePanelDebug(("Redraw rowsBuilt=%d (BuildStorageRecommendationRows)"):format(#rows))

    local db = self.db and self.db.global
    local rawSel = selectedCharKey or GetSelectedCharKey()
    local charData = db and (db.characters[expectedCanonKey] or (rawSel and db.characters[rawSel]))

    local storagePad = host.storagePad
    local storageHeaderH = host.storageHeaderH
    local storageBarW = host.storageBarW
    local storageW = host.storageW
    local rowH = host.rowH
    local sbCol = host.sbCol

    local storagePanelH = (storagePanel.GetHeight and storagePanel:GetHeight()) or 0
    local viewportH = math.max(storagePanelH - storageHeaderH - storagePad - 10, 1)
    local hdrExtra = (#rows > 0) and GEAR_STORAGE_REC_TABLE_HDR or 0
    local rowsOverflow = (#rows * rowH + hdrExtra) > viewportH

    local contentW = rowsOverflow
        and math.max(120, storageW - storagePad * 2 - storageBarW)
        or math.max(120, storageW - storagePad * 2)

    local paintTok = (self.GetGearStorageFindingsDedupeToken and self:GetGearStorageFindingsDedupeToken()) or "0"
    paintTok = paintTok .. ":" .. tostring(#rows) .. ":" .. (rowsOverflow and "1" or "0") .. ":" .. tostring(math.floor(contentW + 0.5))
    -- Never short-circuit when #rows==0: otherwise we can skip repainting after "Scanning…" while the
    -- paint token matches the last empty-state paint, leaving the recommendations panel stuck.
    if recContent._gearRecForceNextPaint then
        host._lastGearRecPaintTok = nil
        recContent._gearRecForceNextPaint = nil
    end
    if host._lastGearRecPaintTok == paintTok and #rows > 0 then
        WarbandNexus:GearStoragePanelDebug("Redraw EXIT true (dedupe: same paintTok, rows>0)")
        return true
    end

    local scanShownAt = mf._gearStorageScanningShownAt
    if scanShownAt then
        local elapsed = GetTime() - scanShownAt
        if elapsed < GEAR_STORAGE_SCANNING_MIN_DISPLAY_SEC then
            if mf._gearStorageScanningMinPaintTimer and mf._gearStorageScanningMinPaintTimer.Cancel then
                mf._gearStorageScanningMinPaintTimer:Cancel()
            end
            local wantK, wantG, wantT = expectedCanonKey, expectedDrawGen, trustEquipSigWhenInvMiss
            local delay = GEAR_STORAGE_SCANNING_MIN_DISPLAY_SEC - elapsed
            mf._gearStorageScanningMinPaintTimer = C_Timer.NewTimer(delay, function()
                mf._gearStorageScanningMinPaintTimer = nil
                if wantG ~= (ns._gearTabDrawGen or 0) then return end
                if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
                WarbandNexus:RedrawGearStorageRecommendationsOnly(wantK, wantG, wantT)
            end)
            WarbandNexus:GearStoragePanelDebug(("Redraw defer final paint %.3fs (min scanning display)"):format(delay))
            return true
        end
    end
    mf._gearStorageScanningShownAt = nil

    stStart("Gear_StorageRec_paint")
    recScroll:ClearAllPoints()
    recScroll:SetPoint("TOPLEFT", storagePanel, "TOPLEFT", storagePad, -storageHeaderH)
    if rowsOverflow then
        recScroll:SetPoint("BOTTOMRIGHT", storagePanel, "BOTTOMRIGHT", -storageBarW, storagePad)
        if sbCol and sbCol.Show then sbCol:Show() end
    else
        recScroll:SetPoint("BOTTOMRIGHT", storagePanel, "BOTTOMRIGHT", -storagePad, storagePad)
        if sbCol and sbCol.Hide then sbCol:Hide() end
    end

    ClearGearRecScrollContent(recContent)

    recContent:SetWidth(contentW)
    local headerExtra = 0
    if #rows > 0 then
        recContent._gearRecHasHeader = true
        PaintGearStorageRecColumnHeader(recContent, contentW)
        headerExtra = GEAR_STORAGE_REC_TABLE_HDR
    else
        recContent._gearRecHasHeader = nil
    end
    recContent:SetHeight(math.max(#rows * rowH + headerExtra, viewportH))

    if #rows == 0 then
        local empty = FontManager:CreateFontString(recContent, GFR("gearStorageEmpty"), "OVERLAY")
        recContent._gearStorageStatusFont = empty
        empty:SetAllPoints()
        empty:SetJustifyH("CENTER")
        empty:SetJustifyV("MIDDLE")
        empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY", "No transferable stash upgrade beats your equipped items for these slots."))
        empty:SetTextColor(0.55, 0.55, 0.6)
        WarbandNexus:GearStoragePanelDebug("Redraw painted EMPTY list (0 upgrade rows after filter)")
    elseif AcquireStorageRow then
        stStop("Gear_StorageRec_paint")
        local function onRowsPainted()
            host._lastGearRecPaintTok = paintTok
            TryDismissGearContentVeil(mf, expectedDrawGen)
            stStart("Gear_StorageRec_sig")
            local mfSig = self.UI and self.UI.mainFrame
            if mfSig and self.GetGearPopulateSignatureFromDrawCaches then
                local curForSig = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(expectedCanonKey)) or {}
                local upForSig = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(expectedCanonKey)) or {}
                mfSig._gearPopulateContentSig = self:GetGearPopulateSignatureFromDrawCaches(gearData, curForSig, upForSig)
            elseif mfSig and self.GetGearPopulateSignature then
                mfSig._gearPopulateContentSig = self:GetGearPopulateSignature()
            end
            stStop("Gear_StorageRec_sig")
        end
        if #rows > 16 then
            PaintGearStorageRowsBatched(recContent, recScroll, rows, contentW, rowH, charData, expectedDrawGen, onRowsPainted)
        else
            local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
            local viewerClass = charData and charData.classFile
            for i = 1, #rows do
                local r = rows[i]
                local line = AcquireStorageRow(recContent, contentW, math.max(1, rowH - 2))
                if line then
                    PaintGearStorageRecommendationRow(line, i, rowH, contentW, r, itemTooltipContext, viewerClass)
                end
            end
            if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
            end
            onRowsPainted()
        end
        WarbandNexus:GearStoragePanelDebug(("Redraw painted ROWS sync path count=%d"):format(#rows))
        return true
    end

    if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
    end
    if recScroll and recScroll.SetVerticalScroll then
        recScroll:SetVerticalScroll(0)
    end

    host._lastGearRecPaintTok = paintTok
    stStop("Gear_StorageRec_paint")

    stStart("Gear_StorageRec_sig")
    local mfSig = self.UI and self.UI.mainFrame
    if mfSig and self.GetGearPopulateSignatureFromDrawCaches then
        local curForSig = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(expectedCanonKey)) or {}
        local upForSig = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(expectedCanonKey)) or {}
        mfSig._gearPopulateContentSig = self:GetGearPopulateSignatureFromDrawCaches(gearData, curForSig, upForSig)
    elseif mfSig and self.GetGearPopulateSignature then
        mfSig._gearPopulateContentSig = self:GetGearPopulateSignature()
    end
    stStop("Gear_StorageRec_sig")
    WarbandNexus:GearStoragePanelDebug(("Redraw DONE ok=true rows=%d emptyState=%s"):format(#rows, tostring(#rows == 0)))
    return true
end

--- Minimal slot snapshot from live inventory (equip events before DB read catches up).
---@param slotID number
---@return table|nil

--- In-place paperdoll slot refresh after equip/unequip (no full tab teardown).
---@param payload table|nil { charKey, slotIDs = { number, ... } }
---@return boolean ok
---@return boolean|nil needFollowUp When true, PLAYER_EQUIPMENT_CHANGED path should retry next tick (live link lag viewing current character).
function WarbandNexus:TryRefreshGearEquipSlotsOnly(payload)
    local mf = self.UI and self.UI.mainFrame
    if not mf or mf.currentTab ~= "gear" then return false end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return false end
    -- Storage scan / staged paperdoll defer must not block equip-slot visuals: icons read DB + live inventory only.

    local card = mf._gearPaperdollCard
    if not card or not card._gearSlotInspectList or #card._gearSlotInspectList == 0 then return false end
    if not card.GetParent or not card:GetParent() then return false end

    local canon = mf._gearPopulateCanonKey
    if not canon then return false end
    local rawSel = selectedCharKey or GetSelectedCharKey()
    local selCanon = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(rawSel) or rawSel
    if selCanon ~= canon then return false end

    local currentKey = (self.GetCurrentGearStorageKey and self:GetCurrentGearStorageKey())
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
    local currentCanon = currentKey and ((ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(currentKey) or currentKey) or nil
    if currentCanon and canon ~= currentCanon then
        return false
    end
    local isViewingCurrent = currentCanon and canon == currentCanon

    local slotFilter = payload and payload.slotIDs
    if not slotFilter or #slotFilter == 0 then
        return false
    end
    local refreshSet = {}
    for i = 1, #slotFilter do
        local sid = tonumber(slotFilter[i])
        if sid then refreshSet[sid] = true end
    end
    for sid in pairs(refreshSet) do
        local partner = ns.GEAR_PAPERDOLL.GEAR_REFRESH_PAIR_SLOTS[sid]
        if partner then refreshSet[partner] = true end
    end
    if not next(refreshSet) then return false end

    local gearData = (self.GetEquippedGear and self:GetEquippedGear(canon)) or nil
    local slots = gearData and gearData.slots
    if not slots then
        if not isViewingCurrent then return false end
        slots = {}
    elseif not next(slots) and not isViewingCurrent then
        return false
    end

    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canon)) or {}
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(canon)) or {}
    local currencyAmounts = {}
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur and cur.currencyID ~= nil then
            local id = (type(cur.currencyID) == "number") and cur.currencyID or tonumber(cur.currencyID)
            local amt = (type(cur.amount) == "number") and cur.amount or tonumber(cur.amount)
            if id then currencyAmounts[id] = (amt and amt >= 0) and amt or 0 end
        end
    end

    local slotList = card._gearSlotInspectList
    local refreshed = {}
    local needFollowUp = false
    local sawRefreshTarget = false
    for si = 1, #slotList do
        local sb = slotList[si]
        local slotID = sb and sb._slotID
        if sb and slotID and refreshSet[slotID] and sb._gearApplySlotVisual then
            sawRefreshTarget = true
            -- Prefer live inventory when viewing the logged-in character so ring/weapon swaps
            -- never paint stale/empty DB rows before ScanEquippedGear's debounced write lands.
            local liveSnap
            if isViewingCurrent then
                liveSnap = ns.GearUI_BuildLiveEquippedSlotSnapshot(slotID)
            end
            local slotData
            if isViewingCurrent then
                slotData = liveSnap or (slots and slots[slotID])
            else
                slotData = slots and slots[slotID]
            end
            local quality = (slotData and slotData.quality) or 0
            local up = upgradeInfo[slotID]
            local canUpgrade = up and up.canUpgrade and CanAffordNextUpgrade(up, currencyAmounts)
            local notUpgradeable = false
            if slotData and slotData.notUpgradeable then
                notUpgradeable = true
            elseif up and up.notUpgradeable then
                notUpgradeable = true
            end
            local trackText = ns.GearUI_GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)
            local bypassDiff = isViewingCurrent and not liveSnap
                and (ns.GearUI_GearSlotHasInspectableItemLink(slotData) or ns.GearUI_GearSlotHasInspectableItemLink(sb._slotDataRef))
            if bypassDiff then
                needFollowUp = true
            end
            if not bypassDiff and ns.GearUI_GearSlotPaperdollVisualEquals(sb, slotData, canUpgrade, trackText, notUpgradeable) then
                -- No-op: visuals already match (avoids texture churn + deferred inspect storms).
            else
                sb:_gearApplySlotVisual(slotData, canUpgrade, trackText, notUpgradeable)
                refreshed[#refreshed + 1] = sb
            end
        end
    end
    if #refreshed == 0 then
        if not sawRefreshTarget then
            return false
        end
        return true, needFollowUp
    end

    C_Timer.After(0, function()
        if not mf or mf.currentTab ~= "gear" then return end
        if not card or not card.GetParent or not card:GetParent() then return end
        for ri = 1, #refreshed do
            local sb = refreshed[ri]
            if sb and sb._needsDeferredInspect then
                ns.GearUI_GearSlotApplyDeferredEnchantGemInspect(sb)
            end
        end
    end)

    local db = self.db and self.db.global
    local charData = db and db.characters[canon]
    local avgIlvl = charData and charData.itemLevel or 0
    local ilvlFrame = ns._gearIlvlFrame
    if ilvlFrame and ilvlFrame._label and avgIlvl and avgIlvl > 0 then
        ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
        ilvlFrame:Show()
    end

    gearData = (self.GetEquippedGear and self:GetEquippedGear(canon)) or gearData
    if self.GetGearPopulateSignatureFromDrawCaches then
        mf._gearPopulateContentSig = self:GetGearPopulateSignatureFromDrawCaches(gearData, currencies, upgradeInfo)
    elseif self.GetGearPopulateSignature then
        mf._gearPopulateContentSig = self:GetGearPopulateSignature()
    end
    return true, needFollowUp
end

--- After equip-only updates: repaint Recommended from cached bag findings + fresh equipped gear (no full storage scan).
---@param expectedCanonKey string
---@param expectedDrawGen number
---@return boolean ok
function WarbandNexus:TryRedrawGearStorageRecAfterEquipChange(expectedCanonKey, expectedDrawGen)
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then return false end
    if not expectedCanonKey or not expectedDrawGen then return false end
    if self.IsGearStorageScanInFlightForCanon and self:IsGearStorageScanInFlightForCanon(expectedCanonKey) then
        if self.NotifyGearStorageEquipChanged then
            self:NotifyGearStorageEquipChanged(expectedCanonKey)
        end
        local mf = self.UI and self.UI.mainFrame
        local host = mf and mf._gearStorageRecHost
        if host and host.recContent and host.drawGen == expectedDrawGen then
            ShowGearStorageScanningInRecContent(host.recContent)
        end
        return true
    end
    if ns._gearStorageDeferAwaiting then return false end
    local mf = self.UI and self.UI.mainFrame
    if not mf or mf.currentTab ~= "gear" then return false end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return false end
    if not mf._gearStorageRecHost or mf._gearStorageRecHost.drawGen ~= expectedDrawGen then return false end
    if not self.RefreshGearStorageCacheEquipSigForCanon then return false end
    if not self:RefreshGearStorageCacheEquipSigForCanon(expectedCanonKey) then return false end
    if not self.RedrawGearStorageRecommendationsOnly then return false end
    return self:RedrawGearStorageRecommendationsOnly(expectedCanonKey, expectedDrawGen, false) == true
end

--- Live paperdoll repaint from equipment events before debounced ScanEquippedGear / WN_GEAR_UPDATED.
--- Inventory APIs can lag PLAYER_EQUIPMENT_CHANGED by a frame; we coalesce paired slots and retry.
---@param changedSlotID number
function WarbandNexus:TryRefreshGearEquipSlotsImmediate(changedSlotID)
    if not changedSlotID or type(changedSlotID) ~= "number" then return end
    local sid = math.floor(changedSlotID)
    if sid < 1 or sid > 17 then return end
    local slotIDs = { sid }
    local partner = ns.GEAR_PAPERDOLL.GEAR_REFRESH_PAIR_SLOTS[sid]
    if partner then
        slotIDs[#slotIDs + 1] = partner
    end
    local pl = { slotIDs = slotIDs }
    local function run()
        if WarbandNexus.TryRefreshGearEquipSlotsOnly then
            return WarbandNexus:TryRefreshGearEquipSlotsOnly(pl)
        end
        return false
    end
    local ok1, follow1 = run()
    if C_Timer and C_Timer.After then
        if (not ok1) or follow1 then
            C_Timer.After(0, function()
                run()
            end)
        end
    end
end

--- One-shot refresh of all gear-tab paperdoll slot icons (after item cache resolves).
function WarbandNexus:TryRefreshAllGearEquipSlotIcons()
    if self.TryRefreshGearEquipSlotsOnly then
        self:TryRefreshGearEquipSlotsOnly({ slotIDs = GEAR_PAPERDOLL_REFRESH_SLOT_IDS })
    end
end

--- Item-level-only refresh (no PopulateContent): paperdoll ilvl badge + populate signature.
---@param charKeyFromMsg string|nil canonical or storage key from WN_CHARACTER_UPDATED
---@return boolean ok true when the gear tab was showing that character and the badge was refreshed
function WarbandNexus:TryRefreshGearTabItemLevelOnly(charKeyFromMsg)
    if not charKeyFromMsg or charKeyFromMsg == "" then return false end
    local mf = self.UI and self.UI.mainFrame
    if not mf or mf.currentTab ~= "gear" then return false end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return false end
    local U = ns.Utilities
    local viewCanon = mf._gearPopulateCanonKey
    if not viewCanon then return false end
    local msgCanon = (U and U.GetCanonicalCharacterKey) and U:GetCanonicalCharacterKey(charKeyFromMsg) or charKeyFromMsg
    local gCanon = (U and U.GetCanonicalCharacterKey) and U:GetCanonicalCharacterKey(viewCanon) or viewCanon
    if not msgCanon or not gCanon or msgCanon ~= gCanon then return false end

    local db = self.db and self.db.global
    local charData = db and db.characters and db.characters[gCanon]
    local avgIlvl = charData and charData.itemLevel or 0
    local ilvlFrame = ns._gearIlvlFrame
    if ilvlFrame and ilvlFrame._label and avgIlvl and avgIlvl > 0 then
        ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
        ilvlFrame:Show()
    end

    local gearData = (self.GetEquippedGear and self:GetEquippedGear(gCanon)) or nil
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(gCanon)) or {}
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(gCanon)) or {}
    if self.GetGearPopulateSignatureFromDrawCaches then
        mf._gearPopulateContentSig = self:GetGearPopulateSignatureFromDrawCaches(gearData, currencies, upgradeInfo)
    elseif self.GetGearPopulateSignature then
        mf._gearPopulateContentSig = self:GetGearPopulateSignature()
    end
    return true
end

--- Prefer narrow storage-row repaint (no full PopulateContent) when item cache warms on Gear.
---@return boolean ok
function WarbandNexus:TryGearStorageRedrawOnly()
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then return false end
    local mf = self.UI and self.UI.mainFrame
    if not mf or mf.currentTab ~= "gear" then return false end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return false end
    if ns._gearStorageDeferAwaiting or ns._gearStorageYieldCo or mf._gearDeferChainActive then
        return false
    end
    local rawSel = selectedCharKey or GetSelectedCharKey()
    if not rawSel then return false end
    local canon = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(rawSel) or rawSel
    local gen = ns._gearTabDrawGen or 0
    if not self.RedrawGearStorageRecommendationsOnly then return false end
    return self:RedrawGearStorageRecommendationsOnly(canon, gen, true) == true
end

-- ============================================================================
-- CHARACTER SELECTOR  (dropdown button)
-- ============================================================================

-- Singleton dropdown frames (reused to avoid frame buildup)
local gearCharDropdownMenu = nil
local gearCharDropdownBg   = nil
local gearCharSelectorBtn  = nil
local gearHideFilterBtn    = nil
local gearCharDropdownEntryPool = {}

local GEAR_CHAR_SEP = "|cff888888 | |r"

--- Max pixel width of colored character names (for aligned name column).
local function MeasureGearCharNameColumnWidth(chars, measureFs)
    local maxW = 0
    for i = 1, #chars do
        local c = chars[i].data
        local hex = GetClassHex(c.classFile)
        local nm = c.name or chars[i].key or ""
        measureFs:SetText("|cff" .. hex .. nm .. "|r")
        maxW = math.max(maxW, measureFs:GetStringWidth())
    end
    return maxW
end

--- Name column width: wide enough for longest name, capped so realm keeps a readable minimum width.
local function ComputeGearCharNameColW(chars, measureFs, textBudget)
    if textBudget < 56 then
        return math.max(36, math.floor(textBudget * 0.38))
    end
    local raw = MeasureGearCharNameColumnWidth(chars, measureFs) + 6
    local minRealm = 102
    local sepReserve = 22
    local capByRealm = textBudget - minRealm - sepReserve
    local capByRatio = math.floor(textBudget * 0.48)
    local cap = math.min(capByRatio, math.max(52, capByRealm))
    return math.min(math.max(raw, 48), cap)
end

--- Two fontstrings: fixed-width name column, then separator, then realm (remaining width).
local function LayoutGearCharNameRealmColumns(parent, nameColW, leftPad, arrowReserve)
    local nm = parent._nameLabel
    local sp = parent._sepLabel
    local rm = parent._realmLabel
    if not nm or not sp or not rm then return end
    nm:ClearAllPoints()
    sp:ClearAllPoints()
    rm:ClearAllPoints()
    nm:SetWidth(nameColW)
    nm:SetJustifyH("LEFT")
    nm:SetWordWrap(false)
    nm:SetPoint("LEFT", parent, "LEFT", leftPad, 0)
    nm:SetPoint("TOP", parent, "TOP", 0, 0)
    nm:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    sp:SetText(GEAR_CHAR_SEP)
    sp:SetWidth(20)
    sp:SetJustifyH("CENTER")
    sp:SetPoint("LEFT", nm, "RIGHT", 0, 0)
    sp:SetPoint("TOP", parent, "TOP", 0, 0)
    sp:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
    rm:SetJustifyH("LEFT")
    rm:SetWordWrap(false)
    rm:SetPoint("LEFT", sp, "RIGHT", 2, 0)
    rm:SetPoint("RIGHT", parent, "RIGHT", -arrowReserve, 0)
    rm:SetPoint("TOP", parent, "TOP", 0, 0)
    rm:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)
end

local function EnsureGearSelectorColumnLabels(btn)
    if btn._nameLabel then return end
    if btn._label then
        btn._label:Hide()
        btn._label = nil
    end
    btn._nameLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._sepLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._realmLabel = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "OVERLAY")
    btn._measureFs = FontManager:CreateFontString(btn, GFR("gearCharSelector"), "ARTWORK")
    btn._measureFs:SetAlpha(0)
    btn._measureFs:SetPoint("TOPLEFT", btn, "TOPLEFT", -4000, 0)
end

local function EnsureGearEntryColumnLabels(entryBtn)
    if entryBtn._nameLabel then return end
    if entryBtn._label then
        entryBtn._label:Hide()
        entryBtn._label = nil
    end
    entryBtn._nameLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
    entryBtn._sepLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
    entryBtn._realmLabel = FontManager:CreateFontString(entryBtn, GFR("gearCharSelector"), "OVERLAY")
end

--- Close Gear character picker when main addon frame hides (menu is parented to UIParent).
function ns.HideGearCharacterDropdown()
    if gearCharDropdownMenu then gearCharDropdownMenu:Hide() end
    if gearCharDropdownBg then gearCharDropdownBg:Hide() end
end

local function CreateCharacterSelector(parent, currentCharKey, yOffset)
    local chars  = GetTrackedCharacters()
    if #chars == 0 then return nil, yOffset end

    local COLORS = ns.UI_COLORS
    local accent = COLORS.accent
    local SCROLL_COL_EST = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local MENU_EDGE_EST = 4

    local btn = gearCharSelectorBtn
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetHeight(GEAR_CHAR_SELECTOR_HEIGHT)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })

        EnsureGearSelectorColumnLabels(btn)

        local arrow = btn:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT", -5, 0)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

        local hi = btn:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.08)

        btn.isPersistentRowElement = true
        gearCharSelectorBtn = btn
    end

    EnsureGearSelectorColumnLabels(btn)

    btn:SetParent(parent)
    btn:ClearAllPoints()
    btn:SetHeight(GEAR_CHAR_SELECTOR_HEIGHT)
    btn:SetWidth(GEAR_CHAR_SELECTOR_WIDTH)
    -- Vertically centered like Characters/Storage/PvE header sort controls (RIGHT, -20, 0).
    btn:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    btn:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
    btn:SetBackdropBorderColor(accent[1]*0.6, accent[2]*0.6, accent[3]*0.6, 0.8)

    local function SetLabelToChar(charKey)
        local db    = WarbandNexus.db and WarbandNexus.db.global
        local cData = db and db.characters and db.characters[charKey]
        local nm = btn._nameLabel
        local rm = btn._realmLabel
        if not nm then return end
        if cData and (cData.name and cData.name ~= "") then
            local hex   = GetClassHex(cData.classFile)
            local namePart = "|cff" .. hex .. (cData.name or "") .. "|r"
            nm:SetText(namePart)
            nm:SetTextColor(1, 1, 1)
            local realm = cData.realm and cData.realm ~= "" and cData.realm or nil
            if realm and rm then
                local realmShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(realm)) or realm
                rm:SetText("|cffffffff" .. realmShown .. "|r")
            elseif rm then
                rm:SetText("")
            end
        elseif charKey and charKey ~= "" then
            nm:SetText(charKey)
            nm:SetTextColor(1, 1, 1)
            if rm then rm:SetText("") end
        else
            nm:SetText("")
            if rm then rm:SetText("") end
        end
    end

    -- Shared text budget: selector row and list rows use the same inner width as the scroll child
    -- (outer width minus left/right menu edges, scrollbar column, gap, and entry horizontal padding).
    local function RefreshSelectorColumns(charList)
        local list = charList or GetTrackedCharacters()
        if #list == 0 or not btn._measureFs then return end
        local btnW = math.max(1, btn:GetWidth())
        local scrollFrameW = btnW - 2 * MENU_EDGE_EST - SCROLL_COL_EST - 2
        local entryHPad = 12
        local rowTextBudget = math.max(56, scrollFrameW - entryHPad)
        local selectorLeftPad = 8
        local selectorArrowReserve = 22
        local selectorTextBudget = math.max(56, btnW - selectorLeftPad - selectorArrowReserve)
        local textBudget = math.max(56, math.min(rowTextBudget, selectorTextBudget))
        local nameColW = ComputeGearCharNameColW(list, btn._measureFs, textBudget)
        LayoutGearCharNameRealmColumns(btn, nameColW, selectorLeftPad, selectorArrowReserve)
        for i = 1, #gearCharDropdownEntryPool do
            local eb = gearCharDropdownEntryPool[i]
            if eb and eb._nameLabel then
                LayoutGearCharNameRealmColumns(eb, nameColW, 6, 6)
            end
        end
    end

    RefreshSelectorColumns(chars)
    SetLabelToChar(currentCharKey)

    -- Dropdown: reuse singleton menu and bg to avoid frame buildup
    btn:SetScript("OnClick", function(self)
        local list = GetTrackedCharacters()
        if #list == 0 then return end

        local menu = gearCharDropdownMenu
        local bg   = gearCharDropdownBg

        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(500)
            menu:SetWidth(GEAR_CHAR_SELECTOR_WIDTH)
            menu:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.06, 0.06, 0.10, 0.98)
            menu:SetBackdropBorderColor(accent[1]*0.5, accent[2]*0.5, accent[3]*0.5, 0.9)

            -- Factory scroll + dedicated scrollbar column (matches main window / Collections)
            local SCROLL_COL = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
            local MENU_EDGE = 4

            menu._barColumn = GearFact:CreateScrollBarColumn(menu, SCROLL_COL, MENU_EDGE, MENU_EDGE)
            local sf = GearFact:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
            sf:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_EDGE, -MENU_EDGE)
            sf:SetPoint("BOTTOMRIGHT", menu._barColumn, "BOTTOMLEFT", -2, MENU_EDGE)
            if sf.SetClipsChildren then
                sf:SetClipsChildren(true)
            end
            local initScW = math.max(56, GEAR_CHAR_SELECTOR_WIDTH - SCROLL_COL - MENU_EDGE * 2)
            local initScH = math.max(8, GEAR_CHAR_DROPDOWN_ENTRY_H + 8)
            local sc = GearFact:CreateContainer(sf, initScW, initScH, false)
            sf:SetScrollChild(sc)
            menu._charScroll = sf
            menu._charScrollChild = sc
            if sf.ScrollBar then
                GearFact:PositionScrollBarInContainer(sf.ScrollBar, menu._barColumn, 0)
            end
            sf:SetScript("OnSizeChanged", function(frame, w)
                if sc and w and w > 0 then
                    sc:SetWidth(w)
                end
            end)
            gearCharDropdownMenu = menu
        end
        if not bg then
            bg = GearFact:CreateButton(UIParent, 64, 64, true)
            bg:SetAllPoints()
            bg:SetFrameStrata("FULLSCREEN_DIALOG")
            bg:SetFrameLevel(499)
            bg:SetScript("OnClick", function()
                menu:Hide()
                bg:Hide()
            end)
            gearCharDropdownBg = bg
        end

        local ENTRY_H = GEAR_CHAR_DROPDOWN_ENTRY_H
        local contentH = #list * ENTRY_H + 8
        local screenH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 800
        local maxMenuH = math.max(ENTRY_H + 8, math.floor(screenH * 0.52))
        local menuH = math.min(contentH, maxMenuH)
        menu:SetHeight(menuH)
        menu:ClearAllPoints()
        -- Same outer width and horizontal alignment as header selector (full card strip).
        local btnW = math.max(1, math.floor(self:GetWidth() + 0.5))
        menu:SetWidth(btnW)
        menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)

        local scroll = menu._charScroll
        local scrollChild = menu._charScrollChild
        if scroll and scrollChild then
            scrollChild:SetHeight(math.max(contentH, 1))
            scroll:SetVerticalScroll(0)
            local sw = scroll:GetWidth()
            if sw and sw > 0 then
                scrollChild:SetWidth(sw)
            end
        end

        local selKey = selectedCharKey or GetSelectedCharKey()

        -- Hide excess pooled entries, reuse or create as needed
        for pi = #list + 1, #gearCharDropdownEntryPool do
            local poolBtn = gearCharDropdownEntryPool[pi]
            if poolBtn then poolBtn:Hide() end
        end

        local entryParent = scrollChild or menu
        local entryY = -4
        for i = 1, #list do
            local charEntry = list[i]
            local entryBtn = gearCharDropdownEntryPool[i]
            if not entryBtn then
                entryBtn = GearFact:CreateButton(entryParent, math.max(120, btnW - 12), ENTRY_H, true)
                EnsureGearEntryColumnLabels(entryBtn)
                local entryHi = entryBtn:CreateTexture(nil, "HIGHLIGHT")
                entryHi:SetAllPoints()
                entryHi:SetColorTexture(1, 1, 1, 0.1)
                gearCharDropdownEntryPool[i] = entryBtn
            end
            EnsureGearEntryColumnLabels(entryBtn)
            entryBtn:SetHeight(ENTRY_H)

            entryBtn:EnableMouseWheel(true)
            entryBtn:SetScript("OnMouseWheel", function(entry, delta)
                if ns.UI_ForwardMouseWheelToScrollAncestor then
                    ns.UI_ForwardMouseWheelToScrollAncestor(entry, delta)
                end
            end)

            entryBtn:SetParent(entryParent)
            entryBtn:ClearAllPoints()
            entryBtn:SetPoint("TOPLEFT",  6, entryY)
            entryBtn:SetPoint("TOPRIGHT", -6, entryY)

            if entryBtn.SetClippingChildren then
                entryBtn:SetClippingChildren(true)
            end
            local cKey   = charEntry.key
            local cData  = charEntry.data
            local hex    = GetClassHex(cData.classFile)
            local namePart = "|cff" .. hex .. (cData.name or cKey) .. "|r"
            local r = cData.realm and cData.realm ~= "" and cData.realm or ""
            entryBtn._nameLabel:SetText(namePart)
            entryBtn._nameLabel:SetTextColor(1, 1, 1)
            if r ~= "" then
                local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(r)) or r
                entryBtn._realmLabel:SetText("|cffffffff" .. rShown .. "|r")
            else
                entryBtn._realmLabel:SetText("")
            end

            if cKey == selKey then
                entryBtn._realmLabel:SetTextColor(accent[1] + 0.2, accent[2] + 0.2, accent[3] + 0.2)
            else
                entryBtn._realmLabel:SetTextColor(1, 1, 1)
            end

            entryBtn:SetScript("OnClick", function()
                selectedCharKey = cKey
                SetLabelToChar(cKey)
                menu:Hide()
                bg:Hide()
                local mfInst = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                if mfInst then
                    mfInst._gearCharUpdSuppressUntil = GetTime() + 0.45
                end
                if WarbandNexus and WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "gear",
                        skipCooldown = true,
                        instantPopulate = true,
                    })
                end
            end)

            entryBtn:Show()
            entryY = entryY - ENTRY_H
        end

        local function SyncDropdownScroll()
            if not menu or not menu:IsShown() or not scroll or not scrollChild then return end
            local sw = scroll:GetWidth()
            if sw and sw > 0 then
                scrollChild:SetWidth(sw)
            end
            if GearFact.UpdateScrollBarVisibility then
                GearFact:UpdateScrollBarVisibility(scroll)
            elseif scroll.UpdateScrollBarVisibility then
                scroll:UpdateScrollBarVisibility()
            end
        end

        local function RelayoutColumnsAfterSize()
            SyncDropdownScroll()
            RefreshSelectorColumns(list)
            SetLabelToChar(selKey)
        end

        bg:Show()
        menu:Show()
        RelayoutColumnsAfterSize()
        C_Timer.After(0, RelayoutColumnsAfterSize)
    end)

    btn:SetScript("OnEnter", function(self)
        local a = (ns.UI_COLORS or {}).accent or {0.5, 0.3, 0.8}
        self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        local a = (ns.UI_COLORS or {}).accent or {0.5, 0.3, 0.8}
        self:SetBackdropBorderColor(a[1]*0.6, a[2]*0.6, a[3]*0.6, 0.8)
    end)

    btn._refreshGearCharColumns = function()
        local cl = GetTrackedCharacters()
        if #cl == 0 then return end
        RefreshSelectorColumns(cl)
        SetLabelToChar(selectedCharKey or GetSelectedCharKey())
    end

    return btn, yOffset
end

local function CreateGearHeaderHideButton(parent)
    local btn = gearHideFilterBtn
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(GEAR_HIDE_FILTER_BUTTON_W, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or GEAR_CHAR_SELECTOR_HEIGHT or 32)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        local txt = FontManager:CreateFontString(btn, "body", "OVERLAY")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetJustifyH("CENTER")
        txt:SetTextColor(0.9, 0.9, 0.9)
        btn._text = txt
        gearHideFilterBtn = btn
    end

    btn:SetParent(parent)
    btn:ClearAllPoints()
    btn:SetBackdropColor(0.08, 0.08, 0.11, 0.9)
    do
        local a = (COLORS and COLORS.accent) or { 0.5, 0.3, 0.8 }
        btn:SetBackdropBorderColor(a[1] * 0.6, a[2] * 0.6, a[3] * 0.6, 0.8)
    end

    btn._text:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"))

    local function HideMenuClose()
        if btn._menu and btn._menu:IsShown() then btn._menu:Hide() end
        if btn._catcher and btn._catcher:IsShown() then btn._catcher:Hide() end
    end
    local function HideMenuApply(threshold, keepMenuOpen)
        ApplyLowLevelHideThreshold(threshold)
        if not keepMenuOpen then
            HideMenuClose()
        end
    end
    local function HideMenuBuild()
        local menu = btn._menu
        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(5200)
            menu:SetSize(132, 66)
            menu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
            local accent = (COLORS and COLORS.accent) or ((ns.UI_COLORS or {}).accent) or { 0.40, 0.20, 0.58 }
            menu:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
            btn._menu = menu
        end
        local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        local options = {
            { value = 80, label = GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") },
            { value = 90, label = GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") },
        }
        local children = { menu:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #children do
            children[i]:Hide()
            if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
        end
        local rowH = 30
        for i = 1, #options do
            local opt = options[i]
            local row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * rowH)
            row:SetHeight(rowH - 2)
            row:RegisterForClicks("LeftButtonUp")
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor((opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.20 or 0.10, 1)
            local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, opt.value == cur)
            if not cb then return menu end
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", row, "LEFT", 6, 0)
            cb:EnableMouse(false)
            local fs = FontManager:CreateFontString(row, "body", "OVERLAY")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(opt.label)
            fs:SetTextColor(1, 1, 1)
            row:SetScript("OnClick", function()
                local active = GetLowLevelHideThreshold(WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile)
                local nextThreshold = (active == opt.value) and 0 or opt.value
                HideMenuApply(nextThreshold, true)
                HideMenuBuild()
            end)
        end
        return menu
    end

    btn:SetScript("OnClick", function(self)
        local menu = btn._menu
        if menu and menu:IsShown() then
            HideMenuClose()
            return
        end
        if ns.HideGearCharacterDropdown then
            ns.HideGearCharacterDropdown()
        end
        menu = HideMenuBuild()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        menu:Show()
        local catcher = btn._catcher
        if not catcher then
            catcher = GearFact:CreateButton(UIParent, 64, 64, true)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetFrameLevel(5199)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function(_, button)
                if menu and menu:IsShown() and not menu:IsMouseOver() and not btn:IsMouseOver() then
                    HideMenuClose()
                end
            end)
            btn._catcher = catcher
        end
        catcher:Show()
    end)
    btn:SetScript("OnEnter", function(self)
        local a = (COLORS and COLORS.accent) or { 0.5, 0.3, 0.8 }
        self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"), 1, 1, 1)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_TOGGLE", "Toggle filters: Level 80 / Level 90"), 0.8, 0.8, 0.8)
        local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_CURRENT", "Current: %s"):format(GetLowLevelHideLabel(cur)), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        local a = (COLORS and COLORS.accent) or { 0.5, 0.3, 0.8 }
        self:SetBackdropBorderColor(a[1] * 0.6, a[2] * 0.6, a[3] * 0.6, 0.8)
        if GameTooltip then GameTooltip:Hide() end
    end)

    btn:Show()
    return btn
end

-- ============================================================================
-- POPULATE DEDUPE SIGNATURE (same-tab redundant PopulateContent)
-- ============================================================================

--- Stable fingerprint of everything DrawGearTab reads from DB/cache for the current selection.
--- Used by Modules/UI.lua to skip teardown+full redraw when WN_* debounce fires with no real delta.
---@param cachedGearData table|nil When non-nil, skips GetEquippedGear (DrawGearTab / storage redraw already fetched).
---@param cachedCurrencies table|nil When non-nil, skips GetGearUpgradeCurrenciesFromDB.
---@param cachedUpgradeInfo table|nil When non-nil, skips GetPersistedUpgradeInfo.
local function ComputeGearPopulateSignatureCore(self, parts, curBlob, upPieces, cachedGearData, cachedCurrencies, cachedUpgradeInfo)
    local mf = self.UI and self.UI.mainFrame
    if not mf or mf.currentTab ~= "gear" then return nil end
    local charKey = selectedCharKey or GetSelectedCharKey()
    if not charKey then return nil end
    local canon = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    local invE = tonumber(ns._gearStorageInvGen) or 0
    local w = 0
    if mf.scrollChild and mf.scrollChild.GetWidth then
        w = math.floor(tonumber(mf.scrollChild:GetWidth()) or 0)
    end
    local hideTh = 0
    if self.db and self.db.profile then
        hideTh = tonumber(GetLowLevelHideThreshold(self.db.profile)) or 0
    end
    local gearData
    if cachedGearData ~= nil then
        gearData = cachedGearData
    else
        gearData = (self.GetEquippedGear and self:GetEquippedGear(canon)) or nil
    end
    local slots = gearData and gearData.slots
    for sid = 1, 19 do
        local s = slots and slots[sid]
        if s then
            parts[#parts + 1] = tostring(sid) .. ":" .. tostring(tonumber(s.itemID) or 0) .. ":"
                .. tostring(math.floor(tonumber(s.itemLevel) or 0)) .. ":" .. tostring(tonumber(s.quality) or 0)
        end
    end
    local currencies
    if cachedCurrencies ~= nil then
        currencies = cachedCurrencies
    else
        currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(canon)) or {}
    end
    for i = 1, #currencies do
        local c = currencies[i]
        if c and c.currencyID ~= nil then
            local id = (type(c.currencyID) == "number") and c.currencyID or tonumber(c.currencyID)
            local amt = (type(c.amount) == "number") and c.amount or tonumber(c.amount)
            curBlob[#curBlob + 1] = tostring(id or 0) .. ":" .. tostring(amt or 0)
        end
    end
    local up
    if cachedUpgradeInfo ~= nil then
        up = cachedUpgradeInfo
    else
        up = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canon)) or {}
    end
    for slotID = 1, 19 do
        local u = up[slotID]
        if u and type(u) == "table" then
            upPieces[#upPieces + 1] = tostring(slotID) .. ":" .. tostring(tonumber(u.currUpgrade) or 0) .. ":"
                .. tostring(tonumber(u.maxUpgrade) or 0) .. ":" .. tostring(u.trackName or "")
        end
    end
    local storageTok = "0"
    if WarbandNexus:IsGearStorageRecommendationsEnabled()
        and self.GetGearStorageFindingsDedupeToken then
        storageTok = self:GetGearStorageFindingsDedupeToken() or "0"
    end
    return canon .. "\1" .. tostring(invE) .. "\1" .. tostring(w) .. "\1" .. tostring(hideTh) .. "\1"
        .. table.concat(parts, ";") .. "\1" .. table.concat(curBlob, ";") .. "\1" .. table.concat(upPieces, ";")
        .. "\1" .. tostring(storageTok)
end

function WarbandNexus:GetGearPopulateSignature()
    _gearPopulateSigDepth = _gearPopulateSigDepth + 1
    local out
    if _gearPopulateSigDepth > 1 then
        out = ComputeGearPopulateSignatureCore(self, {}, {}, {}, nil, nil, nil)
    else
        wipe(_gearSigParts)
        wipe(_gearSigCurBlob)
        wipe(_gearSigUpPieces)
        out = ComputeGearPopulateSignatureCore(self, _gearSigParts, _gearSigCurBlob, _gearSigUpPieces, nil, nil, nil)
    end
    _gearPopulateSigDepth = _gearPopulateSigDepth - 1
    return out
end

--- Same string as GetGearPopulateSignature() but reuses tables already read in DrawGearTab / storage redraw (avoids a second GetEquippedGear and duplicate currency/upgrade DB reads when those tables are passed).
---@param gearData table|nil
---@param currencies table|nil
---@param upgradeInfo table|nil
---@return string|nil
function WarbandNexus:GetGearPopulateSignatureFromDrawCaches(gearData, currencies, upgradeInfo)
    _gearPopulateSigDepth = _gearPopulateSigDepth + 1
    local out
    if _gearPopulateSigDepth > 1 then
        out = ComputeGearPopulateSignatureCore(self, {}, {}, {}, gearData, currencies, upgradeInfo)
    else
        wipe(_gearSigParts)
        wipe(_gearSigCurBlob)
        wipe(_gearSigUpPieces)
        out = ComputeGearPopulateSignatureCore(self, _gearSigParts, _gearSigCurBlob, _gearSigUpPieces, gearData, currencies, upgradeInfo)
    end
    _gearPopulateSigDepth = _gearPopulateSigDepth - 1
    return out
end

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================

--- Phase timings for first-open / roster freezes: requires WN Trace visible or debug+verbose (ns.IsTabPerfMonitorEnabled).
local function ShouldLogGearOpenPhases()
    local P = ns.Profiler
    if P and P.IsUserTraceWindowShown and P:IsUserTraceWindowShown() then return true end
    if ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled() then return true end
    return false
end

local function AppendGearOpenTrace(msg)
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine(msg)
    end
end

function WarbandNexus:DrawGearTab(parent)
    -- Lazy-load FontManager if needed
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then return 0 end
    end

    -- Re-bind shared helpers (may not have been loaded at file parse time)
    if not COLORS then COLORS = ns.UI_COLORS end
    if not CreateCard then CreateCard = ns.UI_CreateCard end
    if not ApplyVisuals then ApplyVisuals = ns.UI_ApplyVisuals end
    if not GetQualityHex then GetQualityHex = ns.UI_GetQualityHex end
    if not FormatGold then FormatGold = ns.UI_FormatGold end
    if not FormatNumber then FormatNumber = ns.UI_FormatNumber end
    if not GEAR_SLOTS then GEAR_SLOTS = ns.GEAR_SLOTS end
    if not SLOT_BY_ID then SLOT_BY_ID = ns.SLOT_BY_ID end

    if not COLORS or not CreateCard or not FontManager then return 0 end

    local mfGearFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mfGearFrame)
    local fixedHeader = mfGearFrame and mfGearFrame.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or TOP_MARGIN
    local accent     = COLORS.accent

    -- ── Character selection ───────────────────────────────────────────────────
    local charKey = GetSelectedCharKey()

    -- Auto-validate: selected char might no longer be tracked
    if selectedCharKey then
        local db = self.db and self.db.global
        if not (db and db.characters and db.characters[selectedCharKey] and db.characters[selectedCharKey].isTracked) then
            selectedCharKey = nil
            charKey = GetSelectedCharKey()
        end
    end

    -- Standard: use canonical key (normalized) for all DB/service calls so currency, gear, gold match.
    local canonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey

    local allChars = GetTrackedCharacters()
    if #allChars == 0 then
        local mf0 = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mf0 then mf0._gearPopulateContentSig = nil end
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame then
            WarbandNexus.UI.mainFrame._gearStorageRecHost = nil
        end
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local height = DrawEmptyState and DrawEmptyState(
            parent,
            (ns.L and ns.L["GEAR_NO_TRACKED_CHARACTERS_TITLE"]) or "No tracked characters",
            (ns.L and ns.L["GEAR_NO_TRACKED_CHARACTERS_DESC"]) or "Log in to a character to start tracking gear."
        ) or 200
        return height
    end

    -- Invalidate in-flight storage deferrals when this tab redraws (char change, tab switch, PopulateContent).
    ns._gearTabDrawGen = (ns._gearTabDrawGen or 0) + 1
    local gearPaintGen = ns._gearTabDrawGen
    local mfGear = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfGear then
        mfGear._gearPendingStorageScan = nil
        mfGear._gearStorageTryStartScheduledFor = nil
        if mfGear._gearStorageScanningMinPaintTimer and mfGear._gearStorageScanningMinPaintTimer.Cancel then
            mfGear._gearStorageScanningMinPaintTimer:Cancel()
        end
        mfGear._gearStorageScanningMinPaintTimer = nil
        mfGear._gearStorageScanningShownAt = nil
    end
    ns._gearStorageDeferAwaiting = false
    ns._gearStorageDeferAwaitCanon = nil
    local deferScrollPaint = mfGear and mfGear._wnGearPaintShowVeil
    if deferScrollPaint then
        mfGear._wnGearPaintShowVeil = nil
        EnsureGearContentVeil(parent, mfGear, gearPaintGen)
        mfGear._gearDeferChainActive = true
    end
    if mfGear then
        mfGear._gearPopulateCanonKey = canonicalKey
        local prevView = mfGear._wnGearTraceLastCanon
        mfGear._wnGearTraceLastCanon = canonicalKey
        if prevView and prevView ~= canonicalKey then
            local P = ns.Profiler
            if P and P.AppendUserTraceLine then
                P:AppendUserTraceLine(string.format(
                    "[GearChar] roster view %s -> %s | drawGen=%s",
                    tostring(prevView),
                    tostring(canonicalKey),
                    tostring(gearPaintGen)))
            end
        end
    end

    local gearOpenLog = ShouldLogGearOpenPhases()
    local gearOpenAllT0 = gearOpenLog and debugprofilestop() or nil
    if gearOpenLog then
        AppendGearOpenTrace(string.format(
            "[WN Perf][GearOpen] begin gen=%s canon=%s",
            tostring(gearPaintGen),
            tostring(canonicalKey)))
    end

    local Pgear = ns.Profiler
    local profSlicesOn = Pgear and Pgear.enabled and Pgear.StartSlice and Pgear.StopSlice
    local function pGearSliceStart(n)
        if profSlicesOn then Pgear:StartSlice(Pgear.CAT.UI, n) end
    end
    local function pGearSliceStop(n)
        if profSlicesOn then Pgear:StopSlice(Pgear.CAT.UI, n) end
    end

    -- ── Header Card (in fixedHeader - non-scrolling) — Characters-tab layout + room for char selector ─────
    pGearSliceStart("Gear_headerCard")
    local r, g, b = accent[1], accent[2], accent[3]
    local hexAcc  = format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    local titleTextContent = "|cff" .. hexAcc .. ((ns.L and ns.L["GEAR_TAB_TITLE"]) or "Gear Management") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["GEAR_TAB_DESC"]) or "Equipped gear, upgrade analysis, and crest tracking"
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local gearHeaderRightReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        GEAR_CHAR_SELECTOR_WIDTH,
        GEAR_HIDE_FILTER_BUTTON_W,
    })) or (GEAR_CHAR_SELECTOR_WIDTH + GEAR_HIDE_FILTER_BUTTON_W + (tm.gap or 8))

    local headerCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "gear",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = gearHeaderRightReserve,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(headerCard, chrome)
    else
        headerCard:SetPoint("TOPLEFT",  SIDE_MARGIN, -headerYOffset)
        headerCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    end

    local gearCharSel = CreateCharacterSelector(headerCard, charKey, 0)
    local hideBtn = CreateGearHeaderHideButton(headerCard)
    local titleEdgeInset = tm.edgeInset or 0
    local hdrGap = tm.gap or 8
    if gearCharSel and ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(gearCharSel, headerCard, headerCard, "RIGHT", -titleEdgeInset)
    elseif gearCharSel then
        gearCharSel:SetPoint("RIGHT", headerCard, "RIGHT", -titleEdgeInset, 0)
    end
    if hideBtn and gearCharSel then
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(hideBtn, headerCard, gearCharSel, "LEFT", -hdrGap)
        else
            hideBtn:SetPoint("RIGHT", gearCharSel, "LEFT", -hdrGap, 0)
        end
    elseif hideBtn then
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(hideBtn, headerCard, headerCard, "RIGHT", -titleEdgeInset)
        else
            hideBtn:SetPoint("RIGHT", headerCard, "RIGHT", -titleEdgeInset, 0)
        end
    end
    headerCard:Show()
    if gearCharSel and gearCharSel._refreshGearCharColumns then
        C_Timer.After(0, function()
            if gearCharSel.GetParent and gearCharSel:GetParent() then
                gearCharSel._refreshGearCharColumns()
            end
        end)
    end

    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, headerCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mfGearFrame, headerYOffset) end
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    pGearSliceStop("Gear_headerCard")

    --- Scroll-body paint (data + paperdoll). When splitPaperDollToNextTick, DB reads run now, card draw next tick.
    local function paintGearScrollBody(splitPaperDollToNextTick)
    local yOffset = -TOP_MARGIN
    if gearOpenAllT0 then
        AppendGearOpenTrace(string.format(
            "[WN Perf][GearOpen] gen=%s enter scroll paint wall=%.2fms",
            tostring(gearPaintGen),
            debugprofilestop() - gearOpenAllT0))
    end
    local goT0 = gearOpenLog and debugprofilestop() or nil
    local goMark = goT0
    local function gearOpenStamp(phase)
        if not goT0 then return end
        local now = debugprofilestop()
        AppendGearOpenTrace(string.format(
            "[WN Perf][GearOpen] gen=%s | %s +%.2fms (body.cum %.2fms) split=%s",
            tostring(gearPaintGen),
            phase,
            now - goMark,
            now - goT0,
            tostring(splitPaperDollToNextTick == true)))
        goMark = now
    end
    if mfGear and not splitPaperDollToNextTick then
        mfGear._gearDeferChainActive = false
    end

    -- ── Data retrieval (all by canonical key) ──────────────────────────────────
    pGearSliceStart("Gear_dataSync")
    local db        = self.db and self.db.global
    local charData  = db and (db.characters[canonicalKey] or db.characters[charKey])
    local gearData  = (self.GetEquippedGear and self:GetEquippedGear(canonicalKey)) or nil

    local currentKey = (self.GetCurrentGearStorageKey and self:GetCurrentGearStorageKey())
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        or (ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey())

    if canonicalKey == currentKey and self.ScanEquippedGear then
        local slotsTbl = gearData and gearData.slots
        if not slotsTbl or not next(slotsTbl) then
            self:ScanEquippedGear()
            gearData = (self.GetEquippedGear and self:GetEquippedGear(canonicalKey)) or gearData
        end
    end

    gearOpenStamp("after_getEquipped+scanIfNeeded")

    pGearSliceStart("Gear_data_upgradeInfo")
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canonicalKey)) or {}
    pGearSliceStop("Gear_data_upgradeInfo")

    gearOpenStamp("after_upgradeInfo")

    -- Fetch currencies once; reuse for both affordability map and display panel
    pGearSliceStart("Gear_data_currencies")
    local currencies = (self.GetGearUpgradeCurrenciesFromDB and self:GetGearUpgradeCurrenciesFromDB(canonicalKey)) or {}
    local currencyAmounts = {}
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur and cur.currencyID ~= nil then
            local id = (type(cur.currencyID) == "number") and cur.currencyID or tonumber(cur.currencyID)
            local amt = (type(cur.amount) == "number") and cur.amount or tonumber(cur.amount)
            if id then currencyAmounts[id] = (amt and amt >= 0) and amt or 0 end
        end
    end
    pGearSliceStop("Gear_data_currencies")

    gearOpenStamp("after_currencies")

    -- Storage scan (optional): skipped when recommendations panel is disabled.
    pGearSliceStart("Gear_data_storageGate")
    local storageFindings = {}
    local storageScanPending = false
    if WarbandNexus:IsGearStorageRecommendationsEnabled() then
        local cachedHit = false
        if self.GetGearStorageFindingsIfCached then
            local findingsCached, hit = self:GetGearStorageFindingsIfCached(canonicalKey)
            if hit == true then
                cachedHit = true
                storageFindings = findingsCached or {}
            end
        end
        if not cachedHit then
            storageScanPending = true
            ns._gearStorageDeferAwaiting = true
            ns._gearStorageDeferAwaitCanon = canonicalKey
            if mfGear then
                mfGear._gearPendingStorageScan = {
                    canon = canonicalKey,
                    paintGen = gearPaintGen,
                }
            end
        elseif mfGear then
            mfGear._gearPendingStorageScan = nil
        end
    else
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        if mfGear then
            mfGear._gearPendingStorageScan = nil
            mfGear._gearDeferChainActive = false
        end
        if ns._gearStorageYieldCo then
            ns._gearStorageYieldCo = nil
            ns._gearStorageYieldFindCanon = nil
        end
    end

    pGearSliceStop("Gear_data_storageGate")
    if ns.WN_GEAR_STORAGE_PANEL_DEBUG and WarbandNexus:IsGearStorageRecommendationsEnabled() then
        local fs, fc = 0, 0
        for _, list in pairs(storageFindings) do
            fs = fs + 1
            if type(list) == "table" then
                fc = fc + #list
            end
        end
        local strictHit = false
        if self.GetGearStorageFindingsIfCached then
            local _, hit = self:GetGearStorageFindingsIfCached(canonicalKey)
            strictHit = (hit == true)
        end
        WarbandNexus:GearStoragePanelDebug(("DrawGear STASH GATE canon=%s strictCacheHit=%s scanPending=%s initialSlots=%d initialCandidates=%d paintGen=%s"):format(
            tostring(canonicalKey), tostring(strictHit), tostring(storageScanPending), fs, fc, tostring(gearPaintGen)))
    end
    pGearSliceStop("Gear_dataSync")

    gearOpenStamp("after_dataSync+storageGate")

    local function finishPaperDollAndSig()
        local tBlock = gearOpenLog and debugprofilestop() or nil
        pGearSliceStart("Gear_paperDollDraw")
        local tCard = gearOpenLog and debugprofilestop() or nil
        yOffset = ns.GearUI_DrawPaperDollCard(
            parent, yOffset, charData, gearData, upgradeInfo, canonicalKey, currencyAmounts,
            canonicalKey == currentKey, currencies, storageFindings, storageScanPending
        )
        if gearOpenLog and tCard then
            AppendGearOpenTrace(string.format(
                "[WN Perf][GearOpen] gen=%s DrawPaperDollCard %.2fms",
                tostring(gearPaintGen),
                debugprofilestop() - tCard))
        end
        pGearSliceStop("Gear_paperDollDraw")
        local outH = math.abs(yOffset) + TOP_MARGIN
        local mfOut = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        pGearSliceStart("Gear_populateSig")
        local tSig = gearOpenLog and debugprofilestop() or nil
        if mfOut and WarbandNexus.GetGearPopulateSignatureFromDrawCaches then
            mfOut._gearPopulateContentSig = WarbandNexus:GetGearPopulateSignatureFromDrawCaches(gearData, currencies, upgradeInfo)
        elseif mfOut and WarbandNexus.GetGearPopulateSignature then
            mfOut._gearPopulateContentSig = WarbandNexus:GetGearPopulateSignature()
        end
        if gearOpenLog and tSig then
            AppendGearOpenTrace(string.format(
                "[WN Perf][GearOpen] gen=%s populateSig %.2fms",
                tostring(gearPaintGen),
                debugprofilestop() - tSig))
        end
        pGearSliceStop("Gear_populateSig")
        if mfOut and ns.GearUI_RelayoutGearTabViewportFill then
            ns.GearUI_RelayoutGearTabViewportFill(mfOut)
            local fillCard = mfOut._gearPaperdollCard
            local lay = fillCard and fillCard._wnGearViewportLayout
            if fillCard and lay and lay.scrollYOffset and fillCard.GetHeight then
                outH = math.max(outH, math.abs(lay.scrollYOffset) + fillCard:GetHeight() + 12)
            end
        end
        if gearOpenLog and tBlock then
            AppendGearOpenTrace(string.format(
                "[WN Perf][GearOpen] gen=%s finishPaperDollAndSig %.2fms",
                tostring(gearPaintGen),
                debugprofilestop() - tBlock))
        end
        return outH
    end

    if splitPaperDollToNextTick and mfGear then
        mfGear._gearDeferChainActive = true
        C_Timer.After(0, function()
            if gearPaintGen ~= ns._gearTabDrawGen then
                mfGear._gearDeferChainActive = false
                TryDismissGearContentVeil(mfGear, gearPaintGen)
                return
            end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
                mfGear._gearDeferChainActive = false
                TryDismissGearContentVeil(mfGear, gearPaintGen)
                return
            end
            local outH = finishPaperDollAndSig()
            local sc = mfGear.scrollChild
            if sc and outH then
                if ns.UI_SyncMainTabScrollChrome then
                    ns.UI_SyncMainTabScrollChrome(mfGear, sc, outH)
                else
                    local pad = 8
                    local viewportH = GearResultsViewportHeight(mfGear)
                    sc:SetHeight(math.max(outH + pad, viewportH))
                end
            end
            if gearOpenAllT0 then
                AppendGearOpenTrace(string.format(
                    "[WN Perf][GearOpen] gen=%s TOTAL splitPaperDoll wall %.2fms",
                    tostring(gearPaintGen),
                    debugprofilestop() - gearOpenAllT0))
            end
        end)
        return GearResultsViewportHeight(mfGear)
    end

    local outSync = finishPaperDollAndSig()
    if gearOpenAllT0 then
        AppendGearOpenTrace(string.format(
            "[WN Perf][GearOpen] gen=%s TOTAL DrawGearTab wall %.2fms",
            tostring(gearPaintGen),
            debugprofilestop() - gearOpenAllT0))
    end
    return outSync
  end

    if deferScrollPaint and mfGear then
        C_Timer.After(0, function()
            if gearPaintGen ~= ns._gearTabDrawGen then
                mfGear._gearDeferChainActive = false
                TryDismissGearContentVeil(mfGear, gearPaintGen)
                return
            end
            if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
                mfGear._gearDeferChainActive = false
                TryDismissGearContentVeil(mfGear, gearPaintGen)
                return
            end
            paintGearScrollBody(true)
            if gearOpenAllT0 then
                AppendGearOpenTrace(string.format(
                    "[WN Perf][GearOpen] gen=%s TOTAL deferScrollPaint wall %.2fms",
                    tostring(gearPaintGen),
                    debugprofilestop() - gearOpenAllT0))
            end
        end)
        local scroll = mfGear.scroll
        local viewportH = scroll and scroll:GetHeight() or 0
        if viewportH < 2 and mfGear.fixedHeader and scroll then
            local fhBot = mfGear.fixedHeader:GetBottom()
            local sb = scroll:GetBottom()
            if fhBot and sb and fhBot > sb then
                viewportH = fhBot - sb
            end
        end
        if gearOpenAllT0 then
            AppendGearOpenTrace(string.format(
                "[WN Perf][GearOpen] gen=%s deferScrollPaint first return wall %.2fms (body paints next tick)",
                tostring(gearPaintGen),
                debugprofilestop() - gearOpenAllT0))
        end
        return math.max(viewportH, 480)
    end

    return paintGearScrollBody()
end

ns.UI_EnsureGearTabLoadingVeil = EnsureGearContentVeil
ns.UI_TryDismissGearTabLoadingVeil = TryDismissGearContentVeil
-- Runtime hooks for GearUI_Paperdoll.lua (loads before this file)
ns.GearUI_TryStartPendingGearStorageScan = TryStartPendingGearStorageScan
ns.GearUI_TryDismissGearContentVeil = TryDismissGearContentVeil
ns.GearUI_PaintGearStorageRowsBatched = PaintGearStorageRowsBatched
ns.GearUI_STORAGE_REC_TABLE_HDR = GEAR_STORAGE_REC_TABLE_HDR
ns.GearUI_GetCraftedIlvlRange = GetCraftedIlvlRange
ns.GearUI_CalculateAffordableUpgrades = CalculateAffordableUpgrades
ns.GearUI_IsPrimaryEnchantExpected = IsPrimaryEnchantExpected
ns.GearUI_GetItemIconSafe = GetItemIconSafe
ns.GearUI_BuildGearTabItemTooltipContext = BuildGearTabItemTooltipContext

