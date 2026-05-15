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

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants    = ns.Constants
local FontManager   = ns.FontManager

--- Tek merkez: Modules/FontManager.lua → FONT_ROLE
local function GFR(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local issecretvalue = issecretvalue

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

--- Locale helper (defined before first use; GetLocalizedText is declared later in this file).
local function GearTabL(key, fallback)
    local v = ns.L and ns.L[key]
    if type(v) == "string" and v ~= "" and v ~= key then
        return v
    end
    return fallback
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
    veil:SetScript("OnUpdate", nil)
    veil:Hide()
end

---@param mf Frame|nil
---@param gen number
local function TryDismissGearContentVeil(mf, gen)
    if not mf or gen ~= (ns._gearTabDrawGen or 0) then return end
    if ns._gearStorageDeferAwaiting or ns._gearStorageYieldCo then return end
    if (mf._gearDeferChainActive == true) then return end
    DismissGearContentVeil(mf, gen)
end

--- Start yielded storage scan after paperdoll defer chain (never same frame as DressUpModel / row paint).
---@param mf Frame|nil
---@param paintGen number
local function TryStartPendingGearStorageScan(mf, paintGen)
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        if mf then
            mf._gearPendingStorageScan = nil
        end
        return
    end
    if not mf then return end
    local pending = mf._gearPendingStorageScan
    if not pending or pending.paintGen ~= paintGen then
        if paintGen ~= (ns._gearTabDrawGen or 0) then
            return
        end
        -- Duplicate C_Timer(0): first TryStart cleared `pending` while a scan is still scheduled
        -- (sync Find + deferred applyStorageScanUI) or about to start. Never clear `_gearStorageDeferAwaiting`
        -- here — that orphans "Scanning storage…" with no follow-up Redraw.
        if ns._gearStorageYieldCo then
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
        return
    end
    local capCanon = pending.canon
    mf._gearPendingStorageScan = nil
    WarbandNexus:GearStorageTrace("TryStart pending storage scan canon=" .. tostring(capCanon) .. " paintGen=" .. tostring(paintGen))

    if paintGen ~= (ns._gearTabDrawGen or 0) then
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        TryDismissGearContentVeil(mf, paintGen)
        return
    end
    if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
        ns._gearStorageDeferAwaiting = false
        ns._gearStorageDeferAwaitCanon = nil
        TryDismissGearContentVeil(mf, paintGen)
        return
    end

    local selKey = GetSelectedCharKey and GetSelectedCharKey() or nil
    local selCanon = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(selKey) or selKey
    -- Pending canon can lag selection by a frame (dropdown → refresh). Dropping defer here used to orphan
    -- the in-scroll "Scanning storage…" line; re-queue for the current selection instead.
    if capCanon and selCanon ~= capCanon then
        WarbandNexus:GearStorageTrace("TryStart requeue (selection != pending cap) cap=" .. tostring(capCanon) .. " sel=" .. tostring(selCanon))
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
        selKey = GetSelectedCharKey and GetSelectedCharKey() or nil
        selCanon = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey) and ns.Utilities:GetCanonicalCharacterKey(selKey) or selKey
        if selCanon ~= capCanon then
            -- Scan finished for a character we are no longer viewing; do not touch defer (new paint owns it).
            WarbandNexus:GearStorageTrace("apply skip (selection changed) cap=" .. tostring(capCanon) .. " sel=" .. tostring(selCanon))
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
    local enchantableSlots = Constants and Constants.GEAR_ENCHANTABLE_SLOTS
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

--- Color-code upgrade-track tiers like item quality: Adventurer→common, Veteran→uncommon,
--- Champion→rare, Hero→epic, Myth→legendary. Returns hex (no #) or nil for unknown tiers.
local UPGRADE_TRACK_TIER_HEX = {
    Adventurer = "9d9d9d",
    Explorer   = "9d9d9d",
    Veteran    = "1eff00",
    Champion   = "0070dd",
    Hero       = "a335ee",
    Myth       = "ff8000",
}
local function GetUpgradeTrackHex(englishName)
    if not englishName or englishName == "" then return nil end
    local trimmed = englishName:match("^%s*(.-)%s*$") or englishName
    return UPGRADE_TRACK_TIER_HEX[trimmed]
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
local PAPERDOLL_SCALE = 1.10
local function P(n) return math.floor(n * PAPERDOLL_SCALE + 0.5) end
local SLOT_SIZE      = P(38)
local SLOT_GAP       = P(5)
local DOLL_PAD       = P(12)
local SLOT_TO_ARROW_GAP = P(4)   -- slot ile upgrade ikonu arası
local ARROW_TO_TEXT_GAP = P(6)   -- ok ile yazı arası boşluk (artık yaslamalı olduğu için pozitif olmalı)
local TRACK_TEXT_W   = P(136)  -- Track metin taşmasını engellemek için genişletildi
-- Paperdoll status: gem + enchant stacked on outer (track) side.
-- Increase (upgrade) / lock: small icon inside the item square, corner chosen per column so it stays visible
-- (center "toward model" sat under the 3D portrait sibling) and does not overlap the outer gem/enchant column.
local STATUS_OUTER_ICON = P(17)
local STATUS_UPGRADE_ICON = P(21)
local STATUS_UPGRADE_DRAW_MULT = 0.78
local STATUS_UPGRADE_BG_PAD = 3
local STATUS_HOST_GAP = P(4)
local STATUS_OUTER_GAP_V = P(3)
local STATUS_OUTER_COL_W = STATUS_OUTER_ICON
local STATUS_OUTER_COL_H = STATUS_OUTER_ICON + STATUS_OUTER_GAP_V + STATUS_OUTER_ICON
local STATUS_TEXT_WARD_W = STATUS_OUTER_COL_W
local STATUS_ICON_INSET = 1
-- DEBUG: show upgrade arrow on every occupied slot. Set false for release.
local GEAR_DEBUG_ALWAYS_SHOW_UPGRADE = false
-- Inline ilvl separator in recommendation FontStrings (Unicode → renders as tofu); same atlas as storage row ilvl arrow.
local GEAR_ILVL_ARROW_ATLAS = "common-dropdown-icon-play"
local GEAR_ILVL_ARROW_INLINE_SZ = 14
local GEAR_ILVL_ARROW_INLINE_MARKUP = (CreateAtlasMarkup and CreateAtlasMarkup(GEAR_ILVL_ARROW_ATLAS, GEAR_ILVL_ARROW_INLINE_SZ, GEAR_ILVL_ARROW_INLINE_SZ))
    or ("|A:" .. GEAR_ILVL_ARROW_ATLAS .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. ":" .. GEAR_ILVL_ARROW_INLINE_SZ .. "|a")
local CURRENCY_PANEL_W = 248
local GEAR_STAT_PANEL_W = 292
local CENTER_GAP     = P(10)
local CURRENCY_PAPERDOLL_GAP = 14  -- boşluk crest paneli ile paperdoll arası

-- Fixed panel widths: sol = yazı + ikon + slot, sağ = slot + ikon + yazı
local LEFT_PANEL_W   = TRACK_TEXT_W + ARROW_TO_TEXT_GAP + STATUS_TEXT_WARD_W + SLOT_TO_ARROW_GAP + SLOT_SIZE
local RIGHT_PANEL_W  = SLOT_SIZE + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + 2 + ARROW_TO_TEXT_GAP + TRACK_TEXT_W
local MODEL_W       = P(248)
-- Neutral center fill: Blizzard tooltip tile (FrameXML Backdrop — see warcraft.wiki.gg UIOBJECT Frame / Backdrop).
-- Avoids a flat ColorTexture “void” without class-specific art.
local GEAR_MODEL_PANEL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    tile = true,
    tileSize = 8,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}
-- Paperdoll blok genişliği (sol kolon + model + sağ kolon) — kart içinde ortalanır
local PAPERDOLL_BLOCK_W = LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP + RIGHT_PANEL_W

-- Gear tab: paperdoll column | narrow info column (stats then currencies) | recommendations (optional).
local GEAR_PANEL_GAP = 10
local MIN_GEAR_PANEL_W = PAPERDOLL_BLOCK_W
local GEAR_REC_COL_MIN_W = 218
local GEAR_MID_COL_MIN_W = 228
local GEAR_MID_COL_PREF_W = 340
local GEAR_PAPER_COL_W = PAPERDOLL_BLOCK_W + 8
-- Cross-character storage recommendations (FindGearStorageUpgrades) disabled: spikes on equip/bag events.
local GEAR_STORAGE_RECOMMENDATIONS_ENABLED = false
local MIN_CARD_INNER_W_WITH_REC = GEAR_PAPER_COL_W + GEAR_PANEL_GAP + GEAR_MID_COL_MIN_W + GEAR_PANEL_GAP + GEAR_REC_COL_MIN_W
local MIN_CARD_INNER_W_NO_REC = GEAR_PAPER_COL_W + GEAR_PANEL_GAP + GEAR_MID_COL_PREF_W

---@return boolean
function WarbandNexus:IsGearStorageRecommendationsEnabled()
    return GEAR_STORAGE_RECOMMENDATIONS_ENABLED == true
end

local function GetGearTabMinCardInnerW()
    if WarbandNexus:IsGearStorageRecommendationsEnabled() then
        return MIN_CARD_INNER_W_WITH_REC
    end
    return MIN_CARD_INNER_W_NO_REC
end

-- Minimum scrollChild width: daraldığında yatay scroll, elementler üst üste binmesin
local MIN_GEAR_CARD_W = 2 * (SIDE_MARGIN or 16) + 2 * 12 + GetGearTabMinCardInnerW()  -- 12 = CARD_PAD
ns.MIN_GEAR_CARD_W = MIN_GEAR_CARD_W  -- used by UI.lua for scrollChild width on gear tab

-- Ortadan çizgi hizalama: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ)
local SLOT_HALF      = SLOT_SIZE / 2
local TEXT_HALF_W   = TRACK_TEXT_W / 2
-- Slot merkezinden yazı bloğu merkezine uzaklık (px) — gem sütunu + boşluk + yazı yarım genişliği
local TEXT_OFFSET_FROM_SLOT_CENTER = SLOT_HALF + SLOT_TO_ARROW_GAP + STATUS_TEXT_WARD_W + ARROW_TO_TEXT_GAP + TEXT_HALF_W

-- Empty slot textures (standard WoW interface art)
local EMPTY_SLOT_TEXTURE = {
    [1]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Head",
    [2]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Neck",
    [3]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Shoulder",
    [5]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest",
    [6]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Waist",
    [7]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Legs",
    [8]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Feet",
    [9]  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Wrist",
    [10] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Hands",
    [11] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    [12] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    [13] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    [14] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    [15] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Back",
    [16] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-MainHand",
    [17] = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-SecondaryHand",
}

local SLOT_FALLBACK_TEXTURE = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Bag"

-- In-place paperdoll refresh: PLAYER_EQUIPMENT_CHANGED debounce may only list one slot of a swap pair.
local GEAR_REFRESH_PAIR_SLOTS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }
-- Paperdoll slot list for cache-warm repaints (GET_ITEM_INFO / metadata); stable table — no fresh {} in hot path.
local GEAR_PAPERDOLL_REFRESH_SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

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
    local events = Constants and Constants.EVENTS
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
            local map = Constants and Constants.CLASS_FILE_TO_CLASS_ID
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

--- Column header for the gear-tab storage recommendations table (symmetric columns).
local function PaintGearStorageRecColumnHeader(parent, contentW)
    if not parent or not FontManager then return end
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetSize(contentW, 22)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local function colFs(text, width, justify, xOff)
        local fs = FontManager:CreateFontString(hdr, GFR("gearStorageHdr"), "OVERLAY")
        fs:SetPoint("LEFT", hdr, "LEFT", xOff, 0)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.55, 0.58, 0.65)
        return fs
    end
    colFs((ns.L and ns.L["GEAR_REC_COL_SLOT"]) or "Slot", 72, "LEFT", 8)
    colFs((ns.L and ns.L["GEAR_REC_COL_ILVL"]) or "iLvl", 108, "LEFT", 88)
    colFs((ns.L and ns.L["GEAR_REC_COL_ITEM"]) or "Item", 120, "LEFT", 200)
    colFs((ns.L and ns.L["GEAR_REC_COL_SOURCE"]) or "Source", 100, "RIGHT", math.max(8, contentW - 108))
end

--- Paint one storage-upgrade row (symmetric table: slot | ilvl arrow | item | source).
local function PaintGearStorageRecommendationRow(line, index, rowH, contentW, rowData, itemTooltipContext, viewerClassFile)
    if not line then return end
    local parent = line:GetParent()
    if not parent then return end
    local innerH = math.max(1, rowH - 2)
    local yOff = -(index - 1) * rowH
    if index == 1 and parent._gearRecHasHeader then
        yOff = yOff - 22
    end
    line:SetSize(contentW, innerH)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
    line:EnableMouse(true)
    if ns.UI.Factory and ns.UI.Factory.ApplyRowBackground then
        ns.UI.Factory:ApplyRowBackground(line, index)
    end
    if line.qtyText then line.qtyText:Hide() end
    if line.nameText then line.nameText:Hide() end
    if line.locationText then line.locationText:Hide() end

    local slotText = line.slotText
    if not slotText and FontManager then
        slotText = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.slotText = slotText
    end
    if slotText then
        slotText:Show()
        slotText:SetPoint("LEFT", line, "LEFT", 8, 0)
        slotText:SetWidth(72)
        slotText:SetJustifyH("LEFT")
        slotText:SetText(rowData.slotName or "Slot")
        slotText:SetTextColor(0.95, 0.95, 1)
    end

    local currIlvlText = line.currIlvlText
    if not currIlvlText and FontManager then
        currIlvlText = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.currIlvlText = currIlvlText
    end
    if currIlvlText then
        currIlvlText:Show()
        currIlvlText:SetPoint("LEFT", line, "LEFT", 88, 0)
        currIlvlText:SetWidth(36)
        currIlvlText:SetJustifyH("RIGHT")
        currIlvlText:SetText(tostring(rowData.currentIlvl or 0))
        currIlvlText:SetTextColor(0.75, 0.75, 0.8)
    end

    local arrowTex = line.arrowTex
    if not arrowTex then
        arrowTex = line:CreateTexture(nil, "ARTWORK")
        line.arrowTex = arrowTex
    end
    arrowTex:Show()
    arrowTex:SetSize(12, 12)
    arrowTex:SetPoint("LEFT", line, "LEFT", 128, 0)
    if arrowTex.SetAtlas then
        arrowTex:SetAtlas("common-dropdown-icon-play", true)
    else
        arrowTex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        arrowTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        arrowTex:SetVertexColor(0.3, 1, 0.4)
    end

    local targetIlvlText = line.targetIlvlText
    if not targetIlvlText and FontManager then
        targetIlvlText = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.targetIlvlText = targetIlvlText
    end
    if targetIlvlText then
        targetIlvlText:Show()
        targetIlvlText:SetPoint("LEFT", arrowTex, "RIGHT", 4, 0)
        targetIlvlText:SetWidth(36)
        targetIlvlText:SetJustifyH("LEFT")
        targetIlvlText:SetText(tostring(rowData.targetIlvl or 0))
        targetIlvlText:SetTextColor(0.4, 1, 0.5)
    end

    local delta = (rowData.targetIlvl or 0) - (rowData.currentIlvl or 0)
    local deltaText = line.deltaText
    if not deltaText and FontManager then
        deltaText = FontManager:CreateFontString(line, GFR("gearStorageRow"), "OVERLAY")
        line.deltaText = deltaText
    end
    if deltaText then
        deltaText:Show()
        deltaText:SetPoint("LEFT", targetIlvlText, "RIGHT", 4, 0)
        deltaText:SetWidth(32)
        deltaText:SetJustifyH("LEFT")
        deltaText:SetText(delta > 0 and ("+" .. tostring(delta)) or "")
        deltaText:SetTextColor(0.35, 0.9, 0.45)
    end

    local itemIcon = line.icon
    if not itemIcon then
        itemIcon = line:CreateTexture(nil, "ARTWORK")
        line.icon = itemIcon
    end
    itemIcon:Show()
    itemIcon:SetSize(22, 22)
    itemIcon:SetPoint("LEFT", line, "LEFT", 200, 0)
    local icon = rowData.itemLink and GetItemIconSafe(rowData.itemLink) or GetItemIconSafe(rowData.itemID)
    itemIcon:SetTexture(icon or 134400)
    itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local sourceText = line.sourceText
    if not sourceText and FontManager then
        sourceText = FontManager:CreateFontString(line, GFR("gearStorageSource"), "OVERLAY")
        line.sourceText = sourceText
    end
    if sourceText then
        sourceText:Show()
        sourceText:SetPoint("RIGHT", line, "RIGHT", -8, 0)
        sourceText:SetPoint("LEFT", itemIcon, "RIGHT", 8, 0)
        sourceText:SetJustifyH("RIGHT")
        local srcDisplay = FormatStorageSourceDisplay(rowData.source or "", rowData.sourceClassFile, viewerClassFile)
        sourceText:SetText(srcDisplay ~= "" and srcDisplay or (rowData.source or ""))
        sourceText:SetTextColor(0.75, 0.78, 0.85)
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

local GEAR_STORAGE_ROWS_PER_FRAME = 8

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
            C_Timer.After(0, paintChunk)
        else
            if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
            end
            if recScroll and recScroll.SetVerticalScroll then
                recScroll:SetVerticalScroll(0)
            end
            if onComplete then onComplete() end
        end
    end
    paintChunk()
end

local function ShowGearStorageScanningInRecContent(recContent)
    if not recContent then return end
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
local function ItemLinkHasEnchantment(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return false end
    if issecretvalue and issecretvalue(itemLink) then return false end
    local segment = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:[^|]+)|h") or itemLink
    local body = segment:match("^item:(.+)$") or segment
    local _, enc = body:match("^(%d+):([^:]*):")
    if not _ then
        _, enc = body:match("^(%d+):([^:]*)$")
    end
    if enc and enc ~= "" then
        local e = tonumber(enc)
        if e and e > 0 then return true end
    end
    return false
