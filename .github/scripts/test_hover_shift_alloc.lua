#!/usr/bin/env lua
--[[
    Regression test: hover / Shift / scroll hot paths do not redo work that cannot have changed.

    Audit 2026-10-22 (perf/audit-2026-10), each phase loads the shipped file(s) and drives them:
      A  FormatHelpers: a Shift MODIFIER_STATE_CHANGED re-formats only visible bound cells; a hidden
         cell is correct again after the next paint (re-bind), and theme / toggle refreshes still
         reach hidden cells.
      B  VaultButton_Data: same for the vault Shift watcher, and one options table for every cell.
      C  Achievement browse: earned-meta text computed once per achievement per draw generation;
         populate starts a new generation; scroll events coalesce to one repaint per frame;
         the warband class-colour lookup does not lowercase the whole roster per call.
      D  GameTooltip hover: keystone check once per hover; no mount/pet journal lookups without a
         mount/pet plan; zone drops walk C_Map once per map; item-ID label built once per theme;
         concentration Show hook gates on ProfessionsFrame before probing the tooltip and does not
         rebuild line names per line.
      E  TooltipService / TooltipFactory: placement candidates are not rebuilt per Show (same
         order as before); tooltip line entries are pooled; the currency breakdown resolves the
         current character key once.

    Allocation checks run with the JIT off and the GC stopped, so the KB counts are deterministic.
]]

if jit and jit.off then jit.off() end

local passed, failed = 0, 0
local function check(cond, msg, detail)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
end

local ROOT = os.getenv("WN_ROOT") or "."

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

local function LoadFile(rel, ns)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

-- ---------- shared WoW stubs ----------
local timers = {}
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTimer = function(_, fn) timers[#timers + 1] = fn; return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
}
local function RunTimers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        if guard > 1000 then error("timer storm") end
        local batch = timers
        timers = {}
        for i = 1, #batch do pcall(batch[i]) end
    end
end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
strsplit = function(sep, str)
    local out = {}
    for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
end
issecretvalue = function() return false end
hooksecurefunc = function() end
GetTime = function() return 1000 end
GetLocale = function() return "enUS" end
GetScreenWidth = function() return 1920 end
GetScreenHeight = function() return 1080 end
InCombatLockdown = function() return false end
debugprofilestop = function() return 0 end

local shiftDown = false
IsShiftKeyDown = function() return shiftDown end

