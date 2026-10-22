#!/usr/bin/env lua
--[[
    Regression test: UI-layer persisted writes go through service delegates (SOA: View never writes
    db.global / db.char itself).

    - PlansManager:BackfillPlanField: draw paths (Plans Tracker, plan cards) wrote mountID / speciesID /
      source straight onto db.global.plans rows, so the plan indexes (planCache.mountIDs,
      _plansByCollectibleKey) missed the new id until the next full rebuild. The delegate writes the
      field, rebuilds the indexes for ids, and sends no PLANS_UPDATED (it runs inside a draw).
    - Custom plan storage (SaveCustomPlan / GetCustomPlans / CompleteCustomPlan) lives in PlansManager;
      the dead RemoveCustomPlan is gone (RemovePlan already removes custom rows).
    - DataService:TouchCharacterLastSeen replaces the Characters tab's inline lastSeen writes.
    - WarbandBankDepositService per-character setters replace the popups' db.char writes.
    - WindowManager floating-window state replaces the windows' db.global.<key> writes.
    - Static: the listed UI files no longer assign into db.global / db.char (reads allowed).

    Loads the shipped files under wow_stub.lua (one fresh ns per service).
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
end

local function LoadInto(ns, rel)
    local src = assert(ReadFile(rel), "missing file: " .. rel)
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function NewAddon(dbShape)
    local sent = {}
    local printed = {}
    local addon = {
        db = dbShape,
        SendMessage = function(_, msg, payload) sent[#sent + 1] = { msg = msg, payload = payload } end,
        RegisterMessage = function() end,
        RegisterEvent = function() end,
        Print = function(_, msg) printed[#printed + 1] = msg end,
    }
    local ns = {
        WarbandNexus = addon,
        DebugPrint = function() end,
        DebugVerbosePrint = function() end,
        IsDebugModeEnabled = function() return false end,
    }
    return ns, addon, sent, printed
end

CopyTable = CopyTable or function(t)
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    return copy(t)
end

-- ---------------------------------------------------------------------------
print("Phase 1: PlansManager:BackfillPlanField (indexes refreshed, no message)")
local pns, WN, sent, printed = NewAddon({ global = { plans = {}, customPlans = {}, characters = {} }, profile = {}, char = {} })
pns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
pns.Utilities = {
    GetCharacterKey = function() return "Alpha-Kazzak" end,
    GetCharacterStorageKey = function() return "Player-3674-0000000A" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
    IsModuleEnabled = function() return true end,
}
LoadInto(pns, "Locales/enUS.lua")
pns.L = pns.LOCALES and pns.LOCALES.enUS
LoadInto(pns, "Modules/Constants.lua")
LoadInto(pns, "Modules/PlansManager.lua")
local E = pns.Constants.EVENTS

local mountPlan = { id = 11, type = "mount", itemID = 9001, name = "Drake" }
local petPlan = { id = 12, type = "pet", name = "Whelp" }
WN.db.global.plans = { mountPlan, petPlan }
WN:InitializePlanCache()
local backfill = type(WN.BackfillPlanField) == "function" and WN.BackfillPlanField or nil
assert_eq(backfill ~= nil, true, "WarbandNexus:BackfillPlanField exists")
if backfill then
    local before = #sent
    assert_eq(WN:BackfillPlanField(mountPlan, "mountID", 1801), true, "missing mountID written")
    assert_eq(mountPlan.mountID, 1801, "row carries mountID 1801")
    assert_eq(WN:IsMountPlanned(1801), true, "planCache.mountIDs sees the new id at once")
    local pc = WN._plansByCollectibleKey
    assert_eq(pc and pc.mount and pc.mount[1801] and pc.mount[1801][1], mountPlan, "_plansByCollectibleKey.mount indexes the row")
    assert_eq(WN:BackfillPlanField(mountPlan, "mountID", 2222), false, "present mountID is not overwritten")
    assert_eq(mountPlan.mountID, 1801, "row keeps mountID 1801")
    assert_eq(WN:BackfillPlanField(petPlan, "speciesID", 4321), true, "missing speciesID written")
    assert_eq(WN:IsPetPlanned(4321), true, "planCache.petIDs sees the new species")
    assert_eq(WN:BackfillPlanField(petPlan, "speciesID", 0), false, "speciesID 0 ignored")
    assert_eq(WN:BackfillPlanField(mountPlan, "source", "Drop: Boss"), true, "source written")
    assert_eq(mountPlan.source, "Drop: Boss", "row carries the resolved source")
    assert_eq(WN:BackfillPlanField(mountPlan, "source", "Drop: Boss"), false, "same source is a no-op")
    local secret = stub.MarkSecret("secret source")
    assert_eq(WN:BackfillPlanField(mountPlan, "source", secret), false, "secret value ignored")
    assert_eq(mountPlan.source, "Drop: Boss", "row keeps its source after a secret value")
    assert_eq(#sent, before, "no WN_* message sent from the draw-path delegate")
    stub.ClearSecrets()
end

print("Phase 2: Plans Tracker identity resolve goes through the delegate")
do
    local src = ReadFile("Modules/UI/PlansTrackerWindow.lua") or ""
    local fnSrc = src:match("\n(local function EnsureTrackerPlanIdentity%(plan%).-\nend)\n")
    assert_eq(fnSrc ~= nil, true, "EnsureTrackerPlanIdentity found in PlansTrackerWindow.lua")
    if fnSrc then
        local chunk = assert(loadstring("local WarbandNexus = ...\nlocal issecretvalue = issecretvalue\n"
            .. fnSrc .. "\nreturn EnsureTrackerPlanIdentity", "@EnsureTrackerPlanIdentity"))
        local EnsureTrackerPlanIdentity = chunk(WN)
        C_MountJournal = C_MountJournal or {}
        local prevGet = C_MountJournal.GetMountFromItem
        C_MountJournal.GetMountFromItem = function(itemID) if itemID == 7777 then return 1955 end end
        local drawPlan = { id = 13, type = "mount", itemID = 7777, name = "Proto" }
        WN.db.global.plans[#WN.db.global.plans + 1] = drawPlan
        WN:RefreshPlanCache()
        local before = #sent
        EnsureTrackerPlanIdentity(drawPlan)
        assert_eq(drawPlan.mountID, 1955, "tracker resolves mountID from the item")
        assert_eq(WN:IsMountPlanned(1955), true, "tracker-resolved mountID reaches planCache without a rebuild")
        assert_eq(#sent, before, "tracker identity resolve sends no message")

        -- Journal does not know the item: the itemID must not be stored as a mountID / planned id.
        local unknown = { id = 14, type = "mount", itemID = 8888, name = "Unknown reins" }
        WN.db.global.plans[#WN.db.global.plans + 1] = unknown
        WN:RefreshPlanCache()
        EnsureTrackerPlanIdentity(unknown)
        assert_eq(unknown.mountID, nil, "unresolved mount keeps mountID empty (no itemID fallback)")
        assert_eq(WN:IsMountPlanned(8888), false, "itemID does not enter the planned-mount set")
        local pet = { id = 15, type = "pet", petID = 4242, name = "Pet without species" }
        EnsureTrackerPlanIdentity(pet)
        assert_eq(pet.speciesID, nil, "petID is not written as speciesID")
        C_MountJournal.GetMountFromItem = prevGet
    end
end

-- ---------------------------------------------------------------------------
print("Phase 3: custom plan storage lives in PlansManager")
do
    assert_eq(type(WN.SaveCustomPlan), "function", "SaveCustomPlan defined by PlansManager.lua")
    assert_eq(type(WN.CompleteCustomPlan), "function", "CompleteCustomPlan defined by PlansManager.lua")
    assert_eq(type(WN.GetCustomPlans), "function", "GetCustomPlans defined by PlansManager.lua")
    if type(WN.SaveCustomPlan) == "function" and type(WN.CompleteCustomPlan) == "function" then
        pns.PLAN_UI_COLORS = { completed = "|cTESTGRN" }
        pns.UI_FormatTextNumbers = function(s) return s end
        WN.db.global.customPlans = nil
        WN:SaveCustomPlan("Goal", "desc", "daily", 2, false)
        local row = WN.db.global.customPlans and WN.db.global.customPlans[1]
        assert_eq(row and row.type, "custom", "custom plan row stored")
        assert_eq(row and row.resetCycle and row.resetCycle.totalCycles, 2, "finite cycle count stored")
        local last = sent[#sent]
        assert_eq(last and last.msg, E.PLANS_UPDATED, "save sends WN_PLANS_UPDATED")
        assert_eq(last and last.payload and last.payload.action, "custom_created", "save payload action custom_created")
        assert_eq(last and last.payload and last.payload.planID, row and row.id, "save payload carries planID")
        assert_eq(#WN:GetCustomPlans(), 1, "GetCustomPlans returns the stored row")
        assert_eq(WN:CompleteCustomPlan(row.id), true, "CompleteCustomPlan finds the row")
        assert_eq(row.completed, true, "row marked completed")
        assert_eq(type(row.resetCycle.completedAt), "number", "recurring completion time stamped")
        last = sent[#sent]
        assert_eq(last and last.payload and last.payload.action, "completed", "complete payload action completed")
        assert_eq(printed[#printed] and printed[#printed]:find("Goal", 1, true) ~= nil
            and printed[#printed]:find("completed", 1, true) ~= nil, true, "completion chat line names the plan")
        assert_eq(WN.RemoveCustomPlan, nil, "dead RemoveCustomPlan removed")
        assert_eq(WN:RemovePlan(row.id), true, "RemovePlan removes the custom row")
        assert_eq(#WN:GetCustomPlans(), 0, "custom list empty after RemovePlan")
    end
end

-- ---------------------------------------------------------------------------
print("Phase 4: DataService:TouchCharacterLastSeen")
do
    local KEY = "Player-1-00000001"
    GetNormalizedRealmName = GetNormalizedRealmName or function() return "TestRealm" end
    GetMoney = GetMoney or function() return 0 end
    local dns, DWN, dsent = NewAddon({ global = { characters = {} }, profile = {}, char = {} })
    dns.CharacterService = {
        IsCharacterTracked = function() return true end,
        ResolveSubsidiaryCharacterKey = function() return KEY end,
        ResolveCharactersTableKey = function() return KEY end,
    }
    LoadInto(dns, "Modules/Constants.lua")
    LoadInto(dns, "Modules/Utilities.lua")
    dns.Utilities.GetCharacterStorageKey = function() return KEY end
    LoadInto(dns, "Modules/DataService_RosterHelpers.lua")
    LoadInto(dns, "Modules/DataService.lua")
    DWN.db.global.characters[KEY] = { name = "Tester", realm = "TestRealm", guid = KEY, isTracked = true,
        level = 90, lastSeen = 100 }
    assert_eq(type(DWN.TouchCharacterLastSeen), "function", "TouchCharacterLastSeen defined by DataService.lua")
    if type(DWN.TouchCharacterLastSeen) == "function" then
        DWN:GetAllCharacters()
        local cache = dns.DataServiceRoster and dns.DataServiceRoster.cache
        local sigBefore = cache and cache.sig
        local before = #dsent
        assert_eq(DWN:TouchCharacterLastSeen(KEY), true, "existing row stamped")
        assert_eq(DWN.db.global.characters[KEY].lastSeen, time(), "lastSeen = time()")
        assert_eq(DWN:TouchCharacterLastSeen("Player-1-FFFFFFFF"), false, "missing row not stamped")
        assert_eq(DWN.db.global.characters["Player-1-FFFFFFFF"], nil, "missing row not created")
        assert_eq(#dsent, before, "no message sent")
        DWN:GetAllCharacters()
        assert_eq(cache and cache.sig ~= sigBefore, true, "roster signature follows the new lastSeen")
    end
end

-- ---------------------------------------------------------------------------
print("Phase 5: WarbandBankDepositService per-character setters")
do
    local bns, BWN = NewAddon({ global = {}, profile = {}, char = {} })
    LoadInto(bns, "Modules/Constants.lua")
    LoadInto(bns, "Modules/WarbandBankDepositService.lua")
    assert_eq(type(BWN.SetReagentDepositPerCharacter), "function", "SetReagentDepositPerCharacter defined")
    assert_eq(type(BWN.SetGoldManagementPerCharacter), "function", "SetGoldManagementPerCharacter defined")
    if type(BWN.SetReagentDepositPerCharacter) == "function" and type(BWN.SetGoldManagementPerCharacter) == "function" then
        local prof = { enabled = true, destination = "warband", categories = { herbs = true } }
        BWN.db.profile.reagentDeposit = prof
        local s = BWN:SetReagentDepositPerCharacter(true, prof)
        assert_eq(s, BWN.db.char.reagentDeposit, "per-char reagent returns db.char table")
        assert_eq(s ~= prof and s.categories ~= prof.categories, true, "reagent seed deep-copied")
        assert_eq(s.perCharacter == true and s.destination == "warband" and s.categories.herbs == true, true, "reagent copy values + perCharacter")
        s.destination = "reagent"
        local back = BWN:SetReagentDepositPerCharacter(false)
        assert_eq(back, prof, "switch back returns profile reagent table")
        assert_eq(BWN.db.char.reagentDeposit.perCharacter, false, "char reagent kept, flag off")
        local again = BWN:SetReagentDepositPerCharacter(true, prof)
        assert_eq(again.destination, "reagent", "re-enable keeps the character's own values")

        local gprof = { enabled = true, mode = "deposit", targetAmount = 5000 }
        BWN.db.profile.goldManagement = gprof
        local g = BWN:SetGoldManagementPerCharacter(true, gprof)
        assert_eq(g, BWN.db.char.goldManagement, "per-char gold returns db.char table")
        assert_eq(g.perCharacter == true and g.enabled == true and g.mode == "deposit" and g.targetAmount == 5000, true,
            "gold copy enabled / mode / targetAmount + perCharacter")
        assert_eq(BWN:SetGoldManagementPerCharacter(false), gprof, "switch back returns profile gold table")
        assert_eq(BWN.db.char.goldManagement.perCharacter, false, "char gold kept, flag off")
    end
end

-- ---------------------------------------------------------------------------
print("Phase 6: WindowManager floating window state")
do
    local wns, WWN = NewAddon({ global = {}, profile = {}, char = {} })
    local prevGlobal = rawget(_G, "WarbandNexus")
    _G.WarbandNexus = WWN
    LoadInto(wns, "Modules/Constants.lua")
    LoadInto(wns, "Modules/WindowManager.lua")
    local WM = wns.WindowManager
    assert_eq(type(WM.GetFloatingWindowState), "function", "GetFloatingWindowState defined")
    if type(WM.GetFloatingWindowState) == "function" then
        local defaults = { point = "CENTER", x = 0, width = 380, collapsed = false, opacity = 1.0 }
        local st = WM:GetFloatingWindowState("plansTracker", defaults, { opacity = 1.0 })
        assert_eq(st, WWN.db.global.plansTracker, "state created under db.global.plansTracker")
        assert_eq(st ~= defaults and st.width == 380 and st.collapsed == false, true, "created from a copy of the defaults")
        st.opacity = nil
        st.width = nil
        WM:GetFloatingWindowState("plansTracker", defaults, { opacity = 1.0 })
        assert_eq(st.opacity, 1.0, "backfill fills a missing opacity")
        assert_eq(st.width, nil, "fields outside backfill stay unset (no invented defaults)")
        local frame = {
            GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", 12, 34 end,
            GetWidth = function() return 400 end,
            GetHeight = function() return 500 end,
        }
        WM:SaveFloatingWindowGeometry("plansTracker", frame, false)
        assert_eq(st.point == "TOPLEFT" and st.relativePoint == "BOTTOMLEFT" and st.x == 12 and st.y == 34, true, "anchor saved")
        assert_eq(st.height, nil, "size skipped when includeSize is false")
        WM:SaveFloatingWindowGeometry("plansTracker", frame, true)
        assert_eq(st.width == 400 and st.height == 500, true, "size saved when includeSize is true")
        WM:SetFloatingWindowField("plansTracker", "collapsed", true)
        assert_eq(st.collapsed, true, "SetFloatingWindowField writes the field")
        WM:SetFloatingWindowField("recipeCompanion", "x", 5)
        assert_eq(WWN.db.global.recipeCompanion, nil, "setter does not create an unknown window table")
    end
    _G.WarbandNexus = prevGlobal
end

-- ---------------------------------------------------------------------------
print("Phase 7: static -- listed UI files no longer write db.global / db.char")
local UI_FILES = {
    "Modules/UI/PlansTrackerWindow.lua", "Modules/UI/PlanCardFactory.lua", "Modules/UI/CharactersUI.lua",
    "Modules/UI/CharactersUI_Dialogs.lua", "Modules/UI/PlansUI_Dialogs.lua", "Modules/UI/GoldManagementPopup.lua",
    "Modules/UI/WarbandBankDepositPopup.lua", "Modules/UI/ProfessionInfoWindow.lua", "Modules/UI/RecipeCompanionWindow.lua",
}
local WRITE_PATTERNS = {
    { "db%.global[%w_%.%[%]\"']*%s*=[^=]", "assigns into db.global" },
    { "db%.char[%w_%.%[%]\"']*%s*=[^=]", "assigns into db.char" },
    { "table%.insert%s*%([^,]*db%.global", "table.insert into db.global" },
    { "table%.remove%s*%([^,]*db%.global", "table.remove from db.global" },
    { "%f[%w_]plan%.source%s*=[^=]", "writes plan.source on a stored row" },
    { "%f[%w_]plan%.mountID%s*=[^=]", "writes plan.mountID on a stored row" },
    { "%f[%w_]plan%.speciesID%s*=[^=]", "writes plan.speciesID on a stored row" },
    { "%.lastSeen%s*=[^=]", "writes a roster lastSeen" },
}
local STORE_REF_PATTERNS = {   -- window files: writes through the GetDB() reference
    { "%f[%w_]t?db%.[%w_]+%s*=[^=]", "writes through the db.global window table" },
    { "%f[%w_]d%.opacity%s*=[^=]", "writes opacity through the db.global window table" },
}
local WINDOW_FILES = {
    ["Modules/UI/PlansTrackerWindow.lua"] = true,
    ["Modules/UI/ProfessionInfoWindow.lua"] = true,
    ["Modules/UI/RecipeCompanionWindow.lua"] = true,
}
for i = 1, #UI_FILES do
    local rel = UI_FILES[i]
    local src = ReadFile(rel)
    local hits = {}
    if src then
        local n = 0
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for p = 1, #WRITE_PATTERNS do
                if code:find(WRITE_PATTERNS[p][1]) then hits[#hits + 1] = n .. " " .. WRITE_PATTERNS[p][2] end
            end
            if WINDOW_FILES[rel] then
                for p = 1, #STORE_REF_PATTERNS do
                    if code:find(STORE_REF_PATTERNS[p][1]) then hits[#hits + 1] = n .. " " .. STORE_REF_PATTERNS[p][2] end
                end
            end
        end
    end
    assert_eq(src ~= nil and #hits == 0, true, rel .. " has no persisted writes" .. (#hits > 0 and (" (line " .. table.concat(hits, "; line ") .. ")") or ""))
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("UI service delegates suite failed with " .. failed .. " failure(s).")
end
print("UI service delegates suite: ALL TESTS PASSED.")