end

--- Enchant spell id from item hyperlink payload (same field as ItemLinkHasEnchantment).
local function GetItemHyperlinkEnchantmentId(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if issecretvalue and issecretvalue(itemLink) then return nil end
    local segment = itemLink:match("|H(item:[^|]+)|h") or itemLink:match("(item:[^|]+)|h") or itemLink
    local body = segment:match("^item:(.+)$") or segment
    local _, enc = body:match("^(%d+):([^:]*):")
    if not _ then
        _, enc = body:match("^(%d+):([^:]*)$")
    end
    if not enc or enc == "" then return nil end
    local e = tonumber(enc)
    if e and e > 0 then return e end
    return nil
end

local function ResolveGearSpellName(spellID)
    if not spellID or spellID <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            return name
        end
    end
    return nil
end

--- Permanent enchant row tier from C_TooltipInfo (same source as Blizzard “Enchanted:” glyph).
--- Item:GetCraftingQuality() is the base item’s craft tier — wrong when enchant rank differs (e.g. R2 enchant on R1 item).
---@param itemLink string|nil
---@return number|nil 1–3 for display, or nil if unknown
local function GetGearSlotEnchantQualityTier(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end
    if not GetEnchantmentCraftingQualityTierFromItemLink then return nil end
    local q = GetEnchantmentCraftingQualityTierFromItemLink(itemLink)
    q = tonumber(q)
    if q and q >= 1 then return q end
    return nil
end

--- Apply profession crafting-quality atlas or engraving fallback.
local function SetupGearSlotEnchantQualityTexture(tex, tierIdx, pixelSize)
    if not tex then return false end
    local tier = tonumber(tierIdx) or 1
    if tier < 1 then tier = 1 end
    local sz = tonumber(pixelSize) or GEAR_ENCHANT_QUALITY_SZ
    if sz < 10 then sz = 10 end
    if ApplyProfessionCraftingQualityAtlasToTexture and ApplyProfessionCraftingQualityAtlasToTexture(tex, tier, sz) then
        return true
    end
    tex:SetTexture("Interface\\Icons\\Trade_Engraving")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(0.82, 0.76, 1.0, 0.92)
    tex:SetSize(sz, sz)
    tex:Show()
    return true
end

-- Per-socket gem / empty-socket art on paperdoll (C_Item.GetItemNumSockets / GetItemGem; warcraft.wiki.gg API pages 12.0.1).
local MAX_GEAR_ITEM_SOCKETS = 6
local GEAR_SOCKET_GEM_PX = P(14)
local GEAR_SOCKET_GEM_GAP = 2
-- Blizzard socket art (backslashes; matches FrameXML conventions).
local EMPTY_SOCKET_TEX_BY_SUFFIX = {
    META = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Hydraulic",
    RED = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Red",
    YELLOW = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Yellow",
    BLUE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Blue",
    PRISMATIC = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
    HYDRAULIC = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Hydraulic",
    COGWHEEL = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Cogwheel",
    DOMINATION = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
}
local EMPTY_SOCKET_TEX_DEFAULT = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"

local function CollectEmptySocketSuffixesFromStats(stats)
    local list = {}
    if not stats then return list end
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k))
            and string.find(k, "EMPTY_SOCKET_", 1, true) then
            local suf = string.match(k, "^EMPTY_SOCKET_(.+)$") or "PRISMATIC"
            local c = tonumber(v)
            if not c or c < 1 then c = 1 end
            for j = 1, c do
                if EMPTY_SOCKET_TEX_BY_SUFFIX[suf] then
                    list[#list + 1] = suf
                else
                    list[#list + 1] = "PRISMATIC"
                end
            end
        end
    end
    return list
end

local function GetGearGemIconTexture(gemLink)
    if not gemLink or type(gemLink) ~= "string" or (issecretvalue and issecretvalue(gemLink)) then
        return nil
    end
    local ic = GetItemIconSafe(gemLink)
    if ic and ic ~= 0 and ic ~= "" then return ic end
    local id = nil
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            id = C_Item.GetItemInfoInstant(gemLink)
        end
    end)
    if not id then
        local m = gemLink:match("item:(%d+)")
        id = m and tonumber(m) or nil
    end
    if id and C_Item and C_Item.GetItemIconByID then
        local ok, r = pcall(C_Item.GetItemIconByID, id)
        if ok and r and r ~= 0 and r ~= "" then return r end
    end
    if id and GetItemIcon then
        local ok, r = pcall(GetItemIcon, id)
        if ok and r and r ~= 0 and r ~= "" then return r end
    end
    return "Interface\\Icons\\INV_Misc_Gem_01"
end

-- Gem per socket: C_Item.GetItemGem / GetItemGem return (name, itemLink) — second value is the hyperlink (warcraft.wiki.gg API pages).
local function GetItemGemForSocket(itemLink, socketIndex)
    if not itemLink or not socketIndex then return nil end
    local gemName, gemLink
    local ok, a, b = pcall(function()
        if C_Item and C_Item.GetItemGem then
            return C_Item.GetItemGem(itemLink, socketIndex)
        end
    end)
    if ok then
        gemName, gemLink = a, b
    end
    if gemLink and type(gemLink) == "string" and gemLink ~= "" and not (issecretvalue and issecretvalue(gemLink)) then
        return gemLink
    end
    if GetItemGem then
        ok, a, b = pcall(GetItemGem, itemLink, socketIndex)
        if ok and b and type(b) == "string" and b ~= "" and not (issecretvalue and issecretvalue(b)) then
            return b
        end
    end
    return nil
end

---@param itemLink string
---@param slotID number|nil
---@param useLiveSlot boolean|nil When true, retry C_Item.GetItemNumSockets(ItemLocation) for equipped item.
---@return table entries { { gemLink = string|nil, emptyTexture = string }, ... }
---@return string sig Dedupe signature for GearSlotPaperdollVisualEquals
local function ComputeGearSocketLayout(itemLink, slotID, useLiveSlot)
    local entries = {}
    if not itemLink or type(itemLink) ~= "string" or (issecretvalue and issecretvalue(itemLink)) then
        return entries, ""
    end
    local n = 0
    pcall(function()
        if C_Item and C_Item.GetItemNumSockets then
            n = tonumber(C_Item.GetItemNumSockets(itemLink)) or 0
        end
    end)
    if (not n or n <= 0) and useLiveSlot and slotID and ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetItemNumSockets then
        pcall(function()
            local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
            if loc and loc:IsValid() then
                n = tonumber(C_Item.GetItemNumSockets(loc)) or 0
            end
        end)
    end
    local stats = (GetItemStats and GetItemStats(itemLink)) or {}
    local emptyFromStats = 0
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k)) and string.find(k, "EMPTY_SOCKET_", 1, true) then
            local c = tonumber(v)
            if not c or c < 1 then c = 1 end
            emptyFromStats = emptyFromStats + c
        end
    end
    local maxGemIdx = 0
    for i = 1, MAX_GEAR_ITEM_SOCKETS do
        local g = GetItemGemForSocket(itemLink, i)
        if g then maxGemIdx = i end
    end
    if (not n or n <= 0) then
        n = math.max(emptyFromStats, maxGemIdx, (emptyFromStats > 0 or maxGemIdx > 0) and (emptyFromStats + maxGemIdx) or 0)
    end
    if n > MAX_GEAR_ITEM_SOCKETS then n = MAX_GEAR_ITEM_SOCKETS end
    if n <= 0 then return entries, "" end

    local emptySuffixQueue = CollectEmptySocketSuffixesFromStats(stats)
    local eq = 1

    local sigParts = {}
    for i = 1, n do
        local gem = GetItemGemForSocket(itemLink, i)
        if gem then
            local id = nil
            pcall(function()
                if C_Item and C_Item.GetItemInfoInstant then
                    id = C_Item.GetItemInfoInstant(gem)
                end
            end)
            if not id and not (issecretvalue and issecretvalue(gem)) then
                local m = gem:match("item:(%d+)")
                id = m and tonumber(m) or nil
            end
            entries[#entries + 1] = { gemLink = gem, emptyTexture = nil }
            sigParts[#sigParts + 1] = "g" .. tostring(id or 0)
        else
            local suf = emptySuffixQueue[eq]
            eq = eq + 1
            local tex = (suf and EMPTY_SOCKET_TEX_BY_SUFFIX[suf]) or EMPTY_SOCKET_TEX_DEFAULT
            entries[#entries + 1] = { gemLink = nil, emptyTexture = tex }
            sigParts[#sigParts + 1] = "e" .. tostring(i) .. ":" .. tostring(suf or "p")
        end
    end
    return entries, table.concat(sigParts, ":")
end

local function PlaceGearSocketClusterInSlotBottom(btn, cluster)
    if not btn or not cluster then return end
    cluster:ClearAllPoints()
    local anchor = btn.iconTex or btn
    cluster:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 5)
end

local function HideGearSocketCluster(btn)
    local c = btn and btn._gearSocketCluster
    if c then c:Hide() end
end

--- Layout mode for paperdoll flanks: left column + main hand vs right column + off-hand.
local function GetGearStatusLayoutMode(side)
    if side == "left" or side == "bottom" or side == "bottom_left" then
        return "left"
    end
    if side == "right" or side == "bottom_right" then
        return "right"
    end
    return "left"
end

local function EnsureGearOuterSideHost(btn)
    if not btn._gearOuterSideHost then
        local outer = CreateFrame("Frame", nil, btn)
        outer:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 2)
        local gemCell = CreateFrame("Frame", nil, outer)
        local encCell = CreateFrame("Frame", nil, outer)
        outer._gemCell = gemCell
        outer._encCell = encCell
        btn._gearOuterSideHost = outer
    end
    return btn._gearOuterSideHost
end

--- Outer column: gem + enchant stacked when both; single cell vertically centered when only one.
local function ApplyGearOuterSideCellLayout(outer, gemCell, encCell, hasGem, hasEnc)
    gemCell:ClearAllPoints()
    encCell:ClearAllPoints()
    if hasGem and hasEnc then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_COL_H)
        gemCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
        gemCell:SetPoint("TOPRIGHT", outer, "TOPRIGHT", 0, 0)
        encCell:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 0, 0)
        encCell:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", 0, 0)
        gemCell:Show()
        encCell:Show()
    elseif hasGem then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        gemCell:SetPoint("CENTER", outer, "CENTER", 0, 0)
        gemCell:Show()
        encCell:SetSize(1, 1)
        encCell:Hide()
    elseif hasEnc then
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_ICON)
        encCell:SetPoint("CENTER", outer, "CENTER", 0, 0)
        encCell:Show()
        gemCell:SetSize(1, 1)
        gemCell:Hide()
    else
        outer:SetSize(STATUS_OUTER_COL_W, STATUS_OUTER_COL_H)
        gemCell:SetSize(1, 1)
        encCell:SetSize(1, 1)
        gemCell:Hide()
        encCell:Hide()
    end
end

--- Gem/enchant on outer (track) side; mirrored for right column.
local function PlaceGearOuterSideHost(btn, side, hasGem, hasEnc)
    local icon = btn.iconTex or btn
    local mode = GetGearStatusLayoutMode(side)
    local outer = EnsureGearOuterSideHost(btn)
    local gemCell = outer._gemCell
    local encCell = outer._encCell
    outer:ClearAllPoints()
    ApplyGearOuterSideCellLayout(outer, gemCell, encCell, hasGem, hasEnc)
    local cx = (mode == "left") and -(SLOT_HALF + STATUS_HOST_GAP + STATUS_OUTER_COL_W / 2)
        or (SLOT_HALF + STATUS_HOST_GAP + STATUS_OUTER_COL_W / 2)
    outer:SetPoint("CENTER", icon, "CENTER", cx, 0)
    return outer, gemCell, encCell
end

--- Upgrade (optional dark backing + arrow) and/or lock: inside item icon corner away from center column.
--- Backing improves contrast on green item icons; gem/enchant stay on PlaceGearOuterSideHost.
local function PlaceGearUpgradeLockTowardModel(btn, icon, side, upgradeArrowBg, upgradeArrow, lockIcon)
    if not icon then return end
    local baseSz = STATUS_UPGRADE_ICON - 2 * STATUS_ICON_INSET
    local uSz = math.max(10, math.floor(baseSz * STATUS_UPGRADE_DRAW_MULT + 0.5))
    local inset = math.max(1, math.floor(STATUS_ICON_INSET + 0.5))
    local yInset = -inset
    local bgPad = STATUS_UPGRADE_BG_PAD
    local bgSz = uSz + 2 * bgPad

    local function cornerBG(tex, sz)
        if not tex then return end
        tex:SetSize(sz, sz)
        tex:ClearAllPoints()
        if side == "left" or side == "bottom_left" then
            tex:SetPoint("TOPLEFT", icon, "TOPLEFT", inset - 1, yInset + 1)
        elseif side == "right" or side == "bottom_right" then
            tex:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset + 1, yInset + 1)
        else
            tex:SetPoint("TOP", icon, "TOP", 0, yInset + 1)
        end
    end

    if upgradeArrow then
        if upgradeArrowBg then
            cornerBG(upgradeArrowBg, bgSz)
        end
        upgradeArrow:SetSize(uSz, uSz)
        upgradeArrow:ClearAllPoints()
        if upgradeArrowBg then
            upgradeArrow:SetPoint("CENTER", upgradeArrowBg, "CENTER", 0, 0)
        elseif side == "left" or side == "bottom_left" then
            upgradeArrow:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            upgradeArrow:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        else
            upgradeArrow:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end

    if lockIcon then
        local lockSz = math.max(12, math.floor(baseSz * 0.88 + 0.5))
        lockIcon:SetSize(lockSz, lockSz)
        lockIcon:ClearAllPoints()
        if side == "left" or side == "bottom_left" then
            lockIcon:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, yInset)
        elseif side == "right" or side == "bottom_right" then
            lockIcon:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -inset, yInset)
        else
            lockIcon:SetPoint("TOP", icon, "TOP", 0, yInset)
        end
    end
end

local function GearSlotClearPaperdollOverlays(btn)
    if not btn then return end
    HideGearSocketCluster(btn)
    if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
    if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    if btn.missingGemIcon then btn.missingGemIcon:Hide() end
    if btn._gearOuterSideHost then btn._gearOuterSideHost:Hide() end
    if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Hide() end
    if btn.warnIcon then btn.warnIcon:Hide() end
end

local function UpdateGearSocketCluster(btn, entries, opts)
    opts = opts or {}
    if not btn then return end
    if not entries or #entries == 0 then
        HideGearSocketCluster(btn)
        return
    end
    local gemPx = tonumber(opts.gemPx)
    local gemGap = tonumber(opts.gemGap)
    if gemGap == nil then
        gemGap = opts.anchorCell and 0 or GEAR_SOCKET_GEM_GAP
    end
    if not gemPx and opts.anchorCell then
        local capW = STATUS_OUTER_COL_W
        local n = #entries
        if n > 0 then
            gemPx = math.floor((capW - math.max(0, n - 1) * gemGap) / n)
            if gemPx < 8 then gemPx = 8 end
            if gemPx > capW - 2 then gemPx = math.max(8, capW - 2) end
        else
            gemPx = GEAR_SOCKET_GEM_PX
        end
    elseif not gemPx then
        gemPx = GEAR_SOCKET_GEM_PX
    end
    if gemPx < 6 then gemPx = 6 end
    if not btn._gearSocketCluster then
        local f = CreateFrame("Frame", nil, btn)
        f:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 3)
        btn._gearSocketCluster = f
        f._gemTex = {}
    end
    local f = btn._gearSocketCluster
    local gems = f._gemTex
    local n = #entries
    local w = n * gemPx + math.max(0, n - 1) * gemGap
    f:SetSize(w, gemPx)
    for i = 1, MAX_GEAR_ITEM_SOCKETS do
        local t = gems[i]
        if i <= n then
            if not t then
                t = f:CreateTexture(nil, "OVERLAY", nil, 7)
                gems[i] = t
                t:SetSize(gemPx, gemPx)
            else
                t:SetSize(gemPx, gemPx)
            end
            local e = entries[i]
            if e and e.gemLink then
                local ic = GetGearGemIconTexture(e.gemLink)
                if ic then
                    if type(ic) == "number" then
                        t:SetTexture(ic)
                    else
                        t:SetTexture(ic)
                    end
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                else
                    t:SetTexture("Interface\\Icons\\INV_Misc_Gem_01")
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            else
                local texPath = (e and e.emptyTexture) or EMPTY_SOCKET_TEX_DEFAULT
                t:SetTexture(texPath)
                t:SetTexCoord(0, 1, 0, 1)
            end
            t:ClearAllPoints()
            local x0 = (i - 1) * (gemPx + gemGap)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0)
            t:Show()
        elseif t then
            t:Hide()
        end
    end
    f:Show()
    f:ClearAllPoints()
    if opts.anchorCell then
        f:SetPoint("CENTER", opts.anchorCell, "CENTER", 0, 0)
    else
        PlaceGearSocketClusterInSlotBottom(btn, f)
    end
end