-- Every created frame; Fire() dispatches OnEvent to the ones that registered the event.
local frames = {}
local NewFrame
function NewFrame()
    local f = { _events = {}, _scripts = {}, _shown = true }
    function f:RegisterEvent(ev) self._events[ev] = true end
    function f:UnregisterEvent(ev) self._events[ev] = nil end
    function f:SetScript(name, fn) self._scripts[name] = fn end
    function f:HookScript(name, fn) self._scripts[name] = fn end
    function f:GetScript(name) return self._scripts[name] end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:IsShown() return self._shown end
    setmetatable(f, { __index = function(t, k)
        -- Methods only (WoW widget API is PascalCase); data fields stay nil.
        if type(k) ~= "string" or not k:find("^[A-Z]") then return nil end
        local fn = function() end
        if type(k) == "string" and k:find("^Create") then
            fn = function() return NewFrame() end
        end
        rawset(t, k, fn)
        return fn
    end })
    frames[#frames + 1] = f
    return f
end
CreateFrame = function() return NewFrame() end
UIParent = NewFrame()

local function Fire(event, ...)
    for i = 1, #frames do
        local f = frames[i]
        if f._events[event] and f._scripts.OnEvent then
            f._scripts.OnEvent(f, event, ...)
        end
    end
end

--- Fake FontString: counts SetText, visibility under test control.
local function NewFontString(visible)
    local fs = { sets = 0, text = nil, visible = visible ~= false }
    function fs:SetText(t) self.sets = self.sets + 1; self.text = t end
    function fs:GetText() return self.text end
    function fs:IsObjectType() return true end
    function fs:IsVisible() return self.visible end
    return fs
end

-- ======================================================================
print("Phase A: FormatHelpers Shift watcher skips hidden cells")
-- ======================================================================
do
    local ns = { UI = {} }
    ns.UI_GetIconMarkup = function(name) return "<" .. name .. ">" end
    LoadFile("Modules/UI/FormatHelpers.lua", ns)

    local visibleFs, hiddenFs = NewFontString(true), NewFontString(false)
    local bounty = { done = true }
    ns.UI_BindPvEBountyDisplay(visibleFs, bounty)
    ns.UI_BindPvEBountyDisplay(hiddenFs, bounty)
    local before = visibleFs.text
    check(before == hiddenFs.text and before ~= nil, "bound cells start with the same text")

    local vSets, hSets = visibleFs.sets, hiddenFs.sets
    shiftDown = true
    Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    check(visibleFs.sets == vSets + 1, "Shift re-formats the visible cell")
    check(visibleFs.text ~= before, "visible cell shows the Shift view", visibleFs.text)
    check(hiddenFs.sets == hSets, "Shift does not re-format a hidden cell", hiddenFs.sets - hSets)

    -- The tab paint that shows the row again re-binds it, which formats with the live Shift state.
    hiddenFs.visible = true
    ns.UI_BindPvEBountyDisplay(hiddenFs, bounty)
    check(hiddenFs.text == visibleFs.text, "hidden cell is correct after the next paint")

    -- Season amount bindings follow the same rule.
    local sv, sh = NewFontString(true), NewFontString(false)
    local cd = { quantity = 5, totalEarned = 40, seasonMax = 100, currencyID = 1 }
    ns.UI_BindSeasonProgressAmount(sv, cd, { pveDisplayMode = true })
    ns.UI_BindSeasonProgressAmount(sh, cd, { pveDisplayMode = true })
    local svSets, shSets = sv.sets, sh.sets
    shiftDown = false
    Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    check(sv.sets == svSets + 1 and sh.sets == shSets, "season binding: Shift skips the hidden cell",
        string.format("visible +%d hidden +%d", sv.sets - svSets, sh.sets - shSets))

    -- Theme / display-mode refresh is not Shift: it must still reach hidden cells.
    local shBefore = sh.sets
    ns.UI_RefreshSeasonProgressBindings()
    check(sh.sets == shBefore + 1, "theme refresh still re-formats hidden cells")
    shiftDown = false
end

-- ======================================================================
print("Phase B: vault Shift watcher skips hidden cells and reuses one options table")
-- ======================================================================
do
    local ns = { UI = {} }
    local state = { vaultSlotProgressBindings = {}, vaultColumnBindings = {}, vaultColumnCellBindings = {} }
    local M = { state = state }
    ns.VaultButton = M
    ns.WarbandNexus = {}
    LoadFile("Modules/VaultButton_Data.lua", ns)
    M.RefreshEasyAccessHoverTooltip = function() end

    local optsSeen, formatCalls = {}, 0
    ns.VaultFormatCategoryColumn = function(_, _, opts)
        formatCalls = formatCalls + 1
        optsSeen[#optsSeen + 1] = opts
        return opts.shiftHeld and "SHIFT" or "NORMAL"
    end
    local paintOpts = {}
    M.PaintVaultTrackerColumnCells = function(group, opts)
        paintOpts[#paintOpts + 1] = { opts = opts, shift = opts.shiftHeld }
        group.painted = (group.painted or 0) + 1
    end

    local colA, colB, colHidden = NewFontString(true), NewFontString(true), NewFontString(false)
    local data = { slots = { {}, {}, {} }, category = "raid" }
    ns.UI_BindVaultColumnDisplay(colA, data)
    ns.UI_BindVaultColumnDisplay(colB, data)
    ns.UI_BindVaultColumnDisplay(colHidden, data)
    local anchorVisible, anchorHidden = NewFontString(true), NewFontString(false)
    local gVisible, gHidden = { data = data }, { data = data }
    state.vaultColumnCellBindings[anchorVisible] = gVisible
    state.vaultColumnCellBindings[anchorHidden] = gHidden

    local hiddenSets = colHidden.sets
    optsSeen = {}
    formatCalls = 0
    paintOpts = {}
    shiftDown = true
    Fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)
    check(colA.text == "SHIFT" and colB.text == "SHIFT", "visible vault columns show the Shift view")
    check(colHidden.sets == hiddenSets, "hidden vault column is not re-formatted on Shift", colHidden.sets - hiddenSets)
    check(formatCalls == 2, "Shift formats only the 2 visible columns", formatCalls)
    check((gHidden.painted or 0) == 0 and gVisible.painted == 1, "hidden tracker cell group is not repainted on Shift")
    check(#optsSeen >= 2 and optsSeen[1] == optsSeen[2], "one options table shared by every column of a refresh")
    check(paintOpts[1] and paintOpts[1].shift == true, "cell groups receive shiftHeld = true")

    -- Next paint of the hidden row re-binds it with the live state.
    colHidden.visible = true
    ns.UI_BindVaultColumnDisplay(colHidden, data)
    check(colHidden.text == "SHIFT", "hidden vault column is correct after the next paint")

    -- Display-mode toggle (ns.RefreshVaultShiftAwareDisplays) still refreshes everything.
    colHidden.visible = false
    local before = colHidden.sets
    shiftDown = false
    ns.RefreshVaultShiftAwareDisplays()
    check(colHidden.sets == before + 1 and colHidden.text == "NORMAL", "toggle refresh still reaches hidden columns")
end

-- ======================================================================
print("Phase C: achievement browse earned meta, scroll coalescing, class colour lookup")
-- ======================================================================
do
    local ns = { UI = { Factory = {} }, UI_LAYOUT = { PAGE_STACK = {} }, UI_SPACING = {} }
    local WN = {
        db = { global = { collectionsRecentObtained = {}, characters = {} }, profile = {} },
        RegisterMessage = function() end,
    }
    ns.WarbandNexus = WN
    ns.L = {}
    local achInfoCalls = 0
    GetAchievementInfo = function(id)
        achInfoCalls = achInfoCalls + 1
        -- id, name, points, completed, month, day, year, desc, flags, icon, reward, isGuild, wasEarnedByMe, earnedBy
        return id, "Ach", 10, true, 3, 4, 21, "", 0, 0, "", false, false, "Alt"
    end
    GetAchievementNumCriteria = function() return 0 end
    LoadFile("Modules/UI/CollectionsUI_Shared.lua", ns)
    local CUI = ns.CollectionsUI

    achInfoCalls = 0
    local d1, e1 = CUI.FormatAchievementEarnedRowMetaSplit(42)
    for _ = 1, 9 do CUI.FormatAchievementEarnedRowMetaSplit(42) end
    local d2, e2 = CUI.FormatAchievementEarnedRowMetaSplit(42)
    check(d1 ~= nil and e1 ~= nil and d1 == d2 and e1 == e2, "earned meta text is stable across paints")
    check(achInfoCalls <= 2, "10 paints of one row call GetAchievementInfo at most twice", achInfoCalls)

    local hasInvalidate = type(CUI.InvalidateAchievementEarnedMetaCache) == "function"
    check(hasInvalidate, "CollectionsUI exposes InvalidateAchievementEarnedMetaCache")
    if hasInvalidate then
        CUI.InvalidateAchievementEarnedMetaCache()
        achInfoCalls = 0
        CUI.FormatAchievementEarnedRowMetaSplit(42)
        check(achInfoCalls >= 1, "a new generation recomputes the meta")
    end

    -- Populate: starts a generation, and OnVerticalScroll coalesces to one repaint per frame.
    ns.UI_CreateCollapsibleHeader = function() return NewFrame() end
    ns.UI_RebindCollapsibleHeader = function() end
    ns.UI_COLORS = { textBright = { 1, 1, 1 } }
    local repaints = 0
    ns.VirtualListModule = {
        ReleaseVisibleRows = function() end,
        SetupVirtualList = function() end,
        RepaintVisible = function() repaints = repaints + 1 end,
    }
    ns.Constants = { EVENTS = {} }
    local invalidations = 0
    local realInvalidate = CUI.InvalidateAchievementEarnedMetaCache
    CUI.InvalidateAchievementEarnedMetaCache = function()
        invalidations = invalidations + 1
        if realInvalidate then realInvalidate() end
    end
    LoadFile("Modules/UI/AchievementBrowseVirtualList.lua", ns)

    local scrollFrame = NewFrame()
    local scrollChild = NewFrame()
    scrollChild.GetChildren = function() end
    scrollChild.GetRegions = function() end
    scrollChild.GetParent = function() return nil end
    local st = { achievementListScrollFrame = scrollFrame }
    ns.UI_AchievementBrowse_Populate({
        state = st,
        scrollChild = scrollChild,
        listWidth = 300,
        categoryData = {},
        rootCategories = {},
        acquireRow = function() return NewFrame() end,
        releaseRowFrame = function() end,
    })
    RunTimers()
    check(invalidations == 1, "populate starts a new earned-meta generation", invalidations)
    local onScroll = scrollFrame._scripts.OnVerticalScroll
    check(type(onScroll) == "function", "list scroll handler installed")
    if onScroll then
        repaints = 0
        for _ = 1, 5 do onScroll(scrollFrame, 10) end
        local sync = repaints
        RunTimers()
        check(sync == 0 and repaints == 1, "5 scroll events in one frame -> 1 repaint",
            string.format("sync %d, after frame %d", sync, repaints))
        onScroll(scrollFrame, 20)
        RunTimers()
        check(repaints == 2, "the next frame's scroll repaints again", repaints)
    end
end

-- SharedWidgets is too large to load under the stub: run the shipped class-colour block verbatim
-- (from its cache table, when present, through the end of UI_GetClassColorHexForWarbandCharacter).
do
    local src = ReadFile("Modules/UI/SharedWidgets.lua")
    local fnStart = src:find("function ns.UI_GetClassColorHexForWarbandCharacter", 1, true)
    local cacheStart = src:find("ns.UI_WarbandClassTokenCache = ", 1, true)
    local startAt = (cacheStart and cacheStart < fnStart) and cacheStart or fnStart
    local fnEnd = select(2, src:find("\nend\n", fnStart, true))
    local block = src:sub(startAt, fnEnd)
    local prelude = "local ns, WarbandNexus, E, issecretvalue, ResolveClassFileTokenFromCharData, GetClassColorHexForSurface = ...\n"
    local chunk = assert(loadstring(prelude .. block, "@SharedWidgets.lua:class-colour"))

    local listeners = {}
    local WN = { db = { global = { characters = {} } } }
    WN.RegisterMessage = function(_, msg, fn) listeners[msg] = fn end
    local chars = WN.db.global.characters
    for i = 1, 30 do
        chars["Player-1-" .. i] = { name = "Char" .. i, classFile = (i % 2 == 0) and "MAGE" or "PRIEST" }
    end
    local ns = {}
    chunk(ns, WN, { CHARACTER_UPDATED = "WN_CHARACTER_UPDATED", CHARACTER_TRACKING_CHANGED = "WN_CHARACTER_TRACKING_CHANGED" },
        function() return false end,
        function(cd) return cd.classFile end,
        function(token) return token == "MAGE" and "3fc7eb" or "ffffff" end)

    local realLower = string.lower
    local lowerCalls = 0
    string.lower = function(s) lowerCalls = lowerCalls + 1; return realLower(s) end
    local okAll = true
    for i = 1, 20 do
        local want = (i % 2 == 0) and "|cff3fc7eb" or "|cffffffff"
        if ns.UI_GetClassColorHexForWarbandCharacter("char" .. i) ~= want then okAll = false end
    end
    local missing = ns.UI_GetClassColorHexForWarbandCharacter("Nobody")
    string.lower = realLower
    check(okAll, "class colour resolves case-insensitively")
    check(missing == "|cffaaaaaa", "unknown name -> default grey")
    check(lowerCalls <= 30 + 21, "21 lookups over 30 characters lowercase each name once", lowerCalls)

    -- Roster change: a renamed character is picked up after the roster message.
    chars["Player-1-1"].name = "Renamed"
    if listeners["WN_CHARACTER_UPDATED"] then listeners["WN_CHARACTER_UPDATED"]("WN_CHARACTER_UPDATED") end
    check(ns.UI_GetClassColorHexForWarbandCharacter("renamed") == "|cffffffff", "roster message refreshes the name map")
    -- A replaced characters table (profile reset / import) also invalidates.
    WN.db.global.characters = { x = { name = "Fresh", classFile = "MAGE" } }
    check(ns.UI_GetClassColorHexForWarbandCharacter("fresh") == "|cff3fc7eb", "replaced roster table is picked up")
end

-- ======================================================================
print("Phase D: GameTooltip hover path")
-- ======================================================================
local postCalls = {}
local showHooks = {}
local tooltipNameCalls = 0
local tooltipLines = {}
local gtWidgetReads = 0
local gtRaw = {
    NumLines = function() return #tooltipLines end,
    GetName = function() tooltipNameCalls = tooltipNameCalls + 1; return "GameTooltip" end,
    AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    AddDoubleLine = function(_, l) tooltipLines[#tooltipLines + 1] = l end,
    IsShown = function() return true end,
    GetOwner = function() return nil end,
}
GameTooltip = setmetatable({}, {
    __index = function(_, k)
        if k == "widgetSetID" or k == "widgetContainer" then
            gtWidgetReads = gtWidgetReads + 1
            return nil
        end
        return gtRaw[k]
    end,
})
hooksecurefunc = function(target, method, fn)
    if target == GameTooltip and method == "Show" then showHooks[#showHooks + 1] = fn end
end
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
        postCalls[kind] = postCalls[kind] or {}
        table.insert(postCalls[kind], fn)
    end,
}
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Currency = 5, MinimapMouseover = 9, Quest = 23, Object = 33 } }

local keystoneCalls, mountFromItemCalls, petByItemCalls, mapInfoCalls, goldHexCalls, storageKeyCalls = 0, 0, 0, 0, 0, 0
local bestMapID = 2444
C_Item = { GetItemInfo = function() return nil end, IsItemKeystoneByID = function() return false end }
C_MountJournal = {
    GetMountFromItem = function(itemID) mountFromItemCalls = mountFromItemCalls + 1; return itemID == 777 and 55 or nil end,
    GetMountInfoByID = function() return nil end,
}
C_PetJournal = {
    GetPetInfoByItemID = function() petByItemCalls = petByItemCalls + 1; return nil end,
    GetNumCollectedInfo = function() return 0 end,
}
C_Map = {
    GetBestMapForUnit = function() return bestMapID end,
    GetMapInfo = function(id)
        mapInfoCalls = mapInfoCalls + 1
        local parents = { [2444] = 2405, [2405] = 2537, [2413] = 2537 }
        return { mapID = id, parentMapID = parents[id] }
    end,
}
C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
PlayerHasToy = function() return false end
UnitGUID = function(unit) if unit == "mouseover" then return "Creature-0-1-2-3-99999-0000" end end
UnitClassification = function() return "normal" end
UnitCanAttack = function() return true end
UnitIsDead = function() return false end
UnitReaction = function() return 2 end
IsInInstance = function() return false end
RAID_CLASS_COLORS = {}

local nsT = { UI = {} }
local gold = { 1, 0.82, 0 }
local WNT = {
    db = { global = {}, profile = { showTooltipItemCount = true, showTooltipItemID = true }, char = {} },
    planCache = { itemIDs = {}, mountIDs = {}, petIDs = {} },
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    SendMessage = function() end,
    Debug = function() end,
    IsItemPlanned = function(self, _, id) return self.planCache.itemIDs[id] == true end,
    IsMountPlanned = function(self, id) return self.planCache.mountIDs[id] == true end,
    IsPetPlanned = function(self, id) return self.planCache.petIDs[id] == true end,
    GetDetailedItemCountsFast = function() return nil end,
}
nsT.WarbandNexus = WNT
nsT.L = {}
nsT.Utilities = {
    IsKeystoneItemID = function() keystoneCalls = keystoneCalls + 1; return false end,
    IsModuleEnabled = function() return true end,
    GetCharacterStorageKey = function() storageKeyCalls = storageKeyCalls + 1; return "Player-1-A" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
}
nsT.UI_GetSemanticGoldColor = function() return gold[1], gold[2], gold[3] end
nsT.UI_GetSemanticGoldHex = function()
    goldHexCalls = goldHexCalls + 1
    return string.format("|cff%02x%02x%02x", gold[1] * 255, gold[2] * 255, gold[3] * 255)
end
nsT.CollectibleSourceDB = {
    npcs = {},
    containers = {},
    zones = { [2405] = { drops = { { itemID = 1, type = "mount" } } } },
}
LoadFile("Modules/Constants.lua", nsT)
LoadFile("Modules/TooltipService_GameTooltip.lua", nsT)
LoadFile("Modules/TooltipService.lua", nsT)
local TS = nsT.TooltipService
local GT = nsT.TooltipGameTooltip
TS.Debug = function() end
pcall(GT.InitializeGameTooltipHook, TS)
RunTimers()

do
    local itemPost = postCalls[Enum.TooltipDataType.Item] and postCalls[Enum.TooltipDataType.Item][1]
    check(type(itemPost) == "function", "item post-call registered")
    if itemPost then
        keystoneCalls, mountFromItemCalls, petByItemCalls, goldHexCalls = 0, 0, 0, 0
        local idTexts = {}
        for i = 1, 5 do
            tooltipLines = {}
            itemPost(GameTooltip, { id = 1234, dataInstanceID = 100 + i, type = Enum.TooltipDataType.Item })
            idTexts[i] = tooltipLines[#tooltipLines]
        end
        check(keystoneCalls == 5, "IsKeystoneItemID runs once per item hover", keystoneCalls .. " calls / 5 hovers")
        check(mountFromItemCalls == 0 and petByItemCalls == 0, "no mount/pet journal lookups without mount/pet plans",
            string.format("mount %d pet %d", mountFromItemCalls, petByItemCalls))
        check(idTexts[1] == "|cffffd100Item ID|r|cffffffff : 1234|r" and idTexts[5] == idTexts[1],
            "item ID footer text unchanged", idTexts[1])
        check(goldHexCalls <= 1, "item ID label built once across 5 hovers", goldHexCalls)

        -- Theme switch: the gold changes, the label follows.
        gold = { 0.5, 0.4, 0.1 }
        tooltipLines = {}
        itemPost(GameTooltip, { id = 1234, dataInstanceID = 200, type = Enum.TooltipDataType.Item })
        check(tooltipLines[#tooltipLines] == "|cff7f6619Item ID|r|cffffffff : 1234|r", "item ID label follows a theme change",
            tooltipLines[#tooltipLines])
        gold = { 1, 0.82, 0 }

        -- A mount plan exists: the lookup runs and the planned line still appears.
        WNT.planCache.mountIDs[55] = true
        tooltipLines = {}
        itemPost(GameTooltip, { id = 777, dataInstanceID = 300, type = Enum.TooltipDataType.Item })
        local plannedShown = false
        for i = 1, #tooltipLines do
            if tostring(tooltipLines[i]):find("(Planned)", 1, true) or tostring(tooltipLines[i]):find("PLANNED", 1, true) then
                plannedShown = true
            end
        end
        check(mountFromItemCalls >= 1 and plannedShown, "with a mount plan the planned line still shows")
        WNT.planCache.mountIDs[55] = nil
    end

    local unitPost = postCalls[Enum.TooltipDataType.Unit] and postCalls[Enum.TooltipDataType.Unit][1]
    check(type(unitPost) == "function", "unit post-call registered")
    if unitPost then
        mapInfoCalls = 0
        for i = 1, 4 do
            tooltipLines = {}
            unitPost(GameTooltip, { dataInstanceID = 500 + i, type = Enum.TooltipDataType.Unit })
        end
        check(mapInfoCalls == 1, "zone parent chain walked once for 4 hovers on one map", mapInfoCalls)
        bestMapID = 2413
        unitPost(GameTooltip, { dataInstanceID = 600, type = Enum.TooltipDataType.Unit })
        unitPost(GameTooltip, { dataInstanceID = 601, type = Enum.TooltipDataType.Unit })
        -- 2413 has no zone entry: two GetMapInfo calls (2413 -> 2537 -> root) on the first hover,
        -- none on the second (the miss is memoized too).
        check(mapInfoCalls == 3, "a new map walks its chain once, a miss is memoized", mapInfoCalls)
    end

    -- Concentration Show hook: with ProfessionsFrame closed it must not probe the tooltip.
    local concHook = showHooks[#showHooks]
    check(type(concHook) == "function", "concentration Show hook installed")
    if concHook then
        ProfessionsFrame = nil
        gtWidgetReads = 0
        concHook(GameTooltip)
        check(gtWidgetReads == 0, "closed ProfessionsFrame -> no widget probe on GameTooltip:Show", gtWidgetReads)

        ProfessionsFrame = { IsShown = function() return true end }
        tooltipLines = {}
        for i = 1, 12 do tooltipLines[i] = "line" .. i end
        _G.GameTooltipTextLeft1 = { GetText = function() return "Concentration" end }
        for i = 2, 12 do _G["GameTooltipTextLeft" .. i] = { GetText = function() return "line" .. i end } end
        tooltipNameCalls = 0
        concHook(GameTooltip)
        check(tooltipNameCalls <= 2, "marker scan over 12 lines does not rebuild the line name per line", tooltipNameCalls)
        ProfessionsFrame = nil
    end
end

-- ======================================================================
print("Phase E: TooltipService placement / currency rows, TooltipFactory line entries")
-- ======================================================================
do
    -- Placement: record every SetPoint the scorer makes, compare to the pre-change order.
    local points = {}
    local frame = {
        ClearAllPoints = function() end,
        SetPoint = function(_, p, _, rp, x, y) points[#points + 1] = p .. ">" .. rp .. ":" .. x .. "," .. y end,
        GetLeft = function() return 100 end, GetRight = function() return 300 end,
        GetTop = function() return 900 end, GetBottom = function() return 700 end,
    }
    local anchorLeft = {
        GetLeft = function() return 200 end, GetRight = function() return 400 end,
        GetTop = function() return 800 end, GetBottom = function() return 780 end,
    }
    local anchorRight = {
        GetLeft = function() return 1500 end, GetRight = function() return 1700 end,
        GetTop = function() return 800 end, GetBottom = function() return 780 end,
    }
    local R = { "LEFT>RIGHT:8,0", "TOPLEFT>TOPRIGHT:8,0", "BOTTOMLEFT>BOTTOMRIGHT:8,0" }
    local L = { "RIGHT>LEFT:-8,0", "TOPRIGHT>TOPLEFT:-8,0", "BOTTOMRIGHT>BOTTOMLEFT:-8,0" }
    local A = { "BOTTOMLEFT>TOPLEFT:0,8", "BOTTOMRIGHT>TOPRIGHT:0,8" }
    local B = { "TOPLEFT>BOTTOMLEFT:0,-8", "TOPRIGHT>BOTTOMRIGHT:0,-8" }
    local function cat(...)
        local out = {}
        for gi = 1, select("#", ...) do
            local g = select(gi, ...)
            for i = 1, #g do out[#out + 1] = g[i] end
        end
        return table.concat(out, " ")
    end
    local function scored(anchor, pref)
        points = {}
        TS:ApplyBestTooltipPlacement(frame, anchor, pref, 1920, 1080)
        local n = #points
        -- Overlap / clamp re-points come after the scoring pass; keep the scoring pass only.
        local expectedN = 10
        local out = {}
        for i = 1, math.min(n, expectedN) do out[i] = points[i] end
        return table.concat(out, " ")
    end
    check(scored(anchorLeft, "ANCHOR_TOP") == cat(A, B, R, L), "ANCHOR_TOP candidate order unchanged")
    check(scored(anchorLeft, "ANCHOR_BOTTOM") == cat(B, A, R, L), "ANCHOR_BOTTOM candidate order unchanged")
    check(scored(anchorLeft, "ANCHOR_LEFT") == cat(L, R, A, B), "ANCHOR_LEFT candidate order unchanged")
    check(scored(anchorRight, "ANCHOR_RIGHT") == cat(R, L, A, B), "ANCHOR_RIGHT candidate order unchanged")
    check(scored(anchorLeft, "ANCHOR_AUTO") == cat(R, L, A, B), "ANCHOR_AUTO on the left half opens right first")
    check(scored(anchorRight, nil) == cat(L, R, A, B), "ANCHOR_AUTO on the right half opens left first")

    frame.SetPoint = function() end
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for _ = 1, 200 do TS:ApplyBestTooltipPlacement(frame, anchorLeft, "ANCHOR_AUTO", 1920, 1080) end
    local allocKB = collectgarbage("count") - kb0
    collectgarbage("restart")
    check(allocKB < 20, "200 placements allocate < 20 KB (candidates not rebuilt per Show)", string.format("%.1f KB", allocKB))

    -- Currency breakdown: current character key resolved once, not per row.
    local chars = {}
    for i = 1, 6 do chars[i] = { name = "C" .. i, realm = "R", key = "Player-1-" .. i, isTracked = true } end
    WNT.GetCurrenciesForUI = function() return { [3008] = { chars = {} } } end
    WNT.GetAllCharacters = function() return chars end
    WNT.GetCurrencyData = function() return { quantity = 0 } end
    nsT.UI_GetCharKey = function(c) return c.key end
    storageKeyCalls = 0
    local sink = NewFrame()
    pcall(TS.RenderCurrencyCharacterBreakdown, TS, sink, 3008)
    check(storageKeyCalls == 1, "currency breakdown over 6 characters resolves the current key once", storageKeyCalls)
end

do
    -- TooltipFactory: Add* entries are pooled per frame, so a rebuilt tooltip allocates no entry tables.
    local nsF = { UI = {} }
    local fontStrings = 0
    nsF.FontManager = {
        CreateFontString = function()
            fontStrings = fontStrings + 1
            local fs = NewFrame()
            fs.GetStringWidth = function() return 50 end
            fs.GetStringHeight = function() return 12 end
            fs.GetHeight = function() return 12 end
            fs.GetWidth = function() return 50 end
            return fs
        end,
    }
    nsF.UI_SetTextColorRole = function() end
    LoadFile("Modules/UI/TooltipFactory.lua", nsF)
    local ok, tip = pcall(nsF.UI.TooltipFactory.CreateTooltipFrame, nsF.UI.TooltipFactory)
    check(ok and tip ~= nil, "tooltip frame created", not ok and tip or nil)
    if ok and tip then
        tip.LayoutLines = function() end   -- layout is not under test here
        local function build()
            tip:Clear()
            for i = 1, 20 do tip:AddLine("line " .. i, 1, 1, 1) end
            for i = 1, 10 do tip:AddDoubleLine("l" .. i, "r" .. i, 1, 1, 1, 1, 1, 1) end
            tip:AddSpacer(4)
        end
        build()
        build()
        local first = tip.allLines[1]
        check(#tip.allLines == 31 and first.type == "single" and first.wrap == false, "line entries carry type / wrap")
        check(tip.allLines[31].type == "spacer" and tip.allLines[31].height == 4, "spacer entry carries height")
        check(tip.allLines[21].type == "double" and tip.allLines[21].balanced == false, "double entry carries balanced")
        local reused = tip.allLines[1]
        build()
        check(tip.allLines[1] ~= nil and (tip.allLines[1] == reused or tip.allLines[31] == reused
            or tip.allLines[16] == reused or tip.allLines[2] == reused or tip.allLines[30] == reused),
            "entries from the previous build are reused")
        collectgarbage("collect")
        collectgarbage("stop")
        local kb0 = collectgarbage("count")
        for _ = 1, 50 do build() end
        local allocKB = collectgarbage("count") - kb0
        collectgarbage("restart")
        check(allocKB < 60, "50 rebuilds of a 31-line tooltip allocate < 60 KB", string.format("%.1f KB", allocKB))
    end
end

-- Review follow-ups (2026-10-22, static): transient negatives must not stick.
do
    local function src(rel)
        local fh = assert(io.open((os.getenv("WN_ROOT") or ".") .. "/" .. rel, "rb"))
        local t = fh:read("*a"):gsub("\r\n", "\n")
        fh:close()
        return t
    end
    local shared = src("Modules/UI/CollectionsUI_Shared.lua")
    check(shared:find("(GetTime() - at) < 5", 1, true) ~= nil,
        "a 'not earned' achievement meta result expires after a few seconds")
    check(src("Modules/Utilities.lua"):find("local PET_NAME_RETRY_SEC = 1", 1, true) ~= nil,
        "a failed caged-pet name lookup is retried within a second")
    check(src("Modules/UI/PlansUI_WeeklyProgress.lua"):find("SetVertexColor(0.27, 1, 0.27, 1)", 1, true) ~= nil,
        "the pooled completed-quest status icon sets its alpha explicitly")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