--- GetItemStats + socket scan per slot is expensive when multiplied by ~16 slots on Gear first paint.
--- Run once on the next frame (WN-PERF heavy tab first paint).
local function GearSlotApplyDeferredEnchantGemInspect(btn)
    if not btn then return end
    local slotData = btn._slotDataRef
    local slotID = btn._slotID
    local st = btn._gearInspectSt
    local ctx = btn._gearLayoutCtx
    if not slotData or not slotData.itemLink or not st or not ctx then
        GearSlotClearPaperdollOverlays(btn)
        return
    end
    local link = slotData.itemLink
    if issecretvalue and issecretvalue(link) then
        st.socketEntries = nil
        st.socketSig = ""
        st.ready = true
        GearSlotClearPaperdollOverlays(btn)
        return
    end

    st.hasEnchant = ItemLinkHasEnchantment(link)
    local stats = GetItemStats and GetItemStats(link) or {}
    st.isMissingGem = false
    for k, v in pairs(stats) do
        if type(k) == "string" and not (issecretvalue and issecretvalue(k)) and string.find(k, "EMPTY_SOCKET_", 1, true) then
            st.isMissingGem = true
            break
        end
    end
    st.isEnchantable = IsPrimaryEnchantExpected(slotID, slotData)
    st.craftingQualityTier = GetGearSlotEnchantQualityTier(link)

    local sockEntries, sockSig = ComputeGearSocketLayout(link, slotID, btn._gearIsCurrentChar == true)
    st.socketEntries = sockEntries
    st.socketSig = sockSig or ""

    local hasEnchant = st.hasEnchant
    local isMissingGem = st.isMissingGem
    local isEnchantable = st.isEnchantable
    local showSocketRow = sockEntries and #sockEntries > 0
    local showEnchantQuality = hasEnchant
    local missEnchant = isEnchantable and not hasEnchant
    local craftingQualityTier = st.craftingQualityTier
    local enchantDisplayTier = tonumber(craftingQualityTier) or 1
    if enchantDisplayTier < 1 then enchantDisplayTier = 1 end

    local side = ctx.side
    local upgradeArrow = ctx.upgradeArrow
    local lockIcon = btn._gearLockIcon
    local icon = btn.iconTex or btn

    local showGemHost = showSocketRow or isMissingGem
    local showEnchantHost = showEnchantQuality or missEnchant

    local outer, gemHost, encHost = PlaceGearOuterSideHost(btn, side, showGemHost, showEnchantHost)
    local inner = STATUS_OUTER_ICON - 2 * STATUS_ICON_INSET
    PlaceGearUpgradeLockTowardModel(btn, icon, side, btn._gearUpgradeArrowBg, upgradeArrow, lockIcon)

    if showGemHost or showEnchantHost then
        outer:Show()
    else
        outer:Hide()
    end

    local encSz = inner
    if showEnchantQuality then
        if not btn.enchantQualityIcon then
            local eqTex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.enchantQualityIcon = eqTex
        end
        SetupGearSlotEnchantQualityTexture(btn.enchantQualityIcon, enchantDisplayTier, encSz)
        btn.enchantQualityIcon:ClearAllPoints()
        btn.enchantQualityIcon:SetPoint("CENTER", encHost, "CENTER", 0, 0)
        btn.enchantQualityIcon:Show()
        if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    elseif missEnchant then
        if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
        if not btn.missingEnchantIcon then
            local ic = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.missingEnchantIcon = ic
        end
        btn.missingEnchantIcon:SetSize(inner, inner)
        btn.missingEnchantIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        btn.missingEnchantIcon:ClearAllPoints()
        btn.missingEnchantIcon:SetPoint("CENTER", encHost, "CENTER", 0, 0)
        btn.missingEnchantIcon:Show()
    else
        if btn.enchantQualityIcon then btn.enchantQualityIcon:Hide() end
        if btn.missingEnchantIcon then btn.missingEnchantIcon:Hide() end
    end

    if showSocketRow then
        if btn.missingGemIcon then btn.missingGemIcon:Hide() end
        UpdateGearSocketCluster(btn, st.socketEntries, {
            anchorCell = gemHost,
        })
    elseif isMissingGem then
        HideGearSocketCluster(btn)
        if not btn.missingGemIcon then
            local ic = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            btn.missingGemIcon = ic
        end
        btn.missingGemIcon:SetSize(inner, inner)
        btn.missingGemIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        btn.missingGemIcon:ClearAllPoints()
        btn.missingGemIcon:SetPoint("CENTER", gemHost, "CENTER", 0, 0)
        btn.missingGemIcon:Show()
    else
        HideGearSocketCluster(btn)
        if btn.missingGemIcon then btn.missingGemIcon:Hide() end
    end

    if GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and upgradeArrow and link then
        upgradeArrow:Show()
        if btn._gearUpgradeArrowBg then btn._gearUpgradeArrowBg:Show() end
    end

    st.ready = true
end

-- ============================================================================
-- SLOT ICON BUTTON
-- ============================================================================

--- Create a single equipment slot icon button.
---@param parent Frame
---@param slotID number
---@param slotData table|nil  { itemLink, itemLevel, quality, name, ... }
---@param x number x offset from parent TOPLEFT
---@param y number y offset (negative = downward) from parent TOPLEFT
---@param hasUpgradePath boolean|nil if true, show upgrade arrow (next tier exists; may tint when unaffordable)
---@param statusText string|nil e.g. "Veteran 6/6", "Champion 4/8", or nil to show ilvl/"—"
---@param textSide string|nil "right" | "left" | "top" — where to place status text relative to icon
---@param isNotUpgradeable boolean|nil if true, show a lock icon overlay (item confirmed not upgradeable)
---@param centerTextOnIcon boolean|nil if true, center slot name + track text relative to slot icon (weapon row)
---@param upgradeInfo table|nil optional; when set, tooltip shows next upgrade tier and cost for this slot
---@param currencyAmounts table|nil optional; map currencyID -> amount (for "you have X" in tooltip if needed)
---@param itemTooltipContext table|nil optional { level, specID } — rewrite item link for C_TooltipInfo primary-stat lines (Gear tab / viewed character)
---@param charKey string|nil canonical character key for persisted upgrade tooltip append
---@param isCurrentChar boolean|nil live player — enables tooltip scan fallback in GearService
---@return Frame btn
local function CreateSlotButton(parent, slotID, slotData, x, y, hasUpgradePath, statusText, textSide, isNotUpgradeable, textWidth, centerTextOnIcon, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    -- Slot her zaman aynı boyutta; ikon görünmese bile boşluk rezerve (empty texture)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SLOT_SIZE, SLOT_SIZE)
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
    if parent then
        parent._gearSlotInspectList = parent._gearSlotInspectList or {}
        tinsert(parent._gearSlotInspectList, btn)
    end

    -- Outer border frame (quality color rim)
    local borderFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    borderFrame:SetAllPoints()
    borderFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn.borderFrame = borderFrame

    -- Dark background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.9)

    -- Item / empty slot texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.iconTex = tex

    -- ilvl label (bottom-right overlay); font must be set before any SetText (WoW requirement)
    local ilvlLabel = btn:CreateFontString(nil, "OVERLAY")
    ilvlLabel:SetPoint("BOTTOMRIGHT", -2, 2)
    ilvlLabel:SetFontObject(SystemFont_Tiny)  -- ensure font set before Populate() ever calls SetText
    if FontManager and FontManager.CreateFontString then
        local fs = FontManager:CreateFontString(btn, GFR("gearSlotIlvl"), "OVERLAY")
        if fs and fs.SetFontObject then
            fs:SetPoint("BOTTOMRIGHT", -2, 2)
            fs:SetJustifyH("RIGHT")
            if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
            btn.ilvlLabel = fs
            ilvlLabel:SetAlpha(0)
        else
            btn.ilvlLabel = ilvlLabel
        end
    else
        btn.ilvlLabel = ilvlLabel
        if ilvlLabel.SetDrawLayer then ilvlLabel:SetDrawLayer("OVERLAY", 7) end
    end

    -- Populate with item or empty slot art
    local function Populate(data)
        if data and data.itemLink then
            local icon = GetItemIconSafe(data.itemLink) or GetItemIconSafe(data.itemID)
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

            -- Quality border color
            local q = data.quality or 0
            local r, g, b = GetItemQualityColor(q)
            borderFrame:SetBackdropBorderColor(r or 0.4, g or 0.4, b or 0.4, 1)

            -- ilvl label (only when slot has an item link and valid ilvl)
            if btn.ilvlLabel and data.itemLink and data.itemLevel and data.itemLevel > 0 then
                btn.ilvlLabel:SetText(data.itemLevel)
                btn.ilvlLabel:SetTextColor(1, 1, 1)
                btn.ilvlLabel:SetShadowOffset(1, -1)
                btn.ilvlLabel:SetShadowColor(0, 0, 0, 1)
                btn.ilvlLabel:Show()
            elseif btn.ilvlLabel then
                btn.ilvlLabel:Hide()
            end
        else
            -- Empty slot
            tex:SetTexture(EMPTY_SLOT_TEXTURE[slotID] or SLOT_FALLBACK_TEXTURE)
            tex:SetTexCoord(0, 1, 0, 1)
            local accent = COLORS and COLORS.accent or { 0.5, 0.3, 0.8 }
            borderFrame:SetBackdropBorderColor(accent[1] * 0.4, accent[2] * 0.4, accent[3] * 0.4, 0.5)
            if btn.ilvlLabel then btn.ilvlLabel:Hide() end
            GearSlotClearPaperdollOverlays(btn)
        end
    end

    Populate(slotData)

    local side = textSide or "right"
    local upgradeArrow = nil

    local isBottomLeft  = (side == "bottom" or side == "bottom_left")
    local isBottomRight = (side == "bottom_right")

    -- Ortadan çizgi: yazı merkezi, ikon merkezi, slot merkezi aynı yatay çizgide (sol/sağ/alt)
    local upSlot = upgradeInfo and upgradeInfo[slotID]
    local isCraftedSlot = upSlot and upSlot.isCrafted
    local canAffordNext = upSlot and upSlot.canUpgrade and CanAffordNextUpgrade(upSlot, currencyAmounts)
    local statusUpgradeSz = STATUS_UPGRADE_ICON - 2 * STATUS_ICON_INSET
    local wantDebugUpgrade = GEAR_DEBUG_ALWAYS_SHOW_UPGRADE == true and slotData and slotData.itemLink
        and not (issecretvalue and issecretvalue(slotData.itemLink))
    -- Always reserve an arrow texture when the slot has an item (unless lock-only), so a late upgradeInfo refresh can still show/hide in _gearApplySlotVisual.
    local hasItemNow = slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink))
    local lockOnly = isNotUpgradeable and hasItemNow and not wantDebugUpgrade
    if not lockOnly and (hasUpgradePath or wantDebugUpgrade or hasItemNow) then
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
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, upgradeBg, upgradeArrow, nil)
        if not wantDebugUpgrade and hasUpgradePath and not canAffordNext and upgradeArrow.SetVertexColor then
            upgradeArrow:SetVertexColor(1, 0.9, 0.35)
        end
    elseif lockOnly then
        local lockIcon = btn:CreateTexture(nil, "OVERLAY")
        btn._gearLockIcon = lockIcon
        lockIcon:SetSize(statusUpgradeSz, statusUpgradeSz)
        if lockIcon.SetFrameLevel and btn.GetFrameLevel then
            lockIcon:SetFrameLevel((btn:GetFrameLevel() or 0) + 4)
        end
        if lockIcon.SetDrawLayer then lockIcon:SetDrawLayer("OVERLAY", 7) end
        PlaceGearUpgradeLockTowardModel(btn, btn.iconTex, side, nil, nil, lockIcon)
        lockIcon:SetTexture("Interface\\Common\\LockIcon")
        lockIcon:SetVertexColor(0.45, 0.45, 0.45, 0.9)
    end

    -- Tooltip: item link + simplified upgrade info (custom tooltip service)
    local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]

    -- Enchant/gem/socket scan deferred to next frame (see GearSlotApplyDeferredEnchantGemInspect).
    btn._gearLayoutCtx = { side = side, upgradeArrow = upgradeArrow, upgradeArrowBg = btn._gearUpgradeArrowBg }

    btn:SetScript("OnEnter", function(self)
        if slotData and slotData.itemLink then
            local up = upgradeInfo and upgradeInfo[slotID]
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
                    local range = GetCraftedIlvlRange(up, currencyAmounts)
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
                local affordable, goldOnly = CalculateAffordableUpgrades(up, currencyAmounts)
                if affordable > 0 then
                    additionalLines[#additionalLines + 1] = { type = "spacer", height = 6 }
                    -- Show achievable target only (e.g. 2/6 when 20 crests and 1/6 — not 6/6).
                    local targetTier = (up.currUpgrade or 0) + affordable
                    local TRACK_ILVLS = ns.TRACK_ILVLS
                    local targetIlvl = TRACK_ILVLS and TRACK_ILVLS[up.trackName] and TRACK_ILVLS[up.trackName][targetTier]
                    local ilvlStr = targetIlvl and format(" (%d)", targetIlvl) or ""
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_UPGRADE_AVAILABLE_FORMAT"]) or "Available upgrade to %s %d/%d%s", LocalizeUpgradeTrackName(up.trackName or ""), targetTier, up.maxUpgrade or 0, ilvlStr),
                        color = { 0.4, 1, 0.4 }
                    }
                    additionalLines[#additionalLines + 1] = {
                        text = format((ns.L and ns.L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"]) or "%d upgrade(s) with current currency", affordable),
                        color = { 0.6, 0.9, 0.6 }
                    }
                    if goldOnly > 0 then
                        if goldOnly >= affordable then
                            additionalLines[#additionalLines + 1] = {
                                text = (ns.L and ns.L["GEAR_CRESTS_GOLD_ONLY"]) or "Crests needed: 0 (gold only — previously reached)",
                                color = { 1, 0.85, 0.4 }
                            }
                        else
                            additionalLines[#additionalLines + 1] = {
                                text = format((ns.L and ns.L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"]) or "%d upgrade(s) gold only (previously reached)", goldOnly),
                                color = { 1, 0.85, 0.4 }
                            }
                        end
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
                    anchor = "ANCHOR_RIGHT",
                    itemTooltipContext = itemTooltipContext,
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "item",
                    itemID = slotData.itemID,
                    itemLink = slotData.itemLink,
                    additionalLines = additionalLines,
                    underTitleLines = underTitleLines,
                    anchor = "ANCHOR_RIGHT",
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
                    anchor = "ANCHOR_RIGHT",
                })
            elseif ns.TooltipService then
                ns.TooltipService:Show(self, {
                    type = "custom",
                    title = title,
                    lines = {
                        { text = (ns.L and ns.L["GEAR_NO_ITEM_EQUIPPED"]) or "No item equipped in this slot.", color = { 0.65, 0.65, 0.7 } },
                    },
                    anchor = "ANCHOR_RIGHT",
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
    hi:SetColorTexture(1, 1, 1, 0.12)

    -- Slot adı (Head, Trinket 1, Main Hand vb.) — Veteran/Champion yazısının üstünde
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
        slotNameLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, GFR("gearSlotName"), "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slotNameLabel:SetText("|cffffffff" .. slotName .. "|r")
        slotNameLabel:SetNonSpaceWrap(false)
        if slotNameLabel.SetWordWrap then slotNameLabel:SetWordWrap(false) end
    end

    -- Status label ve text layout
    local trackText = (statusText and statusText ~= "") and statusText or nil
    local trackLabel = nil
    local w = textWidth or TRACK_TEXT_W
    
    local currentTextOffset = TEXT_OFFSET_FROM_SLOT_CENTER
    -- Dikey hizalama yapıldığı için artık +20 yatay itme yapmaya gerek yok

    if trackText and side ~= "top" then
        trackLabel = FontManager and FontManager.CreateFontString and FontManager:CreateFontString(parent, GFR("gearTrackLabel"), "OVERLAY") or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
            local textContainer = CreateFrame("Frame", nil, parent)
            textContainer:SetSize(textWidth or TRACK_TEXT_W, P(42))
            textContainer:SetPoint("CENTER", btn, "CENTER", textCenterX, 0)
            
            local blockCenterOffset = 8
            trackLabel:SetParent(textContainer)
            trackLabel:ClearAllPoints()
            trackLabel:SetWidth(textWidth or TRACK_TEXT_W)
            trackLabel:SetPoint("CENTER", textContainer, "CENTER", 0, -blockCenterOffset)
            
            -- Set justification based on side to fix the huge gap
            if side == "left" or isBottomLeft then
                trackLabel:SetJustifyH("RIGHT")
            elseif side == "right" or isBottomRight then
                trackLabel:SetJustifyH("LEFT")
            else
                trackLabel:SetJustifyH("CENTER")
            end
            
            if slotNameLabel then
                slotNameLabel:SetParent(textContainer)
                slotNameLabel:ClearAllPoints()
                slotNameLabel:SetPoint("BOTTOM", trackLabel, "TOP", 0, 2)
                slotNameLabel:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
                slotNameLabel:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
                if side == "left" or isBottomLeft then
                    slotNameLabel:SetJustifyH("RIGHT")
                elseif side == "right" or isBottomRight then
                    slotNameLabel:SetJustifyH("LEFT")
                else
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
        self._slotDataRef = slotData
        self._needsDeferredInspect = false
        if slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink)) then
            self._needsDeferredInspect = true
        end
        if self._gearInspectSt then
            self._gearInspectSt.ready = false
            self._gearInspectSt.socketSig = ""
            self._gearInspectSt.socketEntries = nil
        end
        GearSlotClearPaperdollOverlays(self)
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
        if self._gearUpgradeArrow then
            local hasItem = slotData and slotData.itemLink and not (issecretvalue and issecretvalue(slotData.itemLink))
            if not hasItem then
                self._gearUpgradeArrow:Hide()
                if self._gearUpgradeArrowBg then self._gearUpgradeArrowBg:Hide() end
            else
                local up = self._gearUpgradeInfo and self._gearUpgradeInfo[self._slotID]
                local hasPath = GearUpgradeInfoHasPath(up)
                if GEAR_DEBUG_ALWAYS_SHOW_UPGRADE or hasPath then
                    self._gearUpgradeArrow:Show()
                    if self._gearUpgradeArrowBg then self._gearUpgradeArrowBg:Show() end
                    if self._gearUpgradeArrow.SetVertexColor then
                        if GEAR_DEBUG_ALWAYS_SHOW_UPGRADE or (canUpgrade == true) then
                            if self._gearUpgradeArrowCraftedAtlas then
                                self._gearUpgradeArrow:SetVertexColor(1, 1, 1)
                            else
                                self._gearUpgradeArrow:SetVertexColor(0.2, 1, 0.5)
                            end
                        else
                            self._gearUpgradeArrow:SetVertexColor(1, 0.9, 0.35)
                        end
                    end
                else
                    self._gearUpgradeArrow:Hide()
                    if self._gearUpgradeArrowBg then self._gearUpgradeArrowBg:Hide() end
                end
            end
        end
        if self._gearLockIcon then
            if notUpgradeable and slotData and slotData.itemLink then self._gearLockIcon:Show() else self._gearLockIcon:Hide() end
        end
        self._gearLastCanAffordNext = canUpgrade == true
    end

    return btn
end

-- ============================================================================
-- PAPERDOLL CARD  (full width; doll centered like Characters screen)
-- ============================================================================

local CURRENCY_ROW_H = 26
local ROW_H = 34
local CARD_PAD = 12

--- Build track/tier string from upgradeInfo[slotID], e.g. "Veteran 2/6".
--- For crafted items, shows tier name + ilvl (e.g. "Myth 285") or upgrade arrow (e.g. "Hero → Myth 285").
local function GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)
    local up = upgradeInfo and upgradeInfo[slotID]
    if not up then return nil end
    local fallbackHex = GetQualityHex and GetQualityHex(quality or 0) or "ffffff"

    -- Crafted items: show current tier + achievable recraft target
    if up.isCrafted then
        local currentEnglish = up.craftedTierName or "Crafted"
        local currentHex = GetUpgradeTrackHex(currentEnglish) or fallbackHex
        local currentTier = LocalizeUpgradeTrackName(currentEnglish)
        local range = currencyAmounts and GetCraftedIlvlRange(up, currencyAmounts) or nil
        if range and range.maxIlvl > (up.currentIlvl or 0) then
            local bestEnglish = range.bestCrestName or ""
            local bestHex = GetUpgradeTrackHex(bestEnglish) or fallbackHex
            return format("|cff%s%s|r → |cff%s%s %d|r",
                currentHex, currentTier, bestHex, LocalizeUpgradeTrackName(bestEnglish), range.maxIlvl)
        end
        return format("|cff%s%s %d|r", currentHex, currentTier, up.currentIlvl or 0)
    end

    local englishTrack = up.trackName
    local track = (englishTrack and englishTrack ~= "") and LocalizeUpgradeTrackName(englishTrack) or nil
    local hex = GetUpgradeTrackHex(englishTrack) or fallbackHex
    local curT, maxT = up.currUpgrade or 0, up.maxUpgrade or 0
    if maxT and maxT > 0 and track then
        return format("|cff%s%s %d/%d|r", hex, track, curT, maxT)
    end
    if track and track ~= "" then return "|cff" .. hex .. track .. "|r" end
    return nil
end

--- Offline character center panel: class-accent top rule + bottom bar with badge (3D/2D preview only).
---@param centerRef Frame
---@param classFile string|nil
local function ApplyGearOfflineCenterChrome(centerRef, classFile)
    if not centerRef then return end
    local chrome = ns._gearOfflineCenterChrome
    if not chrome then
        chrome = CreateFrame("Frame", nil, centerRef)
        chrome:SetAllPoints()
        chrome:EnableMouse(false)
        chrome:EnableMouseWheel(false)
        chrome.isPersistentRowElement = true
        local topLine = chrome:CreateTexture(nil, "ARTWORK", nil, 2)
        topLine:SetHeight(2)
        topLine:SetPoint("TOPLEFT", chrome, "TOPLEFT", 0, -1)
        topLine:SetPoint("TOPRIGHT", chrome, "TOPRIGHT", 0, -1)
        chrome._topLine = topLine
        local bar = CreateFrame("Frame", nil, chrome)
        bar:SetPoint("BOTTOMLEFT", chrome, "BOTTOMLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", 0, 0)
        bar:SetHeight(36)
        chrome._bar = bar
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0, 0, 0, 0.5)
        chrome._barBg = barBg
        local barClassLine = bar:CreateTexture(nil, "BORDER", nil, 1)
        barClassLine:SetHeight(2)
        barClassLine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        barClassLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        chrome._barClassLine = barClassLine
        local label = FontManager:CreateFontString(chrome, GFR("gearChromeHint"), "OVERLAY")
        label:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 10, 7)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.93, 0.94, 0.96, 0.95)
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(0, 0, 0, 0.9)
        chrome._label = label
        ns._gearOfflineCenterChrome = chrome
    end
    if chrome:GetParent() ~= centerRef then
        chrome:SetParent(centerRef)
    end
    chrome:ClearAllPoints()
    chrome:SetAllPoints()
    -- Above model (0) and interaction layer (~20), below nothing that matters; mouse passes through to drag layer.
    chrome:SetFrameLevel(25)
    local c = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or { r = 0.55, g = 0.5, b = 0.75 }
    if chrome._topLine then
        chrome._topLine:SetColorTexture(c.r, c.g, c.b, 0.55)
    end
    if chrome._barClassLine then
        chrome._barClassLine:SetColorTexture(c.r, c.g, c.b, 0.9)
    end
    if chrome._label then
        chrome._label:SetText((ns.L and ns.L["GEAR_OFFLINE_BADGE"]) or "Offline")
    end
    chrome:Show()
end

--- Draw paperdoll: sol panel (yazı-ikon-slot) | orta (model) | sağ panel (slot-ikon-yazı) | alt panel.
--- baseX: paperdoll bloğunun sol kenarı (kart içinde ana kolonda ortalanmış).
--- paperOriginY: kart TOPLEFT'e göre kağıt bezi bandının üstü (dikey hizalama için).
local function DrawPaperDollInCard(card, charData, gearData, upgradeInfo, currencyAmounts, isCurrentChar, baseX, charKey, paperOriginY, paperdollNaturalH, paperBandH, opts)
    baseX = baseX or CARD_PAD
    card._gearSlotInspectList = {}
    local itemTooltipContext = BuildGearTabItemTooltipContext(charData)
    -- Sol panel: fixed width; slot sağda (yazı - ikon - slot)
    local leftX = baseX + LEFT_PANEL_W - SLOT_SIZE
    local leftColRight = baseX + LEFT_PANEL_W
    local rightX = baseX + LEFT_PANEL_W + CENTER_GAP + MODEL_W + CENTER_GAP

    local slots = gearData and gearData.slots or {}
    local function GetSlotData(slotID) return slots[slotID] end
    local function HasUpgradePathForSlot(slotID)
        local up = upgradeInfo and upgradeInfo[slotID]
        return GearUpgradeInfoHasPath(up)
    end
    local function IsNotUpgradeable(slotID)
        local slot = slots[slotID]
        if slot and slot.notUpgradeable then return true end
        local up = upgradeInfo and upgradeInfo[slotID]
        if up and up.notUpgradeable then return true end
        return false
    end

    local rowStep = SLOT_SIZE + SLOT_GAP
    local vertCenterPad = 0
    if type(paperBandH) == "number" and type(paperdollNaturalH) == "number" and paperBandH > paperdollNaturalH then
        vertCenterPad = math.floor((paperBandH - paperdollNaturalH) / 2 + 0.5)
    end
    local anchorY = paperOriginY
    if anchorY == nil then
        anchorY = -(CARD_PAD + 24)
    end
    local startY = anchorY - vertCenterPad

    -- Left column: 6 armor slots — text left of icon (Icon - Text), right-aligned text
    local leftSlots = { 1, 2, 3, 15, 5, 9 }
    for i = 1, #leftSlots do
        local slotID = leftSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), leftX, startY - (i - 1) * rowStep, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "left", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    -- Right column: 6 armor + 2 trinkets — slot | ikon | yazı (finger slots 11 then 12 = API order).
    local rightSlots = { 10, 6, 7, 8, 11, 12, 13, 14 }
    for i = 1, #rightSlots do
        local slotID = rightSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        CreateSlotButton(card, slotID, GetSlotData(slotID), rightX, startY - (i - 1) * rowStep, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), "right", IsNotUpgradeable(slotID), TRACK_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    -- Alt panel: slot üstte, altında ikon + yazı (yazılar aşağı); silahlar birbirine yakın
    local weaponSlots = { 16, 17 }
    local WEAPON_GAP = P(36)
    local WEAPON_TEXT_W = TRACK_TEXT_W
    local weaponRowW = SLOT_SIZE + WEAPON_GAP + SLOT_SIZE
    local weaponStartX = baseX + LEFT_PANEL_W + (MODEL_W + CENTER_GAP - weaponRowW) / 2
    local maxRows = math.max(#leftSlots, #rightSlots)
    local bottomY = startY - maxRows * rowStep - 8
    for i = 1, #weaponSlots do
        local slotID = weaponSlots[i]
        local quality = (slots[slotID] and slots[slotID].quality) or 0
        local wx = (i == 1) and weaponStartX or (weaponStartX + SLOT_SIZE + WEAPON_GAP)
        local weaponSide = (i == 1) and "bottom_left" or "bottom_right"  -- Main Hand solunda, Off Hand sağında
        CreateSlotButton(card, slotID, GetSlotData(slotID), wx, bottomY, HasUpgradePathForSlot(slotID), GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts), weaponSide, IsNotUpgradeable(slotID), WEAPON_TEXT_W, nil, upgradeInfo, currencyAmounts, itemTooltipContext, charKey, isCurrentChar)
    end

    local numRightRows = #rightSlots  -- 8 (Hands .. Trinket 2)
    local MODEL_H = (numRightRows - 1) * rowStep + SLOT_SIZE  -- trinket altına kadar
    local modelX    = baseX + LEFT_PANEL_W + CENTER_GAP
    local modelTopY = startY

    local function runPaperdollCenterPaint()
        local classFile = charData and charData.classFile
        local accent    = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.6, 1.0 }
        if ns._gearPaperdollCenterPlaceholder then
            ns._gearPaperdollCenterPlaceholder:Hide()
        end
    -- scrollChild is the stable parent — portrait panel is parented here once and NEVER
    -- re-parented (same pattern as the old PlayerModel paperdoll).
    local scrollParent = card:GetParent()

    --- Resolve creature display ID for portrait: saved gear snapshot, or live for logged-in char.
    local function ResolveGearPaperdollDisplayID()
        local snap = gearData and gearData.modelSnapshot
        local id = snap and snap.displayID
        if type(id) == "string" then id = tonumber(id) end
        if id and issecretvalue and issecretvalue(id) then id = nil end
        if id and type(id) == "number" and id > 0 then return math.floor(id) end
        if isCurrentChar == true then
            if UnitCreatureDisplayID then
                local ok, d = pcall(UnitCreatureDisplayID, "player")
                if ok and d and type(d) == "number" and d > 0
                    and not (issecretvalue and issecretvalue(d)) then
                    return math.floor(d)
                end
            end
            if C_PlayerInfo and C_PlayerInfo.GetDisplayID then
                local ok, d = pcall(C_PlayerInfo.GetDisplayID)
                if ok and d and type(d) == "number" and d > 0
                    and not (issecretvalue and issecretvalue(d)) then
                    return math.floor(d)
                end
            end
        end
        return nil
    end

    local function AcquireGearPortraitPanel()
        local pan = ns._gearPortraitPanel
        if not pan then
            pan = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
            local tex = pan:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", pan, "TOPLEFT", 2, -2)
            tex:SetPoint("BOTTOMRIGHT", pan, "BOTTOMRIGHT", -2, 2)
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            pan._tex = tex
            pan.isPersistentRowElement = true
            ns._gearPortraitPanel = pan
        end
        if not pan._wnGearTooltipPanelBg then
            pan:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
            pan._wnGearTooltipPanelBg = true
        end
        pan:SetBackdropColor(0.1, 0.1, 0.12, 0.92)
        return pan
    end

    -- Hide until we know which center widget to show; legacy PlayerModel (unused)
    if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
    if ns._gearDressModel then ns._gearDressModel:Hide() end
    if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
    if ns._gearOfflineCenterChrome then ns._gearOfflineCenterChrome:Hide() end
    if ns._gearPlayerModel then
        ns._gearPlayerModel:Hide()
        ns._gearPlayerModel._unitSet = false
        ns._gearPlayerModel._displaySet = false
    end

    -- 2D portrait: fallback (SetPortraitTexture*). Shown when 3D (DressUpModel) cannot be built.
    -- TexCoord crop = extra zoom on the bust.
    local GEAR_PORTRAIT_CROP = { 0.09, 0.91, 0.06, 0.94 }

    -- Primary: DressUpModel — current character SetUnit+Dress; alts: snapshot+TryOn. modelView in SavedVariables.
    local GEAR_REFERENCE_RADIUS = 0.96
    local GEAR_FIXED_CAM_DISTANCE = 2.72
    local GEAR_CAM_FIT_PADDING = 1.06
    local GEAR_FIXED_CAM_SCALE = 2.05
    local GEAR_MODEL_SCALE_MIN = 0.15
    local GEAR_MODEL_SCALE_MAX = 6.0
    local GEAR_ZOOM_MIN = 0.5
    local GEAR_ZOOM_MAX = 2.0
    local GEAR_ROTATE_SENSITIVITY = 0.02

    local centerRef = nil

-- Two distinct widgets so SetUnit/Dress state on the online widget can never
    -- bleed into the offline widget (DressUpModel + SetUnit + later SetDisplayInfo
    -- = white-mannequin: dressing layer keeps a stale slot list whose item textures
    -- aren't in the local cache for alts). PlayerModel has no dressing layer, so
    -- SetDisplayInfo renders the displayID's baked race/sex/customizations directly.
    local function BuildModelClip(widgetType)
        -- Clip frame: holds background + 3D model + interaction layer. SetClipsChildren
        -- prevents the model from drawing over neighbouring cards/scroll edges.
        local clip = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
        if clip.SetClipsChildren then clip:SetClipsChildren(true) end
        clip:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
        clip:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        clip.isPersistentRowElement = true

        -- Class-tinted vertical gradient drawn behind the 3D model. Same look as the
        -- offline character card so online and offline panels share a consistent feel.
        local grad = clip:CreateTexture(nil, "BACKGROUND", nil, 1)
        grad:SetPoint("TOPLEFT", clip, "TOPLEFT", 1, -1)
        grad:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -1, 1)
        grad:SetColorTexture(1, 1, 1, 1)
        clip._gradient = grad
        clip._SetClassTint = function(self, classFile)
            local cc = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
                or { r = 0.55, g = 0.5, b = 0.75 }
            local tR, tG, tB = cc.r * 0.50, cc.g * 0.50, cc.b * 0.50
            if grad.SetGradient and CreateColor then
                pcall(grad.SetGradient, grad, "VERTICAL",
                    CreateColor(tR, tG, tB, 0.90),
                    CreateColor(0.04, 0.04, 0.05, 0.95))
            else
                grad:SetColorTexture(tR, tG, tB, 0.90)
            end
        end

        local m = CreateFrame(widgetType, nil, clip)
        m:SetAllPoints(clip)
        m:SetModelDrawLayer("ARTWORK")
        m:EnableMouse(false)
        m:EnableMouseWheel(false)
        m._clip = clip
        clip._model = m

        m._rotation = 0
        m._zoom = 1.0
        m._scale = 1.0
        m._normalized = false

        local function ApplyTransform()
            pcall(function()
                m:SetPosition(0, 0, 0)
                if m.UseModelCenterToTransform then m:UseModelCenterToTransform(true) end
                if m.SetPitch then m:SetPitch(0) end
                m:SetFacing(m._rotation)
                if m.SetPortraitZoom then m:SetPortraitZoom(0) end
                if m._normalized and m.SetModelScale and m.SetCameraDistance then
                    m:SetModelScale(m._scale)
                    local vw, vh = clip:GetWidth() or 1, clip:GetHeight() or 1
                    local aspectPad = (vh > 1 and (vw / vh) > 1.12) and 1.09 or 1.0
                    local camDist = GEAR_FIXED_CAM_DISTANCE
                        * GEAR_CAM_FIT_PADDING
                        * aspectPad
                        * m._zoom
                        * m._scale
                    m:SetCameraDistance(math.max(0.1, camDist))
                elseif m.SetCamDistanceScale then
                    m:SetCamDistanceScale(GEAR_FIXED_CAM_SCALE * m._zoom)
                end
                if m.SetViewTranslation then m:SetViewTranslation(0, 0) end
            end)
        end
        clip._ApplyTransform = ApplyTransform

        local function NormalizeRadius()
            if not m.GetModelRadius or not m.SetModelScale or not m.SetCameraDistance then return false end
            local ok, r = pcall(m.GetModelRadius, m)
            if not ok or not r or r <= 0 then return false end
            local s = (GEAR_REFERENCE_RADIUS / r) * 0.94 * 1.05
            if s < GEAR_MODEL_SCALE_MIN then s = GEAR_MODEL_SCALE_MIN
            elseif s > GEAR_MODEL_SCALE_MAX then s = GEAR_MODEL_SCALE_MAX end
            m._normalized = true
            m._scale = s
            ApplyTransform()
            return true
        end
        clip._Normalize = NormalizeRadius

        m:SetScript("OnModelLoaded", function()
            if m.SetAnimation then
                pcall(m.SetAnimation, m, 0)
            end
            if m.ClearFog then
                pcall(m.ClearFog, m)
            end
            NormalizeRadius()
            ApplyTransform()
        end)

        -- Interaction layer: rotation drag (left/right button) + wheel zoom.
        local il = CreateFrame("Frame", nil, clip)
        il:SetAllPoints()
        il:SetFrameLevel(m:GetFrameLevel() + 20)
        il:EnableMouse(true)
        il:EnableMouseWheel(true)
        clip._il = il

        local function SchedulePersistView()
            if not clip._viewCharKey or not (WarbandNexus and WarbandNexus.SaveGearModelViewState) then return end
            if ns._gearViewSaveTimer then
                ns._gearViewSaveTimer:Cancel()
                ns._gearViewSaveTimer = nil
            end
            ns._gearViewSaveTimer = C_Timer.NewTimer(0.35, function()
                ns._gearViewSaveTimer = nil
                if not clip or not clip._viewCharKey or not clip._model then return end
                WarbandNexus:SaveGearModelViewState(clip._viewCharKey, clip._model._rotation, clip._model._zoom)
            end)
        end

        local function ScaleX()
            local s = il:GetEffectiveScale() or 1
            return (s > 0) and s or 1
        end

        local function dragOnUpdate()
            if m._dragX == nil or not m._dragBtn then il:SetScript("OnUpdate", nil); return end
            if not IsMouseButtonDown(m._dragBtn) then
                m._dragX, m._dragBtn = nil, nil
                il:SetScript("OnUpdate", nil)
                return
            end
            local x = GetCursorPosition() / ScaleX()
            local dx = x - m._dragX
            m._dragX = x
            m._rotation = (m._dragRot or 0) - dx * GEAR_ROTATE_SENSITIVITY
            m._dragRot = m._rotation
            m:SetFacing(m._rotation)
        end
        il:SetScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" and btn ~= "RightButton" then return end
            m._dragX = GetCursorPosition() / ScaleX()
            m._dragRot = m._rotation
            m._dragBtn = btn
            il:SetScript("OnUpdate", dragOnUpdate)
        end)
        il:SetScript("OnMouseUp", function(_, btn)
            if btn == m._dragBtn then m._dragX, m._dragBtn = nil, nil end
            il:SetScript("OnUpdate", nil)
            SchedulePersistView()
        end)
        il:SetScript("OnHide", function()
            m._dragX, m._dragBtn = nil, nil
            il:SetScript("OnUpdate", nil)
        end)
        il:SetScript("OnMouseWheel", function(_, delta)
            local z = m._zoom * ((delta > 0) and 0.9 or 1.1)
            if z < GEAR_ZOOM_MIN then z = GEAR_ZOOM_MIN
            elseif z > GEAR_ZOOM_MAX then z = GEAR_ZOOM_MAX end
            m._zoom = z
            ApplyTransform()
            SchedulePersistView()
        end)

        return clip
    end

    local function AcquireGearDressModel()
        if not ns._gearDressModel then
            ns._gearDressModel = BuildModelClip("DressUpModel")
        end
        return ns._gearDressModel
    end

    -- Offline alts: no DressUpModel / 2D portrait — class card only (see block below).
    if isCurrentChar ~= true then
        if ns._gearDressModel then ns._gearDressModel:Hide() end
        if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
        if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
    elseif not centerRef then
        local clip = AcquireGearDressModel()
        if not clip._wnGearTooltipPanelBg then
            clip:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
            clip._wnGearTooltipPanelBg = true
        end
        clip:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        if clip._SetClassTint then clip:_SetClassTint(classFile) end
        clip._viewCharKey = charKey
        local m = clip._model
        if clip:GetParent() ~= scrollParent then clip:SetParent(scrollParent) end
        clip:ClearAllPoints()
        clip:SetSize(MODEL_W, MODEL_H)
        clip:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        clip:SetFrameLevel(card:GetFrameLevel() + 5)

        -- Reset framing state on character swap so radius normalize re-runs cleanly.
        m._normalized = false
        m._scale = 1.0
        m._zoom = 0.58
        m._rotation = 0
        do
            local mv = gearData and gearData.modelView
            if type(mv) == "table" then
                if mv.rotation ~= nil then
                    m._rotation = tonumber(mv.rotation) or 0
                end
                if mv.zoom ~= nil then
                    m._zoom = tonumber(mv.zoom) or m._zoom
                end
            end
        end
        if m._zoom < GEAR_ZOOM_MIN then m._zoom = GEAR_ZOOM_MIN
        elseif m._zoom > GEAR_ZOOM_MAX then m._zoom = GEAR_ZOOM_MAX end
        m._dragRot = m._rotation

        local ok = pcall(function()
            m:SetUnit("player")
            if m.Dress then m:Dress() end
            if m.RefreshUnit then m:RefreshUnit() end
        end)

        if ok then
            if m.ClearFog then
                pcall(m.ClearFog, m)
            end
            if m.SetAnimation then
                pcall(m.SetAnimation, m, 0)
            end
            if clip._Normalize then clip._Normalize() end
            if clip._ApplyTransform then clip._ApplyTransform() end
            if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
            clip:Show()
            m:Show()
            centerRef = clip
        else
            clip:Hide()
        end
    end

    -- Online (current character) 2D portrait fallback: only when the live DressUpModel
    -- failed AND we're on the player. SetPortraitTexture("player") is reliable; we never
    -- run SetPortraitTextureFromCreatureDisplayID for offline alts here.
    if not centerRef and isCurrentChar == true then
        local pan = AcquireGearPortraitPanel()
        if pan:GetParent() ~= scrollParent then pan:SetParent(scrollParent) end
        pan:ClearAllPoints()
        pan:SetSize(MODEL_W, MODEL_H)
        pan:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        pan:SetFrameLevel(card:GetFrameLevel() + 5)
        local tex = pan._tex
        local ok2d = false
        if tex and SetPortraitTexture then
            if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
            ok2d = pcall(function() SetPortraitTexture(tex, "player") end)
        end
        if ok2d then
            if tex and tex.SetTexCoord then
                local c = GEAR_PORTRAIT_CROP
                tex:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            pan:Show()
            if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
            if ns._gearDressModel then ns._gearDressModel:Hide() end
            if ns._gearOfflineModel then ns._gearOfflineModel:Hide() end
            centerRef = pan
        end
    end

    -- Fallback: modern offline character card.
    -- Layout: class-colored vertical gradient → large class icon → character name
    -- (class-colored) → "Lv N · Race" line → item-level pill → soft hint at bottom.
    -- All elements pulled from charData; gracefully degrades when fields are missing.
    if not centerRef then
        local portrait = ns._gearNoPreviewFrame
        if not portrait then
            portrait = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
            portrait.isPersistentRowElement = true
            ns._gearNoPreviewFrame = portrait

            -- Class-tinted vertical gradient (top → bottom: dim → black).
            local grad = portrait:CreateTexture(nil, "BACKGROUND", nil, 1)
            grad:SetPoint("TOPLEFT", portrait, "TOPLEFT", 1, -1)
            grad:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 1)
            grad:SetColorTexture(1, 1, 1, 1)
            portrait._gradient = grad

            -- Large class icon — modern transparent atlas (classicon-<class>) instead of
            -- the legacy WORLDSTATEFRAME sheet which left a coloured square outline.
            local icon = portrait:CreateTexture(nil, "ARTWORK")
            icon:SetSize(80, 80)
            icon:SetPoint("CENTER", portrait, "CENTER", 0, 22)
            portrait._classIcon = icon

            -- Soft circular halo behind icon (atlas if available, else dim disc).
            local ring = portrait:CreateTexture(nil, "ARTWORK", nil, -1)
            ring:SetSize(108, 108)
            ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
            if ring.SetAtlas then
                local ok = pcall(ring.SetAtlas, ring, "communities-create-avatar-bg-glow", true)
                if not ok then ring:SetColorTexture(0, 0, 0, 0.0) end
            end
            ring:SetVertexColor(1, 1, 1, 0.35)
            portrait._iconRing = ring

            -- Character name (class-colored).
            local name = FontManager:CreateFontString(portrait, GFR("gearPortraitLine"), "OVERLAY")
            name:SetPoint("TOP", icon, "BOTTOM", 0, -10)
            name:SetWidth(MODEL_W - 16)
            name:SetJustifyH("CENTER")
            name:SetShadowOffset(1, -1)
            name:SetShadowColor(0, 0, 0, 0.95)
            portrait._name = name

            -- "Lv N · Race" meta line.
            local meta = FontManager:CreateFontString(portrait, GFR("gearPortraitMeta"), "OVERLAY")
            meta:SetPoint("TOP", name, "BOTTOM", 0, -2)
            meta:SetWidth(MODEL_W - 16)
            meta:SetJustifyH("CENTER")
            meta:SetTextColor(0.78, 0.8, 0.88, 1)
            meta:SetShadowOffset(1, -1)
            meta:SetShadowColor(0, 0, 0, 0.85)
            portrait._meta = meta

            -- Item level pill: small framed bg with bold ilvl text.
            local pill = CreateFrame("Frame", nil, portrait, "BackdropTemplate")
            pill:SetSize(78, 22)
            pill:SetPoint("TOP", meta, "BOTTOM", 0, -10)
            pill:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            pill:SetBackdropColor(0, 0, 0, 0.55)
            portrait._pill = pill
            local pillLabel = FontManager:CreateFontString(pill, GFR("gearPortraitMeta"), "OVERLAY")
            pillLabel:SetPoint("CENTER", pill, "CENTER", 0, 0)
            pillLabel:SetTextColor(1, 0.82, 0.0, 1)
            pillLabel:SetShadowOffset(1, -1)
            pillLabel:SetShadowColor(0, 0, 0, 0.9)
            portrait._pillLabel = pillLabel
        end

        if portrait:GetParent() ~= scrollParent then
            portrait:SetParent(scrollParent)
        end
        portrait:ClearAllPoints()
        portrait:SetSize(MODEL_W, MODEL_H)
        portrait:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        portrait:SetFrameLevel(card:GetFrameLevel() + 5)
        portrait:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
        portrait:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        portrait:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)

        local cc = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
            or { r = 0.55, g = 0.5, b = 0.75 }
        if portrait._gradient and portrait._gradient.SetGradient then
            -- Top: dim class tint; bottom: near-black.
            local topR, topG, topB = cc.r * 0.32, cc.g * 0.32, cc.b * 0.32
            local createColor = (CreateColor or ColorMixin) and CreateColor or nil
            if createColor then
                pcall(portrait._gradient.SetGradient, portrait._gradient, "VERTICAL",
                    CreateColor(topR, topG, topB, 0.85),
                    CreateColor(0.04, 0.04, 0.05, 0.95))
            else
                portrait._gradient:SetColorTexture(topR, topG, topB, 0.85)
            end
        end

        if portrait._classIcon then
            local applied = false
            if classFile and portrait._classIcon.SetAtlas then
                local atlas = "classicon-" .. string.lower(classFile)
                applied = pcall(portrait._classIcon.SetAtlas, portrait._classIcon, atlas)
            end
            if applied then
                -- Reset TexCoord so a previous WORLDSTATEFRAME crop doesn't clip the atlas.
                portrait._classIcon:SetTexCoord(0, 1, 0, 1)
            else
                -- Legacy fallback: WORLDSTATEFRAME sheet with TCoords.
                -- Inset the TexCoords by ~6 % on each edge to crop the coloured square
                -- border that surrounds each class icon cell in the sprite sheet.
                portrait._classIcon:SetTexture("Interface\\WORLDSTATEFRAME\\Icons-Classes")
                local coords = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
                if coords then
                    local INSET = 0.02
                    portrait._classIcon:SetTexCoord(
                        coords[1] + INSET, coords[2] - INSET,
                        coords[3] + INSET, coords[4] - INSET)
                end
            end
            portrait._classIcon:SetVertexColor(1, 1, 1, 1)
            portrait._classIcon:Show()
        end

        if portrait._iconRing then
            portrait._iconRing:SetVertexColor(cc.r, cc.g, cc.b, 0.45)
        end

        local pnDisplayName = (charData and charData.name) or ""
        local pnFallback = ((ns.L and ns.L["GEAR_NO_PREVIEW"]) or "No Preview")
        if portrait._name then
            if pnDisplayName ~= "" then
                portrait._name:Hide()
            else
                portrait._name:SetText(pnFallback)
                portrait._name:SetTextColor(cc.r, cc.g, cc.b, 1)
                portrait._name:Show()
            end
        end

        if portrait._meta then
            local lvl = charData and tonumber(charData.level) or nil
            local race = (charData and (charData.raceName or charData.race)) or nil
            local parts = {}
            if lvl and lvl > 0 then parts[#parts + 1] = "Lv " .. lvl end
            if race and race ~= "" then parts[#parts + 1] = race end
            portrait._meta:SetText(#parts > 0 and table.concat(parts, "  ·  ") or ((ns.L and ns.L["GEAR_NO_PREVIEW_HINT"]) or "Log in on this character to refresh the appearance preview."))
        end

        if portrait._pill then portrait._pill:Hide() end

        portrait:Show()
        centerRef = portrait
    end

    do
        local isNoPreview = (centerRef == ns._gearNoPreviewFrame)
        if isCurrentChar == true or isNoPreview or not centerRef then
            if ns._gearOfflineCenterChrome then
                ns._gearOfflineCenterChrome:Hide()
            end
        else
            ApplyGearOfflineCenterChrome(centerRef, classFile)
        end
    end

    -- Border around model/portrait (singleton — reused across refreshes)
    local modelBorder = ns._gearModelBorder
    if not modelBorder then
        modelBorder = CreateFrame("Frame", nil, card, "BackdropTemplate")
        modelBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        modelBorder.isPersistentRowElement = true
        ns._gearModelBorder = modelBorder
    end
    modelBorder:SetParent(card)
    modelBorder:ClearAllPoints()
    modelBorder:SetPoint("TOPLEFT",     centerRef, "TOPLEFT",      -1,  1)
    modelBorder:SetPoint("BOTTOMRIGHT", centerRef, "BOTTOMRIGHT",   1, -1)
    modelBorder:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.65)
    modelBorder:SetFrameLevel(centerRef:GetFrameLevel() + 6)
    modelBorder:Show()

    -- Character name + average item level: stacked inside model/portrait panel (top).
    local avgIlvl = charData and charData.itemLevel or 0
    local ilvlFrame = ns._gearIlvlFrame
    if not ilvlFrame then
        ilvlFrame = CreateFrame("Frame", nil, card)
        ilvlFrame:SetSize(120, 22)
        local ilvlOverlay = FontManager:CreateFontString(ilvlFrame, GFR("gearIlvlBadge"), "OVERLAY")
        ilvlOverlay:SetPoint("CENTER", 0, 0)
        ilvlOverlay:SetJustifyH("CENTER")
        ilvlOverlay:SetShadowOffset(1, -1)
        ilvlOverlay:SetShadowColor(0, 0, 0, 1)
        ilvlFrame._label = ilvlOverlay
        ilvlFrame.isPersistentRowElement = true
        ns._gearIlvlFrame = ilvlFrame
    end

    local displayName = (charData and charData.name) or ""
    local nameWrapper = ns._gearNameWrapper
    if not nameWrapper then
        nameWrapper = CreateFrame("Frame", nil, card)
        local nameLabel = FontManager:CreateFontString(nameWrapper, GFR("gearCharacterName"), "OVERLAY")
        nameLabel:SetJustifyH("CENTER")
        nameLabel:SetShadowOffset(1, -1)
        nameLabel:SetShadowColor(0, 0, 0, 1)
        nameWrapper._label = nameLabel
        nameWrapper.isPersistentRowElement = true
        ns._gearNameWrapper = nameWrapper
    end

    local textBase = 40
    if centerRef._il and centerRef._il.GetFrameLevel then
        textBase = centerRef._il:GetFrameLevel() + 2
    elseif centerRef._model and centerRef._model.GetFrameLevel then
        textBase = centerRef._model:GetFrameLevel() + 22
    end

    if displayName ~= "" then
        nameWrapper:SetParent(centerRef)
        nameWrapper:ClearAllPoints()
        nameWrapper:SetPoint("TOPLEFT", centerRef, "TOPLEFT", 6, -8)
        nameWrapper:SetPoint("TOPRIGHT", centerRef, "TOPRIGHT", -6, -8)
        nameWrapper:SetHeight(20)
        if nameWrapper.SetFrameLevel then
            nameWrapper:SetFrameLevel(textBase)
        end
        local nameLabel = nameWrapper._label
        nameLabel:ClearAllPoints()
        nameLabel:SetPoint("TOPLEFT", nameWrapper, "TOPLEFT", 0, 0)
        nameLabel:SetPoint("TOPRIGHT", nameWrapper, "TOPRIGHT", 0, 0)
        local classHex = GetClassHex(classFile)
        nameLabel:SetText("|cff" .. classHex .. displayName .. "|r")
        nameWrapper:Show()

        if avgIlvl > 0 then
            ilvlFrame:SetParent(centerRef)
            ilvlFrame:ClearAllPoints()
            ilvlFrame:SetPoint("TOP", nameWrapper, "BOTTOM", 0, 0)
            if ilvlFrame.SetFrameLevel then
                ilvlFrame:SetFrameLevel(textBase + 1)
            end
            ilvlFrame._label:SetTextColor(1, 0.9, 0)
            ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
            ilvlFrame:Show()
        else
            ilvlFrame:Hide()
        end
    else
        nameWrapper:Hide()
        if avgIlvl > 0 then
            ilvlFrame:SetParent(centerRef)
            ilvlFrame:ClearAllPoints()
            ilvlFrame:SetPoint("TOP", centerRef, "TOP", 0, -8)
            if ilvlFrame.SetFrameLevel then
                ilvlFrame:SetFrameLevel(textBase + 1)
            end
            ilvlFrame._label:SetTextColor(1, 0.9, 0)
            ilvlFrame._label:SetText((FormatFloat2(avgIlvl) or tostring(avgIlvl)) .. " " .. GetLocalizedText("ILVL_SHORT_LABEL", "iLvl"))
            ilvlFrame:Show()
        else
            ilvlFrame:Hide()
        end
    end
    end

    if opts and opts.deferCenter then
        local ph = ns._gearPaperdollCenterPlaceholder
        if not ph then
            ph = CreateFrame("Frame", nil, card, "BackdropTemplate")
            ph.isPersistentRowElement = true
            ns._gearPaperdollCenterPlaceholder = ph
        end
        ph:SetParent(card)
        ph:ClearAllPoints()
        ph:SetSize(MODEL_W, MODEL_H)
        ph:SetPoint("TOPLEFT", card, "TOPLEFT", modelX, modelTopY)
        ph:SetBackdrop(GEAR_MODEL_PANEL_BACKDROP)
        ph:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
        ph:SetFrameLevel((card:GetFrameLevel() or 2) + 3)
        ph:Show()
        card._gearPaperdollCenterDefer = runPaperdollCenterPaint
        return
    end

    runPaperdollCenterPaint()
end

-- ── Stat helpers (live API for current char) ────────────────────────────────
local STAT_IDS = {
    { id = 1, label = (ns.L and ns.L["STAT_STRENGTH"]) or SPELL_STAT1_NAME or "Strength",    icon = "Interface\\Icons\\spell_nature_strength" },
    { id = 2, label = (ns.L and ns.L["STAT_AGILITY"]) or SPELL_STAT2_NAME or "Agility",      icon = "Interface\\Icons\\ability_backstab" },
    { id = 3, label = (ns.L and ns.L["STAT_STAMINA"]) or SPELL_STAT3_NAME or "Stamina",      icon = "Interface\\Icons\\spell_holy_wordfortitude" },
    { id = 4, label = (ns.L and ns.L["STAT_INTELLECT"]) or SPELL_STAT4_NAME or "Intellect",  icon = "Interface\\Icons\\spell_holy_magicalsentry" },
}
local SECONDARY_STATS = {
    { label = (ns.L and ns.L["STAT_CRITICAL_STRIKE"]) or "Critical Strike", fn = function() return GetCombatRating and GetCombatRating(9) or 0 end,  pctFn = function() return GetCritChance and GetCritChance() or 0 end },
    { label = (ns.L and ns.L["STAT_HASTE"]) or "Haste",                     fn = function() return GetCombatRating and GetCombatRating(18) or 0 end, pctFn = function() return GetHaste and GetHaste() or 0 end },
    { label = (ns.L and ns.L["STAT_MASTERY"]) or "Mastery",                 fn = function() return GetCombatRating and GetCombatRating(26) or 0 end, pctFn = function() return GetMasteryEffect and select(1, GetMasteryEffect()) or 0 end },
    { label = (ns.L and ns.L["STAT_VERSATILITY"]) or "Versatility",         fn = function() return GetCombatRating and GetCombatRating(29) or 0 end, pctFn = function() return GetCombatRatingBonus and GetCombatRatingBonus(29) or 0 end },
}

-- Offline snapshot: sıra veya etiket ile eşleştir (eski SV uyumu)
local function MergeOfflineSecondaryForGear(savedSec)
    local out = {}
    for i = 1, #SECONDARY_STATS do
        local def = SECONDARY_STATS[i]
        local rating, pct = 0, 0
        local s = savedSec and savedSec[i]
        if s and type(s.rating) == "number" then
            rating = math.floor(s.rating)
            pct = (type(s.pct) == "number") and s.pct or 0
        elseif savedSec then
            for j = 1, #savedSec do
                local ent = savedSec[j]
                if ent and ent.label == def.label then
                    rating = tonumber(ent.rating) or 0
                    pct = (type(ent.pct) == "number") and ent.pct or 0
                    break
                end
            end
        end
        out[#out + 1] = { label = def.label, rating = rating, pct = pct }
    end
    return out
end

--- Equipped gear card: paperdoll (left) | stacked stats + currencies (middle) | upgrade recommendations (right).
--- charKey: key from dropdown (used for currency/gold lookup).
--- isCurrentChar: true if selected character is the logged-in one (live portrait fallback).
--- currencies: array from GetGearUpgradeCurrenciesFromDB (passed to avoid duplicate API calls).
---@param storageScanPending boolean When true and there are no rows yet, show a loading line instead of the empty-state copy.
local function DrawPaperDollCard(parent, yOffset, charData, gearData, upgradeInfo, charKey, currencyAmounts, isCurrentChar, currencies, storageFindings, storageScanPending)
    local rowStep = SLOT_SIZE + SLOT_GAP
    -- Content height: section + slot columns + gap + weapon row (Main/Off Hand) + bottom pad so card border is below weapons
    local contentTop = CARD_PAD + 24
    local weaponBottom = 8 * rowStep + 8 + SLOT_SIZE
    local paperdollH = contentTop + weaponBottom + CARD_PAD
    currencies = currencies or {}
    -- Middle column subpanels: stats + currencies — padding + stat column gaps (uses midColW).
    local GEAR_SUBPANEL_PAD = 10
    local GEAR_SUBPANEL_HDR = 36   -- Bumped from 26: visible breathing room between title and first row.
    local GEAR_STAT_COL_GAP = 8
    local cardH = CARD_PAD + 24 + paperdollH + CARD_PAD

    local card = CreateCard(parent, cardH)
    card:SetPoint("TOPLEFT", SIDE_MARGIN, yOffset)
    card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, yOffset)

    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }

    -- ── Crest / gold block heights (drawn under character stats in main column) ──
    local crestCurrencies = {}
    local goldCurrency = nil
    for i = 1, #currencies do
        local cur = currencies[i]
        if cur.isGold then goldCurrency = cur else crestCurrencies[#crestCurrencies + 1] = cur end
    end

    local playbookTooltipPayload = nil

    -- Currency panel height: header + crest rows + divider + gold + short footer + bottom pad
    local CREST_ROW_H = 36
    local FOOTER_HINT_H = 14
    local currenciesH = GEAR_SUBPANEL_HDR + #crestCurrencies * CREST_ROW_H + 12 + 28 + FOOTER_HINT_H + 8

    local parentW = (card and card.GetWidth) and card:GetWidth() or ((parent and parent.GetWidth) and parent:GetWidth() or 0)
    local CARD_PAD_X = 12
    local cardInnerW = 0
    if parentW and parentW > (SIDE_MARGIN * 2) then
        cardInnerW = parentW - (SIDE_MARGIN * 2) - (CARD_PAD_X * 2)
    end
    if cardInnerW <= 0 and card and card.GetWidth then
        cardInnerW = card:GetWidth() - CARD_PAD_X * 2
    end
    cardInnerW = math.max(cardInnerW or 0, GetGearTabMinCardInnerW())
    local PANEL_GAP = GEAR_PANEL_GAP
    local paperColW = GEAR_PAPER_COL_W
    local recEnabled = WarbandNexus:IsGearStorageRecommendationsEnabled()
    -- Mid column: full width when recommendations panel is off.
    local afterPaper = cardInnerW - paperColW - PANEL_GAP
    local midColW
    if recEnabled then
        afterPaper = cardInnerW - paperColW - PANEL_GAP * 2
        midColW = GEAR_MID_COL_PREF_W
        if midColW > afterPaper - GEAR_REC_COL_MIN_W then
            midColW = math.max(GEAR_MID_COL_MIN_W, afterPaper - GEAR_REC_COL_MIN_W)
        end
    else
        midColW = math.max(GEAR_MID_COL_MIN_W, afterPaper)
    end
    local storageW = recEnabled and math.max(GEAR_REC_COL_MIN_W, afterPaper - midColW) or 0
    local paperLeft = CARD_PAD
    local midLeft = CARD_PAD + paperColW + PANEL_GAP

    local panelTopY = -CARD_PAD - 22
    local SECTION_GAP = 12

    local paperdollBaseX = paperLeft + math.max(0, math.floor((paperColW - PAPERDOLL_BLOCK_W) / 2))

    local STAT_ROW_H = 28
    local primaryRows = {}
    local secondaryRows = {}
    if isCurrentChar and UnitStat then
        local mainStat = (WarbandNexus.GetCurrentCharacterMainStat and WarbandNexus:GetCurrentCharacterMainStat()) or nil
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        for i = 1, #STAT_IDS do
            local stat = STAT_IDS[i]
            if stat.id == 3 then
                -- Stamina always
            elseif mainStatId and stat.id ~= mainStatId then
                stat = nil
            end
            if stat then
                local ok, _, total = pcall(UnitStat, "player", stat.id)
                if ok and type(total) == "number" then
                    primaryRows[#primaryRows + 1] = {
                        label = stat.label,
                        value = FormatNumber and FormatNumber(math.floor(total)) or tostring(math.floor(total)),
                    }
                end
            end
        end
        for i = 1, #SECONDARY_STATS do
            local stat = SECONDARY_STATS[i]
            local okR, rating = pcall(stat.fn)
            local okP, pct = pcall(stat.pctFn)
            local rNum = (okR and type(rating) == "number") and rating or 0
            local pNum = (okP and type(pct) == "number") and pct or 0
            secondaryRows[#secondaryRows + 1] = {
                label = stat.label,
                pctStr = format("%.1f%%", pNum),
                ratingStr = FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum)),
            }
        end
    elseif not isCurrentChar and charData and charData.stats then
        local mainStat = nil
        local mc = charData.stats.mainStatCode
        if mc == "STR" or mc == "AGI" or mc == "INT" then
            mainStat = mc
        end
        if not mainStat and WarbandNexus.GetCharacterMainStat then
            mainStat = WarbandNexus:GetCharacterMainStat(charData)
        end
        local mainStatId = (mainStat == "STR" and 1) or (mainStat == "AGI" and 2) or (mainStat == "INT" and 4) or nil
        local prim = charData.stats.primary
        if prim and next(prim) then
            for idx = 1, #STAT_IDS do
                local stat = STAT_IDS[idx]
                if stat.id == 3 then
                    -- Stamina always
                elseif mainStatId and stat.id ~= mainStatId then
                    stat = nil
                end
                if stat then
                    local raw = prim[stat.id]
                    if raw == nil then raw = 0 end
                    if type(raw) == "number" then
                        primaryRows[#primaryRows + 1] = {
                            label = stat.label,
                            value = FormatNumber and FormatNumber(math.floor(raw)) or tostring(math.floor(raw)),
                        }
                    end
                end
            end
        end
        local mergedSec = MergeOfflineSecondaryForGear(charData.stats.secondary)
        for j = 1, #mergedSec do
            local s = mergedSec[j]
            if s then
                local pNum = (type(s.pct) == "number") and s.pct or 0
                local rNum = (type(s.rating) == "number") and s.rating or 0
                secondaryRows[#secondaryRows + 1] = {
                    label = s.label,
                    pctStr = format("%.1f%%", pNum),
                    ratingStr = FormatNumber and FormatNumber(math.floor(rNum)) or tostring(math.floor(rNum)),
                }
            end
        end
    end
    local hasDivider = (#primaryRows > 0 and #secondaryRows > 0)
    local statContentRows = #primaryRows + #secondaryRows
    local statContentH = GEAR_SUBPANEL_HDR + (statContentRows * STAT_ROW_H) + (hasDivider and 10 or 0) + 14
    if statContentRows == 0 then
        statContentH = GEAR_SUBPANEL_HDR + 70
    end
    local statPanelH = statContentH
    local middleStackNatural = statPanelH + SECTION_GAP + currenciesH
    local naturalMainH = math.max(paperdollH, middleStackNatural)
    -- Card sized to content; do NOT expand to viewport (was leaving a huge dead band below sparse content).
    local panelH = naturalMainH
    local currencyBlockH = math.max(currenciesH, panelH - statPanelH - SECTION_GAP)

    local yPaperBandTop = panelTopY

    local paperChrome = CreateFrame("Frame", nil, card, "BackdropTemplate")
    paperChrome:SetPoint("TOPLEFT", card, "TOPLEFT", paperLeft, yPaperBandTop)
    paperChrome:SetSize(paperColW, paperdollH)
    paperChrome:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    paperChrome:SetBackdropColor(0.05, 0.05, 0.07, 0.38)
    paperChrome:SetBackdropBorderColor(accent[1] * 0.22, accent[2] * 0.22, accent[3] * 0.32, 0.30)
    paperChrome:EnableMouse(false)
    if paperChrome.SetFrameLevel and card.GetFrameLevel then
        paperChrome:SetFrameLevel((card:GetFrameLevel() or 2) + 1)
    end

    -- Plain layout frames (no nested border): avoids “box inside box” next to the gear card chrome.
    local statPanel = CreateFrame("Frame", nil, card)
    statPanel:SetSize(midColW, statPanelH)
    statPanel:SetPoint("TOPLEFT", card, "TOPLEFT", midLeft, panelTopY)
    statPanel:EnableMouse(false)
    if statPanel.SetFrameLevel then
        statPanel:SetFrameLevel((paperChrome:GetFrameLevel() or 3) + 2)
    end

    local currencyPanel = CreateFrame("Frame", nil, card)
    currencyPanel:SetSize(midColW, currencyBlockH)
    currencyPanel:SetPoint("TOPLEFT", statPanel, "BOTTOMLEFT", 0, -SECTION_GAP)
    currencyPanel:EnableMouse(false)
    if currencyPanel.SetClipsChildren then
        currencyPanel:SetClipsChildren(true)
    end
    if currencyPanel.SetFrameLevel then
        currencyPanel:SetFrameLevel(statPanel:GetFrameLevel() or 5)
    end

    local statPad = GEAR_SUBPANEL_PAD
    local statInnerW = math.max(1, midColW - statPad * 2)
    local valColW = 56
    local pctColW = 52
    local labelColW = statInnerW - pctColW - valColW - GEAR_STAT_COL_GAP * 2
    while labelColW < 34 do
        if pctColW > 40 then
            pctColW = pctColW - 2
        elseif valColW > 46 then
            valColW = valColW - 2
        else
            break
        end
        labelColW = statInnerW - pctColW - valColW - GEAR_STAT_COL_GAP * 2
    end
    local currPad = GEAR_SUBPANEL_PAD
    -- 3-value crest format ("362 \194\183 540 / 1000") needs more room than 2-value: bump reserve.
    local currAmtReserve = math.min(176, math.max(110, math.floor((midColW - currPad * 2) * 0.55)))

    -- Middle column: Character Stats, then Upgrade Currencies (reference: classic gear + side info strip).
    local statTitle = FontManager:CreateFontString(statPanel, GFR("gearSectionTitle"), "OVERLAY")
    statTitle:SetPoint("TOPLEFT", statPanel, "TOPLEFT", statPad, -8)
    statTitle:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, -8)
    statTitle:SetJustifyH("CENTER")
    statTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. ((ns.L and ns.L["GEAR_CHARACTER_STATS"]) or "Character Stats") .. "|r")
    statTitle:SetShadowOffset(1, -1)
    statTitle:SetShadowColor(0, 0, 0, 1)

    local function paintGearMidColumnDeferred()
        local statY = -GEAR_SUBPANEL_HDR

        if #primaryRows > 0 or #secondaryRows > 0 then
            for i = 1, #primaryRows do
                local stat = primaryRows[i]
                local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
                row:SetPoint("TOPLEFT", statPad, statY)
                row:SetWidth(labelColW)
                row:SetWordWrap(false)
                row:SetJustifyH("LEFT")
                row:SetTextColor(1, 1, 1)
                row:SetText(stat.label)
                row:SetShadowOffset(1, -1)
                row:SetShadowColor(0, 0, 0, 0.8)

                local mid = FontManager:CreateFontString(statPanel, GFR("gearPrimaryMid"), "OVERLAY")
                mid:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad - valColW - GEAR_STAT_COL_GAP, statY)
                mid:SetWidth(pctColW)
                mid:SetJustifyH("RIGHT")
                mid:SetText("")
                mid:SetTextColor(1, 1, 1)
                mid:SetShadowOffset(1, -1)
                mid:SetShadowColor(0, 0, 0, 0.8)

                local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
                val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
                val:SetWidth(valColW)
                val:SetJustifyH("RIGHT")
                val:SetTextColor(1, 1, 1)
                val:SetText(stat.value)
                val:SetShadowOffset(1, -1)
                val:SetShadowColor(0, 0, 0, 0.8)

                statY = statY - STAT_ROW_H
            end

            if hasDivider then
                local statDiv = statPanel:CreateTexture(nil, "ARTWORK")
                statDiv:SetPoint("TOPLEFT", statPad, statY - 2)
                statDiv:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY - 2)
                statDiv:SetHeight(1)
                statDiv:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)
                statY = statY - 10
            end

            for i = 1, #secondaryRows do
                local stat = secondaryRows[i]
                local row = FontManager:CreateFontString(statPanel, GFR("gearStatLabel"), "OVERLAY")
                row:SetPoint("TOPLEFT", statPad, statY)
                row:SetWidth(labelColW)
                row:SetWordWrap(false)
                row:SetJustifyH("LEFT")
                row:SetTextColor(1, 1, 1)
                row:SetText(stat.label)
                row:SetShadowOffset(1, -1)
                row:SetShadowColor(0, 0, 0, 0.8)

                local pctFs = FontManager:CreateFontString(statPanel, GFR("gearStatPct"), "OVERLAY")
                pctFs:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad - valColW - GEAR_STAT_COL_GAP, statY)
                pctFs:SetWidth(pctColW)
                pctFs:SetJustifyH("RIGHT")
                pctFs:SetTextColor(1, 1, 1)
                pctFs:SetText(stat.pctStr or "0.0%")
                pctFs:SetShadowOffset(1, -1)
                pctFs:SetShadowColor(0, 0, 0, 0.8)

                local val = FontManager:CreateFontString(statPanel, GFR("gearStatRating"), "OVERLAY")
                val:SetPoint("TOPRIGHT", statPanel, "TOPRIGHT", -statPad, statY)
                val:SetWidth(valColW)
                val:SetJustifyH("RIGHT")
                val:SetTextColor(1, 1, 1)
                val:SetText(stat.ratingStr or "0")
                val:SetShadowOffset(1, -1)
                val:SetShadowColor(0, 0, 0, 0.8)

                statY = statY - STAT_ROW_H
            end
        else
            local noStats = FontManager:CreateFontString(statPanel, GFR("gearEmptyStatsHint"), "OVERLAY")
            noStats:SetPoint("TOPLEFT", statPad, statY)
            noStats:SetWidth(statInnerW)
            noStats:SetJustifyH("CENTER")
            noStats:SetTextColor(0.45, 0.45, 0.45)
            noStats:SetText((ns.L and ns.L["GEAR_STATS_CURRENT_ONLY"]) or "Stats available for\ncurrent character only")
            noStats:SetShadowOffset(1, -1)
            noStats:SetShadowColor(0, 0, 0, 0.8)
        end

        -- Panel header (ortalanmış)
        local panelTitle = FontManager:CreateFontString(currencyPanel, GFR("gearPanelTitle"), "OVERLAY")
        panelTitle:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, -8)
        panelTitle:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, -8)
        panelTitle:SetJustifyH("CENTER")
        panelTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1]*255), math.floor(accent[2]*255), math.floor(accent[3]*255)) .. ((ns.L and ns.L["GEAR_UPGRADE_CURRENCIES"]) or "Upgrade Currencies") .. "|r")
        panelTitle:SetShadowOffset(1, -1)
        panelTitle:SetShadowColor(0, 0, 0, 1)

        -- Crest rows: icon | name (clipped) | fixed-width amount column (symmetric insets with stats panel).
        local curY = -GEAR_SUBPANEL_HDR
        local iconSize = 24
        for i = 1, #crestCurrencies do
            local cur = crestCurrencies[i]
            -- Alternating row bg
            local rowBg = currencyPanel:CreateTexture(nil, "BACKGROUND")
            rowBg:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
            rowBg:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
            rowBg:SetHeight(CREST_ROW_H)
            rowBg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

            local ico = currencyPanel:CreateTexture(nil, "ARTWORK")
            ico:SetSize(iconSize, iconSize)
            ico:SetPoint("TOPLEFT", currPad, curY - (CREST_ROW_H - iconSize) / 2)
            ico:SetTexture(cur.icon or "Interface\\Icons\\INV_Misc_Coin_01")
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local crestHit = CreateFrame("Frame", nil, currencyPanel)
            crestHit:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY + 1)
            crestHit:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY + 1)
            crestHit:SetHeight(CREST_ROW_H)
            crestHit:EnableMouse(true)
            crestHit:SetScript("OnEnter", function(self)
                if ShowTooltip then
                    ShowTooltip(self, {
                        type = "currency",
                        currencyID = cur.currencyID,
                        charKey = charKey,
                        anchor = "ANCHOR_RIGHT",
                    })
                elseif ns.TooltipService then
                    ns.TooltipService:Show(self, {
                        type = "currency",
                        currencyID = cur.currencyID,
                        charKey = charKey,
                        anchor = "ANCHOR_RIGHT",
                    })
                end
            end)
            crestHit:SetScript("OnLeave", function()
                if HideTooltip then
                    HideTooltip()
                elseif ns.TooltipService then
                    ns.TooltipService:Hide()
                end
            end)

            -- Name (left aligned; reserve currAmtReserve for amount column — symmetric rows)
            local nameText = FontManager:CreateFontString(currencyPanel, GFR("gearCurrencyLabel"), "OVERLAY")
            nameText:SetPoint("LEFT", ico, "RIGHT", 6, 0)
            nameText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad - currAmtReserve, 0)
            nameText:SetPoint("TOP", ico, "TOP", 0, 0)
            nameText:SetPoint("BOTTOM", ico, "BOTTOM", 0, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            nameText:SetTextColor(0.85, 0.85, 0.85)
            -- Always use the first word (e.g. Adventurer/Veteran) to keep labels crisp without truncation.
            local rawCrestName = cur.name or ""
            local displayCrestName = rawCrestName
            if rawCrestName and not (issecretvalue and issecretvalue(rawCrestName)) and rawCrestName ~= "" then
                local firstWord = rawCrestName:match("^(%S+)")
                firstWord = firstWord or rawCrestName
                local tierHex = GetUpgradeTrackHex(firstWord)
                if tierHex then
                    displayCrestName = "|cff" .. tierHex .. firstWord .. "|r"
                else
                    displayCrestName = firstWord
                end
            end
            nameText:SetText(displayCrestName)
            nameText:SetShadowOffset(1, -1)
            nameText:SetShadowColor(0, 0, 0, 0.8)

            -- Amount / cap: GetCurrencyData (same source as PvE + Currency tab) — season earned/max or weekly qty/cap + green/red
            local cd = WarbandNexus.GetCurrencyData and WarbandNexus:GetCurrencyData(cur.currencyID, charKey) or nil
            if not cd then
                local mq = (type(cur.maxQuantity) == "number" and cur.maxQuantity > 0) and cur.maxQuantity or 0
                cd = {
                    currencyID = cur.currencyID,
                    name = cur.name,
                    quantity = cur.amount or 0,
                    maxQuantity = mq,
                    totalEarned = nil,
                    seasonMax = nil,
                }
            end
            local amountText = FontManager:CreateFontString(currencyPanel, GFR("gearCurrencyAmount"), "OVERLAY")
            amountText:SetWidth(currAmtReserve - 4)
            amountText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad, 0)
            amountText:SetPoint("TOP", ico, "TOP", 0, 0)
            amountText:SetPoint("BOTTOM", ico, "BOTTOM", 0, 0)
            amountText:SetJustifyH("RIGHT")
            amountText:SetShadowOffset(1, -1)
            amountText:SetShadowColor(0, 0, 0, 0.8)
            if ns.UI_BindSeasonProgressAmount then
                ns.UI_BindSeasonProgressAmount(amountText, cd)
            elseif ns.UI_FormatSeasonProgressCurrencyLine then
                amountText:SetText(ns.UI_FormatSeasonProgressCurrencyLine(cd) or "")
            end

            curY = curY - CREST_ROW_H
        end

        -- Divider line
        local divider = currencyPanel:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", currencyPanel, "TOPLEFT", currPad, curY - 4)
        divider:SetPoint("TOPRIGHT", currencyPanel, "TOPRIGHT", -currPad, curY - 4)
        divider:SetHeight(1)
        divider:SetColorTexture(accent[1] * 0.3, accent[2] * 0.3, accent[3] * 0.3, 0.6)

        -- Gold row
        if goldCurrency then
            curY = curY - 14
            local goldIco = currencyPanel:CreateTexture(nil, "ARTWORK")
            goldIco:SetSize(iconSize, iconSize)
            goldIco:SetPoint("TOPLEFT", currPad, curY)
            goldIco:SetTexture(goldCurrency.icon or 133784)
            goldIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local goldText = FontManager:CreateFontString(currencyPanel, GFR("gearGoldLabel"), "OVERLAY")
            goldText:SetPoint("LEFT", goldIco, "RIGHT", 6, 0)
            goldText:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad - currAmtReserve, 0)
            goldText:SetJustifyH("LEFT")
            goldText:SetWordWrap(false)
            goldText:SetTextColor(1, 0.82, 0)
            goldText:SetText((ns.L and ns.L["GOLD_LABEL"]) or "Gold")
            goldText:SetShadowOffset(1, -1)
            goldText:SetShadowColor(0, 0, 0, 0.8)

            local goldAmt = FontManager:CreateFontString(currencyPanel, GFR("gearGoldAmount"), "OVERLAY")
            goldAmt:SetWidth(currAmtReserve - 4)
            goldAmt:SetPoint("RIGHT", currencyPanel, "RIGHT", -currPad, 0)
            goldAmt:SetPoint("TOP", goldIco, "TOP", 0, 0)
            goldAmt:SetPoint("BOTTOM", goldIco, "BOTTOM", 0, 0)
            goldAmt:SetJustifyH("RIGHT")
            goldAmt:SetShadowOffset(1, -1)
            goldAmt:SetShadowColor(0, 0, 0, 0.8)
            local copper = (goldCurrency.amount or 0) * 10000 + (goldCurrency.silver or 0) * 100 + (goldCurrency.copper or 0)
            goldAmt:SetText("|cffffff00" .. FormatGold(copper) .. "|r")
        end

        -- Short hint under gold (season progress on crest amounts).
        local shiftHint = FontManager:CreateFontString(currencyPanel, "small", "OVERLAY")
        shiftHint:SetPoint("BOTTOMLEFT", currencyPanel, "BOTTOMLEFT", currPad, 4)
        shiftHint:SetPoint("BOTTOMRIGHT", currencyPanel, "BOTTOMRIGHT", -currPad, 4)
        shiftHint:SetJustifyH("RIGHT")
        shiftHint:SetText("|cff777777" .. GetLocalizedText("SHIFT_HINT_SEASON_PROGRESS_SHORT", "Shift: Season progress") .. "|r")
        shiftHint:SetShadowOffset(1, -1)
        shiftHint:SetShadowColor(0, 0, 0, 0.8)
    end

    local recScroll, recContent, scroll, storageContentW = nil, nil, nil, nil
    local storagePad = 8
    local storageHeaderH = 32
    local storageBarW = 22
    local rowH = 32
    -- Storage row data before the panel shell so overflow math matches the deferred row paint pass.
    local storageRows = {}
    if recEnabled then
    do
            local equippedSlots = gearData and gearData.slots or {}
            local seenItemLink = {}
            if storageFindings then
                for slotID, candidates in pairs(storageFindings) do
                    local best = candidates and candidates[1]
                    if best then
                        local current = (equippedSlots[slotID] and equippedSlots[slotID].itemLevel) or 0
                        local target = best.itemLevel or 0
                        if target > current then
                            local linkKey = best.itemLink or ("id:" .. tostring(best.itemID or 0))
                            if not seenItemLink[linkKey] then
                                seenItemLink[linkKey] = true
                                local slotDef = SLOT_BY_ID and SLOT_BY_ID[slotID]
                                storageRows[#storageRows + 1] = {
                                    slotID = slotID,
                                    slotName = (slotDef and slotDef.label) or GetLocalizedText("GEAR_SLOT_FALLBACK_FORMAT", "Slot %d"):format(tonumber(slotID) or 0),
                                    currentIlvl = current,
                                    targetIlvl = target,
                                    itemLink = best.itemLink,
                                    itemID = best.itemID,
                                    source = best.source or "",
                                    sourceType = best.sourceType or "",
                                    sourceClassFile = best.sourceClassFile,
                                    delta = target - current,
                                }
                            end
                        end
                    end
                end
            end
            table.sort(storageRows, function(a, b)
                if a.delta ~= b.delta then return a.delta > b.delta end
                return a.slotID < b.slotID
            end)
        end

        -- ── RIGHT PANEL: Item Upgrade Recommendations (scrollable, bordered) ───────
        local storagePanel = CreateFrame("Frame", nil, card, "BackdropTemplate")
        local storagePanelH = panelH
        storagePanel:SetWidth(storageW)
        storagePanel:SetHeight(storagePanelH)
        storagePanel:SetPoint("TOPLEFT", card, "TOPLEFT", midLeft + midColW + PANEL_GAP, panelTopY)
        storagePanel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        storagePanel:SetBackdropColor(0.06, 0.06, 0.08, 0.86)
        storagePanel:SetBackdropBorderColor(accent[1] * 0.36, accent[2] * 0.36, accent[3] * 0.46, 0.52)
        local storageTitle = FontManager:CreateFontString(storagePanel, GFR("gearStorageCardTitle"), "OVERLAY")
        storageTitle:SetPoint("TOPLEFT", 12, -8)
        storageTitle:SetPoint("TOPRIGHT", -12, -8)
        storageTitle:SetText("|cff" .. format("%02x%02x%02x", math.floor(accent[1] * 255), math.floor(accent[2] * 255), math.floor(accent[3] * 255))
            .. GetLocalizedText("GEAR_ITEM_UPGRADE_RECOMMENDATIONS_TITLE", "Item Upgrade Recommendations") .. "|r")

        local viewportH = storagePanelH - storageHeaderH - storagePad - 10
        scroll = ns.UI.Factory and ns.UI.Factory.CreateScrollFrame and ns.UI.Factory:CreateScrollFrame(storagePanel, "UIPanelScrollFrameTemplate", true)
        local sbCol
        -- Pre-compute overflow so we can decide whether to reserve space for the scrollbar column at all.
        local rowsOverflow = (#storageRows * rowH) > viewportH
        if scroll then
            if scroll.SetFrameLevel and storagePanel.GetFrameLevel then
                scroll:SetFrameLevel(storagePanel:GetFrameLevel() + 2)
            end
            sbCol = ns.UI.Factory and ns.UI.Factory.CreateScrollBarColumn and ns.UI.Factory:CreateScrollBarColumn(storagePanel, storageBarW, storagePad, storagePad)
            if sbCol and scroll.ScrollBar and ns.UI.Factory and ns.UI.Factory.PositionScrollBarInContainer then
                ns.UI.Factory:PositionScrollBarInContainer(scroll.ScrollBar, sbCol, 0)
            end
            scroll:SetPoint("TOPLEFT", storagePad, -storageHeaderH)
            -- Hide the scrollbar column entirely when no overflow, and let scroll area reclaim its width.
            if rowsOverflow then
                scroll:SetPoint("BOTTOMRIGHT", -storageBarW, storagePad)
                if sbCol and sbCol.Show then sbCol:Show() end
            else
                scroll:SetPoint("BOTTOMRIGHT", -storagePad, storagePad)
                if sbCol and sbCol.Hide then sbCol:Hide() end
            end
            local content = CreateFrame("Frame", nil, scroll)
            recScroll = scroll
            recContent = content
            local contentW = rowsOverflow
                and math.max(120, storageW - storagePad * 2 - storageBarW)
                or  math.max(120, storageW - storagePad * 2)
            storageContentW = contentW
            content:SetWidth(contentW)
            content:SetHeight(math.max(#storageRows * rowH, viewportH))
            scroll:SetScrollChild(content)

            if #storageRows == 0 then
                local empty = FontManager:CreateFontString(content, GFR("gearStorageEmpty"), "OVERLAY")
                content._gearStorageStatusFont = empty
                empty:SetAllPoints()
                empty:SetJustifyH("CENTER")
                empty:SetJustifyV("MIDDLE")
                if storageScanPending then
                    empty:SetText(GetLocalizedText("GEAR_STORAGE_SCANNING", "Scanning storage for upgrades..."))
                    empty:SetTextColor(0.65, 0.68, 0.75)
                else
                    empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY_NO_BOE_WOE", "Can't find any BoE or WoE to upgrade on item slots."))
                    empty:SetTextColor(0.55, 0.55, 0.6)
                end
            end
            if ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scroll)
            end
            local mfHost = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mfHost and recContent and recScroll and storagePanel then
                mfHost._gearStorageRecHost = {
                    drawGen = ns._gearTabDrawGen,
                    canonKey = charKey,
                    recContent = recContent,
                    recScroll = recScroll,
                    sbCol = sbCol,
                    storagePanel = storagePanel,
                    storageW = storageW,
                    storagePad = storagePad,
                    storageHeaderH = storageHeaderH,
                    storageBarW = storageBarW,
                    rowH = rowH,
                }
            end
        end
    end

    -- Equipped paperdoll after the storage shell so slot buttons stack above the recommendations subtree on `card`.
    DrawPaperDollInCard(card, charData or {}, gearData, upgradeInfo, currencyAmounts, isCurrentChar == true, paperdollBaseX, charKey, yPaperBandTop, paperdollH, paperdollH, { deferCenter = true })

    -- Staged paint: one idle tick per stage (mid+center -> storage rows -> slot inspect) to avoid stacking FRAME SPIKEs.
    local gearDeferGen = ns._gearTabDrawGen
    local mfDefer = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfDefer then
        mfDefer._gearDeferChainActive = true
    end
    local function scheduleGearStorageTryStartOnce(genNow)
        if not mfDefer then return end
        -- `finishGearDeferChain` can run more than once per paint (early exits + final slot batch).
        -- Without this, two C_Timer(0) calls race: the second sees `pending` nil and used to orphan `_gearStorageDeferAwaiting`.
        if mfDefer._gearStorageTryStartScheduledFor == genNow then
            return
        end
        mfDefer._gearStorageTryStartScheduledFor = genNow
        C_Timer.After(0, function()
            mfDefer._gearStorageTryStartScheduledFor = nil
            TryStartPendingGearStorageScan(mfDefer, genNow)
        end)
    end

    local function finishGearDeferChain()
        if mfDefer then
            mfDefer._gearDeferChainActive = false
            local genNow = ns._gearTabDrawGen or 0
            TryDismissGearContentVeil(mfDefer, genNow)
            if WarbandNexus:IsGearStorageRecommendationsEnabled() then
                local scanPending = mfDefer._gearPendingStorageScan
                if scanPending and scanPending.paintGen == genNow then
                    scheduleGearStorageTryStartOnce(genNow)
                elseif ns._gearStorageDeferAwaiting and ns._gearStorageDeferAwaitCanon
                    and mfDefer._gearPopulateCanonKey == ns._gearStorageDeferAwaitCanon then
                    mfDefer._gearPendingStorageScan = {
                        canon = ns._gearStorageDeferAwaitCanon,
                        paintGen = genNow,
                    }
                    scheduleGearStorageTryStartOnce(genNow)
                end
            else
                ns._gearStorageDeferAwaiting = false
                ns._gearStorageDeferAwaitCanon = nil
                mfDefer._gearPendingStorageScan = nil
            end
        end
    end
    C_Timer.After(0, function()
        if gearDeferGen ~= ns._gearTabDrawGen then
            finishGearDeferChain()
            return
        end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
            finishGearDeferChain()
            return
        end
        if not card or not card.GetParent or not card:GetParent() then
            finishGearDeferChain()
            return
        end
        local P = ns.Profiler
        local function runMid()
            paintGearMidColumnDeferred()
        end
        if P and P.enabled and P.Wrap and P.SliceLabel then
            P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_MidColumn_deferred"), runMid)
        else
            runMid()
        end

        local centerFn = card._gearPaperdollCenterDefer
        card._gearPaperdollCenterDefer = nil
        local function runStorageRowsThenInspect()
            if scroll and recContent and #storageRows > 0 and storageContentW then
                local nStorageRows = #storageRows
                local function fillStorageRows()
                    PaintGearStorageRowsBatched(recContent, recScroll, storageRows, storageContentW, rowH, charData, gearDeferGen, nil)
                end
                if P and P.enabled and P.Wrap and P.SliceLabel then
                    P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_StorageRows_deferred"), fillStorageRows)
                else
                    fillStorageRows()
                end
            end

            if card._gearSlotInspectList and #card._gearSlotInspectList > 0 then
                local slotList = card._gearSlotInspectList
                local inspectIdx = 1
                local SLOTS_PER_FRAME = 5
                local function runSlotInspectBatch()
                    if gearDeferGen ~= (ns._gearTabDrawGen or 0) then
                        finishGearDeferChain()
                        return
                    end
                    if not (WarbandNexus.IsStillOnTab and WarbandNexus:IsStillOnTab("gear")) then
                        finishGearDeferChain()
                        return
                    end
                    if not card or not card.GetParent or not card:GetParent() then
                        finishGearDeferChain()
                        return
                    end
                    local function runSlice()
                        local n = #slotList
                        local endIdx = math.min(inspectIdx + SLOTS_PER_FRAME - 1, n)
                        for si = inspectIdx, endIdx do
                            local sb = slotList[si]
                            if sb and sb._needsDeferredInspect then
                                GearSlotApplyDeferredEnchantGemInspect(sb)
                            end
                        end
                        inspectIdx = endIdx + 1
                        if inspectIdx <= n then
                            C_Timer.After(0, runSlotInspectBatch)
                        else
                            finishGearDeferChain()
                        end
                    end
                    if P and P.enabled and P.Wrap and P.SliceLabel then
                        P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_SlotInspect_deferred"), runSlice)
                    else
                        runSlice()
                    end
                end
                C_Timer.After(0, runSlotInspectBatch)
            else
                finishGearDeferChain()
            end
        end

        if centerFn then
            C_Timer.After(0, function()
                if gearDeferGen ~= ns._gearTabDrawGen then
                    finishGearDeferChain()
                    return
                end
                if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then
                    finishGearDeferChain()
                    return
                end
                if not card or not card.GetParent or not card:GetParent() then
                    finishGearDeferChain()
                    return
                end
                if P and P.enabled and P.Wrap and P.SliceLabel then
                    P:Wrap(P:SliceLabel(P.CAT.UI, "Gear_PaperdollCenter_deferred"), centerFn)
                else
                    centerFn()
                end
                C_Timer.After(0, runStorageRowsThenInspect)
            end)
        else
            C_Timer.After(0, runStorageRowsThenInspect)
        end
    end)

    cardH = CARD_PAD + 24 + panelH + CARD_PAD
    if recContent then
        local newViewportH = panelH - storageHeaderH - storagePad - 10
        recContent:SetHeight(math.max(#storageRows * rowH, math.max(newViewportH, 40)))
        if recScroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(recScroll)
        end
    end

    card:SetHeight(cardH)

    card:Show()
    local mfHost = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfHost then
        mfHost._gearPaperdollCard = card
    end
    return yOffset - cardH - 12, cardH
end

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
    if not WarbandNexus:IsGearStorageRecommendationsEnabled() then
        return false
    end
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then return false end
    end
    local mf = self.UI and self.UI.mainFrame
    if not mf then return false end
    if expectedDrawGen ~= (ns._gearTabDrawGen or 0) then return false end

    local host = mf._gearStorageRecHost
    if not host or host.drawGen ~= expectedDrawGen then return false end
    local hostCanon = host.canonKey
    local wantCanon = expectedCanonKey
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        hostCanon = U:GetCanonicalCharacterKey(hostCanon) or hostCanon
        wantCanon = U:GetCanonicalCharacterKey(wantCanon) or wantCanon
    end
    if hostCanon ~= wantCanon then return false end

    local recContent = host.recContent
    local recScroll = host.recScroll
    local storagePanel = host.storagePanel
    if not recContent or not recScroll or not storagePanel then return false end
    if not recContent.GetParent or not recContent:GetParent() then return false end

    -- Yielded storage scan still pumping: keep the loading line; do not return false (avoids applyStorageScanUI Populate storm).
    if ns._gearStorageYieldCo and ns._gearStorageYieldFindCanon == expectedCanonKey then
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
            ShowGearStorageScanningInRecContent(recContent)
            return true
        end
        -- Never run a full cross-character Find on the UI thread (~25-30ms per call). Schedule yielded scan.
        stStop("Gear_StorageRec_resolve")
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
        end
        return true
        end
    end
    findings = findings or {}
    stStop("Gear_StorageRec_resolve")

    stStart("Gear_StorageRec_rows")
    local gearData = (self.GetEquippedGear and self:GetEquippedGear(expectedCanonKey)) or {}
    local rows = BuildStorageRecommendationRows(findings, gearData)
    stStop("Gear_StorageRec_rows")

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
    local rowsOverflow = (#rows * rowH) > viewportH

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
        return true
    end

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
        headerExtra = 22
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
        empty:SetText(GetLocalizedText("GEAR_STORAGE_EMPTY_NO_BOE_WOE", "Can't find any BoE or WoE to upgrade on item slots."))
        empty:SetTextColor(0.55, 0.55, 0.6)
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
    return true
end

--- Minimal slot snapshot from live inventory (equip events before DB read catches up).
---@param slotID number
---@return table|nil
local function BuildLiveEquippedSlotSnapshot(slotID)
    if not slotID or not GetInventoryItemLink then return nil end
    local itemLink = GetInventoryItemLink("player", slotID)
    if not itemLink or (issecretvalue and issecretvalue(itemLink)) then return nil end
    local itemID = nil
    pcall(function()
        if C_Item and C_Item.GetItemInfoInstant then
            itemID = C_Item.GetItemInfoInstant(itemLink)
        end
    end)
    if not itemID and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
        local idFromLink = itemLink:match("item:(%d+)")
        itemID = idFromLink and tonumber(idFromLink) or nil
    end
    if not itemID and not itemLink then return nil end
    local quality = 0
    local ilvl = 0
    pcall(function()
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local v = C_Item.GetDetailedItemLevelInfo(itemLink)
            if v and v > 0 then ilvl = v end
        end
    end)
    pcall(function()
        if C_Item and C_Item.GetItemInfo then
            local _, _, q, level = C_Item.GetItemInfo(itemLink)
            if q then quality = q end
            if (not ilvl or ilvl <= 0) and level and level > 0 then ilvl = level end
        end
    end)
    return {
        itemID = itemID,
        itemLink = itemLink,
        itemLevel = ilvl,
        quality = quality,
    }
end

--- True when slot data or prior ref carries a non-empty item link (not secret).
---@param slotRef table|nil
---@return boolean
local function GearSlotHasInspectableItemLink(slotRef)
    if not slotRef or not slotRef.itemLink or slotRef.itemLink == "" then return false end
    if issecretvalue and issecretvalue(slotRef.itemLink) then return true end
    return true
end

--- Skip redundant _gearApplySlotVisual when icon/labels/overlays already match.
---@param sb Frame|nil
---@param slotData table|nil
---@param canUpgrade boolean|nil
---@param trackText string|nil
---@param notUpgradeable boolean|nil
---@return boolean
local function GearSlotPaperdollVisualEquals(sb, slotData, canUpgrade, trackText, notUpgradeable)
    if not sb then return false end
    local prev = sb._slotDataRef
    local newLink = slotData and slotData.itemLink
    local prevLink = prev and prev.itemLink
    if newLink and issecretvalue and issecretvalue(newLink) then return false end
    if prevLink and issecretvalue and issecretvalue(prevLink) then return false end
    local function linkEmpty(l)
        return not l or l == ""
    end
    if linkEmpty(newLink) ~= linkEmpty(prevLink) then return false end
    if not linkEmpty(newLink) and newLink ~= prevLink then return false end

    local function asNum(x)
        local n = tonumber(x)
        return (type(n) == "number") and n or 0
    end
    if asNum(slotData and slotData.itemLevel) ~= asNum(prev and prev.itemLevel) then return false end
    if asNum(slotData and slotData.quality) ~= asNum(prev and prev.quality) then return false end
    if asNum(slotData and slotData.itemID) ~= asNum(prev and prev.itemID) then return false end

    if not linkEmpty(newLink) and newLink == prevLink then
        local nsig = ""
        local okSig, _ent, sig = pcall(ComputeGearSocketLayout, newLink, sb._slotID, sb._gearIsCurrentChar == true)
        if okSig and type(sig) == "string" then nsig = sig end
        local osig = (sb._gearInspectSt and sb._gearInspectSt.socketSig) or ""
        if nsig ~= osig then return false end
    end

    local upShown = sb._gearUpgradeArrow and sb._gearUpgradeArrow:IsShown() == true
    local up = sb._gearUpgradeInfo and sb._gearUpgradeInfo[sb._slotID]
    local expectUpgradeShown = GearUpgradeInfoHasPath(up)
        or (GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and slotData and slotData.itemLink and slotData.itemLink ~= ""
            and not (issecretvalue and issecretvalue(slotData.itemLink)))
    if expectUpgradeShown ~= upShown then return false end

    local aff = canUpgrade == true
    if sb._gearLastCanAffordNext ~= aff then return false end

    local wantLock = false
    if not (GEAR_DEBUG_ALWAYS_SHOW_UPGRADE and slotData and slotData.itemLink and slotData.itemLink ~= ""
        and not (issecretvalue and issecretvalue(slotData.itemLink))) then
        if notUpgradeable and slotData and slotData.itemLink
            and not (issecretvalue and issecretvalue(slotData.itemLink)) then
            wantLock = true
        end
    end
    local lockShown = sb._gearLockIcon and sb._gearLockIcon:IsShown() == true
    if wantLock ~= lockShown then return false end

    local tNew = (type(trackText) == "string" and trackText ~= "") and trackText or ""
    local tOld = ""
    local tl = sb._gearTrackLabel
    if tl and tl.IsShown and tl:IsShown() and tl.GetText then
        tOld = tl:GetText() or ""
    end
    if tNew ~= tOld then return false end

    return true
end

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
        local partner = GEAR_REFRESH_PAIR_SLOTS[sid]
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
                liveSnap = BuildLiveEquippedSlotSnapshot(slotID)
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
            local trackText = GetSlotTrackText(upgradeInfo, slotID, quality, currencyAmounts)
            local bypassDiff = isViewingCurrent and not liveSnap
                and (GearSlotHasInspectableItemLink(slotData) or GearSlotHasInspectableItemLink(sb._slotDataRef))
            if bypassDiff then
                needFollowUp = true
            end
            if not bypassDiff and GearSlotPaperdollVisualEquals(sb, slotData, canUpgrade, trackText, notUpgradeable) then
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
                GearSlotApplyDeferredEnchantGemInspect(sb)
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
    local partner = GEAR_REFRESH_PAIR_SLOTS[sid]
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
    local layout = ns.UI_LAYOUT or {}
    local SCROLL_COL_EST = layout.SCROLLBAR_COLUMN_WIDTH or 22
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
            local Factory = ns.UI and ns.UI.Factory
            local layoutLocal = ns.UI_LAYOUT or {}
            local SCROLL_COL = layoutLocal.SCROLLBAR_COLUMN_WIDTH or 22
            local MENU_EDGE = 4

            if Factory and Factory.CreateScrollFrame and Factory.CreateScrollBarColumn and Factory.PositionScrollBarInContainer then
                menu._barColumn = Factory:CreateScrollBarColumn(menu, SCROLL_COL, MENU_EDGE, MENU_EDGE)
                local sf = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
                sf:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_EDGE, -MENU_EDGE)
                sf:SetPoint("BOTTOMRIGHT", menu._barColumn, "BOTTOMLEFT", -2, MENU_EDGE)
                if sf.SetClipsChildren then
                    sf:SetClipsChildren(true)
                end
                local sc = CreateFrame("Frame", nil, sf)
                sf:SetScrollChild(sc)
                menu._charScroll = sf
                menu._charScrollChild = sc
                if sf.ScrollBar then
                    Factory:PositionScrollBarInContainer(sf.ScrollBar, menu._barColumn, 0)
                end
                sf:SetScript("OnSizeChanged", function(frame, w)
                    if sc and w and w > 0 then
                        sc:SetWidth(w)
                    end
                end)
            else
                local sf = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
                sf:SetPoint("TOPLEFT", 4, -4)
                sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -4, 4)
                if sf.SetClipsChildren then
                    sf:SetClipsChildren(true)
                end
                local sc = CreateFrame("Frame", nil, sf)
                sf:SetScrollChild(sc)
                menu._charScroll = sf
                menu._charScrollChild = sc
                menu._barColumn = nil
                sf:SetScript("OnSizeChanged", function(frame, w)
                    if sc and w and w > 0 then
                        sc:SetWidth(w)
                    end
                end)
            end
            gearCharDropdownMenu = menu
        end
        if not bg then
            bg = CreateFrame("Button", nil, UIParent)
            bg:SetAllPoints()
            bg:SetFrameStrata("FULLSCREEN_DIALOG")
            bg:SetFrameLevel(499)
            bg:SetScript("OnClick", function()
                menu:Hide()
                bg:Hide()
                if WarbandNexus and WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "gear", skipCooldown = true })
                end
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
                entryBtn = CreateFrame("Button", nil, entryParent)
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
                if WarbandNexus and WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "gear",
                        skipCooldown = true,
                        instantPopulate = true,
                    })
                end
            end)

            entryBtn:Show()
            entryY = entryY - ENTRY_H
        end

        local Factory = ns.UI and ns.UI.Factory
        local function SyncDropdownScroll()
            if not menu or not menu:IsShown() or not scroll or not scrollChild then return end
            local sw = scroll:GetWidth()
            if sw and sw > 0 then
                scrollChild:SetWidth(sw)
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(scroll)
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
            catcher = CreateFrame("Button", nil, UIParent)
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

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = TOP_MARGIN
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
    -- Reserve space for [Hide filter][Character ▼] using shared title-card toolbar inset + gap.
    local layoutInset = (ns.UI_LAYOUT and ns.UI_LAYOUT.TITLE_CARD_CONTROL_RIGHT_INSET) or 20
    local layoutGap = (ns.UI_LAYOUT and ns.UI_LAYOUT.HEADER_TOOLBAR_CONTROL_GAP) or 8
    local gearHeaderRightReserve = GEAR_CHAR_SELECTOR_WIDTH + GEAR_HIDE_FILTER_BUTTON_W + layoutGap + layoutInset + 4

    local headerCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "gear",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = gearHeaderRightReserve,
        cardHeight = 75,
    }))
    headerCard:SetPoint("TOPLEFT",  SIDE_MARGIN, -headerYOffset)
    headerCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)

    local gearCharSel = CreateCharacterSelector(headerCard, charKey, 0)
    local hideBtn = CreateGearHeaderHideButton(headerCard)
    if hideBtn and gearCharSel then
        hideBtn:SetPoint("RIGHT", gearCharSel, "LEFT", -(ns.UI_LAYOUT and ns.UI_LAYOUT.HEADER_TOOLBAR_CONTROL_GAP or 8), 0)
    elseif hideBtn then
        hideBtn:SetPoint("RIGHT", headerCard, "RIGHT", -layoutInset, 0)
    end
    headerCard:Show()
    if gearCharSel and gearCharSel._refreshGearCharColumns then
        C_Timer.After(0, function()
            if gearCharSel.GetParent and gearCharSel:GetParent() then
                gearCharSel._refreshGearCharColumns()
            end
        end)
    end

    -- Use shared header spacing so Gear matches the global tab header rhythm.
    headerYOffset = headerYOffset + (GetLayout().afterHeader or 75)

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    pGearSliceStop("Gear_headerCard")

    --- Scroll-body paint (data + paperdoll). When splitPaperDollToNextTick, DB reads run now, card draw next tick.
    local function paintGearScrollBody(splitPaperDollToNextTick)
    local yOffset = -TOP_MARGIN
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

    pGearSliceStart("Gear_data_upgradeInfo")
    local upgradeInfo = (self.GetPersistedUpgradeInfo and self:GetPersistedUpgradeInfo(canonicalKey)) or {}
    pGearSliceStop("Gear_data_upgradeInfo")

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
    pGearSliceStop("Gear_dataSync")

    local function finishPaperDollAndSig()
        pGearSliceStart("Gear_paperDollDraw")
        yOffset = DrawPaperDollCard(
            parent, yOffset, charData, gearData, upgradeInfo, canonicalKey, currencyAmounts,
            canonicalKey == currentKey, currencies, storageFindings, storageScanPending
        )
        pGearSliceStop("Gear_paperDollDraw")
        local outH = math.abs(yOffset) + TOP_MARGIN
        local mfOut = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        pGearSliceStart("Gear_populateSig")
        if mfOut and WarbandNexus.GetGearPopulateSignatureFromDrawCaches then
            mfOut._gearPopulateContentSig = WarbandNexus:GetGearPopulateSignatureFromDrawCaches(gearData, currencies, upgradeInfo)
        elseif mfOut and WarbandNexus.GetGearPopulateSignature then
            mfOut._gearPopulateContentSig = WarbandNexus:GetGearPopulateSignature()
        end
        pGearSliceStop("Gear_populateSig")
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
                local pad = 8
                local viewportH = GearResultsViewportHeight(mfGear)
                sc:SetHeight(math.max(outH + pad, viewportH))
            end
        end)
        return GearResultsViewportHeight(mfGear)
    end

    return finishPaperDollAndSig()
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
        return math.max(viewportH, 480)
    end

    return paintGearScrollBody()
end

ns.UI_EnsureGearTabLoadingVeil = EnsureGearContentVeil
ns.UI_TryDismissGearTabLoadingVeil = TryDismissGearContentVeil
